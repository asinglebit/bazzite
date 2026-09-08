#!/usr/bin/bash
# Swap sway for SwayFX. Runs after 10-sway-install.sh and before
# 20-display-manager.sh, which validates the greeter config and must do so with
# the binary that will actually run it.
#
# A genuine drop-in: swayfx is rebased on the same sway 1.11 F44 ships,
# `Provides: sway = 1.11` (satisfying sway-config-fedora, sway-systemd and
# grimshot), `Conflicts: sway` (hence `swap`, not `install`), and installs at
# /usr/bin/sway rather than /usr/bin/swayfx. That last point is what keeps
# start-sway, greetd and swaymsg working untouched.
#
# sway-config-fedora is deliberately NOT disturbed: it owns /etc/sway/config,
# start-sway, layered-include and the wayland-sessions entry, and it
# `Provides: sway-config`, which is what swayfx Requires.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# Written by hand rather than `dnf5 copr enable`, for determinism: the repo id is
# then known (so --enable-repo below cannot silently miss), the plugin's
# $releasever detection is out of the loop, and the file lands enabled=0.
#
# This is the project's SECOND third-party repo, and unlike Terra it is NOT one
# the base image already trusts.
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

# --enable-repo and --exclude are dnf5 GLOBALS, before the subcommand. Scoping
# the repo to this one transaction is what stops the COPR satisfying anything
# else in the image.
#
# swayfx-config-upstream ships its own /etc/sway/config and wayland-sessions
# entry, which would collide with sway-config-fedora's. Only a Suggests, so
# excluded rather than trusted to weak-dep policy.
dnf5 -y --enable-repo='copr:*swayfx*' --exclude=swayfx-config-upstream \
    swap sway swayfx

# Every assertion below is a black screen at the next boot if it regresses.

rpm -q swayfx

# swayfx BuildRequires pkgconfig(scenefx-0.4), not the 0.5 this COPR now ships
# as plain `scenefx`. Assert something providing 0.4 is present rather than
# assuming which package won.
rpm -qa 'scenefx*'

# ldd once into a variable, then bash pattern matching. NOT `ldd | grep -q`:
# grep -q exits at the first match, ldd takes SIGPIPE, and pipefail turns that
# into exit 141 -- a failed build from an assertion that passed.
sway_libs="$(ldd /usr/bin/sway)"
[[ "${sway_libs}" == *libscenefx* ]]

# The drop-in property: the binary must be at sway's path, or start-sway, greetd
# and the session entry all point at nothing.
test -x /usr/bin/sway

# THE STALENESS TRIPWIRE, and the whole point of this line. swayfx 0.5.2 in this
# COPR links libwlroots-0.19, which F44 still ships as a compat package
# alongside 0.20. Nobody has rebuilt swayfx in over a year, so the day Fedora
# retires wlroots0.19 or bumps its soname, this must fail the NIGHTLY BUILD
# rather than ship a desktop that cannot start.
[[ "${sway_libs}" == *libwlroots-0.19.so* ]]

# `Conflicts: sway` must not have taken the config stack with it.
rpm -q sway-config-fedora sway-systemd grimshot
test -f /etc/sway/config
test -f /etc/sway/environment
test -x /usr/bin/start-sway
test -f /usr/share/wayland-sessions/sway.desktop

grep -q '^set \$term ghostty$' /etc/sway/config

# NOT VALIDATED HERE: `sway -C`. It cannot work in a build container, and this
# was tested rather than assumed. /usr/bin/sway carries cap_sys_nice=ep, so
# exec'ing it where the bounding set lacks it is EPERM; `cp` drops xattrs and
# gets past that, but the copy then needs XDG_RUNTIME_DIR and then a logind
# SEAT, which a container has no way to provide.
#
# The decisive part: with no seat, a GOOD config and a deliberately broken one
# both exit 1 with identical libseat errors -- zero discriminating power. It
# would fail every build while proving nothing. Config parsing is verified at
# runtime by verify.sh, where a seat exists and `sway -C` really does return 0
# and 1. DO NOT re-add an exec-based check here.

echo "swayfx installed: $(rpm -q swayfx), providing $(rpm -q --provides swayfx | grep -m1 '^sway ')"
