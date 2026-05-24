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
    
    # Mock dynamic gpg command to satisfy initial checks
    gpg() {
        if [[ "$*" == *"--list-secret-keys"* || "$*" == *"--list-keys"* ]]; then
            return 0
        fi
        return 0
    }
    export -f gpg
    
    # Source core framework, library, and command module
    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/kpx.lib"
    source "${BATS_TEST_DIRNAME}/../../command/kpx"
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

@test "rsd::l::gpg::validate_agent_or_fail returns success when agent is active" {
    # Stub dependency check
    rsd::check_binaries_or_fail() {
        return 0
    }
    export -f rsd::check_binaries_or_fail
    
    gpg-connect-agent() {
        return 0
    }
    export -f gpg-connect-agent
    
    run rsd::l::gpg::validate_agent_or_fail
    [ "$status" -eq 0 ]
}

@test "rsd::l::gpg::validate_agent_or_fail launches agent when dead" {
    rsd::check_binaries_or_fail() {
        return 0
    }
    export -f rsd::check_binaries_or_fail
    
    gpg-connect-agent() {
        return 1
    }
    export -f gpg-connect-agent
    
    gpgconf() {
        if [[ "$*" == *"--launch gpg-agent"* ]]; then
            return 0
        fi
        return 1
    }
    export -f gpgconf
    
    run rsd::l::gpg::validate_agent_or_fail
    [ "$status" -eq 0 ]
}

@test "rsd::l::gpg::validate_agent_or_fail fails when agent cannot launch" {
    rsd::check_binaries_or_fail() {
        return 0
    }
    export -f rsd::check_binaries_or_fail
    
    gpg-connect-agent() {
        return 1
    }
    export -f gpg-connect-agent
    
    gpgconf() {
        return 1
    }
    export -f gpgconf
    
    run rsd::l::gpg::validate_agent_or_fail
    [ "$status" -eq 3 ]
}

@test "rsd::l::kpx::init aborts with 10 when GPG key is missing from keyring" {
    gpg() {
        if [[ "$*" == *"--list-secret-keys"* ]]; then
            return 1
        fi
        return 0
    }
    export -f gpg
    
    run rsd::l::kpx::init
    [ "$status" -eq 10 ]
}

@test "rsd::l::kpx::init builds atomic files inside isolated sandbox" {
    # Setup standard config path
    export RSD_CONFIG_DIR="${BATS_TEST_TMPDIR}/rsd_config"
    export RSD_GPG_USER_ID="test_user"
    mkdir -p "$RSD_CONFIG_DIR"
    
    gpg() {
        local arg
        for ((i=1; i<=$#; i++)); do
            if [[ "${!i}" == "--output" ]]; then
                local next_idx=$((i+1))
                touch "${!next_idx}"
                break
            fi
        done
        return 0
    }
    export -f gpg
    
    rsd::l::gpg::validate_agent_or_fail() {
        return 0
    }
    export -f rsd::l::gpg::validate_agent_or_fail
    
    rsd::l::kpx::check() {
        return 0
    }
    export -f rsd::l::kpx::check
    
    openssl() {
        echo "fake_entropy_secret_key"
    }
    export -f openssl
    
    keepassxc-cli() {
        if [[ "$1" == "db-create" ]]; then
            touch "${!#}"
        fi
        return 0
    }
    export -f keepassxc-cli
    
    run rsd::l::kpx::init
    echo "STATUS: $status"
    echo "OUTPUT: $output"
    [ "$status" -eq 0 ]
    
    # Assert that all three production files were atomically promoted to the config folder
    [ -f "$RSD_CONFIG_DIR/vault.key.gpg" ]
    [ -f "$RSD_CONFIG_DIR/recovery.key.gpg" ]
    [ -f "$RSD_CONFIG_DIR/vault.kdbx" ]
}

@test "rsd::l::kpx::get_password and add_password writes and reads entries securely" {
    export RSD_CONFIG_DIR="${BATS_TEST_TMPDIR}/rsd_config_credentials"
    export RSD_GPG_USER_ID="test_user"
    mkdir -p "$RSD_CONFIG_DIR"
    
    # Touch mock databases
    touch "$RSD_CONFIG_DIR/vault.key.gpg"
    touch "$RSD_CONFIG_DIR/vault.kdbx"
    
    rsd::l::gpg::validate_agent_or_fail() {
        return 0
    }
    export -f rsd::l::gpg::validate_agent_or_fail
    
    # Mock GPG decryption of master key
    gpg() {
        echo "MOCK GPG CALLED WITH $*" >&2
        if [[ "$*" == *"--decrypt"* ]]; then
            echo "mocked_master_key"
            return 0
        fi
        return 0
    }
    export -f gpg
    
    # Mock KeePassXC programmatic operations
    keepassxc-cli() {
        echo "MOCK KPX CALLED WITH $*" >&2
        if [[ "$*" == *"show -a Password"* ]]; then
            echo "my_safe_secret_password"
            return 0
        fi
        if [[ "$*" == *"add -p"* ]]; then
            return 0
        fi
        return 1
    }
    export -f keepassxc-cli
    
    # 1. Add secret to vault
    run rsd::l::kpx::add_password "SSH/host1" "raul" "my_safe_secret_password"
    echo "ADD STATUS: $status"
    echo "ADD OUTPUT: $output"
    [ "$status" -eq 0 ]
    
    # 2. Sourced retrieve secret
    local result
    run rsd::l::kpx::get_password "SSH/host1" result
    echo "GET STATUS: $status"
    echo "GET OUTPUT: $output"
    [ "$status" -eq 0 ]
    
    # Since run executes in a subshell, we look at lines or capture variables
    # Assert that the extracted password is correct
    run rsd::c::kpx::show "SSH/host1"
    echo "SHOW STATUS: $status"
    echo "SHOW OUTPUT: $output"
    [ "$output" = "my_safe_secret_password" ]
}

@test "rsd::l::kpx::rotate_key re-encrypts database vault keys atomically" {
    export RSD_CONFIG_DIR="${BATS_TEST_TMPDIR}/rsd_config_rotate"
    mkdir -p "$RSD_CONFIG_DIR"
    
    touch "$RSD_CONFIG_DIR/vault.key.gpg"
    touch "$RSD_CONFIG_DIR/recovery.key.gpg"
    
    gpg() {
        if [[ "$*" == *"--list-secret-keys"* ]]; then
            return 0
        fi
        if [[ "$*" == *"--decrypt"* ]]; then
            echo "master_key"
            return 0
        fi
        if [[ "$*" == *"--encrypt"* ]]; then
            # Write to --output file
            local arg
            for ((i=1; i<=$#; i++)); do
                if [[ "${!i}" == "--output" ]]; then
                    local next_idx=$((i+1))
                    touch "${!next_idx}"
                    break
                fi
            done
            return 0
        fi
        return 1
    }
    export -f gpg
    
    rsd::l::gpg::validate_agent_or_fail() {
        return 0
    }
    export -f rsd::l::gpg::validate_agent_or_fail
    
    run rsd::l::kpx::rotate_key "new_gpg_recipient_id"
    echo "ROTATE STATUS: $status"
    echo "ROTATE OUTPUT: $output"
    [ "$status" -eq 0 ]
    
    [ -f "$RSD_CONFIG_DIR/vault.key.gpg" ]
    [ -f "$RSD_CONFIG_DIR/recovery.key.gpg" ]
}
