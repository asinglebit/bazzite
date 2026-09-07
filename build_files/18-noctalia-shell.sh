#!/usr/bin/bash
# The desktop shell: noctalia, wired to sway-session.target.
#
# WHAT THIS REPLACES. Nine programs, each with its own config language and its
# own stylesheet: waybar (JSONC + CSS), SwayNotificationCenter (JSON + 635 lines
# of CSS), rofi (rasi), wlogout (layout + CSS), hyprlock and hypridle
# (hyprlang), mako (ini), cliphist behind two rofi wrapper scripts, and
# mate-polkit. noctalia draws all of it from one TOML directory and one palette,
# and the parts that had no equivalent -- the sway binding-mode indicator, the
# scratchpad count, failed units, and hardware readings with an alert threshold
# -- are four Luau entries in dotfiles/noctalia/plugins/bazzite-sway/.
#
# The package is installed in 10-sway-install.sh, with the desktop, because
# noctalia is in Fedora proper: no repo to enable, so none of the reasoning that
# gives ghostty and noctalia-greeter their own transactions applies. This script
# owns the unit, and the assertions.
#
# WHAT IT COSTS, stated where it can be read. The greeter's cost note in 17- says
# a greeter failure is a black screen rather than a TTY, and that tuigreet stays
# installed and unbound as the rung below it. There is no such rung here. A
# session shell has no fallback: the packages that used to be it are gone from
# the image, and their configs are gone from dotfiles/, so recovering the old
# desktop is a `bootc rollback` AND a `git checkout` of dotfiles/ -- the image
# and the dotfiles roll back separately, which is written up in the README's
# Known limitations. noctalia 5.0.1 is the first stable release of a ground-up
# C++ rewrite, and upstream's open bugs for this codebase family cluster on
# multi-output DRM teardown, which is this machine's exact shape.
#
# WHAT IS *NOT* NEW, and is the reason the risk was taken: this image has run
# noctalia-greeter on the login path since 17- landed. The shell is a different
# product on a different version line, but it is the same project, the same
# renderer and the same palette -- and the login screen already survives what is
# being asked of the desktop here.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# --- The unit ----------------------------------------------------------------
#
# Not an `exec noctalia` in sway's config, which is what upstream documents for
# sway, and not the shipped .desktop either. This image starts session services
# from sway-session.target -- the arrangement swaync and hypridle both used, for
# the reasons written beside the polkit agent in 10-sway-install.sh -- and doing
# it the same way buys three things upstream's line does not: systemd restarts
# the shell if it dies, `journalctl --user -u noctalia` has somewhere to write,
# and noctalia's own `launch_apps_as_systemd_services` becomes available, which
# it refuses without a systemd user manager ("...but Noctalia is not running
# under the systemd user manager").
install -Dpm0644 "${CTX}/system_files/usr/lib/systemd/user/noctalia.service" \
                 /usr/lib/systemd/user/noctalia.service

# Ship the enablement symlink directly rather than relying on a user preset:
# `systemctl --global enable` writes into /etc, which bootc then has to 3-way
# merge on every upgrade, and user presets only run for users created later.
# This directory used to be created next to the polkit agent in 10-; that block
# is gone, so it is created here.
install -d /usr/lib/systemd/user/sway-session.target.wants
ln -sfn ../noctalia.service \
    /usr/lib/systemd/user/sway-session.target.wants/noctalia.service

test -f /usr/lib/systemd/user/noctalia.service
test -L /usr/lib/systemd/user/sway-session.target.wants/noctalia.service
# The bare binary, not --daemon: see the unit's own comment for why.
grep -q '^ExecStart=/usr/bin/noctalia$' /usr/lib/systemd/user/noctalia.service

# --- Retiring the nine programs that could not be uninstalled ----------------
#
# sway-config-fedora hard-Requires waybar, swaylock, swayidle, grimshot,
# brightnessctl, playerctl and lxqt-policykit -- see the long note in
# 10-sway-install.sh. It owns /etc/sway/config, start-sway, layered-include and
# the wayland-sessions entry, so it cannot be dropped, so neither can they.
# Every one of them is a role noctalia now fills, and every one of them would
# otherwise still be started by a Fedora drop-in in /usr/share/sway/config.d/.
#
# WHY /etc AND NOT dotfiles. layered-include merges
# /usr/share/sway/config.d -> /etc/sway/config.d -> ~/.config/sway/config.d by
# basename, later winning, so either of the last two retires a Fedora drop-in.
# Only /etc is present at first login. dotfiles/ is linked by
# `just link-dotfiles`, which runs AFTER the first boot -- so a dotfiles-only
# retirement would give a fresh install a session with two bars and two idle
# daemons, each locking the screen. That is the same trap 16-hyprlock.sh set for
# itself and then fixed with its /etc/xdg/hypr floor; this does it the right way
# round from the start.
#
# It also makes each retirement recoverable and assertable, which a dotfile is
# neither of: `sudo rm` one and log out, and Fedora's version loads again --
# bootc 3-way merges /etc, so the deletion sticks. That is the way back to a
# working, unthemed bar and locker if the shell misbehaves, without a rollback.
install -d /etc/sway/config.d
for f in 90-bar.conf 90-swayidle.conf 95-autostart-policykit-agent.conf \
         60-bindings-screenshot.conf 60-bindings-volume.conf \
         60-bindings-brightness.conf 60-bindings-media.conf; do
    install -Dpm0644 "${CTX}/system_files/etc/sway/config.d/${f}" \
                     "/etc/sway/config.d/${f}"

    # BOTH halves, because each fails silently on its own.
    #
    # If the Fedora drop-in is missing, this file retires nothing and the
    # retirement is pure confusion -- most likely because upstream renamed it,
    # in which case whatever it was renamed to is now live and unretired.
    test -f "/usr/share/sway/config.d/${f}"
    test -f "/etc/sway/config.d/${f}"

    # And if a directive ever lands in one of these, it runs. They are comment
    # only by design; the comments are the whole content.
    ! grep -qvE '^[[:space:]]*(#|$)' "/etc/sway/config.d/${f}"
done

# --- What the package has to actually contain --------------------------------
rpm -q noctalia
test -x /usr/bin/noctalia
test -d /usr/share/noctalia/assets
test -d /usr/share/noctalia/assets/templates
test -d /usr/share/noctalia/assets/translations

# The shell and the greeter are separate packages on separate version lines from
# separate repos -- 5.x from Fedora, 1.x from Terra -- which is exactly the shape
# that produces a file conflict nobody predicted. They are disjoint today
# (/usr/share/noctalia vs /usr/share/noctalia-greeter); assert it, because an
# upstream that decided to share an assets directory would break the greeter and
# the failure would appear at the login prompt.
noctalia_files="$(rpm -ql noctalia   | grep -v '^/usr/lib/\.build-id' | sort)"
greeter_files="$(rpm -ql noctalia-greeter | grep -v '^/usr/lib/\.build-id' | sort)"
[[ -z "$(comm -12 <(printf '%s\n' "${noctalia_files}") \
                  <(printf '%s\n' "${greeter_files}"))" ]]

# --- The three things whose absence is silent --------------------------------
#
# Each of these is a package this commit REMOVED on the strength of noctalia
# providing the same service. If any of them is not true, the image still builds,
# still boots and still logs in -- and then something does not work with no error
# anywhere. So they are read off the binary rather than trusted, the same method
# 25-effects.conf used to get its layer-shell namespaces. `grep -a` rather than
# `strings` because binutils is not a dependency of anything here.
#
#   mate-polkit            -> pkexec, ujust and bazzite-user-setup hang
#   network-manager-applet -> a password-protected wifi network cannot be joined
#                             (nm-applet was the NetworkManager secret agent;
#                             rofi-wifi.sh only worked because nmcli registers
#                             its own agent for the duration of one call, and
#                             that script is gone too)
#   blueman's applet       -> an incoming pairing request has nothing to confirm
#                             it (this one was ALREADY broken and is now fixed;
#                             see dotfiles/autostart/blueman.desktop)
grep -aq 'libpolkit-agent-1.so.0'                     /usr/bin/noctalia
grep -aq '/org/noctalia/PolkitAuthenticationAgent'    /usr/bin/noctalia
grep -aq 'org.freedesktop.NetworkManager.SecretAgent' /usr/bin/noctalia
grep -aq 'org.bluez.Agent1'                           /usr/bin/noctalia
grep -aq 'org.freedesktop.Notifications'              /usr/bin/noctalia

# And a fourth, which is not about a removed package but about a coupling that
# is easy to miss and expensive to find.
#
# /usr/share/sway/config.d/95-xdg-desktop-autostart.conf runs
# `wait-sni-ready && systemctl --user start sway-xdg-autostart.target`. That
# helper waits for a StatusNotifier HOST to appear and gives up after
# SNI_WAIT_TIMEOUT (25s) with a non-zero exit -- which kills the `&&`, so the
# autostart target never starts and the three gnome-keyring autostart entries
# (secrets, ssh, pkcs11) go with it. waybar used to be that host. If noctalia's
# tray widget were not one, removing waybar from the bar would silently cost the
# session its keyring.
grep -aq 'org.kde.StatusNotifierHost'                 /usr/bin/noctalia
grep -aq 'RegisterStatusNotifierHost'                 /usr/bin/noctalia

# The two Recommends that had to become explicit, asserted here rather than in
# 10- because it is the shell that needs them and the shell that makes them
# non-obvious. Weak deps are off in this base (install_weak_deps=False), so a
# Recommends buys nothing -- see the long note in 10-sway-install.sh.
#
#   ddcutil -> the ONLY brightness path on this hardware; /sys/class/backlight is
#              empty, both outputs being external, so brightnessctl never worked.
#   wtype   -> the clipboard panel's auto-paste.
rpm -q ddcutil wtype

# The renderer, for the same reason 16- checked hyprlock's: this is a native
# EGL/GLES2 client, and /etc/sway/environment pins WLR_RENDERER=gles2 because
# SwayFX's fx_renderer has no Vulkan path. A noctalia built against something
# else would come up blank rather than fail.
noctalia_libs="$(ldd /usr/bin/noctalia)"
[[ "${noctalia_libs}" == *libEGL*     ]]
[[ "${noctalia_libs}" == *libGLESv2*  ]]
[[ "${noctalia_libs}" == *libwayland-client* ]]

# --- The first thing in this image that can be validated at build time -------
#
# README's load-bearing section says nothing in the login or lock path can be
# checked by the thing that reads it: hypridle connected to Wayland before
# parsing anything, hyprlock had no validate-only mode, and one typo was a dead
# locker with silence as the only symptom.
#
# `noctalia config validate` is that missing mode. It takes a path, reports
# file:line:column, and exits 1 on error -- so this proves at BUILD time that the
# validator works, which is what makes verify.sh's run of it against the live
# dotfiles config mean anything. Both directions are checked, because a validator
# that accepts everything would pass the first check alone.
#
# The config itself is NOT checked here and cannot be: dotfiles/ is not in the
# build context (the Containerfile's ctx stage copies build_files/ and
# system_files/ only, by the repo boundary the README sets out), and it is
# per-user by design. verify.sh runs the validator on the real thing.
#
# IF THIS BLOCK FAILS THE BUILD: the likely cause is that the subcommand wants a
# compositor after all, in which case it cannot run in a container at all. Move
# both checks to verify.sh and note it here -- do not weaken them to `|| true`,
# which would leave a check that reports success for a validator that never ran.
validate_dir="$(mktemp -d)"
cat > "${validate_dir}/good.toml" <<'GOOD'
[bar.default]
position = "top"
GOOD
cat > "${validate_dir}/bad.toml" <<'BAD'
[bar.default
position = "top
BAD
noctalia config validate "${validate_dir}/good.toml"
! noctalia config validate "${validate_dir}/bad.toml"
rm -rf "${validate_dir}"

# --- What is deliberately NOT asserted here ----------------------------------
#
# THE CONFIG AND THE PLUGIN. Both live in dotfiles/, so neither exists at build
# time and neither is image content. What checks them is verify.sh: that the
# config validates, that the four plugin entries are present and enabled, and
# that the palette still agrees with the greeter's.
#
# THE PALETTE AGREEMENT. dotfiles/noctalia/palettes/bazzite-grey.json and
# system_files/.../greeter.toml carry the same sixteen Material roles, and they
# have to stay equal -- the desktop and the login screen are the same greyscale
# or the handoff at login is visible. greeter-sync is what upstream offers for
# this and it is deliberately unused: tmpfiles.d recreates the greeter's /var
# copy from /usr/share/factory on EVERY boot, so a sync write is reverted at the
# next reboot. A static palette needs no sync, and the equality is held by a
# check in verify.sh instead of by hand.
#
# THE LAYER-SHELL NAMESPACES. dotfiles/sway/config.d/25-effects.conf blurs
# noctalia's surfaces by namespace, and `layer_effects` matches a literal string,
# so a wrong one is not an error -- it is an unblurred panel. Nothing at build
# time can see a layer surface. verify.sh compares the namespaces in that file
# against the ones a running shell actually creates.
#
# THAT THE SHELL DRAWS ANYTHING AT ALL. Same wall 16- and 17- hit: no seat, no
# GPU, no compositor in a container.

echo "shell: $(rpm -q noctalia), greeter: $(rpm -q noctalia-greeter)"
