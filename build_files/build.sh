#!/usr/bin/bash
# Runs all the build steps in order, inside the image build.
set -euxo pipefail

CTX="${CTX:-/ctx}"
export CTX

"${CTX}/build_files/10-sway-install.sh"

# Must come before 17, whose check would otherwise inspect the Fedora sway this replaces.
"${CTX}/build_files/15-swayfx.sh"

"${CTX}/build_files/17-noctalia-greeter.sh"

# After 17 so it can compare palettes with the login screen, and before 20 which picks the session.
"${CTX}/build_files/18-noctalia-shell.sh"

# Before 30, so the image never points display-manager.service at a package that is gone.
"${CTX}/build_files/20-display-manager.sh"
"${CTX}/build_files/30-kde-remove.sh"

"${CTX}/build_files/35-devel-install.sh"
"${CTX}/build_files/40-branding.sh"

# After 40, because it depends on branding leaving base-image-name as "kinoite".
"${CTX}/build_files/45-bazzite-user-setup.sh"

"${CTX}/build_files/50-signing.sh"

# Clears dnf metadata that would otherwise be baked into the image.
dnf5 clean all
rm -rf /var/cache/libdnf5 /var/lib/dnf /var/tmp/* || true

# Build droppings in runtime-only paths, which should not ship.
rm -rf /run/dnf /run/selinux-policy /tmp/* || true
