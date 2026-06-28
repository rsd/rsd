#!/usr/bin/env bats

# Tests for the MySQL core library (lib/mysql.lib)
# @see lib/mysql.lib

setup() {
    export RSD_ON=1
    export RSD_DEBUG=0
    export RSD_MODE="devel"
    export RSD_RUN_DIR="${BATS_TEST_DIRNAME}/../../"
    export USER="bats-user"

    declare -ga RSD_LIBRARY_SEARCH_PATH
    RSD_LIBRARY_SEARCH_PATH+=("${BATS_TEST_DIRNAME}/../../")

    rsd::create_search_path() {
        return 0
    }

    # Source dependent libraries
    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/config.lib"
    
    # Stub config loader to isolate tests from host configs
    rsd::config::get_file() {
        return 0
    }
    
    source "${BATS_TEST_DIRNAME}/../../lib/mysql.lib"
    source "${BATS_TEST_DIRNAME}/../../command/mysql"
    eval "$(sed -n '/^function rsd::parse_args/,/^}/p' "${BATS_TEST_DIRNAME}/../../rsd")"

    # Capture fd 7 (rsd::io) output on stdout for Bats assertions
    exec 7>&1

    _run_io_inner() {
        exec 7>&1
        "$@"
    }

    # Local mode default
    unset RSD_REMOTE_TARGET
    unset R_INI_mysql
    declare -gA R_INI_mysql

    # Clear resolved variables
    RSD_MYSQL_RESOLVED=0
    RSD_MYSQL_METHOD=""
    RSD_MYSQL_HOST=""
    RSD_MYSQL_USER=""
    RSD_MYSQL_PWD=""
    RSD_MYSQL_PORT=""
    RSD_MYSQL_SOCKET=""
}

# ==============================================================================
# Connection Resolution
# ==============================================================================

@test "mysql::resolve falls back to defaults for empty profile" {
    rsd::l::mysql::resolve ""

    [ "$RSD_MYSQL_RESOLVED" -eq 1 ]
    [ "$RSD_MYSQL_METHOD" = "remote" ]
    [ "$RSD_MYSQL_HOST" = "localhost" ]
    [ "$RSD_MYSQL_USER" = "bats-user" ]
    [ "$RSD_MYSQL_PORT" = "3306" ]
}

@test "mysql::resolve parses values correctly from R_INI_mysql for host profile" {
    R_INI_mysql["prod-db.connection_mode"]="direct"
    R_INI_mysql["prod-db.host"]="db.example.com"
    R_INI_mysql["prod-db.user"]="backup_user"
    R_INI_mysql["prod-db.pwd"]="password123"
    R_INI_mysql["prod-db.port"]="3307"
    R_INI_mysql["prod-db.socket"]="/tmp/mysql.sock"

    rsd::l::mysql::resolve "prod-db"

    [ "$RSD_MYSQL_RESOLVED" -eq 1 ]
    [ "$RSD_MYSQL_METHOD" = "direct" ]
    [ "$RSD_MYSQL_HOST" = "db.example.com" ]
    [ "$RSD_MYSQL_USER" = "backup_user" ]
    [ "$RSD_MYSQL_PWD" = "password123" ]
    [ "$RSD_MYSQL_PORT" = "3307" ]
    [ "$RSD_MYSQL_SOCKET" = "/tmp/mysql.sock" ]
}

@test "mysql::resolve retrieves password from KeePass vault if empty in config" {
    R_INI_mysql["prod-db.connection_mode"]="direct"
    R_INI_mysql["prod-db.host"]="db.example.com"
    R_INI_mysql["prod-db.user"]="backup_user"
    R_INI_mysql["prod-db.pwd"]="" # Empty to trigger vault lookup

    # Stub kpx.lib structures
    export RSD_KPX_LIB=1
    
    # Mock vault files existence
    local mock_vault_dir
    mock_vault_dir=$(mktemp -d)
    touch "$mock_vault_dir/vault.key.gpg"
    touch "$mock_vault_dir/vault.kdbx"
    export RSD_CONFIG_DIR="$mock_vault_dir"

    # Stub vault_dir
    rsd::l::kpx::vault_dir() {
        echo "$RSD_CONFIG_DIR"
    }

    # Mock get_password to return vault secret
    rsd::l::kpx::get_password() {
        local entry="$1"
        declare -n _out="$2"
        [ "$entry" = "Databases/mysql/prod-db" ] || return 2
        _out="vault-secret-abc"
        return 0
    }

    rsd::l::mysql::resolve "prod-db"

    [ "$RSD_MYSQL_RESOLVED" -eq 1 ]
    [ "$RSD_MYSQL_PWD" = "vault-secret-abc" ]

    rm -rf "$mock_vault_dir"
}

@test "mysql::resolve prefers config password over vault if both exist" {
    R_INI_mysql["prod-db.connection_mode"]="direct"
    R_INI_mysql["prod-db.host"]="db.example.com"
    R_INI_mysql["prod-db.user"]="backup_user"
    R_INI_mysql["prod-db.pwd"]="config-secret-123" # Config has priority

    # Stub kpx.lib structures
    export RSD_KPX_LIB=1
    
    # Mock vault files existence
    local mock_vault_dir
    mock_vault_dir=$(mktemp -d)
    touch "$mock_vault_dir/vault.key.gpg"
    touch "$mock_vault_dir/vault.kdbx"
    export RSD_CONFIG_DIR="$mock_vault_dir"

    # Stub vault_dir
    rsd::l::kpx::vault_dir() {
        echo "$RSD_CONFIG_DIR"
    }

    # Mock get_password (should not be called, but return different value just in case)
    rsd::l::kpx::get_password() {
        declare -n _out="$2"
        _out="vault-secret-abc"
        return 0
    }

    rsd::l::mysql::resolve "prod-db"

    [ "$RSD_MYSQL_RESOLVED" -eq 1 ]
    [ "$RSD_MYSQL_PWD" = "config-secret-123" ]

    rm -rf "$mock_vault_dir"
}

# ==============================================================================
# Query Routing & Execution Modes
# ==============================================================================

@test "mysql::query direct mode unsets RSD_REMOTE_TARGET and calls client locally" {
    RSD_MYSQL_RESOLVED=1
    RSD_MYSQL_METHOD="direct"
    RSD_MYSQL_HOST="10.0.0.5"
    RSD_MYSQL_USER="test"
    RSD_MYSQL_PORT="3306"
    RSD_MYSQL_PWD="pass"

    # Set remote target to verify it gets unset/restored
    export RSD_REMOTE_TARGET="@jump-host"

    # Stub binary check to succeed
    rsd::check_binary() {
        return 0
    }

    local tmp_marker
    tmp_marker=$(mktemp)

    # Stub execution tool to assert inputs and mock output
    rsd::l::target::exec() {
        echo "yes" > "$tmp_marker"
        # Assert RSD_REMOTE_TARGET is empty inside exec
        [ -z "${RSD_REMOTE_TARGET:-}" ]
        [ "$1" = "mysql" ]
        [ "$2" = "-sN" ]
        [ "$3" = "-h" ]
        [ "$4" = "10.0.0.5" ]
        [ "$5" = "-P" ]
        [ "$6" = "3306" ]
        [ "$7" = "-u" ]
        [ "$8" = "test" ]
        [ "$9" = "-e" ]
        [ "${10}" = "SELECT 1" ]
        echo "test_db_result"
    }

    run rsd::l::mysql::query "SELECT 1"

    [ "$status" -eq 0 ]
    [ -s "$tmp_marker" ]
    rm -f "$tmp_marker"
    [[ "$output" == *"test_db_result"* ]]
    # Target should be restored after execution
    [ "$RSD_REMOTE_TARGET" = "@jump-host" ]
}

@test "mysql::query remote mode executes mysql command on remote target" {
    RSD_MYSQL_RESOLVED=1
    RSD_MYSQL_METHOD="remote"
    RSD_MYSQL_HOST="localhost"
    RSD_MYSQL_USER="root"
    RSD_MYSQL_PORT="3306"
    RSD_MYSQL_PWD="pass"

    export RSD_REMOTE_TARGET="@remote-host"

    # Stub target binary check to succeed
    rsd::l::target::has_bin() {
        return 0
    }

    local tmp_marker
    tmp_marker=$(mktemp)

    rsd::l::target::exec() {
        echo "yes" > "$tmp_marker"
        # Assert target routing remains active
        [ "$RSD_REMOTE_TARGET" = "@remote-host" ]
        [ "$1" = "env" ]
        [ "$2" = "MYSQL_PWD='pass'" ]
        [ "$3" = "mysql" ]
        [ "$4" = "-sN" ]
        [ "$5" = "-h" ]
        [ "$6" = "'localhost'" ]
        [ "$7" = "-P" ]
        [ "$8" = "3306" ]
        [ "$9" = "-u" ]
        [ "${10}" = "'root'" ]
        [ "${11}" = "-e" ]
        [ "${12}" = "'SELECT 2'" ]
        echo -e "result\r" # SSH transport adds carriage returns
    }

    run rsd::l::mysql::query "SELECT 2"

    [ "$status" -eq 0 ]
    [ -s "$tmp_marker" ]
    rm -f "$tmp_marker"
    # Carriage return should be stripped
    [ "$output" = "result" ]
}

# ==============================================================================
# Helper Assertions
# ==============================================================================

@test "mysql::database_exists returns 0 if database is found" {
    # Stub query to return the db name
    rsd::l::mysql::query() {
        echo "my_app_db"
    }

    run rsd::l::mysql::database_exists "my_app_db"
    [ "$status" -eq 0 ]
}

@test "mysql::database_exists returns 1 if database is not found" {
    rsd::l::mysql::query() {
        echo ""
    }

    run rsd::l::mysql::database_exists "missing_db"
    [ "$status" -ne 0 ]
}

# ==============================================================================
# Configure Action & Vault Integrations
# ==============================================================================

@test "mysql::configure successfully saves password in vault when vault is active" {
    # Mock RSD config command dependency
    rsd::c::config::set() {
        return 0
    }

    # Mock vault presence
    export RSD_KPX_LIB=1
    local mock_vault_dir
    mock_vault_dir=$(mktemp -d)
    touch "$mock_vault_dir/vault.key.gpg"
    touch "$mock_vault_dir/vault.kdbx"
    export RSD_CONFIG_DIR="$mock_vault_dir"

    rsd::l::kpx::vault_dir() {
        echo "$RSD_CONFIG_DIR"
    }

    # Mock add_password using file marker for subshell propagation
    local add_called_file
    add_called_file=$(mktemp)
    rsd::l::kpx::add_password() {
        local entry="$1"
        local user="$2"
        local pwd="$3"
        [ "$entry" = "Databases/mysql/dev-test" ] || return 2
        [ "$user" = "test_user" ] || return 2
        [ "$pwd" = "test_pass" ] || return 2
        echo "yes" > "$add_called_file"
        return 0
    }

    # Run configure action directly
    run _run_io_inner rsd::c::mysql::configure "@dev-test" --mode remote --host localhost --user test_user --pwd test_pass --port 3306

    [ "$status" -eq 0 ]
    [ -s "$add_called_file" ]

    rm -rf "$mock_vault_dir"
    rm -f "$add_called_file"
}

@test "mysql::configure aborts when vault is not active/initialized" {
    # Mock RSD config command dependency
    rsd::c::config::set() {
        return 0
    }

    # Vault not active by pointing RSD_CONFIG_DIR to empty dir
    export RSD_KPX_LIB=1
    local mock_vault_dir
    mock_vault_dir=$(mktemp -d)
    export RSD_CONFIG_DIR="$mock_vault_dir"

    rsd::l::kpx::vault_dir() {
        echo "$RSD_CONFIG_DIR"
    }

    run _run_io_inner rsd::c::mysql::configure "@dev-test" --mode remote --host localhost --user test_user --pwd test_pass --port 3306

    [ "$status" -eq 1 ]
    [[ "$output" == *"KeePass vault is not initialized"* ]]

    rm -rf "$mock_vault_dir"
}

@test "mysql::configure aborts when vault is active but add_password fails" {
    # Mock RSD config command dependency
    rsd::c::config::set() {
        return 0
    }

    # Mock vault presence
    export RSD_KPX_LIB=1
    local mock_vault_dir
    mock_vault_dir=$(mktemp -d)
    touch "$mock_vault_dir/vault.key.gpg"
    touch "$mock_vault_dir/vault.kdbx"
    export RSD_CONFIG_DIR="$mock_vault_dir"

    rsd::l::kpx::vault_dir() {
        echo "$RSD_CONFIG_DIR"
    }

    # Mock add_password failing
    rsd::l::kpx::add_password() {
        return 2
    }

    run _run_io_inner rsd::c::mysql::configure "@dev-test" --mode remote --host localhost --user test_user --pwd test_pass --port 3306

    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to save password in vault"* ]]

    rm -rf "$mock_vault_dir"
}
