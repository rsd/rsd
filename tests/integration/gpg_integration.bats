#!/usr/bin/env bats

setup() {
    RSD_BIN="${BATS_TEST_DIRNAME}/../../rsd"
    
    # Create isolated sandbox directory
    TEST_SANDBOX_DIR=$(mktemp -d -t rsd-sandbox.XXXXXX)
    export HOME="$TEST_SANDBOX_DIR"
    export GNUPGHOME="${TEST_SANDBOX_DIR}/.gnupg"
    mkdir -p -m 700 "$GNUPGHOME"
    
    # Create a real GPG key non-interactively in our sandbox keyring
    cat <<EOF > "${TEST_SANDBOX_DIR}/gpg-key-spec"
Key-Type: DEFAULT
Subkey-Type: DEFAULT
Name-Real: RSD Integration Test
Name-Email: rsd@$(hostname)
Expire-Date: 0
%no-protection
%commit
EOF
    gpg --batch --generate-key "${TEST_SANDBOX_DIR}/gpg-key-spec"
}

teardown() {
    rm -rf "$TEST_SANDBOX_DIR"
}

@test "E2E Integration: encrypting and decrypting a file with real GPG keyring works" {
    # 1. Create dummy file
    local test_file="${TEST_SANDBOX_DIR}/secret.txt"
    echo "SuperSecretData123" > "$test_file"
    
    # 2. Encrypt
    run "$RSD_BIN" gpg encrypt "$test_file"
    
    [ "$status" -eq 0 ]
    [ ! -f "$test_file" ]
    [ -f "${test_file}.gpg" ]
    
    # 3. Decrypt
    run "$RSD_BIN" gpg decrypt "${test_file}.gpg"
    
    [ "$status" -eq 0 ]
    [ -f "$test_file" ]
    [ ! -f "${test_file}.gpg" ]
    
    # 4. Verify contents match
    local restored_content
    restored_content=$(cat "$test_file")
    [ "$restored_content" = "SuperSecretData123" ]
}
