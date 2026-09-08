#!/usr/bin/bash
# Make the system report itself honestly, and stop the auto-updater.
set -euxo pipefail

IMAGE_NAME="bazzite-sway"
IMAGE_VENDOR="rattleworks"
IMAGE_TAG="${IMAGE_TAG:-sway}"

# image-ref is what the running system believes its own upstream is, so a
# published image must not claim to come from a local containers-storage path.
# `ostree-image-signed:` is the form that applies /etc/containers/policy.json on
# every pull -- the same shape stock Bazzite already uses.
if [[ -n "${IMAGE_REGISTRY:-}" ]]; then
    IMAGE_REF="ostree-image-signed:docker://${IMAGE_REGISTRY}/${IMAGE_NAME}"
else
    IMAGE_REF="ostree-unverified-image:containers-storage:localhost/${IMAGE_NAME}"
fi

INFO=/usr/share/ublue-os/image-info.json

# base-image-name STAYS "kinoite", asserted below. It is the runtime DE oracle
# read by bazzite-user-setup, 80-bazzite.just and 82-bazzite-sunshine.just; any
# other value drops those into the GNOME/dconf branch, which is worse than the
# KDE one for a Sway system. 45-bazzite-user-setup.sh depends on this.
#
# image-branch stays "stable": it names the upstream stream this tracks, not our
# tag.
jq --arg n "${IMAGE_NAME}" --arg v "${IMAGE_VENDOR}" --arg r "${IMAGE_REF}" \
   --arg t "${IMAGE_TAG}" \
   '."image-name" = $n | ."image-vendor" = $v | ."image-ref" = $r
    | ."image-tag" = $t' \
   "${INFO}" > "${INFO}.new"
mv "${INFO}.new" "${INFO}"
jq -e '."base-image-name" == "kinoite"' "${INFO}" >/dev/null

# BOOTLOADER_NAME labels the GRUB entries, which is what lets you pick the old
# deployment under pressure.
sed -i \
    -e 's|^PRETTY_NAME=.*|PRETTY_NAME="Bazzite Sway"|' \
    -e "s|^IMAGE_ID=\"bazzite-nvidia-open|IMAGE_ID=\"${IMAGE_NAME}|" \
    -e 's|^BOOTLOADER_NAME="Bazzite |BOOTLOADER_NAME="Bazzite Sway |' \
    /usr/lib/os-release

grep -E '^(PRETTY_NAME|IMAGE_ID|BOOTLOADER_NAME)=' /usr/lib/os-release

# The ublue MOTD banner, which reprints on every interactive shell (once per
# tmux window) because USERMOTDSOURCED is never exported, and whose supported
# off switch is keyed on $HOME so root shells ignore it. It also advertises a
# tag this repo never publishes, because it builds the ref from image-*branch*
# rather than image-tag.
#
# Asserted before removal rather than a bare `rm -f`: if upstream moves this
# file, an unconditional remove would silently no-op and the banner would come
# back on the next rebuild.
test -e /etc/profile.d/user-motd.sh
rm -f /etc/profile.d/user-motd.sh

# uupd is uBlue's updater. Left enabled it fires at 04:00 against a ref it
# cannot upgrade, and bootc warns that an active update agent can revert a
# queued rollback. Updates are `just update`, by hand.
systemctl disable uupd.timer || true
