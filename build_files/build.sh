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
# installs its binary at /usr/bin/sway (it Provides: sway, Conflicts: sway), so
# 20-display-manager.sh's `sway -C -c /etc/greetd/sway-greeter.conf` assertion
# validates the greeter config with the binary that will actually run it, rather
# than with the Fedora sway that is about to be replaced.
"${CTX}/build_files/15-swayfx.sh"

# The locker. After 15 because hyprlock and swayfx share the GLES2/EGL path that
# 15 switches the image onto, and before 20 for no ordering reason beyond
# keeping the numbering honest.
"${CTX}/build_files/16-hyprlock.sh"

"${CTX}/build_files/20-display-manager.sh"

if [[ "${REMOVE_KDE:-0}" == "1" ]]; then
    "${CTX}/build_files/30-kde-remove.sh"
else
    echo "REMOVE_KDE=0 — leaving Plasma installed as a fallback session"
fi

"${CTX}/build_files/35-devel-install.sh"
"${CTX}/build_files/40-branding.sh"
"${CTX}/build_files/50-signing.sh"

# The package cache lives on a --mount=type=cache, so this only clears metadata
# that would otherwise be baked into the image layers.
dnf5 clean all
rm -rf /var/cache/libdnf5 /var/lib/dnf /var/tmp/* || true

# /run and /tmp are runtime-only; dnf5 and the selinux-policy scriptlets leave
# build droppings there that would otherwise ship in the image.
rm -rf /run/dnf /run/selinux-policy /tmp/* || true
