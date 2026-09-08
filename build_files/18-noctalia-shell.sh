#!/usr/bin/bash
# The desktop shell: noctalia, wired to sway-session.target. The package is
# installed in 10-sway-install.sh with the rest of the desktop; this script owns
# the unit and the assertions.
#
# NO FALLBACK. The packages that used to be the shell are gone from the image
# and their configs are gone from dotfiles/, so recovering the old desktop is a
# `bootc rollback` AND a `git checkout` of dotfiles/ -- the image and the
# dotfiles roll back separately. See the README's Known limitations.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# Not `exec noctalia` in sway's config, which is what upstream documents.
# Starting from sway-session.target buys three things that line does not:
# systemd restarts the shell if it dies, `journalctl --user -u noctalia` has
# somewhere to write, and noctalia's own launch_apps_as_systemd_services becomes
# available -- it refuses to work without a systemd user manager.
install -Dpm0644 "${CTX}/system_files/usr/lib/systemd/user/noctalia.service" \
                 /usr/lib/systemd/user/noctalia.service

# Ship the enablement symlink directly rather than using a user preset:
# `systemctl --global enable` writes into /etc, which bootc then 3-way merges on
# every upgrade, and user presets only run for users created later.
install -d /usr/lib/systemd/user/sway-session.target.wants
ln -sfn ../noctalia.service \
    /usr/lib/systemd/user/sway-session.target.wants/noctalia.service

test -f /usr/lib/systemd/user/noctalia.service
test -L /usr/lib/systemd/user/sway-session.target.wants/noctalia.service
# The bare binary, not --daemon: see the unit's own comment.
grep -q '^ExecStart=/usr/bin/noctalia$' /usr/lib/systemd/user/noctalia.service

# RETIRING THE DROP-INS FOR THE PROGRAMS THAT CANNOT BE UNINSTALLED.
# sway-config-fedora hard-Requires waybar, swaylock, swayidle, grimshot,
# brightnessctl, playerctl and lxqt-policykit (see 10-sway-install.sh), and each
# would otherwise still be started by a Fedora drop-in.
#
# WHY /etc AND NOT dotfiles. layered-include merges /usr/share -> /etc ->
# ~/.config by basename, later winning, so either of the last two would work --
# but only /etc is present at FIRST LOGIN. dotfiles/ is linked by
# `just link-dotfiles`, which runs after the first boot, so a dotfiles-only
# retirement would give a fresh install two bars and two idle daemons, each
# locking the screen.
#
# It also makes each retirement recoverable and assertable, which a dotfile is
# neither of: `sudo rm` one and log out, and Fedora's version loads again --
# bootc 3-way merges /etc, so the deletion sticks. That is the way back to a
# working, unthemed bar and locker without a rollback.
install -d /etc/sway/config.d
for f in 90-bar.conf 90-swayidle.conf 95-autostart-policykit-agent.conf \
         60-bindings-screenshot.conf 60-bindings-volume.conf \
         60-bindings-brightness.conf 60-bindings-media.conf; do
    install -Dpm0644 "${CTX}/system_files/etc/sway/config.d/${f}" \
                     "/etc/sway/config.d/${f}"

    # BOTH halves, because each fails silently alone. A missing Fedora drop-in
    # means this file retires nothing -- most likely because upstream renamed
    # it, in which case the new name is live and unretired.
    test -f "/usr/share/sway/config.d/${f}"
    test -f "/etc/sway/config.d/${f}"

    # These are comment-only by design; the comments are the whole content. A
    # directive that landed in one would run.
    ! grep -qvE '^[[:space:]]*(#|$)' "/etc/sway/config.d/${f}"
done

rpm -q noctalia
test -x /usr/bin/noctalia
test -d /usr/share/noctalia/assets
test -d /usr/share/noctalia/assets/templates
test -d /usr/share/noctalia/assets/translations

# The shell and the greeter are separate packages on separate version lines from
# separate repos, which is exactly the shape that produces an unpredicted file
# conflict. They are disjoint today; assert it, because an upstream that decided
# to share an assets directory would break the greeter at the login prompt.
noctalia_files="$(rpm -ql noctalia   | grep -v '^/usr/lib/\.build-id' | sort)"
greeter_files="$(rpm -ql noctalia-greeter | grep -v '^/usr/lib/\.build-id' | sort)"
[[ -z "$(comm -12 <(printf '%s\n' "${noctalia_files}") \
                  <(printf '%s\n' "${greeter_files}"))" ]]

# THE THINGS WHOSE ABSENCE IS SILENT. Each is a package this image removed on
# the strength of noctalia providing the same service. If one is not true the
# image still builds, boots and logs in, and then something does not work with
# no error anywhere. Read off the binary rather than trusted -- `grep -a` rather
# than `strings`, because binutils is not a dependency of anything here.
#
#   polkit agent    -> pkexec, ujust and bazzite-user-setup HANG
#   NM secret agent -> a password-protected wifi network cannot be joined
#   bluez agent     -> an incoming pairing request has nothing to confirm it
grep -aq 'libpolkit-agent-1.so.0'                     /usr/bin/noctalia
grep -aq '/org/noctalia/PolkitAuthenticationAgent'    /usr/bin/noctalia
grep -aq 'org.freedesktop.NetworkManager.SecretAgent' /usr/bin/noctalia
grep -aq 'org.bluez.Agent1'                           /usr/bin/noctalia
grep -aq 'org.freedesktop.Notifications'              /usr/bin/noctalia

# A coupling that is easy to miss and expensive to find.
# /usr/share/sway/config.d/95-xdg-desktop-autostart.conf runs
# `wait-sni-ready && systemctl --user start sway-xdg-autostart.target`. That
# helper waits for a StatusNotifier HOST and gives up after 25s non-zero, which
# kills the `&&` -- so the autostart target never starts and the three
# gnome-keyring entries go with it. waybar used to be that host. If noctalia's
# tray were not one, removing waybar from the bar would silently cost the
# session its keyring.
grep -aq 'org.kde.StatusNotifierHost'                 /usr/bin/noctalia
grep -aq 'RegisterStatusNotifierHost'                 /usr/bin/noctalia

# The two Recommends that had to become explicit in 10-, asserted here because
# it is the shell that needs them. ddcutil is the ONLY brightness path on this
# hardware; wtype is the clipboard panel's auto-paste.
rpm -q ddcutil wtype

# A native EGL/GLES2 client, and /etc/sway/environment pins WLR_RENDERER=gles2
# because SwayFX's fx_renderer has no Vulkan path. A noctalia built against
# something else would come up blank rather than fail.
noctalia_libs="$(ldd /usr/bin/noctalia)"
[[ "${noctalia_libs}" == *libEGL*     ]]
[[ "${noctalia_libs}" == *libGLESv2*  ]]
[[ "${noctalia_libs}" == *libwayland-client* ]]

# THE FIRST THING IN THE LOGIN OR LOCK PATH THIS IMAGE CAN VALIDATE AT BUILD
# TIME. `noctalia config validate` takes a path, reports file:line:column and
# exits 1 on error. Proving it works here in BOTH directions is what makes
# verify.sh's run of it against the live config mean anything -- a validator
# that accepted everything would pass the first check alone.
#
# The config itself is not checked here and cannot be: dotfiles/ is not in the
# build context, and it is per-user by design.
#
# IF THIS BLOCK FAILS THE BUILD, the likely cause is that the subcommand wants a
# compositor after all, in which case it cannot run in a container. Move both
# checks to verify.sh -- do NOT weaken them to `|| true`, which leaves a check
# reporting success for a validator that never ran.
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

# DELIBERATELY NOT ASSERTED HERE, all of it verify.sh's job:
#   the config and the plugin  -- in dotfiles/, so not image content
#   the palette agreement      -- bazzite-grey.json vs the greeter's greeter.toml
#   the layer-shell namespaces -- nothing at build time can see a layer surface
#   that the shell draws at all -- no seat, no GPU, no compositor in a container

echo "shell: $(rpm -q noctalia), greeter: $(rpm -q noctalia-greeter)"
