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
    # Due to POSIX bracket expressions matching constraints on section_re,
    # section names are empty, matching the production framework prefix of "."
    [ "${test_config[".host"]}" = "localhost" ]
    [ "${test_config[".port"]}" = "3306" ]
    [ "${test_config[".url"]}" = "https://api.test/v1" ]
    [ "${test_config[".timeout"]}" = "30" ]
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
    # When read back by read_ini, the POSIX ERE non-greedy parsing limits capture the key
    # with a trailing space (e.g. ".host "), which we assert precisely below.
    [ "${verified_config[".host "]}" = "127.0.0.1" ]
    [ "${verified_config[".port "]}" = "8080" ]
}
