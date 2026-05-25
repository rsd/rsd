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

    # Source core wrapper dependencies and config
    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/config.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/recipe.lib"
}

@test "rsd::recipe::register_task registers properties correctly inside scoped variables" {
    # Clean registers
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_PRE
    declare -g -A RSD_TASKS_APPLY
    declare -g -A RSD_TASKS_POST
    declare -g -A RSD_TASKS_RECOVERY
    declare -g -A RSD_TASKS_ROLLBACK

    rsd::recipe::register_task \
        --name "taskA" \
        --pre-check "check_func" \
        --apply "apply_func" \
        --post-check "post_func" \
        --recovery "ignore" \
        --rollback "undo_func"
    [ "${#RSD_REGISTERED_TASKS[@]}" -eq 1 ]
    [ "${RSD_REGISTERED_TASKS[0]}" = "taskA" ]
    [ "${RSD_TASKS_PRE["taskA"]}" = "check_func" ]
    [ "${RSD_TASKS_APPLY["taskA"]}" = "apply_func" ]
    [ "${RSD_TASKS_POST["taskA"]}" = "post_func" ]
    [ "${RSD_TASKS_RECOVERY["taskA"]}" = "ignore" ]
    [ "${RSD_TASKS_ROLLBACK["taskA"]}" = "undo_func" ]
}

@test "rsd::recipe::register_task fails when name or apply parameters are missing" {
    RSD_REGISTERED_TASKS=()
    
    run rsd::recipe::register_task --apply "some_func"
    [ "$status" -eq 11 ]

    run rsd::recipe::register_task --name "some_name"
    [ "$status" -eq 11 ]
}

@test "rsd::l::recipe::execute_engine executes tasks sequentially and respects pre-check necessity skips" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_PRE
    declare -g -A RSD_TASKS_APPLY
    declare -g -A RSD_TASKS_POST
    declare -g -A RSD_TASKS_RECOVERY

    # Register Task 1 (should skip because pre-check succeeds)
    task1_pre() { return 0; }
    task1_apply() { echo "EXEC_1"; return 0; }
    
    rsd::recipe::register_task \
        --name "task1" \
        --pre-check "task1_pre" \
        --apply "task1_apply"

    # Register Task 2 (should run because pre-check fails)
    task2_pre() { return 1; }
    task2_apply() { echo "EXEC_2"; return 0; }
    task2_post() { return 0; }
    
    rsd::recipe::register_task \
        --name "task2" \
        --pre-check "task2_pre" \
        --apply "task2_apply" \
        --post-check "task2_post"

    run rsd::l::recipe::execute_engine 0 0

    [ "$status" -eq 0 ]
    [[ "$output" == *"Task 'task1' is already satisfied."* ]]
    [[ "$output" == *"Executing task 'task2'"* ]]
    [[ "$output" == *"task2' applied successfully."* ]]
    [[ "$output" != *"EXEC_1"* ]]
    [[ "$output" == *"EXEC_2"* ]]
}

@test "rsd::l::recipe::execute_engine ignores failure on non-critical tasks (soft-failures)" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_PRE
    declare -g -A RSD_TASKS_APPLY
    declare -g -A RSD_TASKS_RECOVERY

    # Register soft-failure task
    task_fail_apply() { return 1; }
    rsd::recipe::register_task \
        --name "optional_task" \
        --apply "task_fail_apply" \
        --recovery "ignore"

    # Register following task
    next_task_apply() { echo "NEXT_EXEC"; return 0; }
    rsd::recipe::register_task \
        --name "next_task" \
        --apply "next_task_apply"

    run rsd::l::recipe::execute_engine 0 0

    [ "$status" -eq 0 ]
    [[ "$output" == *"Task 'optional_task' failed. Skipping optional step."* ]]
    [[ "$output" == *"Executing task 'next_task'"* ]]
    [[ "$output" == *"NEXT_EXEC"* ]]
}
