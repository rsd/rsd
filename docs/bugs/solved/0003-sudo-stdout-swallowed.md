# BUG-0003: exec_sudo Stdout Swallowed in Command Substitution

**Fixed in**: v1.23.0
**Files**: `lib/recipe/letsencrypt/install.recipe`
**Symptoms**: `grep -rlF` via `exec_sudo` returns exit 0 (match found) but
the captured output is empty: `detected=""`.

## Root Cause

`rsd::l::target::exec_sudo ""` builds a sudo pipeline through the SSH
protocol handler:

```
ssh -t host sh -c 'echo password | sudo -S -p "" -u root -- grep -rlF domain /path/'
```

Three layers conspire to swallow stdout:

1. **SSH `-t` (PTY)**: Allocates a pseudo-terminal that **merges stdout and
   stderr into a single stream**. The grep output, sudo's stderr, and PTY
   control sequences all flow through the same channel.

2. **`sh -c` wrapper**: The sudo pipeline is compiled into a single `sh -c`
   string. The inner `grep` stdout goes through sudo, through `sh -c`, through
   the PTY — each layer can buffer, reorder, or inject control characters.

3. **`2> >(tee "$_stderr_cap" >&2)`**: In protocol.lib, stderr is captured via
   process substitution. With PTY stdout/stderr merged, the "stderr capture"
   may consume what was originally stdout.

The net result: `$()` captures an empty string (or PTY escape sequences that
`bash::trim` strips to empty), even though the remote command succeeded.

## Fix

**Don't use `exec_sudo` when sudo isn't needed.**

`/etc/nginx/sites-available/` and its files are `0644` (world-readable).
Reading them doesn't require root privileges:

```bash
# Before (broken):
detected=$(rsd::l::target::exec_sudo "" grep -rlF "$domain" /path/)

# After (works):
detected=$(rsd::l::target::exec grep -rlF "$domain" /path/)
```

## General Rule

**Use `exec_sudo` ONLY for operations that actually require root privileges**
(writing files, managing services, reading restricted paths). For read-only
operations on world-readable paths, use `exec` to avoid the PTY/sudo pipeline
complexity.

When `exec_sudo` stdout capture IS needed (e.g., reading a root-only file),
the output must be treated as potentially corrupted by PTY artifacts:
1. Strip `\r` characters (BUG-0002)
2. Strip ANSI escape sequences if present
3. Validate the output format before using it

## Regression Risk

- Changing file permissions to be more restrictive (e.g., 0640) would require
  reverting to `exec_sudo`, re-exposing this bug.
- New code that captures `exec_sudo` stdout in `$()` for path/value extraction
  without awareness of the PTY merging issue.
