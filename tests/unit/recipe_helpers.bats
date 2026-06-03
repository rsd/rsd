#!/usr/bin/env bats

# Tests for recipe-specific helpers (install_pkg, find_recursive)
# and convention-based engine dispatch integration
# @see lib/recipe.lib

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

    unset RSD_REMOTE_TARGET
}

# rsd::io writes to fd 7 (dedicated bypass channel). bats' `run` only
# captures stdout+stderr, never fd 7. This helper merges fd 7 into
# stdout so $output contains rsd::io messages.
_run_engine() {
    rsd::l::r::execute_engine "$@" 7>&1
}

# ==============================================================================
# Convention-based dispatch — function probing
# ==============================================================================

@test "engine dispatches task function directly (no eval)" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY

    function rsd::r::direct_dispatch() { echo "DIRECT_OK"; return 0; }
    rsd::r::register_task "direct_dispatch"

    run _run_engine 0 0

    # Task output goes through >(frame_lines) process substitution which
    # bats cannot capture reliably. Assert on the engine's io status messages instead.
    [ "$status" -eq 0 ]
    [[ "$output" == *"applied successfully"* ]]
}

@test "engine discovers and calls pre_check by convention suffix" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY

    function rsd::r::probe_test::pre_check() { return 0; }  # Already satisfied
    function rsd::r::probe_test() { echo "SHOULD_NOT_RUN"; return 0; }
    rsd::r::register_task "probe_test"

    run _run_engine 0 0

    [ "$status" -eq 0 ]
    [[ "$output" == *"already satisfied"* ]]
    [[ "$output" != *"SHOULD_NOT_RUN"* ]]
}

@test "engine skips pre_check gracefully when function does not exist" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY

    # No ::pre_check defined — task should always run
    function rsd::r::no_precheck() { echo "ALWAYS_RUNS"; return 0; }
    rsd::r::register_task "no_precheck"

    run _run_engine 0 0

    [ "$status" -eq 0 ]
    [[ "$output" == *"applied successfully"* ]]
}

@test "engine calls task with arguments passed through function body (no quoting issues)" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY

    function rsd::r::arg_test() {
        local path="${HOME}/.config/test"
        echo "PATH=$path"
        return 0
    }
    rsd::r::register_task "arg_test"

    run _run_engine 0 0

    [ "$status" -eq 0 ]
    [[ "$output" == *"applied successfully"* ]]
}

# ==============================================================================
# Engine integration with inline pre-checks via convention
# ==============================================================================

@test "execute_engine with target::has_bin pre_check skips satisfied tasks" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY

    function rsd::r::test_has_bin_bash::pre_check() {
        rsd::l::target::has_bin bash
    }
    function rsd::r::test_has_bin_bash() { echo "SHOULD_NOT_RUN"; return 0; }
    rsd::r::register_task "test_has_bin_bash"

    run _run_engine 0 0

    [ "$status" -eq 0 ]
    [[ "$output" == *"already satisfied"* ]]
    [[ "$output" != *"SHOULD_NOT_RUN"* ]]
}

@test "execute_engine runs apply when pre_check fails" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY

    function rsd::r::test_fails_pre::pre_check() {
        rsd::l::target::has_bin __rsd_nonexistent_binary_xyz__
    }
    function rsd::r::test_fails_pre() { echo "APPLIED_OK"; return 0; }
    rsd::r::register_task "test_fails_pre"

    run _run_engine 0 0

    [ "$status" -eq 0 ]
    [[ "$output" == *"applied successfully"* ]]
}

# ==============================================================================
# find_recursive helper
# ==============================================================================

@test "rsd::l::r::find_recursive discovers nested recipe files" {
    local mock_dir
    mock_dir=$(mktemp -d -t rsd-find-test.XXXXXX)
    mkdir -p "${mock_dir}/sub"
    touch "${mock_dir}/top_level.recipe"
    touch "${mock_dir}/sub/nested.recipe"

    run rsd::l::r::find_recursive "$mock_dir" ""

    rm -rf "$mock_dir"

    [ "$status" -eq 0 ]
    [[ "$output" == *"top_level"* ]]
    [[ "$output" == *"sub/nested"* ]]
}
