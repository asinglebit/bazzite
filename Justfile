# Bazzite + Sway — local image build and deploy.
#
# Typical first run:
#   just insurance      # pin the current deployment, stop the auto-updater
#   just build
#   just switch
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

# The one build path -- `just build` and CI both come through here.
#
#   registry=""     local build: 40-branding.sh keeps the containers-storage ref
#                   and 50-signing.sh skips the trust setup.
#   pull="missing"  reuse the cached base locally. CI passes `newer`, without
#                   which a nightly rebuild could sit on a stale base forever.
#
# CTX_DIGEST PREVENTS A SILENT STALE BUILD. The Containerfile bind-mounts the
# repo from a `ctx` scratch stage so editing build_files/ does not invalidate the
# 5+ GiB base layer -- but podman's cache key for the RUN step does not include
# the bind-mounted content either. So a script edit invalidated NOTHING, podman
# reported "Using cache", and `just switch` found nothing to switch to and said
# so in a way that read like success. Hashing ctx into the key fixes it while
# keeping the base layer cached.
[doc('Parameterised build. `just build` and CI both go through here.')]
build-image tag="sway" registry="" pull="missing":
    #!/usr/bin/bash
    set -euo pipefail
    cd "{{justfile_directory()}}"
    ctx_digest=$(find build_files system_files cosign.pub -type f -print0 \
        | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16)
    echo "ctx digest: ${ctx_digest}"
    sudo podman build --pull={{pull}} \
        --build-arg IMAGE_REGISTRY={{registry}} \
        --build-arg IMAGE_TAG={{tag}} \
        --build-arg CTX_DIGEST="${ctx_digest}" \
        -t {{image}}:{{tag}} .

# The image. Plasma removed, SwayFX and noctalia-greeter in its place. Tag: :sway
build: (build-image "sway")

# Rechunk a built tag. Only needed if `switch` fails with
# "Missing ostree.final-diffid" (ublue-os/bazzite#1892).
[doc('Rechunk a built tag locally. Only for the Missing ostree.final-diffid bug.')]
rechunk tag="sway":
    sudo rpm-ostree compose build-chunked-oci \
        --bootc --format-version=2 --max-layers=127 \
        --from {{image}}:{{tag}} \
        --output containers-storage:{{image}}:{{tag}}

# Rechunk on a machine that has no rpm-ostree of its own -- i.e. a CI runner.
#
# Runs rpm-ostree out of the image just built, against that image's own rootfs.
# --rootfs rather than --from avoids deadlocking on the container-storage lock it
# writes back through; the [overlay@graphroot+runroot] specifier puts the result
# back in the host's storage under the same tag.
#
# This is what keeps a nightly `just update` in the hundreds of MB rather than
# multiple GB: per-package layers that stay byte-identical when packages did not
# change.
[doc('Rechunk without a host rpm-ostree, for CI runners.')]
rechunk-ci tag="sway":
    #!/usr/bin/bash
    set -euxo pipefail
    src="{{image}}:{{tag}}"

    # --rootfs builds the output config from scratch, dropping every
    # Containerfile label -- including org.opencontainers.image.source, which is
    # what links the GHCR package to this repo. ostree.* is excluded
    # deliberately: those are regenerated for the new layer set, and re-applying
    # stale ones is the Missing ostree.final-diffid bug rechunking exists to fix.
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

    # A dropped source label yields an orphaned GHCR package. Assert it.
    sudo podman image inspect "$src" | jq -e '
        .[0].Labels
        | (.["containers.bootc"] == "1")
          and has("ostree.final-diffid")
          and (.["org.opencontainers.image.source"] | startswith("https://github.com/"))
    ' >/dev/null

# Point the system at a built tag. Reboot afterwards.
#
# `bootc switch` compares the image REFERENCE, not its content, so rebuilding the
# same tag prints "unchanged" and leaves the OLD build staged. `bootc upgrade`
# re-reads the ref and picks up the new digest, so fall through to it.
[doc('Point the system at a locally built tag. Reboot afterwards.')]
switch tag="sway":
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
stage tag="sway":
    sudo bootc switch --transport containers-storage --download-only {{image}}:{{tag}}

rollback:
    sudo bootc rollback --apply

# Back to stock, signed, upstream Bazzite.
restore:
    sudo bootc switch ostree-image-signed:docker://ghcr.io/ublue-os/bazzite-nvidia-open:stable

# CI rebuilds and signs nightly against current upstream Bazzite, so these are
# also how upstream's kernel, mesa and NVIDIA updates arrive. Nothing fetches on
# its own: no timer, no update agent.

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
# ostree-image-signed: makes every pull consult /etc/containers/policy.json,
# where 50-signing.sh required this namespace to be signed. bootc stores the
# whole ref, so plain `just update` stays verified with no extra flags.
[doc('Point the system at the published image, verifying its signature.')]
switch-remote tag="sway":
    sudo bootc switch ostree-image-signed:docker://{{registry}}/{{image_name}}:{{tag}}

# One-time, and only once: the very first switch onto GHCR.
#
# The trust exists only INSIDE the image being installed, so this first pull has
# nothing to verify against and falls through to policy.json's "" catch-all.
# Reboot, confirm the trust files landed, then use switch-remote from then on.
[doc('One-time unverified first switch onto GHCR. Use switch-remote after.')]
bootstrap-remote tag="sway":
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

# Symlink dotfiles/ into ~/.config, mirroring the tree the way system_files/
# mirrors the image root.
#
# Deliberately NOT baked into the image: the EDID identifiers in 10-outputs.conf
# name two specific panels, so baking them in would mean a rebuild and a reboot
# to swap a monitor. Here they are version-controlled but still editable with a
# `swaymsg reload`.
#
# Idempotent: an existing regular file is moved to <name>.bak-<timestamp>, an
# already-correct symlink left alone.
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

    # Prune what this repo used to link and no longer ships. In most
    # directories a dangling symlink is untidy; in sway/config.d/ it is fatal --
    # layered-include globs that directory, so a dangling entry becomes an
    # `include` of an unresolvable path and sway fails to load the file.
    #
    # Scoped to links whose TARGET is under $src, so this only removes what this
    # repo put there. That guard is why it is safe to run unattended.
    #
    # BOTH SIDES CANONICALISED, and not as defensive programming: /home is a
    # symlink to /var/home on ostree, so `just` may report the justfile
    # directory either way and the naive prefix test matched NOTHING.
    # `readlink -m` resolves without requiring the target to exist, which is the
    # point -- a dangling link is exactly what is being matched.
    src_real="$(readlink -f "$src")"
    while IFS= read -r -d '' link; do
        tgt_real="$(readlink -m "$(readlink "$link")")"
        [[ "$tgt_real" == "$src_real"/* ]] || continue
        rm -- "$link"
        echo "  pruned    ${link#"$dest"/}"
    done < <(find "$dest" -xtype l -print0 2>/dev/null)

    # And the directories those links lived in. -empty means nothing the user
    # added is at risk.
    find "$dest" -mindepth 1 -type d -empty -delete 2>/dev/null || true

    echo
    echo "Apply:  swaymsg reload"

# Validate dotfiles/noctalia/ as COMMITTED, not as linked.
#
# A recipe rather than a build assertion because the image build cannot see this
# config: .containerignore excludes dotfiles/ and the ctx stage copies only
# build_files/ and system_files/. 18-noctalia-shell.sh proves the validator
# itself works at build time, which is what makes this meaningful.
#
# NOCTALIA_CONFIG_HOME points at the repo, and state/data at a throwaway, for a
# specific reason: the settings GUI writes ~/.local/state/noctalia/settings.toml
# and THAT FILE WINS over everything in dotfiles/. Validating the linked config
# would tell you whether the merged result is valid, not whether the commit is.
[doc('Validate dotfiles/noctalia as committed, ignoring GUI overrides.')]
check-shell-config:
    #!/usr/bin/bash
    set -euo pipefail
    src="{{justfile_directory()}}/dotfiles"
    [[ -d "$src/noctalia" ]] || { echo "no dotfiles/noctalia at $src" >&2; exit 1; }
    command -v noctalia >/dev/null || { echo "noctalia is not installed" >&2; exit 1; }

    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    NOCTALIA_CONFIG_HOME="$src" \
    NOCTALIA_STATE_HOME="$tmp/state" \
    NOCTALIA_DATA_HOME="$tmp/data" \
        noctalia config validate

    # The palette exists twice by design (see greeter.toml), so check the two
    # copies still agree. verify.sh makes the same comparison against the
    # DEPLOYED files; here it runs against the repo, so drift is caught before
    # it is committed rather than after it is booted.
    python3 - "$src" <<'PY'
    import json, sys, tomllib, pathlib
    src = pathlib.Path(sys.argv[1])
    greeter = src.parent / "system_files/usr/share/factory/var/lib/noctalia-greeter/greeter.toml"
    g = tomllib.loads(greeter.read_text())["appearance"]["palette"]
    s = json.loads((src / "noctalia/palettes/bazzite-grey.json").read_text())["dark"]
    camel = lambda k: "m" + "".join(p.capitalize() for p in k.split("_"))
    bad = {k: (s.get(camel(k)), v) for k, v in g.items() if s.get(camel(k)) != v}
    if bad:
        for k, (shell, gr) in sorted(bad.items()):
            print(f"  {k}: shell={shell} greeter={gr}", file=sys.stderr)
        sys.exit(f"palette drift: {len(bad)} of {len(g)} roles disagree")
    print(f"  palette: {len(g)} roles agree with the greeter")
    PY

# THE ONLY CHECK THAT SEES A LIVE GREETER. The build validates greeter.toml as
# TOML and runs `noctalia-greeter sessions`, but cannot start the greeter -- the
# compositor wants DRM and a logind seat.
#
#   fakegreet             stands in for greetd's IPC, so no PAM and no root. Log
#                         in as `user` / `password`; the sum it asks is 9.
#   WLR_BACKENDS=wayland  opens a window on the current session instead of
#                         taking a DRM device.
#   pixman + NO_EXPLICIT_SYNC  REQUIRED, both. The greeter's compositor is
#                         wlroots 0.20 and its wayland backend wants explicit
#                         sync from the host; SwayFX is 0.19 and offers no
#                         syncobj protocol, so the nested backend spins on
#                         "Signal timeline requires a wait timeline" and never
#                         presents a frame. Software rendering sidesteps the
#                         dmabuf/timeline path -- at the cost that the palette is
#                         NOT tone-mapped as the real GLES2 screen maps it, so
#                         sampled colours read as raw seeds. Judge layout and
#                         relative contrast here; do not trust absolute hexes.
#   STATE_DIR             a throwaway seeded from the IMAGE's greeter.toml, so
#                         this tests the shipped config, not whatever is in /var.
#
# CALLS THE COMPOSITOR DIRECTLY rather than the greetd wrapper, because that
# wrapper execs noctalia-greeter-session, which repoints XDG_RUNTIME_DIR and then
# unsets WAYLAND_DISPLAY -- leaving the nested backend nothing to connect to. So
# this replicates the session script and keeps the host's runtime dir.
#
# WHAT IT DOES NOT TELL YOU: nested, this exercises no DRM, no KMS and no
# renderer selection. Whether the login screen comes up on this GPU is only
# answered by rebooting.
[doc('Preview the login screen nested in this session, against a fake greetd.')]
greeter-preview:
    #!/usr/bin/bash
    set -euo pipefail

    # Both live in the image, so this only works from a deployment that HAS
    # them. No fallback that fetches them, deliberately: a preview tool has no
    # business running binaries from outside the image's signed transaction.
    if ! command -v fakegreet >/dev/null || ! test -x /usr/bin/noctalia-greeter-compositor; then
        echo "The running deployment has no greeter to preview."
        echo "  built already?   just switch && sudo systemctl reboot, then re-run this"
        echo "  checking a build without rebooting? there is no way to; the build's own"
        echo "  checks (17-noctalia-greeter.sh) are all you get until you boot it."
        exit 1
    fi
    test -n "${WAYLAND_DISPLAY:-}" || { echo "run this from inside the Sway session"; exit 1; }

    state="$(mktemp -d)"
    trap 'rm -rf "$state"' EXIT
    install -m0644 /usr/share/factory/var/lib/noctalia-greeter/greeter.toml "$state/greeter.toml"

    echo "-- previewing $state/greeter.toml -- log in as user/password, the sum is 9 --"
    NOCTALIA_GREETER_STATE_DIR="$state" \
    NOCTALIA_GREETER_LOG=stderr \
    GREETER_BIN=/usr/bin/noctalia-greeter \
    WLR_BACKENDS=wayland \
    WLR_RENDERER=pixman \
    WLR_RENDER_NO_EXPLICIT_SYNC=1 \
    WLR_LOG="${WLR_LOG:-error}" \
        fakegreet 'dbus-run-session -- /usr/bin/noctalia-greeter-compositor'

# A recipe and not part of the image because the greeter has no avatar key -- it
# asks AccountsService for IconFile, which is per-user state under /var, and /var
# is not shipped. So the image provides the FILE and this attaches it to an
# account. Re-run after a reinstall; verify.sh reports whether it has been.
#
# Out of the box IconFile is $HOME/.face, which cannot work here: the greeter
# runs as greetd and $HOME is 0700, so it cannot even traverse the directory.
#
# NOT the SetIconFile D-Bus call, which is the obvious API: accounts-daemon
# copies the image into /var/lib/AccountsService/icons under the bare username,
# a filename with NO EXTENSION -- and this greeter picks its decoder BY
# EXTENSION. Writing Icon= keeps the /usr path and its extension.
[doc('Bind the image avatar to this user, replacing the stock person icon.')]
greeter-avatar:
    #!/usr/bin/bash
    set -euo pipefail
    icon=/usr/share/bazzite-sway/greeter-avatar.svg
    store="/var/lib/AccountsService/users/$USER"

    [[ -r "$icon" ]] || {
        echo "no $icon -- this deployment predates the avatar." >&2
        echo "  just build && just switch && sudo systemctl reboot, then re-run this" >&2
        exit 1
    }

    # Read-modify-write, not truncate: this file also carries Language,
    # XSession and SystemAccount, and clobbering those is how a user stops being
    # offered a session. Keys are case-sensitive, hence optionxform.
    sudo python3 - "$store" "$icon" <<'AVATAR'
    import configparser, os, sys
    store, icon = sys.argv[1], sys.argv[2]
    os.makedirs(os.path.dirname(store), mode=0o700, exist_ok=True)
    cp = configparser.ConfigParser(interpolation=None)
    cp.optionxform = str
    cp.read(store)
    if not cp.has_section("User"):
        cp.add_section("User")
    cp.set("User", "Icon", icon)
    with open(store, "w") as fh:
        cp.write(fh, space_around_delimiters=False)
    os.chmod(store, 0o600)
    print(f"  wrote Icon={icon} to {store}")
    AVATAR

    # accounts-daemon caches the store; make it re-read before asserting.
    sudo systemctl try-restart accounts-daemon.service

    obj="$(busctl --system call org.freedesktop.Accounts /org/freedesktop/Accounts \
        org.freedesktop.Accounts FindUserByName s "$USER" --json=short | jq -r '.data[0]')"
    got="$(busctl --system get-property org.freedesktop.Accounts "$obj" \
        org.freedesktop.Accounts.User IconFile --json=short | jq -r '.data')"

    if [[ "$got" == "$icon" ]]; then
        echo "  AccountsService reports IconFile=$got"
        echo
        echo "Apply:  it is read at greeter start, so the next login screen has it."
    else
        echo "  AccountsService still reports IconFile=$got" >&2
        exit 1
    fi
