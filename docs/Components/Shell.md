# Shell

[noctalia](https://docs.noctalia.dev/noctalia/). Everything the desktop is made of except
the compositor, from one package and one TOML directory.

## What is behind the one process

Bar, launcher, notifications, control centre, session menu, lock screen, OSD, clipboard
history, screenshots, idle handling, the NetworkManager secret agent, the Bluetooth agent,
the StatusNotifier tray host — and the **only polkit agent on the machine**.

There is no fallback for any of it. When noctalia dies the session is a compositor and a
wallpaper: no bar, no notifications, no lock, and `pkexec` *hangs* rather than failing, so
`ujust` and `bazzite-user-setup` block forever. Nothing prints an error, because the thing
that would show you the error is the thing that died.

`$mod+Return` still opens a terminal — that binding is in `/etc/sway/config` and does not
go through the shell. That is what makes it recoverable. See [[Recovery]].

Because so much rides on it, `build_files/18-noctalia-shell.sh` greps the binary for each
D-Bus name it must own, and `verify.sh` checks `is-active` on the unit before anything
else.

## Fedora, not Terra

Unlike [[Login screen|noctalia-greeter]] and ghostty, the shell comes from Fedora proper.
The build asserts `%{VENDOR}` is `Fedora Project`, because a Terra package winning the
same name would be a different version line arriving silently.

## Started by systemd

`system_files/usr/lib/systemd/user/noctalia.service`, wanted by `sway-session.target`.

Not sway's `exec`, so it restarts when it dies and has somewhere to log. The symlink into
`sway-session.target.wants` is **shipped directly** rather than created by `systemctl
enable`, because enable writes to `/etc` and presets only apply to users created
afterwards.

`ExecStart` is the bare binary, deliberately not `noctalia --daemon`. `--daemon` returns
once the shell is up, which under systemd is wrong twice: the supervised process would
exit immediately so `Restart=on-failure` would watch a corpse, and the real shell would
run outside the unit's cgroup. The build asserts the `ExecStart` line.

## Configuration, and what outranks what

Three layers, last one wins:

1. noctalia's built-in defaults
2. `~/.config/noctalia/*.toml` — this repo, via `dotfiles/noctalia/`
3. `~/.local/state/noctalia/settings.toml` — **written by the settings window**

That third file is the one surprise in the system. It is not version controlled, it cannot
be found by reading `dotfiles/`, and it beats everything here. `verify.sh` reports it if
it exists; deleting it hands control back.

`$mod+period` writes into that same file on purpose — see [[Workspaces|the bar switch]] —
so deleting it also turns every bar back on.

The committed config can be validated without deploying it: `just check-shell-config`
points noctalia at a throwaway state directory precisely so a GUI override cannot mask
whether the commit itself is valid.

## Plugins

Six enabled, in `dotfiles/noctalia/50-services.toml`. One lives in this repo,
`asinglebit/bazzite-sway`, and carries four widgets noctalia has no built-in for:

| Widget | Shows |
| --- | --- |
| `hardware` | CPU, memory and package temperature as one glyph; the sensor is found by name, not index. |
| `swaymode` | The current sway mode, hidden in the default mode. |
| `scratchpad` | How many windows are in the scratchpad — with no borders, the only sign the binding did anything. |
| `failedunits` | Invisible until a systemd unit fails. |

Its thresholds are constants in `hardware.luau` rather than manifest settings, because the
manifest's setting schema is the one thing here that cannot be checked offline and a bad
key would fail the whole plugin, taking all four widgets with it. They mirror
`[system.monitor]` in `50-services.toml`, and `verify.sh` checks the two agree.

The other five are fetched from GitHub at first use and cached outside the image:
untracked and unpinned. `auto_update = "none"`, so nothing re-fetches on its own — see
[[Cadence]].

Related: [[Compositor]], [[Theming]], [[Operations]].
