# Operations

## Once, on a new machine

```bash
just insurance      # pin the running deployment, disable uupd
just build          # ~40 min cold
just switch
sudo systemctl reboot
```

`insurance` pins the current deployment so a rollback cannot later be reverted out from
under you, and prints the deployment list worth recording.

Two things about the build that are easy to get wrong: it must run as **root**, because
bootc reads root's containers-storage, and never `--squash`, which rewrites layer diffids
and produces the `Missing ostree.final-diffid` failure `just rechunk` exists to fix.

Rebuilding the *same* tag then needs `bootc upgrade`, not `switch` — `switch` compares the
image reference rather than its content and would leave the previous build staged.
`just switch` detects that and falls through automatically.

## Per-user setup

The image carries the desktop and no per-user config.

```bash
just link-dotfiles && swaymsg reload   # this repo's desktop config
just install-flatpaks                  # the apps on top of Bazzite's own set
just greeter-avatar                    # bind the login-screen avatar to this account
just check-shell-config                # optional: validate the config as committed
```

All four are idempotent and all four are re-run after a reinstall. `link-dotfiles` backs
up anything in the way with a timestamp and prunes symlinks this repo no longer ships —
which matters most in `sway/config.d/`, where a dangling link stops sway loading at all.

The desktop works without any of it, on stock defaults. What they add is the palette, the
monitor layout, the [[Workspaces|per-screen workspaces]], the plugins and the apps.

## Day to day

| Command | Does |
| --- | --- |
| `just update-check` | Is there anything new? Metadata only. |
| `just update` | Stage the newest published image; applies at the next reboot. |
| `just status` | `bootc`, `rpm-ostree` and `ostree` status together. |
| `just install-flatpaks` | Reconcile apps against `flatpaks.list`. |
| `./verify.sh` | Post-boot checks against the running session. |

See [[Cadence]] for what each of those actually moves.

## verify.sh

The tier of checks that needs a live session — a running compositor, a GPU, a seat. It
exits non-zero if anything critical failed, and reports three levels: `PASS`, `FAIL`, and
`WARN` for things that are not wrong but are not what the repo says either.

The distinction it makes most usefully is *where a value came from*. A theme key that is
correct but written in dconf rather than served by the image override is a warning, not a
pass, because it means [[Theming|the image override is being outranked]] and would stop
working on another machine. Same for a noctalia setting that came from the GUI rather
than from `dotfiles/`.

It also does the cross-checks nothing at runtime would notice: that the palette still
matches between shell and greeter, that the hardware thresholds in the plugin still match
`[system.monitor]`, and that `workspace-block.sh` still agrees with an independently
recomputed block.

Some warnings are expected on a working machine. Read them once and learn which.

## Previewing the login screen

`just greeter-preview` runs the real greeter nested in the current session against a fake
greetd — log in as `user` / `password`, the sum is 9. It uses software rendering, so judge
layout there and not exact colours, and it touches no DRM at all: whether the login screen
works on this GPU is still a reboot away.

Related: [[Recovery]], [[Cadence]], [[Build and release]].
