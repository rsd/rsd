#!/usr/bin/env bats

setup() {
    RSD_BIN="${BATS_TEST_DIRNAME}/../../rsd"
    
    # Create isolated sandbox directory
    TEST_SANDBOX_DIR=$(mktemp -d -t rsd-sandbox.XXXXXX)
    export HOME="$TEST_SANDBOX_DIR"
    export GNUPGHOME="${TEST_SANDBOX_DIR}/.gnupg"
    mkdir -p -m 700 "$GNUPGHOME"
    
    # Configure GPG to bypass interactive pinentry prompts for signing in headless environments
    echo "allow-loopback-pinentry" > "${GNUPGHOME}/gpg-agent.conf"
    echo "pinentry-mode loopback" > "${GNUPGHOME}/gpg.conf"
    gpg-connect-agent reloadagent /bye 2>/dev/null || true
    
    # Determine local hostname natively matching net.lib's algorithm
    local host_id
    if [[ -n "$HOSTNAME" ]]; then
        host_id="$HOSTNAME"
    elif [[ -f /etc/hostname ]]; then
        host_id=$(cat /etc/hostname)
    else
        host_id=$(hostname 2>/dev/null || echo "localhost")
    fi
    
    # Create a real GPG key non-interactively using RSA keys explicitly
    cat <<EOF > "${TEST_SANDBOX_DIR}/gpg-key-spec"
Key-Type: RSA
Key-Length: 2048
Subkey-Type: RSA
Subkey-Length: 2048
Name-Real: RSD Integration Test
Name-Email: rsd@${host_id}
Expire-Date: 0
%no-protection
%commit
EOF
    gpg --batch --generate-key "${TEST_SANDBOX_DIR}/gpg-key-spec"
    
    # Find fingerprint of the generated key
    local fpr
    fpr=$(gpg --list-keys --with-colons | grep '^fpr' | head -n 1 | cut -d: -f10)
    
    # Import the trust level as ultimate (6 in ownertrust database format) non-interactively
    echo "${fpr}:6:" | gpg --import-ownertrust
}

teardown() {
    rm -rf "$TEST_SANDBOX_DIR"
}

@test "E2E Integration: encrypting and decrypting a file with real GPG keyring works" {
    # 1. Create dummy file
    local test_file="${TEST_SANDBOX_DIR}/secret.txt"
    echo "SuperSecretData123" > "$test_file"
    
    # 2. Encrypt using rsd CLI (action must match 'encrypt-file' in command/gpg)
    run "$RSD_BIN" gpg encrypt-file "$test_file"
    
    [ "$status" -eq 0 ]
    [ ! -f "$test_file" ]
    [ -f "${test_file}.gpg" ]
    
    # 3. Decrypt using rsd CLI (action must match 'decrypt-file' in command/gpg)
    run "$RSD_BIN" gpg decrypt-file "${test_file}.gpg"
    
    [ "$status" -eq 0 ]
    [ -f "$test_file" ]
    [ ! -f "${test_file}.gpg" ]
    
    # 4. Verify contents match
    local restored_content
    restored_content=$(cat "$test_file")
    [ "$restored_content" = "SuperSecretData123" ]
}
