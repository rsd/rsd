#!/usr/bin/env bats

setup() {
    export RSD_ON=1
    export RSD_DEBUG=0
    export RSD_MODE="devel"
    export RSD_RUN_DIR="${BATS_TEST_DIRNAME}/../../"
    
    declare -ga RSD_LIBRARY_SEARCH_PATH
    RSD_LIBRARY_SEARCH_PATH+=("${BATS_TEST_DIRNAME}/../../")

    # Stub create search path
    rsd::create_search_path() {
        return 0
    }

    # Source dependencies
    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/config.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/kpx.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/sudo.lib"
}

@test "rsd::l::sudo::get_password retrieves password from session cache" {
    declare -gA RSD_SUDO_PASSWORDS
    RSD_SUDO_PASSWORDS["root@localhost"]="secret123"

    local password=""
    rsd::l::sudo::get_password "localhost" "root" password

    [ "$password" = "secret123" ]
}

@test "rsd::l::sudo::get_password falls back to mock override when set" {
    export RSD_MOCK_SUDO_PASSWORD="mocked-password"

    local password=""
    rsd::l::sudo::get_password "some-host" "some-user" password

    [ "$password" = "mocked-password" ]
    unset RSD_MOCK_SUDO_PASSWORD
}

@test "rsd::l::sudo::run configures secure SUDO_ASKPASS pipeline when password is found" {
    export RSD_MOCK_SUDO_PASSWORD="mypassword"

    # Mock sudo command to verify it was called with askpass
    sudo() {
        # Check that SUDO_ASKPASS is configured and points to a script that prints our password
        [ -n "$SUDO_ASKPASS" ]
        [ -x "$SUDO_ASKPASS" ]
        local askpass_out
        askpass_out=$("$SUDO_ASKPASS")
        [ "$askpass_out" = "mypassword" ]
        [ "$1" = "-A" ]
        [ "$2" = "whoami" ]
        echo "MOCKED_ELEVATED"
        return 0
    }

    run rsd::l::sudo::run "" "whoami"

    [ "$status" -eq 0 ]
    [ "$output" = "MOCKED_ELEVATED" ]
    
    # Verify environment variables were cleaned up
    [ -z "$SUDO_ASKPASS" ]
    [ -z "$RSD_SUDO_PASS" ]
    
    unset RSD_MOCK_SUDO_PASSWORD
}
