#!/usr/bin/bash
# Make the system report itself honestly, and stop the auto-updater.
set -euxo pipefail

IMAGE_NAME="bazzite-sway"
IMAGE_VENDOR="rattleworks"
IMAGE_TAG="${IMAGE_TAG:-sway}"

# image-ref is what the running system believes its own upstream is. A published
# image must not claim to come from a local containers-storage path, so it
# follows IMAGE_REGISTRY: set (CI) -> the signed GHCR ref that `bootc upgrade`
# can actually follow; empty (a local `just build`) -> the old local ref.
#
# ostree-image-signed: is the form that applies /etc/containers/policy.json on
# every pull. It is the same shape the stock Bazzite deployment already uses
# (ostree-image-signed:docker://ghcr.io/ublue-os/bazzite-nvidia-open:stable).
if [[ -n "${IMAGE_REGISTRY:-}" ]]; then
    IMAGE_REF="ostree-image-signed:docker://${IMAGE_REGISTRY}/${IMAGE_NAME}"
else
    IMAGE_REF="ostree-unverified-image:containers-storage:localhost/${IMAGE_NAME}"
fi

INFO=/usr/share/ublue-os/image-info.json

# NOTE: base-image-name stays "kinoite" on purpose. It is the runtime DE oracle
# read by bazzite-user-setup, 80-bazzite.just (flatpak list selection) and
# 82-bazzite-sunshine.just; any other value drops those into the GNOME/dconf
# branch, which is worse than the KDE one for a Sway system.
#
# image-branch also stays "stable": it names the *upstream* stream this tracks,
# which is still bazzite-nvidia-open:stable regardless of which of our tags this
# happens to be.
jq --arg n "${IMAGE_NAME}" --arg v "${IMAGE_VENDOR}" --arg r "${IMAGE_REF}" \
   --arg t "${IMAGE_TAG}" \
   '."image-name" = $n | ."image-vendor" = $v | ."image-ref" = $r
    | ."image-tag" = $t' \
   "${INFO}" > "${INFO}.new"
mv "${INFO}.new" "${INFO}"
jq -e '."base-image-name" == "kinoite"' "${INFO}" >/dev/null

# BOOTLOADER_NAME is what labels the GRUB entries. Making it visibly different
# is what lets you pick the old deployment under pressure.
sed -i \
    -e 's|^PRETTY_NAME=.*|PRETTY_NAME="Bazzite Sway"|' \
    -e "s|^IMAGE_ID=\"bazzite-nvidia-open|IMAGE_ID=\"${IMAGE_NAME}|" \
    -e 's|^BOOTLOADER_NAME="Bazzite |BOOTLOADER_NAME="Bazzite Sway |' \
    /usr/lib/os-release

grep -E '^(PRETTY_NAME|IMAGE_ID|BOOTLOADER_NAME)=' /usr/lib/os-release

# The ublue MOTD banner. /etc/bashrc sources profile.d for non-login shells as
# well as login ones, and USERMOTDSOURCED is never exported, so it reprints on
# every interactive shell -- once per tmux window, not once per terminal. The
# supported off switch is a ~/.config/no-show-user-motd marker, but that is
# keyed on $HOME, so root shells print it regardless of what the user set.
#
# It also misreports this artifact. motd/env.sh builds the displayed ref from
# image-ref and image-*branch* -- not image-tag -- and image-branch names the
# upstream stream this tracks, so the banner advertises
# ghcr.io/asinglebit/bazzite-sway:stable, a tag this repo deliberately never
# publishes. Its issue and Discord links point at bazzite.gg, not here.
#
# Asserted before removal rather than a bare `rm -f`: if upstream renames or
# moves this file, an unconditional remove would silently no-op and the banner
# would quietly come back on the next rebuild.
test -e /etc/profile.d/user-motd.sh
rm -f /etc/profile.d/user-motd.sh

# uupd is uBlue's updater (ublue-update no longer exists). Left enabled it fires
# at 04:00 against a ref it cannot upgrade, and bootc warns that an active
# update agent can revert a queued rollback. Updates are `just update`, by hand.
systemctl disable uupd.timer || true
