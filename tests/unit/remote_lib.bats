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

    # Source core wrapper dependencies and config
    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/config.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/remote.lib"
}

@test "rsd::l::remote::parse_spec splits standard SSH target" {
    local proto user host port
    rsd::l::remote::parse_spec "userA@hostA" proto user host port

    [ "$proto" = "ssh" ]
    [ "$user" = "userA" ]
    [ "$host" = "hostA" ]
    [ -z "$port" ]
}

@test "rsd::l::remote::parse_spec splits custom protocol scheme and port" {
    local proto user host port
    rsd::l::remote::parse_spec "lxc://root@container-db:8080" proto user host port

    [ "$proto" = "lxc" ]
    [ "$user" = "root" ]
    [ "$host" = "container-db" ]
    [ "$port" = "8080" ]
}

@test "rsd::l::remote::parse_spec splits sudo targets" {
    local proto user host port
    rsd::l::remote::parse_spec "sudo://root" proto user host port

    [ "$proto" = "sudo" ]
    [ "$user" = "root" ]
    [ -z "$host" ]
    [ -z "$port" ]
}

@test "rsd::l::remote::parse_spec defaults host-only targets to SSH" {
    local proto user host port
    rsd::l::remote::parse_spec "gateway.production" proto user host port

    [ "$proto" = "ssh" ]
    [ -z "$user" ]
    [ "$host" = "gateway.production" ]
    [ -z "$port" ]
}

@test "rsd::l::remote::resolve_pathway expands config pathways and individual host aliases recursively" {
    # Verify INI config array exists
    [ -n "${R_INI_remote[pathways.production-web]}" ]

    local -a hops=()
    rsd::l::remote::resolve_pathway "@production-web" hops

    # Resolves pathways.production-web -> @gateway,target
    # Resolves hosts.gateway -> ssh://admin@10.0.0.1:2222
    # Resolves hosts.target -> ssh://developer@192.168.1.50
    [ "${#hops[@]}" -eq 2 ]
    [ "${hops[0]}" = "ssh://admin@10.0.0.1:2222" ]
    [ "${hops[1]}" = "ssh://developer@192.168.1.50" ]
}

@test "rsd::l::remote::resolve_pathway splits raw comma-separated lists" {
    local -a hops=()
    rsd::l::remote::resolve_pathway "hostX,hostY" hops

    [ "${#hops[@]}" -eq 2 ]
    [ "${hops[0]}" = "hostX" ]
    [ "${hops[1]}" = "hostY" ]
}

@test "rsd::l::remote::delegate compiles and dispatches nested right-to-left wrapped execution" {
    # Mock the SSH protocol execution handler
    rsd::l::protocol::ssh::run() {
        echo "CALLED_SSH: user=$1 host=$2 port=$3 payload=(${@:4})"
        return 0
    }

    # Execute a two-hop chained path
    run rsd::l::remote::delegate "hostA,lxc://root@containerB" "gpg" "check"

    [ "$status" -eq 0 ]
    
    # Outer hop (SSH) should be executed locally, with the inner LXC hop compiled and nested inside
    [[ "$output" == *"CALLED_SSH: user= host=hostA port="* ]]
    [[ "$output" == *"payload=(lxc-attach -n containerB --clear-env --user root -- gpg check)"* ]]
}

@test "rsd::l::remote::delegate compiles and dispatches intermediate sudo hops" {
    export RSD_MOCK_SUDO_PASSWORD="remote-sudo-pass"

    # Mock the SSH execution runner
    rsd::l::protocol::ssh::run() {
        echo "CALLED_SSH: user=$1 host=$2 port=$3 payload=(${@:4})"
        return 0
    }

    # Execute a pathway: hostA (SSH), sudo://root
    run rsd::l::remote::delegate "hostA,sudo://root" "gpg" "check"

    [ "$status" -eq 0 ]
    [[ "$output" == *"CALLED_SSH: user= host=hostA port="* ]]
    [[ "$output" == *"payload=(sh -c echo 'remote-sudo-pass' | sudo -S -p '' -u root --  'gpg' 'check')"* ]]

    unset RSD_MOCK_SUDO_PASSWORD
}

@test "rsd::l::remote::prompt_user correctly parses mock prompts" {
    # 1. User accepts (Mock Y)
    export RSD_MOCK_PROMPT_REPLY="Y"
    run rsd::l::remote::prompt_user "Mock prompt?"
    [ "$status" -eq 0 ]
    
    # 2. User declines (Mock N)
    export RSD_MOCK_PROMPT_REPLY="N"
    run rsd::l::remote::prompt_user "Mock prompt?"
    [ "$status" -eq 1 ]
}

@test "rsd::l::remote::bootstrap_check handles remote targets with framework already installed" {
    # Mock dynamic ssh probe command execution
    rsd::l::remote::execute() {
        local target="$1"
        local cmd="$2"
        if [[ "$cmd" == "rsd" && "$3" == "--version" ]]; then
            echo "1.9.12"
            return 0
        fi
        return 1
    }
    
    local rsd_bin=""
    rsd::l::remote::bootstrap_check "mock-host" rsd_bin
    
    [ "$?" -eq 0 ]
    [ "$rsd_bin" = "rsd" ]
}

@test "rsd::l::remote::bootstrap_check aborts if framework is missing and user declines installation" {
    # Mock probe failure (RSD missing remotely)
    rsd::l::remote::execute() {
        return 127
    }
    
    # Mock user declining installation
    rsd::l::remote::prompt_user() {
        return 1
    }
    
    local rsd_bin=""
    run rsd::l::remote::bootstrap_check "mock-host" rsd_bin
    [ "$status" -eq 1 ]
}

@test "rsd::l::remote::bootstrap_check warns but continues if remote is older and user declines upgrade" {
    # Mock probe returning an older remote version
    rsd::l::remote::execute() {
        local cmd="$2"
        if [[ "$cmd" == "rsd" && "$3" == "--version" ]]; then
            echo "1.8.0"
            return 0
        fi
        return 1
    }
    
    # Mock user declining upgrade
    rsd::l::remote::prompt_user() {
        return 1
    }
    
    local rsd_bin=""
    rsd::l::remote::bootstrap_check "mock-host" rsd_bin
    
    [ "$?" -eq 0 ]
    [ "$rsd_bin" = "rsd" ]
}

@test "rsd::l::remote::bootstrap_check blocks bootstrapping if allow_bootstrap is false and framework is missing" {
    # Ensure R_INI_hosts associative array exists
    declare -gA R_INI_hosts
    R_INI_hosts["hosts.blocked-host.allow_bootstrap"]="false"
    
    # Mock probe failure (RSD missing remotely)
    rsd::l::remote::execute() {
        return 127
    }
    
    # Stub load_config to prevent loading real files
    rsd::l::host::load_config() {
        return 0
    }
    
    local rsd_bin=""
    run rsd::l::remote::bootstrap_check "blocked-host" rsd_bin
    [ "$status" -eq 1 ]
}

@test "rsd::l::remote::bootstrap_check skips upgrade but executes if allow_bootstrap is false and remote has older version" {
    declare -gA R_INI_hosts
    R_INI_hosts["hosts.readonly-host.allow_bootstrap"]="no"
    
    # Mock probe returning an older remote version
    rsd::l::remote::execute() {
        local cmd="$2"
        if [[ "$cmd" == "rsd" && "$3" == "--version" ]]; then
            echo "1.8.0"
            return 0
        fi
        return 1
    }
    
    # Stub load_config to prevent loading real files
    rsd::l::host::load_config() {
        return 0
    }
    
    local rsd_bin=""
    rsd::l::remote::bootstrap_check "readonly-host" rsd_bin
    
    [ "$?" -eq 0 ]
    [ "$rsd_bin" = "rsd" ]
}

@test "rsd::l::remote::bootstrap_check handles trailing carriage returns and CRLF in version string correctly" {
    export RSD_VERSION="1.9.12"
    # Mock probe returning an older remote version with trailing carriage return and newline
    rsd::l::remote::execute() {
        local cmd="$2"
        if [[ "$cmd" == "rsd" && "$3" == "--version" ]]; then
            printf "1.8.0\r\n"
            return 0
        fi
        return 1
    }
    
    # Mock user declining upgrade
    rsd::l::remote::prompt_user() {
        return 1
    }
    
    local rsd_bin=""
    run rsd::l::remote::bootstrap_check "mock-host" rsd_bin
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"Warning: Remote framework version (1.8.0) is"* ]]
    # Assert that no carriage return carriage remains in output to prevent line overwrites
    [[ "$output" != *$'\r'* ]]
}



