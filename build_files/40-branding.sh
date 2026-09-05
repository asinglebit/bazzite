#!/usr/bin/bash
# Make the system report itself honestly, and stop the auto-updater.
set -euxo pipefail

IMAGE_NAME="bazzite-sway"
IMAGE_VENDOR="rattleworks"
IMAGE_REF="ostree-unverified-image:containers-storage:localhost/${IMAGE_NAME}"

INFO=/usr/share/ublue-os/image-info.json

# NOTE: base-image-name stays "kinoite" on purpose. It is the runtime DE oracle
# read by bazzite-user-setup, 80-bazzite.just (flatpak list selection) and
# 82-bazzite-sunshine.just; any other value drops those into the GNOME/dconf
# branch, which is worse than the KDE one for a Sway system.
jq --arg n "${IMAGE_NAME}" --arg v "${IMAGE_VENDOR}" --arg r "${IMAGE_REF}" \
   '."image-name" = $n | ."image-vendor" = $v | ."image-ref" = $r' \
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

# uupd is uBlue's updater (ublue-update no longer exists). Left enabled it fires
# at 04:00 against a containers-storage ref it cannot upgrade, and bootc warns
# that an active update agent can revert a queued rollback.
systemctl disable uupd.timer || true
