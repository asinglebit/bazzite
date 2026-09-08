#!/usr/bin/bash
# Remove the Plasma session and the KDE applications, keeping the Qt6/KF6
# libraries that btrfs-assistant, bazzite-updater, pinentry-qt and KDE-flatpak
# theming need.
#
# EXPLICIT LEAF PACKAGES ONLY. Globs (plasma-*, kde-*) would take
# plasma-foreground-booster-dmemcg and kde-settings with them, and comps
# `group remove` is not tracked on an atomic image at all.
set -euxo pipefail

REMOVE=(
    # Plasma session core.
    plasma-workspace plasma-workspace-common plasma-workspace-libs
    plasma-workspace-wallpapers
    plasma-desktop plasma-desktop-doc
    plasma-lookandfeel-fedora plasma-setup plasma-milou
    kwin kwin-common kwin-libs
    powerdevil aurorae
    plasma-integration plasma-integration-qt5

    # Login manager -- greetd is already the DM by this point.
    plasma-login-manager kcm-plasmalogin kde-settings-plasmalogin

    # Applets and services replaced by the Sway stack.
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

    # Bazzite's KDE-specific extras.
    steamdeck-kde-presets-desktop krunner-yafti krunner-bazaar

    # KDE applications.
    dolphin dolphin-libs dolphin-plugins
    konsole konsole-part
    kate kate-libs kate-plugins kate-krunner-plugin
    ark ark-libs
    filelight kfind khelpcenter kwrite spectacle
    kwalletmanager5
    krdc krdc-libs krfb krfb-libs
    kcm-fcitx5
)

# Only pass what is installed, so the transaction is deterministic and a package
# disappearing upstream is not a build failure.
INSTALLED=()
for pkg in "${REMOVE[@]}"; do
    if rpm -q "${pkg}" >/dev/null 2>&1; then
        INSTALLED+=("${pkg}")
    else
        echo "skip (not installed): ${pkg}"
    fi
done

# --no-autoremove: the Qt6/KF6 stack is intentionally orphaned but kept.
dnf5 remove -y --no-autoremove "${INSTALLED[@]}"

# fcitx5 loses its KDE config UI with kcm-fcitx5; give it the GTK one back.
if rpm -q fcitx5 >/dev/null 2>&1; then
    dnf5 install -y fcitx5-configtool
fi

# Guard rails. A regression here has to fail the build.
#
# Xwayland is versionlocked to Bazzite's Valve-patched build and was required by
# plasma-workspace as well as sway-config-fedora.
rpm -q xorg-x11-server-Xwayland
rpm -q xdg-desktop-portal xdg-desktop-portal-gtk xdg-desktop-portal-wlr
# --whatprovides, NOT `rpm -q sway`: 15-swayfx.sh swapped the package for
# swayfx, which Provides sway and Conflicts sway. A literal `rpm -q sway` fails
# here and takes the whole build with it.
rpm -q --whatprovides sway
rpm -q sway-config-fedora sway-systemd greetd tuigreet
# Everything this desktop is except the compositor is behind this one package,
# including the only authentication agent on the machine. A Plasma transaction
# that reached it would leave a session that is a compositor and a wallpaper.
rpm -q noctalia
test -L /usr/lib/systemd/user/sway-session.target.wants/noctalia.service
# A DIFFERENT product on a different version line -- 1.x from Terra against the
# shell's 5.x from Fedora -- sharing nothing but a name and a palette.
rpm -q noctalia-greeter
# Asserted for the OPPOSITE reason to the lines above. These stay installed
# because sway-config-fedora hard-Requires them, and 18-noctalia-shell.sh's
# /etc/sway/config.d/ overrides retire them. If Fedora ever stops requiring one,
# it disappears and its override retires nothing -- silently, because a
# retirement file for a drop-in that no longer exists looks exactly like one
# that is working.
rpm -q waybar swaylock swayidle grimshot lxqt-policykit
# The seven that genuinely went, so deliberate removals stay distinguishable
# from casualties.
! rpm -q SwayNotificationCenter
! rpm -q mako
! rpm -q rofi
! rpm -q wlogout
! rpm -q cliphist
! rpm -q swappy
! rpm -q mate-polkit
# Nothing removes these -- the script that installed them is deleted. Asserted
# because "the script is gone" and "the packages are gone" are different claims.
! rpm -q hyprlock
! rpm -q hypridle
test ! -f /etc/yum.repos.d/_copr_scottames-hypr.repo
rpm -q btrfs-assistant bazzite-updater
rpm -q steam

# Plasma must be gone as a session.
test ! -e /usr/share/wayland-sessions/plasma.desktop
test -e /usr/share/wayland-sessions/sway.desktop
