# BUG-0005: pre_check Passes on Broken Config Files

**Fixed in**: v1.22.0
**Files**: `lib/recipe/centrifugo/install.recipe`
**Symptoms**: `generate_config` task skipped ("already satisfied"), but the
existing config file was invalid/broken from a previous failed run. The
`validate_install` step then failed with `Config check: FAILED`.

## Root Cause

The `generate_config::pre_check` only verified **file existence**:

```bash
function rsd::r::centrifugo_install::generate_config::pre_check() {
    rsd::l::target::file_exists "$RSD_CENTRIFUGO_CONFIG"
}
```

A broken `config.json` from a previous session (with wrong JSON types,
incomplete fields, or syntax errors) still satisfies `file_exists`. The
pre_check returns 0, the engine skips `generate_config`, and the broken
config persists until `validate_install` catches it — too late to self-heal.

## Fix

Extend the pre_check to validate the config is **parseable**, not just present:

```bash
function rsd::r::centrifugo_install::generate_config::pre_check() {
    rsd::l::target::file_exists "$RSD_CENTRIFUGO_CONFIG" || return 1
    rsd::l::target::exec_sudo "" "$RSD_CENTRIFUGO_BIN" checkconfig \
        --config "$RSD_CENTRIFUGO_CONFIG" &>/dev/null
}
```

Note: `exec_sudo` is required because the config file is `0640 root:centrifugo`
— the SSH user cannot read it without elevation.

## General Rule

**pre_check functions should verify the DESIRED STATE, not just the artifact's
existence.** For config files, this means:
- File exists AND
- File is valid/parseable by the consuming application

Common validators:
- `centrifugo checkconfig --config <path>`
- `nginx -t`
- `jq . <path> >/dev/null`
- `python3 -m json.tool <path> >/dev/null`

## Test

The fix is implicitly tested by re-running the recipe after a failed config
generation — the pre_check now correctly detects the broken config and
re-generates it.

## Regression Risk

- Removing the `checkconfig` call from pre_check "for speed".
- Changing config permissions so `exec_sudo` is no longer needed, then
  switching to `exec` which might fail silently on permission errors.
