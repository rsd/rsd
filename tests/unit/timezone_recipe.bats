#!/usr/bin/env bats

# Tests for the timezone set recipe (lib/recipe/timezone/set.recipe)
# Verifies recipe registration, task function existence, pre_check logic,
# and validate_env behavior with mocked timedatectl.
#
# @see lib/recipe/timezone/set.recipe

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
    source "${BATS_TEST_DIRNAME}/../../lib/recipe/timezone/set.recipe"

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
# Registration
# ==============================================================================

@test "timezone_set::register registers all three tasks with default timezone" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY

    rsd::r::timezone_set::register

    [ "${#RSD_REGISTERED_TASKS[@]}" -eq 3 ]
    [ "${RSD_REGISTERED_TASKS[0]}" = "timezone_set::validate_env" ]
    [ "${RSD_REGISTERED_TASKS[1]}" = "timezone_set::apply" ]
    [ "${RSD_REGISTERED_TASKS[2]}" = "timezone_set::verify" ]
}

@test "timezone_set::register uses default timezone when --timezone is not provided" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY
    declare -g -A RSD_COMMAND_ARGS=()

    rsd::r::timezone_set::register

    [ "$RSD_TZ_TARGET" = "America/Sao_Paulo" ]
}

@test "timezone_set::register accepts --timezone CLI argument" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY
    declare -g -A RSD_COMMAND_ARGS=(["timezone"]="Europe/London")

    rsd::r::timezone_set::register

    [ "$RSD_TZ_TARGET" = "Europe/London" ]
}

@test "all registered tasks have forward recovery mode" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY

    rsd::r::timezone_set::register

    [ "${RSD_TASKS_RECOVERY["timezone_set::validate_env"]}" = "forward" ]
    [ "${RSD_TASKS_RECOVERY["timezone_set::apply"]}" = "forward" ]
    [ "${RSD_TASKS_RECOVERY["timezone_set::verify"]}" = "forward" ]
}

# ==============================================================================
# Task Function Existence
# ==============================================================================

@test "all required task functions are defined" {
    # apply functions (mandatory)
    bash::is_function rsd::r::timezone_set::validate_env
    bash::is_function rsd::r::timezone_set::apply
    bash::is_function rsd::r::timezone_set::verify

    # pre_check for apply (the only task with one)
    bash::is_function rsd::r::timezone_set::apply::pre_check
}

@test "validate_env and verify have no pre_check (unconditional)" {
    ! bash::is_function rsd::r::timezone_set::validate_env::pre_check
    ! bash::is_function rsd::r::timezone_set::verify::pre_check
}

# ==============================================================================
# apply::pre_check — idempotency
# ==============================================================================

@test "apply::pre_check returns 0 when timezone already matches" {
    RSD_TZ_TARGET="America/Sao_Paulo"

    # Stub get_current to return the target timezone
    rsd::l::tz::get_current() {
        declare -n _ref="$1"
        _ref="America/Sao_Paulo"
    }

    run rsd::r::timezone_set::apply::pre_check
    [ "$status" -eq 0 ]
}

@test "apply::pre_check returns 1 when timezone differs" {
    RSD_TZ_TARGET="America/Sao_Paulo"

    # Stub get_current to return a different timezone
    rsd::l::tz::get_current() {
        declare -n _ref="$1"
        _ref="UTC"
    }

    run rsd::r::timezone_set::apply::pre_check
    [ "$status" -ne 0 ]
}

# ==============================================================================
# validate_env — platform and input validation
# ==============================================================================

@test "validate_env fails when systemd is not available" {
    RSD_TZ_TARGET="UTC"

    # Stub is_supported to fail
    rsd::l::tz::is_supported() { rsd::io::error "not systemd"; return 1; }

    _run_io rsd::r::timezone_set::validate_env
    [ "$status" -eq 1 ]
}

@test "validate_env fails for invalid timezone" {
    RSD_TZ_TARGET="Fake/Timezone"

    rsd::l::tz::is_supported() { return 0; }
    rsd::l::tz::is_valid() { return 1; }

    _run_io rsd::r::timezone_set::validate_env
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid timezone"* ]]
}

@test "validate_env succeeds and reports method for valid timezone" {
    RSD_TZ_TARGET="UTC"

    rsd::l::tz::is_supported() { return 0; }
    rsd::l::tz::get_method() {
        declare -n _ref="$1"
        _ref="timedatectl"
    }
    rsd::l::tz::is_valid() { return 0; }

    _run_io rsd::r::timezone_set::validate_env
    [ "$status" -eq 0 ]
    [[ "$output" == *"Timezone method: timedatectl"* ]]
    [[ "$output" == *"valid"* ]]
}

# ==============================================================================
# verify — post-change confirmation
# ==============================================================================

@test "verify succeeds when timezone matches target" {
    RSD_TZ_TARGET="America/Sao_Paulo"

    rsd::l::tz::get_current() {
        declare -n _ref="$1"
        _ref="America/Sao_Paulo"
    }
    rsd::l::tz::get_ntp_status() {
        declare -n _ref="$1"
        _ref="yes"
    }
    rsd::l::target::exec() { echo "2026-06-03 16:30:00 BRT"; }

    _run_io rsd::r::timezone_set::verify
    [ "$status" -eq 0 ]
    [[ "$output" == *"America/Sao_Paulo"* ]]
    [[ "$output" == *"NTP synchronized: yes"* ]]
}

@test "verify fails when timezone does not match target" {
    RSD_TZ_TARGET="America/Sao_Paulo"

    rsd::l::tz::get_current() {
        declare -n _ref="$1"
        _ref="UTC"
    }

    _run_io rsd::r::timezone_set::verify
    [ "$status" -eq 1 ]
    [[ "$output" == *"verification failed"* ]]
}

# ==============================================================================
# Recipe options declaration
# ==============================================================================

@test "RSD_RECIPE_OPTIONS declares --timezone as a value option" {
    [ "${RSD_RECIPE_OPTIONS["timezone"]}" = "1" ]
}
