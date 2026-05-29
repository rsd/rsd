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

@test "rsd::r::register_task registers task with default forward recovery" {
    # Clean registers
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY

    # Declare the apply function
    function rsd::r::taskA() { return 0; }

    rsd::r::register_task "taskA"
    [ "${#RSD_REGISTERED_TASKS[@]}" -eq 1 ]
    [ "${RSD_REGISTERED_TASKS[0]}" = "taskA" ]
    [ "${RSD_TASKS_RECOVERY["taskA"]}" = "forward" ]
}

@test "rsd::r::register_task registers task with explicit recovery mode" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY

    # Declare apply + rollback functions
    function rsd::r::taskB() { return 0; }
    function rsd::r::taskB::rollback() { return 0; }

    rsd::r::register_task "taskB" "rollback"
    [ "${RSD_TASKS_RECOVERY["taskB"]}" = "rollback" ]
}

@test "rsd::r::register_task fails when apply function is not declared" {
    RSD_REGISTERED_TASKS=()

    run rsd::r::register_task "nonexistent_task"
    [ "$status" -eq 11 ]
}

@test "rsd::r::register_task fails when recovery=rollback but no rollback function" {
    RSD_REGISTERED_TASKS=()

    # Declare apply but NOT rollback
    function rsd::r::taskC() { return 0; }

    run rsd::r::register_task "taskC" "rollback"
    [ "$status" -eq 11 ]
}

@test "rsd::l::r::execute_engine executes tasks sequentially and respects pre-check necessity skips" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY

    # Task 1: should skip because pre-check succeeds
    function rsd::r::task1::pre_check() { return 0; }
    function rsd::r::task1() { echo "EXEC_1"; return 0; }

    # Task 2: should run because pre-check fails
    function rsd::r::task2::pre_check() { return 1; }
    function rsd::r::task2() { echo "EXEC_2"; return 0; }

    rsd::r::register_task "task1"
    rsd::r::register_task "task2"

    run rsd::l::r::execute_engine 0 0

    [ "$status" -eq 0 ]
    [[ "$output" == *"Task 'task1' is already satisfied."* ]]
    [[ "$output" == *"Executing task 'task2'"* ]]
    [[ "$output" == *"task2' applied successfully."* ]]
    [[ "$output" != *"EXEC_1"* ]]
    [[ "$output" == *"EXEC_2"* ]]
}

@test "rsd::l::r::execute_engine ignores failure on non-critical tasks (soft-failures)" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY

    # Register soft-failure task
    function rsd::r::optional_task() { return 1; }
    rsd::r::register_task "optional_task" "ignore"

    # Register following task
    function rsd::r::next_task() { echo "NEXT_EXEC"; return 0; }
    rsd::r::register_task "next_task"

    run rsd::l::r::execute_engine 0 0

    [ "$status" -eq 0 ]
    [[ "$output" == *"Task 'optional_task' failed. Skipping optional step."* ]]
    [[ "$output" == *"Executing task 'next_task'"* ]]
    [[ "$output" == *"NEXT_EXEC"* ]]
}

@test "rsd::l::r::execute_engine runs tasks without pre_check unconditionally" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY

    # Task with no pre_check — should always run
    function rsd::r::always_run() { echo "ALWAYS"; return 0; }
    rsd::r::register_task "always_run"

    run rsd::l::r::execute_engine 0 0

    [ "$status" -eq 0 ]
    [[ "$output" == *"ALWAYS"* ]]
    [[ "$output" == *"Task 'always_run' applied successfully."* ]]
}

@test "rsd::l::r::execute_engine dry-run mode does not execute apply" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY

    function rsd::r::dry_task::pre_check() { return 1; }
    function rsd::r::dry_task() { echo "SHOULD_NOT_APPEAR"; return 0; }
    rsd::r::register_task "dry_task"

    run rsd::l::r::execute_engine 1 0

    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY-RUN] Would apply task 'dry_task'"* ]]
    [[ "$output" != *"SHOULD_NOT_APPEAR"* ]]
}

@test "rsd::c::recipe::list outputs basenames of recipes in search paths" {
    # 1. Create an isolated mock recipe library directory
    local mock_libdir
    mock_libdir=$(mktemp -d -t rsd-recipe-test.XXXXXX)
    mkdir -p "${mock_libdir}/lib/recipe"
    touch "${mock_libdir}/lib/recipe/test_recipe_A.recipe"
    touch "${mock_libdir}/lib/recipe/test_recipe_B.recipe"

    # 2. Configure path array
    local -a old_path
    old_path=("${RSD_LIBRARY_SEARCH_PATH[@]}")
    RSD_LIBRARY_SEARCH_PATH=("${mock_libdir}")

    # Load recipe command
    source "${BATS_TEST_DIRNAME}/../../command/recipe"

    run rsd::c::recipe::list

    # Restore path array and cleanup
    RSD_LIBRARY_SEARCH_PATH=("${old_path[@]}")
    rm -rf "$mock_libdir"

    [ "$status" -eq 0 ]
    [[ "$output" == *"=== Available Recipes ==="* ]]
    [[ "$output" == *"test_recipe_A"* ]]
    [[ "$output" == *"test_recipe_B"* ]]
}

@test "rsd::c::recipe::help compiles and displays tasks inside the specified recipe" {
    # 1. Create an isolated mock recipe library directory
    local mock_libdir
    mock_libdir=$(mktemp -d -t rsd-recipe-help.XXXXXX)
    mkdir -p "${mock_libdir}/lib/recipe"
    
    # Write mock recipe file content using convention-based API
    cat << 'EOF' > "${mock_libdir}/lib/recipe/test_help.recipe"
function rsd::r::test_help::register() {
    rsd::r::register_task "test_help::mock_task_1"
}

function rsd::r::test_help::mock_task_1::pre_check() { return 0; }
function rsd::r::test_help::mock_task_1() { return 0; }
EOF

    # 2. Configure path array
    local -a old_path
    old_path=("${RSD_LIBRARY_SEARCH_PATH[@]}")
    RSD_LIBRARY_SEARCH_PATH=("${mock_libdir}")

    # Load recipe command
    source "${BATS_TEST_DIRNAME}/../../command/recipe"

    run rsd::c::recipe::help "test_help"

    # Restore path array and cleanup
    RSD_LIBRARY_SEARCH_PATH=("${old_path[@]}")
    rm -rf "$mock_libdir"

    [ "$status" -eq 0 ]
    [[ "$output" == *"=== Recipe Overview: test_help ==="* ]]
    [[ "$output" == *"test_help::mock_task_1"* ]]
    [[ "$output" == *"Apply Function:  rsd::r::test_help::mock_task_1"* ]]
    [[ "$output" == *"Necessity Check: rsd::r::test_help::mock_task_1::pre_check"* ]]
    [[ "$output" == *"On Failure:      forward"* ]]
}

@test "rsd::c::recipe::help parses and displays top-level recipe inline comment block as rich documentation" {
    # 1. Create an isolated mock recipe library directory
    local mock_libdir
    mock_libdir=$(mktemp -d -t rsd-recipe-help-comments.XXXXXX)
    mkdir -p "${mock_libdir}/lib/recipe"
    
    # Write mock recipe file with a shebang and structured comments
    cat << 'EOF' > "${mock_libdir}/lib/recipe/test_comments.recipe"
#!/usr/bin/env bash

# ==============================================================================
# Test Recipe for Rich Comments
# ==============================================================================
#
# PURPOSE
# -------
# This is a mock recipe to verify that inline comment parsing works.
# It should strip hashes and spaces correctly.

function rsd::r::test_comments::register() {
    rsd::r::register_task "test_comments::mock_task"
}

function rsd::r::test_comments::mock_task() { return 0; }
EOF

    # 2. Configure path array
    local -a old_path
    old_path=("${RSD_LIBRARY_SEARCH_PATH[@]}")
    RSD_LIBRARY_SEARCH_PATH=("${mock_libdir}")

    # Load recipe command
    source "${BATS_TEST_DIRNAME}/../../command/recipe"

    run rsd::c::recipe::help "test_comments"

    # Restore path array and cleanup
    RSD_LIBRARY_SEARCH_PATH=("${old_path[@]}")
    rm -rf "$mock_libdir"

    [ "$status" -eq 0 ]
    
    # Assert human-readable formatted comments are present and stripped of comment prefix
    [[ "$output" == *"Test Recipe for Rich Comments"* ]]
    [[ "$output" == *"PURPOSE"* ]]
    [[ "$output" == *"This is a mock recipe to verify that inline comment parsing works."* ]]
    [[ "$output" == *"It should strip hashes and spaces correctly."* ]]
    
    # Verify we stopped parsing at the first line of code (i.e. we do not print bash function definition)
    [[ "$output" != *"rsd::r::test_comments::register"* ]]
    
    # Assert standard compiled task output still follows
    [[ "$output" == *"=== Recipe Overview: test_comments ==="* ]]
}

@test "rsd::c::recipe::list outputs relative paths for recipes in subfolders" {
    # 1. Create an isolated mock recipe library directory
    local mock_libdir
    mock_libdir=$(mktemp -d -t rsd-recipe-subfolders-test.XXXXXX)
    mkdir -p "${mock_libdir}/lib/recipe/category"
    touch "${mock_libdir}/lib/recipe/category/test_recipe_C.recipe"

    # 2. Configure path array
    local -a old_path
    old_path=("${RSD_LIBRARY_SEARCH_PATH[@]}")
    RSD_LIBRARY_SEARCH_PATH=("${mock_libdir}")

    # Load recipe command
    source "${BATS_TEST_DIRNAME}/../../command/recipe"

    run rsd::c::recipe::list

    # Restore path array and cleanup
    RSD_LIBRARY_SEARCH_PATH=("${old_path[@]}")
    rm -rf "$mock_libdir"

    [ "$status" -eq 0 ]
    [[ "$output" == *"category/test_recipe_C"* ]]
}

@test "rsd::r::include resolves subfolder recipes and calls their hook functions" {
    # 1. Create an isolated mock recipe library directory
    local mock_libdir
    mock_libdir=$(mktemp -d -t rsd-recipe-include.XXXXXX)
    mkdir -p "${mock_libdir}/lib/recipe/utils"
    
    # Write mock recipe using convention-based API
    cat << 'EOF' > "${mock_libdir}/lib/recipe/utils/sub_task.recipe"
function rsd::r::utils_sub_task::register() {
    rsd::r::register_task "utils_sub_task::do_thing"
}

function rsd::r::utils_sub_task::do_thing() { echo 'SUBFOLDER'; }
EOF

    # 2. Configure path array
    local -a old_path
    old_path=("${RSD_LIBRARY_SEARCH_PATH[@]}")
    RSD_LIBRARY_SEARCH_PATH=("${mock_libdir}")

    # Reset registers
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY

    # Load recipe command
    source "${BATS_TEST_DIRNAME}/../../command/recipe"

    rsd::r::include "utils/sub_task"

    # Restore path array and cleanup
    RSD_LIBRARY_SEARCH_PATH=("${old_path[@]}")
    rm -rf "$mock_libdir"

    [ "${#RSD_REGISTERED_TASKS[@]}" -eq 1 ]
    [ "${RSD_REGISTERED_TASKS[0]}" = "utils_sub_task::do_thing" ]
    [ "${RSD_TASKS_RECOVERY["utils_sub_task::do_thing"]}" = "forward" ]
}
