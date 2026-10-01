# What Changed: review and improvement plan

Status: proposed for review. This document records findings and planned work; it does not implement the changes.

## Assessment

The project has a sound foundation: a small CLI owns the data model, QML renders it, and installation requires no daemon or update hook. The most valuable next release would improve **accuracy, compatibility and reliability**.

Reviewed project commit: `59e1f2587ee127db243c28219329dea9a86e4958`. Compared against Omarchy **4.0.4** and upstream `quattro` snapshot `c05d901`, retrieved on 1 October 2026. Upstream findings describe that snapshot, not a released compatibility guarantee.

Verification completed during the review:

- **122 CLI tests and 97 model tests passed.**
- The manifest passed Omarchy's stable and upstream validators.
- Additional reproductions confirmed the problems below.
- QML lint produced warnings; live rendering and full desktop interaction remain unverified.
- No project or installed plugin files were changed during the review.

## Prioritized findings

### 1. High: current Omarchy kernel support is missing

Omarchy 4.0.4 introduces `linux-omarchy`. The plugin's kernel classification excludes it, along with `linux-t2`.

A reproduced `linux-omarchy` upgrade appeared under **Other packages**, with `rebootRequired: false` when no live marker existed. The classification is also duplicated between awk and jq, creating another opportunity for drift. See the [Omarchy 4.0.4 release](https://github.com/omacom/omarchy/releases/tag/v4.0.4) and [plugin classifiers](https://github.com/BVisagie/omarchy-what-changed/blob/59e1f25/bin/what-changed#L140).

**Change:** add these kernel families, excluding headers, and ensure row retention and grouping use matching classification rules.

### 2. High: migration-installed packages disappear from the summary

The command filter deliberately excludes `pacman -S --noconfirm --needed …`. Omarchy migrations use that command through `omarchy-pkg-add`.

This affects the central change in 4.0.4: its migration installs `linux-omarchy` and its headers. A reproduction showed the Omarchy upgrade but omitted the kernel installation completely. This is an existing completeness problem exposed by the new release. See the [kernel migration](https://github.com/omacom/omarchy/blob/v4.0.4/migrations/1789325478.sh) and [command filtering](https://github.com/BVisagie/omarchy-what-changed/blob/59e1f25/bin/what-changed#L117).

**Change:** retain these events in a separate **Other changes during this window** group. Explain that they may come from migrations or manual commands. Keep their counts separate from changes attributed by the existing update-command rules.

This follows the selected preference: expose uncertainty while preserving the hook-free design.

### 3. High: session navigation can display the wrong release notes

When notes for session A are loading, switching to B clears the notes but leaves `notesLoading` true. B's request is therefore skipped. A's response is then accepted without checking its session identity.

Executing the existing lifecycle functions reproduced **selected session B with session A's notes**. The loaded session header also remains stale while the replacement package view loads. See the [loading lifecycle](https://github.com/BVisagie/omarchy-what-changed/blob/59e1f25/Overlay.qml#L149).

**Change:** cancel superseded requests, identify responses by session and request generation, clear stale session data, and reset scrolling on navigation. Apply the same response checks to package details and compare URLs.

### 4. High: large updates lose important facts

The 500-row cap applies before summary calculation. Only reboot-class events receive special retention; Omarchy events do not.

A reproduction containing 600 ordinary upgrades followed by an Omarchy upgrade:

- Lost the Omarchy version event.
- Reported no version jump.
- Reported `total: 500` despite 602 observed package events, including the keyring reinstall.
- Consequently lost the correct release-note association.

The version reducer also takes the **first** Omarchy event, so multiple Omarchy changes in one session report an intermediate destination. See [row retention](https://github.com/BVisagie/omarchy-what-changed/blob/59e1f25/bin/what-changed#L240) and [version reduction](https://github.com/BVisagie/omarchy-what-changed/blob/59e1f25/bin/what-changed#L355).

**Change:** compute totals and version transitions before display truncation. Preserve Omarchy and kernel events, and derive the transition from the first source version to the final destination.

### 5. Medium: upstream breaks the shell-restart assumption

Stable 4.0.4 restarts the shell at the end. The inspected upstream flow now restarts it **before hooks, mise and AUR updates**.

The widget can therefore inspect a partially populated session. Because read state records only the session ID, reading it before AUR finishes also means later changes to that same session do not become unread. Failed updates and updates over SSH already expose weaknesses in restart-only refresh. See the [stable restart](https://github.com/omacom/omarchy/blob/v4.0.4/bin/omarchy-update-restart) and [upstream ordering](https://github.com/omacom/omarchy/blob/c05d901/bin/omarchy-update#L137).

**Change:** watch pacman log changes directly, without polling, and track a session content fingerprint alongside its ID. Later content in a previously read session should restore the unread indicator.

### 6. Medium: release-note failures are misclassified

A missing intermediate release returns curl failure, which is treated as "offline." Further uncached releases are skipped—even when the destination release exists. A controlled reproduction confirmed this.

Cache files are accepted without validation. A malformed cached release remained unusable without triggering repair. Writes are also non-atomic. Finally, GitHub release descriptions can be edited, so caching bodies forever can preserve outdated information. See [release fetching](https://github.com/BVisagie/omarchy-what-changed/blob/59e1f25/bin/what-changed#L460).

**Change:** distinguish missing releases, connection failures and rate limits; continue past individual missing releases; validate and atomically replace cache entries. Revalidate cached notes on demand after 24 hours, retaining usable cached content when offline.

### 7. Medium: historical information looks like current machine status

Every historical kernel update displays **"reboot needed"**, even after the user has rebooted. Historical sessions also show today's channel without an on-screen qualification.

Additionally, `incomplete` only detects unfinished pacman transactions. An update that fails before starting a transaction can appear complete. The logs cannot establish whole-update success. See [session enrichment](https://github.com/BVisagie/omarchy-what-changed/blob/59e1f25/bin/what-changed#L380) and [header presentation](https://github.com/BVisagie/omarchy-what-changed/blob/59e1f25/Model.js#L352).

**Change:** use historical wording such as **Reboot-related changes**, label the channel as current, and describe `incomplete` specifically as an unfinished package transaction. Do not imply that a completed transaction proves a successful update.

## Further improvements

- **Make older history accessible.** The UI silently stops at 50 sessions. A reproduced 1,500-session history exceeded the CLI output limit and failed, despite the error suggesting a narrowing option that does not exist. Add pagination and disclose available history. See the [session limit](https://github.com/BVisagie/omarchy-what-changed/blob/59e1f25/Model.js#L17).
- **Improve release-note usability.** Add Retry and Open official notes actions. Preserve safe links as structured actions while continuing to render prose as plain text. Show when bodies or Markdown blocks were shortened.
- **Improve narrow-screen layouts.** The header uses an unwrapped row beside dated navigation controls. Make the header wrap and hide navigation dates when space is limited; verify visually before release.
- **Clarify data coverage.** Explain that retained pacman logs bound history, command matching is heuristic, AUR provenance is inferred from invocation shape, and migration attribution uses timestamps.
- **Add automated regression checks.** There is no checked-in CI workflow. The existing suites are useful but currently miss the confirmed failures above.
- **Update documentation.** Replace the 4.0.3 compatibility statement and restart assumptions with a dated compatibility matrix. The CLI's "Up to date" read-status message should become "Latest recorded session already read," consistent with the product's purpose.

## Implementation and interface changes

Deliver these changes as plugin **1.1.0**, targeting stable and the inspected upstream behavior.

- Keep JSON schema version 1 with additive fields for attribution, session fingerprints, pagination and release-note diagnostics. Update model intake and documentation together.
- Make `sessions` return 50 entries by default; add `--limit` and `--before`, with `totalSessions`, `hasMore` and `nextBefore`. Keep direct lookup of older session IDs available.
- Preserve existing primary counts, but calculate them from all attributed events before truncation. Add separate counts for ambiguous nearby changes.
- Extend read state to store the newest session ID and content fingerprint. Read existing single-line markers and adopt their current fingerprint without creating an initial notification.
- Define fingerprints from recorded package events, attributed migration IDs and transaction completeness; exclude today's channel, live reboot markers and display formatting.
- Retain bounded rendering, fixed argv process calls, plain-text presentation and event-driven refresh.

## Acceptance checks

Add regression coverage for:

- `linux-omarchy`, `linux-t2`, headers and migration-installed packages.
- More than 500 events, accurate totals, retained version jumps and multiple Omarchy events.
- Session switching during delayed notes and package responses.
- New events appended after shell restart and after a session was marked read.
- Missing intermediate releases, rate limiting, invalid caches, interrupted writes and offline cached notes.
- More than 50 sessions, pagination and histories exceeding the former output limit.
- Collector completion and process exit arriving in either order.
- Historical reboot wording, current-channel qualification and unknown update outcomes.

Run existing suites and both manifest validators. Complete live smoke checks for menu/bar opening, dismissal, multiple monitors, narrow displays, scaling and contrasting themes before publishing.

## Assumptions and selected defaults

- Compatibility target: released Omarchy stable plus the inspected upstream development behavior.
- Attribution policy: label uncertain nearby changes rather than add capture hooks or continue silently omitting them.
- This PR is documentation only. Implementation, the proposed 1.1.0 version bump and release publication require subsequent work after plan review.
- Existing product boundaries remain requirements: no pending-update indicator, update action, polling daemon, Arch news, `.pacnew` handling, snapper diffs, AI summaries or invented per-session mise results.
