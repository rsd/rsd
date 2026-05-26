#!/usr/bin/env bats

# Tests for the eval_hook dispatcher and taint guard (recipe.lib v0.3.0)
# Tests for recipe-specific helpers (install_pkg)
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

# ==============================================================================
# eval_hook dispatcher — legacy compatibility
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

# ==============================================================================
# eval_hook — taint guard: metacharacter rejection
# ==============================================================================

@test "eval_hook TAINT: rejects semicolon injection" {
    safe_func() { return 0; }
    run rsd::l::recipe::eval_hook "safe_func; echo INJECTED"
    [ "$status" -eq 2 ]
    [[ "$output" == *"TAINT"* ]]
    [[ "$output" == *"forbidden shell metacharacters"* ]]
}

@test "eval_hook TAINT: rejects pipe injection" {
    safe_func() { return 0; }
    run rsd::l::recipe::eval_hook "safe_func | malicious_cmd"
    [ "$status" -eq 2 ]
    [[ "$output" == *"TAINT"* ]]
}

@test "eval_hook TAINT: rejects backtick command substitution" {
    safe_func() { return 0; }
    run rsd::l::recipe::eval_hook 'safe_func `whoami`'
    [ "$status" -eq 2 ]
    [[ "$output" == *"TAINT"* ]]
}

@test "eval_hook TAINT: rejects dollar-paren command substitution" {
    safe_func() { return 0; }
    run rsd::l::recipe::eval_hook 'safe_func $(whoami)'
    [ "$status" -eq 2 ]
    [[ "$output" == *"TAINT"* ]]
}

# ==============================================================================
# eval_hook — taint guard: function existence validation
# ==============================================================================

@test "eval_hook TAINT: rejects non-existent function names" {
    run rsd::l::recipe::eval_hook "__rsd_nonexistent_function_xyz__"
    [ "$status" -eq 2 ]
    [[ "$output" == *"TAINT"* ]]
    [[ "$output" == *"not a declared function"* ]]
}

@test "eval_hook TAINT: catches typos in function names" {
    run rsd::l::recipe::eval_hook "rsd::l::target::haz_bin bash"
    [ "$status" -eq 2 ]
    [[ "$output" == *"TAINT"* ]]
}

# ==============================================================================
# eval_hook — legitimate usage passes taint guard
# ==============================================================================

@test "eval_hook TAINT: allows dollar-sign variable references in arguments" {
    test_func() { echo "OK"; return 0; }
    run rsd::l::recipe::eval_hook 'test_func $HOME'
    [ "$status" -eq 0 ]
    [[ "$output" == *"OK"* ]]
}

@test "eval_hook TAINT: allows target library functions with arguments" {
    run rsd::l::recipe::eval_hook "rsd::l::target::has_bin bash"
    [ "$status" -eq 0 ]
}

# ==============================================================================
# execute_engine integration with inline-argument hooks and taint guard
# ==============================================================================

@test "execute_engine works with inline-argument hooks through taint guard" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_PRE
    declare -g -A RSD_TASKS_APPLY
    declare -g -A RSD_TASKS_POST
    declare -g -A RSD_TASKS_RECOVERY

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

@test "full engine cycle using target::has_bin pre-check skips satisfied tasks" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_PRE
    declare -g -A RSD_TASKS_APPLY
    declare -g -A RSD_TASKS_POST
    declare -g -A RSD_TASKS_RECOVERY

    dummy_apply() { echo "SHOULD_NOT_RUN"; return 0; }

    rsd::recipe::register_task \
        --name "test_has_bin_bash" \
        --pre-check "rsd::l::target::has_bin bash" \
        --apply "dummy_apply" \
        --recovery "forward"

    run rsd::l::recipe::execute_engine 0 0

    [ "$status" -eq 0 ]
    [[ "$output" == *"Task 'test_has_bin_bash' is already satisfied."* ]]
    [[ "$output" != *"SHOULD_NOT_RUN"* ]]
}
