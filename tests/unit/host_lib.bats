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
    
    # Source core framework, config library, and host library
    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/config.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/host.lib"
    
    # Create a temporary directory for release and config mocks
    TEST_TMP_DIR=$(mktemp -d -t rsd-host-test.XXXXXX)
}

# Helper: run capturing fd 7 (rsd::io) in $output
_run_io() {
    _run_io_inner() { exec 7>&1; "$@"; }
    run _run_io_inner "$@"
}

teardown() {
    rm -rf "$TEST_TMP_DIR"
}

@test "rsd::l::host::identify parses Debian host correctly" {
    local os_release="${TEST_TMP_DIR}/os-release-debian"
    cat <<EOF > "$os_release"
ID=debian
VERSION_ID="12"
EOF

    export RSD_MOCK_OS_RELEASE="$os_release"
    
    # Mock uname command to output Linux and x86_64
    uname() {
        if [[ "$1" == "-s" ]]; then
            echo "Linux"
        elif [[ "$1" == "-m" ]]; then
            echo "x86_64"
        else
            echo "uname called with unknown argument $1" >&2
            return 1
        fi
    }
    export -f uname

    declare -A props
    rsd::l::host::identify props
    
    [ "$?" -eq 0 ]
    [ "${props[os]}" = "linux" ]
    [ "${props[arch]}" = "x86_64" ]
    [ "${props[distro]}" = "debian" ]
    [ "${props[family]}" = "debian" ]
    [ "${props[version]}" = "12" ]
    [ "${props[pkg_manager]}" = "apt" ]
}

@test "rsd::l::host::identify parses Ubuntu host and resolves family to debian correctly" {
    local os_release="${TEST_TMP_DIR}/os-release-ubuntu"
    cat <<EOF > "$os_release"
ID=ubuntu
ID_LIKE="debian"
VERSION_ID="22.04"
EOF

    export RSD_MOCK_OS_RELEASE="$os_release"
    
    uname() {
        if [[ "$1" == "-s" ]]; then
            echo "Linux"
        elif [[ "$1" == "-m" ]]; then
            echo "x86_64"
        fi
    }
    export -f uname

    declare -A props
    rsd::l::host::identify props
    
    [ "$?" -eq 0 ]
    [ "${props[os]}" = "linux" ]
    [ "${props[distro]}" = "ubuntu" ]
    [ "${props[family]}" = "debian" ]
    [ "${props[version]}" = "22.04" ]
    [ "${props[pkg_manager]}" = "apt" ]
}

@test "rsd::l::host::identify parses Arch Linux host and version rolling correctly" {
    local os_release="${TEST_TMP_DIR}/os-release-arch"
    cat <<EOF > "$os_release"
ID=arch
EOF

    export RSD_MOCK_OS_RELEASE="$os_release"
    
    uname() {
        if [[ "$1" == "-s" ]]; then
            echo "Linux"
        elif [[ "$1" == "-m" ]]; then
            echo "x86_64"
        fi
    }
    export -f uname

    declare -A props
    rsd::l::host::identify props
    
    [ "$?" -eq 0 ]
    [ "${props[os]}" = "linux" ]
    [ "${props[distro]}" = "arch" ]
    [ "${props[family]}" = "arch" ]
    [ "${props[version]}" = "rolling" ]
    [ "${props[pkg_manager]}" = "pacman" ]
}

@test "rsd::l::host::get_property retrieves saved profile and falls back to localhost dynamically" {
    # Ensure R_INI_hosts exists and populate server1 mock config
    declare -gA R_INI_hosts
    R_INI_hosts["hosts.server1.distro"]="ubuntu"
    R_INI_hosts["hosts.server1.family"]="debian"
    R_INI_hosts["hosts.server1.pkg_manager"]="apt"
    
    # 1. Test profile retrieval
    local val=""
    rsd::l::host::get_property server1 distro val
    [ "$?" -eq 0 ]
    [ "$val" = "ubuntu" ]
    
    rsd::l::host::get_property server1 family val
    [ "$?" -eq 0 ]
    [ "$val" = "debian" ]
    
    # Test retrieving from non-prefixed key section (which read_ini constructs from [section])
    R_INI_hosts["server2.distro"]="debian"
    local val2=""
    rsd::l::host::get_property server2 distro val2
    [ "$?" -eq 0 ]
    [ "$val2" = "debian" ]
    
    # 2. Test localhost dynamic fallback
    local os_release="${TEST_TMP_DIR}/os-release-local"
    cat <<EOF > "$os_release"
ID=arch
EOF
    export RSD_MOCK_OS_RELEASE="$os_release"
    
    uname() {
        if [[ "$1" == "-s" ]]; then
            echo "Linux"
        elif [[ "$1" == "-m" ]]; then
            echo "x86_64"
        fi
    }
    export -f uname
    
    local local_family=""
    rsd::l::host::get_property localhost family local_family
    [ "$?" -eq 0 ]
    [ "$local_family" = "arch" ]
}

@test "rsd::l::host::generate_standalone_script generates non-empty bash script" {
    local script=""
    rsd::l::host::generate_standalone_script script
    [ "$?" -eq 0 ]
    [ -n "$script" ]
    [[ "$script" == *"os="* ]]
    [[ "$script" == *"pkg_manager="* ]]
}

@test "rsd::c::host::show retrieves and prints saved host properties correctly" {
    # Source the command file
    source "${BATS_TEST_DIRNAME}/../../command/host"

    # Populate mock config data (without hosts. prefix as parsed from hosts.ini)
    declare -gA R_INI_hosts
    R_INI_hosts["server3.os"]="linux"
    R_INI_hosts["server3.arch"]="x86_64"
    R_INI_hosts["server3.distro"]="ubuntu"
    R_INI_hosts["server3.family"]="debian"
    R_INI_hosts["server3.version"]="22.04"
    R_INI_hosts["server3.pkg_manager"]="apt"
    R_INI_hosts["server3.writable_bins"]="/usr/bin"

    # 1. Test displaying saved server3 configuration
    run rsd::c::host::show server3
    [ "$status" -eq 0 ]
    [[ "$output" == *"os=linux"* ]]
    [[ "$output" == *"arch=x86_64"* ]]
    [[ "$output" == *"distro=ubuntu"* ]]
    [[ "$output" == *"family=debian"* ]]
    [[ "$output" == *"version=22.04"* ]]
    [[ "$output" == *"pkg_manager=apt"* ]]
    [[ "$output" == *"writable_bins=/usr/bin"* ]]

    # 2. Test displaying missing configuration returns error 10
    _run_io rsd::c::host::show missing-server
    [ "$status" -eq 10 ]
    [[ "$output" == *"No saved host properties found for"* ]]
}

