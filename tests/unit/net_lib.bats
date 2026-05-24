#!/usr/bin/env bats

setup() {
    export RSD_ON=1
    export RSD_DEBUG=0
    
    # Initialize framework search path directories before sourcing
    export RSD_MODE="devel"
    export RSD_RUN_DIR="${BATS_TEST_DIRNAME}/../../"
    declare -ga RSD_LIBRARY_SEARCH_PATH
    RSD_LIBRARY_SEARCH_PATH+=("${BATS_TEST_DIRNAME}/../../")
    
    # Declare global associative arrays to prevent arithmetic syntax errors when evaluated with string keys
    declare -g -A RSD_ARGS
    declare -g -A RSD_COMMAND_ARGS
    declare -g -A RSD_ARGS_PARAM
    
    # Stub create search path to allow sourcing
    rsd::create_search_path() {
        return 0
    }
    
    # Source core framework and network library
    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/net.lib"
}

@test "rsd::l::net::hostname returns HOSTNAME variable if defined" {
    # Isolate environment variable
    local HOSTNAME="mocked-var-hostname"
    
    run rsd::l::net::hostname
    [ "$status" -eq 0 ]
    [ "$output" = "mocked-var-hostname" ]
}

@test "rsd::l::net::hostname falls back to system hostname command" {
    # Unset HOSTNAME variable to trigger fallbacks
    unset HOSTNAME
    
    # Mock system commands checks to target the hostname check
    rsd::check_binaries() {
        [ "$1" = "hostname" ] && return 0
        return 1
    }
    
    # Mock hostname utility
    hostname() {
        echo "mocked-bin-hostname"
    }
    export -f hostname
    
    run rsd::l::net::hostname
    [ "$status" -eq 0 ]
    [ "$output" = "mocked-bin-hostname" ]
}

@test "rsd::l::net::hostname falls back to localhost if all checks fail" {
    # Clear environment variables
    unset HOSTNAME
    unset COMPUTERNAME
    
    # Mock all system checks to fail
    rsd::check_binaries() {
        return 1
    }
    
    run rsd::l::net::hostname
    [ "$status" -eq 1 ] # net.lib returns exit code 1 on absolute fallback
    [ "$output" = "localhost" ]
}
