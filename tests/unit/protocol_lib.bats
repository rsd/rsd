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
    source "${BATS_TEST_DIRNAME}/../../lib/protocol.lib"
}

# ==============================================================================
# SSH Protocol Handler Tests
# ==============================================================================

@test "rsd::l::protocol::ssh::run builds connection target with user and host" {
    # Mock ssh to capture arguments
    ssh() {
        echo "SSH_ARGS: $*"
        return 0
    }

    # Disable vault and skip interactive TTY detection
    export RSD_VAULT_MODE="never"
    export RSD_KPX_LIB=0

    run rsd::l::protocol::ssh::run "deploy" "server1.example.com" "" "uname" "-a"

    [ "$status" -eq 0 ]
    [[ "$output" == *"deploy@server1.example.com"* ]]
    [[ "$output" == *"uname"* ]]
}

@test "rsd::l::protocol::ssh::run builds connection target host-only without user" {
    ssh() {
        echo "SSH_ARGS: $*"
        return 0
    }

    export RSD_VAULT_MODE="never"
    export RSD_KPX_LIB=0

    run rsd::l::protocol::ssh::run "" "server1.example.com" "" "hostname"

    [ "$status" -eq 0 ]
    # Should NOT contain '@' — no user prefix
    [[ "$output" != *"@server1"* ]]
    [[ "$output" == *"server1.example.com"* ]]
}

@test "rsd::l::protocol::ssh::run adds port option when port is specified" {
    ssh() {
        echo "SSH_ARGS: $*"
        return 0
    }

    export RSD_VAULT_MODE="never"
    export RSD_KPX_LIB=0

    run rsd::l::protocol::ssh::run "root" "server1" "2222" "ls"

    [ "$status" -eq 0 ]
    [[ "$output" == *"-p 2222"* ]]
}

@test "rsd::l::protocol::ssh::run propagates remote exit code" {
    ssh() {
        return 42
    }

    export RSD_VAULT_MODE="never"
    export RSD_KPX_LIB=0

    run rsd::l::protocol::ssh::run "" "server1" "" "false"

    [ "$status" -eq 42 ]
}

@test "rsd::l::protocol::ssh::run configures ASKPASS when vault provides password" {
    # Mock kpx::get_password to return a password
    rsd::l::kpx::get_password() {
        declare -n _out="$2"
        _out="vault-secret-123"
        return 0
    }

    ssh() {
        # Verify ASKPASS pipeline is configured
        [ -n "$SSH_ASKPASS" ]
        [ -x "$SSH_ASKPASS" ]
        [ "$SSH_ASKPASS_REQUIRE" = "force" ]
        local askpass_out
        askpass_out=$("$SSH_ASKPASS")
        [ "$askpass_out" = "vault-secret-123" ]
        echo "SSH_ASKPASS_CONFIGURED"
        return 0
    }

    export RSD_VAULT_MODE="opportunistic"
    export RSD_KPX_LIB=1

    run rsd::l::protocol::ssh::run "" "server1" "" "whoami"

    [ "$status" -eq 0 ]
    [[ "$output" == *"SSH_ASKPASS_CONFIGURED"* ]]

    # Verify cleanup
    [ -z "$SSH_ASKPASS" ]
    [ -z "$RSD_SSH_PASS" ]
    [ -z "$SSH_ASKPASS_REQUIRE" ]
}

@test "rsd::l::protocol::ssh::run preserves and restores DISPLAY" {
    rsd::l::kpx::get_password() {
        declare -n _out="$2"
        _out="some-password"
        return 0
    }

    export DISPLAY=":5.0"

    ssh() {
        # During execution, DISPLAY should be overridden for ASKPASS
        [ "$DISPLAY" = ":0.0" ]
        return 0
    }

    export RSD_VAULT_MODE="opportunistic"
    export RSD_KPX_LIB=1

    run rsd::l::protocol::ssh::run "" "host1" "" "true"

    [ "$status" -eq 0 ]
    # After cleanup, DISPLAY should be restored to original
    [ "$DISPLAY" = ":5.0" ]
}

@test "rsd::l::protocol::ssh::run skips vault when RSD_VAULT_MODE is never" {
    # This should NOT be called
    rsd::l::kpx::get_password() {
        echo "VAULT_WAS_CALLED — should not happen"
        return 0
    }

    ssh() {
        echo "SSH_RAN"
        return 0
    }

    export RSD_VAULT_MODE="never"
    export RSD_KPX_LIB=1

    run rsd::l::protocol::ssh::run "" "server1" "" "hostname"

    [ "$status" -eq 0 ]
    [[ "$output" == *"SSH_RAN"* ]]
    [[ "$output" != *"VAULT_WAS_CALLED"* ]]
}

@test "rsd::l::protocol::ssh::run probes user-specific vault entry first" {
    local probe_order=""
    rsd::l::kpx::get_password() {
        probe_order="${probe_order}${1};"
        return 1 # fail all lookups to see full probe sequence
    }

    ssh() {
        return 0
    }

    export RSD_VAULT_MODE="opportunistic"
    export RSD_KPX_LIB=1

    rsd::l::protocol::ssh::run "deploy" "webserver" "" "true"

    # Should probe user@host first, then host-only
    [[ "$probe_order" == "RemoteHosts/deploy@webserver;RemoteHosts/webserver;" ]]
}

# ==============================================================================
# LXC Protocol Handler Tests
# ==============================================================================

@test "rsd::l::protocol::lxc::run executes lxc-attach with container name" {
    # Override binary check — lxc-attach is mocked as a function
    rsd::check_binaries_or_fail() { return 0; }

    lxc-attach() {
        echo "LXC_ARGS: $*"
        return 0
    }

    run rsd::l::protocol::lxc::run "" "my-container" "" "cat" "/etc/hostname"

    [ "$status" -eq 0 ]
    [[ "$output" == *"-n my-container"* ]]
    [[ "$output" == *"cat"* ]]
}

@test "rsd::l::protocol::lxc::run adds user options when user is specified" {
    rsd::check_binaries_or_fail() { return 0; }

    lxc-attach() {
        echo "LXC_ARGS: $*"
        return 0
    }

    run rsd::l::protocol::lxc::run "www-data" "web-container" "" "ls"

    [ "$status" -eq 0 ]
    [[ "$output" == *"--clear-env"* ]]
    [[ "$output" == *"--user www-data"* ]]
}

@test "rsd::l::protocol::lxc::run propagates container exit code" {
    rsd::check_binaries_or_fail() { return 0; }

    lxc-attach() {
        return 7
    }

    run rsd::l::protocol::lxc::run "" "test-ct" "" "exit" "7"

    [ "$status" -eq 7 ]
}

# ==============================================================================
# Sudo Protocol Handler Tests
# ==============================================================================

@test "rsd::l::protocol::sudo::run delegates to sudo.lib for localhost" {
    source "${BATS_TEST_DIRNAME}/../../lib/sudo.lib"

    export RSD_MOCK_SUDO_PASSWORD="mypassword"

    sudo() {
        [ "$1" = "-A" ]
        local askpass_out
        askpass_out=$("$SUDO_ASKPASS")
        [ "$askpass_out" = "mypassword" ]
        echo "LOCAL_SUDO_RAN"
        return 0
    }

    run rsd::l::protocol::sudo::run "root" "localhost" "" "whoami"

    [ "$status" -eq 0 ]
    [[ "$output" == *"LOCAL_SUDO_RAN"* ]]
    unset RSD_MOCK_SUDO_PASSWORD
}

@test "rsd::l::protocol::sudo::run delegates to sudo.lib when host is empty" {
    source "${BATS_TEST_DIRNAME}/../../lib/sudo.lib"

    export RSD_MOCK_SUDO_PASSWORD="mypassword"

    sudo() {
        [ "$1" = "-A" ]
        echo "LOCAL_SUDO_EMPTY_HOST"
        return 0
    }

    run rsd::l::protocol::sudo::run "root" "" "" "id"

    [ "$status" -eq 0 ]
    [[ "$output" == *"LOCAL_SUDO_EMPTY_HOST"* ]]
    unset RSD_MOCK_SUDO_PASSWORD
}

@test "rsd::l::protocol::ssh::run avoids duplicate semicolons when command ends with semicolon" {
    ssh() {
        echo "SSH_COMMAND: $*"
        return 0
    }

    export RSD_VAULT_MODE="never"
    export RSD_KPX_LIB=0

    run rsd::l::protocol::ssh::run "" "server1" "" "echo 'test';"

    [ "$status" -eq 0 ]
    # The output should contain exactly one semicolon between test and exit
    [[ "$output" == *"echo 'test'; _rsd_rc="* ]]
    [[ "$output" != *";; _rsd_rc="* ]]
}

