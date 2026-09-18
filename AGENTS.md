# AGENTS.md

Guidance for AI agents (and humans) working on this repository.

## What this is

An [Omarchy](https://omarchy.org) shell plugin: a Quickshell bar widget with
media controls and synced lyrics. It follows any MPRIS player, fetches lyrics
from LRCLIB, and can romanize and translate them. Everything user-visible is in
English; the plugin has no personal data, no credentials and no bundled
binaries.

## Repository layout

```
manifest.json       plugin manifest: id, kinds ["bar-widget"], settings schema
Bar.qml             entry point: bar item (glyph + scrolling line + progress
                    hairline), the popup, and the settings page
LyricsView.qml      the themed card: cover art (hover play/pause), track header
                    with transport and hover-revealed volume, lyrics list, seek bar
SliderBar.qml       knobless slider used for both the volume and the seek bar
PlayerService.qml   MPRIS player selection, media control wrappers, LRCLIB
                    lookup, sync clock, romanization and translation
LrcParser.js        LRC parser (multiple timestamps, offset, binary search)
romanize.py         transliteration helper: pykakasi > kakasi > ICU uconv
probe.qml           dev tool: loads service + card outside the bar (see below)
install.sh          install/update/remove into the shell's plugin directory
tests/lrc_test.js   parser tests, run with node
preview.png         marketplace preview image
```

The installed copy lives at
`~/.config/omarchy/plugins/io.github.enrell.super-player/`; `install.sh` is the
only supported way to sync it.

## Conventions

- QML style follows Omarchy's own plugins: two-space indent, no semicolons,
  `readonly property` for derived values, comments in English.
- Theme everything through the shell tokens — `import qs.Commons` (`Color`,
  `Style`, `Util`, `Border`) and `import qs.Ui` (`PopupCard`, `BorderSurface`,
  `Button`, `Dropdown`, `PanelSlider`, `PanelHero`, `PanelSeparator`). Never
  hardcode colors, spacing or fonts.
- The bar widget receives `bar`, `moduleName` and `settings`; persist changes
  with `bar.shell.updateEntryInline(moduleName, entry)`.
- `PlayerService.qml` must stay free of `qs.*` imports so it can be loaded and
  tested outside the shell.
- Keep the settings schema in `manifest.json` in sync with the settings page in
  `Bar.qml` (both list the same keys and defaults).

## Workflow

```bash
./install.sh --restart     # copy the sources into the shell and restart it
node tests/lrc_test.js     # parser tests
omarchy plugin validate .  # manifest validation
```

- **QML changes only take effect after `omarchy restart shell`.** A rescan
  (`omarchy-shell shell rescanPlugins`) re-reads manifests but keeps serving the
  previously compiled QML, which shows up as errors pointing at stale line
  numbers.
- Install the plugin as a **real directory**, never a symlink: Qt's QML loader
  gets confused by symlinked plugin directories (stale directory listings,
  `File name mismatch`).
- Load errors land in the shell log. Read it with a narrow grep, it is binary:
  `grep -a -o 'Plugin widget io.github.enrell.super-player failed:.\{0,200\}' <log>`.
  Logs live in `/run/user/1000/quickshell/by-id/<id>/log.qslog` (newest first:
  `ls -t`).

## Verifying changes

`probe.qml` loads the service and the card outside the bar, prints one line per
second and exits — much faster than restarting the shell:

```bash
ln -sfn /usr/share/omarchy/shell/Commons Commons     # dev only, git-ignored
ln -sfn /usr/share/omarchy/shell/Ui Ui
PROBE_SOURCE=org.mpris.MediaPlayer2.spotify PROBE_TICKS=20 qs -p probe.qml
```

Environment variables: `PROBE_SOURCE` (player to pin, default `Auto`),
`PROBE_ROMANIZE`, `PROBE_TRANSLATE`, `PROBE_VOLUME` (force the volume bar open,
useful for previews), `PROBE_TICKS` (seconds to run).

The probe window uses the Overlay layer, so it is visible even over a fullscreen
window. Screenshot it with `grim -g "X,Y WxH"`; OCR Latin text with
`tesseract` (add `-colorspace Gray -normalize` for dim text). `hyprctl layers -j`
lists layer surfaces and their geometry.

Runtime checks from the shell side:

```bash
omarchy plugin list | grep super-player      # enabled?
omarchy-shell super-player status            # JSON: player, track, lyrics, volume
omarchy-shell super-player next              # exercise the controls
```

## Gotchas learned the hard way

- `IpcHandler` needs `import Quickshell.Io`; without it the whole widget fails
  to compile with `IpcHandler is not a type`.
- `show` is a reserved function name in Quickshell's IPC (calling it prints the
  target listing instead of running it). Use `open`/`close`/`toggle`.
- A QML property holding an object literal needs parentheses:
  `property var x: ({ ... })`.
- Only one handler per signal is allowed; merge them
  (`onLinesChanged: { scheduleRomanize(); scheduleTranslate() }`).
- Anchors are not allowed on children of a `Row`/`Column` (the positioner owns
  their geometry). Size the child instead — that is why `SliderBar` gets
  `height: headerControls.height` so the row's top alignment centres its track.
- Two `Rectangle`s stacked in a positioner can silently collapse if the outer one
  animates its width; verify with pixels, not by eye
  (`magick card.png -crop WxH+X+Y txt: | grep -c <accent hex>`).
- `on<Property>Changed` does **not** fire for a binding's initial value. Anchor
  state from an explicit change (player appears) instead of relying on the first
  evaluation — this is why the sync clock also anchors in `onPlayerChanged` and
  why `onTrackKeyChanged` seeds the clock from the MPRIS position.
- LRCLIB's exact lookup returns HTTP 400 when `artist_name` is empty (mpv and
  some players report no artist), so the service skips straight to the free text
  search in that case, and any other non-200 falls through to the next endpoint
  instead of erroring out.
- The tick timer only runs while playing, so anything that moves the clock must
  also call `updateIndex()`.
- `PopupCard` requires a non-null `bar`; that is why the popup lives inside the
  bar widget and the probe renders `LyricsView` inside a `BorderSurface`.
- Bar widgets are not instantiated while the bar is hidden by a fullscreen
  window, so IPC targets from the widget can be missing until the bar is shown.

## Out of scope

- No API keys, tokens or personal data anywhere in the repo.
- No bundled binaries; `romanize.py` is plain text and only shells out to tools
  the user installed.
- Don't add dependencies to the plugin itself: it should work with nothing but
  the Omarchy shell, and degrade gracefully when the optional tools are missing.
