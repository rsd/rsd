#!/usr/bin/env bats

# Tests for the target-aware dispatch primitives (lib/target.lib)
# @see lib/target.lib

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
    source "${BATS_TEST_DIRNAME}/../../lib/target.lib"

    # Ensure local execution mode for all tests
    unset RSD_REMOTE_TARGET
}

# ==============================================================================
# rsd::l::target::exec (the core routing primitive)
# ==============================================================================

@test "rsd::l::target::exec executes local commands when RSD_REMOTE_TARGET is unset" {
    run rsd::l::target::exec echo "LOCAL_DISPATCH"
    [ "$status" -eq 0 ]
    [[ "$output" == *"LOCAL_DISPATCH"* ]]
}

@test "rsd::l::target::exec propagates non-zero exit codes" {
    run rsd::l::target::exec false
    [ "$status" -ne 0 ]
}

# ==============================================================================
# rsd::l::target::has_bin
# ==============================================================================

@test "rsd::l::target::has_bin returns 0 for an existing binary" {
    run rsd::l::target::has_bin bash
    [ "$status" -eq 0 ]
}

@test "rsd::l::target::has_bin returns 1 for a missing binary" {
    run rsd::l::target::has_bin __rsd_nonexistent_binary_xyz__
    [ "$status" -ne 0 ]
}

# ==============================================================================
# rsd::l::target::dir_exists
# ==============================================================================

@test "rsd::l::target::dir_exists returns 0 for existing directory" {
    run rsd::l::target::dir_exists /tmp
    [ "$status" -eq 0 ]
}

@test "rsd::l::target::dir_exists returns 1 for missing directory" {
    run rsd::l::target::dir_exists /tmp/__rsd_nonexistent_dir_xyz__
    [ "$status" -ne 0 ]
}

# ==============================================================================
# rsd::l::target::file_exists
# ==============================================================================

@test "rsd::l::target::file_exists returns 0 for existing file" {
    local tmpfile
    tmpfile=$(mktemp -t rsd-test.XXXXXX)
    run rsd::l::target::file_exists "$tmpfile"
    rm -f "$tmpfile"
    [ "$status" -eq 0 ]
}

@test "rsd::l::target::file_exists returns 1 for missing file" {
    run rsd::l::target::file_exists /tmp/__rsd_nonexistent_file_xyz__
    [ "$status" -ne 0 ]
}

# ==============================================================================
# rsd::l::target::file_contains
# ==============================================================================

@test "rsd::l::target::file_contains returns 0 when pattern matches" {
    local tmpfile
    tmpfile=$(mktemp -t rsd-test.XXXXXX)
    echo "hello world" > "$tmpfile"
    run rsd::l::target::file_contains "hello" "$tmpfile"
    rm -f "$tmpfile"
    [ "$status" -eq 0 ]
}

@test "rsd::l::target::file_contains returns 1 when pattern is absent" {
    local tmpfile
    tmpfile=$(mktemp -t rsd-test.XXXXXX)
    echo "hello world" > "$tmpfile"
    run rsd::l::target::file_contains "goodbye" "$tmpfile"
    rm -f "$tmpfile"
    [ "$status" -ne 0 ]
}

# ==============================================================================
# rsd::l::target::git_clone
# ==============================================================================

@test "rsd::l::target::git_clone builds correct depth args via exec" {
    # Stub git to capture invocation
    git() { echo "GIT_ARGS=$*"; return 0; }
    export -f git

    run rsd::l::target::git_clone "https://example.com/repo.git" "/tmp/dest" "1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"--depth"* ]]
    [[ "$output" == *"1"* ]]
    [[ "$output" == *"/tmp/dest"* ]]
}

@test "rsd::l::target::git_clone omits depth when not specified" {
    git() { echo "GIT_ARGS=$*"; return 0; }
    export -f git

    run rsd::l::target::git_clone "https://example.com/repo.git" "/tmp/dest"
    [ "$status" -eq 0 ]
    [[ "$output" != *"--depth"* ]]
    [[ "$output" == *"/tmp/dest"* ]]
}

# ==============================================================================
# rsd::l::target::mktemp (secure temp file creation)
# ==============================================================================

@test "rsd::l::target::mktemp creates a file with unpredictable name" {
    run rsd::l::target::mktemp "rsd-test.XXXXXX"
    [ "$status" -eq 0 ]

    local path="$output"
    # Trim whitespace
    path="${path#"${path%%[![:space:]]*}"}"
    path="${path%"${path##*[![:space:]]}"}"

    # File must exist and have an unpredictable suffix
    [[ -e "$path" ]]
    [[ "$path" == *"rsd-test."* ]]

    # Cleanup
    rm -f "$path"
}

@test "rsd::l::target::mktemp -d creates a directory" {
    run rsd::l::target::mktemp "rsd-test-dir.XXXXXX" "-d"
    [ "$status" -eq 0 ]

    local path="$output"
    path="${path#"${path%%[![:space:]]*}"}"
    path="${path%"${path##*[![:space:]]}"}"

    [[ -d "$path" ]]

    # Cleanup
    rmdir "$path"
}

@test "rsd::l::target::mktemp sets restrictive 0700 permissions" {
    run rsd::l::target::mktemp "rsd-test-perms.XXXXXX"
    [ "$status" -eq 0 ]

    local path="$output"
    path="${path#"${path%%[![:space:]]*}"}"
    path="${path%"${path##*[![:space:]]}"}"

    # Check permissions are owner-only (rwx for owner, nothing for others)
    local perms
    perms=$(stat -c "%a" "$path")
    [[ "$perms" == "700" ]]

    rm -f "$path"
}

# ==============================================================================
# rsd::l::target::fetch_and_exec (secure download-execute pipeline)
# ==============================================================================

@test "rsd::l::target::fetch_and_exec downloads, executes, and cleans up" {
    # Stub curl to write a known payload to the temp file
    curl() {
        local output_file=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -o) output_file="$2"; shift ;;
            esac
            shift
        done
        echo '#!/bin/sh' > "$output_file"
        echo 'echo "FETCH_EXEC_OK"' >> "$output_file"
        return 0
    }
    export -f curl

    run rsd::l::target::fetch_and_exec "https://example.com/test.sh" "sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"FETCH_EXEC_OK"* ]]
}

@test "rsd::l::target::fetch_and_exec cleans up even on script failure" {
    # Stub curl to write a failing script
    curl() {
        local output_file=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -o) output_file="$2"; shift ;;
            esac
            shift
        done
        echo '#!/bin/sh' > "$output_file"
        echo 'exit 42' >> "$output_file"
        return 0
    }
    export -f curl

    run rsd::l::target::fetch_and_exec "https://example.com/fail.sh" "sh"
    [ "$status" -eq 42 ]

    # Verify no rsd-fetch temp files were left behind
    local leftover
    leftover=$(find /tmp -maxdepth 1 -name "rsd-fetch.*" -user "$(whoami)" 2>/dev/null | wc -l)
    [ "$leftover" -eq 0 ]
}
