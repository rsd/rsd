# BUG-0006: sed Expressions Mangled Through SSH Sudo Pipeline

**Fixed in**: v1.23.0
**Files**: `lib/recipe/letsencrypt/install.recipe`
**Symptoms**: `sed: -e expression #1, char 1: unexpected '}'` during ACME
include injection into nginx vhost.

## Root Cause

The sed command used address ranges with `{ }` and an append command with `\`:

```bash
rsd::l::target::exec_sudo "" sed -i \
    '/listen 80;/,/}/ { /server_name/a\    include snippets/acme-challenge.conf;' \
    -e '}' "$RSD_LE_VHOST_PATH"
```

This goes through **four quoting layers**: local bash → `exec_sudo` → SSH →
remote `sh -c` → `sudo` → `sed`. The `{`, `}`, and `\` characters are
interpreted by one or more intermediate shells before reaching sed.

Specifically:
- The `}` in the sed range `/}/` conflicts with the `sh -c '...'` wrapper
- The `-e '}'` is a separate argument that gets reordered or lost
- The `\` in `a\    include` is consumed as a shell escape character

This is the same class of failure as BUG-0002 and BUG-0003: multi-layer
SSH command construction destroys special characters.

## Fix

**Never use complex sed expressions through the SSH/sudo pipeline.**

Replace with a pure-bash read-modify-write approach:

```bash
# Read vhost content (strip \r per BUG-0002)
vhost_content=$(rsd::l::target::exec_sudo "" cat "$path" 2>/dev/null)
vhost_content="${vhost_content//$'\r'/}"

# Modify in local bash (no quoting issues)
while IFS= read -r line; do
    modified+="${line}"$'\n'
    if [[ "$line" == *"server_name"* ]]; then
        modified+="    include snippets/acme-challenge.conf;"$'\n'
    fi
done <<< "$vhost_content"

# Write back via temp file
printf '%s' "$modified" | rsd::l::target::exec tee "$tmpfile" >/dev/null
rsd::l::target::exec_sudo "" mv "$tmpfile" "$path"
```

## General Rule

**For file modifications on remote targets, prefer the read-modify-write
pattern over remote `sed -i`.** The pattern:

1. `cat` the file via `exec_sudo` into a local variable
2. Strip `\r` (BUG-0002)
3. Transform the content using local bash (no quoting constraints)
4. Write back via `mktemp` + `tee` + `mv`

Reserve remote `sed -i` only for **trivially simple** substitutions with no
special characters: `sed -i 's/old/new/' file`.

## Test

Re-run the recipe — the ACME snippet should be injected into the vhost and
certbot should successfully validate the HTTP-01 challenge.

## Regression Risk

- New code that uses complex sed/awk through `exec_sudo` instead of
  read-modify-write.
- Forgetting to strip `\r` after reading the file via SSH (BUG-0002).
