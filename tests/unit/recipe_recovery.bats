#!/usr/bin/env bats

setup() {
    export RSD_ON=1
    export RSD_DEBUG=0
    export RSD_MODE="devel"
    export RSD_RUN_DIR="${BATS_TEST_DIRNAME}/../../"
    
    declare -ga RSD_LIBRARY_SEARCH_PATH
    RSD_LIBRARY_SEARCH_PATH+=("${BATS_TEST_DIRNAME}/../../")

    # Stub create search path to allow sourcing libraries
    rsd::create_search_path() {
        return 0
    }

    # Source dependencies
    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/config.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/recipe.lib"

    # Redirect RSD messaging fd (7) to stdout so BATS captures it in $output.
    # io.lib sets exec 7>&2, which sends messages to stderr — invisible to
    # BATS's run command. This makes assertions against message content work.
    exec 7>&1
}

# Helper: run a function capturing fd 7 (rsd::io) in $output.
_run_io() {
    _run_io_inner() { exec 7>&1; "$@"; }
    run _run_io_inner "$@"
}

@test "rsd::l::r::handle_failure rollback executes backward recovery pops in exact reverse chronological order" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY

    # Task 1 (succeeds, has rollback)
    function rsd::r::task1() { return 0; }
    function rsd::r::task1::rollback() { echo "ROLLBACK_1"; return 0; }
    rsd::r::register_task "task1" "rollback"

    # Task 2 (succeeds, has rollback)
    function rsd::r::task2() { return 0; }
    function rsd::r::task2::rollback() { echo "ROLLBACK_2"; return 0; }
    rsd::r::register_task "task2" "rollback"

    # Task 3 (fails, recovery=rollback)
    function rsd::r::task3() { return 1; }
    function rsd::r::task3::rollback() { return 0; }
    rsd::r::register_task "task3" "rollback"

    _run_io rsd::l::r::execute_engine 0 0

    [ "$status" -eq 10 ]
    
    # Assert rollback occurred in reverse chronological order
    [[ "$output" == *"Executing task 'task1'"* ]]
    [[ "$output" == *"Executing task 'task2'"* ]]
    [[ "$output" == *"Executing task 'task3'"* ]]
    [[ "$output" == *"Initiating Backward Recovery (Rollback)..."* ]]
    [[ "$output" == *"Undoing changes for task 'task2'"* ]]
    [[ "$output" == *"ROLLBACK_2"* ]]
    [[ "$output" == *"Undoing changes for task 'task1'"* ]]
    [[ "$output" == *"ROLLBACK_1"* ]]
    
    # Validate chronological output order (ROLLBACK_2 must appear before ROLLBACK_1)
    [[ "$output" == *"ROLLBACK_2"*"ROLLBACK_1"* ]]
}

@test "rsd::l::r::handle_failure forward halts execution and prints rerunnable warnings" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY

    function rsd::r::fail_task() { return 1; }
    rsd::r::register_task "fail_task"

    _run_io rsd::l::r::execute_engine 0 0

    [ "$status" -eq 10 ]
    [[ "$output" == *"Recovery Mode: FORWARD."* ]]
    [[ "$output" == *"Please resolve the environmental issue, then run the recipe again."* ]]
    [[ "$output" == *"Already satisfied steps will be automatically skipped."* ]]
}
