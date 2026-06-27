#!/usr/bin/env bats

# Tests for the Percona MySQL recipe (lib/recipe/mysql/percona.recipe)
# Verifies recipe registration, task function existence, pre_check logic,
# and validate_env behavior.
#
# @see lib/recipe/mysql/percona.recipe

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

    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/config.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/recipe.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/recipe/mysql/percona.recipe"

    # Redirect RSD messaging fd (7) to stdout so BATS captures it
    exec 7>&1

    # Local execution mode
    unset RSD_REMOTE_TARGET

    # Provide mock RSD_COMMAND_ARGS for registration
    declare -g -A RSD_COMMAND_ARGS=()
}

# Helper: run capturing fd 7 (rsd::io) in $output
_run_io() {
    _run_io_inner() { exec 7>&1; "$@"; }
    run _run_io_inner "$@"
}

# ==============================================================================
# Registration & Tasks Layout
# ==============================================================================

@test "mysql_percona::register registers all tasks with default version 8.4" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY
    
    # Stub require_platform to succeed
    rsd::l::r::require_platform() { return 0; }

    rsd::r::mysql_percona::register

    [ "${#RSD_REGISTERED_TASKS[@]}" -eq 4 ]
    [ "${RSD_REGISTERED_TASKS[0]}" = "mysql_percona::validate_env" ]
    [ "${RSD_REGISTERED_TASKS[1]}" = "mysql_percona::install_repo" ]
    [ "${RSD_REGISTERED_TASKS[2]}" = "mysql_percona::enable_repo" ]
    [ "${RSD_REGISTERED_TASKS[3]}" = "mysql_percona::install_server" ]
    [ "$RSD_MYSQL_VERSION" = "8.4" ]
    [ "$RSD_MYSQL_DISTRIBUTION" -eq 0 ]
}

@test "mysql_percona::register accepts --version and --distribution options" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY
    declare -g -A RSD_COMMAND_ARGS=(
        ["version"]="8.0"
        ["distribution"]=""
    )
    
    # Stub require_platform to succeed
    rsd::l::r::require_platform() { return 0; }

    rsd::r::mysql_percona::register

    [ "$RSD_MYSQL_VERSION" = "8.0" ]
    [ "$RSD_MYSQL_DISTRIBUTION" -eq 1 ]
    [ "${RSD_TASKS_RECOVERY["mysql_percona::enable_repo"]}" = "rollback" ]
}

# ==============================================================================
# Hook Functions Existence
# ==============================================================================

@test "all required task functions are defined" {
    bash::is_function rsd::r::mysql_percona::validate_env
    bash::is_function rsd::r::mysql_percona::install_repo
    bash::is_function rsd::r::mysql_percona::enable_repo
    bash::is_function rsd::r::mysql_percona::install_server

    bash::is_function rsd::r::mysql_percona::install_repo::pre_check
    bash::is_function rsd::r::mysql_percona::enable_repo::pre_check
    bash::is_function rsd::r::mysql_percona::install_server::pre_check
    bash::is_function rsd::r::mysql_percona::enable_repo::rollback
}

# ==============================================================================
# Task: validate_env
# ==============================================================================

@test "validate_env fails for unsupported OS families" {
    # Stub resolve_host_alias
    rsd::l::r::resolve_host_alias() {
        declare -n _ref="$1"
        _ref="localhost"
    }

    # Stub host properties to return redhat
    rsd::l::host::get_property() {
        declare -n _ref="$3"
        if [[ "$2" == "distro" ]]; then
            _ref="centos"
        elif [[ "$2" == "version" ]]; then
            _ref="9.0"
        fi
    }

    RSD_MYSQL_VERSION="8.4"
    RSD_MYSQL_DISTRIBUTION=0

    _run_io rsd::r::mysql_percona::validate_env
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unsupported distribution"* ]]
}

@test "validate_env fails for old Ubuntu version" {
    rsd::l::r::resolve_host_alias() {
        declare -n _ref="$1"
        _ref="localhost"
    }
    rsd::l::host::get_property() {
        declare -n _ref="$3"
        if [[ "$2" == "distro" ]]; then
            _ref="ubuntu"
        elif [[ "$2" == "version" ]]; then
            _ref="22.04"
        fi
    }
    rsd::l::host::version_gte() { return 1; }

    RSD_MYSQL_VERSION="8.4"
    RSD_MYSQL_DISTRIBUTION=0

    _run_io rsd::r::mysql_percona::validate_env
    [ "$status" -eq 1 ]
    [[ "$output" == *"Ubuntu version must be at least 24.04"* ]]
}

@test "validate_env succeeds for Ubuntu >= 24.04" {
    rsd::l::r::resolve_host_alias() {
        declare -n _ref="$1"
        _ref="localhost"
    }
    rsd::l::host::get_property() {
        declare -n _ref="$3"
        if [[ "$2" == "distro" ]]; then
            _ref="ubuntu"
        elif [[ "$2" == "version" ]]; then
            _ref="26.04"
        fi
    }
    rsd::l::host::version_gte() { return 0; }

    RSD_MYSQL_VERSION="8.4"
    RSD_MYSQL_DISTRIBUTION=0

    _run_io rsd::r::mysql_percona::validate_env
    [ "$status" -eq 0 ]
    [[ "$output" == *"Repo: ps-84-lts"* ]]
    [[ "$output" == *"Environment validation passed"* ]]
}

@test "validate_env resolves pdps-84-lts for 8.4 with distribution" {
    rsd::l::r::resolve_host_alias() {
        declare -n _ref="$1"
        _ref="localhost"
    }
    rsd::l::host::get_property() {
        declare -n _ref="$3"
        if [[ "$2" == "distro" ]]; then
            _ref="ubuntu"
        elif [[ "$2" == "version" ]]; then
            _ref="26.04"
        fi
    }
    rsd::l::host::version_gte() { return 0; }

    RSD_MYSQL_VERSION="8.4"
    RSD_MYSQL_DISTRIBUTION=1

    _run_io rsd::r::mysql_percona::validate_env
    [ "$status" -eq 0 ]
    [[ "$output" == *"Repo: pdps-84-lts"* ]]
}

@test "validate_env resolves ps80 for 8.0 standard" {
    rsd::l::r::resolve_host_alias() {
        declare -n _ref="$1"
        _ref="localhost"
    }
    rsd::l::host::get_property() {
        declare -n _ref="$3"
        if [[ "$2" == "distro" ]]; then
            _ref="ubuntu"
        elif [[ "$2" == "version" ]]; then
            _ref="26.04"
        fi
    }
    rsd::l::host::version_gte() { return 0; }

    RSD_MYSQL_VERSION="8.0"
    RSD_MYSQL_DISTRIBUTION=0

    _run_io rsd::r::mysql_percona::validate_env
    [ "$status" -eq 0 ]
    [[ "$output" == *"Repo: ps80"* ]]
}

@test "validate_env fails for invalid mysql version option" {
    rsd::l::r::resolve_host_alias() {
        declare -n _ref="$1"
        _ref="localhost"
    }
    rsd::l::host::get_property() {
        declare -n _ref="$3"
        if [[ "$2" == "distro" ]]; then
            _ref="ubuntu"
        elif [[ "$2" == "version" ]]; then
            _ref="26.04"
        fi
    }
    rsd::l::host::version_gte() { return 0; }

    RSD_MYSQL_VERSION="5.7"
    RSD_MYSQL_DISTRIBUTION=0

    _run_io rsd::r::mysql_percona::validate_env
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unsupported Percona MySQL version"* ]]
}

# ==============================================================================
# Task: install_repo::pre_check
# ==============================================================================

@test "install_repo::pre_check returns 0 when percona-release is installed" {
    rsd::l::target::exec() {
        # Simulate dpkg outputting success
        return 0
    }

    run rsd::r::mysql_percona::install_repo::pre_check
    [ "$status" -eq 0 ]
}

@test "install_repo::pre_check returns 1 when percona-release is missing" {
    rsd::l::target::exec() {
        # Simulate dpkg outputting failure
        return 1
    }

    run rsd::r::mysql_percona::install_repo::pre_check
    [ "$status" -ne 0 ]
}

# ==============================================================================
# Task: enable_repo::pre_check
# ==============================================================================

@test "enable_repo::pre_check returns 0 when repo name is in list file" {
    RSD_MYSQL_REPO_NAME="ps-84-lts"
    rsd::l::target::file_contains() {
        # Mocking file_contains to succeed
        return 0
    }
    rsd::l::apt::has_candidate() {
        # Mocking has_candidate to succeed
        return 0
    }

    run rsd::r::mysql_percona::enable_repo::pre_check
    [ "$status" -eq 0 ]
}

@test "enable_repo::pre_check returns 1 when repo name is not in list file" {
    RSD_MYSQL_REPO_NAME="ps-84-lts"
    rsd::l::target::file_contains() {
        # Mocking file_contains to fail
        return 1
    }
    rsd::l::apt::has_candidate() {
        return 0
    }

    run rsd::r::mysql_percona::enable_repo::pre_check
    [ "$status" -ne 0 ]
}
