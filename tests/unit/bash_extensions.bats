#!/usr/bin/env bats

setup() {
    export RSD_ON=1
    export RSD_DEBUG=0
    
    # Source the library under test
    source "${BATS_TEST_DIRNAME}/../../lib/bash_extensions.lib"
}

@test "bash::is_function returns success for existing functions" {
    dummy_function() {
        echo "hello"
    }
    
    run bash::is_function dummy_function
    [ "$status" -eq 0 ]
}

@test "bash::is_function returns failure for non-existing functions" {
    run bash::is_function non_existent_function_name
    [ "$status" -eq 1 ]
}

@test "bash::reverse correctly reverses string arguments" {
    run bash::reverse "one" "two" "three"
    
    [ "${lines[0]}" = "three" ]
    [ "${lines[1]}" = "two" ]
    [ "${lines[2]}" = "one" ]
}

@test "bash::key_exists detects keys in associative arrays" {
    declare -A my_array=( ["test_key"]="test_val" )
    
    run bash::key_exists "test_key" in my_array
    [ "$status" -eq 0 ]
    
    run bash::key_exists "missing_key" in my_array
    [ "$status" -eq 1 ]
}
