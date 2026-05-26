# KeePassXC Integration & Hardened Vault Specification

The **KeePass Subsystem** in the RSD (Rapid Script Developer) framework provides a highly secure, automated, and GPG-hardened interface for storing and retrieving platform credentials (e.g. SSH passkeys, sudo passwords, remote access tokens). 

By integrating the lightweight standard Bash library ([kpx.lib](file:///home/raul/Devel/rsd/lib/kpx.lib)) and the command module ([kpx](file:///home/raul/Devel/rsd/command/kpx)) with the host system's `keepassxc-cli`, RSD enables automated script execution without exposing plain-text keys in configuration files or process command lines.

---

## 1. Hardened Architectural Security Model

RSD implements a **double-envelope security protocol** combining asymmetric GPG encryption with symmetric KeePassXC database encryption to achieve silent, secure credential delivery:

```
  ┌──────────────────────────────────────────────────────────────────┐
  │                           gpg-agent                              │
  │     (Holds active decrypted session key in secure kernel RAM)    │
  └───────────────────────────────┬──────────────────────────────────┘
                                  │
                                  ▼   [ Decrypts ]
  ┌───────────────────────────────┴──────────────────────────────────┐
  │                 ~/.config/rsd/vault.key.gpg                      │
  │              (48-character high-entropy master key)               │
  └───────────────────────────────┬──────────────────────────────────┘
                                  │
                                  ▼   [ Stream Piping ]
  ┌───────────────────────────────┴──────────────────────────────────┐
  │                   keepassxc-cli show/add                         │
  │       (Queries ~/.config/rsd/vault.kdbx via secure FD stdin)     │
  └──────────────────────────────────────────────────────────────────┘
```

1. **Transaction Isolation & Atomic Writes**: Vault creations (`init`) or credential modifications (`add`, `rotate-key`) occur entirely inside sandboxed temporary directories (e.g. `/tmp/rsd-bootstrap-XXXXXX`) to prevent partial write corruptions or dirty states. Promoted files are swapped atomically via `mv` once operations succeed.
2. **Double-Envelope Vault Key**: The 48-character high-entropy KeePass database master password is generated dynamically via `openssl rand -base64 48` and immediately encrypted as a GPG payload (`vault.key.gpg`) targeting the user's `RSD_GPG_USER_ID`.
3. **Zero-Echo Stdin Stream Piping**: RSD never leaks database master keys or password entries in shell history or process list tables (avoiding command-line arguments like `keepassxc-cli --password`). Instead, it pushes credentials into standard input file descriptors dynamically:
   ```bash
   keepassxc-cli show -a Password "$vault_db" "$entry_path" <<< "$master_key"
   ```
4. **Active Memory Cleanup**: All in-memory secret parameters and keys are dynamically monitored and scrubbed from execution environments using shell cleanup traps (`trap 'unset master_key; ...' EXIT INT TERM`).

---

## 2. Setup & Host Installation

RSD depends on `keepassxc-cli` to coordinate vault operations. Choose the installation route matched to your workstation layout:

### Route A: For Native / Local Users (Arch Linux Native Setup)
Since your workstation runs Native Arch Linux, you can run all vault utilities natively:
```bash
sudo pacman -S keepassxc
```

### Route B: For Docker / Standard Container Environments (CI & Team Setup)
For team environments or isolated sandbox testing, ensure dependencies are present inside the runner container:
```dockerfile
# Include within your testing or development Dockerfile
RUN apt-get update && apt-get install -y keepassxc gpg-agent openssl
```

---

## 3. CLI Command Reference

Execute the `kpx` command module to manage your local secure vault.

### A. Environment Diagnostics (`check`)
Verifies host binary paths (`keepassxc-cli`, `gpg`, `openssl`) and validates that the `gpg-agent` daemon is active and responsive:
```bash
rsd kpx check
```
* **Exit Codes**: Returns `0` if the environment is ready, and `3` (Program Not Found) on missing dependencies.

### B. Hardened Vault Initialization (`init`)
Generates a new database `vault.kdbx` and GPG-encrypted keys:
```bash
rsd kpx init
```
* **Recovery Phrase**: Outputs a unique, one-time 24-character hexadecimal backup recovery token (`recovery.key.gpg`) encrypted to your GPG ID. Store this phrase safely offline to recover the vault in case of key loss.

### C. Add Credential to Vault (`add`)
Safely inserts a username and password mapping into the database:
```bash
rsd kpx add "RemoteHosts/server1" "admin" "SuperSecurePassword123"
rsd kpx add "Sudo/localhost" "" "MyLocalSudoPass"
```

### D. Retrieve Credential from Vault (`show`)
Decrypts the vault key and displays the target credential cleanly:
```bash
rsd kpx show "RemoteHosts/server1"
```

### E. Rotate Vault Recipient Key (`rotate-key`)
Re-encrypts your database keys (`vault.key.gpg` and `recovery.key.gpg`) to a new GPG Recipient Key ID (e.g. after key expiration or migration):
```bash
rsd kpx rotate-key "new-recipient@nostromo"
```

---

## 4. Developer Library API (`lib/kpx.lib`)

Custom automation commands and recipes can programmatic retrieve credentials using the standard library functions:

```bash
# Sourcing hook
[[ "$RSD_KPX_LIB" != "1" ]] && $(rsd::source_lib_or_die lib/kpx.lib)
```

### `rsd::l::kpx::get_password`
Safely retrieves a vault credential, promoting the GPG-decrypted master password directly to your local variable.

```bash
local db_pass=""
if rsd::l::kpx::get_password "RemoteHosts/server1" db_pass; then
    # Use password dynamically in pipeline execution
    mysql -u admin -p"$db_pass" -h 10.0.0.1
fi
```
* **Parameters**:
  - `$1` (`string`): The path inside the database vault (e.g. `'RemoteHosts/server1'`).
  - `$2` (`string&`): Nameref output variable to write the retrieved secret.
* **Return Value**: Returns `0` on success, `1` on key decryption failure, and `2` if the entry is not found.

### `rsd::l::kpx::add_password`
Programmatically writes a credential mapping into the database.

```bash
rsd::l::kpx::add_password "Sudo/server1" "root" "ElevatedSecurePassword"
```
* **Parameters**:
  - `$1` (`string`): Database target path.
  - `$2` (`string`): Target username (can be empty string).
  - `$3` (`string`): Plain-text secret to store.
* **Return Value**: Returns `0` on success, `1` if the database is uninitialized, and `2` on KeepassXC write failures.