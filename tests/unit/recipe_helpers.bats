#!/usr/bin/env bats

# Tests for the recipe helper abstractions introduced in recipe.lib v0.2.0
# @see lib/recipe.lib

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

    # Ensure RSD_REMOTE_TARGET is unset for local tests
    unset RSD_REMOTE_TARGET
}

# ==============================================================================
# eval_hook dispatcher
# ==============================================================================

@test "rsd::l::recipe::eval_hook dispatches a bare function name (legacy compat)" {
    my_hook() { echo "LEGACY_OK"; return 0; }
    run rsd::l::recipe::eval_hook "my_hook"
    [ "$status" -eq 0 ]
    [[ "$output" == *"LEGACY_OK"* ]]
}

@test "rsd::l::recipe::eval_hook dispatches a function with inline arguments" {
    my_param_hook() { echo "ARG=$1"; return 0; }
    run rsd::l::recipe::eval_hook "my_param_hook hello_world"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARG=hello_world"* ]]
}

@test "rsd::l::recipe::eval_hook propagates non-zero exit codes" {
    failing_hook() { return 42; }
    run rsd::l::recipe::eval_hook "failing_hook"
    [ "$status" -eq 42 ]
}

@test "rsd::l::recipe::execute_engine works with inline-argument hooks" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_PRE
    declare -g -A RSD_TASKS_APPLY
    declare -g -A RSD_TASKS_POST
    declare -g -A RSD_TASKS_RECOVERY

    # Pre-check with args: always satisfied
    check_with_arg() { [[ "$1" == "yes" ]]; }
    apply_with_arg() { echo "APPLIED_$1"; return 0; }

    rsd::recipe::register_task \
        --name "test_inline_skip" \
        --pre-check "check_with_arg yes" \
        --apply "apply_with_arg skipped"

    rsd::recipe::register_task \
        --name "test_inline_run" \
        --pre-check "check_with_arg no" \
        --apply "apply_with_arg executed"

    run rsd::l::recipe::execute_engine 0 0

    [ "$status" -eq 0 ]
    [[ "$output" == *"Task 'test_inline_skip' is already satisfied."* ]]
    [[ "$output" == *"APPLIED_executed"* ]]
    [[ "$output" != *"APPLIED_skipped"* ]]
}

# ==============================================================================
# has_bin helper (local mode)
# ==============================================================================

@test "rsd::l::recipe::helper::has_bin returns 0 for an existing binary" {
    run rsd::l::recipe::helper::has_bin bash
    [ "$status" -eq 0 ]
}

@test "rsd::l::recipe::helper::has_bin returns 1 for a missing binary" {
    run rsd::l::recipe::helper::has_bin __rsd_nonexistent_binary_xyz__
    [ "$status" -ne 0 ]
}

# ==============================================================================
# dir_exists helper (local mode)
# ==============================================================================

@test "rsd::l::recipe::helper::dir_exists returns 0 for existing directory" {
    run rsd::l::recipe::helper::dir_exists /tmp
    [ "$status" -eq 0 ]
}

@test "rsd::l::recipe::helper::dir_exists returns 1 for missing directory" {
    run rsd::l::recipe::helper::dir_exists /tmp/__rsd_nonexistent_dir_xyz__
    [ "$status" -ne 0 ]
}

# ==============================================================================
# file_exists helper (local mode)
# ==============================================================================

@test "rsd::l::recipe::helper::file_exists returns 0 for existing file" {
    local tmpfile
    tmpfile=$(mktemp -t rsd-test.XXXXXX)
    run rsd::l::recipe::helper::file_exists "$tmpfile"
    rm -f "$tmpfile"
    [ "$status" -eq 0 ]
}

@test "rsd::l::recipe::helper::file_exists returns 1 for missing file" {
    run rsd::l::recipe::helper::file_exists /tmp/__rsd_nonexistent_file_xyz__
    [ "$status" -ne 0 ]
}

# ==============================================================================
# file_contains helper (local mode)
# ==============================================================================

@test "rsd::l::recipe::helper::file_contains returns 0 when pattern matches" {
    local tmpfile
    tmpfile=$(mktemp -t rsd-test.XXXXXX)
    echo "hello world" > "$tmpfile"
    run rsd::l::recipe::helper::file_contains "hello" "$tmpfile"
    rm -f "$tmpfile"
    [ "$status" -eq 0 ]
}

@test "rsd::l::recipe::helper::file_contains returns 1 when pattern is absent" {
    local tmpfile
    tmpfile=$(mktemp -t rsd-test.XXXXXX)
    echo "hello world" > "$tmpfile"
    run rsd::l::recipe::helper::file_contains "goodbye" "$tmpfile"
    rm -f "$tmpfile"
    [ "$status" -ne 0 ]
}

# ==============================================================================
# git_clone helper (local mode)
# ==============================================================================

@test "rsd::l::recipe::helper::git_clone builds correct depth args" {
    # Stub git to capture its invocation
    git() { echo "GIT_ARGS=$*"; return 0; }
    export -f git

    run rsd::l::recipe::helper::git_clone "https://example.com/repo.git" "/tmp/dest" "1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"--depth"* ]]
    [[ "$output" == *"1"* ]]
    [[ "$output" == *"/tmp/dest"* ]]
}

@test "rsd::l::recipe::helper::git_clone omits depth when not specified" {
    git() { echo "GIT_ARGS=$*"; return 0; }
    export -f git

    run rsd::l::recipe::helper::git_clone "https://example.com/repo.git" "/tmp/dest"
    [ "$status" -eq 0 ]
    [[ "$output" != *"--depth"* ]]
    [[ "$output" == *"/tmp/dest"* ]]
}

# ==============================================================================
# run_cmd helper (local mode)
# ==============================================================================

@test "rsd::l::recipe::helper::run_cmd executes local commands in local mode" {
    run rsd::l::recipe::helper::run_cmd echo "PASSTHROUGH_OK"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PASSTHROUGH_OK"* ]]
}

# ==============================================================================
# Integration: full engine cycle with helpers
# ==============================================================================

@test "full engine cycle using helpers: has_bin pre-check skips satisfied tasks" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_PRE
    declare -g -A RSD_TASKS_APPLY
    declare -g -A RSD_TASKS_POST
    declare -g -A RSD_TASKS_RECOVERY

    dummy_apply() { echo "SHOULD_NOT_RUN"; return 0; }

    rsd::recipe::register_task \
        --name "test_has_bin_bash" \
        --pre-check "rsd::l::recipe::helper::has_bin bash" \
        --apply "dummy_apply" \
        --recovery "forward"

    run rsd::l::recipe::execute_engine 0 0

    [ "$status" -eq 0 ]
    [[ "$output" == *"Task 'test_has_bin_bash' is already satisfied."* ]]
    [[ "$output" != *"SHOULD_NOT_RUN"* ]]
}
