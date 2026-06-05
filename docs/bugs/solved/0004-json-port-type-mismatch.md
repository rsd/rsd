# BUG-0004: Centrifugo Config Check Fails on String Ports

**Fixed in**: v1.22.0
**Files**: `lib/recipe/centrifugo/install.recipe`
**Symptoms**: `Config check: FAILED` during `validate_install`, even though
the config was freshly generated.

## Root Cause

The JSON config template used `printf '%s'` for port values, wrapping them
in quotes:

```json
{
  "http_server": {
    "port": "8000",
    "internal_port": "8001"
  }
}
```

Centrifugo v6+ performs strict JSON type validation. Ports must be integers:

```json
{
  "http_server": {
    "port": 8000,
    "internal_port": 8001
  }
}
```

The `centrifugo checkconfig` command rejects string-typed port values.

## Fix

Remove quotes from port fields in the `printf -v config_json` template:

```bash
# Before:
"port": "%s",
"internal_port": "%s"

# After:
"port": %s,
"internal_port": %s
```

The `%s` format specifier still works — it outputs the bare number without
quotes, producing valid JSON integers.

## General Rule

**When generating JSON in Bash with `printf`, distinguish between string and
numeric fields.** Use `"%s"` for strings and `%s` (no quotes) for numbers.
Validate generated JSON with the consuming application's own checker when
available (`centrifugo checkconfig`, `nginx -t`, `jq .`, etc.).

## Test

The pre_check now runs `centrifugo checkconfig --config` to validate the
config is parseable, not just that the file exists (see BUG-0005).

## Regression Risk

- Adding new numeric fields to the JSON template with quoted `"%s"`.
- Changing port defaults to include non-numeric characters (would produce
  invalid JSON since there are no quotes).
