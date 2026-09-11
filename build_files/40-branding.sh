#!/usr/bin/bash
# Makes the system report itself honestly, and turns off the auto-updater.
set -euxo pipefail

IMAGE_NAME="bazzite-sway"
IMAGE_VENDOR="rattleworks"
IMAGE_TAG="${IMAGE_TAG:-sway}"

# This is where the system thinks it came from, so a published image must not name a local path.
# The signed form is what makes every pull check policy.json.
if [[ -n "${IMAGE_REGISTRY:-}" ]]; then
    IMAGE_REF="ostree-image-signed:docker://${IMAGE_REGISTRY}/${IMAGE_NAME}"
else
    IMAGE_REF="ostree-unverified-image:containers-storage:localhost/${IMAGE_NAME}"
fi

INFO=/usr/share/ublue-os/image-info.json

# base-image-name must stay "kinoite", checked below: Bazzite's own scripts read it to
# guess the desktop, and any other value sends them down a worse branch.
jq --arg n "${IMAGE_NAME}" --arg v "${IMAGE_VENDOR}" --arg r "${IMAGE_REF}" \
   --arg t "${IMAGE_TAG}" \
   '."image-name" = $n | ."image-vendor" = $v | ."image-ref" = $r
    | ."image-tag" = $t' \
   "${INFO}" > "${INFO}.new"
mv "${INFO}.new" "${INFO}"
jq -e '."base-image-name" == "kinoite"' "${INFO}" >/dev/null

# BOOTLOADER_NAME labels the GRUB entries, which is how you pick the old one when things break.
sed -i \
    -e 's|^PRETTY_NAME=.*|PRETTY_NAME="Bazzite Sway"|' \
    -e "s|^IMAGE_ID=\"bazzite-nvidia-open|IMAGE_ID=\"${IMAGE_NAME}|" \
    -e 's|^BOOTLOADER_NAME="Bazzite |BOOTLOADER_NAME="Bazzite Sway |' \
    /usr/lib/os-release

grep -E '^(PRETTY_NAME|IMAGE_ID|BOOTLOADER_NAME)=' /usr/lib/os-release

# The ublue banner reprints in every shell and advertises a tag this repo never publishes.
# Checked before removing, so that upstream moving the file fails the build instead of going quiet.
test -e /etc/profile.d/user-motd.sh
rm -f /etc/profile.d/user-motd.sh

# uBlue's updater would fire nightly against a ref it cannot upgrade, so updates stay manual.
systemctl disable uupd.timer || true
