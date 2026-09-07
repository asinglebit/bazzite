#!/usr/bin/bash
# Make greetd the display manager.
set -euxo pipefail

CTX="${CTX:-/ctx}"

cp -av "${CTX}/system_files/etc/greetd/config.toml" /etc/greetd/config.toml

# The greeter's compositor and its stylesheet. greetd no longer runs a greeter
# on the VT: it runs a Sway instance that hosts gtkgreet, because a console cell
# is a pixel bitmap and its physical size therefore tracks the framebuffer mode.
# See the files themselves for the measurements.
cp -av "${CTX}/system_files/etc/greetd/sway-greeter.conf" /etc/greetd/sway-greeter.conf
# The session list gtkgreet offers. DELIBERATELY BARE -- one command per line,
# no comments and no blank lines, which is exactly what Fedora's own
# /usr/libexec/gtkgreet-update-environments writes (bare `Exec=` values, sorted).
#
# It carries no explanation because it cannot: gtkgreet's environments format is
# not documented to support comments, and if it does not, every `#` line becomes
# a bogus entry in the session dropdown -- with the FIRST one as the default
# selection, i.e. a login that fails on the happy path. Not a risk worth taking
# on the login screen to save a comment, so the explanation lives here instead:
#
#   start-sway   the desktop. NOT `sway`: start-sway sources
#                /etc/sway/environment for --unsupported-gpu, -D noscanout and
#                WLR_RENDERER=gles2, without which sway will not start on this
#                GPU at all. Same command /usr/share/wayland-sessions/sway.desktop
#                uses.
#   bash -l      the escape hatch. If the session is broken, this is how you get
#                a prompt without dropping to a VT. It is the reason there is no
#                Plasma entry on the :sway build.
#
# gtkgreet reads THIS FILE ONLY -- unlike tuigreet's --sessions, it never scans
# /usr/share/wayland-sessions. Anything not listed here cannot be logged into.
cp -av "${CTX}/system_files/etc/greetd/environments"      /etc/greetd/environments

# gtkgreet reads its session list from /etc/greetd/environments and NOTHING
# else -- it does not scan /usr/share/wayland-sessions the way tuigreet's
# --sessions did. So on the REMOVE_KDE=0 build, Plasma has to be named here or
# it is not selectable at the login prompt, which would quietly defeat the whole
# point of boot 1 keeping it as a fallback session.
#
# Appended conditionally rather than shipped in the file, because on the :sway
# build startplasma-wayland does not exist and a dead entry in the session
# dropdown is worse than no entry.
if [[ "${REMOVE_KDE:-0}" != "1" ]]; then
    test -x /usr/bin/startplasma-wayland
    # Bare, for the same reason the shipped file is -- no comment line, no
    # blank line, or it could land in the dropdown as a session.
    printf 'startplasma-wayland\n' >> /etc/greetd/environments
    grep -q '^startplasma-wayland$' /etc/greetd/environments
else
    # And on :sway it must NOT be there, or the greeter offers a session that
    # cannot start.
    ! grep -q 'startplasma' /etc/greetd/environments
fi
install -Dpm0644 "${CTX}/system_files/etc/gtkgreet/style.css" /etc/gtkgreet/style.css

# What the greeter is made of. 10-sway-install.sh and 15-swayfx.sh both ran
# already, so these are all in place by now; asserted rather than assumed
# because every one of them is a blank login screen if it goes missing.
test -x /usr/bin/start-sway     # supplies --unsupported-gpu; sway alone would refuse
test -x /usr/bin/gtkgreet
rpm -q gtkgreet
# tuigreet is KEPT, unbound, as the fallback greeter -- see config.toml.
rpm -q tuigreet
# -q, not `| grep -q`: grep -q exits early, fc-list takes SIGPIPE, and the
# pipefail above turns a successful match into exit 141.
fc-list -q 'Inter'
fc-list -q 'Hack Nerd Font Mono'

# The greeter config is NOT parsed here -- see the long note in
# build_files/15-swayfx.sh for why `sway -C` cannot run in a build container
# (file capability, then a libseat/logind seat that does not exist, and a good
# config indistinguishable from a broken one).
#
# That is a real loss: a greeter config sway cannot parse means greetd burns its
# five restarts against a VT with no getty on it. What is left is asserting the
# config's CONTENT below, and verify.sh parsing it for real at runtime.

# And check the gtkgreet command line, which now lives inside that config where
# nothing else would ever look at it. Getting it wrong is not a cosmetic bug:
# greetd is Restart=always with StartLimitBurst=5 and
# Conflicts=getty@tty1.service, so five failures in thirty seconds leaves VT 1
# dead with no getty on it.
grep -q 'start-sway -c /etc/greetd/sway-greeter.conf' /etc/greetd/config.toml
grep -q -- '--style /etc/gtkgreet/style.css' /etc/greetd/sway-greeter.conf
test -s /etc/gtkgreet/style.css

# gtkgreet reads its session list from this file, not from
# /usr/share/wayland-sessions -- an empty or missing one is a greeter with
# nothing to log into.
test -s /etc/greetd/environments
grep -q '^start-sway$' /etc/greetd/environments
# Every line must be a runnable command: no comments, no blanks. See above.
! grep -qE '^[[:space:]]*(#|$)' /etc/greetd/environments
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
