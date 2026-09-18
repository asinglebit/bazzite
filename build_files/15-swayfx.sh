#!/usr/bin/bash
# Swaps sway for SwayFX, a drop-in at the same path, so everything pointing at it keeps working.
# Fedora's sway config package stays, because swayfx needs it.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# Written out by hand so the repo id is known and the file lands disabled by default.
install -Dpm0644 /dev/stdin /etc/yum.repos.d/_copr_swayfx-swayfx.repo <<'REPOEOF'
[copr:copr.fedorainfracloud.org:swayfx:swayfx]
name=Copr repo for swayfx owned by swayfx
baseurl=https://download.copr.fedorainfracloud.org/results/swayfx/swayfx/fedora-$releasever-$basearch/
type=rpm-md
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/swayfx/swayfx/pubkey.gpg
repo_gpgcheck=0
skip_if_unavailable=False
enabled=0
enabled_metadata=1
REPOEOF

# The repo is enabled for this one command only, so it cannot satisfy anything else in the image.
# swayfx-config-upstream is excluded because its config would collide with Fedora's.
dnf5 -y --enable-repo='copr:*swayfx*' --exclude=swayfx-config-upstream \
    swap sway swayfx

# Every check below is a black screen at the next boot if it stops being true.

rpm -q swayfx

# Just check some scenefx is here, rather than guessing which package name won.
rpm -qa 'scenefx*'

# Run ldd once into a variable, because piping it into `grep -q` fails the build on a passing check.
sway_libs="$(ldd /usr/bin/sway)"
[[ "${sway_libs}" == *libscenefx* ]]

# The binary has to sit at sway's own path, or everything pointing at it breaks.
test -x /usr/bin/sway

# swayfx needs an old wlroots that Fedora will drop one day, and that day must fail the build.
[[ "${sway_libs}" == *libwlroots-0.19.so* ]]

# Removing sway must not have taken the config packages with it.
rpm -q sway-config-fedora sway-systemd grimshot
test -f /etc/sway/config
test -f /etc/sway/environment
test -x /usr/bin/start-sway
test -f /usr/share/wayland-sessions/sway.desktop

grep -q '^set \$term ghostty$' /etc/sway/config

# No config validation here: in a container a good and a broken config fail identically.

echo "swayfx installed: $(rpm -q swayfx), providing $(rpm -q --provides swayfx | grep -m1 '^sway ')"
