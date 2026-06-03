#!/usr/bin/env bats

# Tests for the timezone management library (lib/timezone.lib)
# @see lib/timezone.lib

setup() {
    export RSD_ON=1
    export RSD_DEBUG=0
    export RSD_MODE="devel"
    export RSD_RUN_DIR="${BATS_TEST_DIRNAME}/../../"

    declare -ga RSD_LIBRARY_SEARCH_PATH
    RSD_LIBRARY_SEARCH_PATH+=("${BATS_TEST_DIRNAME}/../../")

    rsd::create_search_path() {
        return 0
    }

    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/config.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/timezone.lib"

    # Ensure local execution mode for all tests
    unset RSD_REMOTE_TARGET
}

# Helper: run capturing fd 7 (rsd::io) in $output
_run_io() {
    _run_io_inner() { exec 7>&1; "$@"; }
    run _run_io_inner "$@"
}

# ==============================================================================
# rsd::l::tz::is_supported
# ==============================================================================

@test "rsd::l::tz::is_supported returns 0 on systemd hosts with timedatectl" {
    # Skip if test host doesn't have systemd (CI containers, etc.)
    if [[ ! -d /run/systemd/system ]]; then
        skip "Test host is not running systemd"
    fi

    run rsd::l::tz::is_supported
    [ "$status" -eq 0 ]
}

@test "rsd::l::tz::is_supported returns 1 when systemd is absent" {
    # Stub is_systemd to simulate non-systemd host
    rsd::l::systemd::is_systemd() { return 1; }

    _run_io rsd::l::tz::is_supported
    [ "$status" -eq 1 ]
    [[ "$output" == *"not running systemd"* ]]
}

@test "rsd::l::tz::is_supported returns 1 when timedatectl is missing" {
    # Stub systemd check to pass, but has_bin to fail
    rsd::l::systemd::is_systemd() { return 0; }
    rsd::l::target::has_bin() {
        [[ "$1" != "timedatectl" ]]
    }

    _run_io rsd::l::tz::is_supported
    [ "$status" -eq 1 ]
    [[ "$output" == *"timedatectl binary not found"* ]]
}

# ==============================================================================
# rsd::l::tz::get_current
# ==============================================================================

@test "rsd::l::tz::get_current reads timezone into nameref variable" {
    if [[ ! -d /run/systemd/system ]]; then
        skip "Test host is not running systemd"
    fi

    local result=""
    rsd::l::tz::get_current result
    [ -n "$result" ]
    # Timezone format is Area/City (contains a slash)
    [[ "$result" == */* ]] || [[ "$result" == "UTC" ]]
}

@test "rsd::l::tz::get_current returns 1 when timedatectl fails" {
    # Stub exec to simulate failure
    rsd::l::target::exec() { return 1; }

    local result=""
    _run_io rsd::l::tz::get_current result
    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to read"* ]]
}

# ==============================================================================
# rsd::l::tz::get_ntp_status
# ==============================================================================

@test "rsd::l::tz::get_ntp_status reads NTP sync into nameref variable" {
    if [[ ! -d /run/systemd/system ]]; then
        skip "Test host is not running systemd"
    fi

    local result=""
    rsd::l::tz::get_ntp_status result
    # Value should be "yes" or "no"
    [[ "$result" == "yes" || "$result" == "no" ]]
}

# ==============================================================================
# rsd::l::tz::is_valid
# ==============================================================================

@test "rsd::l::tz::is_valid returns 0 for a known timezone" {
    if [[ ! -d /run/systemd/system ]]; then
        skip "Test host is not running systemd"
    fi

    run rsd::l::tz::is_valid "UTC"
    [ "$status" -eq 0 ]
}

@test "rsd::l::tz::is_valid returns 0 for America/Sao_Paulo" {
    if [[ ! -d /run/systemd/system ]]; then
        skip "Test host is not running systemd"
    fi

    run rsd::l::tz::is_valid "America/Sao_Paulo"
    [ "$status" -eq 0 ]
}

@test "rsd::l::tz::is_valid returns 1 for an invalid timezone" {
    if [[ ! -d /run/systemd/system ]]; then
        skip "Test host is not running systemd"
    fi

    run rsd::l::tz::is_valid "Invalid/Timezone_Name"
    [ "$status" -ne 0 ]
}

@test "rsd::l::tz::is_valid returns 1 for empty string" {
    run rsd::l::tz::is_valid ""
    [ "$status" -ne 0 ]
}

@test "rsd::l::tz::is_valid rejects partial matches" {
    # "America" alone is not a valid timezone, only "America/*" entries are
    if [[ ! -d /run/systemd/system ]]; then
        skip "Test host is not running systemd"
    fi

    run rsd::l::tz::is_valid "America"
    [ "$status" -ne 0 ]
}

# ==============================================================================
# rsd::l::tz::list
# ==============================================================================

@test "rsd::l::tz::list returns timezone entries" {
    if [[ ! -d /run/systemd/system ]]; then
        skip "Test host is not running systemd"
    fi

    run rsd::l::tz::list
    [ "$status" -eq 0 ]
    # Should contain well-known timezones
    [[ "$output" == *"UTC"* ]]
    [[ "$output" == *"America/Sao_Paulo"* ]]
}

@test "rsd::l::tz::list with filter returns only matching entries" {
    if [[ ! -d /run/systemd/system ]]; then
        skip "Test host is not running systemd"
    fi

    run rsd::l::tz::list "Europe"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Europe/"* ]]
    # Should NOT contain non-European timezones
    [[ "$output" != *"America/"* ]]
}

# ==============================================================================
# rsd::l::tz::set (mocked — cannot change timezone in test environment)
# ==============================================================================

@test "rsd::l::tz::set returns 2 for empty timezone" {
    _run_io rsd::l::tz::set ""
    [ "$status" -eq 2 ]
    [[ "$output" == *"required"* ]]
}

@test "rsd::l::tz::set delegates to exec_sudo with correct arguments" {
    local captured_args=""
    rsd::l::target::exec_sudo() {
        captured_args="$*"
        return 0
    }

    rsd::l::tz::set "America/Sao_Paulo"
    [[ "$captured_args" == *"timedatectl"*"set-timezone"*"America/Sao_Paulo"* ]]
}
