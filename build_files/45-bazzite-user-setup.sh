#!/usr/bin/bash
# Fix Bazzite's own per-user setup script, which does not parse.
#
# /usr/libexec/bazzite-user-setup comes from the base image and runs at every
# login via a user unit. Upstream wrote "nothing to do on KDE" as nothing at
# all, and bash requires at least one command in a `then` branch:
#
#     if [[ $BASE_IMAGE_NAME =~ "kinoite" ]]; then
#     else
#       gnome-extensions enable tdp-control@...
#     fi
#
# so the script dies with a syntax error at line 201 of 243. Not fallout from
# anything this image does -- bash parses the whole compound command before
# executing any of it, so stock Bazzite Kinoite fails identically.
#
# WHY PATCH RATHER THAN MASK THE UNIT. What the script never reaches is its own
# tail, where it writes the three state files that its early-exit test reads. So
# with them missing it re-runs and re-fails at every login, forever. Masking
# would silence that at the cost of the ~200 lines that do run.
#
# 40-branding.sh keeps base-image-name as "kinoite", so the KDE side of the `if`
# is the side taken and the gnome-extensions call is never reached here anyway.
#
# The file is owned by no RPM, so there is nothing to rpm-verify and no package
# update that would undo this -- but a fixed base image will ship a fixed
# script, hence the parse checks on both sides.
set -euxo pipefail

# Overridable so the patch can be exercised against a copy without a full build.
TARGET="${TARGET:-/usr/libexec/bazzite-user-setup}"

if [[ ! -f "${TARGET}" ]]; then
    echo "NOTE: ${TARGET} is absent -- upstream may have dropped it; nothing to patch"
    exit 0
fi

if bash -n "${TARGET}" 2>/dev/null; then
    echo "NOTE: ${TARGET} already parses -- upstream fixed it; patch skipped"
    exit 0
fi

# Advance one line past the branch that opens it and replace it ONLY if blank.
# Deliberately narrow: the file has a second `=~ "kinoite"` branch whose next
# line is an echo, and an empty branch anywhere else would be a different bug
# that should be read rather than papered over.
sed -i '/=~ "kinoite" \]\]; then$/{n;/^[[:space:]]*$/s/^.*$/      :/;}' "${TARGET}"

# The tripwire: if a later base image breaks somewhere else, stop here rather
# than shipping another login unit that fails silently every boot.
if ! bash -n "${TARGET}"; then
    echo "ERROR: ${TARGET} still does not parse after patching." >&2
    echo "       The upstream script changed shape. Read it before touching this." >&2
    exit 1
fi

echo "OK: patched ${TARGET} -- bash -n passes"
