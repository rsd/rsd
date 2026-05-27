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
    declare -gA RSD_SUDO_PASSWORDS_TS
    RSD_SUDO_PASSWORDS["root@localhost"]="secret123"
    RSD_SUDO_PASSWORDS_TS["root@localhost"]=$EPOCHSECONDS

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

@test "rsd::l::sudo::get_password reports source as 'mock' for mock override" {
    export RSD_MOCK_SUDO_PASSWORD="mocked"

    local password="" source=""
    rsd::l::sudo::get_password "host" "user" password source

    [ "$password" = "mocked" ]
    [ "$source" = "mock" ]
    unset RSD_MOCK_SUDO_PASSWORD
}

@test "rsd::l::sudo::get_password reports source as 'cache' for session cache" {
    declare -gA RSD_SUDO_PASSWORDS
    declare -gA RSD_SUDO_PASSWORDS_TS
    RSD_SUDO_PASSWORDS["root@myhost"]="cached-pass"
    RSD_SUDO_PASSWORDS_TS["root@myhost"]=$EPOCHSECONDS

    local password="" source=""
    rsd::l::sudo::get_password "myhost" "root" password source

    [ "$password" = "cached-pass" ]
    [ "$source" = "cache" ]
}

@test "rsd::l::sudo::get_password reports source as 'vault' when kpx returns password" {
    rsd::l::kpx::get_password() {
        declare -n _out="$2"
        _out="vault-secret"
        return 0
    }

    export RSD_VAULT_MODE="opportunistic"
    export RSD_KPX_LIB=1

    local password="" source=""
    rsd::l::sudo::get_password "server1" "" password source

    [ "$password" = "vault-secret" ]
    [ "$source" = "vault" ]
}

@test "rsd::l::sudo::get_password skips vault when RSD_VAULT_MODE is never" {
    rsd::l::kpx::get_password() {
        echo "VAULT_CALLED — should not happen"
        return 0
    }

    declare -gA RSD_SUDO_PASSWORDS
    declare -gA RSD_SUDO_PASSWORDS_TS
    RSD_SUDO_PASSWORDS["root@host"]="cached"
    RSD_SUDO_PASSWORDS_TS["root@host"]=$EPOCHSECONDS

    export RSD_VAULT_MODE="never"
    export RSD_KPX_LIB=1

    local password="" source=""
    rsd::l::sudo::get_password "host" "root" password source

    # Should skip vault and fall through to cache
    [ "$password" = "cached" ]
    [ "$source" = "cache" ]
}

@test "rsd::l::sudo::get_password works without optional 4th source parameter" {
    export RSD_MOCK_SUDO_PASSWORD="compat-test"

    local password=""
    rsd::l::sudo::get_password "host" "user" password

    [ "$password" = "compat-test" ]
    unset RSD_MOCK_SUDO_PASSWORD
}
