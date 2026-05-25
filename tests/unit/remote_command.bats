#!/usr/bin/env bats

setup() {
    export RSD_ON=1
    export RSD_DEBUG=0
    export RSD_MODE="devel"
    export RSD_RUN_DIR="${BATS_TEST_DIRNAME}/../../"
    
    declare -ga RSD_LIBRARY_SEARCH_PATH
    RSD_LIBRARY_SEARCH_PATH+=("${BATS_TEST_DIRNAME}/../../")

    # Stub create search path to allow sourcing rsd.lib
    rsd::create_search_path() {
        return 0
    }

    # Source dependencies
    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/config.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/remote.lib"
    source "${BATS_TEST_DIRNAME}/../../command/remote"
}

@test "rsd::c::remote::check fails if RSD_REMOTE_TARGET is empty" {
    unset RSD_REMOTE_TARGET
    run rsd::c::remote::check
    [ "$status" -eq 2 ]
}

@test "rsd::c::remote::check passes if target has all mandatory binaries" {
    export RSD_REMOTE_TARGET="mock-target"
    
    # Mock remote execution returning success
    rsd::l::remote::execute() {
        local target="$1"
        local cmd="$2"
        if [[ "$cmd" == "bash" && "$3" == "-s" ]]; then
            echo "OK"
            return 0
        fi
        return 1
    }
    
    run rsd::c::remote::check
    [ "$status" -eq 0 ]
    
    unset RSD_REMOTE_TARGET
}

@test "rsd::c::remote::check fails and outputs missing programs when dependencies are not met" {
    export RSD_REMOTE_TARGET="mock-target"
    
    # Mock remote execution returning dependency failures
    rsd::l::remote::execute() {
        local target="$1"
        local cmd="$2"
        if [[ "$cmd" == "bash" && "$3" == "-s" ]]; then
            echo "FAILED:tar openssl"
            return 1
        fi
        return 1
    }
    
    run rsd::c::remote::check
    [ "$status" -eq 3 ]
    [[ "$output" == *"missing required installer binaries: tar openssl"* ]]
    
    unset RSD_REMOTE_TARGET
}

@test "rsd::c::remote::install runs checks first and triggers bootstrapping on success" {
    export RSD_REMOTE_TARGET="mock-target"
    
    # Mock rsd::c::remote::check to return success
    rsd::c::remote::check() {
        return 0
    }
    
    # Mock bootstrap install tracker
    rsd::l::remote::bootstrap_install() {
        local target="$1"
        local mode="$2"
        if [[ "$target" == "mock-target" && "$mode" == "local" ]]; then
            echo "BOOTSTRAP_SUCCESS"
            return 0
        fi
        return 1
    }
    
    run rsd::c::remote::install "local"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BOOTSTRAP_SUCCESS"* ]]
    
    unset RSD_REMOTE_TARGET
}

@test "rsd::c::remote::verify validates remote responsive framework version checks" {
    export RSD_REMOTE_TARGET="mock-target"
    
    # Mock remote framework check returning responsive version
    rsd::l::remote::execute() {
        local target="$1"
        local cmd="$2"
        if [[ "$cmd" == "\$HOME/.local/bin/rsd" && "$3" == "--version" ]]; then
            echo "1.9.11"
            return 0
        fi
        return 1
    }
    
    run rsd::c::remote::verify
    [ "$status" -eq 0 ]
    [[ "$output" == *"RSD is responsive at \$HOME/.local/bin/rsd (v1.9.11)"* ]]
    
    unset RSD_REMOTE_TARGET
}
