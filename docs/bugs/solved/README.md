# Solved Bugs — Regression Knowledge Base

This directory documents bugs that were diagnosed, root-caused, and fixed.
Its purpose is to **prevent regressions** by providing a searchable history of
failure modes and their solutions.

## When to Add an Entry

Add a file here when:
- A bug took significant debugging effort to root-cause.
- The failure mode is non-obvious and could easily recur.
- The fix touches a layer boundary (SSH, PTY, quoting, process substitution).
- A previous fix was accidentally reverted or broken by a later change.

## File Format

Each bug is a Markdown file named `NNNN-short-description.md` (zero-padded
sequence number). Use the template:

```markdown
# BUG-NNNN: Short Title

**Fixed in**: v1.X.Y
**Files**: `lib/file.lib`, `lib/recipe/name.recipe`
**Symptoms**: What the user saw.
**Root Cause**: Why it happened (the non-obvious part).
**Fix**: What was changed.
**Test**: How to verify the fix holds (`bats tests/unit/...`).
**Regression Risk**: What kind of change could re-break this.
```

## Index

| Bug | Title | Version | Key Insight |
|:----|:------|:--------|:------------|
| [0001](0001-ssh-connection-closed-noise.md) | SSH "Connection closed" noise | v1.22.0 | SSH `-t` PTY writes to stderr asynchronously after pipe close |
| [0002](0002-ssh-pty-carriage-returns.md) | SSH PTY carriage returns corrupt parsed values | v1.22.0 | SSH `-t` returns `\r\n`; sed/grep `$` anchors miss the `\r` |
| [0003](0003-sudo-stdout-swallowed.md) | exec_sudo stdout swallowed in command substitution | v1.23.0 | sudo pipeline through SSH PTY merges stdout/stderr |
| [0004](0004-json-port-type-mismatch.md) | Centrifugo config check fails on string ports | v1.22.0 | JSON `"port": "8000"` vs required integer `"port": 8000` |
| [0005](0005-config-precheck-exists-not-valid.md) | pre_check passes on broken config files | v1.22.0 | File existence ≠ file validity |
| [0006](0006-sed-mangled-through-ssh.md) | sed expressions mangled through SSH | v1.23.0 | Complex sed `{ }` and `\` destroyed by 4-layer quoting |
