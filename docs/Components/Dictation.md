# Dictation

Press `$mod+x`, speak, press it again, and the words are typed into whatever window has
focus — terminal, browser, anything. [voxtype](https://github.com/peteonrails/voxtype)
records and transcribes; Whisper runs on the GPU on this machine, so no audio leaves it.
English and Russian, picked per recording.

## What the two presses do

1. `$mod+x` runs `voxtype record toggle`, which finds the daemon idle and starts a
   recording. The daemon switches sway into the `dictating` mode — which the bar's mode
   widget shows — and noctalia's privacy OSD shows the microphone in use.
2. The second `$mod+x` lands in the `dictating` mode, which carries its own copy of the
   binding, because a sway mode sees no binding from outside it. The same command now
   finds the daemon recording and stops it.
3. Voice-activity detection drops a recording with no speech in it. Without that, Whisper
   fills silence with invented text — in Russian, typically "Продолжение следует...".
4. Whisper transcribes, choosing only between English and Russian, because choosing from
   all 99 languages it can misdetect short phrases.
5. voxtype switches sway into the `typing` mode, types the text with `wtype`, and returns
   to the default mode. It returns on every path, cancel and no-speech included.

F12 cancels a recording, and gets out of either mode if voxtype dies halfway.

## Where each part lives

| Part | Where | Layer |
| --- | --- | --- |
| The binary | `/usr/bin/voxtype`, from `build_files/36-voxtype.sh` | Image |
| The unit | `system_files/usr/lib/systemd/user/voxtype.service` | Image |
| Settings: model, languages, hooks | `dotfiles/voxtype/config.toml` | `~/.config` |
| Binding and the two modes | `dotfiles/sway/config.d/40-bindings.conf` | `~/.config` |
| The model, 1.6 GB | `~/.local/share/voxtype/models/` | Per user, `voxtype setup --download` |

The settings are in `dotfiles/` because they are about this person and this GPU — the
languages spoken, a model sized for 12 GB of VRAM.

## The choices

**The Vulkan binary, not the RPM.** The release RPM carries every CPU and GPU variant,
358 MiB, and picks one by rewriting `/usr/bin/voxtype`, which is read-only here. The
Vulkan build alone is 63 MiB, needs no CUDA toolkit, and runs on any vendor's GPU. It is
pinned by version and checksum, like the other downloads.

**`toggle` in both modes.** Whether a press starts or stops is decided by the daemon's
own state rather than by sway's mode, so the key still works when the two disagree. A
`swaymsg reload` mid-recording puts sway back in the default mode, where a `record start`
would be ignored and the recording would run on to voxtype's 60-second cap.

**Inert until configured.** voxtype's built-in defaults read the keyboard through
`/dev/input` and exit without the `input` group. So the unit carries
`ConditionPathExists=%E/voxtype/config.toml`: with no linked config it does not start,
rather than restarting every five seconds forever.

**Never the `input` group.** It would let voxtype read every keystroke on the machine.
Sway's own bindings drive it instead. The cost is the `typing` mode: voxtype's built-in
wait for released modifiers needs that same `/dev/input` access, so without the mode a
Super still held as the text arrives would turn each letter into a shortcut.

**`gpu_isolation`.** The model loads in a subprocess when recording starts, while you are
still speaking, and is gone once the text is typed, so a game never shares VRAM with an
idle 1.6 GB model. A warm transcription of a few seconds of speech takes about a third of
a second on the 4070 Ti.

**Quiet logging.** At its default level the daemon writes every transcript to the
journal, so the unit runs it with `-q`, which logs errors only.

## What goes wrong

- **`$mod+x` does nothing.** The config was not linked when the session started, so the
  unit stayed inert. `just link-dotfiles`, then `systemctl --user restart voxtype`.
- **The first recording fails with a missing model.** `voxtype setup --download` has not
  been run for this user.
- **Sway is stuck in `dictating` or `typing`.** voxtype died mid-recording. Press F12.
- **A long dictation is typed before the second press.** voxtype stops a recording at
  60 seconds (`max_duration_secs` under `[audio]`) and types what it heard. Press `$mod+x`
  again to carry on.
- **The config stopped following the repo.** `voxtype configure` saves by swapping a new
  file in, which replaces the symlink. `verify.sh` warns, and `just link-dotfiles` backs
  the file up and links the repo's copy again.

voxtype has no background update check, only a manual `voxtype check-update`, so it
changes when the pin in `36-voxtype.sh` does and at no other time.

Related: [[Compositor]], [[Shell]], [[Operations]], [[Cadence]].
