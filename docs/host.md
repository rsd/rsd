# Host Identification Subsystem

The Host Identification Subsystem provides a robust, safe, and standard mechanism for discovering, grouping, and storing platform parameters. By abstracting kernel properties, system architectures, and distribution variations into standard schemas, RSD command modules and libraries can dynamically adapt their execution paths (e.g. mapping package installers).

---

## 1. Core Concepts & Schema

Platform metadata is collected using standard Unix commands (e.g., `uname`) and safe parsing of `/etc/os-release` files (avoiding sourcing untrusted system configurations).

The subsystem defines a structured schema of six core properties:

| Property | Description | Example Values |
| :--- | :--- | :--- |
| **`os`** | The kernel or operating system name in lowercase. | `linux`, `darwin` |
| **`arch`** | The CPU architecture of the machine in lowercase. | `x86_64`, `aarch64` |
| **`distro`** | The unique identifier of the operating system distribution. | `ubuntu`, `debian`, `arch`, `macos` |
| **`family`** | The broader classification or parent family of the distribution. | `debian`, `arch`, `darwin` |
| **`version`** | The specific release version ID or `rolling` for continuous releases. | `22.04`, `12`, `rolling` |
| **`pkg_manager`**| The canonical package installer mapped to the platform's family. | `apt`, `pacman`, `dnf`, `brew` |

### Distribution Family Aggregation
To prevent configuration duplication, closely related distributions are grouped under a single **family** using `/etc/os-release`'s `ID_LIKE` properties. For example, both `ubuntu` and `debian` map to the `debian` family. Downstream tools can write general installation logic targeting `debian` family hosts while applying minor inline adjustments where necessary.

---

## 2. Configuration Storage (`hosts.ini`)

Discovered profiles are stored inside the standard user-space override path: `~/.config/rsd/hosts.ini` (or resolved via the `RSD_CONFIGLIB_SEARCH_PATH` hierarchy).

### INI File Structure
```ini
[localhost]
os = linux
arch = x86_64
distro = arch
family = arch
version = rolling
pkg_manager = pacman

[server1]
os = linux
arch = x86_64
distro = ubuntu
family = debian
version = 22.04
pkg_manager = apt
```

Properties are loaded into the global `R_INI_hosts` associative array namespace following `hosts.<alias>.<property>` keys (e.g., `R_INI_hosts["hosts.server1.family"]="debian"`).

---

## 3. CLI Command Reference

The `host` command module handles interactive platform identification and profile persistence.

### A. Discover Host Platform Properties (`identify`)
Identifies and displays active system metadata in key-value lines:
```bash
./rsd host identify
```
*Output:*
```
os=linux
arch=x86_64
distro=arch
family=arch
version=rolling
pkg_manager=pacman
```

### B. Persist Host Profile to Configuration (`save`)
Performs dynamic identification on the target machine and saves all properties to `hosts.ini` under the specified alias section:
```bash
# Saves properties under [localhost]
./rsd host save

# Saves properties under [my-server]
./rsd host save my-server
```

### C. Remote Execution Integration
The `host` command module is **remote-aware** (`RSD_C_HOST_REMOTE_AWARE=1`). This triggers the local engine to orchestrate remote platform scans by compiling a lightweight standalone platform discovery script and piping it dynamically to the remote target over SSH/LXC:

```bash
# Performs zero-dependency discovery on server1 and displays properties locally (no RSD required on server1)
rsd @server1 host identify

# Identifies server1 and saves its discovered profile into the LOCAL hosts.ini config under section [server1]
rsd @server1 host save
```

---

## 4. Developer Library API (`lib/host.lib`)

Downstream command modules and utility scripts can source the host library using short-circuit evaluation:

```bash
# Sourcing hook
[[ "$RSD_HOST_LIB" != "1" ]] && $(rsd::source_lib_or_die lib/host.lib)
```

### `rsd::l::host::identify`
Collects platform properties dynamically on the executing host.

```bash
declare -A my_host
rsd::l::host::identify my_host

echo "Our platform family is ${my_host[family]}"
```
* **Parameters**:
  - `$1` (`AssociativeArray&`): Nameref output variable to write discovered keys.
* **Return Value**: Returns `0` on success.
* **Throws**: Exits with `3` (Program Not Found) if system dependency `uname` is missing from `$PATH`.

### `rsd::l::host::get_property`
Safely retrieves a registered host property from `hosts.ini`.

```bash
local family=""
rsd::l::host::get_property "server1" "family" family

if [[ "$family" == "debian" ]]; then
    # Run Debian package installation routines
fi
```
* **Parameters**:
  - `$1` (`string`): Target host alias section name (e.g. `'localhost'`, `'server1'`).
  - `$2` (`string`): Property key to retrieve.
  - `$3` (`string&`): Nameref output variable to write the resolved value.
* **Return Value**: Returns `0` on success, `1` if the property or host is not found.
* **Fallback Behavior**: If querying `'localhost'` and no configurations have been written yet, the function automatically triggers dynamic on-the-fly local identification to return the property.
