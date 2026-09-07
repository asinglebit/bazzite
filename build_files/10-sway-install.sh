#!/usr/bin/bash
# Install the Sway session and the surrounding desktop essentials.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# WEAK DEPS ARE OFF, and this comment used to say the opposite.
#
# /etc/dnf/dnf.conf in the Bazzite base carries `install_weak_deps=False`, so
# nothing here gets a package because something Recommends it. That was measured,
# not read: noctalia Recommends ddcutil, upower, gnome-keyring and wtype, and
# after installing it only wtype was absent -- the other three were already in
# the base image, installed 19 hours earlier by its own build.
#
# So every package this desktop needs has to be in this list by name. The old
# claim that "weak deps stay ON deliberately: that is how sway-config-fedora
# pulls in qt5/qt6-qtwayland, xdg-user-dirs, foot and sway-systemd" was wrong on
# the mechanism and right by accident: those four are present, but from the base
# image and from this list, not from a Recommends.
#
# --- WHY THE SHELL CULL IS TWO DIFFERENT OPERATIONS -------------------------
#
# noctalia replaced nine programs. Only some of them could be UNINSTALLED,
# because sway-config-fedora -- which owns /etc/sway/config, start-sway,
# layered-include and the wayland-sessions entry, and so cannot itself be
# dropped -- hard-*Requires* most of them:
#
#     $ rpm -q --requires sway-config-fedora
#     brightnessctl  grimshot  lxqt-policykit  playerctl  swaybg
#     swayidle  swaylock  waybar  ...
#
# Those are plain Requires, not Recommends. So waybar, swaylock, swayidle,
# swaybg, grimshot (which drags grim and slurp, as does
# xdg-desktop-portal-wlr), brightnessctl, playerctl and lxqt-policykit ARE
# STILL INSTALLED and always will be. They are gone from the list below because
# nothing here asks for them any more, not because that removes them.
#
# What retires them instead is a comment-only file of the same name in
# /etc/sway/config.d/, shipped by 18-noctalia-shell.sh -- see the long note
# there. Do not try to --exclude any of them: excluding a hard dependency makes
# the transaction unresolvable, which is a failed build rather than a smaller
# image.
#
# ROFI IS THE ONE EXCEPTION, and the trap is worth writing down because the
# obvious reading of the dependency list is wrong. sway-config-fedora
# *Recommends* rofi-wayland, and there is no such package in F44 -- the `rofi`
# package Provides that name:
#
#     $ rpm -q --provides rofi | grep wayland
#     rofi-wayland = 2.0.0-2.fc44
#
# With install_weak_deps=False that Recommends is inert, so deleting `rofi` from
# the list below is in fact enough today -- verified absent from the built image.
# The exclude stays anyway, and cheaply: it is the guard for the day that dnf.conf
# changes or this list is built somewhere it has not been read, and excluding by
# name works precisely because nothing else in the repos satisfies that provide.
#
# Genuinely uninstalled by this change: rofi, SwayNotificationCenter, mako,
# wlogout, cliphist, swappy, mate-polkit -- verified with
# `rpm -q --whatrequires` as required by nothing.
# --exclude is a dnf5 GLOBAL option: it has to come before the subcommand.
dnf5 --exclude=sway-config-upstream,rofi install -y \
    sway \
    sway-config-fedora \
    sway-systemd \
    swaybg \
    greetd \
    tuigreet \
    xdg-desktop-portal-wlr \
    xdg-desktop-portal-gtk \
    gnome-keyring \
    gnome-keyring-pam \
    noctalia \
    foot \
    Thunar \
    thunar-archive-plugin \
    xarchiver \
    gvfs-smb \
    gvfs-mtp \
    pavucontrol \
    imv \
    wl-clipboard \
    wtype \
    ddcutil \
    wlr-randr \
    kanshi \
    wlsunset \
    blueman \
    wev \
    adw-gtk3-theme \
    papirus-icon-theme-dark \
    rsms-inter-fonts

# THE SHELL, and what it replaced.
#
# noctalia draws the bar, the notifications and their control centre, the
# launcher, the session menu, the lock screen, the OSD, the clipboard history,
# the screenshots, the wallpaper and the polkit prompt -- one package where there
# were nine, from one TOML config and one palette. It is in Fedora proper, so
# unlike ghostty below and noctalia-greeter in 17-, it needs no repo enabled and
# belongs in the list above rather than a transaction of its own.
#
# What it took over, split by whether the package could actually leave.
#
# UNINSTALLED -- nothing requires these, so they are gone from the image:
#
#   SwayNotificationCenter  -> notifications + control centre
#   mako                    -> was already only swaync's unbound fallback
#   rofi                    -> the launcher, and `noctalia dmenu` for scripts
#   wlogout                 -> `noctalia msg session`
#   cliphist                -> the clipboard panel
#   swappy                  -> nothing. The annotator went with the grim path.
#   mate-polkit             -> NoctaliaPolkitListener, asserted in 18-
#   network-manager-applet  -> noctalia is the NM SecretAgent, asserted in 18-
#   hyprlock / hypridle     -> [lockscreen] and [idle]   (16-hyprlock.sh, deleted)
#
# STILL ON DISK, retired by /etc/sway/config.d/ overrides in 18- because
# sway-config-fedora hard-Requires them:
#
#   waybar                  -> the bar             (dotfiles/noctalia/30-bar.toml)
#   swaylock / swayidle     -> [lockscreen] and [idle]
#   grimshot / grim / slurp -> `noctalia msg screenshot-*`
#   brightnessctl           -> [shell] brightness, over DDC/CI via ddcutil
#   playerctl               -> the MPRIS service behind the media widget
#   lxqt-policykit          -> NoctaliaPolkitListener
#   swaybg                  -> NOT retired. sway spawns it for `output * bg`,
#                              which still paints the wallpaper: see
#                              dotfiles/sway/config.d/20-appearance.conf.
#
# ddcutil and wtype are in the list above BY NAME, and that is the correction
# this change had to make: they are noctalia Recommends, weak deps are off here,
# and both are load-bearing.
#
#   ddcutil is what gives a DESKTOP brightness control at all. The waybar config
#   dropped backlight as "not applicable to a desktop", which was true of an
#   internal panel and never true of these two monitors -- /sys/class/backlight
#   is empty on this machine. It happened to be in the base image already, so
#   the brightness keys would have worked today and broken silently the first
#   time upstream dropped it.
#
#   wtype is the clipboard panel's auto-paste, and it was genuinely missing from
#   the first build that installed noctalia -- which is how the weak-dep claim
#   above came to be checked at all.
#
# 18-noctalia-shell.sh asserts both, next to the shell that needs them.
#
# blueman and pavucontrol STAY. They are applications, not shell: the deep
# pairing dialogue and the routing/profile editor that a bar widget is not
# trying to be. What went is blueman's tray applet, which was already
# suppressed, and nm-applet, whose second job -- answering NetworkManager for
# secrets -- noctalia now does properly. See dotfiles/autostart/.
rpm -q noctalia
test -x /usr/bin/noctalia

# The terminal.
#
# ghostty is not in Fedora at all -- it comes from Terra (Fyra Labs), which the
# base image already ships at /etc/yum.repos.d/terra.repo with enabled=0, and
# whose signing key is already in /etc/pki/rpm-gpg/. Bazzite itself enables
# terra-mesa, so this is a repo the artifact already trusts rather than a new
# trust root.
#
# Deliberately its OWN transaction. --enable-repo is a dnf5 global like
# --exclude, so folding it into the list above would let Terra satisfy any
# package in that list and silently swap Fedora builds for Terra ones.
#
# ghostty-terminfo is a hard Requires, so it comes along on its own. That
# matters more than it looks: ghostty sets TERM=xterm-ghostty, and without the
# terminfo entry every ssh session and every curses app misbehaves in a way
# that looks nothing like a terminal problem.
dnf5 --enable-repo=terra install -y ghostty

rpm -q ghostty ghostty-terminfo
test -x /usr/bin/ghostty
test -f /usr/share/applications/com.mitchellh.ghostty.desktop
test -f /usr/share/terminfo/x/xterm-ghostty

# foot stays installed, just unbound, as a fallback: ghostty is GPU-accelerated
# and this is an NVIDIA box under --unsupported-gpu, and losing the only
# terminal on a tiling WM is a bad way to discover that. It is also a *weak*
# dependency of sway-config-fedora, so dropping it later needs foot added to
# the --exclude above -- deleting the line from the list is not enough.
rpm -q foot

# Hack Nerd Font.
#
# Vendored from the upstream release, because no repo this image trusts carries
# a patched Hack: Fedora ships only cascadia-*-nf-fonts, and the che:nerd-fonts
# COPR that the base image already pulls `nerd-fonts` from builds ONLY that one
# symbols-only package -- there is no nerd-fonts-hack to install.
#
# That base `nerd-fonts` package is a *fallback*: Symbols Nerd Font, wired in by
# /etc/fonts/conf.d/10-nerd-font-symbols.conf, carrying icons and no Latin
# glyphs at all. It is why Nerd glyphs render on a stock image, and it is not a
# substitute for the patched face -- with it alone, text and icons come from two
# files with two sets of metrics.
#
# Pinned by version AND by checksum: this is the one artifact in the build that
# does not come from a GPG-verified repo, so the hash is what makes it
# reproducible. Bump both together.
#
# All three variants are extracted (2.7MB for the lot). Mono forces icons to a
# single cell, plain doubles them, Propo is proportional -- keeping all three
# makes switching a config edit rather than another image build.
NERD_FONTS_VERSION=3.5.1
HACK_SHA256=cdd389472e10e2261520140ff1b382b4f8a226af5fd0b2735b975d31151d9c3c

curl -fsSL -o /tmp/Hack.tar.xz \
    "https://github.com/ryanoasis/nerd-fonts/releases/download/v${NERD_FONTS_VERSION}/Hack.tar.xz"
echo "${HACK_SHA256}  /tmp/Hack.tar.xz" | sha256sum -c -

install -d -m0755 /usr/share/fonts/hack-nerd-fonts
tar -xJf /tmp/Hack.tar.xz -C /usr/share/fonts/hack-nerd-fonts --no-same-owner
chmod 0644 /usr/share/fonts/hack-nerd-fonts/*
rm -f /tmp/Hack.tar.xz
fc-cache -f /usr/share/fonts/hack-nerd-fonts

# Asserted for the same reason as ghostty above: a font that fails to install
# does not break the build, it just silently falls back to Noto at runtime.
test -f /usr/share/fonts/hack-nerd-fonts/HackNerdFontMono-Regular.ttf
# fc-list -q rather than `fc-list | grep -q`: grep -q exits on its first
# match, fc-list takes SIGPIPE, and pipefail turns that into exit 141 --
# a green check that kills the build. -q is fontconfig's own match test.
fc-list -q 'Hack Nerd Font Mono'


# --- GTK theming, fonts and icons --------------------------------------------
#
# Asserted for the same reason as the font above: none of these failing breaks
# the build, they just silently fall back at runtime to something that looks
# almost right.
#
# adw-gtk3 is structural rather than cosmetic here, and it survived the shell
# swap for a reason that got NARROWER, not weaker. It used to be holding a split
# desktop together: swaync was GTK4 + libadwaita while wlogout, swappy, Thunar,
# nm-applet and blueman-manager were GTK3, so without it the shell itself was
# drawn across two GTK eras.
#
# noctalia is neither -- it is a native EGL/GLES2 client and takes its colours
# from dotfiles/noctalia/palettes/, not from GTK at all. So what is left to theme
# is the APPLICATIONS: Thunar, imv, xarchiver, blueman-manager, and pavucontrol,
# which was in that GTK3 list until F44 rebuilt it against GTK4 and is themed
# through adw-gtk3-dark's gtk-4.0/ directory now. Both eras are still present
# among them, so the package earns its place either way -- but a GTK regression
# is now a wrong-looking file manager rather than a wrong-looking desktop.
test -d /usr/share/themes/adw-gtk3-dark
test -d /usr/share/icons/Papirus-Dark
fc-list -q 'Inter'

# --- and the file that actually selects them ---------------------------------
#
# Installing the theme is not choosing it. On Wayland GTK does not read
# gtk-theme-name, gtk-icon-theme-name, gtk-cursor-theme-name or gtk-font-name
# from gtk-3.0/settings.ini at all: it asks the XDG desktop portal, which
# answers out of org.gnome.desktop.interface in dconf, and the portal wins for
# every key it serves. Measured before this override existed, settings.ini
# asked for adw-gtk3-dark / Papirus-Dark / Adwaita / Inter and GTK reported
# Adwaita / breeze-dark / breeze_cursors / Noto Sans -- the Plasma-era values
# kde-gtk-config wrote into dconf, where 30-kde-remove.sh cannot follow.
#
# So the selection belongs in the image, like everything else the desktop has to
# have before a dotfiles repo exists. See the file itself for the rest.
install -Dpm0644 "${CTX}/system_files/usr/share/glib-2.0/schemas/90-bazzite-sway.gschema.override" \
                 /usr/share/glib-2.0/schemas/90-bazzite-sway.gschema.override
glib-compile-schemas /usr/share/glib-2.0/schemas/

# Read the result back rather than trusting the write. glib-compile-schemas
# WARNS about an override naming a schema or key that does not exist and still
# exits 0, so a typo there is not a build failure -- it is a desktop that comes
# up in stock Adwaita with nothing to show why. The memory backend is what makes
# this readable during a build: it returns the compiled default and needs no
# dconf daemon.
while read -r key want; do
    got="$(GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.interface "$key" | tr -d "'")"
    [[ "${got}" == "${want}" ]] || {
        echo "gschema override did not take: ${key} is ${got}, wanted ${want}" >&2
        exit 1
    }
done <<'KEYS'
gtk-theme adw-gtk3-dark
icon-theme Papirus-Dark
cursor-theme Adwaita
color-scheme prefer-dark
font-name Inter 10
monospace-font-name Hack Nerd Font Mono 10
KEYS

# Black folder icons.
#
# papirus-folders is not packaged in any repo this image trusts, so it is
# vendored the same way the Hack font above is: pinned by version AND by
# checksum, fetched at a tag rather than as a generated tarball so the hash is
# stable. This and the font are the only two artifacts in the build that do not
# come from a GPG-verified repo.
#
# It has to run HERE, in the build, and not as a post-install step: the script
# works by replacing folder*.svg with symlinks inside
# /usr/share/icons/Papirus/*/places/, which is inside the ostree deployment and
# read-only at runtime.
PAPIRUS_FOLDERS_VERSION=1.14.0
PAPIRUS_FOLDERS_SHA256=b30a6848a00690302accffc050549218b0b114d3178b28bd3a16891817821b06

curl -fsSL -o /tmp/papirus-folders \
    "https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-folders/v${PAPIRUS_FOLDERS_VERSION}/papirus-folders"
echo "${PAPIRUS_FOLDERS_SHA256}  /tmp/papirus-folders" | sha256sum -c -
chmod +x /tmp/papirus-folders

# -t Papirus, never Papirus-Dark. Fedora puts the colour variants ONLY in the
# main papirus-icon-theme -- 391 files match folder-black there against exactly
# one (a lone 16x16) in papirus-icon-theme-dark, which ships nothing at all
# under 48x48/places/. papirus-folders enumerates the colours it offers from
# folder-<color>-documents.svg in 48x48/places/, so aimed at the dark theme it
# finds no colours whatsoever. papirus-icon-theme-dark hard-Requires the main
# package and inherits its places/ through index.theme, so recolouring the
# parent gives Papirus-Dark black folders for free.
#
# This is the assertion that the variants are actually installed, and it fails
# loudly if that packaging split ever changes.
#
# Captured into a variable and matched with a here-string, NOT piped into
# `grep -q`. That pipe is the exact trap the fc-list note further up this file
# describes, and it is fatal here: grep -q exits on its first match,
# papirus-folders keeps writing into the closed pipe, takes SIGPIPE, and the
# `set -o pipefail` at the top turns a SUCCESSFUL check into exit 141 -- a
# passing assertion that kills the build.
papirus_colours="$(/tmp/papirus-folders -t Papirus -l)"
grep -qw black <<<"${papirus_colours}"

# -o  do NOT write the state file. It would land in /var/lib/papirus-folders,
#     and /var content in a bootc image is only applied on INITIAL provisioning
#     -- exactly the trap system_files/usr/lib/tmpfiles.d/bazzite-sway.conf
#     exists to work around. Nothing reads it at runtime; the symlinks are the
#     state.
# -u  rebuild the icon caches. Papirus ships a prebuilt icon-theme.cache and a
#     stale one shadows the new symlinks. v1.14.0 updates siblings too, which is
#     what reaches Papirus-Dark.
/tmp/papirus-folders -t Papirus -C black -o -u -v

# The mapping is not a plain folder-* rename -- the variant set is ~81 names
# across five sizes, ~400 symlinks, and it covers user-* as well (the script
# uses prefixes "folder-$color" and "user-$color"). Assert one of each: a
# folder, and the Home icon that only the user-* half provides.
# No pipes here either -- bash pattern matching on a captured value, which
# cannot SIGPIPE at all.
test -L /usr/share/icons/Papirus/48x48/places/folder.svg
[[ "$(readlink /usr/share/icons/Papirus/48x48/places/folder.svg)"    == *folder-black* ]]
[[ "$(readlink /usr/share/icons/Papirus/48x48/places/user-home.svg)" == *user-black*   ]]

# Not installed into the image. The symlinks are the product; nothing at runtime
# needs the tool.
rm -f /tmp/papirus-folders

# Re-run on every nightly rebuild, so a papirus-icon-theme update that restores
# the stock blue folder.svg is re-blackened in the same build rather than
# shipping. It does mean `rpm -V papirus-icon-theme` reports those files as
# modified -- that is this, not corruption.


# Point sway's $term at ghostty.
#
# This has to happen at the source, not in a config.d drop-in. sway expands
# `set` variables at parse time, and /etc/sway/config uses $term twice --
# `bindsym $mod+Return exec $term` and rofi's `-terminal '$term'` -- both baked
# long before the layered-include on the final line reads
# ~/.config/sway/config.d/. A late `set $term ghostty` there does nothing at all.
#
# The second of those two uses is now dead text: rofi is gone and $menu with it.
# The first is not, so the rewrite stays exactly as it was.
#
# Asserted because a silent no-op is invisible until you press $mod+Return and
# get foot.
sed -i 's|^set \$term foot$|set $term ghostty|' /etc/sway/config
grep -q '^set \$term ghostty$' /etc/sway/config

# NO $menu REWRITE. There used to be a second sed here giving rofi's combi mode
# window switching (`-combi-modes drun#run#window`), because F44's rofi 2.0.0
# had gained the window mode that /etc/sway/config's own TODO was waiting for.
# rofi is gone, so $menu is dead text: dotfiles/sway/config.d/40-bindings.conf
# rebinds $mod+d over the top of it, which works precisely because a `bindsym`
# in a later drop-in replaces an earlier one -- unlike a `set`, which is why the
# $term rewrite above still has to happen at the source.
#
# noctalia's launcher has the window mode built in, plus calculator, emoji,
# session and wallpaper providers behind prefix characters. See
# dotfiles/noctalia/40-panels.toml.

# THE POLKIT AGENT, and why there is no longer a package or a unit for it here.
#
# noctalia is the agent now. It registers a NoctaliaPolkitListener on
# /org/noctalia/PolkitAuthenticationAgent and links libpolkit-agent-1 --
# 18-noctalia-shell.sh asserts that ldd line rather than trusting it, because it
# is the single thing that made mate-polkit removable and a missing agent is
# silent until something calls pkexec.
#
# What that retired, kept here because both traps cost a boot to find and both
# are still true of anything that tries to be the agent on this image:
#
#  1. lxqt-policykit -- the obvious LXQt-agnostic choice -- is BROKEN on F44.
#     It links libQt6Xdg, which uses Qt *private* API and has not been rebuilt
#     against qt6-qtbase 6.11:
#       symbol lookup error: /usr/lib64/libQt6Xdg.so.4: undefined symbol:
#       _ZN14QObjectPrivateC2E16QtPrivate_6_11_2, version Qt_6.11_PRIVATE_API
#     It installs fine and fails only at exec. It also CANNOT be excluded:
#     sway-config-fedora hard-Requires it. So it stays installed, and what
#     changed is that it is no longer merely inert -- see 3.
#
#  2. Every packaged polkit agent ships an /etc/xdg/autostart entry guarded by
#     OnlyShowIn= (LXQt;, MATE;, KDE;). XDG_CURRENT_DESKTOP is "sway", so the
#     systemd XDG autostart generator skips all of them and the session comes
#     up with NO agent at all -- pkexec, ujust and bazzite-user-setup then hang
#     with no error. That is why mate-polkit was bound to sway-session.target
#     rather than fought through OnlyShowIn, and it is why noctalia is bound the
#     same way in 18-noctalia-shell.sh.
#
#  3. NEW, and the one that is not about /etc/xdg/autostart at all:
#     /usr/share/sway/config.d/95-autostart-policykit-agent.conf execs
#     /usr/libexec/lxqt-policykit-agent from sway's own config, bypassing
#     OnlyShowIn entirely. With mate-polkit bound to the session target that was
#     a second agent racing a working one and losing loudly (see 1). With
#     noctalia it would be a second agent racing a working one, so
#     dotfiles/sway/config.d/95-autostart-policykit-agent.conf shadows that
#     drop-in to nothing. verify.sh checks lxqt-policykit is installed and NOT
#     running, which is the only way that shadow file's absence would show.

# NO NOTIFICATION-DAEMON SYMLINK. swaync used to be started from
# sway-session.target here, and the reason was a race: mako and swaync both ship
# a D-Bus service file declaring Name=org.freedesktop.Notifications, different
# filenames so no RPM conflict, and which one activation picks for a duplicated
# name is not something to build a desktop on. Starting one from the target made
# it own the bus name before any application could ask.
#
# Both are gone and noctalia owns that name, from its own unit, for the same
# reason and by the same mechanism -- 18-noctalia-shell.sh. The race is gone
# rather than won: nothing else in the image claims the name now.

# nvidia-settings' autostart entry runs `nvidia-settings --load-config-only`,
# which is an X11-only operation and exits 1 under a Wayland session. Harmless,
# but it leaves a permanently failed user unit on every login. Hidden=true is
# the XDG-specified way to retire an autostart entry; the systemd
# xdg-autostart-generator honours it and emits no unit at all.
if [[ -f /etc/xdg/autostart/nvidia-settings-load.desktop ]]; then
    cat > /etc/xdg/autostart/nvidia-settings-load.desktop <<'DESKEOF'
[Desktop Entry]
Type=Application
Name=NVIDIA X Server Settings
Exec=/usr/bin/nvidia-settings --load-config-only
# X11-only; this session is Wayland. See bazzite-sway build_files/10-sway-install.sh
Hidden=true
DESKEOF
fi

# sway-systemd is what reaches graphical-session.target. Without it
# xdg-desktop-portal.service refuses to start (it carries
# Requisite=graphical-session.target, RHBZ 2481764), which silently breaks
# Flatpak file dialogs, screen sharing and the Steam overlay.
rpm -q sway-systemd

# sway ships /usr/share/xdg-desktop-portal/sway-portals.conf itself
# (gtk for everything, wlr for ScreenCast/Screenshot, gnome-keyring for Secret),
# so there is no portals config to write here.
test -f /usr/share/xdg-desktop-portal/sway-portals.conf

# NVIDIA. start-sway sources this file, and so would an SDDM sway greeter.
cat >> /etc/sway/environment <<'ENVEOF'

### Bazzite-Sway: NVIDIA (nvidia-open, Ada) ####################################
# sway 1.11 hard-exits when the DRM driver is named "nvidia-drm" — the open
# kernel modules are matched by that check too, so this flag is mandatory.
# -D noscanout disables direct scanout, the standard wlroots-on-NVIDIA fix for
# flicker and black frames.
SWAY_EXTRA_ARGS="$SWAY_EXTRA_ARGS --unsupported-gpu -D noscanout"

# GLES2, not Vulkan, and this is a SwayFX constraint rather than a preference.
# SwayFX implements every effect (blur, corner radius, shadows, dim-inactive) in
# its own fx_renderer, which is GLES2-only -- there is no Vulkan code path. Left
# at vulkan you get a compositor that starts, works, and silently draws none of
# the effects, which is a nasty thing to debug from the config end.
#
# The cost is real and worth stating: vulkan is the renderer wlroots recommends
# on NVIDIA, and this gives it up. That is the price of build_files/15-swayfx.sh.
WLR_RENDERER=gles2

# VA-API through the already-installed libva-nvidia-driver.
LIBVA_DRIVER_NAME=nvidia
NVD_BACKEND=direct

# Electron apps on native Wayland rather than Xwayland.
ELECTRON_OZONE_PLATFORM_HINT=auto

# Deliberately NOT set:
#   GBM_BACKEND=nvidia-drm      obsolete since glvnd picks the backend itself
#   WLR_NO_HARDWARE_CURSORS=1   only needed if the cursor misbehaves on 610.x
################################################################################
ENVEOF
