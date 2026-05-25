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
    
    # Source core framework and config library
    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/config.lib"
    
    # Create a temporary directory for config files
    TEST_CONF_DIR=$(mktemp -d -t rsd-config.XXXXXX)
}

teardown() {
    rm -rf "$TEST_CONF_DIR"
}

@test "rsd::config::read_ini parses sections, keys, and values correctly" {
    local ini_file="${TEST_CONF_DIR}/test.ini"
    
    # Create a mock ini file
    cat <<EOF > "$ini_file"
# Global comment
; Another comment

[database]
host=localhost
port=3306

[api]
url=https://api.test/v1
timeout=30
EOF

    declare -A test_config
    # Call directly (not using the Bats 'run' subshell) to allow local nameref changes to propagate to test scope
    rsd::config::read_ini "$ini_file" test_config
    
    [ "$?" -eq 0 ]
    # Section matching correctly parses host and api sections using standard POSIX compliance.
    [ "${test_config["database.host"]}" = "localhost" ]
    [ "${test_config["database.port"]}" = "3306" ]
    [ "${test_config["api.url"]}" = "https://api.test/v1" ]
    [ "${test_config["api.timeout"]}" = "30" ]
}

@test "rsd::config::read_ini returns error for non-existent file" {
    declare -A test_config
    run rsd::config::read_ini "/non/existent/file.ini" test_config
    
    [ "$status" -eq 1 ]
}

@test "rsd::config::write_ini serializes array back to ini format correctly" {
    local ini_file="${TEST_CONF_DIR}/output.ini"
    
    declare -A my_config
    my_config[".host"]="127.0.0.1"
    my_config[".port"]="8080"
    
    rsd::config::write_ini "$ini_file" my_config
    [ "$?" -eq 0 ]
    [ -f "$ini_file" ]
    
    # Load and verify it parses back exactly without 'run' subshells
    declare -A verified_config
    rsd::config::read_ini "$ini_file" verified_config
    
    [ "$?" -eq 0 ]
    # Note: write_ini serializes with spaces around the equals sign (e.g. "host = 127.0.0.1").
    # The parser correctly resolves keys without trailing spaces.
    [ "${verified_config[".host"]}" = "127.0.0.1" ]
    [ "${verified_config[".port"]}" = "8080" ]
}

@test "rsd::config::get_file respects priority order: CLI override > workspace > user > system" {
    # Isolate parameters
    RSD_LIBRARY_SEARCH_PATH=()
    RSD_CONFIG_CONFIG_SEARCH_PATH=()
    RSD_MODE="devel"
    RSD_RUN_DIR="${TEST_CONF_DIR}/run"
    mkdir -p "$RSD_RUN_DIR/config"
    
    # Mock system configuration paths
    local mock_system="/etc/rsd/"
    local mock_user="$HOME/.config/rsd"
    local mock_workspace="$(pwd)/config"
    local mock_cli="${TEST_CONF_DIR}/cli"
    
    # Set RSD_ARGS simulating a command line --config-dir parameter
    RSD_ARGS["config-dir"]="$mock_cli"
    
    rsd::config::get_file
    
    # Assert size of the constructed array
    [ "${#RSD_CONFIGLIB_SEARCH_PATH[@]}" -gt 0 ]
    
    # Verify that CLI override has precedence over workspace, user, and system configs.
    # Therefore, CLI override must be at the very end of the array (processed last).
    local last_index=$(( ${#RSD_CONFIGLIB_SEARCH_PATH[@]} - 1 ))
    [ "${RSD_CONFIGLIB_SEARCH_PATH[$last_index]}" = "$mock_cli" ]
}
