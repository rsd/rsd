# RSD Core System Specification & Architecture

This document serves as the formal architectural specification and system documentation for the **RSD** (Rapid Script Developer / Runner) command-line framework. It outlines the core responsibilities, filesystem layout boundaries, execution cycles, and design parameters of the system.

---

## 1. Executive System Overview

RSD is a structural meta-framework for shell scripting that provides a **single zero-dependency executable boundary** to route, load, and manage custom automation suites. Rather than polluting environments with countless individual scripts, RSD structures script suites around two primary concepts:

```
                  ┌──────────────────────────────────────────────┐
                  │                 CLI INPUT                    │
                  │        rsd [Global Flags] CMD ACTION         │
                  └──────────────────────┬───────────────────────┘
                                         │
                                         ▼
                  ┌──────────────────────────────────────────────┐
                  │          Command File Resolution             │
                  │      Locates & Sources command/CMD           │
                  └──────────────────────┬───────────────────────┘
                                         │
                                         ▼
                  ┌──────────────────────────────────────────────┐
                  │         Function Execution Routing           │
                  │    Invokes rsd::c::CMD::ACTION() in shell    │
                  └──────────────────────────────────────────────┘
```

1. **Commands as Files**: Core domains map to cohesive physical files under the `command/` directory (e.g. `command/gpg`, `command/kpx`). Sourcing a command file lazy-loads its scope on-demand.
2. **Sub-commands (Actions) as Functions**: Specific operational routines are declared as structured Bash functions inside those files (e.g., `rsd::c::gpg::check`).

---

## 2. The 9 Core Responsibilities

The `rsd` executable is responsible for orchestrating the following nine distinct system operations:

### 2.1 Dynamic Command & Sub-command Routing
* **Lazy Sourcing**: Dynamically matches, resolves, and loads only the specific command module matching the CLI call.
* **Namespace Resolution**: Dispatches parameters to sub-command (action) functions matching the `rsd::c::<command>::<action>` namespace.

### 2.2 System & Command Argument Parsing
* **Global Options**: Parses wrapper-specific configurations (e.g., `--debug`, `--lib-dir`, `--config-dir`, `--no-local`).
* **Dynamic Action Parameters**: Populates separate, scoped associative arrays (`RSD_ARGS` for wrapper parameters, and `RSD_COMMAND_ARGS` for sub-command arguments) leveraging safe name referencing (`declare -n`).

### 2.3 On-Demand Utility Library Loading
* **Core Libraries Sourcing**: Sources low-level extensions (`lib/bash_extensions.lib`, `lib/rsd.lib`) and domain helper wrappers (`lib/gpg.lib`, `lib/kpx.lib`) only when triggered by matching execution paths.

### 2.4 Precedence-Ordered Location Resolution
* **The Search Hierarchy**: Resolves locations for configs, commands, and libraries across a strict, prioritized path hierarchy:
  1. CLI Override Parameters (`--lib-dir`, `--config-dir`)
  2. Local Tree/Development paths (`$RSD_RUN_DIR`)
  3. User Space overrides (`$HOME/.config/rsd`, `$HOME/.local/share/rsd`)
  4. System Space defaults (`/etc/rsd`, `/usr/share/rsd`)
  5. Current Working Directory (`$(pwd)`)

### 2.5 Standalone Self-Bootstrapping & Installation
* **Single-File Bootstrap**: Enables a user to download a single, raw `rsd` wrapper and install the entire multi-file framework structure by executing:
  ```bash
  rsd --install PATH
  ```
* **Privilege Escalation**: Handles secure directory creations (`mktemp`), Git cloning, and permission verifications, dynamically executing `sudo` elevations via subshell parameters when writing to protected directories (like `/usr/local/bin`).

### 2.6 Transparent Workspace Version Auto-Swapping
* **Worktree Alignment**: Compares the version of the globally executing PATH bin against any executable `rsd` located in the current working directory (`$(pwd)`).
* **Execution Handoff**: If the local copy is newer, the wrapper automatically re-routes the active parameter array (`$@`) to the local script and terminates, maintaining version consistency across Git repositories.

### 2.7 Autocompletion Bridge & Dry Evaluation
* **Bridge Actions**: Serves as the dynamic backend state machine for system-level autocompletions (supporting tab completions for commands, sub-commands, and options).
* **Dry Routing**: Runs the command path in a dry-evaluation context (`--completion` mode) to validate configuration maps and parameters without executing any script side-effects.

### 2.8 Shell Execution Fallback (Pass-Through)
* **Delegation Mode**: If a command is not registered but `--pass-thru` is enabled, RSD acts as a transparent proxy layer, forwarding the unparsed parameter array directly to the native shell execution thread (`rsd::passthru`).

### 2.9 Environment Protection & Requirements Gatekeeping
* **Syntax Guard**: Parses system versions on startup to enforce compatibility rules (e.g. `BASH_VERSINFO` check), exiting cleanly before sourcing components if the host processor is incompatible.
* **Namespace Isolation**: Uses isolated prefixes (`rsd::` and `RSD_`) to guarantee that functions executed inside the caller shell do not pollute the user's environment.

---

## 3. Code Conventions, Scoping, and Idempotency Protections

To guarantee runtime stability, avoid symbol collisions, and minimize sourcing overhead, RSD enforces strict defensive programming guidelines for libraries and command modules.

### 3.1 Framework Presence Protection (Re-execution Guard)
Every library file (`lib/*.lib`) must enforce strict bootstrap validation at its very first lines of code to prevent accidental direct shell execution:
```bash
if [[ ! -v RSD_ON || $RSD_ON -ne 1 ]]; then
    echo "This is a RSD library file. It should not be executed directly."
    echo "Please call 'rsd' to use it."
    exit 12
fi
```
This re-execution guard guarantees that library files cannot be run as standalone binaries (e.g., `bash lib/gpg.lib`) in an un-sandboxed global scope. Sourcing is blocked unless the parent `rsd` framework entry point has properly initialized the environment.

### 3.2 Double-Sourcing Prevention (Idempotency Guards)
To minimize CPU overhead and prevent function re-definition issues, all subsystem libraries set a global loaded flag (e.g., `RSD_LIB=1`, `RSD_NET_LIB=1`, `RSD_GPG_LIB=1`) upon successful sourcing.
Command files and other libraries utilize **short-circuit guard evaluations** before sourcing files:
```bash
[[ "$RSD_SUDO_LIB" != "1" ]] && source "$RSD_BASE/lib/sudo.lib"
```
This keeps sourcing fully idempotent, preventing redundant filesystem read operations and ensuring static variables are not cleared or re-assigned.

### 3.3 Dynamic Namespace Scoping Conventions
RSD relies strictly on namespace separation using specific identifiers (`::c::` and `::l::`) to avoid namespace contamination inside the caller process:
* **Subsystem Libraries (`::l::`)**: All library functions are prefixed using the `rsd::l::<library_name>::` convention (e.g. `rsd::l::gpg::get_keys`, `rsd::l::kpx::check`). The `::l::` designation uniquely identifies shared, low-level modules.
* **Command Modules (`::c::`)**: Sourced sub-commands and actions are prefixed using the `rsd::c::<command_name>::` convention (e.g. `rsd::c::gpg::check`, `rsd::c::gpg::init`). The `::c::` designation maps directly to command actions executed via CLI.
* **Global Variables**: Global variables driving the shell wrapper are named in uppercase with an `RSD_` prefix (e.g. `RSD_DEBUG`, `RSD_VERSION`). Scoped configurations fetched from `.ini` maps are strictly confined under `R::INI::<command>` namespaces.

---

## 4. Directory and File Boundaries

RSD maintains a strict distinction between shared libraries, dynamic commands, and configurations:

| Directory | Type | Responsibility | Sourcing Hook |
| :--- | :--- | :--- | :--- |
| **`lib/`** | Static Subsystem Libraries | Domain-specific helpers, mathematical modules, GPG/Vault wrappers, and language extensions. | Sourced inside libraries using `rsd::source_lib_or_die`. |
| **`command/`** | Executable Command Scripts | Core domain entry files representing top-level CLI arguments. | Sourced by the wrapper engine using `rsd::load_command_file`. |
| **`config/`** | Settings Files | Global and script-specific configuration overrides (`.conf`, `.ini`). | Evaluated by the config manager using `rsd::config::get_file`. |

---

## 5. Standard Lifecycle of an RSD Call

The following sequence details how RSD routes and executes an action:

```
 ┌──────────────┐
 │ 1. Bootstrap │ ──► Verifies BASH >= 4.3 and initializes path variables
 └──────┬───────┘
        ▼
 ┌──────────────┐
 │   2. Parse   │ ──► Extracts global flags & command/action parameters
 └──────┬───────┘
        ▼
 ┌──────────────┐
 │  3. Handoff  │ ──► Checks pwd version; delegates to local copy if newer
 └──────┬───────┘
        ▼
 ┌──────────────┐
 │  4. Source   │ ──► Sources lib/rsd.lib, lib/bash_extensions.lib, and lib/config.lib
 └──────┬───────┘
        ▼
 ┌──────────────┐
 │   5. Route   │ ──► Sources command/<command> and checks for function target
 └──────┬───────┘
        ▼
 ┌──────────────┐
 │  6. Execute  │ ──► Invokes target function; exits with status or passes to shell
 └──────────────┘
```
