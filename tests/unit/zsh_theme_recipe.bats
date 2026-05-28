#!/usr/bin/env bats

# Smoke tests for the zsh theme recipe (lib/recipe/zsh/theme.recipe)
# Tests recipe tasks in local execution mode with filesystem fixtures.
#
# DESIGN NOTE: Recipe tasks use the \$HOME convention (escaped dollar sign)
# to produce paths that survive local bash expansion and get re-expanded
# by the remote shell. For local-mode testing, we override target::exec
# to use eval, which simulates the remote shell expansion behavior.
# This is the correct test harness because it validates the same code paths
# that run in production (remote), not a synthetic local-only mode.
#
# @see lib/recipe/zsh/theme.recipe

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
    source "${BATS_TEST_DIRNAME}/../../lib/recipe.lib"
    source "${BATS_TEST_DIRNAME}/../../lib/recipe/zsh/theme.recipe"

    # Local execution mode
    unset RSD_REMOTE_TARGET

    # Create a sandboxed HOME to avoid touching real user files
    TEST_HOME=$(mktemp -d -t rsd-theme-test.XXXXXX)
    export HOME="$TEST_HOME"

    # Override target::exec to simulate remote shell expansion locally.
    # In production, SSH concatenates the payload into a single string
    # (${payload[*]}) and the remote shell parses it. bash -c "$*"
    # replicates this exactly: argument boundaries are erased, single-quote
    # protection is preserved, and $HOME is expanded by the child shell.
    rsd::l::target::exec() {
        bash -c "$*"
    }

    # Override file_push local branch: expand $HOME in destination path
    rsd::l::target::file_push() {
        local src="$1"
        local dest="$2"

        if [[ ! -f "$src" ]]; then
            rsd::warn "Error: Source file '$src' does not exist."
            return 1
        fi

        local expanded_dest
        expanded_dest=$(bash -c "echo $dest")
        cp "$src" "$expanded_dest"
    }
}

teardown() {
    # Clean up sandboxed HOME
    if [[ -n "$TEST_HOME" && -d "$TEST_HOME" ]]; then
        rm -rf "$TEST_HOME"
    fi
}

# ==============================================================================
# deploy_p10k_config — ships data/recipes/zsh/p10k.zsh to ~/.p10k.zsh
# ==============================================================================

@test "deploy_p10k_config::pre_check returns 1 when ~/.p10k.zsh is absent" {
    run rsd::r::zsh_theme::deploy_p10k_config::pre_check
    [ "$status" -ne 0 ]
}

@test "deploy_p10k_config copies the shipped config to ~/.p10k.zsh" {
    run rsd::r::zsh_theme::deploy_p10k_config
    [ "$status" -eq 0 ]
    [ -f "$HOME/.p10k.zsh" ]

    # Verify content matches the shipped file
    local shipped
    shipped="$(rsd::get_libdir_file "data/recipes/zsh/p10k.zsh")"
    local src_hash dest_hash
    src_hash=$(sha256sum "$shipped" | awk '{print $1}')
    dest_hash=$(sha256sum "$HOME/.p10k.zsh" | awk '{print $1}')
    [ "$src_hash" = "$dest_hash" ]
}

@test "deploy_p10k_config::pre_check returns 0 after deployment" {
    rsd::r::zsh_theme::deploy_p10k_config

    run rsd::r::zsh_theme::deploy_p10k_config::pre_check
    [ "$status" -eq 0 ]
}

# ==============================================================================
# patch_zshrc_for_p10k — idempotent scan-based .zshrc patching
# ==============================================================================

@test "patch_zshrc_for_p10k::pre_check returns 1 on pristine .zshrc" {
    # Create a minimal .zshrc without any p10k content
    cat > "$HOME/.zshrc" <<'EOF'
# If you come from bash you might have to change your $PATH.
export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH
ZSH_THEME="powerlevel10k/powerlevel10k"
EOF

    run rsd::r::zsh_theme::patch_zshrc_for_p10k::pre_check
    [ "$status" -ne 0 ]
}

@test "patch_zshrc_for_p10k prepends instant-prompt block" {
    cat > "$HOME/.zshrc" <<'EOF'
# If you come from bash you might have to change your $PATH.
export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH
ZSH_THEME="powerlevel10k/powerlevel10k"
EOF

    rsd::r::zsh_theme::patch_zshrc_for_p10k

    # Instant-prompt marker must exist
    run grep -c 'p10k-instant-prompt' "$HOME/.zshrc"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]

    # Instant-prompt block should appear BEFORE the original content
    local instant_line orig_line
    instant_line=$(grep -n 'p10k-instant-prompt' "$HOME/.zshrc" | head -1 | cut -d: -f1)
    orig_line=$(grep -n 'If you come from bash' "$HOME/.zshrc" | head -1 | cut -d: -f1)
    [ "$instant_line" -lt "$orig_line" ]
}

@test "patch_zshrc_for_p10k appends source line" {
    cat > "$HOME/.zshrc" <<'EOF'
# If you come from bash you might have to change your $PATH.
export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH
ZSH_THEME="powerlevel10k/powerlevel10k"
EOF

    rsd::r::zsh_theme::patch_zshrc_for_p10k

    # Source line should exist
    run grep -c 'source ~/.p10k.zsh' "$HOME/.zshrc"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

@test "patch_zshrc_for_p10k creates backup before patching" {
    cat > "$HOME/.zshrc" <<'EOF'
ZSH_THEME="powerlevel10k/powerlevel10k"
EOF

    rsd::r::zsh_theme::patch_zshrc_for_p10k

    [ -f "$HOME/.zshrc.p10k.bak" ]
}

@test "patch_zshrc_for_p10k::pre_check returns 0 after patching" {
    cat > "$HOME/.zshrc" <<'EOF'
ZSH_THEME="powerlevel10k/powerlevel10k"
EOF

    rsd::r::zsh_theme::patch_zshrc_for_p10k

    run rsd::r::zsh_theme::patch_zshrc_for_p10k::pre_check
    [ "$status" -eq 0 ]
}

@test "patch_zshrc_for_p10k is idempotent — no double-injection on second run" {
    cat > "$HOME/.zshrc" <<'EOF'
ZSH_THEME="powerlevel10k/powerlevel10k"
EOF

    # Run twice
    rsd::r::zsh_theme::patch_zshrc_for_p10k
    rsd::r::zsh_theme::patch_zshrc_for_p10k

    # The instant-prompt block contains 2 lines with the marker
    # (the 'if [[ -r ...' line and the 'source ...' line).
    # Verify only one block exists (2 marker lines, not 4).
    local count
    count=$(grep -c 'p10k-instant-prompt' "$HOME/.zshrc")
    [ "$count" -eq 2 ]

    # Source line should appear exactly once
    count=$(grep -c 'source ~/.p10k.zsh' "$HOME/.zshrc")
    [ "$count" -eq 1 ]
}

@test "patch_zshrc_for_p10k skips instant-prompt when already present" {
    # .zshrc already has instant-prompt but NOT the source line
    cat > "$HOME/.zshrc" <<'EOF'
# Enable Powerlevel10k instant prompt.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

ZSH_THEME="powerlevel10k/powerlevel10k"
EOF

    rsd::r::zsh_theme::patch_zshrc_for_p10k

    # The instant-prompt block contains 2 lines with the marker.
    # Verify only one block exists (2 marker lines, not 4).
    local count
    count=$(grep -c 'p10k-instant-prompt' "$HOME/.zshrc")
    [ "$count" -eq 2 ]

    # Source line was added
    run grep 'source ~/.p10k.zsh' "$HOME/.zshrc"
    [ "$status" -eq 0 ]
}

@test "patch_zshrc_for_p10k skips source line when already present" {
    # .zshrc already has source line but NOT instant-prompt
    cat > "$HOME/.zshrc" <<'EOF'
ZSH_THEME="powerlevel10k/powerlevel10k"

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
EOF

    rsd::r::zsh_theme::patch_zshrc_for_p10k

    # Source line still exactly once (not doubled)
    local count
    count=$(grep -c 'source ~/.p10k.zsh' "$HOME/.zshrc")
    [ "$count" -eq 1 ]

    # Instant-prompt was added
    run grep 'p10k-instant-prompt' "$HOME/.zshrc"
    [ "$status" -eq 0 ]
}

@test "patch_zshrc_for_p10k::rollback restores original .zshrc" {
    cat > "$HOME/.zshrc" <<'EOF'
ORIGINAL_CONTENT=true
EOF

    rsd::r::zsh_theme::patch_zshrc_for_p10k
    rsd::r::zsh_theme::patch_zshrc_for_p10k::rollback

    run cat "$HOME/.zshrc"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ORIGINAL_CONTENT=true"* ]]
    # Should NOT contain p10k content after rollback
    [[ "$output" != *"p10k-instant-prompt"* ]]
}

# ==============================================================================
# adjust_p10k_context — comments out CONTEXT_{DEFAULT,SUDO} expansion lines
# ==============================================================================

@test "adjust_p10k_context::pre_check returns 1 when lines are NOT yet commented" {
    # Deploy the pristine config (has uncommented CONTEXT lines)
    rsd::r::zsh_theme::deploy_p10k_config

    run rsd::r::zsh_theme::adjust_p10k_context::pre_check
    [ "$status" -ne 0 ]
}

@test "adjust_p10k_context comments out the CONTEXT expansion line" {
    rsd::r::zsh_theme::deploy_p10k_config
    rsd::r::zsh_theme::adjust_p10k_context

    # The line should now be commented
    run grep '^# typeset -g POWERLEVEL9K_CONTEXT_' "$HOME/.p10k.zsh"
    [ "$status" -eq 0 ]
}

@test "adjust_p10k_context::pre_check returns 0 after adjustment" {
    rsd::r::zsh_theme::deploy_p10k_config
    rsd::r::zsh_theme::adjust_p10k_context

    run rsd::r::zsh_theme::adjust_p10k_context::pre_check
    [ "$status" -eq 0 ]
}

@test "adjust_p10k_context is idempotent — safe to run twice" {
    rsd::r::zsh_theme::deploy_p10k_config
    rsd::r::zsh_theme::adjust_p10k_context
    rsd::r::zsh_theme::adjust_p10k_context

    # Should still have exactly one commented-out CONTEXT line (not double-commented)
    local count
    count=$(grep -c '^# typeset -g POWERLEVEL9K_CONTEXT_{DEFAULT,SUDO}' "$HOME/.p10k.zsh")
    [ "$count" -eq 1 ]
}

# ==============================================================================
# Full pipeline — end-to-end execution order
# ==============================================================================

@test "full pipeline: deploy → patch → adjust runs in correct order" {
    # Create a minimal .zshrc
    cat > "$HOME/.zshrc" <<'EOF'
ZSH_THEME="powerlevel10k/powerlevel10k"
EOF

    # Execute the three new tasks in order
    rsd::r::zsh_theme::deploy_p10k_config
    rsd::r::zsh_theme::patch_zshrc_for_p10k
    rsd::r::zsh_theme::adjust_p10k_context

    # Verify all three outcomes
    [ -f "$HOME/.p10k.zsh" ]
    run grep 'p10k-instant-prompt' "$HOME/.zshrc"
    [ "$status" -eq 0 ]
    run grep 'source ~/.p10k.zsh' "$HOME/.zshrc"
    [ "$status" -eq 0 ]
    run grep '^# typeset -g POWERLEVEL9K_CONTEXT_' "$HOME/.p10k.zsh"
    [ "$status" -eq 0 ]

    # All pre_checks should now report satisfied
    run rsd::r::zsh_theme::deploy_p10k_config::pre_check
    [ "$status" -eq 0 ]
    run rsd::r::zsh_theme::patch_zshrc_for_p10k::pre_check
    [ "$status" -eq 0 ]
    run rsd::r::zsh_theme::adjust_p10k_context::pre_check
    [ "$status" -eq 0 ]
}
