# Working on What Changed

For contributors and coding agents. Everyday use is in the
[README](../README.md), how sessions are reconstructed is in
[How it works](HOW-IT-WORKS.md), and the CLI's JSON contracts are in the
[CLI reference](CLI.md).

## Design rules

These are invariants, not v1 scope limits. **Changing any of them changes what
the plugin is**, so treat them as requirements rather than preferences.

1. **Never signals pending updates.** `omarchy.system-update` owns that. No
   badge, no count, no number on the widget — a single glyph or nothing.
2. **Never runs an update.** Read-only, no sudo, no pacman lock, no key that
   starts one.
3. **Not a poller.** No timers. Every refresh is driven by a file changing or
   the shell restarting.
4. **QML renders, the CLI knows.** No pacman, git or network calls from QML.
   Every `Process` command is a fixed argv array — never a shell string.
5. **Honest over clever.** `unknown` beats a wrong checkmark. Anything derived
   rather than observed is labelled as derived.
6. **Untrusted input.** Package names come from a log and release bodies from
   GitHub. Everything is `Text.PlainText`; intake rebuilds objects from known
   fields only; every string is control-character flattened and length-capped.

## Out of scope

Not a backlog — these are things the plugin declines to do, and a change that
adds one is a change to what it is:

- **Anything about pending updates**: scanning for them, listing them, an apply
  button, or a badge. That is `omarchy.system-update`'s job.
- **Arch news, `.pacnew` handling, snapper diffs, AI summaries.** Other plugins
  cover these and cover them better.
- **`mise` results.** No available source records them per session, so claiming
  them would mean guessing.

Per-bullet `landed` / `not installed` / `n/a here` annotations on release notes
are wanted, but only once they can be right: a wrong checkmark is worse than an
honest `unknown`.

## Repo map

| File | Role |
|---|---|
| `bin/what-changed` | The whole read model. bash + jq + awk. Parses the log, groups, fetches notes, owns the read marker |
| `Model.js` | Intake and formatting for QML. Sanitises CLI output, parses Markdown into blocks, formats headers and counts |
| `Overlay.qml` | The summoned surface: tab state, keys, `Process` wiring, session navigation |
| `SessionHeader.qml` | The header line and the prev/next stepper |
| `MachineView.qml` | Grouped package list. Renders what the CLI bucketed; decides nothing itself |
| `NotesView.qml` | Release-note blocks |
| `BarWidget.qml` | The unread marker |
| `manifest.json` | Plugin manifest. Also the single source of truth for the version |
| `test/sessions.test.sh` | CLI tests against a fixture log. No network |
| `test/model.test.js` | Intake, sanitising and formatting tests |
| `test/accuracy.test.py` | Accuracy acceptance checks, including the minimized real 4.0.4 fixture |
| `test/requests.test.js` | Overlay lifecycle checks with controlled callback ordering |
| `test/runtime.test.py` | Actual Quickshell cancellation and overlapping request checks, in an isolated offscreen shell |
| `test/fixtures/pacman.log` | A synthetic log: one full update, one thin one, plus manual pacman calls that must **not** be attributed |
| `docs/` | How it works, the CLI reference and this page |

## Architecture

```
/var/log/pacman.log ───────────────────────┐
~/.local/state/omarchy/migrations/ ────────┤
~/.local/state/omarchy/reboot-required ────┤
                                           ├──→ bin/what-changed ──→ JSON
~/.cache/…/releases/  (GitHub, cached) ────┤                          │
~/.local/state/…/last-read ────────────────┘                          │
                                                                      ▼
                        Overlay.qml / BarWidget.qml  ──→  Model.js  ──→  views
```

The CLI is the seam. If Omarchy ever grows a first-party `omarchy update log`,
this plugin becomes a viewer over it by changing one layer.

## Testing

```bash
./test/sessions.test.sh      # CLI: parsing, grouping, marker, failure modes
node test/model.test.js      # intake, sanitising, Markdown blocks, formatting
python3 test/accuracy.test.py # migration bounds, versions, exact counts, boot timing
node test/requests.test.js   # superseded callbacks and both completion orders
python3 test/runtime.test.py # isolated offscreen Quickshell request/cancellation acceptance
omarchy plugin validate .
/usr/lib/qt6/bin/qmllint -I /usr/share/omarchy/shell *.qml
```

None of these suites touches the network — `curl` is shimmed to fail inside
`sessions.test.sh`, so an accidental fetch shows up as a failure rather than a
slow, flaky pass. The tests use plain scripts and Python's standard library.
Python, Node and Quickshell are test tools; Python and Node are not runtime dependencies.

Runtime evidence on 1 October 2026: the isolated Quickshell test confirmed
`running = false` sends SIGTERM. The handler exited with code 23, and stdout,
stderr, then exit callbacks arrived in that order. Delayed A→B→C show, notes and
compare requests settled on C; controlled lifecycle tests also cover exit before
collectors. The complete overlay loaded against installed 4.0.4 components and
read the six-event real fixture. QML lint still reports import/type and
unqualified-access warnings; static lint and this load check do not establish
visual layout, menu/bar interaction, dismissal or multi-monitor behavior. Those
checks remain required before publishing.

The CLI honours environment overrides, which is what makes it testable:

| Variable | Overrides |
|---|---|
| `WHAT_CHANGED_PACMAN_LOG` | `/var/log/pacman.log` |
| `WHAT_CHANGED_STATE_DIR` | Omarchy's state dir (migrations, reboot marker) |
| `WHAT_CHANGED_STATE_HOME` | This plugin's own state dir (the read marker) |
| `WHAT_CHANGED_CACHE_DIR` | The release-note cache |
| `WHAT_CHANGED_OWN_WINDOW` | Seconds a session may still claim a recognized command after its last recognized activity (default 3600) |
| `WHAT_CHANGED_PROC_STAT` | Boot-time source (default `/proc/stat`); missing/invalid `btime` means unknown |
| `WHAT_CHANGED_REBOOT_MARKER_EPOCH` | Epoch seconds for an existing reboot marker, replacing its mtime for deterministic tests |

## Local development loop

The plugin runs from `~/.config/omarchy/plugins/<id>/`, so iterate by syncing and
restarting the shell:

```bash
DEST=~/.config/omarchy/plugins/io.github.bvisagie.what-changed
cp *.qml Model.js manifest.json "$DEST/" && cp bin/what-changed "$DEST/bin/"
omarchy-restart-shell

omarchy-shell shell summon io.github.bvisagie.what-changed
journalctl --user --since "1 minute ago" | grep what-changed
```

Two things that will otherwise cost an hour:

- **Quickshell caches compiled QML.** After an edit that changes a type, a plain
  rescan can keep serving the stale compile, so an error you already fixed keeps
  reappearing. `omarchy-restart-shell` is the reliable move.
- **`implicitHeight` is read-only on `Column`.** Assigning it fails the whole
  component with `Type <X> unavailable`, which reads like a missing import.

To exercise the widget without waiting for a real update:

```bash
"$DEST/bin/what-changed" mark-read 20260908T184129Z   # an older id → icon appears
"$DEST/bin/what-changed" mark-read                    # newest → icon clears
```

The icon reacts within a second; the marker `FileView` does not need a restart.
