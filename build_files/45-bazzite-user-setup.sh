#!/usr/bin/bash
# Fixes Bazzite's own login script, which has an empty `then` branch and so does not parse.
# Stock Bazzite fails the same way; it is not caused by anything here.
# Patched rather than masked, because the script never reaches the part that would stop it
# re-running, so it would fail at every login forever.
set -euxo pipefail

# Overridable so the patch can be tested on a copy.
TARGET="${TARGET:-/usr/libexec/bazzite-user-setup}"

if [[ ! -f "${TARGET}" ]]; then
    echo "NOTE: ${TARGET} is absent -- upstream may have dropped it; nothing to patch"
    exit 0
fi

if bash -n "${TARGET}" 2>/dev/null; then
    echo "NOTE: ${TARGET} already parses -- upstream fixed it; patch skipped"
    exit 0
fi

# Only replaces the line after that branch, and only if it is blank, so it cannot hit anything else.
sed -i '/=~ "kinoite" \]\]; then$/{n;/^[[:space:]]*$/s/^.*$/      :/;}' "${TARGET}"

# Fail the build rather than ship another login script that breaks quietly every boot.
if ! bash -n "${TARGET}"; then
    echo "ERROR: ${TARGET} still does not parse after patching." >&2
    echo "       The upstream script changed shape. Read it before touching this." >&2
    exit 1
fi

echo "OK: patched ${TARGET} -- bash -n passes"
