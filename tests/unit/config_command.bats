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
    
    # Source core libraries and our new files
    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/config.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/io.lib"
    source "${BATS_TEST_DIRNAME}/../../command/config"
}

@test "rsd::l::config::set_conf_value sets and updates key-value pairs atomically in .conf files" {
    local conf_file="${BATS_TEST_TMPDIR}/rsd.conf"
    
    # 1. Test set on non-existing file (initial creation)
    run rsd::l::config::set_conf_value "$conf_file" "RSD_GPG_USER_ID" "test@jumba"
    [ "$status" -eq 0 ]
    [ -f "$conf_file" ]
    run grep "^RSD_GPG_USER_ID=" "$conf_file"
    [ "$status" -eq 0 ]
    [ "$output" = 'RSD_GPG_USER_ID="test@jumba"' ]

    # 2. Test updating an existing value
    run rsd::l::config::set_conf_value "$conf_file" "RSD_GPG_USER_ID" "updated@jumba"
    [ "$status" -eq 0 ]
    run grep "^RSD_GPG_USER_ID=" "$conf_file"
    [ "$status" -eq 0 ]
    [ "$output" = 'RSD_GPG_USER_ID="updated@jumba"' ]
    
    # 3. Test appending a second distinct value
    run rsd::l::config::set_conf_value "$conf_file" "RSD_DEBUG" "3"
    [ "$status" -eq 0 ]
    run grep "^RSD_DEBUG=" "$conf_file"
    [ "$status" -eq 0 ]
    [ "$output" = 'RSD_DEBUG="3"' ]
    
    # Check that both exist in the file
    local count
    count=$(grep -c "=" "$conf_file")
    [ "$count" -eq 2 ]
}

@test "rsd::c::config::get and set manages global .conf parameters correctly" {
    export RSD_CONFIG_DIR="${BATS_TEST_TMPDIR}/global_config"
    mkdir -p "$RSD_CONFIG_DIR"
    
    # Set active shell env variable manually first
    export RSD_TEST_GLOBAL="env_value"
    
    # 1. Get from active env
    run rsd::c::config::get "RSD_TEST_GLOBAL"
    [ "$status" -eq 0 ]
    [ "$output" = "env_value" ]

    # 2. Get a missing global variable
    run rsd::c::config::get "RSD_MISSING_GLOBAL"
    [ "$status" -eq 10 ]
    
    # 3. Set a global variable to the conf file
    run rsd::c::config::set "RSD_GPG_USER_ID" "config_tester"
    [ "$status" -eq 0 ]
    [ -f "$RSD_CONFIG_DIR/rsd.conf" ]
    
    # Check the file contents
    run grep "^RSD_GPG_USER_ID=" "$RSD_CONFIG_DIR/rsd.conf"
    [ "$status" -eq 0 ]
    [ "$output" = 'RSD_GPG_USER_ID="config_tester"' ]
}

@test "rsd::c::config::get and set manages modular .ini parameters correctly" {
    export RSD_CONFIG_DIR="${BATS_TEST_TMPDIR}/ini_config"
    mkdir -p "$RSD_CONFIG_DIR"
    
    # 1. Set a modular INI config: remote.host1.user = raul
    run rsd::c::config::set "remote.host1.user" "raul"
    [ "$status" -eq 0 ]
    [ -f "$RSD_CONFIG_DIR/remote.ini" ]
    
    # Assert correct INI structure is written
    run cat "$RSD_CONFIG_DIR/remote.ini"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[host1]"* ]]
    [[ "$output" == *"user = raul"* ]]
    
    # 2. Add another key to the same section in remote.ini
    run rsd::c::config::set "remote.host1.port" "2222"
    [ "$status" -eq 0 ]
    
    # 3. Read back remote.host1.user using config get
    # Note: We need to override RSD_LIBRARY_SEARCH_PATH search so rsd::config::get_file resolves the test dir
    # config resolution search path resolves config_dir first, so it will work fine!
    run rsd::c::config::get "remote.host1.user"
    [ "$status" -eq 0 ]
    [ "$output" = "raul" ]
    
    # Read back remote.host1.port
    run rsd::c::config::get "remote.host1.port"
    [ "$status" -eq 0 ]
    [ "$output" = "2222" ]
}

@test "rsd::c::config::list lists all active and loaded configurations" {
    export RSD_CONFIG_DIR="${BATS_TEST_TMPDIR}/list_config"
    mkdir -p "$RSD_CONFIG_DIR"
    
    # Set a few global variables in env
    export RSD_CUSTOM_VAR1="val1"
    export RSD_CUSTOM_VAR2="val2"
    
    # Setup a mock module ini array
    declare -g -A R_INI_mock
    R_INI_mock["sec1.key1"]="value1"
    R_INI_mock["sec1.key2"]="value2"
    
    run rsd::c::config::list
    [ "$status" -eq 0 ]
    [[ "$output" == *"RSD_CUSTOM_VAR1=val1"* ]]
    [[ "$output" == *"RSD_CUSTOM_VAR2=val2"* ]]
    [[ "$output" == *"mock.sec1.key1=value1"* ]]
    [[ "$output" == *"mock.sec1.key2=value2"* ]]
}

@test "rsd::c::config::set masks secret values in log output" {
    export RSD_CONFIG_DIR="${BATS_TEST_TMPDIR}/mask_config"
    mkdir -p "$RSD_CONFIG_DIR"

    # Define _run_io_inner in local test scope to capture fd 7
    _run_io_inner() {
        exec 7>&1
        "$@"
    }

    # 1. Set global GPG user ID (not a secret keyword, should show value)
    run _run_io_inner rsd::c::config::set "RSD_GPG_USER_ID" "test_id"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Successfully set 'RSD_GPG_USER_ID' to 'test_id'"* ]]

    # 2. Set global secret variable (secret, should show masked)
    run _run_io_inner rsd::c::config::set "RSD_MY_PASSWORD" "my_super_secret"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Successfully set 'RSD_MY_PASSWORD' to '********'"* ]]
    [[ "$output" != *"my_super_secret"* ]]

    # 3. Set modular INI config secret (secret, should show masked)
    run _run_io_inner rsd::c::config::set "mysql.chronos.pwd" "secret_pass"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Successfully set 'chronos.pwd' to '********'"* ]]
    [[ "$output" != *"secret_pass"* ]]
}
