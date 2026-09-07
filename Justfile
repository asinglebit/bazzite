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

# The one build path. Both `just build` and CI go through here, so the image
# published nightly is exactly the one you can reproduce on this machine.
#
#   registry=""       local build: 40-branding.sh keeps the containers-storage
#                     ref and 50-signing.sh skips the trust setup entirely.
#   pull="missing"    reuse the cached base locally. CI passes `newer`, without
#                     which a nightly rebuild could sit on a stale base forever.
#
# --- CTX_DIGEST, and the silent stale build it exists to prevent -------------
#
# The Containerfile runs build.sh with the repo bind-mounted from a `ctx` scratch
# stage, deliberately, so that editing build_files/ does not invalidate the 5+ GiB
# base image layer. The cost of that -- undocumented until it bit -- is that
# podman's cache key for the RUN step does not include the bind-mounted stage's
# content either. So editing a build script invalidates NOTHING, `podman build`
# reports "Using cache", and you get a freshly tagged image that is byte-identical
# to the last one. `just switch` then has nothing new to switch to and says so in
# a way that reads like success. That is how a whole shell replacement got built,
# tagged, switched and rebooted into without any of it being in the image.
#
# So the cache key gets the one thing it was missing: a hash of everything that
# ends up in ctx. Base layer still cached, script edits still invalidate, and
# nothing has to be remembered.
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
rechunk-ci tag="sway":
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
switch-remote tag="sway":
    sudo bootc switch ostree-image-signed:docker://{{registry}}/{{image_name}}:{{tag}}

# One-time, and only once: the very first switch onto GHCR.
#
# The trust for ghcr.io/asinglebit only exists *inside* the image being installed, so
# this first pull has nothing to verify against and falls through to the
# policy.json "" catch-all. Reboot, confirm the trust files landed, then use
# switch-remote from then on. See README "Updating".
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

    # Prune what this repo used to link and no longer ships.
    #
    # Until this existed, deleting a dotfile left a dangling symlink in
    # ~/.config forever, and the shell swap deleted twenty-one of them at once.
    # In most directories that is untidy. In sway/config.d/ it is not:
    # layered-include globs that directory, so a dangling entry becomes an
    # `include` of a path that does not resolve, and sway fails to load the file.
    #
    # Scoped to links whose TARGET is under $src, so this only ever removes
    # something this repo put there -- never a link the user or another tool owns.
    # That guard is the whole reason this is safe to run unattended.
    #
    # BOTH SIDES ARE CANONICALISED, and that is not defensive programming -- the
    # naive prefix test silently matched NOTHING on this machine. /home is a
    # symlink to /var/home on an ostree system, so `just` can report the justfile
    # directory as either, and the existing links were created through the other
    # one: comparing "/var/home/...dotfiles/mako/config" against a $src of
    # "/home/...dotfiles" fails for every single link. `readlink -m` resolves the
    # prefix without requiring the target to exist, which is the whole point here,
    # since a dangling link is exactly what is being matched.
    src_real="$(readlink -f "$src")"
    while IFS= read -r -d '' link; do
        tgt_real="$(readlink -m "$(readlink "$link")")"
        [[ "$tgt_real" == "$src_real"/* ]] || continue
        rm -- "$link"
        echo "  pruned    ${link#"$dest"/}"
    done < <(find "$dest" -xtype l -print0 2>/dev/null)

    # And the directories those links used to live in (waybar/, swaync/, rofi/,
    # wlogout/, mako/, swaylock/, hypr/). -empty means nothing the user added is
    # at risk.
    find "$dest" -mindepth 1 -type d -empty -delete 2>/dev/null || true

    echo
    echo "Apply:  swaymsg reload"

# Validate dotfiles/noctalia/ as committed, not as linked.
#
# WHY THIS IS A RECIPE AND NOT A BUILD ASSERTION. The image build cannot see this
# config at all: .containerignore excludes dotfiles/, and the Containerfile's ctx
# stage copies build_files/ and system_files/ only. So the same wall
# 16-hyprlock.sh described for hyprlock applies -- except that this time there IS
# a validator. `noctalia config validate` parses without a compositor, reports
# file:line:column and exits 1 on error; 18-noctalia-shell.sh proves that at build
# time against a known-good and a known-bad file, which is what makes this
# meaningful.
#
# NOCTALIA_CONFIG_HOME points at the repo rather than ~/.config, and the state and
# data dirs at a throwaway, for a specific reason: the settings GUI writes
# ~/.local/state/noctalia/settings.toml and that file WINS over everything in
# dotfiles/. Validating the linked config would therefore tell you whether the
# merged result is valid, not whether what is committed is. This tells you the
# second thing, which is the one a commit can be wrong about.
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

    # The palette exists twice by design -- see the note at the top of
    # system_files/usr/share/factory/var/lib/noctalia-greeter/greeter.toml -- so
    # check the two copies still say the same thing. This is the same comparison
    # verify.sh makes against the DEPLOYED files; here it runs against the repo,
    # so a drift is caught before it is committed rather than after it is booted.
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

# Run the real login screen, nested, inside the session you are already in.
#
# THIS IS THE ONLY CHECK THAT SEES A LIVE GREETER. The build validates
# greeter.toml as TOML and runs `noctalia-greeter sessions`, but it cannot start
# the greeter: the compositor wants DRM and a logind seat, and no subcommand of
# the greeter reads its config. See the note at the end of
# build_files/17-noctalia-greeter.sh.
#
# Three pieces make it work without touching the login path:
#
#   fakegreet             greetd's own test harness, from greetd-fakegreet. It
#                         creates a socket, exports GREETD_SOCK at it and answers
#                         the greeter's IPC, so no PAM and no root. Log in as
#                         `user` / `password`; it also asks `7 + 2:` -- type `9`.
#   WLR_BACKENDS=wayland  makes the bundled wlroots compositor open a window on
#                         the current session instead of taking a DRM device.
#   pixman + NO_EXPLICIT_SYNC  without BOTH of these this recipe does not paint
#                         at all. The greeter's compositor is wlroots 0.20 and
#                         its wayland backend wants explicit sync from its host;
#                         SwayFX is 0.19 and does not offer the syncobj
#                         protocol, so the nested backend spins on
#                         "Signal timeline requires a wait timeline" (
#                         backend/wayland/output.c:482) and never presents a
#                         frame. Software rendering sidesteps the whole
#                         dmabuf/timeline path. The cost is that the palette is
#                         NOT tone-mapped the way the real GLES2 login screen
#                         maps it, so colours sampled here read as their raw
#                         seeds -- the accent shows as #fff59b rather than the
#                         #cac37f the real screen draws. Judge layout and
#                         relative contrast here; do not trust absolute hexes.
#   STATE_DIR             a throwaway seeded from the image's own greeter.toml,
#                         so this tests the SHIPPED config rather than whatever
#                         is in /var. Verified to carry the palette: with
#                         `surface` set to #ff0000 the window turns red.
#
# WHY IT CALLS THE COMPOSITOR DIRECTLY, and not
# /usr/libexec/noctalia-greeter-nvidia like greetd does. That wrapper execs
# noctalia-greeter-session, which repoints XDG_RUNTIME_DIR at
# /tmp/noctalia-runtime-$(id -u) and then `unset WAYLAND_DISPLAY` -- so the
# nested backend has no way to find the host compositor. Symlinking the host
# socket in as wayland-0 does work exactly once: the nested compositor then binds
# ITS socket over the symlink and the next run has nothing to connect to. So this
# replicates what the session script does (dbus-run-session, GREETER_BIN, WLR_LOG)
# and keeps the host's runtime dir. The one thing that skips is the wrapper's
# WLR_RENDERER pin, which is meaningless nested anyway.
#
# WHAT IT DOES NOT TELL YOU: nested, this exercises no DRM, no KMS and no
# renderer selection. It validates the palette, the fonts and the session list.
# Whether the login screen comes up on this GPU is only answered by rebooting.
[doc('Preview the login screen nested in this session, against a fake greetd.')]
greeter-preview:
    #!/usr/bin/bash
    set -euo pipefail

    # Both live in the image, so this recipe only works from the deployment that
    # HAS them -- `just build` alone is not enough, and there is deliberately no
    # fallback that fetches them: a preview tool has no business running binaries
    # it downloaded outside the image's own signed transaction.
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

# Bind the image's avatar to the invoking user's account.
#
# WHY THIS IS A RECIPE AND NOT PART OF THE IMAGE. noctalia-greeter has no avatar
# key in greeter.toml at all -- it asks AccountsService for the user's IconFile.
# That is per-user state under /var/lib/AccountsService, and /var is not shipped
# in a bootc image, so the image can only provide the FILE (17-noctalia-greeter.sh
# installs it into /usr) and something outside the image has to attach it to an
# account. Re-run this after a reinstall; verify.sh reports whether it has been.
#
# WHAT IT FIXES. Out of the box AccountsService reports IconFile=$HOME/.face,
# which cannot work for this greeter under any circumstances: it runs as greetd,
# $HOME is 0700, so it cannot even traverse the directory -- and on this machine
# the file did not exist either way. The greeter falls back to its built-in
# line-art person icon, which is the thing being replaced.
#
# NOT THE SetIconFile D-BUS CALL, which is the obvious API. accounts-daemon
# carries /var/lib/AccountsService/icons as a baked-in path and copies the image
# there under the bare username -- a filename with no extension. This greeter
# picks its image decoder BY EXTENSION (`.svg` is special-cased in the binary),
# so the copy would come back as an unrecognised raster file and the placeholder
# would return. Writing Icon= keeps the /usr path and its extension, and
# duplicates nothing.
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

    # Read-modify-write rather than truncate: this file also carries Language,
    # XSession and SystemAccount for the account, and clobbering those is how a
    # user stops being offered a session. Keys are case-sensitive, hence
    # optionxform.
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

    # accounts-daemon caches the store, so make it re-read before asserting.
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
