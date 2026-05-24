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
