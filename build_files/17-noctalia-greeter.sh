#!/usr/bin/bash
# The login screen: noctalia-greeter, which brings its own wlroots 0.20
# compositor.
#
# WHY IT IS NOT ON A VT. A kernel console draws in cells of a fixed pixel
# bitmap, so the same 8x16 cell measured 7.36mm on the 81 PPI HP and 3.69mm on
# the 160 PPI Dell, and this kernel is built `# CONFIG_FONTS is not set`. This
# greeter is a native EGL/GLES2 Wayland client and scales through
# wp_fractional_scale_v1 from each output's geometry, which is the whole point.
#
# WHAT IT COSTS: the login path runs a third-party wlroots compositor from
# Terra, whose open bugs cluster on multi-output DRM teardown -- this machine's
# exact shape. A failure here is a black screen, not a TTY. tuigreet stays
# installed and unbound as the single rung below it: no compositor, no GPU, so a
# driver regression still leaves something that can log you in. The switch-back
# line is in /etc/greetd/config.toml.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# The ghostty case, not the COPR case: the base image already ships terra.repo
# disabled with the keys trusted, so this adds no trust root.
#
# ITS OWN TRANSACTION, because --enable-repo is a dnf5 global and Terra also
# carries wlroots and mesa -- folding this into another list would let Terra
# satisfy anything in it. Terra's priority=150 against Fedora's 99 is what makes
# Fedora win a name collision; the vendor assertion below proves it did.
#
# greetd-fakegreet is from Fedora and stands in for greetd's IPC socket, so the
# greeter can be run from inside a live session without being bound to greetd.
# It is the only way to find out whether the greeter AGREES with greeter.toml --
# see the note at the end of this file. `just greeter-preview`.
dnf5 --enable-repo=terra install -y noctalia-greeter
dnf5 install -y greetd-fakegreet

# greetd runs this instead of noctalia-greeter-session directly: a separate
# wlroots instance inherits nothing from /etc/sway/environment, and neither a
# greetd.service drop-in nor greetd's own TOML can put it back. The file carries
# the full reasoning.
install -Dpm0755 "${CTX}/system_files/usr/libexec/noctalia-greeter-nvidia" \
                 /usr/libexec/noctalia-greeter-nvidia

# /usr/share/factory, NOT /var/lib/noctalia-greeter where the greeter actually
# reads it from: /var in a bootc image is applied on initial provisioning ONLY,
# so a file shipped there would not exist on an upgraded system. tmpfiles.d
# copies it into place on every boot instead -- the `r` + `C` pair installed by
# 20-display-manager.sh, which explains there why it is not a `C+`.
install -Dpm0644 "${CTX}/system_files/usr/share/factory/var/lib/noctalia-greeter/greeter.toml" \
                 /usr/share/factory/var/lib/noctalia-greeter/greeter.toml

# The greeter has NO avatar key -- it asks AccountsService for IconFile, which
# out of the box resolves to $HOME/.face. That cannot work: it runs as greetd
# and $HOME is 0700, so it cannot even traverse the directory. The symptom is
# the stock line-art placeholder.
#
# So the asset ships here, world readable, at a path unrelated to any home.
# Binding it to an account is per-user state and cannot live in the image, so
# that half is `just greeter-avatar`.
#
# SVG, not PNG: the greeter links librsvg and scales through
# wp_fractional_scale_v1. A rasterised avatar would be the same fixed-bitmap
# mistake this greeter exists to avoid.
install -Dpm0644 "${CTX}/system_files/usr/share/bazzite-sway/greeter-avatar.svg" \
                 /usr/share/bazzite-sway/greeter-avatar.svg

# NOT OPTIONAL. greetd runs as xdm_t on an enforcing system, /var/lib/greetd is
# xdm_var_lib_t by policy, and a freshly created /var/lib/noctalia-greeter gets
# plain var_lib_t -- which xdm_t cannot write. The symptom of a state directory
# the greeter cannot use is a blank login screen.
#
# Aliased rather than added: one line in file_contexts.subs makes the new path
# borrow greetd's rule, needing no policy module. Format is
# `/aliased_path /original_path`.
#
# NOT `semanage fcontext -a -e`, which does the same thing correctly and then
# loses it: semanage writes the equivalency into the policy store under
# /var/lib/selinux, and /var is not part of a bootc image. /etc is, and bootc
# 3-way merges it.
SUBS=/etc/selinux/targeted/contexts/files/file_contexts.subs
if ! grep -q '^/var/lib/noctalia-greeter /var/lib/greetd$' "${SUBS}" 2>/dev/null; then
    printf '/var/lib/noctalia-greeter /var/lib/greetd\n' >> "${SUBS}"
fi

rpm -q noctalia-greeter greetd-fakegreet

# The exec chain: greetd calls only the wrapper, which execs -session, which
# execs -compositor, which execs the greeter. A missing link anywhere is a black
# screen at boot.
test -x /usr/bin/noctalia-greeter
test -x /usr/bin/noctalia-greeter-compositor
test -x /usr/bin/noctalia-greeter-session
test -x /usr/libexec/noctalia-greeter-nvidia

# Getting either of these wrong is not cosmetic: greetd is Restart=always with
# StartLimitBurst=5 and Conflicts=getty@tty1.service, so five failures in thirty
# seconds leaves VT 1 with no getty on it.
grep -q 'noctalia-greeter-session' /usr/libexec/noctalia-greeter-nvidia
grep -q 'WLR_RENDERER:=gles2'      /usr/libexec/noctalia-greeter-nvidia

# Upstream's PACKAGING.md: the assets tree is required at runtime, not
# decoration. A binary without it loses its fonts and icons.
test -d /usr/share/noctalia-greeter/assets

# A config that fails to install does not break the build, it just comes up in
# somebody else's colours.
test -s /usr/share/factory/var/lib/noctalia-greeter/greeter.toml
grep -q '^surface *= *"#1a1a1a"$' /usr/share/factory/var/lib/noctalia-greeter/greeter.toml
fc-list -q 'Inter'

# The greeter has no validate-only mode (see the note at the end), but python3
# and tomllib are in this image, so syntax and the palette are checkable here
# rather than at the password prompt. The hex check earns its keep: the greeter's
# own reaction to a bad value is one line into the journal, from a screen that
# has nowhere to print.
python3 - /usr/share/factory/var/lib/noctalia-greeter/greeter.toml <<'TOMLCHECK'
import re, sys, tomllib

with open(sys.argv[1], "rb") as fh:
    cfg = tomllib.load(fh)

palette = cfg["appearance"]["palette"]
# A missing role falls back to a Noctalia default, i.e. a colour on a greyscale
# screen.
assert len(palette) == 16, f"expected 16 palette roles, got {len(palette)}: {sorted(palette)}"
bad = {k: v for k, v in palette.items() if not re.fullmatch(r"#[0-9a-fA-F]{6}", str(v))}
assert not bad, f"invalid hex in [appearance.palette]: {bad}"

greys = {"#1a1a1a", "#242424", "#2e2e2e", "#5a5a5a", "#9a9a9a", "#d8d8d8", "#ffffff"}
off = {k: v for k, v in palette.items() if v not in greys}
assert not off, f"off-palette colours on the login screen: {off}"

# The two settings that would silently reintroduce Noctalia's own look.
assert cfg["appearance"]["scheme_selector_position"] == "hidden"
assert cfg["appearance"]["font_family"] == "Inter"

# Per-connector scale constants are the console-cell mistake in a different
# file. See the comment at the bottom of greeter.toml.
assert "output" not in cfg, "greeter.toml has an [output] block -- scale is derived, not declared"
TOMLCHECK

# THE ONE BEHAVIOURAL CHECK THE BUILD CAN MAKE. `noctalia-greeter sessions`
# reads /usr/share/wayland-sessions through the greeter's own code and exits
# before it wants a display, a seat or a config, so unlike the compositor it
# runs in a build container. An empty list is a login screen with nothing to log
# into.
#
# WHAT IT CANNOT SEE: 30-kde-remove.sh has not run yet, so the list here is
# "Sway\nPlasma". This asserts only that Sway is OFFERED; that the finished
# image offers nothing else is checked by CI and by verify.sh after boot.
#
# Captured rather than piped: grep -q exits at its first match and pipefail
# turns the writer's SIGPIPE into a failed build.
greeter_sessions="$(noctalia-greeter sessions)"
[[ "${greeter_sessions}" == *Sway* ]]

# THE SONAME PAIR IS THE POINT. This greeter needs wlroots 0.20 (F44's
# `wlroots`), SwayFX needs 0.19 (the `wlroots0.19` compat package), and they are
# meant to coexist. The last line is the tripwire: if anything swaps sway onto
# 0.20, the session breaks and this is where it is noticed.
#
# ldd into a variable, never `ldd | grep -q` -- see 15-swayfx.sh.
greeter_libs="$(ldd /usr/bin/noctalia-greeter-compositor)"
[[ "${greeter_libs}" == *libwlroots-0.20.so* ]]
[[ "${greeter_libs}" == *libEGL*             ]]
[[ "${greeter_libs}" == *libGLESv2*          ]]
sway_libs="$(ldd /usr/bin/sway)"
[[ "${sway_libs}" == *libwlroots-0.19.so* ]]

# Terra carries its own wlroots. If enabling the repo above ever pulls Fedora's
# out from under mesa and swayfx, it will be because a version comparison beat
# the priority, and it will not be obvious.
[[ "$(rpm -q --queryformat '%{VENDOR}' wlroots)" == "Fedora Project" ]]

# noctalia-greeter-session runs the compositor under `dbus-run-session` when
# available and SILENTLY WITHOUT IT when not. With no bus there is no logind
# resume handling, no AccountsService avatars and no working power buttons -- a
# degraded greeter that still starts, the worst kind of missing dependency. dbus
# is a hard Requires, but the binary that matters is in dbus-daemon.
test -x /usr/bin/dbus-run-session

# tuigreet is KEPT, unbound, as the only fallback. gtkgreet is gone: it needed a
# compositor of its own to host it, which is the layer this deletes.
rpm -q tuigreet
! rpm -q gtkgreet

# The SELinux alias, the one item here whose absence is silent. matchpathcon
# reads file_contexts on disk, so it works in the build container even with no
# policy loaded.
grep -q '^/var/lib/noctalia-greeter /var/lib/greetd$' \
    /etc/selinux/targeted/contexts/files/file_contexts.subs
greeter_state_context="$(matchpathcon /var/lib/noctalia-greeter)"
[[ "${greeter_state_context}" == *xdm_var_lib_t* ]]

# WHAT IS NOT ASSERTED, because it cannot be. The checks above cover
# greeter.toml's syntax and values, plus the session list behaviourally. What
# they cannot cover is whether the greeter AGREES those are its keys:
# `--help` offers only `sessions` and `outputs`, there is no validate-only mode,
# and NEITHER subcommand reads greeter.toml at all -- tested, `sessions` prints
# the same list with the config deliberately corrupted. A misspelled key is
# ignored in silence and looks exactly like a key that had no effect.
#
# So the semantic gap is closed at runtime, which is why greetd-fakegreet is
# installed above:
#
#   just greeter-preview  runs THIS greeter and THIS config nested in a live
#                         session against fakegreet. Validates the palette and
#                         the session list; exercises no DRM and no renderer
#                         selection, so it does not tell you the login screen
#                         will come up on this GPU.
#   ./verify.sh           checks the state directory, its SELinux label, and
#                         that the greeter enumerates a session, after boot.
#
# Do not add a build-time check here that only appears to work.

echo "greeter: $(rpm -q noctalia-greeter), fallback: $(rpm -q tuigreet)"
