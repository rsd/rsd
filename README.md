# Rapid Script Developer (RSD) Meta-Framework

RSD is a structural meta-framework and execution engine for shell scripting. It wraps automated provisioning setups, dynamic remote orchestrations, and secure credentials management into a **single, zero-dependency executable boundary**. 

Instead of cluttering systems with loose script files, RSD structures automation suites around structured, lazy-loaded command files (`command/`) and shared idempotent libraries (`lib/`).

## Quick-Start Example: Provisioning a Zsh Environment

RSD simplifies complex installations (like fully deploying and configuring a secure Zsh environment with themes, plugins, and dependencies) down to a single terminal call.

To simulate or execute the `zsh_dev_setup` provisioning recipe:

```bash
# 1. Preview the compiled checklist (Necessity Checks & Task Dry-Run Simulation)
rsd recipe run zsh_dev_setup --dry-run --verbose

# 2. Provision locally (Installs Zsh, configures default shells via Sudo Askpass, and deploys Oh-My-Zsh)
rsd recipe run zsh_dev_setup

# 3. Or provision a remote server target natively over SSH with one call
rsd @server1 recipe run zsh_dev_setup
```

*(Under the hood, RSD dynamically maps the host distribution's package manager, extracts target SSH/Sudo credentials securely from a GPG-encrypted KeePassXC database, and applies modifications idempotently so subsequent executions automatically skip completed steps).*

---

## Objective

RSD exists to eliminate repetitive infrastructure work. Whether provisioning a database on a remote server, deploying a development environment, or restoring a backup — if a task has been done once, RSD should be able to do it again with a single command and zero user guesswork.

Simple tasks are bundled as **commands** (with sub-command actions). Complex, multi-step operations are structured as **recipes** — declarative, idempotent scripts that the framework compiles, executes, and recovers from automatically.

## Philosophy

RSD is built on one core belief: **the user should provide the *what*, never the *how***. If the framework installed PostgreSQL on a server, it should know how to connect to it. If a backup was created with a specific compression method, the restore should detect it automatically. The user's job is to say "restore this database." RSD's job is to figure out everything else.

This means RSD operates under a principle of **maximum self-sufficiency**: probe the environment, detect the configuration, adapt to what's available, and only ask the user when there's a genuine ambiguity that cannot be resolved programmatically. Expert users can always override any auto-detected value — but the default path should require nothing beyond the essential intent.

## Design Principles

### 1. Security First

Every operation assumes adversarial conditions. Temporary files use unpredictable paths (`mktemp`, never hardcoded `/tmp/foo`). Existing files are backed up before modification. Passwords and credentials never appear in command-line arguments, process lists, or debug output — they are piped via stdin or file descriptors. File permissions are restrictive by default (`0700` for temp, `0600` for credentials). Cleanup is guaranteed, including on failure paths.

### 2. Namespace Preservation

RSD must be invisible to the host environment. All functions use the `rsd::` prefix with scoping tags (`::c::` for commands, `::l::` for libraries, `::r::` for recipes). All globals use the `RSD_` prefix. Shell extension primitives use the `bash::` prefix. This strict isolation ensures RSD never collides with user scripts, sourced tools, or system utilities — and makes it safe to `source` external bash tools into the same process.

### 3. Environment Detection — Never Assume

RSD never assumes the state of the environment it operates in. Before calling a binary, verify it exists. Before connecting to a service, probe for the correct method. Before writing a file, check if the path is writable. The environment is always discovered, never presumed.

The sole exception: explicit configuration. If a config file declares "this host uses PostgreSQL on port 5433," trust it and skip the probe. The user has deliberately asserted the environment's state. Configuration overrides detection; detection overrides assumption.

### 4. Remote Transparency

A task must work identically whether the target is local or remote. The user writes `@host` and the framework handles everything else. Two modes support this:

- **Delegated** (RSD installed remotely) — Best case. The framework ensures version parity via bootstrap checks and delegates tasks to the remote binary. This allows recipes, libraries, and scripts to stay synchronized.
- **Direct** (No remote RSD) — For servers we don't own, thin clients, and containers. Each command executes individually through the transport layer (SSH, LXC, Docker). Slower, but universally compatible.

Remote cascading (host → VPN → SSH → LXC → Docker) follows the same rules at every hop.

### 5. Local and Remote Filesystems

Files and directories can be local or remote, distinguished by the `@host:path` syntax:

| Form | Example | Resolution |
| :--- | :--- | :--- |
| Relative local | `backups/` | Against `$(pwd)` |
| Absolute local | `/tmp/backups/` | As-is |
| Relative remote | `@bi:backups/` | Against remote `$HOME` |
| Absolute remote | `@bi:/tmp/backups/` | As-is |

RSD maximizes remote operations and minimizes file transfers. If a file is remote and the operation can run remotely, execute remotely — don't copy gigabytes just to read a header. Transfer only when the operation genuinely requires the file on the other side, and always to a secure temp location with guaranteed cleanup.

### 6. User's Soft Ignorance

The user wants a task done. It is RSD's job to figure out how. The framework must never burden the user with questions it can answer itself.

- **Minimize required arguments** — Only the intent is mandatory (`--db-name`). Everything else (connection method, compression algorithm, auth strategy) should be auto-detected with sensible defaults.
- **Expert escape hatch** — Every auto-detected value can be overridden by explicit CLI flags or configuration files. The effortless path is the default; the expert path is always available.
- **Helpful failure** — When something fails, explain what went wrong *and* what to try next. Never exit with just a code.

### 7. Recipe Independence *(planned)*

Recipes should be able to live outside the RSD repository. A recipe file with an RSD shebang should be executable independently — downloadable, shareable, and runnable without a full RSD checkout. The recipe would still access all RSD libraries and target abstraction, but wouldn't need to be physically bundled in `lib/recipe/`.

---

## Getting Started: GPG, Vault, and Remote Host Initialization

Follow these standard steps to configure your GPG identity, initialize the GPG-hardened KeePassXC credential vault, define a remote server alias, and bootstrap the RSD framework remotely:

### Step 1: Export/Ensure Your GPG Recipient Key ID
RSD utilizes GPG asymmetric encryption to secure your KeePassXC database master password. You can use an existing GPG key from your keyring or generate a dedicated one for RSD:
```bash
# Option A: Use an existing GPG key — identify your Key ID or email
gpg --list-secret-keys --keyid-format=long

# Option B: Generate a dedicated RSD-only key (ed25519 + cv25519)
rsd gpg create-key

# Write your chosen GPG Key ID to your user configuration
rsd config set RSD_GPG_USER_ID "your.email@example.com"
```

**GPG Agent Session Caching**: After you enter your GPG passphrase once, `gpg-agent` caches the decrypted key in memory. Subsequent vault lookups are silent — no re-prompting — until the cache expires (`default-cache-ttl`, 10 minutes of inactivity by default). To manually flush the cache: `gpg-connect-agent reloadagent /bye`. See the [GPG Agent & Session Caching](docs/kpx.md#2-gpg-agent--session-caching) section for timeout tuning and full details.

### Step 2: Initialize the KeePassXC Vault (`kpx`)
Generate a new, secure database (`vault.kdbx`) and a GPG-encrypted master key (`vault.key.gpg`) targeting your GPG Recipient ID:
```bash
# 1. Initialize the vault
rsd kpx init

# 2. Store credentials for your target remote server and local sudo
rsd kpx add "RemoteHosts/server1" "admin" "YourSSHPasswordHere"
rsd kpx add "Sudo/localhost" "" "YourLocalSudoPassword"
```

### Step 3: Configure and Identify Your Remote Host (`@server1`)
Define the remote server connection alias in your local `remote.ini` file and run platform discovery to cache its properties locally:
```bash
# 1. Define the connection URI for the @server1 alias
rsd config set remote.hosts.server1 "ssh://admin@192.168.1.100:22"

# 2. Run remote platform discovery and save server1's specifications to hosts.ini
rsd @server1 host save
```

### Step 4: Bootstrap and Install RSD on the Remote Target
Stream the local RSD framework to your remote server to install it automatically:
```bash
# 1. Stream the RSD code and execute remote installation
rsd @server1 remote install

# 2. Append the remote binary path (~/.local/bin) to the target's interactive shell PATH
rsd @server1 remote setup-path
```

Now you are fully configured to run any automated setup, recipe, or library function locally or remotely:
```bash
# Run the Zsh developer environment provisioning recipe remotely on @server1
rsd @server1 recipe run zsh/dev_setup
```

---

## 1. Core Architectural Pillars

* **Zero-Dependency CLI Routing**: Maps top-level commands directly to cohesive physical files (e.g. `command/gpg`), lazy-sourcing bash functions inside on-demand. See the [RSD Core Specification & Architecture](docs/rsd_specification.md) for execution cycles and routing maps.
* **GPG-Hardened Credentials Vault**: Integrates dynamically with `keepassxc-cli`. Vault master keys are encrypted asymmetric GPG payloads, decoded session keys reside strictly in kernel memory, and passwords are piped via secure standard input streams (no command-line arg exposures). See the [KeePassXC Subsystem Reference](docs/kpx.md) for the complete security model and GPG key integrations.
* **Multi-Hop Remote Target Delegation**: Executes operations seamlessly over standard target pathways (configured in `config/remote.ini` or user `hosts.ini`). Automatically builds nested intermediate hops (e.g. `@gateway,target,sudo://root`) and escapes command lines recursively. Details on configuration resolutions can be found in the [Configuration Management Subsystem](docs/config.md).
* **Declarative & Idempotent Recipes**: A recursive provisioning task engine. Compiles nested prerequisite steps into flat, dry-runnable chronological execution stacks that support reverse chronological backward rollbacks. Read the [Recipes Provisioning Guide](docs/recipes.md) for advanced composition and rollback guidelines.

---

## 2. Framework Installation

### A. Local Workstation Setup

#### Local User-Space / Global Installation
You can install the runner script using raw streaming curl or via a cloned tree:

```bash
# Streaming Bootstrap Installation
curl -sL https://raw.githubusercontent.com/rsd/rsd/main/rsd | bash -s -- --install ~/.local/bin

# Cloned Tree Installation
git clone https://github.com/rsd/rsd.git
cd rsd
./rsd --install ~/.local/bin
```

#### Running Tests Native vs Docker
RSD features E2E integration and unit test suites written using **Bats-core** (test runner) and **Kcov** (coverage):

* **Native Setup (For Arch Linux / Local Users)**:
  ```bash
  sudo pacman -S bats kcov
  bats tests/
  ```
* **Containerized Setup (For Team / CI Standardized Environments)**:
  ```bash
  docker build -t rsd-test-runner -f Dockerfile.test .
  docker run --rm -v "$(pwd):/workspace" -w /workspace rsd-test-runner bats tests/
  ```

For deep-dives into GPG sandbox mocking, isolated directory configurations, and coverage tracing, see the [RSD Test Execution & Integration Guide](docs/testing_guide.md).

---

## 3. Remote Bootstrapping & Setup

RSD features a **self-healing remote bootstrap protocol**. You do *not* need to pre-install RSD or configure files manually on target machines. Details on the standalone discovery and execution lifecycle can be found in the [Host Identification Guide](docs/host.md) and [RSD Core Specification](docs/rsd_specification.md).

### Step 1: Pre-Flight Dependency Scan
Verify if the target machine contains the minimal binaries required for streaming bootstrapping (`bash`, `tar`, `openssl`, etc.):
```bash
rsd @server1 remote check
```
*(If the host target has a custom entry defined in `config/remote.ini` or `hosts.ini`, specify the alias directly, e.g. `@server1`)*

### Step 2: Stream-Bootstrap RSD Remotely
Streams the local RSD codebase as an archive payload over SSH, extracts it to a temporary `/tmp` sandbox, and triggers a user-space installation atomically on the target:
```bash
rsd @server1 remote install
```
*(If you want ~/.local/bin to be created automatically if missing, pass the `-y` flag)*

### Step 3: Append PATH to Remote Profiles
Appends the default installation path (`~/.local/bin`) to the target machine's remote `~/.bashrc`:
```bash
rsd @server1 remote setup-path
```

---

## 4. Key CLI Commands & Core Uses

RSD options follow a strict positional boundary: **Global Options** (e.g. `--debug`) go before the command, and **Command Specific Options** go after.
```bash
rsd [global options] COMMAND [sub-command/action] [arguments]
```

### A. Host Platform Identification
Query operating system, architecture, release version, and package installer schemas locally or remotely. See the [Host Identification Guide](docs/host.md) for kernel schemas and distro family aggregation details.
```bash
# Display local platform properties
rsd host identify

# Scans a remote host target (zero dependencies required on the remote target)
rsd @server1 host identify

# Scan remote target and save its profile into the LOCAL hosts.ini config
rsd @server1 host save
```

### B. KeePassXC Hardened Vault
Configure and interact with a GPG-secured credential database. See the [KeePassXC Subsystem Reference](docs/kpx.md) for setup details, key rotation, and the library API reference.
```bash
# Setup the encrypted database, GPG keys, and backups
rsd kpx init

# Safely store an SSH or database password entry
rsd kpx add "RemoteHosts/server1" "admin" "SuperSecurePass123"
rsd kpx add "Sudo/localhost" "" "MyLocalSudoPassword"

# Output decrypted credential to shell output (uses gpg-agent credentials)
rsd kpx show "RemoteHosts/server1"
```

### C. Idempotent Task & Recipe Provisioning
Declaratively compile and execute multi-stage configurations declared in `.recipe` files (stored under `lib/recipe/`). Read the [Recipes Provisioning Guide](docs/recipes.md) for task cycles, composition, prerequisites, and testing details.

#### 1. Composable Task Architecture
* **Flat Stack Compilation**: Nested sub-recipes included via `rsd::recipe::include_recipe "zsh_core"` compile recursively into a single, flat chronological stack of tasks. This avoids context thread splits and enables dry-runs across all dependencies.
* **Double-Inclusion Guards**: Active registry checking ensures prerequisite recipes included multiple times in a tree are compiled **exactly once**.
* **Idempotency Lifecycles**: Every task implements a strict necessity guard:
  1. *Pre-Check*: Checks if state is already met. Succeeded checks skip the task instantly.
  2. *Apply*: Applies modifications.
  3. *Post-Check*: Assures modifications succeeded before continuing.

#### 2. Fault Tolerance & Recovery Modes
If a task application or post-check verification fails, execution halts and handles the issue based on configured recovery keys:
* **`forward` (Default)**: Halts execution immediately, keeping completed changes. Once host environmental issues are fixed, re-running skips completed tasks and resumes exactly where it failed.
* **`rollback`**: Triggers LIFO backward recovery. Chronologically completed tasks are popped and their `--rollback` cleanup payloads executed in reverse.
* **`ignore`**: Prints a diagnostic warning but proceeds silently (used for optional components).

#### 3. Recipe CLI Commands & Execution
Manage and execute recipes locally or on remote targets using the following actions:

##### List Available Recipes
Discovers and lists all compiled `.recipe` basenames located in library search paths:
```bash
rsd recipe list
```

##### Review Recipe Task Checklist
Inspects a specific recipe, outputting its compiled flat task stack, callbacks, and recovery strategies without running modifications:
```bash
rsd recipe help zsh_dev_setup
```

##### Run Recipe Provisioning
Executes recipe configurations. Supports target aliases (e.g. `@server1`), dry-run simulations, and verbose logs:
```bash
# Run a dry-run checklist simulation locally (verifies necessity and loops)
rsd recipe run zsh_dev_setup --dry-run --verbose

# Run a dry-run checklist simulation remotely
rsd @server1 recipe run zsh_dev_setup -n -v

# Execute recipe provisioning locally
rsd recipe run zsh_dev_setup

# Execute recipe provisioning remotely over SSH target pathways
rsd @server1 recipe run zsh_dev_setup
```

---

## 5. Technical Documentation Links

* [RSD Core Specification & Architecture](docs/rsd_specification.md) — System lifecycle, exit code tables, and dynamic routing conventions.
* [RSD Test Execution & Integration Guide](docs/testing_guide.md) — Sandbox boundaries, bats layouts, and coverage measurement.
* [Recipes Provisioning Guide](docs/recipes.md) — Task cycles, composition patterns, and rollback mechanisms.
* [KeePassXC Subsystem Reference](docs/kpx.md) — Vault decryption, credential piping, and GPG keyring bindings.
* [Configuration Management Subsystem](docs/config.md) — Environment variables, .ini structures, and directory priorities.
* [Host Identification Guide](docs/host.md) — Kernel schemas, family aggregation, and remote standalone discovery.
