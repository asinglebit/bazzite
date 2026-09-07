#!/usr/bin/bash
# Make greetd the display manager.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# The greeter itself -- the package, its GPU wrapper and its config -- is
# 17-noctalia-greeter.sh. This script only binds greetd and points it at the
# result, which is the order the build needs: greetd has to be the display
# manager before 30-kde-remove.sh takes plasmalogin out.
cp -av "${CTX}/system_files/etc/greetd/config.toml" /etc/greetd/config.toml

# What the greeter is made of. 17-noctalia-greeter.sh ran already and asserted
# all of this itself; re-asserted here because this is the file that names the
# command line, and every one of them is a blank login screen if it goes missing.
test -x /usr/libexec/noctalia-greeter-nvidia
test -x /usr/bin/noctalia-greeter-session
# tuigreet is KEPT, unbound, as the fallback greeter -- see config.toml.
rpm -q tuigreet

# greeter.toml is validated in 17-noctalia-greeter.sh -- TOML syntax, the
# palette, and the session list through the greeter's own `sessions` command.
# What NEITHER script can check is whether the greeter agrees those are its keys:
# it has no validate-only mode, and a misspelled one is ignored in silence. See
# the note at the bottom of that file, and 15-swayfx.sh for the original version
# of the same wall.
#
# That gap matters here because greetd is Restart=always with StartLimitBurst=5
# and Conflicts=getty@tty1.service, so five failures in thirty seconds leaves VT
# 1 dead with no getty on it. What this file adds is asserting the command line's
# CONTENT below; verify.sh checks the live greeter after boot.
grep -q '^command = "/usr/libexec/noctalia-greeter-nvidia"$' /etc/greetd/config.toml
grep -q '^user = "greetd"$' /etc/greetd/config.toml
grep -q '^vt = 1$'          /etc/greetd/config.toml

# The session list. noctalia-greeter scans /usr/share/wayland-sessions and
# nothing else -- no /etc/greetd/environments (that file is gone with gtkgreet,
# which read only it and never scanned anything), no /usr/share/xsessions. So
# this desktop entry, shipped by sway-config-fedora, IS the session list, and an
# `Exec=` that does not go through start-sway is a login that fails on the happy
# path: sway will not start on this GPU without the flags start-sway sources.
#
# Nothing has to be added here for Plasma any more either. This image always
# removes it, and anything else that ships a wayland-sessions entry shows up on
# its own.
test -f /usr/share/wayland-sessions/sway.desktop
grep -q '^Exec=start-sway$' /usr/share/wayland-sessions/sway.desktop

cp -av "${CTX}/system_files/usr/lib/systemd/system-preset/05-sway-dm.preset" \
       /usr/lib/systemd/system-preset/05-sway-dm.preset

# Everything this image needs under /var is created by tmpfiles.d, never by
# shipping it in the image -- see the file itself for why. That now includes the
# greeter's state directory and its copy of greeter.toml, whose source
# 17-noctalia-greeter.sh put under /usr/share/factory.
cp -av "${CTX}/system_files/usr/lib/tmpfiles.d/bazzite-sway.conf" \
       /usr/lib/tmpfiles.d/bazzite-sway.conf
systemd-tmpfiles --cat-config >/dev/null
# The greeter.toml rule in there copies from /usr/share/factory with its source
# argument omitted, so the path it resolves to is implicit. Assert it explicitly,
# or a rename upstream of this line is a greeter with no config -- which is a
# blank screen, not an error.
test -s /usr/share/factory/var/lib/noctalia-greeter/greeter.toml

# And that the rule is still the `r` + `C` pair rather than the `C+` it was
# written as first. This is not style. Per tmpfiles.d(5) the + on a C line only
# lets the copy descend into a non-empty destination DIRECTORY; over an existing
# destination FILE, C and C+ both skip and both log nothing. A C+ here therefore
# ships greeter.toml on initial provisioning and then silently ignores every
# later edit to it -- a login screen that quietly stops tracking the image, with
# nothing anywhere saying so. The `r` runs in the remove pass that precedes the
# create pass of the same `systemd-tmpfiles --create --remove --boot`.
grep -qE '^r[[:space:]]+/var/lib/noctalia-greeter/greeter\.toml[[:space:]]*$' \
    /usr/lib/tmpfiles.d/bazzite-sway.conf
grep -qE '^C[[:space:]]+/var/lib/noctalia-greeter/greeter\.toml[[:space:]]' \
    /usr/lib/tmpfiles.d/bazzite-sway.conf
! grep -qE '^C\+[[:space:]]+/var/lib/noctalia-greeter/greeter\.toml' \
    /usr/lib/tmpfiles.d/bazzite-sway.conf

# Unlock the gnome-keyring at login instead of prompting for it separately.
# sway-portals.conf names gnome-keyring as the Secret portal backend.
# PAM orders modules within each type, so appending puts these last in their
# own type -- which is exactly where the keyring modules belong.
#
# pam_systemd needs no help here: /etc/pam.d/greetd already reaches it through
# `session include system-auth`, which is what gives the greeter's own session a
# logind seat.
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
