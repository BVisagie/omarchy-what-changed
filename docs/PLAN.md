# What Changed — design brief

The plan this plugin was built from, kept as the record of *why* it is shaped
this way. Anything here that the code contradicts, the code wins.

## Job

After `omarchy update`, answer "what just happened on *this* machine?", then
show the official Omarchy release notes for the version jump actually taken.

`omarchy update` is a black box once it finishes. One run upgrades Omarchy *and*
the rest of the system — kernel, Chromium, AUR, mise, migrations — and
`/tmp/omarchy-update.log` is gone after a reboot. The stock bar icon only ever
means "the `omarchy` package is behind". GitHub release notes describe the
product, not this computer. And "the latest update" is ambiguous: last night's
4.0.2 → 4.0.3 and this morning's keyring reinstall are both "the latest".

Two different questions — *what landed here?* and *what is new in Omarchy?* —
and they are not the same list.

## Neighbours

| Plugin | Job | Relationship |
|---|---|---|
| `omarchy.system-update` | Pending icon, runs the update | Never replaced, never duplicated |
| Pending-update reviewers | *Before*: what an update would change | Neighbours. They own pending, this owns applied |
| News and RSS readers | Ecosystem news | A different job entirely |

The wedge is **after** the update, **this computer**, plus notes for **that
jump**.

## Why the log, and not a hook

The brief originally captured sessions from a `post-update` hook. Reading the
Omarchy source ruled that out:

1. **A post-update hook cannot see AUR or mise.** `omarchy-update` calls
   `omarchy-hook post-update` *before* `omarchy-update-aur-pkgs`,
   `omarchy-update-mise`, `omarchy-update-orphan-pkgs` and
   `omarchy-update-restart`. A hook-written record's `aur[]` and `mise[]` are
   empty by construction.
2. **`/var/log/pacman.log` already holds it all, durably.**
   `omarchy-update-keyring` unconditionally runs
   `pacman -Sy --noconfirm archlinux-keyring`, which logs a `[PACMAN] Running`
   line at the head of every update. Omarchy ships no logrotate config for
   pacman.log, so the history is retained.
3. **`jq` is a hard dependency of the `omarchy` package; `python` is not.**
   So the CLI is bash + jq + awk.

The result: v1 is log-only, hook-free and stateless. It works the moment
`omarchy plugin add` finishes, with the machine's whole update history already
in it, and uninstalling leaves nothing behind but a cache directory.

## Product rules

1. Default view is **This machine**.
2. Never light a second "updates available" indicator. No bar widget.
3. Sessions, not a raw package tail.
4. Group the machine view. A 139-line dump is a failure.
5. Release notes are for the jump you took, not "latest on GitHub".
6. Read-only. No sudo, no pacman lock, never starts an update.
7. Offline-first for the machine view.
8. Honest over clever: say "unknown" rather than show a wrong checkmark.

## Deliberately not done in v1

- Per-bullet `landed` / `not installed` / `n/a` annotations on release notes.
  The two views work first; a wrong checkmark is worse than none.
- Any pending-update scan, apply button, or bar badge.
- Arch news, `.pacnew`, snapper diffs, AI summaries.
- `mise` results, which no available source records per-session.

## Later

- Annotate release-note bullets, starting from a small hand-written map of
  known items rather than a large regex.
- Become a viewer over a first-party `omarchy update log`, if one lands. The
  CLI is the seam that would make that a small change.
- Edge/dev channels: `git log` subjects for the checkout range.
- An optional post-update notification, off by default.
