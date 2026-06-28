# MySQL Command — Database Integration & Administration

## Overview

The `mysql` command module provides a unified interface for configuring, testing, query routing, and exporting MySQL database servers. It natively supports both direct connection from the local controller and remote execution via SSH jump hosts.

---

## Quick Start

```bash
# 1. Configure a database connection profile (interactive)
rsd mysql configure @prod-db

# 2. Test connection
rsd mysql ping @prod-db

# 3. List schemas
rsd mysql list-databases @prod-db

# 4. Run a query
rsd mysql query "SELECT COUNT(*) FROM users" my_database @prod-db

# 5. Export users & privileges for migration
rsd mysql export-users @prod-db > users_migration.sql
```

---

## Connection Profiles (`mysql.ini`)

Connection profiles are saved under `~/.config/rsd/mysql.ini`. Passwords are encrypted and securely stored inside the KeePassXC vault under `Databases/mysql/<profile_name>` to prevent plaintext leakage.

### Configuration Parameters
* **`connection_mode`**: Either `direct` or `remote` (see execution modes below).
* **`host`**: Database server IP address or hostname.
* **`port`**: Database TCP port (default: `3306`).
* **`user`**: Database login username.
* **`socket`**: Optional local Unix socket path.

---

## Understanding Execution Modes

Choosing between `direct` and `remote` execution modes is critical for routing your queries safely through your network architecture.

```
[ Direct Mode ]
Local Controller (RSD) ===(Direct TCP/3306)===> Remote Database Server

[ Remote Mode ]
Local Controller (RSD) ===(SSH/22)===> Target Host ===(Local TCP/3306)===> Database Server
```

### 1. Direct Mode (`connection_mode = direct`)
* **How it works**: RSD executes the `mysql` client binary **locally** on your controller host.
* **Network**: The local machine connects directly to the specified database `host` over the network on port `3306`.
* **When to use**: 
  * Connecting to a database server running on your local machine (`localhost`).
  * Connecting to a database server that exposes port 3306 to your network/VPN/Tailscale mesh.
* **Configuration Example**:
  ```ini
  [local-instance]
  connection_mode = direct
  host = localhost
  port = 3306
  user = root
  ```

### 2. Remote Mode (`connection_mode = remote`)
* **How it works**: RSD connects via SSH to the active target host (e.g. `@techteam@jumba-mysql`) and executes the `mysql` client binary **remotely** on that target host.
* **Network**: The database connection is initiated from the remote target host, meaning it only needs to be accessible to that host over local network loops.
* **When to use**:
  * The database server is bound to `127.0.0.1` on the remote server for security.
  * The database server is behind a private LAN/subnet and only accessible after SSHing to a jump/bastion server.

#### Case A: Database is on the SSH host itself
To connect to a database server running on the same machine that you SSH into:
```ini
[techteam@jumba-mysql]
connection_mode = remote
host = localhost
port = 3306
user = root
```
*RSD SSHes into `techteam@jumba-mysql`, runs `mysql`, and connects to `localhost` (the database process running locally on that server).*

#### Case B: Database is on a separate internal machine (Jump Host workflow)
To connect to an internal database server (e.g. `db-internal.lan`) that is only accessible from your SSH target host (`techteam@jumba-mysql`):
```ini
[techteam@jumba-mysql]
connection_mode = remote
host = db-internal.lan
port = 3306
user = db_app_user
```
*RSD SSHes into `techteam@jumba-mysql`, runs the remote `mysql` client, and opens a TCP connection from the target host to the internal database server at `db-internal.lan` on port 3306.*

---

## Action Reference

### `configure [@profile]`
Configures connection parameters for a profile. If no options are specified, prompts interactively.
* **Options**:
  - `-i, --interactive`: Prompts for all settings.
  - `--mode <remote|direct>`: Connection mode.
  - `--host <host>`: Database host address.
  - `--user <user>`: Database username.
  - `--pwd <password>`: Database password (automatically encrypted and saved to vault).
  - `--port <port>`: Database TCP port.
  - `--socket <socket>`: Unix socket path.

### `ping [@profile]`
Pings the MySQL server to verify credentials and connectivity.

### `list-databases [@profile]`
Lists all database schemas on the server, excluding default system schemas.

### `list-tables <database> [@profile]`
Lists all tables in a specified database.

### `query "<sql>" [database] [@profile]`
Executes a SQL query string. Standard output contains query results only; all logs and debug lines are sent to standard error.

### `export-users [@profile] [--include-root]`
Generates and prints a list of `CREATE USER` and `GRANT` DDL statements to recreate the user accounts and permissions, ending with `FLUSH PRIVILEGES;`.
* **Options**:
  - `--include-root`: By default, the administrative `root` account is excluded to prevent import conflicts. Set this flag to include it.
