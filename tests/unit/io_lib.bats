#!/usr/bin/env bats

# Tests for io.lib — output formatting, SSH noise filtering, frame_lines
# @see lib/io.lib

setup() {
    export RSD_ON=1
    export RSD_DEBUG=0
    export RSD_MODE="devel"
    export RSD_RUN_DIR="${BATS_TEST_DIRNAME}/../../"

    declare -ga RSD_LIBRARY_SEARCH_PATH
    RSD_LIBRARY_SEARCH_PATH+=("${BATS_TEST_DIRNAME}/../../")

    source "${BATS_TEST_DIRNAME}/../../lib/io.lib"
}

# Helper: pipe input through frame_lines and capture fd 7 output.
_frame() {
    RSD_IO_FRAME_CMD="$1"
    shift
    printf '%s\n' "$@" | rsd::l::io::frame_lines 7>&1
}

# ==============================================================================
# SSH Noise Filter — frame_lines
# ==============================================================================

@test "frame_lines filters 'Connection to <host> closed.' lines" {
    run _frame "test_task" \
        "useful output" \
        "Connection to flow.jumba.com.br closed." \
        "more useful output"

    [ "$status" -eq 0 ]
    [[ "$output" == *"useful output"* ]]
    [[ "$output" == *"more useful output"* ]]
    [[ "$output" != *"Connection to"* ]]
    [[ "$output" != *"closed."* ]]
}

@test "frame_lines filters multiple consecutive SSH close messages" {
    run _frame "deploy" \
        "Connection to 10.0.0.1 closed." \
        "Connection to 10.0.0.1 closed." \
        "Connection to 10.0.0.1 closed." \
        "actual data"

    [ "$status" -eq 0 ]
    [[ "$output" == *"actual data"* ]]
    [[ "$output" != *"Connection to"* ]]
}

@test "frame_lines suppresses empty lines following SSH noise" {
    run _frame "task" \
        "before" \
        "Connection to server.example.com closed." \
        "" \
        "after"

    [ "$status" -eq 0 ]
    [[ "$output" == *"before"* ]]
    [[ "$output" == *"after"* ]]
    # Count output lines (non-empty) — should be exactly 2 (before + after)
    local line_count
    line_count=$(echo "$output" | grep -c '│')
    [ "$line_count" -eq 2 ]
}

@test "frame_lines preserves empty lines NOT following SSH noise" {
    run _frame "task" \
        "line 1" \
        "" \
        "line 2"

    [ "$status" -eq 0 ]
    [[ "$output" == *"line 1"* ]]
    [[ "$output" == *"line 2"* ]]
    # Should have 3 framed lines (line1, empty, line2)
    local line_count
    line_count=$(echo "$output" | grep -c '│')
    [ "$line_count" -eq 3 ]
}

@test "frame_lines does NOT filter lines that partially match SSH noise" {
    run _frame "task" \
        "Connection to database established" \
        "The connection was closed." \
        "Connection to server"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Connection to database established"* ]]
    [[ "$output" == *"The connection was closed."* ]]
    [[ "$output" == *"Connection to server"* ]]
}

@test "frame_lines handles various hostnames in SSH noise" {
    run _frame "task" \
        "Connection to 192.168.1.1 closed." \
        "Connection to my-server.internal closed." \
        "Connection to flow.jumba.com.br closed." \
        "real output"

    [ "$status" -eq 0 ]
    [[ "$output" == *"real output"* ]]
    [[ "$output" != *"Connection to"* ]]
}

# ==============================================================================
# frame_lines — basic formatting
# ==============================================================================

@test "frame_lines prefixes output with pipe character" {
    run _frame "my_task" "hello world"

    [ "$status" -eq 0 ]
    [[ "$output" == *"│"* ]]
    [[ "$output" == *"hello world"* ]]
}

@test "frame_lines includes command tag when RSD_IO_FRAME_CMD is set" {
    run _frame "deploy" "test line"

    [ "$status" -eq 0 ]
    [[ "$output" == *"deploy"* ]]
    [[ "$output" == *"test line"* ]]
}

@test "frame_lines works with empty RSD_IO_FRAME_CMD" {
    run _frame "" "bare output"

    [ "$status" -eq 0 ]
    [[ "$output" == *"bare output"* ]]
}

# ==============================================================================
# Consecutive empty line dedup
# ==============================================================================

@test "frame_lines deduplicates consecutive empty lines" {
    run _frame "task" \
        "line 1" \
        "" \
        "" \
        "" \
        "line 2"

    [ "$status" -eq 0 ]
    [[ "$output" == *"line 1"* ]]
    [[ "$output" == *"line 2"* ]]
    # Should have 3 framed lines: line1, ONE empty, line2
    local line_count
    line_count=$(echo "$output" | grep -c '│')
    [ "$line_count" -eq 3 ]
}

@test "frame_lines preserves a single empty line between content" {
    run _frame "task" \
        "line 1" \
        "" \
        "line 2"

    [ "$status" -eq 0 ]
    local line_count
    line_count=$(echo "$output" | grep -c '│')
    [ "$line_count" -eq 3 ]
}

# ==============================================================================
# Origin Tag Computation — compute_tag
# ==============================================================================

@test "compute_tag defaults to [rsd] for local execution" {
    unset RSD_IO_ORIGIN
    rsd::l::io::compute_tag

    [ "$RSD_IO_TAG" = "[rsd]" ]
}

@test "compute_tag uses [rsd@host] when RSD_IO_ORIGIN is set" {
    RSD_IO_ORIGIN="flow"
    rsd::l::io::compute_tag

    [ "$RSD_IO_TAG" = "[rsd@flow]" ]
    unset RSD_IO_ORIGIN
}

@test "compute_tag supports multi-hop chain via RSD_IO_ORIGIN" {
    RSD_IO_ORIGIN="gw→flow"
    rsd::l::io::compute_tag

    [ "$RSD_IO_TAG" = "[rsd@gw→flow]" ]
    unset RSD_IO_ORIGIN
}

@test "compute_tag ignores RSD_REMOTE_TARGET (local orchestrator stays [rsd])" {
    unset RSD_IO_ORIGIN
    RSD_REMOTE_TARGET="@flow"
    rsd::l::io::compute_tag

    [ "$RSD_IO_TAG" = "[rsd]" ]
    unset RSD_REMOTE_TARGET
}

@test "compute_tag with RSD_IO_ORIGIN takes precedence even if RSD_REMOTE_TARGET is set" {
    RSD_IO_ORIGIN="flow"
    RSD_REMOTE_TARGET="@flow"
    rsd::l::io::compute_tag

    [ "$RSD_IO_TAG" = "[rsd@flow]" ]
    unset RSD_IO_ORIGIN RSD_REMOTE_TARGET
}

# ==============================================================================
# Semantic Emitters — tag presence in output
# ==============================================================================

@test "rsd::io::info includes origin tag in output" {
    RSD_IO_TAG="[rsd]"
    run bash -c 'source "'"${BATS_TEST_DIRNAME}"'/../../lib/io.lib" && rsd::io::info "test message" 7>&1'

    [ "$status" -eq 0 ]
    [[ "$output" == *"[rsd]"* ]]
    [[ "$output" == *"test message"* ]]
}

@test "rsd::io::info shows remote tag when RSD_IO_ORIGIN is set" {
    RSD_IO_ORIGIN="flow"
    run bash -c '
        export RSD_ON=1 RSD_DEBUG=0 RSD_MODE=devel RSD_IO_ORIGIN=flow
        source "'"${BATS_TEST_DIRNAME}"'/../../lib/io.lib"
        rsd::io::info "remote message" 7>&1
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"[rsd@flow]"* ]]
    [[ "$output" == *"remote message"* ]]
    unset RSD_IO_ORIGIN
}

# ==============================================================================
# Debug Message Dedup
# ==============================================================================

@test "debug dedup suppresses consecutive identical messages" {
    run bash -c '
        export RSD_ON=1 RSD_DEBUG=10 RSD_MODE=devel _RSD_DEBUG_LAST_MSG=""
        declare -ga RSD_LIBRARY_SEARCH_PATH=("'"${BATS_TEST_DIRNAME}"'/../../")
        source "'"${BATS_TEST_DIRNAME}"'/../../lib/rsd.lib"
        rsd::debug "same message" 1
        rsd::debug "same message" 1
        rsd::debug "same message" 1
    '

    [ "$status" -eq 0 ]
    local msg_count
    msg_count=$(echo "$output" | grep -c "same message")
    [ "$msg_count" -eq 1 ]
}

@test "debug dedup allows different messages through" {
    run bash -c '
        export RSD_ON=1 RSD_DEBUG=10 RSD_MODE=devel _RSD_DEBUG_LAST_MSG=""
        declare -ga RSD_LIBRARY_SEARCH_PATH=("'"${BATS_TEST_DIRNAME}"'/../../")
        source "'"${BATS_TEST_DIRNAME}"'/../../lib/rsd.lib"
        rsd::debug "message A" 1
        rsd::debug "message B" 1
        rsd::debug "message A" 1
    '

    [ "$status" -eq 0 ]
    local a_count b_count
    a_count=$(echo "$output" | grep -c "message A")
    b_count=$(echo "$output" | grep -c "message B")
    [ "$a_count" -eq 2 ]
    [ "$b_count" -eq 1 ]
}

@test "debug messages include [rsd] prefix" {
    run bash -c '
        export RSD_ON=1 RSD_DEBUG=10 RSD_MODE=devel _RSD_DEBUG_LAST_MSG=""
        declare -ga RSD_LIBRARY_SEARCH_PATH=("'"${BATS_TEST_DIRNAME}"'/../../")
        source "'"${BATS_TEST_DIRNAME}"'/../../lib/rsd.lib"
        rsd::debug "test prefix" 1
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"[rsd]"* ]]
    [[ "$output" == *"test prefix"* ]]
}

@test "debug messages use RSD_IO_TAG when available" {
    run bash -c '
        export RSD_ON=1 RSD_DEBUG=10 RSD_MODE=devel _RSD_DEBUG_LAST_MSG=""
        export RSD_IO_TAG="[rsd@flow]"
        declare -ga RSD_LIBRARY_SEARCH_PATH=("'"${BATS_TEST_DIRNAME}"'/../../")
        source "'"${BATS_TEST_DIRNAME}"'/../../lib/rsd.lib"
        rsd::debug "remote debug" 1
    '

    [ "$status" -eq 0 ]
    [[ "$output" == *"[rsd@flow]"* ]]
    [[ "$output" == *"remote debug"* ]]
}

