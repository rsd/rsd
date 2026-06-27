#!/usr/bin/env bats

# Tests for the MySQL core library (lib/mysql.lib)
# @see lib/mysql.lib

setup() {
    export RSD_ON=1
    export RSD_DEBUG=0
    export RSD_MODE="devel"
    export RSD_RUN_DIR="${BATS_TEST_DIRNAME}/../../"

    declare -ga RSD_LIBRARY_SEARCH_PATH
    RSD_LIBRARY_SEARCH_PATH+=("${BATS_TEST_DIRNAME}/../../")

    rsd::create_search_path() {
        return 0
    }

    # Source dependent libraries
    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/config.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/mysql.lib"

    # Capture fd 7 (rsd::io) output on stdout for Bats assertions
    exec 7>&1

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
    [ "$RSD_MYSQL_USER" = "$USER" ]
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
        [ "$2" = "MYSQL_PWD=pass" ]
        [ "$3" = "mysql" ]
        [ "$4" = "-sN" ]
        [ "$5" = "-h" ]
        [ "$6" = "localhost" ]
        [ "$7" = "-P" ]
        [ "$8" = "3306" ]
        [ "$9" = "-u" ]
        [ "${10}" = "root" ]
        [ "${11}" = "-e" ]
        [ "${12}" = "SELECT 2" ]
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
