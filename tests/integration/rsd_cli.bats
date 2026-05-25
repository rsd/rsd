#!/usr/bin/env bats

setup() {
    RSD_BIN="${BATS_TEST_DIRNAME}/../../rsd"
}

@test "rsd --version prints version and exits successfully" {
    run "$RSD_BIN" --version
    
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "rsd with unrecognized command triggers warning and exit status 2" {
    run "$RSD_BIN" --no-pass-thru non_existent_command_xyz
    
    [ "$status" -eq 2 ]
}

@test "rsd test command executes correctly" {
    # rsd::c::test::test acts as the top-level command function,
    # so we call "rsd test arg1 arg2" directly.
    run "$RSD_BIN" test arg1 arg2
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"Teste: arg1 arg2"* ]]
}

@test "rsd @gateway -- gpg check outputs double-dash skip logs" {
    run "$RSD_BIN" --debug 20 @gateway -- gpg check
    
    # Bypasses custom command checks and triggers direct pass-through
    [[ "$output" == *"Double-dash skip detected. Direct remote pass-through for 'gpg'"* ]]
}

@test "rsd @gateway gpgg check outputs raw pass-through fallback logs" {
    run "$RSD_BIN" --debug 20 @gateway gpgg check
    
    # Fallback triggers since gpgg doesn't exist in command/
    [[ "$output" == *"No custom RSD script found for 'gpgg'. Triggering raw remote pass-through."* ]]
}

@test "rsd install command with --dry-run simulates package manager execution" {
    run "$RSD_BIN" install tmux --dry-run
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"sudo pacman "* || "$output" == *"sudo apt-get "* ]]
}

@test "rsd install command with shorthand -n simulates package manager execution" {
    run "$RSD_BIN" install tmux -n
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"sudo pacman "* || "$output" == *"sudo apt-get "* ]]
}

