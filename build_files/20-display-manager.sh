#!/usr/bin/bash
# Make greetd the display manager.
set -euxo pipefail

CTX="${CTX:-/ctx}"

cp -av "${CTX}/system_files/etc/greetd/config.toml" /etc/greetd/config.toml
cp -av "${CTX}/system_files/usr/lib/systemd/system-preset/05-sway-dm.preset" \
       /usr/lib/systemd/system-preset/05-sway-dm.preset

# Everything this image needs under /var is created by tmpfiles.d, never by
# shipping it in the image -- see the file itself for why.
cp -av "${CTX}/system_files/usr/lib/tmpfiles.d/bazzite-sway.conf" \
       /usr/lib/tmpfiles.d/bazzite-sway.conf
systemd-tmpfiles --cat-config >/dev/null

# Unlock the gnome-keyring at login instead of prompting for it separately.
# sway-portals.conf names gnome-keyring as the Secret portal backend.
# PAM orders modules within each type, so appending puts these last in their
# own type -- which is exactly where the keyring modules belong.
if ! grep -q pam_gnome_keyring /etc/pam.d/greetd; then
    cat >> /etc/pam.d/greetd <<'PAMEOF'
-auth      optional   pam_gnome_keyring.so
-session   optional   pam_gnome_keyring.so auto_start
PAMEOF
fi

# The base image's 85-display-manager.preset enables gdm, sddm AND plasmalogin
# together, with a comment admitting "the one which is installed first wins".
# Do not rely on that: enable explicitly. Every DM unit carries
# [Install] Alias=display-manager.service, so this writes the symlink that
# ostree relocates to /usr/etc and 3-way merges onto the live /etc.
# The base image ships /etc/systemd/system/display-manager.service already
# pointing at plasmalogin; systemctl will not clobber an existing alias symlink,
# so drop it before enabling greetd.
systemctl disable plasmalogin.service || true
rm -f /etc/systemd/system/display-manager.service
systemctl enable greetd.service

# Verify the alias actually landed where we expect.
readlink -f /etc/systemd/system/display-manager.service | grep -q greetd.service
