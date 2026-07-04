#!/usr/bin/env bats

# Tests for the conda install recipe (lib/recipe/conda/install.recipe)
# Verifies recipe registration, task function existence, pre_check logic,
# and validate_env behavior.
#
# @see lib/recipe/conda/install.recipe

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
    source "${BATS_TEST_DIRNAME}/../../lib/recipe.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/recipe/conda/install.recipe"

    # Redirect RSD messaging fd (7) to stdout so BATS captures it
    exec 7>&1

    # Local execution mode by default
    unset RSD_REMOTE_TARGET

    # Provide mock RSD_COMMAND_ARGS for registration
    declare -g -A RSD_COMMAND_ARGS=()
}

# Helper: run capturing fd 7 (rsd::io) in $output
_run_io() {
    _run_io_inner() { exec 7>&1; "$@"; }
    run _run_io_inner "$@"
}

# ==============================================================================
# Registration
# ==============================================================================

@test "conda_install::register registers all four tasks" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY

    rsd::r::conda_install::register

    [ "${#RSD_REGISTERED_TASKS[@]}" -eq 4 ]
    [ "${RSD_REGISTERED_TASKS[0]}" = "conda_install::validate_env" ]
    [ "${RSD_REGISTERED_TASKS[1]}" = "conda_install::install" ]
    [ "${RSD_REGISTERED_TASKS[2]}" = "conda_install::initialize_shell" ]
    [ "${RSD_REGISTERED_TASKS[3]}" = "conda_install::configure" ]
}

@test "conda_install::register defaults distribution to miniforge" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY
    declare -g -A RSD_COMMAND_ARGS=()

    rsd::r::conda_install::register

    [ "$RSD_CONDA_DISTRIBUTION" = "miniforge" ]
}

@test "conda_install::register lowercases distribution parameter" {
    RSD_REGISTERED_TASKS=()
    declare -g -A RSD_TASKS_RECOVERY
    declare -g -A RSD_COMMAND_ARGS=(["distribution"]="MiniConda")

    rsd::r::conda_install::register

    [ "$RSD_CONDA_DISTRIBUTION" = "miniconda" ]
}

# ==============================================================================
# validate_env — platform and parameter validation
# ==============================================================================

@test "validate_env fails when distribution is invalid" {
    RSD_CONDA_DISTRIBUTION="invalid_dist"
    RSD_CONDA_PREFIX="/tmp/conda"

    _run_io rsd::r::conda_install::validate_env
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid distribution"* ]]
}

@test "validate_env fails when curl is missing on target" {
    RSD_CONDA_DISTRIBUTION="miniforge"
    RSD_CONDA_PREFIX="/tmp/conda"

    # Stub has_bin to say curl is missing
    rsd::l::target::has_bin() {
        [[ "$1" == "curl" ]] && return 1
        return 0
    }

    _run_io rsd::r::conda_install::validate_env
    [ "$status" -eq 3 ]
    [[ "$output" == *"Required binary 'curl' is missing"* ]]
}

@test "validate_env fails on unsupported architectures" {
    RSD_CONDA_DISTRIBUTION="miniforge"
    RSD_CONDA_PREFIX="/tmp/conda"

    # Stub target binary check to pass
    rsd::l::target::has_bin() { return 0; }

    # Stub target architecture check to return unsupported one
    rsd::l::target::exec() {
        if [[ "$1" == "uname" && "$2" == "-m" ]]; then
            echo "riscv64"
            return 0
        fi
        "$@"
    }

    _run_io rsd::r::conda_install::validate_env
    [ "$status" -eq 1 ]
    [[ "$output" == *"Unsupported architecture: riscv64"* ]]
}

@test "validate_env resolves default prefix relative to dynamic home dir" {
    RSD_CONDA_DISTRIBUTION="miniforge"
    RSD_CONDA_PREFIX=""

    # Stub target checks
    rsd::l::target::has_bin() { return 0; }
    rsd::l::target::exec() {
        if [[ "$1" == "uname" && "$2" == "-m" ]]; then
            echo "x86_64"
            return 0
        elif [[ "$1" == "printenv" && "$2" == "HOME" ]]; then
            echo "/home/mockuser"
            return 0
        fi
        "$@"
    }

    rsd::r::conda_install::validate_env
    [ "$RSD_CONDA_PREFIX" = "/home/mockuser/miniforge3" ]
}

@test "validate_env resolves relative ~/ and \$HOME/ prefix paths correctly" {
    # Test ~/ relative path
    RSD_CONDA_DISTRIBUTION="miniconda"
    RSD_CONDA_PREFIX="~/custom/conda"

    # Stub target checks
    rsd::l::target::has_bin() { return 0; }
    rsd::l::target::exec() {
        if [[ "$1" == "uname" && "$2" == "-m" ]]; then
            echo "x86_64"
            return 0
        elif [[ "$1" == "printenv" && "$2" == "HOME" ]]; then
            echo "/home/mockuser"
            return 0
        fi
        "$@"
    }

    rsd::r::conda_install::validate_env
    [ "$RSD_CONDA_PREFIX" = "/home/mockuser/custom/conda" ]

    # Test $HOME/ relative path
    RSD_CONDA_PREFIX='$HOME/another/conda'
    rsd::r::conda_install::validate_env
    [ "$RSD_CONDA_PREFIX" = "/home/mockuser/another/conda" ]
}

# ==============================================================================
# pre_check — idempotency
# ==============================================================================

@test "install::pre_check returns 0 when conda binary already exists" {
    RSD_CONDA_PREFIX="/tmp/mock-conda"

    # Stub file_exists to return true
    rsd::l::target::file_exists() {
        [[ "$1" == "/tmp/mock-conda/bin/conda" ]] && return 0
        return 1
    }

    run rsd::r::conda_install::install::pre_check
    [ "$status" -eq 0 ]
}

@test "install::pre_check returns 1 when conda binary is missing" {
    RSD_CONDA_PREFIX="/tmp/mock-conda"

    # Stub file_exists to return false
    rsd::l::target::file_exists() {
        return 1
    }

    run rsd::r::conda_install::install::pre_check
    [ "$status" -ne 0 ]
}

# ==============================================================================
# initialize_shell
# ==============================================================================

@test "initialize_shell::pre_check returns 0 when shell config already contains conda init block" {
    # Stub target commands
    rsd::l::target::exec() {
        if [[ "$1" == "printenv" && "$2" == "SHELL" ]]; then
            echo "/bin/bash"
            return 0
        fi
        "$@"
    }

    # Stub file_contains to return true
    rsd::l::target::file_contains() {
        [[ "$1" == "# >>> conda initialize >>>" && "$2" == "\$HOME/.bashrc" ]] && return 0
        return 1
    }

    run rsd::r::conda_install::initialize_shell::pre_check
    [ "$status" -eq 0 ]
}

@test "initialize_shell::pre_check returns 1 when shell config lacks conda init block" {
    # Stub target commands
    rsd::l::target::exec() {
        if [[ "$1" == "printenv" && "$2" == "SHELL" ]]; then
            echo "/bin/zsh"
            return 0
        fi
        "$@"
    }

    # Stub file_contains to return false
    rsd::l::target::file_contains() {
        return 1
    }

    run rsd::r::conda_install::initialize_shell::pre_check
    [ "$status" -ne 0 ]
}

@test "initialize_shell task succeeds for supported shell" {
    RSD_CONDA_PREFIX="/tmp/mock-conda"

    # Stub target commands
    rsd::l::target::exec() {
        if [[ "$1" == "printenv" && "$2" == "SHELL" ]]; then
            echo "/usr/bin/zsh"
            return 0
        elif [[ "$1" == "/tmp/mock-conda/bin/conda" && "$2" == "init" && "$3" == "zsh" ]]; then
            return 0
        fi
        "$@"
    }

    _run_io rsd::r::conda_install::initialize_shell
    [ "$status" -eq 0 ]
    [[ "$output" == *"Conda initialized successfully for zsh"* ]]
}

@test "initialize_shell task warns and skips for unsupported shell" {
    # Stub target commands
    rsd::l::target::exec() {
        if [[ "$1" == "printenv" && "$2" == "SHELL" ]]; then
            echo "/bin/tcsh"
            return 0
        fi
        "$@"
    }

    _run_io rsd::r::conda_install::initialize_shell
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping conda shell initialization: unsupported shell 'tcsh'"* ]]
}

# ==============================================================================
# configure
# ==============================================================================

@test "configure::pre_check returns 0 when condarc already disables base activation" {
    # Stub target commands
    rsd::l::target::exec() {
        if [[ "$1" == "printenv" && "$2" == "HOME" ]]; then
            echo "/home/mockuser"
            return 0
        fi
        "$@"
    }

    # Stub file_contains to return true
    rsd::l::target::file_contains() {
        [[ "$1" == "auto_activate_base: false" && "$2" == "/home/mockuser/.condarc" ]] && return 0
        return 1
    }

    run rsd::r::conda_install::configure::pre_check
    [ "$status" -eq 0 ]
}

@test "configure::pre_check returns 1 when condarc lacks disabling flag" {
    # Stub target commands
    rsd::l::target::exec() {
        if [[ "$1" == "printenv" && "$2" == "HOME" ]]; then
            echo "/home/mockuser"
            return 0
        fi
        "$@"
    }

    # Stub file_contains to return false
    rsd::l::target::file_contains() {
        return 1
    }

    run rsd::r::conda_install::configure::pre_check
    [ "$status" -ne 0 ]
}

@test "configure task executes conda config set successfully" {
    RSD_CONDA_PREFIX="/tmp/mock-conda"

    # Stub target commands
    rsd::l::target::exec() {
        if [[ "$1" == "/tmp/mock-conda/bin/conda" && "$2" == "config" && "$3" == "--set" && "$4" == "auto_activate_base" && "$5" == "false" ]]; then
            return 0
        fi
        "$@"
    }

    _run_io rsd::r::conda_install::configure
    [ "$status" -eq 0 ]
    [[ "$output" == *"Conda base auto-activation disabled successfully"* ]]
}
