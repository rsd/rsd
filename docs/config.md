# RSD Configuration Management Subsystem

The Configuration Management Subsystem provides a robust, atomic, and safe interface for managing framework configurations. It allows developers and users to read, write, and inspect configuration parameters across the entire suite of RSD command modules and helper libraries directly from the command line.

---

## 1. Core Architecture & Formats

RSD supports two primary configuration types to balance power and safety:

### A. Global Variables (`.conf` Files)
* **File Name**: `rsd.conf`
* **Format**: Standard Bash script syntax containing key-value assignments (e.g., `RSD_GPG_USER_ID="raul@nostromo"`).
* **Execution**: Sourced directly by the framework at boot.
* **Usage**: Ideal for framework-wide parameters (e.g., `RSD_DEBUG`, `RSD_GPG_USER_ID`, `RSD_CONFIG_DIR`).

### B. Modular Scope Settings (`.ini` Files)
* **File Name**: `<module>.ini` (e.g., `remote.ini`)
* **Format**: Standard section-based INI structure.
* **Execution**: Safely parsed into a global associative array prefixed with `R_INI_<module>`, e.g., `R_INI_remote["section.key"]`.
* **Usage**: Best for structured module configurations (e.g., remote hosts, connection profiles).

---

## 2. Directory Resolution & Priority

RSD resolves config folders using a strict priority queue (`RSD_CONFIGLIB_SEARCH_PATH`). When running the `set` command, RSD writes directly to the user-space overrides folder to ensure user alterations do not contaminate system-wide defaults.

```
       [ HIGH PRIORITY ]
       
    1. CLI Override Options          (--config-dir, -c)
    2. Primary Custom Path           ($RSD_CONFIG_DIR)
    3. Workspace / Working Tree      ($(pwd)/config/, $RSD_RUN_DIR/config/)
    4. User Space Configs            ($HOME/.config/rsd/, $HOME/.rsd/)
    5. System Defaults               (/etc/rsd/, /usr/local/etc/rsd/)
    
       [ LOW PRIORITY ]
```

---

## 3. CLI Command Reference

Execute the `config` command module to inspect and alter settings.

### A. Show Help Layout
Displays registration description and sub-commands:
```bash
./rsd config help
```

### B. Retrieve Configuration (`get`)
Gets a resolved global or parsed module setting:
```bash
# Retrieve a global .conf variable from the active environment
./rsd config get RSD_GPG_USER_ID

# Retrieve a section parameter from a module .ini file
./rsd config get remote.host1.user
```
* **Exit Codes**: Returns `0` on success, `2` on key format error, and `10` if the key is not defined.

### C. Update/Write Configuration (`set`)
Saves or replaces a configuration parameter. Key formats automatically govern the target file:
```bash
# Writes to user-space override rsd.conf file
./rsd config set RSD_GPG_USER_ID "tester@nostromo"

# Writes to user-space override remote.ini file under [host1] section
./rsd config set remote.host1.port "2222"
```
* **Key Format Rules**:
  * Global keys must be in uppercase and prefixed with `RSD_`.
  * Modular keys must follow `module.section.key` notation.
* **Transactional Integrity**: Employs atomic write-safety (`mktemp` and signal-safe `mv` swaps) to prevent partial write corruptions or silent config drops.

### D. List Configurations (`list`)
Dumps all active shell globals starting with `RSD_` along with all currently parsed module `.ini` parameters:
```bash
./rsd config list
```

---

## 4. Developer API & Static Helpers

For low-level shell integrations within command scripts or library wrappers, the following library function is available in `lib/config.lib`:

### `rsd::l::config::set_conf_value`
Atomically writes or replaces a key-value assignment in standard `.conf` files.

```bash
# Sourcing hook
[[ "$RSD_CONFIGLIB_VERSION" == "" ]] && $(rsd::source_lib_or_die lib/config.lib)

# Usage
rsd::l::config::set_conf_value "/path/to/rsd.conf" "RSD_GPG_USER_ID" "my_new_id"
```
* **Parameters**:
  * `$1` (string): Absolute file path.
  * `$2` (string): Key name.
  * `$3` (string): New value.
* **Safety Details**: Automatically escapes slashes, backslashes, and ampersands using sed before writing, protecting configuration values from breaking shell evaluations.
