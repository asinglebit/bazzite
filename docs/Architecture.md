# Architecture

Three layers, each with a different lifetime and a different way of being changed. Almost
every "where does this go?" question is answered by picking the right one.

| Layer | Source | Lifetime | Changed by |
| --- | --- | --- | --- |
| The image | `build_files/`, `system_files/` | Replaced wholesale on every update | A rebuild and a reboot |
| `/etc` | `system_files/etc/`, shipped inside the image | Survives updates; bootc 3-way merges it | Editing it, and the edit persists |
| `~/.config` | `dotfiles/`, symlinked | Never enters the image | `just link-dotfiles`, then a reload |

## Which layer

The question is *when does a change need to take effect, and for whom*.

**The image** is for anything that must be true before a user exists. Packages, the
session entry, the polkit agent, the login screen's config. A first boot on a fresh
install has no home directory to read from, so anything the desktop needs in order to
come up at all lives here. The cost is that changing it is a forty-minute build and a
reboot.

**`/etc`** is for image-level config a human might need to edit under pressure, and for
retiring things that cannot be uninstalled. bootc 3-way merges `/etc`, so a hand edit
survives updates — which is what makes it the right place for
`/etc/greetd/config.toml` and for the empty drop-ins described below.

**`~/.config`** is for anything that depends on *this* hardware or *this* person: the
monitor layout, the input devices, the palette, the bar. Changing a monitor should be a
`swaymsg reload`, not a rebuild. Nothing here enters the image, so the desktop has to work
without it — and it does, on stock defaults.

## Retirement instead of removal

Several packages cannot be uninstalled: `waybar`, `swaylock`, `swayidle`, `grimshot` and
`lxqt-policykit` are hard requirements of `sway-config-fedora`, which SwayFX needs. Each
one ships a drop-in under `/usr/share/sway/config.d/` that would start it.

They are retired instead. `system_files/etc/sway/config.d/` holds a **comment-only file of
the same basename** for each, and sway reads `/etc` over `/usr/share`, so the Fedora
drop-in is shadowed by a file that does nothing.

This has a failure mode worth knowing: if upstream renames one of those files, the
retirement stops matching and the program comes back, silently. So the build asserts
*both* halves — that the Fedora file still exists and that ours still shadows it — and
`verify.sh` repeats the check after boot. Deleting one of these files is also the
supported way back to Fedora's bar or locker, which is why they are in `/etc` and not in
`dotfiles/`.

## Ownership

Exactly one thing owns any given path. `dotfiles/` here owns the *desktop* half of
`~/.config` — sway, noctalia, GTK. Shell, toolchains, tmux and Ghostty's own config live
in a separate portable repo, and the two never touch the same path. That is what lets
either one be absent.

## Where the checks live

Three tiers, because they can each assert different things:

- **The build** (`build_files/*.sh`) asserts anything provable inside a container:
  packages present, files installed, symlinks made, `ldd` output. A failure here fails the
  nightly rather than shipping.
- **CI** (`.github/workflows/build.yml`) re-runs a set of those against the **finished,
  rechunked** image, which is how the rechunk is proven not to have dropped `/etc`.
- **`verify.sh`** asserts what needs a running session, a GPU and a seat: is the shell
  alive, did the palette drift, is the config the committed one or a GUI override.

A claim that cannot be checked at build time is deliberately not checked there. The sway
config is the standing example — see [[Compositor]].

Related: [[Build and release]], [[Cadence]], [[Decisions]].
