# Cadence

What moves on its own, what moves when asked, and what never moves by itself.

| Thing | Rhythm | Trigger |
| --- | --- | --- |
| The published image | Nightly, 12:00 UTC | CI cron — rebuilds against current upstream Bazzite |
| This machine | Never on its own | `just update`, applied at the next reboot |
| Kernel, mesa, NVIDIA driver | Arrive with the image | Same nightly; there is no separate path |
| Flatpak apps | Independent of the image | `flatpak update` or topgrade, no reboot |
| noctalia plugins | Never | `auto_update = "none"` |
| `dotfiles/` | Never | `just link-dotfiles`, then `swaymsg reload` |

## Nothing fetches on its own

There is no timer and no update agent on the machine. `just insurance` disables
`uupd.timer` as part of the one-time setup, and `40-branding.sh` disables uBlue's updater
in the image, because it would fire nightly against a ref it cannot upgrade.

This is a deliberate split between two things that are easy to conflate: **the image is
reproducible and rebuilt nightly**, and **this machine updates when told to**. The first
is what keeps the base current without anyone remembering to build; the second is what
keeps a reboot from becoming a surprise.

The same reasoning is why noctalia's `auto_update` is `"none"`. A shell that updates
itself in the background is no longer the thing the commit says it is. Installing when
asked is fine, which is what `enabled` does.

## How updates reach the machine

```bash
just update-check   # metadata only, nothing downloaded
just update         # stage; applies at the next reboot
just update-now     # stage and reboot straight into it
```

Because the nightly tracks upstream Bazzite, this is *also* how kernel, mesa and NVIDIA
driver updates arrive. There is no second channel.

## Tags

CI publishes `:sway` and a dated `sway-YYYYMMDD`. Both are the same manifest, so they
share one digest and one signature covers both.

There is deliberately **no `:latest`**. Deployments track the `:sway` ref, and a bare
`bootc switch ghcr.io/asinglebit/bazzite-sway` resolving to some other tag would be a
silent change of what the machine follows. Without a tag the pull simply fails and tells
you to name what you meant.

## The ref trap

`bootc upgrade` re-resolves whichever ref the deployment already carries. That is fine on
a machine installed from GHCR, and useless on one that got here via `just switch` — that
one follows `ostree-unverified-image:containers-storage:localhost/bazzite-sway:sway`, its
own local podman storage, and will never see a CI build however many times the workflow
runs.

`bootc status` says which. If the ref reads `containers-storage`, moving onto GHCR is a
one-time `bootc switch`, after which plain `bootc upgrade` is enough forever.

Take that first switch **unverified**, deliberately. A locally built machine has no
`asinglebit` rule in `policy.json` and no public key, because [[Build and release|a local
build skips the trust setup]] — so an `ostree-image-signed:` ref matches nothing and falls
through to the `insecureAcceptAnything` catch-all. It would pull unverified while
*looking* verified. Use `just bootstrap-remote`, reboot, confirm the pubkey landed, then
move to `just switch-remote`.

## Verifying that verification is on

Two of the three obvious checks can pass while verification silently falls through to the
catch-all. Only a negative control proves it: point the same policy at the *wrong* key and
confirm the pull is refused in about a second. The repo README has the exact commands.

`skopeo inspect` is no use here — it does not apply the policy at all.

## What rolls back, and what does not

A rollback restores the **image**. It does not restore `dotfiles/`, which is a git
checkout, or `flatpaks.list`'s apps, or anything under `~/.var/app`. The two roll back
separately and neither knows about the other.

Related: [[Build and release]], [[Operations]], [[Recovery]], [[Decisions]].
