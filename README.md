# What Changed

**What actually changed after my Omarchy update?**

![What Changed, showing the packages that landed in one update](preview.png)

---

## The problem

`omarchy update` can change Omarchy, the kernel, packages, migrations and more —
but once it finishes, that information is easy to lose.
`/tmp/omarchy-update.log` is gone after a reboot, the stock bar icon only ever
meant "the `omarchy` package is behind", and GitHub's release notes describe the
product, not your computer.

What Changed gives you a clear, per-update summary of what actually changed on
your machine, scoped to one update run. Other plugins show you what an update
*will* do; this is the one for what it actually did.

## The two views

### This machine

Every package, migration and reboot flag from one update session, grouped so a
145-package night is legible. Omarchy's own version move first, then anything
with reboot-related changes, then named applications and inferred migration
package changes, then the long tail collapsed behind a count. Other changes
during the same window are shown separately and excluded from update totals.

### Release notes

The official Omarchy notes for **the exact version jump that session made** —
not "latest on GitHub" — parsed into headings, bullets and paragraphs rather
than dumped as raw Markdown.

![The release notes for the version jump that session made](docs/img/notes.png)

---

## Install

```bash
omarchy plugin add https://github.com/BVisagie/omarchy-what-changed.git --enable
```

Then add a menu entry so it lives under **Update › What changed**. Merge this
into `~/.config/omarchy/extensions/omarchy-menu.jsonc` — create the file if it
does not exist. The dotted id files it under the existing Update submenu on its
own, with no parent declaration:

```jsonc
{
  "update.what-changed": {
    "icon": "󰌱",
    "label": "What changed",
    "action": "omarchy-shell shell summon io.github.bvisagie.what-changed"
  }
}
```

That is the whole install. There is no hook to register and no daemon. Your
update history is already there the first time you open it — the plugin
reconstructs it from `/var/log/pacman.log`, so a fresh install typically has
months of sessions in it immediately.

You can also summon it directly, optionally at a specific session or view:

```bash
omarchy-shell shell summon io.github.bvisagie.what-changed
omarchy-shell shell summon io.github.bvisagie.what-changed \
  '{"session":"20260908T184129Z","tab":"notes"}'
```

## The bar icon

What Changed puts one icon in the bar, and it is **not** an update indicator.

It appears only when an update has landed that you have not read yet, and it
disappears the moment you open the overlay. It carries no badge and no count. It
never tells you updates are available — that is `omarchy.system-update`'s job,
and this plugin does not duplicate, clone or replace it.

Nothing polls. The widget checks recorded sessions when the shell starts, and
watches the read marker with a `FileView` so opening the overlay clears the icon.
Stable 4.0.4 restarts the shell at the end of a successful update. Failed updates
and updates over SSH or a TTY may need a manual re-check:

```bash
omarchy-shell -q io.github.bvisagie.what-changed refresh
```

That handler lives on the bar widget, so it exists only while the widget is in
`bar.layout` — which is the normal installation, and the only one where there is
an icon to re-check in the first place.

The inspected upstream development flow restarts the shell before hooks, mise
and AUR finish. Version 1.1.0 can therefore show a partial session until a manual
refresh or another shell restart. Reading that session records its ID; later
changes to the same ID do not restore the icon in this release. Event-driven
refresh and content fingerprints are reserved for a separately reviewed release.

A current system reboot request appears in the overlay only. It never makes the
bar icon appear, even if the request came from an unrelated system action.

### If you would rather not have the icon

Note that `omarchy plugin disable` turns off the **whole plugin**, not just the
bar entry — the menu item stops working too. Omarchy enables a plugin by writing
one entry, and for a plugin that declares `bar-widget` that entry goes into
`bar.layout`, so removing it deregisters the overlay as well.

Before reaching for that: the icon is not permanent. It occupies zero width
whenever there is nothing unread, which is nearly all of the time.

If you do want the overlay without ever seeing the icon, move the plugin's entry
in `~/.config/omarchy/shell.json` out of `bar.layout.right` and into the
top-level `plugins` array:

```jsonc
"plugins": [
  { "id": "io.github.bvisagie.what-changed" }
]
```

Then `omarchy-restart-shell`. The overlay stays summonable from the menu and the
widget is never instantiated — and with it goes both the icon and the `refresh`
handler above, which that configuration no longer has anything to refresh.

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

---

## The CLI

The overlay only ever runs `bin/what-changed` and renders its JSON. It stands
alone in a terminal — it is not on `PATH`, so alias it if you want it there:

```bash
alias what-changed=~/.config/omarchy/plugins/io.github.bvisagie.what-changed/bin/what-changed
```

```console
$ what-changed sessions
9 Sep 10:27  4.0.3             1↻
9 Sep 05:19  4.0.3             1↑ 1↻
8 Sep 20:41  4.0.2 → 4.0.3     135↑ 5+ 4- 1↻         reboot

$ what-changed show 20260908T184129Z
8 Sep 20:41  ·  omarchy 4.0.2 → 4.0.3  ·  current channel: stable  ·  reboot needed
145 packages changed  ·  5 added  ·  4 removed

Omarchy
  omarchy           4.0.2-1 → 4.0.3-1
  omarchy-settings  4.0.2-1 → 4.0.3-1

Reboot-related changes
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
| `what-changed compare-url [id]` | The GitHub compare URL for the jump |
| `what-changed status` | The newest session, and whether it has been read |
| `what-changed mark-read [id]` | Record a session as read (default: the newest) |

| Flag | Does |
|---|---|
| `--json` | Machine-readable. `show --json` arrives already grouped |
| `--expand other` | Include the collapsed group's rows |
| `--version` | Reads the version from `manifest.json` |

Session ids, exit codes and the `--json` contracts are in the
[CLI reference](docs/CLI.md).

## How it works

What Changed needs no hook and no capture step. Every `omarchy update` starts
with the same keyring step in `/var/log/pacman.log`, so the plugin rebuilds each
update session from that log after the fact, including history from before you
installed it.

A few things are inferred rather than recorded, and the overlay says so:

- **Packages a migration installed or removed** carry an `(inferred)` label.
  Omarchy's migration completion markers place them inside the update, but a
  manual command run at the same moment cannot be ruled out.
- **Other pacman activity near an update**, such as an `omarchy pkg add` you ran
  yourself, appears under *Other changes during this window* and is left out of
  the update's totals.
- **Reboot needed** compares the time of a reboot-related change with the
  machine's last boot, so an older session says whether a reboot has since
  followed.

The full rules, their limits and the Omarchy behaviour they depend on are in
[How it works](docs/HOW-IT-WORKS.md).

---

## What it writes

Two paths, both removable, and nothing else anywhere:

| Path | What |
|---|---|
| `~/.local/state/io.github.bvisagie.what-changed/last-read` | One line naming the newest session you have opened. This is what makes the bar icon appear and disappear |
| `~/.cache/io.github.bvisagie.what-changed/releases/` | Fetched release notes, cached indefinitely in 1.1.0. Release descriptions can change; revalidation is future work |

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

## Requirements

Omarchy 4.x. Uses only `bash`, `jq`, `awk`, `curl` and coreutils — `jq` is
already a hard dependency of the `omarchy` package and the rest ship with base.
No Python, no Node at runtime.

## More

| Document | For |
|---|---|
| [How it works](docs/HOW-IT-WORKS.md) | How sessions are reconstructed, what is inferred, and the Omarchy behaviour the plugin relies on |
| [CLI reference](docs/CLI.md) | Session ids, exit codes and the `--json` contracts |
| [Development](docs/DEVELOPMENT.md) | Design rules, architecture, tests and the local development loop |

## License

MIT © [BVisagie](https://github.com/BVisagie)
