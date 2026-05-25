#!/usr/bin/env bats

setup() {
    export RSD_ON=1
    export RSD_DEBUG=0
    
    export RSD_MODE="devel"
    export RSD_RUN_DIR="${BATS_TEST_DIRNAME}/../../"
    declare -ga RSD_LIBRARY_SEARCH_PATH
    RSD_LIBRARY_SEARCH_PATH+=("${BATS_TEST_DIRNAME}/../../")
    
    declare -g -A RSD_ARGS
    declare -g -A RSD_COMMAND_ARGS
    declare -g -A RSD_ARGS_PARAM
    
    rsd::create_search_path() {
        return 0
    }
    
    # Source core libraries and our command files
    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/config.lib"
    source "${BATS_TEST_DIRNAME}/../../command/gpg"
    source "${BATS_TEST_DIRNAME}/../../command/kpx"
    source "${BATS_TEST_DIRNAME}/../../command/config"
    source "${BATS_TEST_DIRNAME}/../../command/init"
}

@test "rsd::c::init skips setups cleanly when GPG and KPX vault are already active" {
    # 1. Mock GPG check to return success
    rsd::l::gpg::check() {
        return 0
    }
    export -f rsd::l::gpg::check
    
    # 2. Mock KPX check and files existence
    export RSD_CONFIG_DIR="${BATS_TEST_TMPDIR}/init_exist"
    mkdir -p "$RSD_CONFIG_DIR"
    touch "$RSD_CONFIG_DIR/vault.key.gpg"
    touch "$RSD_CONFIG_DIR/vault.kdbx"
    
    rsd::check_binaries_or_fail() {
        return 0
    }
    export -f rsd::check_binaries_or_fail
    
    run rsd::c::init
    echo "STATUS: $status"
    echo "OUTPUT: $output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"KeePass credentials vault already exists"* ]]
    [[ "$output" == *"RSD ENVIRONMENT INITIALIZED SUCCESSFULLY"* ]]
}

@test "rsd::c::init option q aborts the setup flow cleanly without modifying files" {
    rsd::l::gpg::check() {
        return 1 # missing key
    }
    export -f rsd::l::gpg::check
    
    rsd::check_binaries_or_fail() {
        return 0
    }
    export -f rsd::check_binaries_or_fail
    
    # Mock user input to choose 'q' (abort)
    read() {
        local var_name="${@: -1}"
        eval "$var_name=\"q\""
        return 0
    }
    
    run rsd::c::init
    echo "STATUS: $status"
    echo "OUTPUT: $output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Initialization aborted by user"* ]]
}

@test "rsd::c::init option 1 generates dedicated GPG key and initializes KPX vault atomically" {
    export RSD_CONFIG_DIR="${BATS_TEST_TMPDIR}/init_opt1"
    mkdir -p "$RSD_CONFIG_DIR"
    export RSD_GPG_USER_ID="rsd_boot_test"
    
    # Pre-flight mocks
    rsd::check_binaries_or_fail() {
        return 0
    }
    export -f rsd::check_binaries_or_fail
    
    rsd::l::gpg::check() {
        return 1 # not ready
    }
    export -f rsd::l::gpg::check
    
    # Mock key creation
    rsd::c::gpg::create-key() {
        return 0
    }
    export -f rsd::c::gpg::create-key
    
    # Mock vault setup
    rsd::l::kpx::init() {
        touch "$RSD_CONFIG_DIR/vault.key.gpg"
        touch "$RSD_CONFIG_DIR/vault.kdbx"
        return 0
    }
    export -f rsd::l::kpx::init
    
    # Mock user choosing option 1
    read() {
        local var_name="${@: -1}"
        eval "$var_name=\"1\""
        return 0
    }
    
    run rsd::c::init
    echo "STATUS: $status"
    echo "OUTPUT: $output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"GPG key generated successfully"* ]]
    [[ "$output" == *"KeePass Vault initialized atomically"* ]]
    [ -f "$RSD_CONFIG_DIR/vault.key.gpg" ]
    [ -f "$RSD_CONFIG_DIR/vault.kdbx" ]
}

@test "rsd::c::init option 2 binds existing GPG key and initiates vault setup" {
    export RSD_CONFIG_DIR="${BATS_TEST_TMPDIR}/init_opt2"
    mkdir -p "$RSD_CONFIG_DIR"
    export RSD_GPG_USER_ID="rsd_boot_test"
    
    rsd::check_binaries_or_fail() {
        return 0
    }
    export -f rsd::check_binaries_or_fail
    
    rsd::l::gpg::check() {
        return 1 # not ready
    }
    export -f rsd::l::gpg::check
    
    # Mock system keyring lookup: simulate entered key exists
    gpg() {
        return 0
    }
    export -f gpg
    
    # Mock config writer
    rsd::c::config::set() {
        return 0
    }
    export -f rsd::c::config::set
    
    rsd::l::kpx::init() {
        touch "$RSD_CONFIG_DIR/vault.key.gpg"
        touch "$RSD_CONFIG_DIR/vault.kdbx"
        return 0
    }
    export -f rsd::l::kpx::init
    
    # Mock sequential reads:
    # First read (choice) -> "2"
    # Second read (key ID) -> "existing@key.com"
    local read_count=0
    read() {
        ((read_count++))
        local var_name="${@: -1}"
        if [ "$read_count" -eq 1 ]; then
            eval "$var_name=\"2\""
        else
            eval "$var_name=\"existing@key.com\""
        fi
        return 0
    }
    
    run rsd::c::init
    echo "STATUS: $status"
    echo "OUTPUT: $output"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Bound GPG key ID: 'existing@key.com'"* ]]
    [[ "$output" == *"KeePass Vault initialized"* ]]
    [ -f "$RSD_CONFIG_DIR/vault.key.gpg" ]
    [ -f "$RSD_CONFIG_DIR/vault.kdbx" ]
}
