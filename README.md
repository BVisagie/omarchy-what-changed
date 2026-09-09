# What Changed

After Omarchy updates, see what actually landed on this machine — then the
official release notes for the version you just installed. **Not a
pending-update indicator. Not a news feed.**

![What Changed](preview.png)

`omarchy update` is a black box once it finishes. One run upgrades Omarchy *and*
the rest of the system — kernel, Chromium, AUR, migrations — then
`/tmp/omarchy-update.log` is gone after a reboot. The bar icon only ever meant
"the `omarchy` package is behind". And "the latest update" is ambiguous: last
night's 4.0.2 → 4.0.3 and this morning's keyring reinstall are both "the
latest".

This is the reading surface for afterwards. Two views of one update session:

- **This machine** — the packages, migrations and reboot flags that landed here,
  grouped so a 145-package night is legible.
- **Release notes** — the official Omarchy notes for the exact version jump that
  session made, parsed into headings, bullets and paragraphs rather than left as
  raw Markdown.

## Install

```bash
omarchy plugin add https://github.com/BVisagie/omarchy-what-changed.git --enable
```

Then add a menu entry, so it lives under **Update > What changed**. Merge this
into `~/.config/omarchy/extensions/omarchy-menu.jsonc` (create the file if it
does not exist — the dotted id puts it under the existing Update submenu on its
own):

```jsonc
{
  "update.what-changed": {
    "icon": "󰌱",
    "label": "What changed",
    "action": "omarchy-shell shell summon io.github.bvisagie.what-changed"
  }
}
```

That is the whole install. There is no hook to register and no daemon — your
update history is already there the first time you open it.

You can also summon it directly, optionally at a specific session or view:

```bash
omarchy-shell shell summon io.github.bvisagie.what-changed
omarchy-shell shell summon io.github.bvisagie.what-changed '{"session":"20260908T184129Z","tab":"notes"}'
```

## The bar icon

What Changed puts one icon in the bar, and it is **not** an update indicator.

It appears only when an update has landed that you have not read yet, and it
disappears the moment you open the overlay. It carries no badge and no count. It
never tells you updates are available — that is `omarchy.system-update`'s job,
and this plugin does not duplicate, clone or replace it.

Nothing polls. Two events can change the answer and both are watched directly: a
new session can only be created by `omarchy update`, which always ends by
restarting the shell, so the widget is rebuilt right after it; and the read
marker is watched, so the icon clears the instant you open the overlay.

If you would rather not have it in the bar at all, the plugin is still fully
usable from the menu:

```bash
omarchy plugin disable io.github.bvisagie.what-changed   # removes it from the bar
```

The one case the shell restart does not cover is an update run over ssh or a
TTY, where `omarchy-restart-shell` could not run. Force a re-check with:

```bash
omarchy-shell -q io.github.bvisagie.what-changed refresh
```

## Keys

| Key | Action |
|---|---|
| `Tab` | Switch This machine / Release notes |
| `[` `]` | Older / newer session |
| `j` `k`, arrows, `PgUp` `PgDn`, `Home` `End` | Scroll |
| `e` | Expand the collapsed "other packages" group |
| `o` | Open the GitHub compare for this jump |
| `Esc` `q` | Close |

There is deliberately no key that starts an update.

## How a session is found

Every `omarchy update` begins by running
`pacman -Sy --noconfirm archlinux-keyring` (from `omarchy-update-keyring`), and
that lands in `/var/log/pacman.log`. That line is the head of a session;
everything until the next one belongs to it, however many pacman transactions it
took — keyring, the `-Syu`, one `-U` per AUR package, the orphan sweep.

Within that window, only pacman invocations that an update actually makes are
counted:

| Invocation | Belongs to the update |
|---|---|
| `pacman -Sy --noconfirm archlinux-keyring` | yes — `omarchy-update-keyring` |
| `pacman -Syu … --overwrite /usr/share/omarchy/*` | yes — `omarchy-update-system-pkgs` |
| `pacman -U … --config /etc/pacman.conf … /.cache/yay/…` | yes — yay, tagged AUR |
| `pacman -Rns …` *without* `--noconfirm` | yes — `omarchy-update-orphan-pkgs` |
| `pacman -S --noconfirm --needed …` | no — `omarchy pkg add` |
| `pacman -Rns --noconfirm …` | no — `omarchy pkg remove` |

So the `gthumb` you installed an hour after the update does not show up as part
of it.

### What is derived, and how honestly

| Field | Source |
|---|---|
| Packages, versions, AUR | `/var/log/pacman.log`, exactly |
| Omarchy version | The `omarchy` package event in that session; sessions that did not move it carry the previous version forward, and sessions older than the first recorded jump show none rather than guessing |
| Migrations | `~/.local/state/omarchy/migrations/*.sh` mtimes falling inside the session |
| Reboot needed | A kernel-class package in that session. The live `reboot-required` marker is only trusted for the newest session, because `omarchy-update-restart` clears it |
| Channel | `omarchy-channel-current`, which reports *now*, not then |
| `mise` | Not recorded anywhere per-session, so not claimed |
| Repo | Not in pacman.log, and `pacman -Si` needs a sync, so not claimed |

## The CLI

The overlay only ever runs `bin/what-changed` and renders its JSON — no pacman,
git or network calls from QML. The CLI stands alone in a terminal:

```console
$ what-changed sessions
9 Sep 10:27  4.0.3             1↻
9 Sep 05:19  4.0.3             1↑ 1↻
8 Sep 20:41  4.0.2 → 4.0.3     135↑ 5+ 4- 1↻         reboot

$ what-changed show 20260908T184129Z
8 Sep 20:41  ·  omarchy 4.0.2 → 4.0.3  ·  stable  ·  reboot needed
145 packages changed  ·  5 added  ·  4 removed

Omarchy
  omarchy           4.0.2-1 → 4.0.3-1
  omarchy-settings  4.0.2-1 → 4.0.3-1

Needs reboot
  linux  7.1.9.arch1-2 → 7.2.3.arch1-3
  mesa   1:26.2.1-1 → 1:26.2.2-1

Migrations
  9 migrations ran
…
```

| Command | Does |
|---|---|
| `what-changed sessions` | One line per session, newest first |
| `what-changed show [id]` | What landed (the default command) |
| `what-changed notes [id]` | Release notes for that session's jump |
| `what-changed compare-url [id]` | The GitHub compare URL |
| `what-changed status` | The newest session, and whether it has been read |
| `what-changed mark-read [id]` | Record a session as read (default: the newest) |
| `--json` | Machine-readable; `show --json` is already grouped |
| `--expand other` | Include the collapsed group's rows |

A session id may be given in full or as a unique prefix; where a prefix matches
more than one session, the newest match wins.

`counts.aur` and the AUR group answer different questions. The count is
provenance — how many packages in that session came from the AUR — while the
group lists only the AUR packages not already shown under Apps or Omarchy. A
session that upgraded `brave-origin-bin` and `ai-usagebar-bin` reports
`counts.aur: 2` and shows one row under AUR, because Brave is a named app.

## Safety

- **Read-only where it matters.** No sudo, no pacman lock, and nothing written
  outside the two paths under "What it writes" below. It never starts an update.
- Every `Text` is `Text.PlainText`, and intake rebuilds each object from known
  fields only. Package names come from a log and release bodies from GitHub;
  both are treated as untrusted, control-character flattened and length-capped.
- `Process` commands are fixed argv arrays. No shell strings anywhere in QML.
- Release notes: HTTPS only, host allowlisted, one redirect, 10s timeout,
  512 KiB cap, and the URL is built only from a strict version match. Tags are
  immutable, so a fetched release is cached under
  `~/.cache/io.github.bvisagie.what-changed/` (mode 0700) forever. One request
  per missing tag, never a poll.
- Rows are capped at 500 per session, with kernel-class packages held apart from
  the cap so a huge session can never be the one that hides the kernel. The
  footer says how many were omitted.

## What it writes

Two things, both removable, and nothing else anywhere:

| Path | What |
|---|---|
| `~/.local/state/io.github.bvisagie.what-changed/last-read` | One line naming the newest session you have opened. This is what makes the bar icon appear and disappear |
| `~/.cache/io.github.bvisagie.what-changed/releases/` | Fetched release notes. Tags are immutable, so these are cached forever and fetched once each |

It never writes to your Omarchy config, never touches `/var/log/pacman.log`, and
never needs sudo.

## Removal

```bash
omarchy plugin remove io.github.bvisagie.what-changed
rm -rf ~/.local/state/io.github.bvisagie.what-changed \
       ~/.cache/io.github.bvisagie.what-changed
```

Then delete the `update.what-changed` entry from
`~/.config/omarchy/extensions/omarchy-menu.jsonc` if you added it.

`omarchy plugin remove` takes the plugin out of the bar and the menu, but it does
not clear XDG state or cache, which is why the second command is listed.

## Alongside Update Review

[jampick/omarchy-update-review](https://github.com/jampick/omarchy-update-review)
is *what will change*, before you click update. What Changed is *what did
change*, after it finished. They stack, and neither replaces the stock update
icon — this plugin ships no bar widget and never signals that updates are
available.

## Tests

```bash
./test/sessions.test.sh   # parser, grouping, failure modes; no network
node test/model.test.js   # intake, sanitising, formatting
omarchy plugin validate .
```

`test/fixtures/pacman.log` is a synthetic log holding one full update (keyring +
`-Syu` + two AUR builds + an orphan sweep), a thin one, and the manual
`pacman -S`/`-Rns` calls that must *not* be attributed to either.

## Requirements

Omarchy 4.x. Uses only `bash`, `jq`, `awk`, `curl` and `coreutils` — `jq` is
already a hard dependency of the `omarchy` package, and the rest ship with base.

## License

MIT © BVisagie
