#!/usr/bin/bash
# The login screen, which brings its own compositor so it can scale per monitor.
# A failure here is a black screen, so tuigreet stays installed as the fallback.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# Its own transaction, because Terra also carries wlroots and mesa and must not satisfy those.
# fakegreet stands in for greetd, so the greeter can run inside a live session.
dnf5 --enable-repo=terra install -y noctalia-greeter
dnf5 install -y greetd-fakegreet

# The greeter's compositor inherits none of sway's driver settings, so a wrapper puts them back.
install -Dpm0755 "${CTX}/system_files/usr/libexec/noctalia-greeter-nvidia" \
                 /usr/libexec/noctalia-greeter-nvidia

# /var is only written on a fresh install, so tmpfiles.d copies this into place each boot.
install -Dpm0644 "${CTX}/system_files/usr/share/factory/var/lib/noctalia-greeter/greeter.toml" \
                 /usr/share/factory/var/lib/noctalia-greeter/greeter.toml

# The greeter cannot read your home, so the avatar ships somewhere world-readable.
install -Dpm0644 "${CTX}/system_files/usr/share/bazzite-sway/greeter-avatar.svg" \
                 /usr/share/bazzite-sway/greeter-avatar.svg

# Without this the greeter cannot write its state directory and the login screen comes up blank.
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

# Without the assets tree the greeter loses its fonts and icons.
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

# Plasma is still installed at this point, so this only checks that Sway is offered.
greeter_sessions="$(noctalia-greeter sessions)"
[[ "${greeter_sessions}" == *Sway* ]]

# The greeter and sway need different wlroots versions and are meant to coexist.
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

# The greeter has no validate mode and ignores a misspelled key in silence, so `just greeter-preview` is the real check.

echo "greeter: $(rpm -q noctalia-greeter), fallback: $(rpm -q tuigreet)"
