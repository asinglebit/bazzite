# Bazzite + Sway — local image build and deploy.
#
# Typical first run:
#   just insurance      # pin the current deployment, stop the auto-updater
#   just build          # boot 1: Sway added, Plasma still there as a fallback
#   just switch test
#   sudo systemctl reboot

image_name := "bazzite-sway"
image      := "localhost/" + image_name
registry   := "ghcr.io/asinglebit"

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

# The one build path. Both `just build` and CI go through here, so the image
# published nightly is exactly the one you can reproduce on this machine.
#
#   registry=""       local build: 40-branding.sh keeps the containers-storage
#                     ref and 50-signing.sh skips the trust setup entirely.
#   pull="missing"    reuse the cached base locally. CI passes `newer`, without
#                     which a nightly rebuild could sit on a stale base forever.
[doc('Parameterised build. `just build` and CI both go through here.')]
build-image variant tag registry="" pull="missing":
    sudo podman build --pull={{pull}} \
        --build-arg REMOVE_KDE={{variant}} \
        --build-arg IMAGE_REGISTRY={{registry}} \
        --build-arg IMAGE_TAG={{tag}} \
        -t {{image}}:{{tag}} .

# Boot 1: Sway alongside Plasma. Tag: :test
build: (build-image "0" "test")

# Boot 2: Plasma removed. Tag: :latest
build-nokde: (build-image "1" "latest")

# Rechunk a built tag. Only needed if `switch` fails with
# "Missing ostree.final-diffid" (ublue-os/bazzite#1892).
[doc('Rechunk a built tag locally. Only for the Missing ostree.final-diffid bug.')]
rechunk tag="test":
    sudo rpm-ostree compose build-chunked-oci \
        --bootc --format-version=2 --max-layers=127 \
        --from {{image}}:{{tag}} \
        --output containers-storage:{{image}}:{{tag}}

# Rechunk on a machine that has no rpm-ostree of its own -- i.e. a CI runner.
#
# Runs rpm-ostree *out of the image just built* (Bazzite ships it) against that
# image's own rootfs mounted read-only. Going through --rootfs rather than
# --from is what avoids deadlocking on the container-storage lock it is writing
# back through; the [overlay@graphroot+runroot] output specifier is what puts
# the result back in the host's storage under the same tag.
#
# This is the step that keeps a nightly `just update` in the hundreds of MB
# instead of multiple GB: it re-splits the image into per-package layers that
# stay byte-identical across rebuilds when the packages did not change.
[doc('Rechunk without a host rpm-ostree, for CI runners.')]
rechunk-ci tag="test":
    #!/usr/bin/bash
    set -euxo pipefail
    src="{{image}}:{{tag}}"

    # build-chunked-oci given --rootfs builds the output image config from
    # scratch, so every label from the Containerfile is dropped -- including
    # org.opencontainers.image.source, which is what links the GHCR package to
    # this repo. Capture them off the pre-rechunk image and hand them back.
    #
    # ostree.* is excluded deliberately: build-chunked-oci regenerates those
    # for the new layer set, and re-applying the stale inherited ones is
    # exactly the Missing ostree.final-diffid bug that rechunking exists to fix.
    labels=()
    while IFS= read -r kv; do
        [[ -n "$kv" ]] && labels+=(--label "$kv")
    done < <(sudo podman image inspect "$src" \
        | jq -r '.[0].Labels // {} | to_entries[]
                 | select(.key | startswith("ostree.") | not)
                 | "\(.key)=\(.value)"')

    graphroot="$(sudo podman info --format json | jq -r '.store.graphRoot')"

    sudo podman run --rm --pull=never --privileged \
        --security-opt label=disable \
        --mount=type=image,src="$src",target=/rpm-ostree \
        --mount=type=bind,src="${graphroot}",target=/run/host-container-storage,rw \
        --mount=type=tmpfs,target=/run/rpm-ostree-storage \
        --entrypoint /usr/bin/rpm-ostree \
        "$src" \
        compose build-chunked-oci \
            --bootc --format-version=2 --max-layers 127 \
            --rootfs /rpm-ostree \
            "${labels[@]}" \
            --output "containers-storage:[overlay@/run/host-container-storage+/run/rpm-ostree-storage]{{image}}:{{tag}}"

    # A rechunk that quietly dropped the source label yields an orphaned GHCR
    # package that never links back to the repo. Assert rather than hope.
    sudo podman image inspect "$src" | jq -e '
        .[0].Labels
        | (.["containers.bootc"] == "1")
          and has("ostree.final-diffid")
          and (.["org.opencontainers.image.source"] | startswith("https://github.com/"))
    ' >/dev/null

# Point the system at a built tag. Reboot afterwards.
#
# `bootc switch` compares the image *reference*, not its content, so rebuilding
# the same tag and re-running switch prints "Image specification is unchanged"
# and leaves the old build staged. `bootc upgrade` re-reads the ref and picks up
# the new digest, so fall through to it.
[doc('Point the system at a locally built tag. Reboot afterwards.')]
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

# --- the published image ---------------------------------------------------
#
# CI rebuilds and signs ghcr.io/asinglebit/bazzite-sway nightly against current
# upstream Bazzite, so these are also how upstream's kernel, mesa and NVIDIA
# updates arrive. Nothing fetches on its own: no timer, no update agent.

# Is there anything new? Metadata only -- does not download layers.
update-check:
    sudo bootc upgrade --check

# Stage the newest published image. Applies at the next reboot.
update:
    #!/usr/bin/bash
    set -euo pipefail
    sudo bootc upgrade
    echo
    echo "Staged. Reboot when ready:  sudo systemctl reboot"
    ostree admin status

# Stage it and reboot straight into it.
update-now:
    sudo bootc upgrade --apply

# Point the system at the published image, verifying its cosign signature.
#
# ostree-image-signed: is what makes every pull consult
# /etc/containers/policy.json, where 50-signing.sh installed a block requiring
# ghcr.io/asinglebit to be signed by /etc/pki/containers/asinglebit.pub. bootc stores
# this whole ref, so plain `just update` stays verified with no extra flags.
[doc('Point the system at the published image, verifying its signature.')]
switch-remote tag="test":
    sudo bootc switch ostree-image-signed:docker://{{registry}}/{{image_name}}:{{tag}}

# One-time, and only once: the very first switch onto GHCR.
#
# The trust for ghcr.io/asinglebit only exists *inside* the image being installed, so
# this first pull has nothing to verify against and falls through to the
# policy.json "" catch-all. Reboot, confirm the trust files landed, then use
# switch-remote from then on. See README "Updating".
[doc('One-time unverified first switch onto GHCR. Use switch-remote after.')]
bootstrap-remote tag="test":
    sudo bootc switch {{registry}}/{{image_name}}:{{tag}}

status:
    @bootc status || true
    @echo
    @rpm-ostree status
    @echo
    @ostree admin status

# Drop build layers. Does NOT touch the OS: bootc keeps deployments in
# /ostree/container-storage, separate from /var/lib/containers.
[doc('Drop local build layers. Does NOT touch the OS or its deployments.')]
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
