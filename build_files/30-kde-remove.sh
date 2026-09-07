#!/usr/bin/bash
# Remove the Plasma session and the KDE applications, keeping the Qt6/KF6
# libraries so btrfs-assistant, bazzite-updater, pinentry-qt and KDE-flatpak
# theming keep working.
#
# Explicit leaf packages only. Globs (plasma-*, kde-*) would take
# plasma-foreground-booster-dmemcg and kde-settings with them, and comps
# `group remove` is not tracked on an atomic image at all.
set -euxo pipefail

REMOVE=(
    # --- Plasma session core -------------------------------------------------
    plasma-workspace plasma-workspace-common plasma-workspace-libs
    plasma-workspace-wallpapers
    plasma-desktop plasma-desktop-doc
    plasma-lookandfeel-fedora plasma-setup plasma-milou
    kwin kwin-common kwin-libs
    powerdevil aurorae
    plasma-integration plasma-integration-qt5

    # --- Login manager (greetd is already the DM by this point) --------------
    plasma-login-manager kcm-plasmalogin kde-settings-plasmalogin

    # --- Applets and services replaced by the Sway stack --------------------
    plasma-nm plasma-nm-openconnect plasma-nm-openvpn plasma-nm-vpnc
    plasma-pa
    plasma-systemmonitor plasma-systemsettings
    plasma-print-manager plasma-print-manager-libs
    plasma-disks plasma-thunderbolt plasma-vault
    plasma-browser-integration plasma-keyboard
    plasma-foreground-booster-dmemcg
    bluedevil flatpak-kcm
    xdg-desktop-portal-kde
    kde-gtk-config kde-cli-tools kinfocenter kmenuedit

    # --- Bazzite's KDE-specific extras --------------------------------------
    steamdeck-kde-presets-desktop krunner-yafti krunner-bazaar

    # --- KDE applications ----------------------------------------------------
    dolphin dolphin-libs dolphin-plugins
    konsole konsole-part
    kate kate-libs kate-plugins kate-krunner-plugin
    ark ark-libs
    filelight kfind khelpcenter kwrite spectacle
    kwalletmanager5
    krdc krdc-libs krfb krfb-libs
    kcm-fcitx5
)

# Only pass packages that are actually installed, so the transaction is
# deterministic and a package disappearing upstream is not a build failure.
INSTALLED=()
for pkg in "${REMOVE[@]}"; do
    if rpm -q "${pkg}" >/dev/null 2>&1; then
        INSTALLED+=("${pkg}")
    else
        echo "skip (not installed): ${pkg}"
    fi
done

# --no-autoremove: do not let dnf decide what else to drag out. The Qt6/KF6
# stack is intentionally orphaned but kept.
dnf5 remove -y --no-autoremove "${INSTALLED[@]}"

# fcitx5 loses its KDE config UI with kcm-fcitx5; give it the GTK one back.
if rpm -q fcitx5 >/dev/null 2>&1; then
    dnf5 install -y fcitx5-configtool
fi

# --- Guard rails: things that must survive this transaction ------------------
# Xwayland is versionlocked to Bazzite's Valve-patched build and is required by
# both sway-config-fedora and (until now) plasma-workspace.
rpm -q xorg-x11-server-Xwayland
rpm -q xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-wlr
# --whatprovides sway, not `rpm -q sway`: build_files/15-swayfx.sh swapped the
# sway package out for swayfx, which Provides: sway = 1.11 and Conflicts: sway.
# A literal `rpm -q sway` fails here and takes the whole :sway build with it.
rpm -q --whatprovides sway
rpm -q sway-config-fedora sway-systemd greetd tuigreet
# The locker and its idle daemon, plus the swaylock/swayidle pair kept as the
# fallback. Removing Plasma must not have reached any of them.
rpm -q hyprlock hypridle swaylock swayidle
# The only polkit agent this image can actually run: polkit-kde is a Plasma
# component and lxqt-policykit is ABI-broken against Qt 6.11 on F44.
rpm -q mate-polkit
test -L /usr/lib/systemd/user/sway-session.target.wants/polkit-mate-authentication-agent-1.service
rpm -q btrfs-assistant bazzite-updater
# breeze-icon-theme / breeze-cursor-theme are deliberately NO LONGER asserted.
# They were only kept alive because gtk-{3,4}.0/settings.ini named breeze-dark
# and breeze_cursors -- a load-bearing dependency on Plasma's icon set, on a
# machine whose entire point is that Plasma is gone. Those settings now name
# Papirus-Dark and Adwaita (the latter already present as a GTK dependency), so
# the packages are free to be orphaned like the rest of the Qt/KF6 stack.
rpm -q steam

# Plasma must be gone as a session.
test ! -e /usr/share/wayland-sessions/plasma.desktop
test -e /usr/share/wayland-sessions/sway.desktop
