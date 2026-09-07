#!/usr/bin/bash
# Fix Bazzite's own per-user setup script, which does not parse.
#
# /usr/libexec/bazzite-user-setup comes from the base image and is run at every
# login by bazzite-user-setup.service (a *user* unit). On this image it fails
# every login:
#
#     Running setup for Kinoite
#     /usr/libexec/bazzite-user-setup: line 201: syntax error near unexpected token `else'
#     bazzite-user-setup.service: Failed with result 'exit-code'.
#
# The bug is upstream, and it is a plain shell syntax error:
#
#     if [[ $BASE_IMAGE_NAME =~ "kinoite" ]]; then
#                                                    <-- nothing here
#     else
#       gnome-extensions enable tdp-control@opengamingcollective.org
#     fi
#
# "Nothing to do on KDE" was written as nothing at all, and bash requires at
# least one command in a `then` branch. So the fix is the no-op that was meant
# to be there: `:`.
#
# Nothing about this is specific to what this image does to Bazzite. It is not
# fallout from removing Plasma in 30-kde-remove.sh -- the broken block enables a
# GNOME extension -- and the branch taken does not matter either, because bash
# parses the whole compound command before executing any of it. A stock Bazzite
# Kinoite image has the same failure.
#
# WHY FIX IT RATHER THAN MASK THE UNIT. The script dies at line 201 of 243, and
# what it never reaches is its own tail:
#
#     echo $USER_SETUP_VER > $USER_SETUP_VER_FILE
#     echo $FEDORA_VERSION > $USER_SETUP_FEDORA_VER_FILE
#     echo $BASE_IMAGE_NAME > $USER_SETUP_IMAGE_VER_FILE
#
# Those state files are what its own early-exit test reads, so with them missing
# the unit re-runs and re-fails at every single login, forever. Masking the unit
# would silence that at the cost of the ~200 lines that do currently run;
# patching it lets the script finish once and then no-op, which is what it was
# written to do.
#
# WHAT RUNS AFTER THE FIX: `:` and nothing else in that branch. 40-branding.sh
# keeps `base-image-name` as "kinoite" on purpose -- it is the runtime DE oracle
# and that file asserts it with `jq -e` -- so the KDE side of the `if` is the
# side taken, and the `gnome-extensions` call in the `else` is not reached on
# this image at all. The block is also gated on handheld hardware detection
# above it, which this desktop fails anyway.
#
# The file is owned by no RPM (it is baked into the image, not packaged), so
# there is nothing to rpm-verify and no package update that would undo this --
# but a fixed base image will ship a fixed script, so this only touches a file
# that actually fails `bash -n`, and asserts the result either way.
set -euxo pipefail

# Overridable so the patch can be exercised against a copy without a full image
# build; the default is the only path this is ever pointed at in CI.
TARGET="${TARGET:-/usr/libexec/bazzite-user-setup}"

if [[ ! -f "${TARGET}" ]]; then
    echo "NOTE: ${TARGET} is absent -- upstream may have dropped it; nothing to patch"
    exit 0
fi

if bash -n "${TARGET}" 2>/dev/null; then
    echo "NOTE: ${TARGET} already parses -- upstream fixed it; patch skipped"
    exit 0
fi

# On the line that opens the empty branch, advance one line (`n`) and replace it
# with the no-op ONLY if it is blank. Deliberately narrow: the file has a second
# `=~ "kinoite"` branch at line 49 whose next line is an `echo`, so it is left
# alone, and an empty branch anywhere else would be a different bug that should
# be read rather than papered over.
sed -i '/=~ "kinoite" \]\]; then$/{n;/^[[:space:]]*$/s/^.*$/      :/;}' "${TARGET}"

# The tripwire. If a later base image breaks somewhere else, this build stops
# here rather than shipping another login unit that fails silently every boot.
if ! bash -n "${TARGET}"; then
    echo "ERROR: ${TARGET} still does not parse after patching." >&2
    echo "       The upstream script changed shape. Read it before touching this." >&2
    exit 1
fi

echo "OK: patched ${TARGET} -- bash -n passes"
