#!/usr/bin/env bats

# Unit tests for lib/vm.lib and lib/vm/libvirt.lib
# Tests pure-logic functions only — no virsh/virt-install calls.

setup() {
    export RSD_ON=1
    export RSD_DEBUG=0

    # Initialize framework search path
    export RSD_MODE="devel"
    export RSD_RUN_DIR="${BATS_TEST_DIRNAME}/../../"
    declare -ga RSD_LIBRARY_SEARCH_PATH
    RSD_LIBRARY_SEARCH_PATH+=("${BATS_TEST_DIRNAME}/../../")

    # Declare global arrays to prevent arithmetic syntax errors
    declare -g -A RSD_ARGS
    declare -g -A RSD_COMMAND_ARGS
    declare -g -A RSD_ARGS_PARAM

    # Stub create search path
    rsd::create_search_path() {
        return 0
    }

    # Source core framework
    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/config.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/io.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/vm.lib"

    # Create temporary directory for test fixtures
    TEST_TMP_DIR=$(mktemp -d -t rsd-vm-test.XXXXXX)
}

teardown() {
    rm -rf "$TEST_TMP_DIR"
}

# ==============================================================================
# VM Name Validation
# ==============================================================================

@test "validate_name: accepts valid alphanumeric name" {
    rsd::l::vm::validate_name "ubuntu-test" 7>&1
    [ "$?" -eq 0 ]
}

@test "validate_name: accepts name with underscores" {
    rsd::l::vm::validate_name "my_vm_01" 7>&1
    [ "$?" -eq 0 ]
}

@test "validate_name: accepts single-letter name" {
    rsd::l::vm::validate_name "a" 7>&1
    [ "$?" -eq 0 ]
}

@test "validate_name: rejects empty name" {
    run rsd::l::vm::validate_name "" 7>&1
    [ "$status" -eq 1 ]
}

@test "validate_name: rejects name starting with digit" {
    run rsd::l::vm::validate_name "0test" 7>&1
    [ "$status" -eq 1 ]
}

@test "validate_name: rejects name starting with hyphen" {
    run rsd::l::vm::validate_name "-test" 7>&1
    [ "$status" -eq 1 ]
}

@test "validate_name: rejects name with spaces" {
    run rsd::l::vm::validate_name "my vm" 7>&1
    [ "$status" -eq 1 ]
}

@test "validate_name: rejects name with dots" {
    run rsd::l::vm::validate_name "my.vm" 7>&1
    [ "$status" -eq 1 ]
}

@test "validate_name: rejects name exceeding 63 characters" {
    local long_name
    long_name=$(printf 'a%.0s' {1..64})
    run rsd::l::vm::validate_name "$long_name" 7>&1
    [ "$status" -eq 1 ]
}

@test "validate_name: accepts name at exactly 63 characters" {
    local name63
    name63=$(printf 'a%.0s' {1..63})
    rsd::l::vm::validate_name "$name63" 7>&1
    [ "$?" -eq 0 ]
}

# ==============================================================================
# VM Name Prefix
# ==============================================================================

@test "prefixed_name: applies default prefix" {
    local result
    result=$(rsd::l::vm::prefixed_name "my-vm")
    [ "$result" = "rsd-my-vm" ]
}

@test "prefixed_name: is idempotent — does not double-prefix" {
    local result
    result=$(rsd::l::vm::prefixed_name "rsd-my-vm")
    [ "$result" = "rsd-my-vm" ]
}

@test "prefixed_name: respects custom prefix from config" {
    declare -g -A R_INI_vm
    R_INI_vm["defaults.prefix"]="test-"

    local result
    result=$(rsd::l::vm::prefixed_name "myvm")
    [ "$result" = "test-myvm" ]

    unset 'R_INI_vm[defaults.prefix]'
}

@test "display_name: strips default prefix" {
    local result
    result=$(rsd::l::vm::display_name "rsd-my-vm")
    [ "$result" = "my-vm" ]
}

@test "display_name: returns unprefixed name unchanged" {
    local result
    result=$(rsd::l::vm::display_name "other-vm")
    [ "$result" = "other-vm" ]
}

@test "prefix: returns default rsd-" {
    local result
    result=$(rsd::l::vm::prefix)
    [ "$result" = "rsd-" ]
}

# ==============================================================================
# Snapshot Name Sanitization
# ==============================================================================

@test "sanitize_snapshot_name: passes through clean names" {
    local snap="my-snapshot-01"
    rsd::l::vm::sanitize_snapshot_name snap
    [ "$snap" = "my-snapshot-01" ]
}

@test "sanitize_snapshot_name: replaces spaces with hyphens" {
    local snap="my snapshot name"
    rsd::l::vm::sanitize_snapshot_name snap
    [ "$snap" = "my-snapshot-name" ]
}

@test "sanitize_snapshot_name: replaces special characters" {
    local snap="snap@2024!test#1"
    rsd::l::vm::sanitize_snapshot_name snap
    [ "$snap" = "snap-2024-test-1" ]
}

@test "sanitize_snapshot_name: collapses consecutive hyphens" {
    local snap="snap---test"
    rsd::l::vm::sanitize_snapshot_name snap
    [ "$snap" = "snap-test" ]
}

@test "sanitize_snapshot_name: trims leading and trailing hyphens" {
    local snap="-snap-test-"
    rsd::l::vm::sanitize_snapshot_name snap
    [ "$snap" = "snap-test" ]
}

@test "sanitize_snapshot_name: truncates to 63 characters" {
    local snap
    snap=$(printf 'a%.0s' {1..80})
    rsd::l::vm::sanitize_snapshot_name snap
    [ "${#snap}" -eq 63 ]
}

@test "sanitize_snapshot_name: preserves underscores" {
    local snap="my_snap_01"
    rsd::l::vm::sanitize_snapshot_name snap
    [ "$snap" = "my_snap_01" ]
}

# ==============================================================================
# Image Registry Resolution
# ==============================================================================

@test "resolve_image: parses distro-version format correctly" {
    local distro version url
    rsd::l::vm::resolve_image "ubuntu-26.04" distro version url 7>&1
    [ "$?" -eq 0 ]
    [ "$distro" = "ubuntu" ]
    [ "$version" = "26.04" ]
    [[ "$url" == *"ubuntu"* ]]
}

@test "resolve_image: resolves debian image" {
    local distro version url
    rsd::l::vm::resolve_image "debian-12" distro version url 7>&1
    [ "$?" -eq 0 ]
    [ "$distro" = "debian" ]
    [ "$version" = "12" ]
    [[ "$url" == *"debian"* ]]
}

@test "resolve_image: rejects spec without hyphen separator" {
    local distro version url
    run rsd::l::vm::resolve_image "ubuntu2604" distro version url 7>&1
    [ "$status" -eq 1 ]
}

@test "resolve_image: rejects unknown distro-version combination" {
    local distro version url
    run rsd::l::vm::resolve_image "fedora-40" distro version url 7>&1
    [ "$status" -eq 1 ]
}

# ==============================================================================
# Connection Mode Resolution
# ==============================================================================

@test "resolve_connection: defaults to session mode" {
    local uri
    rsd::l::vm::resolve_connection 0 uri
    [ "$uri" = "qemu:///session" ]
}

@test "resolve_connection: system flag overrides to system mode" {
    local uri
    rsd::l::vm::resolve_connection 1 uri
    [ "$uri" = "qemu:///system" ]
}

@test "resolve_connection: respects config when no flag set" {
    # Override config to system
    declare -g -A R_INI_vm
    R_INI_vm["defaults.mode"]="system"

    local uri
    rsd::l::vm::resolve_connection 0 uri
    [ "$uri" = "qemu:///system" ]

    # Cleanup
    R_INI_vm["defaults.mode"]="session"
}

# ==============================================================================
# Cache Management
# ==============================================================================

@test "cache_filename: generates deterministic filename from URL" {
    local filename
    filename=$(rsd::l::vm::cache_filename "ubuntu" "26.04" "https://example.com/noble-server-cloudimg-amd64.img")
    [ "$filename" = "ubuntu-26.04-amd64.img" ]
}

@test "cache_filename: extracts qcow2 extension" {
    local filename
    filename=$(rsd::l::vm::cache_filename "debian" "12" "https://example.com/debian-12-generic-amd64.qcow2")
    [ "$filename" = "debian-12-amd64.qcow2" ]
}

@test "cache_enabled: returns true by default" {
    rsd::l::vm::cache_enabled
    [ "$?" -eq 0 ]
}

@test "cache_enabled: respects false config" {
    declare -g -A R_INI_vm
    R_INI_vm["cache.enabled"]="false"

    run rsd::l::vm::cache_enabled
    [ "$status" -eq 1 ]

    R_INI_vm["cache.enabled"]="true"
}

@test "cache_dir: expands tilde to HOME" {
    local dir
    dir=$(rsd::l::vm::cache_dir)
    [[ "$dir" != *"~"* ]]
    [[ "$dir" == "$HOME"* ]]
}

# ==============================================================================
# Cloud-Init Template Rendering
# ==============================================================================

@test "render_template: replaces all placeholder tokens" {
    local template="${TEST_TMP_DIR}/template.yaml"
    local output="${TEST_TMP_DIR}/rendered.yaml"

    cat > "$template" <<'EOF'
hostname: %%HOSTNAME%%
user: %%USERNAME%%
key: %%SSH_PUB_KEY%%
id: %%INSTANCE_ID%%
EOF

    rsd::l::vm::render_template "$template" "$output" \
        "test-vm" "myuser" "ssh-ed25519 AAAA..." "rsd-test-vm"

    [ -f "$output" ]
    grep -q "hostname: test-vm" "$output"
    grep -q "user: myuser" "$output"
    grep -q "key: ssh-ed25519 AAAA..." "$output"
    grep -q "id: rsd-test-vm" "$output"
}

@test "render_template: handles multiple occurrences of same placeholder" {
    local template="${TEST_TMP_DIR}/multi.yaml"
    local output="${TEST_TMP_DIR}/multi_rendered.yaml"

    cat > "$template" <<'EOF'
name: %%HOSTNAME%%
fqdn: %%HOSTNAME%%.local
EOF

    rsd::l::vm::render_template "$template" "$output" "myvm"
    grep -q "name: myvm" "$output"
    grep -q "fqdn: myvm.local" "$output"
}

@test "render_template: returns error for missing template file" {
    run rsd::l::vm::render_template "/nonexistent/template" "/tmp/out" "test" 7>&1
    [ "$status" -eq 1 ]
}

# ==============================================================================
# Config Accessor
# ==============================================================================

@test "config: returns INI value when set" {
    declare -g -A R_INI_vm
    R_INI_vm["defaults.driver"]="libvirt"

    local val
    val=$(rsd::l::vm::config "defaults.driver" "fallback")
    [ "$val" = "libvirt" ]
}

@test "config: returns fallback when key not set" {
    declare -g -A R_INI_vm
    unset 'R_INI_vm[nonexistent.key]' 2>/dev/null || true

    local val
    val=$(rsd::l::vm::config "nonexistent.key" "my-default")
    [ "$val" = "my-default" ]
}

# ==============================================================================
# Cloud-Init Template Files (data/vm/ validation)
# ==============================================================================

@test "user-data template contains required placeholders" {
    local tpl="${BATS_TEST_DIRNAME}/../../data/vm/cloud-init/user-data.yaml"
    [ -f "$tpl" ]
    grep -q "%%HOSTNAME%%" "$tpl"
    grep -q "%%USERNAME%%" "$tpl"
    grep -q "%%SSH_PUB_KEY%%" "$tpl"
}

@test "meta-data template contains required placeholders" {
    local tpl="${BATS_TEST_DIRNAME}/../../data/vm/cloud-init/meta-data.yaml"
    [ -f "$tpl" ]
    grep -q "%%INSTANCE_ID%%" "$tpl"
    grep -q "%%HOSTNAME%%" "$tpl"
}

# ==============================================================================
# Image Registry File (data/vm/images.ini validation)
# ==============================================================================

@test "images.ini exists and contains ubuntu section" {
    local ini="${BATS_TEST_DIRNAME}/../../data/vm/images.ini"
    [ -f "$ini" ]
    grep -q "\[ubuntu\]" "$ini"
    grep -q "26.04=" "$ini"
}

@test "images.ini contains valid URLs" {
    local ini="${BATS_TEST_DIRNAME}/../../data/vm/images.ini"
    local bad_lines=0
    while IFS= read -r line; do
        case "$line" in
            '#'*|';'*|'['*|'') continue ;;
        esac
        if [[ "$line" != *"=http"* ]]; then
            bad_lines=$((bad_lines + 1))
        fi
    done < "$ini"
    [ "$bad_lines" -eq 0 ]
}
