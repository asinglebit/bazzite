#!/usr/bin/bash
# Headers needed to compile the Pay Per Paper Tauri debugger.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# The base image already ships the runtime halves and the compilers; only these headers are missing.
dnf5 install -y \
    dbus-devel \
    gtk3-devel \
    webkit2gtk4.1-devel \
    libsoup3-devel \
    libappindicator-gtk3-devel \
    libX11-devel
