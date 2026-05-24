#!/usr/bin/env bats

setup() {
    export RSD_ON=1
    export RSD_DEBUG=0
    
    # Initialize framework search path directories before sourcing
    export RSD_MODE="devel"
    export RSD_RUN_DIR="${BATS_TEST_DIRNAME}/../../"
    declare -ga RSD_LIBRARY_SEARCH_PATH
    RSD_LIBRARY_SEARCH_PATH+=("${BATS_TEST_DIRNAME}/../../")
    
    # Declare global associative arrays
    declare -g -A RSD_ARGS
    declare -g -A RSD_COMMAND_ARGS
    declare -g -A RSD_ARGS_PARAM
    
    # Stub create search path to allow sourcing
    rsd::create_search_path() {
        return 0
    }
    
    # Source core framework
    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
}

@test "rsd::arguments_or_usage returns success when argument bounds are met" {
    # Expect 2 arguments, we provide 2 ("arg1" "arg2")
    run rsd::arguments_or_usage 2 "arg1" "arg2"
    [ "$status" -eq 0 ]
}

@test "rsd::arguments_or_usage exits with bad usage when bounds are not met" {
    # Mock usage helper to prevent process exit
    rsd::usage() {
        echo "usage warning"
        return 0
    }
    
    # Expect 3 arguments, we provide 2
    run rsd::arguments_or_usage 3 "arg1" "arg2"
    
    [ "$status" -eq 0 ] # since we mocked usage to return 0
    [[ "$output" == *"Abort! Missing required arguments"* ]]
}

@test "rsd::check_command locates registered framework commands" {
    run rsd::check_command "test"
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"command/test"* ]]
}

@test "rsd::check_command fails for non-existent commands" {
    run rsd::check_command "non_existent_command_xyz"
    [ "$status" -eq 1 ]
}

@test "rsd::list_all_commands returns registered command names" {
    run rsd::list_all_commands
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"gpg"* ]]
    [[ "$output" == *"kpx"* ]]
    [[ "$output" == *"test"* ]]
}

@test "Library direct execution blocks with exit 12" {
    # Unset RSD_ON explicitly for direct execution check, avoiding host state leak
    run env -u RSD_ON bash "${BATS_TEST_DIRNAME}/../../lib/gpg.lib"
    
    [ "$status" -eq 12 ]
    [[ "$output" == *"This is a RSD library file. It should not be executed directly."* ]]
}
