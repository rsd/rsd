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
