#!/usr/bin/bash
# Make greetd the display manager. The greeter package, its GPU wrapper and its
# config are 17-noctalia-greeter.sh; this only binds greetd and points at the
# result -- which must happen before 30-kde-remove.sh takes plasmalogin out.
set -euxo pipefail

CTX="${CTX:-/ctx}"

cp -av "${CTX}/system_files/etc/greetd/config.toml" /etc/greetd/config.toml

# Re-asserted here because this is the file that names the command line, and
# every one of these is a blank login screen if it goes missing.
test -x /usr/libexec/noctalia-greeter-nvidia
test -x /usr/bin/noctalia-greeter-session
# tuigreet is KEPT, unbound, as the fallback greeter -- see config.toml.
rpm -q tuigreet

# Asserting the command line's CONTENT matters because greetd is Restart=always
# with StartLimitBurst=5 and Conflicts=getty@tty1.service: five failures in
# thirty seconds leaves VT 1 dead with no getty on it.
grep -q '^command = "/usr/libexec/noctalia-greeter-nvidia"$' /etc/greetd/config.toml
grep -q '^user = "greetd"$' /etc/greetd/config.toml
grep -q '^vt = 1$'          /etc/greetd/config.toml

# noctalia-greeter scans /usr/share/wayland-sessions and nothing else -- no
# /etc/greetd/environments, no xsessions. So this entry IS the session list, and
# an `Exec=` that does not go through start-sway is a login that fails on the
# happy path: sway will not start on this GPU without the flags start-sway
# sources.
test -f /usr/share/wayland-sessions/sway.desktop
grep -q '^Exec=start-sway$' /usr/share/wayland-sessions/sway.desktop

cp -av "${CTX}/system_files/usr/lib/systemd/system-preset/05-sway-dm.preset" \
       /usr/lib/systemd/system-preset/05-sway-dm.preset

# Everything this image needs under /var is created by tmpfiles.d rather than
# shipped -- see the file itself.
cp -av "${CTX}/system_files/usr/lib/tmpfiles.d/bazzite-sway.conf" \
       /usr/lib/tmpfiles.d/bazzite-sway.conf
systemd-tmpfiles --cat-config >/dev/null
# The greeter.toml rule omits its source argument, so the path is implicit.
# Assert it, or a rename upstream is a greeter with no config -- a blank screen,
# not an error.
test -s /usr/share/factory/var/lib/noctalia-greeter/greeter.toml

# THE `r` + `C` PAIR IS NOT STYLE. Per tmpfiles.d(5) the + on a C line only lets
# the copy descend into a non-empty destination DIRECTORY; over an existing
# destination FILE, C and C+ both skip and log nothing. A C+ here would ship
# greeter.toml on initial provisioning and then silently ignore every later edit
# -- a login screen that quietly stops tracking the image. The `r` runs in the
# remove pass that precedes the create pass of the same run.
grep -qE '^r[[:space:]]+/var/lib/noctalia-greeter/greeter\.toml[[:space:]]*$' \
    /usr/lib/tmpfiles.d/bazzite-sway.conf
grep -qE '^C[[:space:]]+/var/lib/noctalia-greeter/greeter\.toml[[:space:]]' \
    /usr/lib/tmpfiles.d/bazzite-sway.conf
! grep -qE '^C\+[[:space:]]+/var/lib/noctalia-greeter/greeter\.toml' \
    /usr/lib/tmpfiles.d/bazzite-sway.conf

# Unlock the keyring at login rather than prompting separately;
# sway-portals.conf names gnome-keyring as the Secret backend. PAM orders
# modules within each type, so appending puts these last in their own type,
# which is where the keyring modules belong.
if ! grep -q pam_gnome_keyring /etc/pam.d/greetd; then
    cat >> /etc/pam.d/greetd <<'PAMEOF'
-auth      optional   pam_gnome_keyring.so
-session   optional   pam_gnome_keyring.so auto_start
PAMEOF
fi

# The base image's preset enables gdm, sddm AND plasmalogin together, with a
# comment admitting "the one which is installed first wins". Do not rely on it.
# Every DM unit carries [Install] Alias=display-manager.service, and systemctl
# will not clobber an existing alias symlink -- the base image already points it
# at plasmalogin -- so drop it before enabling greetd.
systemctl disable plasmalogin.service || true
rm -f /etc/systemd/system/display-manager.service
systemctl enable greetd.service

readlink -f /etc/systemd/system/display-manager.service | grep -q greetd.service
