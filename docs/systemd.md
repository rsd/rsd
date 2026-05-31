# Systemd Service Management

## Overview

The `systemd` module provides target-aware primitives for managing systemd
units on both local and remote hosts. It replaces ad-hoc `systemctl` calls
with validated, structured operations.

Two components:

- **Library** (`lib/systemd.lib`) — Bash functions for programmatic use by
  recipes and other libraries. Namespace: `rsd::l::systemd::`.
- **Command** (`command/systemd`) — CLI entry point for interactive use.
  Namespace: `rsd::c::systemd::`.

Both route through `target.lib`, so all operations work transparently
on local and remote targets.

## Scope: System vs User

All actions support a `--user` flag to operate on user-scoped units:

| | System (default) | User (`--user`) |
|--|------------------|-----------------|
| **Unit directory** | `/etc/systemd/system/` | `~/.config/systemd/user/` |
| **Mutations** | via `sudo` | no sudo |
| **Default WantedBy** | `multi-user.target` | `default.target` |
| **Timer WantedBy** | `timers.target` | `timers.target` |
| **Journal flag** | `-u` | `--user-unit` |
| **systemctl flag** | *(none)* | `--user` |

```bash
# System-level (default) — requires sudo
rsd @prod systemd create myapp.service --exec "/usr/bin/myapp"

# User-level — no sudo needed
rsd systemd --user create myapp.service --exec "/usr/bin/myapp"
```

## Quick Reference

```bash
# Query
rsd systemd status nginx.service
rsd systemd logs nginx.service -n 100
rsd @prod systemd status nginx.service

# User-scope query
rsd systemd --user status myapp.service

# Lifecycle
rsd systemd enable nginx.service
rsd systemd --user enable myapp.service
rsd systemd disable nginx.service

# Create a long-running service
rsd systemd create myapp.service \
    --exec "/usr/bin/node /var/www/app/server.js" \
    --run-as www-data \
    --workdir /var/www/app \
    --description "My Node.js Application"

# Create a scheduled job (paired timer+service in one command)
rsd @prod systemd create renew-tailscale-cert.timer \
    --exec "/usr/local/sbin/renew-tailscale-nginx-cert" \
    --type oneshot \
    --on-calendar daily \
    --persistent \
    --after "tailscaled.service,network-online.target" \
    --wants "network-online.target" \
    --description "Renew Tailscale HTTPS certificate for Nginx"

# Remove timer + companion service
rsd @prod systemd remove renew-tailscale-cert.timer

# Remove timer only, keep the companion service
rsd @prod systemd remove renew-tailscale-cert.timer --timer-only
```

## Actions

### `status <unit>`

Pretty-prints the unit's active state, boot status, PID, memory, and
unit file path using structured IO formatting.

### `logs <unit> [-n N] [--since "time"]`

Fetches journal entries. Always uses `--no-pager` and ISO timestamps.
Default: last 50 lines.

```bash
rsd systemd logs nginx.service -n 100
rsd systemd logs nginx.service --since "1 hour ago"
```

### `create <unit> --exec <cmd> [options]`

Generates and installs a unit file. System scope writes to
`/etc/systemd/system/`, user scope writes to `~/.config/systemd/user/`.
Auto-detects `.service` vs `.timer` from the unit name suffix.

After writing: runs `daemon-reload`, then enables and starts the unit
(unless `--no-enable` or `--no-start` is specified).

#### Paired Timer+Service Workflow

When creating a `.timer` with `--exec`, **both** the companion
`.service` and the `.timer` are created automatically in one command:

```bash
rsd systemd create renew-cert.timer \
    --exec "/usr/local/bin/renew" \
    --type oneshot \
    --on-calendar daily \
    --persistent
```

This creates:
1. `renew-cert.service` — installed but **not enabled** (timer triggers it)
2. `renew-cert.timer` — installed and **enabled** (the scheduler)

Options are split between the two units:

| Goes to `.service` | Goes to `.timer` | Goes to both |
|---------------------|-------------------|--------------|
| `--exec`, `--type`, `--run-as`, `--group`, `--workdir`, `--restart`, `--restart-sec`, `--env`, `--exec-stop`, `--pid-file` | `--on-calendar`, `--on-boot-sec`, `--on-unit-active-sec`, `--persistent` | `--description`, `--after`, `--wants`, `--requires`, `--before` |

To create a timer without auto-creating the service (if it already exists),
omit `--exec`:

```bash
rsd systemd create renew-cert.timer --on-calendar daily --persistent
```

#### Service Options

| Option | Description | Default |
|--------|-------------|---------|
| `--exec <cmd>` | ExecStart command | *(required for .service, optional for .timer)* |
| `--type <type>` | simple, forking, oneshot, notify | simple (.service) / oneshot (.timer) |
| `--description <text>` | Unit description | auto-generated |
| `--run-as <user>` | Run as user (User= directive) | root |
| `--group <group>` | Run as group | inherited |
| `--workdir <path>` | Working directory | none |
| `--restart <policy>` | no, on-failure, always, on-abnormal | per-type |
| `--restart-sec <N>` | Restart delay seconds | 5 |
| `--env <K=V,K=V>` | Environment variables | none |
| `--exec-stop <cmd>` | ExecStop command | none |
| `--pid-file <path>` | PID file (forking type) | none |

#### Dependency Options (comma-separated)

| Option | Directive | Default |
|--------|-----------|---------|
| `--after <units>` | After= | network.target (except oneshot) |
| `--wants <units>` | Wants= | none |
| `--requires <units>` | Requires= | none |
| `--before <units>` | Before= | none |
| `--wanted-by <targets>` | WantedBy= | multi-user.target (system) / default.target (user) |

Multiple units are comma-separated:

```bash
--after "tailscaled.service,network-online.target"
```

#### Timer Options (when unit name ends in `.timer`)

| Option | Directive |
|--------|-----------|
| `--on-calendar <expr>` | OnCalendar= |
| `--on-boot-sec <time>` | OnBootSec= |
| `--on-unit-active-sec <time>` | OnUnitActiveSec= |
| `--timer-unit <service>` | Unit= (companion service) |
| `--persistent` | Persistent=true |

#### Flags

| Flag | Effect |
|------|--------|
| `--user` | User scope (`~/.config/systemd/user/`) |
| `--no-enable` | Don't enable or start after creation |
| `--no-start` | Enable at boot but don't start now |

### `enable <unit>`

Enables the unit at boot and starts it now (`systemctl enable --now`).

### `disable <unit>`

Disables the unit from starting at boot.

### `remove <unit> [--timer-only]`

Stops the unit, disables it, deletes the file from the unit directory,
and runs `daemon-reload`.

When removing a `.timer`, the companion `.service` is also removed
automatically. Use `--timer-only` to keep the companion service.

```bash
# Remove both timer and its companion service
rsd systemd remove renew-cert.timer

# Remove only the timer, keep the service
rsd systemd remove renew-cert.timer --timer-only
```

## Smart Defaults by Service Type

| Type | Default After= | Default Restart= | Default WantedBy= |
|------|---------------|------------------|-------------------|
| simple | network.target | on-failure | multi-user.target / default.target |
| forking | network.target | on-failure | multi-user.target / default.target |
| notify | network.target | on-failure | multi-user.target / default.target |
| oneshot | *(none)* | no | multi-user.target / default.target |

Specifying `--after` **replaces** the default — it does not append.

## Unit Name Validation

All unit names are validated against the
[freedesktop.org systemd naming specification](https://www.freedesktop.org/software/systemd/man/latest/systemd.unit.html):

- Must end with a valid suffix (`.service`, `.timer`, `.target`, etc.)
- Prefix allows: `[a-zA-Z0-9:._\-\\]`
- Cannot start with a dot
- Maximum 255 characters
- Template units (`name@.service`) not yet supported

Dependency references (`--after`, `--wants`, etc.) are also validated.

## Library API

For programmatic use in recipes and other libraries:

```bash
# Load the library
[[ "$RSD_SYSTEMD_LIB" != "1" ]] && source "$(rsd::get_libdir_file lib/systemd.lib)"

# Set scope (default: system)
RSD_SYSTEMD_SCOPE="user"   # or "system"

# Query
rsd::l::systemd::is_active "nginx.service"
rsd::l::systemd::is_enabled "nginx.service"

# Lifecycle (sudo for system scope, plain for user scope)
rsd::l::systemd::restart "nginx.service"
rsd::l::systemd::enable "nginx.service"

# Create
declare -A params=(
    [exec]="/usr/bin/node /var/www/app/server.js"
    [type]="simple"
    [user]="www-data"
    [workdir]="/var/www/app"
)
local content
content=$(rsd::l::systemd::generate_service params "myapp.service")
rsd::l::systemd::install_unit "myapp.service" "$content"

# Remove
rsd::l::systemd::remove_unit "myapp.service"

# Logs
rsd::l::systemd::logs "nginx.service" 100 "1 hour ago"
```

## Roadmap

### Template Units

Template units (`myapp@.service`) support parameterized instances:

```
laravel-worker@queue1.service
laravel-worker@queue2.service
```

Each instance shares the same unit file but receives its identifier
via `%i` / `%I` specifiers. Planned features:

- Template creation with `%i` substitution in ExecStart
- Instance management (start/stop specific instances)
- Wildcard operations (`systemctl enable myapp@*.service`)
