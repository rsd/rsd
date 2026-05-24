#!/usr/bin/env bats

setup() {
    export RSD_ON=1
    export RSD_DEBUG=0
    
    # Pre-define user ID to prevent net.lib resolution issues
    declare -g RSD_GPG_USER_ID="rsd@test-env"
    
    # Mock dynamic gpg command
    gpg() {
        if [[ "$*" == *"--list-keys"* ]]; then
            echo "pub:u:2048:1:D8A3C4E5F67890AB:2026-05-24:::"
            echo "fpr:::::::::2B9D4C7E8A0F1E2D3C4B5A6F7E8D9C0B1A2C3D4E:"
            return 0
        fi
        return 1
    }
    export -f gpg
    
    # Source core framework and target library
    source "${BATS_TEST_DIRNAME}/../../lib/rsd.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/gpg.lib"
}

@test "rsd::l::gpg::get_keys extracts key fingerprint correctly" {
    local -a test_keys
    
    rsd::l::gpg::get_keys "" test_keys
    
    [ "${#test_keys[@]}" -eq 1 ]
    [ "${test_keys[0]}" = "2B9D4C7E8A0F1E2D3C4B5A6F7E8D9C0B1A2C3D4E" ]
}

@test "rsd::l::gpg::encrypt_file fails when target file does not exist" {
    run rsd::l::gpg::encrypt_file "/tmp/non_existent_file_xyz.txt"
    
    [ "$status" -eq 2 ]
}
