# Decisions

Each entry is a choice, the alternative that lost, and the cost that was accepted.

## Derive at runtime, never write down a constant

The rule that shows up most often. Monitors are named by EDID identifier, not connector,
because connector names change when you swap ports. [[Workspaces]] are computed from
output geometry on every keypress rather than pinned with `workspace N output`. The
[[Login screen]] derives each output's scale from that output's geometry, and
`greeter.toml` deliberately has no `[output]` block even though the knobs exist.

The losing alternative in each case is a per-connector constant that is correct today and
wrong the first time a monitor moves. The cost is a little runtime work — which is why
`workspace-block.sh` uses `jq` rather than `python3`.

## A bootc image rather than a package set

Everything the desktop needs to come up is in the image, so a first boot works before any
dotfiles repo is cloned. The alternative — a post-install script — has no answer for "the
machine reinstalled and the shell does not start".

The cost is that changing the image is a forty-minute build and a reboot, which is why
anything hardware- or person-specific lives in [[Architecture|`~/.config`]] instead.

## Retire, do not remove

`waybar`, `swaylock`, `swayidle`, `grimshot` and `lxqt-policykit` are hard requirements of
`sway-config-fedora`, which SwayFX needs. Excluding them would just fail the build.

They are shadowed by comment-only files of the same basename in `/etc/sway/config.d/`.
The cost is a silent failure mode — a rename upstream un-retires one — so the build
asserts both halves and `verify.sh` re-checks after boot. The benefit is that deleting one
file is the supported way back to Fedora's bar or locker.

## One shell package, no fallback

[[Shell|noctalia]] provides bar, launcher, notifications, lock, OSD, clipboard,
screenshots, idle, the NM secret agent, the Bluetooth agent, the tray host and the only
polkit agent. The alternative is seven small programs, each configured separately, which
is what was removed.

The cost is the largest single point of failure in the system, and it fails *silently* —
`pkexec` hangs rather than errors. Accepted because `$mod+Return` is bound in
`/etc/sway/config` and does not go through the shell, so there is always a way back in.

## A graphical login screen, GPU and all

A console greeter cannot scale per monitor; the same text cell is physically twice the
size on one of these screens as the other. So [[Login screen|noctalia-greeter]] runs its
own compositor.

The cost is a GPU stack in the login path, where the driver's open bugs cluster on exactly
this machine's shape. `tuigreet` stays installed and unbound as the rung below, chosen
because it needs no compositor and no GPU.

## greetd over sddm-wayland-sway

sddm-wayland-sway runs its greeter as a real Sway instance with no way to pass flags, so
it hits sway's own NVIDIA guard. greetd lets the command line be written by hand — which
is the whole reason the wrapper at `/usr/libexec/noctalia-greeter-nvidia` can exist.

## Greyscale

No hue anywhere the config can reach. State is signalled with brightness instead, which is
why the accent is the *bright* end of the ramp.

The cost is explicit: no red for errors, no green for success, and an error is one step of
brightness from a warning. [[Theming]] documents how to put hue back for those roles alone
if it ever stops being worth it.

## Flatpaks over layered RPMs

Apps live outside the image, so they update without a rebuild or a reboot and the image
stays small. Layering a GUI app with `rpm-ostree` would make every future rebase carry it.

The cost is that apps are not part of the image's reproducibility, which is what
`flatpaks.list` and `just install-flatpaks` exist to close. See [[Applications]].

## Reproducible image, manual update

Two knobs that are easy to conflate, kept separate on purpose. CI rebuilds nightly so the
base never goes stale; the machine updates only when told. Nothing on the machine fetches
on its own — no timer, no update agent, and noctalia's `auto_update` is `"none"`.

See [[Cadence]].

## No `:latest`

A bare image reference resolving to some other tag would be a silent change of what the
machine follows. Without a tag the pull fails and says so.

## Checks live where they can actually be made

The build asserts what a container can prove, CI re-asserts against the rechunked image,
and `verify.sh` asserts what needs a session and a GPU.

The explicit counter-example is the sway config: `sway -C` cannot run in a container at
all, and a good config fails identically to a broken one, so a build-time check would
prove nothing while *looking* like it proved something. `build_files/15-swayfx.sh` says so
and tells you not to add it back.

## Comments carry the reason, not the history

One sentence, plain words, and only where the behaviour cannot be read off the code. No
changelogs in comments — that is what git is for.

Related: [[Architecture]], [[Cadence]], [[Components]].
