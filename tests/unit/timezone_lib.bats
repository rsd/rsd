#!/usr/bin/env bats

# Tests for the timezone management library (lib/timezone.lib)
# Covers method detection, multi-method query/mutation, and fallback paths.
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

    # Reset method cache between tests
    RSD_TZ_METHOD=""
}

# Helper: run capturing fd 7 (rsd::io) in $output
_run_io() {
    _run_io_inner() { exec 7>&1; "$@"; }
    run _run_io_inner "$@"
}

# ==============================================================================
# Method Detection
# ==============================================================================

@test "rsd::l::tz::_detect_method finds timedatectl on systemd hosts" {
    if [[ ! -d /run/systemd/system ]]; then
        skip "Test host is not running systemd"
    fi

    rsd::l::tz::_detect_method
    [ "$RSD_TZ_METHOD" = "timedatectl" ]
}

@test "rsd::l::tz::_detect_method falls back to debconf when no systemd" {
    # Stub: no systemd, but dpkg-reconfigure exists
    rsd::l::systemd::is_systemd() { return 1; }
    rsd::l::target::has_bin() {
        [[ "$1" == "dpkg-reconfigure" ]] && return 0
        return 1
    }

    rsd::l::tz::_detect_method
    [ "$RSD_TZ_METHOD" = "debconf" ]
}

@test "rsd::l::tz::_detect_method falls back to posix when no systemd and no dpkg" {
    rsd::l::systemd::is_systemd() { return 1; }
    rsd::l::target::has_bin() { return 1; }
    rsd::l::target::exec() {
        # Simulate: test -d /usr/share/zoneinfo succeeds
        if [[ "$1" == "test" && "$2" == "-d" && "$3" == "/usr/share/zoneinfo" ]]; then
            return 0
        fi
        return 1
    }

    rsd::l::tz::_detect_method
    [ "$RSD_TZ_METHOD" = "posix" ]
}

@test "rsd::l::tz::_detect_method caches result on subsequent calls" {
    RSD_TZ_METHOD="timedatectl"
    local call_count=0
    rsd::l::systemd::is_systemd() { ((call_count++)); return 0; }

    rsd::l::tz::_detect_method
    [ "$call_count" -eq 0 ]  # Should not re-probe
    [ "$RSD_TZ_METHOD" = "timedatectl" ]
}

# ==============================================================================
# rsd::l::tz::is_supported
# ==============================================================================

@test "rsd::l::tz::is_supported returns 0 on systemd hosts" {
    if [[ ! -d /run/systemd/system ]]; then
        skip "Test host is not running systemd"
    fi

    run rsd::l::tz::is_supported
    [ "$status" -eq 0 ]
}

@test "rsd::l::tz::is_supported returns 0 when debconf fallback works" {
    rsd::l::systemd::is_systemd() { return 1; }
    rsd::l::target::has_bin() {
        [[ "$1" == "dpkg-reconfigure" ]] && return 0
        return 1
    }

    run rsd::l::tz::is_supported
    [ "$status" -eq 0 ]
}

@test "rsd::l::tz::is_supported returns 1 when nothing is available" {
    rsd::l::systemd::is_systemd() { return 1; }
    rsd::l::target::has_bin() { return 1; }
    rsd::l::target::exec() { return 1; }

    _run_io rsd::l::tz::is_supported
    [ "$status" -eq 1 ]
    [[ "$output" == *"No timezone management method"* ]]
}

# ==============================================================================
# rsd::l::tz::get_method
# ==============================================================================

@test "rsd::l::tz::get_method returns detected method in nameref" {
    RSD_TZ_METHOD="timedatectl"
    local result=""
    rsd::l::tz::get_method result
    [ "$result" = "timedatectl" ]
}

# ==============================================================================
# rsd::l::tz::get_current (timedatectl path)
# ==============================================================================

@test "rsd::l::tz::get_current reads timezone via timedatectl" {
    if [[ ! -d /run/systemd/system ]]; then
        skip "Test host is not running systemd"
    fi

    local result=""
    rsd::l::tz::get_current result
    [ -n "$result" ]
    [[ "$result" == */* ]] || [[ "$result" == "UTC" ]]
}

# ==============================================================================
# rsd::l::tz::get_current (debconf fallback path)
# ==============================================================================

@test "rsd::l::tz::get_current reads /etc/timezone in debconf mode" {
    RSD_TZ_METHOD="debconf"

    rsd::l::target::exec() {
        if [[ "$1" == "cat" && "$2" == "/etc/timezone" ]]; then
            echo "America/Sao_Paulo"
            return 0
        fi
        return 1
    }

    local result=""
    rsd::l::tz::get_current result
    [ "$result" = "America/Sao_Paulo" ]
}

@test "rsd::l::tz::get_current falls back to readlink /etc/localtime" {
    RSD_TZ_METHOD="posix"

    rsd::l::target::exec() {
        case "$1" in
            cat)
                # Simulate: /etc/timezone does not exist
                return 1
                ;;
            readlink)
                echo "/usr/share/zoneinfo/Europe/London"
                return 0
                ;;
            *)
                return 1
                ;;
        esac
    }

    local result=""
    rsd::l::tz::get_current result
    [ "$result" = "Europe/London" ]
}

@test "rsd::l::tz::get_current returns 1 when all methods fail" {
    RSD_TZ_METHOD="posix"
    rsd::l::target::exec() { return 1; }

    local result=""
    _run_io rsd::l::tz::get_current result
    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to read"* ]]
}

# ==============================================================================
# rsd::l::tz::get_ntp_status
# ==============================================================================

@test "rsd::l::tz::get_ntp_status reads NTP sync on systemd" {
    if [[ ! -d /run/systemd/system ]]; then
        skip "Test host is not running systemd"
    fi

    local result=""
    rsd::l::tz::get_ntp_status result
    [[ "$result" == "yes" || "$result" == "no" ]]
}

@test "rsd::l::tz::get_ntp_status returns unknown for non-systemd" {
    RSD_TZ_METHOD="debconf"
    local result=""
    rsd::l::tz::get_ntp_status result
    [ "$result" = "unknown" ]
}

# ==============================================================================
# rsd::l::tz::is_valid
# ==============================================================================

@test "rsd::l::tz::is_valid returns 0 for known timezone (timedatectl)" {
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

@test "rsd::l::tz::is_valid returns 1 for invalid timezone" {
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

@test "rsd::l::tz::is_valid checks zoneinfo file in posix mode" {
    RSD_TZ_METHOD="posix"

    rsd::l::target::exec() {
        if [[ "$1" == "test" && "$2" == "-f" ]]; then
            [[ "$3" == "/usr/share/zoneinfo/America/Sao_Paulo" ]] && return 0
            return 1
        fi
        return 1
    }

    run rsd::l::tz::is_valid "America/Sao_Paulo"
    [ "$status" -eq 0 ]

    run rsd::l::tz::is_valid "Fake/Zone"
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

@test "rsd::l::tz::set delegates to exec_sudo with timedatectl" {
    RSD_TZ_METHOD="timedatectl"
    local captured_args=""
    rsd::l::target::exec_sudo() {
        captured_args="$*"
        return 0
    }

    rsd::l::tz::set "America/Sao_Paulo"
    [[ "$captured_args" == *"timedatectl"*"set-timezone"*"America/Sao_Paulo"* ]]
}

@test "rsd::l::tz::set uses dpkg-reconfigure in debconf mode" {
    RSD_TZ_METHOD="debconf"
    local -a calls=()
    rsd::l::target::exec_sudo() {
        calls+=("$*")
        return 0
    }

    rsd::l::tz::set "UTC"
    # Should have two calls: echo to /etc/timezone + dpkg-reconfigure
    [ "${#calls[@]}" -eq 2 ]
    [[ "${calls[0]}" == *"/etc/timezone"* ]]
    [[ "${calls[1]}" == *"dpkg-reconfigure"* ]]
}

@test "rsd::l::tz::set uses ln -sf in posix mode" {
    RSD_TZ_METHOD="posix"
    local -a calls=()
    rsd::l::target::exec_sudo() {
        calls+=("$*")
        return 0
    }

    rsd::l::tz::set "Europe/London"
    # Should have two calls: ln -sf + echo to /etc/timezone
    [ "${#calls[@]}" -eq 2 ]
    [[ "${calls[0]}" == *"ln"*"/usr/share/zoneinfo/Europe/London"* ]]
    [[ "${calls[1]}" == *"/etc/timezone"* ]]
}
