# CLI reference

`bin/what-changed` is the plugin's whole read model: the overlay runs only this
CLI and renders its JSON. The [README](../README.md#the-cli) covers the commands
and flags. This page covers session ids, exit codes and the `--json` contracts.

## Session ids

A session id may be given in full (`20260908T184129Z`) or as a prefix. Where a
prefix matches more than one session, the newest match wins.

## Exit status

| Exit | Means |
|---|---|
| `0` | Success |
| `3` | The log holds no update sessions yet |
| `1` | A real failure: missing or unreadable log, unknown command, no such session |

`3` exists so a caller can tell "this machine has never been updated" — a true
and complete answer — from "the log did not read". The overlay uses it to avoid
reporting a permissions problem as an empty history.

## JSON contracts

QML never inspects the system; it consumes these. Anything added here must also
be added to the matching `intake*` function in `Model.js`, or it will be dropped
on purpose.

### `what-changed sessions --json`

```json
{
  "schemaVersion": 1,
  "currentRebootRequest": "absent",
  "sessions": [
    {
      "id": "20260908T184129Z",
      "startedAt": "2026-09-08T20:41:29+0200",
      "finishedAt": "2026-09-08T20:47:11+0200",
      "label": "8 Sep 20:41",
      "channel": "stable",
      "incomplete": false,
      "source": "pacman-log",
      "isLatest": false,
      "omarchy": {
        "package": "omarchy",
        "from": "4.0.2-1",
        "to": "4.0.3-1",
        "jumped": true,
        "jump": "4.0.2-1 → 4.0.3-1"
      },
      "rebootRequired": true,
      "rebootStatus": "pending",
      "rebootReason": ["mesa", "linux"],
      "migrations": ["1788577553"],
      "counts": {
        "upgraded": 135, "installed": 5, "removed": 4, "downgraded": 0,
        "reinstalled": 1, "aur": 2, "total": 145, "omitted": 0
      },
      "nearbyCounts": {
        "upgraded": 0, "installed": 0, "removed": 0, "downgraded": 0,
        "reinstalled": 0, "aur": 0, "total": 0, "omitted": 0
      }
    }
  ]
}
```

Ids are the session start in UTC (`YYYYMMDDTHHMMSSZ`); `label` is local time for
display. `finishedAt` records only recognized update activity; candidate
transactions never advance it. `incomplete` means an owned pacman transaction
started without completing, not that the whole update succeeded or failed.

`counts` includes all `update-command` and `migration-inferred` events before
display truncation. `nearbyCounts` has the same operation-count shape for
`nearby-uncertain` events. Each `omitted` count describes only its own rows.
The `omarchy` object starts from all Omarchy package events logged before this
session, then reduces only its primary events. Outside or uncertain events do
not create a release jump for this session; they can establish the package and
version known when the next session starts. Installer history seeds the first
session, and removal of the active package without replacement leaves the next
version unknown. Internal version seeds are not exposed in the JSON contract.
`rebootStatus` is `pending`, `rebooted`, `unknown` or `not-indicated`;
`rebootRequired` is true only for `pending`. Historical `rebootReason` names remain
after a subsequent boot. Missing/unparseable boot or event timestamps, and an
equal-second boot/change timestamp, yield `unknown`.

`currentRebootRequest` is a separate top-level enum on sessions, show and status:
`pending`, `stale`, `unknown` or `absent`. Unknown includes an unreadable boot time
or equal-second marker/boot timestamps. It is displayed only in the overlay and
has no effect on unread state. Channel always reports the current machine channel.

### `what-changed show --json`

Group order is fixed and meaningful: `omarchy`, `reboot`, `apps`, `migration-packages`,
`migrations`, `aur`, `other`, `nearby`. A group with a `summary` states itself in one line instead of
listing rows. `other` is collapsed and carries `count` with no `items` until
`--expand other`.

```json
{
  "schemaVersion": 1,
  "currentRebootRequest": "absent",
  "session": { "…as above, minus events…" },
  "groups": [
    { "id": "omarchy", "title": "Omarchy",
      "items": [
        { "kind": "pkg", "op": "upgraded", "name": "omarchy",
          "from": "4.0.2-1", "to": "4.0.3-1", "aur": false,
          "attribution": "update-command", "occurredAt": "2026-09-08T20:42:02+0200" }
      ] },
    { "id": "migrations", "title": "Migrations",
      "summary": "9 migrations ran",
      "items": [ { "kind": "migration", "name": "1788577553" } ] },
    { "id": "other", "title": "127 other packages",
      "collapsed": true, "count": 127, "items": [] }
  ]
}
```

`op` is one of `upgraded`, `installed`, `removed`, `downgraded`, `reinstalled`.
Each package row has `attribution`: `update-command`, `migration-inferred` or
`nearby-uncertain`, plus its recorded `occurredAt` timestamp. Groups carry exact
`count` and display `omitted` values; an `explanation` qualifies inferred and
uncertain groups. `other` remains the sole expandable group. Priority package
facts are retained independently of the bulk budget, and nearby rows have a
separate display budget. `outputTruncated: true` appears at the top level when the expanded view would
have exceeded the output cap.

### `what-changed status --json` and `notes --json`

```json
{ "schemaVersion": 1, "unread": false, "currentRebootRequest": "absent",
  "lastRead": "20260909T082737Z",
  "newest": { "…a session, or null…" } }
```

`unread` is `newest.id !== lastRead`. An absent marker means first run: the
newest session is adopted so the bar starts quiet. An unreadable marker counts
as unread, because claiming "all read" would swallow a real one.

```json
{ "schemaVersion": 1,
  "status": "ok",
  "message": "",
  "releases": [ { "tag": "v4.0.3", "name": "v4.0.3",
                  "url": "https://github.com/omacom/omarchy/releases/tag/v4.0.3",
                  "body": "…markdown…" } ] }
```

`status` is `ok`, `partial`, `no-jump` or `unavailable`. `Model.parseNotes` adds
a `blocks` array per release — `h1`–`h3`, `p`, `li`, `code`, `quote`, `rule` —
which is what `NotesView.qml` renders.
