# Screen capture indicator

A macOS-style purple dot for the Omarchy bar while your screen is being
recorded, shared or captured. Click it to see recent captures.

By [hanssound](https://github.com/hanssound). [0BSD license](LICENSE).

## What it shows

- A bright purple dot during capture, faded for 15 seconds afterward.
- Up to 20 recent sessions: app names, start time, duration and capture target.
- `via claude` or `via codex` when a detected tool was started by one of those agents.
- Short captures marked as snapshots; pauses under three seconds merge into the same session.
- One shared watcher across monitors, with history available on each bar.

Detection combines Hyprland's `screencastv2` events, PipeWire portal streams,
known capture processes and recent Wayland clients. A socket watcher also
detects GPU Screen Recorder's KMS captures. It probes once at startup, on
capture events, and every two seconds during capture. There is no idle polling.
Closed history popups build no session rows, and unchanged probes leave history alone.

## Requirements

Omarchy Quattro (4.x), its Quickshell shell, and a Hyprland version that emits
`screencastv2`. Runtime commands come from `bash`, `coreutils`, `procps-ng`,
`iproute2`, `pipewire`, `jq` and `inotify-tools`.

On a standard Omarchy installation, check that the extra tools are installed:

```bash
omarchy pkg add inotify-tools jq
```

## Install

```bash
omarchy plugin add https://github.com/hanssound/omarchy-screencast-indicator.git --enable
```

The widget appears in the right section. Move it through Omarchy's bar settings
or with:

```bash
omarchy bar move hanssound.screencast-indicator --section center
```

## Settings

`linger` is the number of seconds the faded dot stays after capture ends.
Its default is 15; use 0 to hide immediately. In `~/.config/omarchy/shell.json`,
replace this widget's string in `bar.layout` with an object:

```json
{ "id": "hanssound.screencast-indicator", "linger": 30 }
```

Layout/settings changes reload automatically. Restart the shell after changing
service code; its shared service stays loaded across normal plugin reloads:

```bash
omarchy restart shell
```

## Privacy

The plugin never captures pixels, reads the clipboard, opens saved captures,
or makes network requests. It reads local capture events, PipeWire metadata,
process names and ancestry, and Unix socket metadata to identify capture tools.
Hyprland can supply a captured window's title, which appears in the popup.

History stays in memory and disappears when the shell restarts. Nothing is
written to disk or sent anywhere. App names and targets are displayed as plain
text, including names that resemble HTML.

This is an indicator, not an access-control mechanism. Very short screenshots
can finish before their app is identified. The recent-client fallback can
also name an unrelated app opened within five seconds of a capture. Hyprland
reports targets rather than unique client ids, so simultaneous captures of
the same target cannot always be distinguished. KMS detection depends on GPU
Screen Recorder creating `/tmp/.gsr-kms-socket-*`.

## Update or remove

```bash
omarchy plugin update hanssound.screencast-indicator
omarchy plugin remove hanssound.screencast-indicator
```

## Check and package

With Node.js, Python 3 and the runtime dependencies installed:

```bash
bash prepare-release.sh
```

This checks the model, probe fixtures, actual service offscreen, Omarchy
manifest, and release files for private paths and credential patterns. Tests
use synthetic metadata and sleeping processes; they never capture the screen.
The archive in `.release/` contains only the files allowed by `.gitignore`.
Local project notes, Git metadata, machine configuration and capture history
are excluded. Archive ownership and timestamps are normalized.
