# BUG-0002: SSH PTY Carriage Returns Corrupt Parsed Values

**Fixed in**: v1.22.0
**Files**: `lib/recipe/nginx/install.recipe`, `lib/recipe/letsencrypt/install.recipe`
**Symptoms**: `Worker user: www-data;` — trailing semicolon not stripped.
Vhost basename detection returning empty or corrupted paths.

## Root Cause

When SSH allocates a PTY (`-t` flag), all output uses `\r\n` line endings
instead of Unix `\n`. This breaks any text processing that relies on `$`
anchors in `sed` or `grep`:

```
# What we expected:
user www-data;\n

# What SSH -t actually sends:
user www-data;\r\n
```

The sed pattern `s/[[:space:]]*;$//` matches `;` at end-of-line. But `$`
matches before `\n`, and `\r` sits between `;` and `\n`:

```
www-data;\r   ← the \r is BEFORE the $ anchor
            $  ← sed's $ is HERE
```

So `;\r` doesn't match `;$`, and the semicolon (and `\r`) survive.

## Fix

Always strip `\r` when processing SSH command output for value extraction:

```bash
# After sed/grep pipeline:
sed '...; s/\r//'

# Or for shell variables captured from SSH:
detected="${detected//$'\r'/}"
```

## General Rule

**Any value captured from `$(rsd::l::target::exec ...)` or
`$(rsd::l::target::exec_sudo ...)` that will be used in string comparisons,
basename extraction, or file path construction MUST strip `\r` characters.**

The `bash::trim` function strips whitespace but NOT `\r`.

## Test

Manual verification on remote targets with PTY. The `\r` issue only manifests
over SSH with `-t`; local execution never produces `\r`.

## Regression Risk

- Any new code that captures SSH output in `$(...)` and uses it for path
  construction, string comparison, or sed/awk processing without stripping `\r`.
- Removing the `s/\r//` from existing sed pipelines during "cleanup" refactors.
