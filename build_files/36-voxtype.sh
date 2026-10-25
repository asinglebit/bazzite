#!/usr/bin/bash
# Installs voxtype, which types what you say into the focused window.
# Its settings and binding live in dotfiles/, and its unit stays inert until they are linked.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# Downloaded because no trusted repo carries it, so it is pinned by checksum.
# Only the Vulkan build, because the RPM carries every variant and switches them by rewriting /usr.
VOXTYPE_VERSION=1.1.1
VOXTYPE_SHA256=102a7caa22facc5c257c526ae4a9e63c04c027297fec4ca370209a1f94ae9863

curl -fsSL -o /tmp/voxtype \
    "https://github.com/peteonrails/voxtype/releases/download/v${VOXTYPE_VERSION}/voxtype-${VOXTYPE_VERSION}-linux-x86_64-vulkan"
echo "${VOXTYPE_SHA256}  /tmp/voxtype" | sha256sum -c -
install -Dpm0755 /tmp/voxtype /usr/bin/voxtype
rm -f /tmp/voxtype

install -Dpm0644 "${CTX}/system_files/usr/lib/systemd/user/voxtype.service" \
                 /usr/lib/systemd/user/voxtype.service

# Shipped directly, because the enable command writes to /etc and presets miss existing users.
install -d /usr/lib/systemd/user/sway-session.target.wants
ln -sfn ../voxtype.service \
    /usr/lib/systemd/user/sway-session.target.wants/voxtype.service

test -L /usr/lib/systemd/user/sway-session.target.wants/voxtype.service

# Without this condition voxtype starts on its defaults, which read the keyboard and exit every five seconds.
grep -q '^ConditionPathExists=%E/voxtype/config.toml$' /usr/lib/systemd/user/voxtype.service

# A checksum proves the download, not that it runs on this glibc.
[[ "$(/usr/bin/voxtype --version)" == "voxtype ${VOXTYPE_VERSION}" ]]

# Run ldd once into a variable, because piping it into `grep -q` fails the build on a passing check.
voxtype_libs="$(ldd /usr/bin/voxtype)"
[[ "${voxtype_libs}" != *"not found"* ]]
# Without libvulkan this is a CPU build, and every sentence takes seconds instead of a fraction of one.
[[ "${voxtype_libs}" == *libvulkan.so.1* ]]

# It types with wtype, and records through ALSA, which reaches the microphone only via PipeWire's plugin.
rpm -q wtype pipewire-alsa

echo "dictation: $(/usr/bin/voxtype --version)"
