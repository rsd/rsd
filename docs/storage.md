# Storage Command — Cross-Cloud File Operations

## Overview

The `storage` command provides a unified interface for moving files across local
filesystems and cloud storage providers (AWS S3, Google Drive, Backblaze B2,
SFTP, etc.) via [rclone](https://rclone.org).

**RSD handles WHERE rclone runs** (local or remote host via target dispatch).
**rclone handles WHERE the data lives** (cloud endpoints via `remote:path` syntax).

```bash
# Copy files from S3 to Google Drive
rsd storage copy s3:my-bucket/logs/ gdrive:archive/logs/

# Move data on a remote host's cloud backends
rsd @bi storage move s3:old-data/ b2:cold-storage/

# Upload local files to cloud
rsd storage copy /home/raul/documents/ gdrive:documents/
```

## Quick Start

```bash
# 1. Install rclone (if not installed)
rsd recipe run rclone/install

# 2. Configure remotes (interactive)
rsd storage config

# 3. Verify everything works
rsd storage doctor

# 4. Start using
rsd storage ls gdrive:
rsd storage copy /local/data/ s3:my-bucket/data/
```

## Actions

| Action   | Description                                     | Destructive? |
| :------- | :---------------------------------------------- | :----------: |
| `copy`   | Copy files from source to destination           | No           |
| `move`   | Move files (copy + delete source)               | Source only  |
| `sync`   | Make dest identical to source                   | **YES**      |
| `ls`     | List remote contents                            | No           |
| `size`   | Calculate total size of a remote path           | No           |
| `check`  | Verify source and dest are identical            | No           |
| `config` | Interactive rclone configuration                | No           |
| `setup`  | Bootstrap rclone + push config to remote target | No           |
| `doctor` | Diagnose config, tokens, connectivity           | No           |

### Sync Safety Gate

`sync` will **delete files at the destination** that do not exist at the source.
To prevent accidental data loss:

- Without `--confirm`, sync always runs in `--dry-run` mode
- Use `--confirm` to execute the actual sync
- Always review the dry-run output first

```bash
# Preview what would happen
rsd storage sync /local/data/ s3:backup/

# Actually execute (after reviewing dry-run)
rsd storage sync /local/data/ s3:backup/ --confirm
```

## Path Syntax

rclone's native `remote:path` syntax is used directly:

```
s3:bucket-name/folder/         # AWS S3
gdrive:My Documents/           # Google Drive
b2:bucket/path/                # Backblaze B2
sftp:server/path/              # SFTP
/local/filesystem/path/        # Local filesystem
```

## Configuration

### Config File Resolution

The storage library resolves rclone config in this priority order:

1. **CLI flag**: `rsd storage --config /path/to/rclone.conf ...`
2. **Environment**: `RCLONE_CONFIG=/path/to/rclone.conf`
3. **RSD-managed**: `~/.config/rsd/rclone.conf`
4. **rclone default**: `~/.config/rclone/rclone.conf` (fallback)

### Creating a Config

```bash
rsd storage config
```

This launches `rclone config` interactively, writing to the RSD-managed path
(`~/.config/rsd/rclone.conf`).

### Distributing Config to Remote Hosts

```bash
# Push only S3 and Google Drive configs to host @bi
rsd @bi storage setup --remotes s3,gdrive

# Push all configured remotes
rsd @bi storage setup
```

The `setup` action:
1. Verifies rclone is installed on the remote (prompts to install if missing)
2. Extracts only the requested remote sections from your local config
3. Pushes them to the remote's `~/.config/rsd/rclone.conf` via SSH tunnel
4. Verifies connectivity for each pushed remote

### Encrypted Config

Protect your config file with rclone's built-in encryption:

```bash
rclone config encryption set
```

RSD can store the encryption password in KeePassXC and inject it automatically
via `RCLONE_CONFIG_PASS`. Store the password at the vault path:
`rsd/storage/rclone-config-pass`

## OAuth Token Lifecycle

### The Problem

OAuth-based remotes (Google Drive, OneDrive, Dropbox) use tokens that can
expire or be revoked under specific conditions:

| Risk                      | Trigger                                       | Consequence                |
| :------------------------ | :-------------------------------------------- | :------------------------- |
| **7-day expiry**          | Google Cloud project in "Testing" mode         | Token dies every 7 days    |
| **6-month inactivity**    | No rclone operation for 6 months              | Token revoked by Google    |
| **User revocation**       | User removes app access in Google account     | Immediate token death      |
| **Token limit (100)**     | Too many refresh tokens per client ID         | Oldest token evicted       |
| **Missing refresh_token** | Incomplete OAuth flow                         | Cannot refresh, dies in 1h |

### Prevention

1. **Use your OWN Google Cloud Client ID** — not rclone's shared one
2. **Ensure OAuth consent screen is NOT in "Testing" mode**
3. **Run `rsd storage doctor` periodically** — warns at 150 days of inactivity
4. **For headless servers**: Use Google Service Accounts instead of user OAuth

### Service Accounts (Recommended for Servers)

For servers that run unattended for months, Service Accounts are more reliable
than user OAuth tokens:

- **No refresh needed** — tied to a key file, not a user session
- **No browser required** — fully headless setup
- **No expiration** — permanent until the key is revoked

To configure:
1. Create a Service Account in Google Cloud Console
2. Grant it access to the specific Drive folder or GCS bucket
3. Download the JSON key file
4. Configure rclone: `rclone config` → choose "service_account_file" option

### Token Health Monitoring

```bash
rsd storage doctor

# Sample output:
# [rsd]    ✓ rclone binary found: v1.68.2
# [rsd]    ✓ Config: ~/.config/rsd/rclone.conf
# [rsd]    ✓ Remote 's3' — type: s3 — credentials: static (no expiry concern)
# [rsd]    ⚠ Remote 'gdrive' — type: drive — token last used 147 days ago. ~33 days until expiry.
# [rsd]    ✓ Remote 'b2' — type: b2 — credentials: static (no expiry concern)
```

### Re-authorization

If a token expires, re-authorize:

```bash
# Re-authorize a specific remote
rclone config reconnect gdrive:

# Or reconfigure from scratch
rsd storage config
```

## Troubleshooting

### "rclone not found"

Install rclone:
```bash
rsd recipe run rclone/install          # Local
rsd @bi recipe run rclone/install      # Remote host
```

### "invalid_grant" / Token expired

1. Run `rsd storage doctor` to identify the affected remote
2. Re-authorize: `rclone config reconnect <remote>:`
3. Push updated config: `rsd @bi storage setup --remotes <remote>`

### Config file not found

```bash
# Check where RSD looks for config
rsd storage doctor

# Create a new config
rsd storage config
```

### Connection timeout / Permission denied

```bash
# Test connectivity with verbose output
rsd storage ls s3:my-bucket/ --verbose

# Check rclone config directly
rclone config show
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    command/storage                           │
│  CLI entry point: rsd::c::storage::*                        │
│  Actions: copy, move, sync, ls, size, check, config,        │
│           setup, doctor                                     │
│  REMOTE_AWARE=1 (Mode A: local orchestration)               │
├─────────────────────────────────────────────────────────────┤
│                    lib/storage.lib                           │
│  namespace: rsd::l::storage::                               │
│  • rclone binary discovery & validation                     │
│  • Config file resolution (RSD-managed → rclone default)    │
│  • Partial config extraction for remote push                │
│  • Credential injection from KeePassXC vault                │
│  • OAuth token health monitoring                            │
├─────────────────────────────────────────────────────────────┤
│             lib/recipe/rclone/install.recipe                 │
│  Bootstrap rclone binary on local or remote targets         │
│  Tasks: validate_env → download → install → verify          │
├─────────────────────────────────────────────────────────────┤
│  Existing layers (unchanged):                               │
│  target.lib → remote.lib → protocol.lib                     │
└─────────────────────────────────────────────────────────────┘
```
