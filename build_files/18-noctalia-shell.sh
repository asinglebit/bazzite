#!/usr/bin/bash
# Wires the noctalia shell to the sway session; the package itself is installed in step 10.
# There is no fallback shell, so going back means both a bootc rollback and a git checkout.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# Started by systemd rather than sway's `exec`, so it restarts when it dies and has somewhere to log.
install -Dpm0644 "${CTX}/system_files/usr/lib/systemd/user/noctalia.service" \
                 /usr/lib/systemd/user/noctalia.service

# The symlink is shipped directly, because the usual enable command writes to /etc and
# presets only apply to users created afterwards.
install -d /usr/lib/systemd/user/sway-session.target.wants
ln -sfn ../noctalia.service \
    /usr/lib/systemd/user/sway-session.target.wants/noctalia.service

test -f /usr/lib/systemd/user/noctalia.service
test -L /usr/lib/systemd/user/sway-session.target.wants/noctalia.service
# The bare binary, not --daemon; the unit explains why.
grep -q '^ExecStart=/usr/bin/noctalia$' /usr/lib/systemd/user/noctalia.service

# Retires the Fedora drop-ins that start programs this image cannot uninstall.
# They go in /etc rather than dotfiles/ because only /etc exists at first login,
# and deleting one is the supported way back to Fedora's bar or locker.
install -d /etc/sway/config.d
for f in 90-bar.conf 90-swayidle.conf 95-autostart-policykit-agent.conf \
         60-bindings-screenshot.conf 60-bindings-volume.conf \
         60-bindings-brightness.conf 60-bindings-media.conf; do
    install -Dpm0644 "${CTX}/system_files/etc/sway/config.d/${f}" \
                     "/etc/sway/config.d/${f}"

    # Both halves, because if the Fedora file is renamed this one retires nothing and says nothing.
    test -f "/usr/share/sway/config.d/${f}"
    test -f "/etc/sway/config.d/${f}"

    # Comment-only by design, since anything else in them would actually run.
    ! grep -qvE '^[[:space:]]*(#|$)' "/etc/sway/config.d/${f}"
done

rpm -q noctalia
test -x /usr/bin/noctalia
test -d /usr/share/noctalia/assets
test -d /usr/share/noctalia/assets/templates
test -d /usr/share/noctalia/assets/translations

# The shell and greeter are unrelated packages that could one day claim the same file,
# which would break the login screen, so check they still share none.
noctalia_files="$(rpm -ql noctalia   | grep -v '^/usr/lib/\.build-id' | sort)"
greeter_files="$(rpm -ql noctalia-greeter | grep -v '^/usr/lib/\.build-id' | sort)"
[[ -z "$(comm -12 <(printf '%s\n' "${noctalia_files}") \
                  <(printf '%s\n' "${greeter_files}"))" ]]

# Each of these is a package this image removed because noctalia does the same job,
# and if one stops being true the desktop still boots and then quietly cannot do it:
# no password prompt, no wifi password dialog, no bluetooth pairing.
grep -aq 'libpolkit-agent-1.so.0'                     /usr/bin/noctalia
grep -aq '/org/noctalia/PolkitAuthenticationAgent'    /usr/bin/noctalia
grep -aq 'org.freedesktop.NetworkManager.SecretAgent' /usr/bin/noctalia
grep -aq 'org.bluez.Agent1'                           /usr/bin/noctalia
grep -aq 'org.freedesktop.Notifications'              /usr/bin/noctalia

# The tray has to register as a StatusNotifier host, because a Fedora drop-in waits for one
# before starting autostart apps, and without it the session silently loses its keyring.
grep -aq 'org.kde.StatusNotifierHost'                 /usr/bin/noctalia
grep -aq 'RegisterStatusNotifierHost'                 /usr/bin/noctalia

# ddcutil is the only way to change brightness on this hardware, and wtype is the clipboard paste.
rpm -q ddcutil wtype

# Must be a GLES client to match the renderer, or the bar comes up blank instead of failing.
noctalia_libs="$(ldd /usr/bin/noctalia)"
[[ "${noctalia_libs}" == *libEGL*     ]]
[[ "${noctalia_libs}" == *libGLESv2*  ]]
[[ "${noctalia_libs}" == *libwayland-client* ]]

# Proves the config validator actually works, in both directions, which is what makes
# verify.sh's use of it mean anything. If this ever fails, move it to verify.sh rather
# than weakening it to `|| true`, which would report success for a validator that never ran.
validate_dir="$(mktemp -d)"
cat > "${validate_dir}/good.toml" <<'GOOD'
[bar.default]
position = "top"
GOOD
cat > "${validate_dir}/bad.toml" <<'BAD'
[bar.default
position = "top
BAD
noctalia config validate "${validate_dir}/good.toml"
! noctalia config validate "${validate_dir}/bad.toml"
rm -rf "${validate_dir}"

# The config, the palette and anything needing a running compositor are verify.sh's job.

echo "shell: $(rpm -q noctalia), greeter: $(rpm -q noctalia-greeter)"
