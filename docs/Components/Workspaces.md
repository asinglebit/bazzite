# Workspaces

Every screen owns its own block of ten. The leftmost screen has workspaces 1–10, the next
11–20, and so on — so `$mod+1` means "this screen's first workspace" and a number key
never moves focus to the other monitor.

## Derived, never declared

There are deliberately no `workspace N output` pins anywhere. A pin nails one number to
one connector, and connector names change when you swap ports; one leftover pin would
strand a single workspace while the other nine follow focus.

Instead `dotfiles/sway/workspace-block.sh` works the block out on **every keypress**, from
the outputs sway reports, sorted left to right by position. Same input, same answer, and
nothing to update when a monitor moves.

```
workspace-block.sh switch <1-10>    $mod+N
workspace-block.sh move   <1-10>    $mod+Shift+N, moves the window and follows it
workspace-block.sh print  <1-10>    says which workspace it would pick
workspace-block.sh reconcile [id]   tidy-up at startup and on reload
```

It uses `jq` rather than `python3` because python needs about 17ms to start against jq's
5ms, and this runs on a keypress. If sway cannot be reached it falls back to the plain
binding, so the key is never dead.

`reconcile` runs from `exec_always` in `10-outputs.conf`: it sends any workspace sitting
on the wrong screen back to its own, then gives any screen showing someone else's
workspace one of its own. Only the first run of a session ends on the main monitor; a
reload leaves focus where it was.

## Monitors

`dotfiles/sway/config.d/10-outputs.conf` names monitors by **EDID identifier**, not
connector, for the same reason. The 4K panel has exactly twice the pixel density of the
1080p one, so `scale 2` makes a window the same physical size on both.

`xwayland-primary.sh` marks the main monitor as the XWayland primary so X11 apps like
Steam open there — wlroots never sets one and sway has no directive for it, hence
`exec_always`.

## The bar switch

`$mod+period` runs `dotfiles/sway/noctalia-bar-toggle.sh`, which writes `enabled = false`
into noctalia's settings file rather than calling `noctalia msg bar-toggle`.

The reason is [[Compositor|blur]]: `bar-toggle` only *hides*, and a hidden bar keeps its
layer surface, which SwayFX goes on blurring — so the top strip stays frosted with nothing
drawn in it. Disabled, the surface is gone and the top edge is wallpaper again.

Writing the setting also means the state survives a restarted shell. It writes the same
file the settings window writes, with a rename rather than an edit in place, because
noctalia is watching and a half-written file is a parse error that costs the whole
settings layer.

`noctalia-bar-toggle.sh print` says which bars are currently on.

## What goes wrong

- **Unplugging a screen strands its ten** on the survivor until it is back. `verify.sh`
  warns rather than failing, and `swaymsg reload` repairs it.
- **A helper that is not executable** fails inside sway's `sh -c` with nothing on screen —
  the key just does nothing. `verify.sh` checks the mode, not just the symlink.
- **The bar drawing both screens' blocks** means `show_all_outputs` is not `false` in
  `30-bar.toml`.

The sorting rule is written in both the helper and `verify.sh`, so the check is a genuine
second opinion: it recomputes the block independently and compares.

Related: [[Compositor]], [[Shell]], [[Operations]].
