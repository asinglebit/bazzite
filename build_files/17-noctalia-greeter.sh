#!/usr/bin/bash
# The login screen: noctalia-greeter, which brings its own compositor.
#
# WHAT THIS REPLACES. greetd used to run `start-sway -c
# /etc/greetd/sway-greeter.conf`, a throwaway SwayFX instance whose only client
# was gtkgreet on a layer surface. That existed because the greeter has to be
# resolution-independent and a kernel console cannot be: a VT draws in cells of
# a fixed *pixel* bitmap, so the same 8x16 cell measured 7.36mm tall on the
# 81 PPI HP and 3.69mm on the 160 PPI Dell, and this kernel is built
# `# CONFIG_FONTS is not set` so fbcon has nothing bigger to offer.
#
# noctalia-greeter reaches the same place from the other side. It is a native
# C++/EGL/GLES2 Wayland client -- no Qt, no GTK, no Quickshell -- and it ships
# /usr/bin/noctalia-greeter-compositor, a wlroots 0.20 instance of its own. So
# the whole "sway hosts the greeter" layer goes away rather than being ported:
# no sway-greeter.conf, no --layer-shell, no /etc/greetd/environments. It scales
# through wp_fractional_scale_v1 + wp_viewporter from each output's geometry,
# which is the property the compositor was put in the login path for.
#
# WHAT IT COSTS, stated where it can be read. The login path now runs a
# four-month-old third-party wlroots compositor from Terra rather than anything
# Fedora ships, and upstream's open bugs cluster on multi-output DRM teardown --
# which is this machine's exact shape, two panels at very different PPI. A
# greeter failure here is a black screen, not a TTY. tuigreet stays installed
# and unbound as the single rung below it: it needs no compositor and no GPU at
# all, so a driver regression that takes this greeter down still leaves
# something that can log you in. The exact switch-back line is in
# /etc/greetd/config.toml.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# From Terra, and NOT behind a hand-written repo file like swayfx and hyprlock.
# This is the ghostty case, not the COPR case: the base image already ships
# /etc/yum.repos.d/terra.repo with enabled=0 and the Terra signing keys are
# already in /etc/pki/rpm-gpg/, and Bazzite itself enables terra-mesa. So this
# adds no trust root -- it enables, for one transaction, a repo the artifact
# already trusts.
#
# Its own transaction, for the reason spelled out beside ghostty in
# 10-sway-install.sh: --enable-repo is a dnf5 global, so folding this into
# another install list would let Terra satisfy anything in that list and quietly
# swap a Fedora build for a Terra one. Terra also carries wlroots and mesa.
# Its priority=150 (against Fedora's default 99) is what makes Fedora win a name
# collision; the vendor assertion below is what proves it did.
#
# greetd-fakegreet comes from Fedora, not Terra, and is here so the greeter can
# be run and re-themed from inside a live session without ever being bound to
# greetd -- it stands in for greetd's IPC socket. See `just greeter-preview`.
# It is the only way to find out whether the greeter AGREES with greeter.toml;
# the note at the bottom of this file says why the build cannot.
dnf5 --enable-repo=terra install -y noctalia-greeter
dnf5 install -y greetd-fakegreet

# --- The GPU environment the bundled compositor cannot inherit ---------------
#
# greetd runs this instead of noctalia-greeter-session directly. The file itself
# carries the full reasoning; the short version is that a separate wlroots
# instance inherits nothing from /etc/sway/environment, and neither a
# greetd.service drop-in nor greetd's own TOML can put it back.
install -Dpm0755 "${CTX}/system_files/usr/libexec/noctalia-greeter-nvidia" \
                 /usr/libexec/noctalia-greeter-nvidia

# --- The greeter's configuration ---------------------------------------------
#
# /usr/share/factory rather than /var/lib/noctalia-greeter, which is where the
# greeter actually reads it from: /var in a bootc image is applied on initial
# provisioning ONLY, so a file shipped there would not exist on an upgraded
# system. tmpfiles.d copies it into place on every boot instead -- the `r` + `C`
# pair in system_files/usr/lib/tmpfiles.d/bazzite-sway.conf, installed by
# 20-display-manager.sh, which explains there why it is not the `C+` this used
# to be. The file's own header repeats all of this, because it is the kind of
# thing that gets "tidied" into /etc by someone who has not hit it.
install -Dpm0644 "${CTX}/system_files/usr/share/factory/var/lib/noctalia-greeter/greeter.toml" \
                 /usr/share/factory/var/lib/noctalia-greeter/greeter.toml

# --- SELinux -----------------------------------------------------------------
#
# NOT OPTIONAL, and not something upstream has hit: greetd runs as xdm_t on an
# enforcing system, /var/lib/greetd is xdm_var_lib_t by policy, and a freshly
# created /var/lib/noctalia-greeter gets plain var_lib_t -- which xdm_t cannot
# write. The documented symptom of a state directory the greeter cannot use is a
# blank login screen, i.e. indistinguishable from every other way this can fail.
#
# Aliased rather than added: one line in file_contexts.subs makes the new path
# borrow greetd's existing rule, which needs no policy module and no
# recompilation. The format is `/aliased_path /original_path`, documented in
# file_contexts.subs_dist beside it.
#
# NOT `semanage fcontext -a -e`, which would do the same thing correctly and
# then lose it: semanage writes the equivalency into the policy STORE under
# /var/lib/selinux, and /var is not part of a bootc image. /etc is, and bootc
# 3-way merges it -- the same reason the PAM edit in 20-display-manager.sh is an
# append to /etc/pam.d/greetd.
SUBS=/etc/selinux/targeted/contexts/files/file_contexts.subs
if ! grep -q '^/var/lib/noctalia-greeter /var/lib/greetd$' "${SUBS}" 2>/dev/null; then
    printf '/var/lib/noctalia-greeter /var/lib/greetd\n' >> "${SUBS}"
fi

# --- Guard rails -------------------------------------------------------------
rpm -q noctalia-greeter greetd-fakegreet

# Three of the package's five binaries, and the wrapper in front of them. greetd
# calls only the wrapper; the wrapper execs -session, which execs -compositor,
# which execs the greeter. A missing link anywhere in that chain is a black
# screen at boot, so each one is asserted rather than assumed.
test -x /usr/bin/noctalia-greeter
test -x /usr/bin/noctalia-greeter-compositor
test -x /usr/bin/noctalia-greeter-session
test -x /usr/libexec/noctalia-greeter-nvidia

# The wrapper's contents, checked here rather than in 20-display-manager.sh
# because this is the file they live in. Getting either wrong is not cosmetic:
# greetd is Restart=always with StartLimitBurst=5 and
# Conflicts=getty@tty1.service, so five failures in thirty seconds leaves VT 1
# with no getty on it.
grep -q 'noctalia-greeter-session' /usr/libexec/noctalia-greeter-nvidia
grep -q 'WLR_RENDERER:=gles2'      /usr/libexec/noctalia-greeter-nvidia

# Upstream's PACKAGING.md states the shipped assets tree is required at runtime,
# not decoration: a binary without it loses its fonts and icons.
test -d /usr/share/noctalia-greeter/assets

# The config, and the one line in it that proves it is the greyscale copy rather
# than something stock. Asserted for the same reason the fonts are: a config
# that fails to install does not break the build, it just quietly comes up in
# somebody else's colours.
test -s /usr/share/factory/var/lib/noctalia-greeter/greeter.toml
grep -q '^surface *= *"#1a1a1a"$' /usr/share/factory/var/lib/noctalia-greeter/greeter.toml
fc-list -q 'Inter'

# And that it is TOML the greeter can actually load. The greeter has no
# validate-only mode -- see the note at the end of this file -- but python3 and
# tomllib are both in this image, so syntax and the palette's hex values are
# checkable here instead of at the password prompt. The hex check earns its keep:
# the greeter's own reaction to a bad value is one line into the journal,
# "greeter.toml appearance.palette has an invalid hex value", from a screen that
# has nowhere to print.
python3 - /usr/share/factory/var/lib/noctalia-greeter/greeter.toml <<'TOMLCHECK'
import re, sys, tomllib

with open(sys.argv[1], "rb") as fh:
    cfg = tomllib.load(fh)

palette = cfg["appearance"]["palette"]
# 16 Material roles, the set upstream's examples/greeter.toml carries. A missing
# one falls back to a Noctalia default, i.e. a colour on a greyscale screen.
assert len(palette) == 16, f"expected 16 palette roles, got {len(palette)}: {sorted(palette)}"
bad = {k: v for k, v in palette.items() if not re.fullmatch(r"#[0-9a-fA-F]{6}", str(v))}
assert not bad, f"invalid hex in [appearance.palette]: {bad}"

greys = {"#1a1a1a", "#242424", "#2e2e2e", "#5a5a5a", "#9a9a9a", "#d8d8d8", "#ffffff"}
off = {k: v for k, v in palette.items() if v not in greys}
assert not off, f"off-palette colours on the login screen: {off}"

# The two settings that would silently reintroduce Noctalia's own look.
assert cfg["appearance"]["scheme_selector_position"] == "hidden"
assert cfg["appearance"]["font_family"] == "Inter"

# No [output] block: per-connector scale constants are the console-cell mistake
# written in a different file. See the comment at the bottom of greeter.toml.
assert "output" not in cfg, "greeter.toml has an [output] block -- scale is derived, not declared"
TOMLCHECK

# THE ONE BEHAVIOURAL CHECK THE BUILD CAN MAKE. `noctalia-greeter sessions` reads
# /usr/share/wayland-sessions through the greeter's own code and exits before it
# wants a Wayland display, a seat or a config -- verified with WAYLAND_DISPLAY and
# XDG_RUNTIME_DIR both unset -- so unlike the compositor it runs in a build
# container. An empty list here is a login screen with nothing to log into.
#
# Captured into a variable rather than piped to grep, for the reason in
# 15-swayfx.sh: grep -q exits at its first match and pipefail turns the writer's
# SIGPIPE into a failed build.
#
# WHAT THIS CANNOT SEE: 30-kde-remove.sh has not run yet, so at this point the
# list is "Sway\nPlasma" -- plasma-workspace still owns
# /usr/share/wayland-sessions/plasma.desktop and takes it along when it goes.
# This asserts only that Sway is OFFERED. That the finished image offers nothing
# else is checked where the finished image exists: the CI image check, and
# verify.sh after boot.
greeter_sessions="$(noctalia-greeter sessions)"
[[ "${greeter_sessions}" == *Sway* ]]

# ldd once into a variable, then bash pattern matching -- NOT `ldd | grep -q`.
# See the note in 15-swayfx.sh: grep -q exits at its first match, ldd takes
# SIGPIPE, and the pipefail above turns a passing assertion into exit 141.
#
# The soname pair is the point. This greeter needs wlroots 0.20 (Fedora 44's
# `wlroots`), SwayFX needs 0.19 (Fedora's `wlroots0.19` compat package), and
# they are meant to coexist. The second line is the tripwire: if anything ever
# swaps sway onto 0.20, the session breaks and this is where it is noticed.
greeter_libs="$(ldd /usr/bin/noctalia-greeter-compositor)"
[[ "${greeter_libs}" == *libwlroots-0.20.so* ]]
[[ "${greeter_libs}" == *libEGL*             ]]
[[ "${greeter_libs}" == *libGLESv2*          ]]
sway_libs="$(ldd /usr/bin/sway)"
[[ "${sway_libs}" == *libwlroots-0.19.so* ]]

# And that wlroots itself is still Fedora's. Terra carries its own; if enabling
# the repo above ever pulls this out from under mesa and swayfx, it will be
# because a version comparison beat the priority, and it will not be obvious.
[[ "$(rpm -q --queryformat '%{VENDOR}' wlroots)" == "Fedora Project" ]]

# noctalia-greeter-session runs the compositor under `dbus-run-session` when it
# is available and silently without it when it is not. Without a bus there is no
# logind resume handling, no AccountsService avatars and no working power
# buttons -- a degraded greeter that still starts, which is the worst kind of
# missing dependency. dbus is a hard Requires of the package, but the binary
# that matters lives in dbus-daemon.
test -x /usr/bin/dbus-run-session

# tuigreet is KEPT, unbound, as the only fallback -- see the header and
# /etc/greetd/config.toml. gtkgreet is gone: it needed a compositor of its own to
# host it, which was the layer this change deletes.
rpm -q tuigreet
! rpm -q gtkgreet

# The SELinux alias, which is the one item here whose absence is silent.
grep -q '^/var/lib/noctalia-greeter /var/lib/greetd$' \
    /etc/selinux/targeted/contexts/files/file_contexts.subs
# And that the alias actually resolves to greetd's type. matchpathcon reads the
# file_contexts on disk, so this works in the build container even though no
# policy is loaded in it. Into a variable rather than piped to grep -q, same
# rule as the ldd calls above.
greeter_state_context="$(matchpathcon /var/lib/noctalia-greeter)"
[[ "${greeter_state_context}" == *xdm_var_lib_t* ]]

# NOTE ON WHAT IS *NOT* ASSERTED HERE, because it cannot be.
#
# The checks above cover greeter.toml's SYNTAX and the values that matter, plus
# the session list behaviourally. What they cannot cover is whether the greeter
# AGREES that those are its keys. `noctalia-greeter --help` offers only
# `sessions` and `outputs`, there is no validate-only mode, and NEITHER
# subcommand reads greeter.toml at all -- tested: `sessions` prints the same list
# with the config deliberately corrupted. A misspelled key is therefore ignored
# in silence and looks exactly like a key that had no effect.
#
# The old greeter did better here: `sway -C -c /etc/greetd/sway-greeter.conf`
# parsed the real file without touching a device. That went with it. Everything
# that would read this config for real wants a Wayland display, and the
# compositor under it wants DRM and a logind seat -- the same wall 15-swayfx.sh
# documents for `sway -C`, one step further along.
#
# So the semantic gap is closed at runtime instead, and that is the reason
# greetd-fakegreet is installed above:
#
#   just greeter-preview   runs THIS greeter and THIS config nested inside a
#                          live session (WLR_BACKENDS=wayland), against fakegreet
#                          instead of greetd. It calls the compositor directly
#                          rather than through the wrapper, because
#                          noctalia-greeter-session unsets WAYLAND_DISPLAY and a
#                          nested backend then has nothing to connect to -- the
#                          recipe's comment has the detail. Validates the palette
#                          and the session list; exercises no DRM and no renderer
#                          selection, so it does not tell you the login screen
#                          will come up on this GPU.
#   ./verify.sh            checks the state directory, its SELinux label, and
#                          that the greeter enumerates a session, after boot.
#
# Do not add a build-time check here that only appears to work.

echo "greeter: $(rpm -q noctalia-greeter), fallback: $(rpm -q tuigreet)"
