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
}

@test "rsd::l::recipe::handle_failure rollback executes backward recovery pops in exact reverse chronological order" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_PRE
    declare -g -A RSD_TASKS_APPLY
    declare -g -A RSD_TASKS_POST
    declare -g -A RSD_TASKS_RECOVERY
    declare -g -A RSD_TASKS_ROLLBACK

    # Task 1 (succeeds)
    task1_apply() { return 0; }
    task1_rollback() { echo "ROLLBACK_1"; return 0; }
    rsd::recipe::register_task \
        --name "task1" \
        --apply "task1_apply" \
        --rollback "task1_rollback"

    # Task 2 (succeeds)
    task2_apply() { return 0; }
    task2_rollback() { echo "ROLLBACK_2"; return 0; }
    rsd::recipe::register_task \
        --name "task2" \
        --apply "task2_apply" \
        --rollback "task2_rollback"

    # Task 3 (fails, recovery=rollback)
    task3_apply() { return 1; }
    rsd::recipe::register_task \
        --name "task3" \
        --apply "task3_apply" \
        --recovery "rollback"

    run rsd::l::recipe::execute_engine 0 0

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

@test "rsd::l::recipe::handle_failure forward halts execution and prints rerunnable warnings" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_PRE
    declare -g -A RSD_TASKS_APPLY
    declare -g -A RSD_TASKS_RECOVERY

    task_apply() { return 1; }
    rsd::recipe::register_task \
        --name "fail_task" \
        --apply "task_apply" \
        --recovery "forward"

    run rsd::l::recipe::execute_engine 0 0

    [ "$status" -eq 10 ]
    [[ "$output" == *"Recovery Mode: FORWARD."* ]]
    [[ "$output" == *"Please resolve the environmental issue, then run the recipe again."* ]]
    [[ "$output" == *"Already satisfied steps will be automatically skipped."* ]]
}
