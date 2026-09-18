# Bazzite + Sway — local image build and deploy.
#
# First run:
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

# An empty registry means a local unsigned build.
[doc('Parameterised build. `just build` and CI both go through here.')]
build-image tag="sway" registry="" pull="missing":
    #!/usr/bin/bash
    set -euo pipefail
    cd "{{justfile_directory()}}"
    # Without this podman says "Using cache" and re-tags the previous image.
    ctx_digest=$(find build_files system_files cosign.pub -type f -print0 \
        | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16)
    echo "ctx digest: ${ctx_digest}"
    sudo podman build --pull={{pull}} \
        --build-arg IMAGE_REGISTRY={{registry}} \
        --build-arg IMAGE_TAG={{tag}} \
        --build-arg CTX_DIGEST="${ctx_digest}" \
        -t {{image}}:{{tag}} .

# Plasma removed, SwayFX and noctalia-greeter in its place.
build: (build-image "sway")

[doc('Rechunk a built tag locally. Only for the Missing ostree.final-diffid bug.')]
rechunk tag="sway":
    sudo rpm-ostree compose build-chunked-oci \
        --bootc --format-version=2 --max-layers=127 \
        --from {{image}}:{{tag}} \
        --output containers-storage:{{image}}:{{tag}}

# Keeps a nightly update in the hundreds of MB rather than several GB.
[doc('Rechunk without a host rpm-ostree, for CI runners.')]
rechunk-ci tag="sway":
    #!/usr/bin/bash
    set -euxo pipefail
    src="{{image}}:{{tag}}"

    # Rechunking drops every label, so carry them over -- bar the ostree ones, which are regenerated.
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

    # A dropped source label would orphan the package on GHCR.
    sudo podman image inspect "$src" | jq -e '
        .[0].Labels
        | (.["containers.bootc"] == "1")
          and has("ostree.final-diffid")
          and (.["org.opencontainers.image.source"] | startswith("https://github.com/"))
    ' >/dev/null

# Rebuilding the same tag says "unchanged", so fall through to upgrade for the new digest.
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

# CI rebuilds nightly, and nothing here fetches on its own -- no timer, no update agent.

# Is there anything new? Metadata only, nothing downloaded.
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

[doc('Point the system at the published image, verifying its signature.')]
switch-remote tag="sway":
    sudo bootc switch ostree-image-signed:docker://{{registry}}/{{image_name}}:{{tag}}

# Unverifiable, because the key to verify it with is inside the image being installed.
[doc('One-time unverified first switch onto GHCR. Use switch-remote after.')]
bootstrap-remote tag="sway":
    sudo bootc switch {{registry}}/{{image_name}}:{{tag}}

status:
    @bootc status || true
    @echo
    @rpm-ostree status
    @echo
    @ostree admin status

[doc('Drop local build layers. Does NOT touch the OS or its deployments.')]
clean:
    sudo podman image prune -af

# Out of the image, so changing a monitor is a reload and not a rebuild.
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

    # A link this repo no longer ships is fatal in sway/config.d/, where sway stops loading.
    # Resolve both, because /home is itself a symlink and the naive compare matched nothing.
    src_real="$(readlink -f "$src")"
    while IFS= read -r -d '' link; do
        tgt_real="$(readlink -m "$(readlink "$link")")"
        [[ "$tgt_real" == "$src_real"/* ]] || continue
        rm -- "$link"
        echo "  pruned    ${link#"$dest"/}"
    done < <(find "$dest" -xtype l -print0 2>/dev/null)

    # Their directories too, but only if empty.
    find "$dest" -mindepth 1 -type d -empty -delete 2>/dev/null || true

    echo
    echo "Apply:  swaymsg reload"

# A throwaway state dir, because the settings GUI writes a file that outranks the commit.
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

    # The palette exists twice by design, so check the copies still agree before committing.
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

# Apps live outside the image, so a reinstall would lose every one you added by hand.
[doc('Reconcile installed flatpaks with flatpaks.list. Idempotent.')]
install-flatpaks:
    #!/usr/bin/bash
    set -euo pipefail
    list="{{justfile_directory()}}/flatpaks.list"

    [[ -r "$list" ]] || { echo "no flatpaks.list at $list" >&2; exit 1; }

    want=() drop=() section=""
    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line//[[:blank:]]/}"
        [[ -n "$line" ]] || continue
        case "$line" in
            "[install]") section=want; continue ;;
            "[remove]")  section=drop; continue ;;
        esac
        case "$section" in
            want) want+=("$line") ;;
            drop) drop+=("$line") ;;
            *) echo "$list: '$line' sits before any [install] or [remove] header" >&2; exit 1 ;;
        esac
    done < "$list"

    (( ${#want[@]} + ${#drop[@]} )) || { echo "$list lists nothing" >&2; exit 1; }

    wanted=$(printf '%s\n' "${want[@]}")
    dropped=$(printf '%s\n' "${drop[@]}")
    have=$(flatpak list --app --columns=application | sort -u)

    for id in "${drop[@]}"; do
        grep -qxF "$id" <<<"$wanted" && { echo "$list: $id is in both sections" >&2; exit 1; }
    done

    # Bazzite reinstalls these itself, so they never count as unlisted extras.
    stock=$(sed 's|//.*||' /usr/share/ublue-os/bazzite/flatpak/install 2>/dev/null | grep . || true)

    # One bad ID would sink the whole batch install, so check each before installing any.
    install=() unknown=()
    for id in "${want[@]}"; do
        if grep -qxF "$id" <<<"$have"; then
            echo "  ok        $id"
        elif flatpak remote-info flathub "$id" >/dev/null 2>&1; then
            echo "  install   $id"
            install+=("$id")
        else
            echo "  unknown   $id"
            unknown+=("$id")
        fi
    done

    remove=()
    for id in "${drop[@]}"; do
        if grep -qxF "$id" <<<"$have"; then
            echo "  remove    $id"
            remove+=("$id")
        else
            echo "  gone      $id"
        fi
    done

    if [[ ${#install[@]} -gt 0 ]]; then
        echo
        sudo flatpak install --system --noninteractive flathub "${install[@]}"
    fi

    if [[ ${#remove[@]} -gt 0 ]]; then
        echo
        sudo flatpak uninstall --system --noninteractive "${remove[@]}"
        echo "Their runtimes stay behind until:  sudo flatpak uninstall --system --unused"
    fi

    # Read again, because the steps above changed what is installed.
    have=$(flatpak list --app --columns=application | sort -u)

    # Installed by hand and written down nowhere, so a reinstall would lose it.
    extra=()
    while IFS= read -r id; do
        [[ -n "$id" ]] || continue
        grep -qxF "$id" <<<"$wanted"  && continue
        grep -qxF "$id" <<<"$dropped" && continue
        grep -qxF "$id" <<<"$stock"   && continue
        extra+=("$id")
    done <<<"$have"

    if [[ ${#extra[@]} -gt 0 ]]; then
        echo
        echo "Installed but not listed:"
        printf '  %s\n' "${extra[@]}"
        echo
        echo "Add them to flatpaks.list, or drop them:"
        echo "  sudo flatpak uninstall --system ${extra[*]}"
    fi

    if [[ ${#unknown[@]} -gt 0 ]]; then
        echo >&2
        echo "Flathub has no such app -- a typo, a rename, or denied by the image's" >&2
        echo "flatpak-blocklist (Steam and Lutris are, since the image ships them):" >&2
        printf '  %s\n' "${unknown[@]}" >&2
        exit 1
    fi

    echo
    echo "${#want[@]} listed, ${#install[@]} installed, ${#remove[@]} removed."

# The only way to see the real login screen without rebooting: it runs nested in a window,
# against a fake greetd, so log in as user/password and the sum it asks is 9.
# Software rendering is required, because the nested compositor otherwise never draws a frame;
# the cost is that colours are not tone-mapped, so judge layout here and not exact hexes.
# It calls the compositor directly, since the usual wrapper would leave it nothing to connect to.
# It exercises no DRM at all, so whether the login screen works on this GPU is still a reboot away.
[doc('Preview the login screen nested in this session, against a fake greetd.')]
greeter-preview:
    #!/usr/bin/bash
    set -euo pipefail

    # Only works from a deployment that already has these, and deliberately fetches nothing.
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

# The image ships the avatar file and this attaches it to your account, which is per-user
# state and so cannot be in the image; re-run it after a reinstall.
# Written directly rather than through the obvious D-Bus call, because that copies the file
# to a name with no extension and this greeter picks its decoder from the extension.
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

    # Read and rewrite rather than overwrite: this file also says which session you get.
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

    # The daemon caches this file, so make it re-read before checking.
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
