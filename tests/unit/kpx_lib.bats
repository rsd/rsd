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
    
    # Mock dynamic gpg command with capabilities to satisfy auto-sourcing gpg.lib check on startup
    gpg() {
        if [[ "$*" == *"--list-keys"* ]]; then
            echo "pub:u:2048:1:D8A3C4E5F67890AB:2026-05-24::::::esc:"
            echo "fpr:::::::::2B9D4C7E8A0F1E2D3C4B5A6F7E8D9C0B1A2C3D4E:"
            return 0
        fi
        return 1
    }
    export -f gpg
    
    # Source core framework
    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/kpx.lib"
}

@test "rsd::l::kpx::check returns success when keepassxc-cli is available" {
    # Mock check_binary to simulate success
    rsd::check_binary() {
        [ "$1" = "keepassxc-cli" ] && return 0
        return 1
    }
    
    run rsd::l::kpx::check 1
    [ "$status" -eq 0 ]
}

@test "rsd::l::kpx::check returns failure when keepassxc-cli is missing" {
    # Mock check_binary to simulate failure
    rsd::check_binary() {
        return 1
    }
    
    run rsd::l::kpx::check 1
    [ "$status" -eq 1 ]
}
