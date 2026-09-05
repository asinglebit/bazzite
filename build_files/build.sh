#!/usr/bin/bash
# Orchestrator. Runs inside the image build with the repo bind-mounted at /ctx.
set -euxo pipefail

CTX="${CTX:-/ctx}"
export CTX

# Order matters: greetd has to be the display manager *before* plasmalogin is
# removed, so the image never contains a display-manager.service symlink
# pointing at a package that is no longer installed.
"${CTX}/build_files/10-sway-install.sh"
"${CTX}/build_files/20-display-manager.sh"

if [[ "${REMOVE_KDE:-0}" == "1" ]]; then
    "${CTX}/build_files/30-kde-remove.sh"
else
    echo "REMOVE_KDE=0 — leaving Plasma installed as a fallback session"
fi

"${CTX}/build_files/40-branding.sh"

# The package cache lives on a --mount=type=cache, so this only clears metadata
# that would otherwise be baked into the image layers.
dnf5 clean all
rm -rf /var/cache/libdnf5 /var/lib/dnf /var/tmp/* || true

# /run and /tmp are runtime-only; dnf5 and the selinux-policy scriptlets leave
# build droppings there that would otherwise ship in the image.
rm -rf /run/dnf /run/selinux-policy /tmp/* || true
