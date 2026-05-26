#!/usr/bin/env bats

setup() {
    export RSD_ON=1
    export RSD_DEBUG=0
    export RSD_MODE="devel"
    export RSD_RUN_DIR="${BATS_TEST_DIRNAME}/../../"
    
    declare -ga RSD_LIBRARY_SEARCH_PATH
    RSD_LIBRARY_SEARCH_PATH+=("${BATS_TEST_DIRNAME}/../../")

    # Stub create search path to allow sourcing rsd.lib
    rsd::create_search_path() {
        return 0
    }

    # Source dependencies
    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/config.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/remote.lib"
    source "${BATS_TEST_DIRNAME}/../../command/remote"
}

@test "rsd::c::remote::check fails if RSD_REMOTE_TARGET is empty" {
    unset RSD_REMOTE_TARGET
    run rsd::c::remote::check
    [ "$status" -eq 2 ]
}

@test "rsd::c::remote::check passes if target has all mandatory binaries" {
    export RSD_REMOTE_TARGET="mock-target"
    
    # Mock remote execution returning success
    rsd::l::remote::execute() {
        local target="$1"
        local cmd="$2"
        if [[ "$cmd" == "bash" && "$3" == "-s" ]]; then
            echo "OK:EXISTS:YES"
            return 0
        fi
        return 1
    }
    
    run rsd::c::remote::check
    [ "$status" -eq 0 ]
    
    unset RSD_REMOTE_TARGET
}

@test "rsd::c::remote::check fails and outputs missing programs when dependencies are not met" {
    export RSD_REMOTE_TARGET="mock-target"
    
    # Mock remote execution returning dependency failures (successfully executed, return 0)
    rsd::l::remote::execute() {
        local target="$1"
        local cmd="$2"
        if [[ "$cmd" == "bash" && "$3" == "-s" ]]; then
            echo "FAILED:tar openssl:MISSING:NO"
            return 0
        fi
        return 1
    }
    
    run rsd::c::remote::check
    [ "$status" -eq 3 ]
    [[ "$output" == *"missing required installer binaries: tar openssl"* ]]
    
    unset RSD_REMOTE_TARGET
}

@test "rsd::c::remote::install runs checks first and triggers bootstrapping on success" {
    export RSD_REMOTE_TARGET="mock-target"
    
    # Mock rsd::c::remote::check to return success
    rsd::c::remote::check() {
        return 0
    }
    
    # Mock bootstrap install tracker
    rsd::l::remote::bootstrap_install() {
        local target="$1"
        local mode="$2"
        if [[ "$target" == "mock-target" && "$mode" == "local" ]]; then
            echo "BOOTSTRAP_SUCCESS"
            return 0
        fi
        return 1
    }
    
    run rsd::c::remote::install "local"
    [ "$status" -eq 0 ]
    [[ "$output" == *"BOOTSTRAP_SUCCESS"* ]]
    
    unset RSD_REMOTE_TARGET
}

@test "rsd::c::remote::verify validates remote responsive framework version checks" {
    export RSD_REMOTE_TARGET="mock-target"
    
    # Mock remote framework check returning responsive version
    rsd::l::remote::execute() {
        local target="$1"
        local cmd="$2"
        if [[ "$cmd" == "\$HOME/.local/bin/rsd" && "$3" == "--version" ]]; then
            echo "1.9.11"
            return 0
        fi
        return 1
    }
    
    run rsd::c::remote::verify
    [ "$status" -eq 0 ]
    [[ "$output" == *"RSD is responsive at \$HOME/.local/bin/rsd (v1.9.11)"* ]]
    
    unset RSD_REMOTE_TARGET
}

@test "rsd::c::remote::install auto-creates ~/.local/bin if missing and -y flag is passed" {
    export RSD_REMOTE_TARGET="mock-target"
    
    rsd::c::remote::check() {
        return 0
    }
    
    rsd::l::remote::execute() {
        local target="$1"
        local cmd="$2"
        if [[ "$cmd" == "[ -d \$HOME/.local/bin ]" ]]; then
            return 1  # folder does not exist
        elif [[ "$cmd" == "mkdir" && "$3" == "-p" && "$4" == "\$HOME/.local/bin" ]]; then
            echo "MKDIR_AUTO_SUCCESS"
            return 0
        fi
        return 0
    }
    
    rsd::l::remote::bootstrap_install() {
        return 0
    }
    
    run rsd::c::remote::install "user" "-y"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MKDIR_AUTO_SUCCESS"* ]]
    
    unset RSD_REMOTE_TARGET
}

@test "rsd::c::remote::install prompts and creates ~/.local/bin if missing and user confirms" {
    export RSD_REMOTE_TARGET="mock-target"
    
    rsd::c::remote::check() {
        return 0
    }
    
    rsd::l::remote::execute() {
        local target="$1"
        local cmd="$2"
        if [[ "$cmd" == "[ -d \$HOME/.local/bin ]" ]]; then
            return 1  # folder does not exist
        elif [[ "$cmd" == "mkdir" && "$3" == "-p" && "$4" == "\$HOME/.local/bin" ]]; then
            echo "MKDIR_PROMPTED_SUCCESS"
            return 0
        fi
        return 0
    }
    
    rsd::l::remote::prompt_user() {
        return 0  # User accepts
    }
    
    rsd::l::remote::bootstrap_install() {
        return 0
    }
    
    run rsd::c::remote::install "user"
    [ "$status" -eq 0 ]
    [[ "$output" == *"MKDIR_PROMPTED_SUCCESS"* ]]
    
    unset RSD_REMOTE_TARGET
}

@test "rsd::c::remote::install aborts if ~/.local/bin is missing and user declines" {
    export RSD_REMOTE_TARGET="mock-target"
    
    rsd::c::remote::check() {
        return 0
    }
    
    rsd::l::remote::execute() {
        local target="$1"
        local cmd="$2"
        if [[ "$cmd" == "[ -d \$HOME/.local/bin ]" ]]; then
            return 1  # folder does not exist
        fi
        return 0
    }
    
    rsd::l::remote::prompt_user() {
        return 1  # User declines
    }
    
    run rsd::c::remote::install "user"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Abort: Remote installation declined because user bin directory is missing."* ]]
    
    unset RSD_REMOTE_TARGET
}

@test "rsd::c::remote::setup_path fails if RSD_REMOTE_TARGET is empty" {
    unset RSD_REMOTE_TARGET
    run rsd::c::remote::setup_path
    [ "$status" -eq 2 ]
}

@test "rsd::c::remote::setup_path skips if already configured in remote ~/.bashrc" {
    export RSD_REMOTE_TARGET="mock-target"
    
    rsd::l::remote::execute() {
        local target="$1"
        local cmd="$2"
        if [[ "$cmd" == "bash" && "$3" == "-s" ]]; then
            # in_path:in_bashrc -> 0:1 (in bashrc but not active in path)
            echo "0:1"
            return 0
        fi
        return 1
    }
    
    run rsd::c::remote::setup_path
    [ "$status" -eq 0 ]
    [[ "$output" == *"Remote ~/.bashrc already contains a ~/.local/bin path configuration."* ]]
    [[ "$output" == *"configured in ~/.bashrc, but not active in this session"* ]]
    
    unset RSD_REMOTE_TARGET
}

@test "rsd::c::remote::setup_path skips if already in remote PATH" {
    export RSD_REMOTE_TARGET="mock-target"
    
    rsd::l::remote::execute() {
        local target="$1"
        local cmd="$2"
        if [[ "$cmd" == "bash" && "$3" == "-s" ]]; then
            # in_path:in_bashrc -> 1:0 (in path but not bashrc)
            echo "1:0"
            return 0
        fi
        return 1
    }
    
    run rsd::c::remote::setup_path
    [ "$status" -eq 0 ]
    [[ "$output" == *"is already in the remote PATH"* ]]
    
    unset RSD_REMOTE_TARGET
}

@test "rsd::c::remote::setup_path appends to remote ~/.bashrc if missing and -y flag is passed" {
    export RSD_REMOTE_TARGET="mock-target"
    
    rsd::l::remote::execute() {
        local target="$1"
        local cmd="$2"
        if [[ "$cmd" == "bash" && "$3" == "-s" ]]; then
            # in_path:in_bashrc -> 0:0
            echo "0:0"
            return 0
        elif [[ "$cmd" == "bash" && "$3" == "-c" && "$4" == *"export PATH="* ]]; then
            echo "APPEND_SUCCESS"
            return 0
        fi
        return 1
    }
    
    run rsd::c::remote::setup_path "-y"
    [ "$status" -eq 0 ]
    [[ "$output" == *"APPEND_SUCCESS"* ]]
    [[ "$output" == *"Successfully added PATH configuration"* ]]
    
    unset RSD_REMOTE_TARGET
}

@test "rsd::c::remote::setup_path appends to remote ~/.bashrc if missing and user confirms interactive prompt" {
    export RSD_REMOTE_TARGET="mock-target"
    
    rsd::l::remote::execute() {
        local target="$1"
        local cmd="$2"
        if [[ "$cmd" == "bash" && "$3" == "-s" ]]; then
            # in_path:in_bashrc -> 0:0
            echo "0:0"
            return 0
        elif [[ "$cmd" == "bash" && "$3" == "-c" && "$4" == *"export PATH="* ]]; then
            echo "APPEND_SUCCESS"
            return 0
        fi
        return 1
    }
    
    rsd::l::remote::prompt_user() {
        return 0  # User confirms
    }
    
    run rsd::c::remote::setup_path
    [ "$status" -eq 0 ]
    [[ "$output" == *"APPEND_SUCCESS"* ]]
    [[ "$output" == *"Successfully added PATH configuration"* ]]
    
    unset RSD_REMOTE_TARGET
}

@test "rsd::c::remote::setup_path aborts if missing and user declines interactive prompt" {
    export RSD_REMOTE_TARGET="mock-target"
    
    rsd::l::remote::execute() {
        local target="$1"
        local cmd="$2"
        if [[ "$cmd" == "bash" && "$3" == "-s" ]]; then
            # in_path:in_bashrc -> 0:0
            echo "0:0"
            return 0
        fi
        return 1
    }
    
    rsd::l::remote::prompt_user() {
        return 1  # User declines
    }
    
    run rsd::c::remote::setup_path
    [ "$status" -eq 1 ]
    [[ "$output" == *"Abort: Path setup declined by user."* ]]
    
    unset RSD_REMOTE_TARGET
}

