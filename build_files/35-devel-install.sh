#!/usr/bin/bash
# Build-time headers for the Pay Per Paper Tauri debugger (src/debugger/editor).
set -euxo pipefail

CTX="${CTX:-/ctx}"

# The runtime halves all ship in the base image; only the -devel side is
# missing, and the debugger's -sys crates need it to compile. gcc, g++, make and
# pkg-config are already present.
dnf5 install -y \
    dbus-devel \
    gtk3-devel \
    webkit2gtk4.1-devel \
    libsoup3-devel \
    libappindicator-gtk3-devel \
    libX11-devel
