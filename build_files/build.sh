#!/usr/bin/bash
# Orchestrator. Runs inside the image build with the repo bind-mounted at /ctx.
set -euxo pipefail

CTX="${CTX:-/ctx}"
export CTX

"${CTX}/build_files/10-sway-install.sh"

# Between 10 and 20: swayfx installs its binary at /usr/bin/sway, and
# 17-noctalia-greeter.sh asserts that binary links libwlroots-0.19 while the
# greeter's own compositor links 0.20. Run earlier, that tripwire would check
# the Fedora sway that is about to be replaced.
"${CTX}/build_files/15-swayfx.sh"

"${CTX}/build_files/17-noctalia-greeter.sh"

# After 17 so this can read the greeter's palette and check the desktop agrees
# with the login screen. Before 20, so nothing below can change what the session
# starts. The PACKAGE is installed in 10; this script owns the unit and the
# assertions.
"${CTX}/build_files/18-noctalia-shell.sh"

# Before 30: greetd has to be the display manager before plasmalogin is removed,
# so the image never contains a display-manager.service symlink pointing at a
# package that is no longer installed.
"${CTX}/build_files/20-display-manager.sh"
"${CTX}/build_files/30-kde-remove.sh"

"${CTX}/build_files/35-devel-install.sh"
"${CTX}/build_files/40-branding.sh"

# After 40, because the patch depends on branding keeping `base-image-name` as
# "kinoite", which decides which side of the repaired `if` runs at login.
"${CTX}/build_files/45-bazzite-user-setup.sh"

"${CTX}/build_files/50-signing.sh"

# The package cache is on a --mount=type=cache, so this only clears metadata
# that would otherwise be baked into the image layers.
dnf5 clean all
rm -rf /var/cache/libdnf5 /var/lib/dnf /var/tmp/* || true

# Runtime-only paths where dnf5 and the selinux-policy scriptlets leave build
# droppings that would otherwise ship.
rm -rf /run/dnf /run/selinux-policy /tmp/* || true
