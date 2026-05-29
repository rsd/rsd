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
    
    # Source core framework and config
    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/config.lib"
}

# Helper: run capturing fd 7 (rsd::io) in $output
_run_io() {
    _run_io_inner() { exec 7>&1; "$@"; }
    run _run_io_inner "$@"
}

teardown() {
    # Unset all loaded OS library environment markers to allow subsequent tests to re-source cleanly
    unset RSD_OS_LINUX_LIB
    unset RSD_OS_DEBIAN_LIB
    unset RSD_OS_ARCH_LIB
    unset RSD_OS_UBUNTU_LIB
    unset RSD_OS_UBUNTU_2604_LIB
    unset RSD_OS_UBUNTU_2404_LIB
    unset RSD_OS_UBUNTU_2204_LIB
}

@test "sourcing linux.lib loads generic package manager fallback" {
    source "${BATS_TEST_DIRNAME}/../../lib/os/linux.lib"
    
    [ "$RSD_OS_LINUX_LIB" = "1" ]
    
    _run_io rsd::l::os::install_package "test-pkg"
    [ "$status" -eq 3 ]
    [[ "$output" == *"no default package manager"* ]]
}

@test "sourcing debian.lib dynamically pulls linux.lib and overrides install_package to use apt-get" {
    # Verify that sourcing debian.lib triggers upstream recursive hook loading linux.lib
    source "${BATS_TEST_DIRNAME}/../../lib/os/linux/debian.lib"
    
    [ "$RSD_OS_LINUX_LIB" = "1" ]
    [ "$RSD_OS_DEBIAN_LIB" = "1" ]
    
    # Dry-run execution
    export RSD_INSTALL_DRY_RUN=1
    run rsd::l::os::install_package "tmux"
    [ "$status" -eq 0 ]
    [ "$output" = "sudo apt-get install -y tmux" ]
}

@test "sourcing arch.lib dynamically pulls linux.lib and overrides install_package to use pacman" {
    source "${BATS_TEST_DIRNAME}/../../lib/os/linux/arch.lib"
    
    [ "$RSD_OS_LINUX_LIB" = "1" ]
    [ "$RSD_OS_ARCH_LIB" = "1" ]
    
    export RSD_INSTALL_DRY_RUN=1
    run rsd::l::os::install_package "tmux"
    [ "$status" -eq 0 ]
    [ "$output" = "sudo pacman -Sy --noconfirm tmux" ]
}

@test "sourcing ubuntu-22.04.lib dynamically pulls entire upstream hierarchy and resolves correct overrides" {
    # Sourcing the most specific version triggers recursive upstream parent loads up to linux.lib
    source "${BATS_TEST_DIRNAME}/../../lib/os/linux/debian/ubuntu/22.04.lib"
    
    [ "$RSD_OS_LINUX_LIB" = "1" ]
    [ "$RSD_OS_DEBIAN_LIB" = "1" ]
    [ "$RSD_OS_UBUNTU_LIB" = "1" ]
    [ "$RSD_OS_UBUNTU_2604_LIB" = "1" ]
    [ "$RSD_OS_UBUNTU_2404_LIB" = "1" ]
    [ "$RSD_OS_UBUNTU_2204_LIB" = "1" ]
    
    # Verify that install_package resolved to debian.lib's override
    export RSD_INSTALL_DRY_RUN=1
    run rsd::l::os::install_package "htop"
    [ "$status" -eq 0 ]
    [ "$output" = "sudo apt-get install -y htop" ]
    
    # Verify that set_default_editor resolved to ubuntu-22.04.lib's override specifically
    _run_io rsd::l::os::set_default_editor
    [ "$status" -eq 0 ]
    [[ "$output" == *"setting default editor to vim-tiny"* ]]
}
