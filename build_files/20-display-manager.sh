#!/usr/bin/bash
# Makes greetd the display manager, which has to happen before 30 removes the KDE one.
set -euxo pipefail

CTX="${CTX:-/ctx}"

cp -av "${CTX}/system_files/etc/greetd/config.toml" /etc/greetd/config.toml

# Any of these going missing is a blank login screen.
test -x /usr/libexec/noctalia-greeter-nvidia
test -x /usr/bin/noctalia-greeter-session
# tuigreet stays installed as the fallback greeter.
rpm -q tuigreet

# Worth checking the contents: five failed starts leaves tty1 dead with no console to fix it from.
grep -q '^command = "/usr/libexec/noctalia-greeter-nvidia"$' /etc/greetd/config.toml
grep -q '^user = "greetd"$' /etc/greetd/config.toml
grep -q '^vt = 1$'          /etc/greetd/config.toml

# This one file is the entire session list, and sway will not start on this GPU
# unless the Exec line goes through start-sway.
test -f /usr/share/wayland-sessions/sway.desktop
grep -q '^Exec=start-sway$' /usr/share/wayland-sessions/sway.desktop

cp -av "${CTX}/system_files/usr/lib/systemd/system-preset/05-sway-dm.preset" \
       /usr/lib/systemd/system-preset/05-sway-dm.preset

# Everything this image needs under /var is created by tmpfiles.d rather than shipped.
cp -av "${CTX}/system_files/usr/lib/tmpfiles.d/bazzite-sway.conf" \
       /usr/lib/tmpfiles.d/bazzite-sway.conf
systemd-tmpfiles --cat-config >/dev/null
# The rule leaves its source path implicit, so check it exists or the greeter comes up blank.
test -s /usr/share/factory/var/lib/noctalia-greeter/greeter.toml

# The remove-then-copy pair is required: a copy rule on its own skips an existing file
# without saying so, and the login screen would quietly stop tracking the image.
grep -qE '^r[[:space:]]+/var/lib/noctalia-greeter/greeter\.toml[[:space:]]*$' \
    /usr/lib/tmpfiles.d/bazzite-sway.conf
grep -qE '^C[[:space:]]+/var/lib/noctalia-greeter/greeter\.toml[[:space:]]' \
    /usr/lib/tmpfiles.d/bazzite-sway.conf
! grep -qE '^C\+[[:space:]]+/var/lib/noctalia-greeter/greeter\.toml' \
    /usr/lib/tmpfiles.d/bazzite-sway.conf

# Unlocks the keyring at login instead of prompting again; appending puts these last, where they belong.
if ! grep -q pam_gnome_keyring /etc/pam.d/greetd; then
    cat >> /etc/pam.d/greetd <<'PAMEOF'
-auth      optional   pam_gnome_keyring.so
-session   optional   pam_gnome_keyring.so auto_start
PAMEOF
fi

# The base image enables three display managers and lets them race, so do not rely on it.
# systemctl will not overwrite the existing alias, so remove it before enabling greetd.
systemctl disable plasmalogin.service || true
rm -f /etc/systemd/system/display-manager.service
systemctl enable greetd.service

readlink -f /etc/systemd/system/display-manager.service | grep -q greetd.service
