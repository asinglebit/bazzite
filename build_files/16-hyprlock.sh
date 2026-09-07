#!/usr/bin/bash
# The lock screen: hyprlock, driven by hypridle.
#
# WHY NOT SWAYLOCK. swaylock cannot blur anything. Once the bar, the launcher
# and the notification centre are frosted (dotfiles/sway/config.d/25-effects.conf),
# the lock screen is the one surface left that visibly cannot match.
#
# WHY HYPRLOCK WORKS HERE AT ALL. It is a Hyprland project, and the usual advice
# is that it needs Hyprland. Its CMakeLists says otherwise -- the only protocols
# it binds are ext-session-lock-v1, wlr-screencopy-unstable-v1, linux-dmabuf-v1,
# fractional-scale-v1, viewporter, cursor-shape-v1 and tablet-v2. No hyprland-*
# protocol, no IPC. sway 1.11 provides every one of them
# (wlr_session_lock_manager_v1_create is in the sway binary; the rest come from
# wlroots). It needs EGL/GBM/OpenGL, which is the GLES2 path 15-swayfx.sh has
# already moved this image onto.
#
# WHY HYPRIDLE REPLACES SWAYIDLE. hyprlock has no daemonize flag -- its args are
# -c/--config, -g/--grace, --immediate-render, --no-fade-in, --display, -q, -v.
# Fedora's 90-swayidle.conf runs `swayidle -w`, and -w is documented as "causes
# swayidle to block until the command finishes". `swaylock -f` forks once the
# screen is locked, so "command exited" means "locked"; hyprlock does not exit
# until you authenticate. Dropped into that file naively, swayidle blocks for the
# entire duration of the lock and the 360s display-off timeout and its resume
# handler never fire -- the monitors stay on all night. All four of that file's
# hooks are swaylock-specific anyway (swaylock -f, pgrep -x swaylock,
# pkill -SIGUSR1 swaylock), so it is retired wholesale by a blank same-name
# override in dotfiles/sway/config.d/.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# Written by hand and shipped disabled, exactly as 15-swayfx.sh does and for the
# same reasons. This is the project's THIRD third-party repo, and it puts a
# non-Fedora binary between you and your own unlocked session -- worth weighing
# on its own terms, not just counted. (The login screen itself now comes from
# Terra; see 17-noctalia-greeter.sh, which weighs that separately.)
#
# WHY THIS COPR AND NOT solopasha/hyprland, which is the well-known one:
# solopasha builds for fedora-rawhide ONLY. Its chroot list has no F44 entry at
# all, so its baseurl 404s here. Nor can hyprlock be built from source against
# Fedora's own libraries: 0.9.x needs hyprutils >= 0.8.0 and
# hyprwayland-scanner >= 0.4.4, and F44 ships 0.7.1 and 0.4.2.
#
# Of the F44 COPRs that do carry a working build, this one was chosen because it
# is the narrowest: 43 packages, and it does NOT ship the hyprland compositor.
# A disabled repo that cannot satisfy "a compositor" is a smaller footgun to
# leave lying in /etc/yum.repos.d next to a machine running swayfx.
install -Dpm0644 /dev/stdin /etc/yum.repos.d/_copr_scottames-hypr.repo <<'REPOEOF'
[copr:copr.fedorainfracloud.org:scottames:hypr]
name=Copr repo for hypr owned by scottames
baseurl=https://download.copr.fedorainfracloud.org/results/scottames/hypr/fedora-$releasever-$basearch/
type=rpm-md
gpgcheck=1
gpgkey=https://download.copr.fedorainfracloud.org/results/scottames/hypr/pubkey.gpg
repo_gpgcheck=0
skip_if_unavailable=False
enabled=0
enabled_metadata=1
REPOEOF

# Its own transaction, separate from 15-swayfx.sh: different repo, different
# concern, and --enable-repo is a dnf5 global -- one combined call would let
# either COPR satisfy the other's dependencies.
#
# This pulls in newer hyprutils and hyprgraphics than Fedora carries -- hyprlock
# 0.9.6 links libhyprutils.so.13 and libhyprgraphics.so.4, against Fedora's
# 0.7.1 and 0.1.5 -- because hyprlock needs them. That is safe rather than
# merely tolerable: none of those packages is installed on the stock image and
# nothing in it requires them (`rpm -q --whatrequires` reports "no package
# requires" for hyprlang, hyprutils, hyprgraphics and hyprcursor alike). Fedora
# ships them for consumers this image does not have. The soname assertions below
# are what keep that true if a future base image starts using them.
dnf5 -y --enable-repo='copr:*scottames*' install hyprlock hypridle

# --- Guard rails -------------------------------------------------------------
rpm -q hyprlock hypridle

# The fallback pair, kept installed and unbound -- the same call as foot and
# tuigreet. If hyprlock breaks you have no way back into the session, so:
# Ctrl+Alt+F2, delete the blank ~/.config/sway/config.d/90-swayidle.conf, and
# Fedora's swayidle+swaylock drop-in loads again on the next login.
rpm -q swaylock swayidle
test -x /usr/bin/swaylock

# hyprlock needs the GL stack, not just wayland. A hyprlock that installs but
# cannot get an EGL context is a black screen you cannot type into.
# ldd once, then bash pattern matching -- see the note in 15-swayfx.sh for why
# this is not `ldd | grep -q`. The soname numbers are the point: hyprlock 0.9.6
# links libhyprutils.so.13 and libhyprgraphics.so.4, which is why Fedora's
# 0.7.1 / 0.1.5 cannot satisfy it and the COPR has to supply them.
hyprlock_libs="$(ldd /usr/bin/hyprlock)"
[[ "${hyprlock_libs}" == *libhyprlang.so.2*     ]]
[[ "${hyprlock_libs}" == *libhyprutils.so.13*   ]]
[[ "${hyprlock_libs}" == *libhyprgraphics.so.4* ]]
[[ "${hyprlock_libs}" == *libEGL* || "${hyprlock_libs}" == *libgbm* ]]
[[ "${hyprlock_libs}" == *libpam* ]]

# hypridle ships systemd/hypridle.service.in upstream, so the RPM installs a
# user unit. Assert it, because the enablement symlink below is pointing at it.
test -f /usr/lib/systemd/user/hypridle.service

# A user unit wanted by sway-session.target, which is the third use of the
# pattern this image already uses for polkit-mate and swaync. NOT an
# exec_always: that re-runs on every `swaymsg reload` and would stack daemons.
# NOT `systemctl --global enable`: that writes into /etc, which bootc then has
# to 3-way merge on every upgrade.
install -d /usr/lib/systemd/user/sway-session.target.wants
ln -sfn ../hypridle.service \
    /usr/lib/systemd/user/sway-session.target.wants/hypridle.service
test -L /usr/lib/systemd/user/sway-session.target.wants/hypridle.service

# --- The floor under both configs --------------------------------------------
#
# NEITHER BINARY HAS BUILT-IN DEFAULTS. With no config in any of
# $XDG_CONFIG_HOME/hypr, $HOME/.config/hypr, $XDG_CONFIG_DIRS/hypr or
# /etc/xdg/hypr, hyprlock exits 1 and so does hypridle -- and the unit above
# ships Restart=on-failure, so hypridle then burns systemd's default start limit
# (5 tries in 10s) and stays dead for the whole session:
#
#     [CRITICAL] ConfigManager: No hypridle.conf file found in: ...
#     hypridle.service: Start request repeated too quickly.
#
# Until these two files existed, a login BEFORE `just link-dotfiles` had run got
# a session that never locked and never blanked, with no error on screen. That
# made the dotfiles repo a hard dependency of the desktop, which is the one
# thing the rest of this image is careful not to be.
#
# /etc/xdg/hypr is the LAST entry in that search order, so dotfiles/hypr/ still
# wins the moment it is linked. These are the floor, not the configuration.
#
# /etc rather than /usr because the search list is compiled into hyprutils and
# contains no /usr path -- there is nowhere else to put them. Same treatment as
# the greetd config in 20-display-manager.sh. The greeter's own config is the
# other way round -- /usr/share/factory, copied into /var by tmpfiles.d -- because
# noctalia-greeter's search order has no /etc path at all; see
# 17-noctalia-greeter.sh.
install -Dpm0644 "${CTX}/system_files/etc/xdg/hypr/hypridle.conf" /etc/xdg/hypr/hypridle.conf
install -Dpm0644 "${CTX}/system_files/etc/xdg/hypr/hyprlock.conf" /etc/xdg/hypr/hyprlock.conf
test -s /etc/xdg/hypr/hypridle.conf
test -s /etc/xdg/hypr/hyprlock.conf

# NOTE ON WHAT IS *NOT* ASSERTED HERE, because it cannot be.
#
# The two `test -s` lines above assert that the fallbacks EXIST. They say
# nothing about whether they PARSE, and that gap is unclosable here. The greeter
# used to be better off -- 20-display-manager.sh could run `sway -C`, which
# parses without touching a device -- and since it became noctalia-greeter the
# most its build script can do is check greeter.toml as TOML, which catches a
# syntax error and a bad colour but not a key the greeter never heard of.
# hypridle
# connects to Wayland in its constructor, before it parses anything, so in this
# container it dies with "Couldn't connect to a wayland compositor" having never
# read the file; and hyprlock has no validate-only mode. hyprlang errors on
# unknown keys, so a single typo in any of the four files -- these two or the
# dotfiles pair that shadows them -- is a dead locker AND a dead DPMS timer,
# discovered at the first idle timeout.
#
# The only guards are runtime: verify.sh checks `systemctl --user is-active
# hypridle` and that both fallbacks are on disk. Do not add a build-time check
# here that only appears to work.
#
# A hyprlock config CAN be parse-checked outside the build, by running it
# against a throwaway headless nested sway -- `WLR_BACKENDS=headless sway -c`
# with an `exec timeout 6 hyprlock -c <candidate>`; it reaches "Locking session"
# and "PAMPROMPT" on a good file and exits 1 on a bad one, without touching the
# real session. That needs a compositor, so it belongs beside verify.sh and not
# in this script. The greeter's equivalent is `just greeter-preview`, which runs
# it nested against greetd's fakegreet for the same reason.

echo "locker: $(rpm -q hyprlock), idle: $(rpm -q hypridle)"
