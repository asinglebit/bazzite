# Bazzite + Sway — local image build and deploy.
#
# Typical first run:
#   just insurance      # pin the current deployment, stop the auto-updater
#   just build          # boot 1: Sway added, Plasma still there as a fallback
#   just switch test
#   sudo systemctl reboot

image := "localhost/bazzite-sway"

default:
    @just --list

# Pin the running deployment and disable uupd so a rollback cannot be reverted.
insurance:
    #!/usr/bin/bash
    set -euo pipefail
    sudo ostree admin pin 0
    sudo systemctl disable --now uupd.timer || true
    echo
    echo "Current deployment (record this):"
    rpm-ostree status
    ostree admin status

# Boot 1: Sway alongside Plasma. Tag: :test
build:
    sudo podman build --build-arg REMOVE_KDE=0 -t {{image}}:test .

# Boot 2: Plasma removed. Tag: :latest
build-nokde:
    sudo podman build --build-arg REMOVE_KDE=1 -t {{image}}:latest .

# Rechunk a built tag. Only needed if `switch` fails with
# "Missing ostree.final-diffid" (ublue-os/bazzite#1892).
rechunk tag="test":
    sudo rpm-ostree compose build-chunked-oci \
        --bootc --format-version=2 --max-layers=127 \
        --from {{image}}:{{tag}} \
        --output containers-storage:{{image}}:{{tag}}

# Point the system at a built tag. Reboot afterwards.
#
# `bootc switch` compares the image *reference*, not its content, so rebuilding
# the same tag and re-running switch prints "Image specification is unchanged"
# and leaves the old build staged. `bootc upgrade` re-reads the ref and picks up
# the new digest, so fall through to it.
switch tag="test":
    #!/usr/bin/bash
    set -euo pipefail
    out=$(sudo bootc switch --transport containers-storage {{image}}:{{tag}} 2>&1) || { echo "$out"; exit 1; }
    echo "$out"
    if grep -q "unchanged" <<<"$out"; then
        echo "-- already on this ref; upgrading to pick up the rebuilt digest --"
        sudo bootc upgrade
    fi
    echo
    echo "Staged. Reboot when ready:  sudo systemctl reboot"
    ostree admin status

# Stage without committing to a reboot.
stage tag="test":
    sudo bootc switch --transport containers-storage --download-only {{image}}:{{tag}}

rollback:
    sudo bootc rollback --apply

# Back to stock, signed, upstream Bazzite.
restore:
    sudo bootc switch ostree-image-signed:docker://ghcr.io/ublue-os/bazzite-nvidia-open:stable

status:
    @bootc status || true
    @echo
    @rpm-ostree status
    @echo
    @ostree admin status

# Drop build layers. Does NOT touch the OS: bootc keeps deployments in
# /ostree/container-storage, separate from /var/lib/containers.
clean:
    sudo podman image prune -af

# Symlink everything under dotfiles/ into ~/.config, mirroring the tree the
# same way system_files/ mirrors the image root.
#
# Deliberately NOT baked into the image. Monitor layout, scaling and workspace
# bindings are per-user preference rather than a property of the artifact, and
# the EDID identifiers in 10-outputs.conf name two specific physical panels --
# baking those in would mean a rebuild and a reboot to swap a monitor. Living
# here they are version-controlled but still editable with a `swaymsg reload`.
#
# Idempotent. An existing regular file is moved to <name>.bak-<timestamp>
# rather than overwritten; an already-correct symlink is left alone.
[doc('Symlink dotfiles/ into ~/.config. Idempotent; backs up anything in the way.')]
link-dotfiles:
    #!/usr/bin/bash
    set -euo pipefail
    src="{{justfile_directory()}}/dotfiles"
    dest="${XDG_CONFIG_HOME:-$HOME/.config}"
    stamp=$(date +%Y%m%d-%H%M%S)

    [[ -d "$src" ]] || { echo "no dotfiles/ directory at $src" >&2; exit 1; }

    while IFS= read -r -d '' file; do
        rel="${file#"$src"/}"
        target="$dest/$rel"
        if [[ -L "$target" && "$(readlink "$target")" == "$file" ]]; then
            echo "  ok        $rel"
            continue
        fi
        mkdir -p "$(dirname "$target")"
        if [[ -e "$target" || -L "$target" ]]; then
            mv -- "$target" "$target.bak-$stamp"
            echo "  backed up $rel -> $rel.bak-$stamp"
        fi
        ln -s -- "$file" "$target"
        echo "  linked    $rel"
    done < <(find "$src" -type f -print0 | sort -z)

    echo
    echo "Apply:  swaymsg reload"
