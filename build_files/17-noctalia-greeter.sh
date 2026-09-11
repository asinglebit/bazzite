#!/usr/bin/bash
# The login screen, which brings its own compositor so it can scale per monitor.
# A text console cannot: its font is a fixed bitmap, so the same text is twice the size
# on one of these screens as the other.
# The cost is that a failure here is a black screen, so tuigreet stays installed as the
# fallback, switched on in /etc/greetd/config.toml.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# The base image already trusts Terra, so this adds no new trust root.
# Its own transaction, because Terra also carries wlroots and mesa and must not satisfy those.
# fakegreet stands in for greetd so the greeter can be run inside a live session; see the end of this file.
dnf5 --enable-repo=terra install -y noctalia-greeter
dnf5 install -y greetd-fakegreet

# A wrapper, because the greeter's compositor inherits none of sway's driver settings
# and there is nowhere else to put them back.
install -Dpm0755 "${CTX}/system_files/usr/libexec/noctalia-greeter-nvidia" \
                 /usr/libexec/noctalia-greeter-nvidia

# Shipped here rather than where the greeter reads it, because /var only gets written
# on a fresh install; tmpfiles.d copies it into place on every boot instead.
install -Dpm0644 "${CTX}/system_files/usr/share/factory/var/lib/noctalia-greeter/greeter.toml" \
                 /usr/share/factory/var/lib/noctalia-greeter/greeter.toml

# The greeter would look for an avatar inside your home directory, which it cannot read,
# so the image ships one somewhere world-readable instead; `just greeter-avatar` points at it.
# SVG rather than PNG, so it scales like everything else on this screen.
install -Dpm0644 "${CTX}/system_files/usr/share/bazzite-sway/greeter-avatar.svg" \
                 /usr/share/bazzite-sway/greeter-avatar.svg

# Without this SELinux line the greeter cannot write its own state directory, and the
# login screen comes up blank. One alias borrows greetd's existing rule, needing no policy module.
# Edited by hand because the proper command writes into /var, which a bootc image does not keep.
SUBS=/etc/selinux/targeted/contexts/files/file_contexts.subs
if ! grep -q '^/var/lib/noctalia-greeter /var/lib/greetd$' "${SUBS}" 2>/dev/null; then
    printf '/var/lib/noctalia-greeter /var/lib/greetd\n' >> "${SUBS}"
fi

rpm -q noctalia-greeter greetd-fakegreet

# Each of these execs the next, and a missing link anywhere is a black screen at boot.
test -x /usr/bin/noctalia-greeter
test -x /usr/bin/noctalia-greeter-compositor
test -x /usr/bin/noctalia-greeter-session
test -x /usr/libexec/noctalia-greeter-nvidia

# Getting these wrong leaves tty1 with no console to fix it from, after five failed starts.
grep -q 'noctalia-greeter-session' /usr/libexec/noctalia-greeter-nvidia
grep -q 'WLR_RENDERER:=gles2'      /usr/libexec/noctalia-greeter-nvidia

# The assets tree is required at runtime; without it the greeter loses its fonts and icons.
test -d /usr/share/noctalia-greeter/assets

# A config that failed to install would not break the build, it would just look wrong.
test -s /usr/share/factory/var/lib/noctalia-greeter/greeter.toml
grep -q '^surface *= *"#1a1a1a"$' /usr/share/factory/var/lib/noctalia-greeter/greeter.toml
fc-list -q 'Inter'

# The greeter has no way to check its own config, so do it here instead of at the password prompt.
python3 - /usr/share/factory/var/lib/noctalia-greeter/greeter.toml <<'TOMLCHECK'
import re, sys, tomllib

with open(sys.argv[1], "rb") as fh:
    cfg = tomllib.load(fh)

palette = cfg["appearance"]["palette"]
# A missing role falls back to a default, which means a colour on a grey screen.
assert len(palette) == 16, f"expected 16 palette roles, got {len(palette)}: {sorted(palette)}"
bad = {k: v for k, v in palette.items() if not re.fullmatch(r"#[0-9a-fA-F]{6}", str(v))}
assert not bad, f"invalid hex in [appearance.palette]: {bad}"

greys = {"#1a1a1a", "#242424", "#2e2e2e", "#5a5a5a", "#9a9a9a", "#d8d8d8", "#ffffff"}
off = {k: v for k, v in palette.items() if v not in greys}
assert not off, f"off-palette colours on the login screen: {off}"

# The two settings that would quietly bring back the stock look.
assert cfg["appearance"]["scheme_selector_position"] == "hidden"
assert cfg["appearance"]["font_family"] == "Inter"

# Scale is worked out per monitor, never written down, which is the whole point of this greeter.
assert "output" not in cfg, "greeter.toml has an [output] block -- scale is derived, not declared"
TOMLCHECK

# The one thing the build can actually run, since listing sessions needs no screen.
# An empty list would be a login screen with nothing to log into.
# Plasma is still installed at this point, so this only checks that Sway is offered.
greeter_sessions="$(noctalia-greeter sessions)"
[[ "${greeter_sessions}" == *Sway* ]]

# The greeter and sway need different wlroots versions and are meant to coexist,
# so the last line catches anything that moves sway onto the greeter's.
greeter_libs="$(ldd /usr/bin/noctalia-greeter-compositor)"
[[ "${greeter_libs}" == *libwlroots-0.20.so* ]]
[[ "${greeter_libs}" == *libEGL*             ]]
[[ "${greeter_libs}" == *libGLESv2*          ]]
sway_libs="$(ldd /usr/bin/sway)"
[[ "${sway_libs}" == *libwlroots-0.19.so* ]]

# Terra ships its own wlroots, and it replacing Fedora's would not be obvious.
[[ "$(rpm -q --queryformat '%{VENDOR}' wlroots)" == "Fedora Project" ]]

# Without this the greeter still starts, just with no avatars and dead power buttons.
test -x /usr/bin/dbus-run-session

# tuigreet stays as the only fallback; gtkgreet needed its own compositor to host it.
rpm -q tuigreet
! rpm -q gtkgreet

# The SELinux alias, whose absence is the one thing here that would fail silently.
grep -q '^/var/lib/noctalia-greeter /var/lib/greetd$' \
    /etc/selinux/targeted/contexts/files/file_contexts.subs
greeter_state_context="$(matchpathcon /var/lib/noctalia-greeter)"
[[ "${greeter_state_context}" == *xdm_var_lib_t* ]]

# What none of this can check is whether the greeter agrees those are its keys: it has no
# validate mode, and a misspelled key is ignored in silence. `just greeter-preview` runs the
# real greeter nested in a live session, and verify.sh checks the rest after boot.
# Do not add a build-time check here that only appears to work.

echo "greeter: $(rpm -q noctalia-greeter), fallback: $(rpm -q tuigreet)"
