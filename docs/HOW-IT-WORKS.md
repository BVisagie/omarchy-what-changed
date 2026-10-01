# How What Changed works

What Changed rebuilds each `omarchy update` from `/var/log/pacman.log` and
Omarchy's own state files. This page describes how sessions are found, what is
inferred, and which Omarchy behaviour the plugin depends on. For installation and
everyday use, see the [README](../README.md).

## How a session is found

This is the part worth understanding, because it is what lets the plugin work
with no hook and no capture step.

Every `omarchy update` begins by running
`pacman -Sy --noconfirm archlinux-keyring` (from `omarchy-update-keyring`), and
that lands in `/var/log/pacman.log`. **That line is the head of a session.**
The log order splits sessions at each such invocation. Recognized update
commands are admitted within one hour of the last recognized activity; accepted
commands extend that rolling window. Matching is heuristic: a manual command
with the same shape can be indistinguishable from an update step.

| Invocation | Recognition |
|---|---|
| `pacman -Sy --noconfirm archlinux-keyring` | Session start and update-keyring |
| `pacman -S --noconfirm --needed [--] omarchy-keyring` | First-run keyring install |
| `pacman -Syu … --overwrite /usr/share/omarchy/*` | System package update |
| `pacman -U … --config /etc/pacman.conf … /.cache/yay/…` or `/.cache/paru/…`, without `--needed` | AUR update |
| `pacman -D … --config /etc/pacman.conf …` | AUR dependency marking |
| `pacman -Rns …` without `--noconfirm` | Orphan sweep |

## Migration inference and nearby changes

Other pacman transactions are candidates regardless of command form, including
pkg-add, pkg-drop, AUR installs with `--needed`, and direct replacements with
`--ask 4` or `--ask=4`. Their fixed window ends at the earlier of the next session
start and the last recognized update activity plus 1800 seconds. Candidate
activity never extends that bound or the rolling recognition window.

A completed candidate starting at or after the final completed system-upgrade
transaction and ending at or before the newest migration completion marker is
`migration-inferred`. Both ends include equal-second timestamps. Markers
establish a migration-phase bracket, not the caller of a command: concurrent
manual commands cannot be ruled out. When the system upgrade has nothing to
do and opens no transaction, its last recorded log line is the lower bound;
a migration completion marker supplies the evidence that the updater proceeded
after that step. Missing markers, an unfinished candidate, or a system
transaction that started without completing cannot establish that inference.

Inferred rows count toward the update and reboot inference. Omarchy and
reboot-related rows stay in their usual groups and carry an `(inferred)` label;
remaining rows appear under **Migration package changes (inferred)**. All other
candidates appear under **Other changes during this window** with separate
counts. They do not change primary totals, that session’s release jump or reboot
inference. AUR provenance comes from the invocation and cache path, independently
of attribution.

The version known at the start of each session comes from all earlier recorded
`omarchy`/`omarchy-dev` package events, including installer transactions, manual
changes and channel switches outside update windows. Later uncertain or manual
changes can seed the next session without rewriting an earlier session’s jump
or claiming that those packages came from the update.

Package summaries and version transitions use all primary events before the
500-row display budget. Omarchy and reboot-related facts are retained beyond
the bulk budget. A stable/dev replacement uses the removed source version and
final installed destination; removal without replacement makes subsequent
versions unknown. Same-release reinstalls and unsupported development versions
do not produce release-note or compare links.

A rare migration can call `omarchy-update-keyring` mid-update. It is
indistinguishable from a separate update attempt that stops before `-Syu`, so
1.1.0 preserves two reconstructed sessions. The second segment has no system
upgrade bracket and its candidate rows stay uncertain. No event belongs to both
segments, including entries at the same second as the boundary.

Retained pacman history bounds what can be reconstructed; rotated-away log
entries and missing migration markers cannot be recovered by this plugin.

## Why not a post-update hook

Because a hook **structurally cannot see the whole update**.
`/usr/share/omarchy/bin/omarchy-update` calls `omarchy-hook post-update` *before*
`omarchy-update-aur-pkgs`, `omarchy-update-mise`, `omarchy-update-orphan-pkgs`
and `omarchy-update-restart`. A hook-written record's AUR list is empty by
construction. Reading the log after the run includes the later package
transactions and works retroactively, which is why a fresh install already has
your history in it.

## What is derived, and how honestly

| Field | Source |
|---|---|
| Packages and versions | Recorded events in `/var/log/pacman.log`; attribution is recognized or inferred as described above |
| AUR provenance | Inferred from the pacman invocation and yay/paru cache path |
| Omarchy version | All earlier `omarchy`/`omarchy-dev` events seed the known package/version at the session start. Only primary session events define its jump from first source to final destination. Active-package removal clears the known version; today's installed version is never substituted for missing log evidence |
| Migrations | Completion mtimes of `~/.local/state/omarchy/migrations/*.sh` inside the fixed window |
| Reboot needed | Primary reboot-class event timestamps compared with `btime` in `/proc/stat`: pending, rebooted, unknown or not indicated. This establishes whether a reboot followed, not which kernel booted |
| Current system reboot request | The separate `reboot-required` marker compared with boot time; an older marker is stale. `omarchy-update-restart` does not clear it. Omarchy reboot/shutdown clear it; other reboot paths may leave it behind |
| Transaction completeness | `incomplete` means an owned package transaction started without completing. Pacman history cannot establish whole-update success |
| Channel | `omarchy-channel-current`, which reports *now*, not then |
| `mise` | Not recorded per-session anywhere, so not claimed |
| Repo | Not in `pacman.log`, and `pacman -Si` needs a sync, so not claimed |

`counts.aur` and the AUR group answer different questions. The count is
provenance — how many packages in that session came from the AUR — while the
group lists only the AUR packages not already shown under Apps or Omarchy. A
session that upgraded `brave-origin-bin` and `ai-usagebar-bin` reports
`counts.aur: 2` and shows one row under AUR, because Brave is a named app.

## Omarchy integration points

Compatibility evidence dated **1 October 2026**:

| Omarchy | Evidence and limits |
|---|---|
| Stable 4.0.4 | Six-event real update fixture, migration completion markers, kernel families, command forms and pinned manifest validator |
| `quattro` at `c05d901` | Inspected command forms (including optional `--`) and pinned manifest validator; early shell restart can leave the 1.1.0 widget stale until manual refresh |

These are inspected snapshots, not a guarantee for future upstream changes.
Full desktop interaction and multi-monitor checks remain pre-release checks.
The integration points are:

| Depends on | Where | Used for |
|---|---|---|
| `pacman -Sy --noconfirm archlinux-keyring` runs first | `bin/omarchy-update-keyring` | The session start marker |
| Stable restarts near the end; inspected upstream restarts before later steps | `bin/omarchy-update-restart` | The widget refreshing without a poller |
| The orphan sweep omits `--noconfirm` | `bin/omarchy-update-orphan-pkgs` | Telling the sweep apart from `omarchy pkg remove` |
| The AUR step runs `yay -Sua`, never `--needed` | `bin/omarchy-update-aur-pkgs` | Telling it apart from `omarchy pkg aur add` |
| The post-update hook fires before AUR/mise | `bin/omarchy-update` | Why there is no hook |
| Migration markers are touched after success | `bin/omarchy-migrate` | Attributing migrations by mtime |
| The menu merges a user JSONC extension | `shell/plugins/menu/Menu.qml` | The `Update › What changed` entry |
| Third-party widgets receive `bar`, `moduleName`, `settings`, and `bar.shell` exposes `summon` | `shell/plugins/bar/Bar.qml`, `shell/Ui/PluginBarApi.qml` | The widget opening the overlay in-process |
| For a `bar-widget` plugin, "enabled" means placement in `bar.layout` | `shell/services/PluginRegistry.qml` | Why enabling needs `--section` |
| The panel Loader injects `shell` and `manifest`, and the scoped `shell.hide` accepts the plugin's own id | `shell/shell.qml`, `shell/Ui/PluginShellApi.qml` | Dismissing the overlay unloads it, so `keepLoaded: false` keeps meaning something |
