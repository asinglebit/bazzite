#!/usr/bin/bash
# Orchestrator. Runs inside the image build with the repo bind-mounted at /ctx.
set -euxo pipefail

CTX="${CTX:-/ctx}"
export CTX

# Order matters: greetd has to be the display manager *before* plasmalogin is
# removed, so the image never contains a display-manager.service symlink
# pointing at a package that is no longer installed.
"${CTX}/build_files/10-sway-install.sh"

# SwayFX has to land between the sway install and the display manager. It
# installs its binary at /usr/bin/sway (it Provides: sway, Conflicts: sway), and
# 17-noctalia-greeter.sh asserts that binary still links libwlroots-0.19 while
# the greeter's own compositor links 0.20 -- run before this, that tripwire would
# be checking the Fedora sway that is about to be replaced.
"${CTX}/build_files/15-swayfx.sh"

# The locker. After 15 because hyprlock and swayfx share the GLES2/EGL path that
# 15 switches the image onto, and before 20 for no ordering reason beyond
# keeping the numbering honest.
"${CTX}/build_files/16-hyprlock.sh"

# The greeter: noctalia-greeter, which ships its own wlroots 0.20 compositor.
# After 15 for the soname tripwire described above, and before 20, which is what
# points greetd at the wrapper this installs.
"${CTX}/build_files/17-noctalia-greeter.sh"

"${CTX}/build_files/20-display-manager.sh"

# Plasma always goes. There is no second variant of this image: greetd runs
# noctalia-greeter, the session list is whatever ships a wayland-sessions entry,
# and the way back from a broken session is a rollback rather than a login
# prompt that offers two desktops.
"${CTX}/build_files/30-kde-remove.sh"

"${CTX}/build_files/35-devel-install.sh"
"${CTX}/build_files/40-branding.sh"

# After 40, because the patch's reasoning depends on what branding does: that
# file keeps `base-image-name` as "kinoite", which decides which side of the
# repaired `if` runs at login. Before 50 for no reason beyond signing being last.
"${CTX}/build_files/45-bazzite-user-setup.sh"

"${CTX}/build_files/50-signing.sh"

# The package cache lives on a --mount=type=cache, so this only clears metadata
# that would otherwise be baked into the image layers.
dnf5 clean all
rm -rf /var/cache/libdnf5 /var/lib/dnf /var/tmp/* || true

# /run and /tmp are runtime-only; dnf5 and the selinux-policy scriptlets leave
# build droppings there that would otherwise ship in the image.
rm -rf /run/dnf /run/selinux-policy /tmp/* || true
