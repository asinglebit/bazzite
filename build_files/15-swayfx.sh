#!/usr/bin/bash
# Swap sway for SwayFX -- sway with corner radius, blur, shadows and
# dim-inactive. Runs AFTER 10-sway-install.sh (which installs sway and seds
# /etc/sway/config) and BEFORE 20-display-manager.sh (which validates the
# greeter config with the sway binary, and must therefore validate it with the
# binary that will actually run it).
#
# The swap is far less invasive than it looks, because swayfx is a genuine
# drop-in and says so in its spec:
#
#   %global sway_base_version 1.11     -- rebased on the same sway F44 ships
#   Provides:  sway = 1.11             -- satisfies sway-config-fedora's
#                                         `Requires: sway >= 1.8`, sway-systemd
#                                         and grimshot
#   Conflicts: sway                    -- hence `swap` rather than `install`
#   %{_bindir}/sway                    -- NOT /usr/bin/swayfx
#
# That last line is what keeps everything else working untouched: start-sway
# hardcodes _SWAY_COMMAND="/usr/bin/sway", greetd runs `start-sway`, and
# swaymsg/swaybar/swaynag come from this package too.
#
# sway-config-fedora is deliberately NOT disturbed. It owns /etc/sway/config,
# /etc/sway/environment, start-sway, layered-include, volume-helper, all of
# /usr/share/sway/config.d/ and /usr/share/wayland-sessions/sway.desktop -- and
# it `Provides: sway-config`, which is exactly what swayfx `Requires`. So the
# whole layered-config machinery this project leans on survives the swap.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# The repo is written out by hand rather than via `dnf5 copr enable`, for the
# same reason the ghostty install is its own transaction: determinism. Writing
# it means the repo *id* is known (so --enable-repo below cannot silently miss),
# the plugin's $releasever/$basearch detection is not in the loop, and the file
# lands enabled=0 -- the same shape terra.repo already ships in this image.
#
# This is the project's SECOND third-party repo, and unlike Terra it is not one
# the base image already trusts. See the README.
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

# --enable-repo and --exclude are both dnf5 GLOBALS, so they come before the
# subcommand. Scoping the repo to this one transaction is what stops the COPR
# satisfying anything else in the image -- the same trap the ghostty install
# documents.
#
# swayfx-config-upstream is excluded explicitly. It ships its own
# /etc/sway/config and /usr/share/wayland-sessions/sway.desktop, which would
# collide with sway-config-fedora's. It is only a `Suggests:` so dnf5 would not
# pull it anyway; excluded for the same reason 10-sway-install.sh excludes
# sway-config-upstream rather than trusting weak-dep policy.
dnf5 -y --enable-repo='copr:*swayfx*' --exclude=swayfx-config-upstream \
    swap sway swayfx

# --- Guard rails -------------------------------------------------------------
# Every one of these is a black screen at the next boot if it regresses, which
# is why they are assertions and not comments.

rpm -q swayfx

# swayfx BuildRequires pkgconfig(scenefx-0.4), NOT the 0.5 that this COPR now
# ships as plain `scenefx`. The soname dep should have resolved to the
# scenefx-0.4.1 compat package; assert that something providing 0.4 is present
# rather than assuming which package won.
rpm -qa 'scenefx*'

# ldd once, into a variable, then bash pattern matching. NOT `ldd | grep -q`:
# ldd emits some sixty lines, grep -q exits at the first match, and ldd then
# takes SIGPIPE -- which pipefail turns into exit 141 and a failed build, from
# an assertion that actually passed.
sway_libs="$(ldd /usr/bin/sway)"
[[ "${sway_libs}" == *libscenefx* ]]

# The drop-in property: the binary has to be at sway's path, or start-sway,
# greetd and the session desktop entry all point at nothing.
test -x /usr/bin/sway

# The staleness tripwire. The RPM in this COPR's fedora-44 chroot is
# swayfx-0.5.2-1.fc43, built 2025-07-04 -- it links libwlroots-0.19.so, which
# F44 still ships as a compat package alongside wlroots-0.20. Nobody has rebuilt
# swayfx in over a year, so the day Fedora retires wlroots0.19 or bumps its
# soname this must fail the NIGHTLY BUILD rather than ship a desktop that cannot
# start. That is the whole point of this line.
[[ "${sway_libs}" == *libwlroots-0.19.so* ]]

# Conflicts: sway must not have taken the config stack with it.
rpm -q sway-config-fedora sway-systemd grimshot
test -f /etc/sway/config
test -f /etc/sway/environment
test -x /usr/bin/start-sway
test -f /usr/share/wayland-sessions/sway.desktop

# 10-sway-install.sh's sed must still be in place -- the swap replaced the
# package that owns the binary, not the config, but assert it rather than
# reason about it.
#
# There were two seds here. The second gave rofi's combi mode window switching
# and is gone with rofi: noctalia's launcher has that built in, and $menu is
# dead text that dotfiles/sway/config.d/40-bindings.conf rebinds $mod+d over.
# Nothing asserts $menu any more BECAUSE nothing depends on its value -- see the
# note where that sed used to be in 10-sway-install.sh.
grep -q '^set \$term ghostty$' /etc/sway/config

# NOT VALIDATED HERE: `sway -C`.
#
# It cannot work in a build container, and this was tested rather than assumed.
# Two walls, in order:
#   1. /usr/bin/sway carries `cap_sys_nice=ep`. Exec'ing a binary with an
#      effective file capability where the bounding set lacks it is EPERM
#      (exit 126). `cp` drops xattrs, so a copy gets past this.
#   2. The copy then aborts on "XDG_RUNTIME_DIR is not set". Set that, and it
#      goes on to open a SEAT through libseat/logind -- "Could not get primary
#      session for user" -- and exits 1. There is no logind session in a
#      container, so there is no way through.
#
# The decisive part: with a seat unavailable, a GOOD config and a deliberately
# broken one both exit 1 with identical libseat errors. The check has no
# discriminating power here at all -- it would fail every build while proving
# nothing. Fedora's stock sway behaves the same way, so this was never
# achievable, only untried.
#
# Config parsing is therefore verified at RUNTIME, by verify.sh, where logind
# does provide a seat and `sway -C` returns 0 on a good config and 1 on a bad
# one (measured). Do not re-add an exec-based check here.

echo "swayfx installed: $(rpm -q swayfx), providing $(rpm -q --provides swayfx | grep -m1 '^sway ')"
