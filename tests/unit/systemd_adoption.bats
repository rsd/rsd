#!/usr/bin/env bats

# Tests for the systemd distro adoption registry (lib/systemd.lib)
# @see lib/systemd.lib

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
    source "${BATS_TEST_DIRNAME}/../../lib/systemd.lib"

    unset RSD_REMOTE_TARGET
}

# Helper: run capturing fd 7 (rsd::io) in $output
_run_io() {
    _run_io_inner() { exec 7>&1; "$@"; }
    run _run_io_inner "$@"
}

# ==============================================================================
# RSD_SYSTEMD_ADOPTION table structure
# ==============================================================================

@test "adoption table contains expected distro entries" {
    [[ -v RSD_SYSTEMD_ADOPTION["ubuntu"] ]]
    [[ -v RSD_SYSTEMD_ADOPTION["debian"] ]]
    [[ -v RSD_SYSTEMD_ADOPTION["fedora"] ]]
    [[ -v RSD_SYSTEMD_ADOPTION["arch"] ]]
    [[ -v RSD_SYSTEMD_ADOPTION["alpine"] ]]
    [[ -v RSD_SYSTEMD_ADOPTION["rhel"] ]]
    [[ -v RSD_SYSTEMD_ADOPTION["centos"] ]]
}

# ==============================================================================
# check_distro_support — systemd-era distros
# ==============================================================================

@test "check_distro_support returns 0 for Ubuntu 26.04" {
    run rsd::l::systemd::check_distro_support "ubuntu" "26.04"
    [ "$status" -eq 0 ]
}

@test "check_distro_support returns 0 for Ubuntu 15.04 (adoption version)" {
    run rsd::l::systemd::check_distro_support "ubuntu" "15.04"
    [ "$status" -eq 0 ]
}

@test "check_distro_support returns 0 for Debian 8" {
    run rsd::l::systemd::check_distro_support "debian" "8"
    [ "$status" -eq 0 ]
}

@test "check_distro_support returns 0 for Debian 13" {
    run rsd::l::systemd::check_distro_support "debian" "13"
    [ "$status" -eq 0 ]
}

# ==============================================================================
# check_distro_support — pre-systemd distros
# ==============================================================================

@test "check_distro_support returns 1 for Ubuntu 14.04 (pre-systemd)" {
    run rsd::l::systemd::check_distro_support "ubuntu" "14.04"
    [ "$status" -eq 1 ]
}

@test "check_distro_support returns 1 for Debian 7 (pre-systemd)" {
    run rsd::l::systemd::check_distro_support "debian" "7"
    [ "$status" -eq 1 ]
}

@test "check_distro_support returns 1 for CentOS 6 (pre-systemd)" {
    run rsd::l::systemd::check_distro_support "centos" "6"
    [ "$status" -eq 1 ]
}

@test "check_distro_support returns 1 for RHEL 6 (pre-systemd)" {
    run rsd::l::systemd::check_distro_support "rhel" "6"
    [ "$status" -eq 1 ]
}

# ==============================================================================
# check_distro_support — rolling distros
# ==============================================================================

@test "check_distro_support returns 0 for Arch (rolling, always systemd)" {
    run rsd::l::systemd::check_distro_support "arch" "rolling"
    [ "$status" -eq 0 ]
}

@test "check_distro_support returns 0 for Manjaro (rolling)" {
    run rsd::l::systemd::check_distro_support "manjaro" "rolling"
    [ "$status" -eq 0 ]
}

# ==============================================================================
# check_distro_support — never-systemd distros
# ==============================================================================

@test "check_distro_support returns 1 for Alpine (never adopted systemd)" {
    run rsd::l::systemd::check_distro_support "alpine" "3.20"
    [ "$status" -eq 1 ]
}

# ==============================================================================
# check_distro_support — unknown distros
# ==============================================================================

@test "check_distro_support returns 2 for unknown distro" {
    run rsd::l::systemd::check_distro_support "nixos" "24.05"
    [ "$status" -eq 2 ]
}

# ==============================================================================
# check_distro_support — nameref output
# ==============================================================================

@test "check_distro_support outputs adoption version for supported distro" {
    local ver=""
    rsd::l::systemd::check_distro_support "ubuntu" "26.04" ver
    [ "$ver" = "15.04" ]
}

@test "check_distro_support outputs 'never' for Alpine" {
    local ver=""
    rsd::l::systemd::check_distro_support "alpine" "3.20" ver || true
    [ "$ver" = "never" ]
}

@test "check_distro_support outputs '0' for rolling distro" {
    local ver=""
    rsd::l::systemd::check_distro_support "arch" "rolling" ver
    [ "$ver" = "0" ]
}

@test "check_distro_support outputs 'unknown' for unregistered distro" {
    local ver=""
    rsd::l::systemd::check_distro_support "nixos" "24.05" ver || true
    [ "$ver" = "unknown" ]
}

# ==============================================================================
# diagnose_support — human-readable messages
# ==============================================================================

@test "diagnose_support emits success for Ubuntu 26.04" {
    _run_io rsd::l::systemd::diagnose_support "ubuntu" "26.04"
    [ "$status" -eq 0 ]
    [[ "$output" == *"supports systemd"* ]]
    [[ "$output" == *"15.04"* ]]
}

@test "diagnose_support emits warning for Ubuntu 14.04" {
    _run_io rsd::l::systemd::diagnose_support "ubuntu" "14.04"
    [ "$status" -eq 1 ]
    [[ "$output" == *"pre-dates systemd"* ]]
    [[ "$output" == *"15.04"* ]]
}

@test "diagnose_support emits warning for Alpine (never)" {
    _run_io rsd::l::systemd::diagnose_support "alpine" "3.20"
    [ "$status" -eq 1 ]
    [[ "$output" == *"does not use systemd"* ]]
    [[ "$output" == *"OpenRC"* ]]
}

@test "diagnose_support emits rolling message for Arch" {
    _run_io rsd::l::systemd::diagnose_support "arch" "rolling"
    [ "$status" -eq 0 ]
    [[ "$output" == *"always available"* ]]
}

@test "diagnose_support emits info for unknown distro" {
    _run_io rsd::l::systemd::diagnose_support "nixos" "24.05"
    [ "$status" -eq 2 ]
    [[ "$output" == *"not in the systemd adoption registry"* ]]
}
