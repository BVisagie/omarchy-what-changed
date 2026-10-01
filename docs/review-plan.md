# What Changed: review and improvement plan

Status: proposed for review. This document records findings and planned work; it does not implement the changes.

Revised after the [PR #2 plan review](https://github.com/BVisagie/omarchy-what-changed/pull/2#pullrequestreview-5380598668). Deliver the accuracy fixes as **1.1.0**; review the refresh, read-state, cache and pagination changes separately for a subsequent release.

The [follow-up review](https://github.com/BVisagie/omarchy-what-changed/pull/2#pullrequestreview-5380745966) accepts that release split. Its additions below clarify general transaction candidacy, timestamp boundaries, nested keyring runs, fingerprint upgrades and reboot-request presentation.

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

**Change (1.1.0):** add these kernel families, excluding headers, and ensure row retention and grouping use matching classification rules. Fix this together with migration attribution: classification alone cannot recover an event excluded by the command filter.

### 2. High: migration-installed packages disappear from the summary

The command filter deliberately excludes `pacman -S --noconfirm --needed …`. Omarchy migrations use that command through `omarchy-pkg-add`.

This affects the central change in 4.0.4: its migration installs `linux-omarchy` and its headers. A reproduction showed the Omarchy upgrade but omitted the kernel installation completely. This is an existing completeness problem exposed by the new release. See the [kernel migration](https://github.com/omacom/omarchy/blob/v4.0.4/migrations/1789325478.sh) and [command filtering](https://github.com/BVisagie/omarchy-what-changed/blob/59e1f25/bin/what-changed#L117).

The real machine's update `20260916T055719Z` confirms both findings #1 and #2. It reports three package changes (the keyring reinstall, `omarchy` and `omarchy-settings`) and `rebootRequired: false`. The log records the migration's pkg-add invocation at 07:57:23, installation of `linux-omarchy`, `pahole` and `linux-omarchy-headers` at 07:57:27–28, and the completion marker for `1789325478.sh` at 07:57:41 on 16 September 2026, local time. This evidence was independently rechecked while revising the plan.

**Change (1.1.0):** parse transactions before assigning attribution. Any otherwise unrecognized pacman transaction inside the fixed window is a candidate, independent of command form; the completion-marker bracket determines `migration-inferred` versus `nearby-uncertain`. This includes pkg-add installs, pkg-drop removals (`pacman -Rns --noconfirm`), migration AUR installs and direct replacements using `--ask 4` or `--ask=4`. Migrations [1784672586](https://github.com/omacom/omarchy/blob/v4.0.4/migrations/1784672586.sh), [1787399318](https://github.com/omacom/omarchy/blob/v4.0.4/migrations/1787399318.sh) and [1786952219](https://github.com/omacom/omarchy/blob/v4.0.4/migrations/1786952219.sh) use those direct replacements in stable and the pinned upstream. Candidate commands never become recognized update commands merely because they occur nearby. Keep AUR provenance independent of migration attribution, including `pacman -U` with `--needed` and a yay/paru cache path.

Accept stable command forms and upstream's optional `--` separator in the recognized first-run `omarchy-keyring` install matcher as well as transaction parsing.

- Compute the nearby/migration bound once as `min(next session start, last recognized update activity + 1800 seconds)`. The rolling `OWN_WINDOW` remains the admission rule for recognized update commands. Nearby or inferred migration events must never advance `own_until`, the recognized finish time or their own bound.
- Within that fixed window, bracket migration transactions from the final successfully completed system-upgrade transaction to the newest migration completion marker. At whole-second resolution, both bracket ends are inclusive: candidate start must be greater than or equal to system completion and candidate end less than or equal to the marker timestamp. Require a completed candidate transaction; timestamps alone cannot promote an unfinished transaction. Preserve exclusive ownership at the next session boundary using pacman log order, so same-second entries do not belong to two sessions. Mark bracketed candidates `migration-inferred`, include them in primary counts and let their reboot-class events feed `rebootReason`.
- Marker mtimes establish a phase bracket, not the caller of each pacman command. Display **Migration package changes (inferred)** and explain that concurrent manual commands cannot be ruled out. Promote Omarchy and reboot-class rows to their usual groups with attribution retained; show remaining inferred rows in the migration package group, without duplicating events.
- Keep candidate transactions outside that bracket as `nearby-uncertain`, under **Other changes during this window**, with separate counts and no effect on version carry-forward, reboot inference or future unread fingerprints. A failed migration has no completion marker; events not covered by an earlier successful marker remain uncertain. Missing markers or an unfinished system transaction cannot establish a bracket.

This refines the selected uncertainty policy using the reviewer's stronger evidence while preserving the hook-free design.

**Known limitation retained in 1.1.0:** migration [1787589206](https://github.com/omacom/omarchy/blob/v4.0.4/migrations/1787589206.sh) can conditionally run `omarchy-update-keyring`, reproducing the session-start command mid-update. Preserve the existing start boundary rather than silently merge it with an earlier run: a migration-triggered keyring and a separate update attempt that fails before `-Syu` are indistinguishable in pacman history. Document that this rare case splits one update into two reconstructed sessions. The second segment has no system-upgrade bracket; its candidate changes remain uncertain. Add an acceptance fixture that preserves both segments without duplicating events. Recovering exact run boundaries would require additional evidence and is outside this accuracy release.

### 3. High: session navigation can display the wrong release notes

When notes for session A are loading, switching to B clears the notes but leaves `notesLoading` true. B's request is therefore skipped. A's response is then accepted without checking its session identity.

Executing the existing lifecycle functions reproduced **selected session B with session A's notes**. The loaded session header also remains stale while the replacement package view loads. See the [loading lifecycle](https://github.com/BVisagie/omarchy-what-changed/blob/59e1f25/Overlay.qml#L149).

**Change (1.1.0):** cancel superseded requests, identify responses by session and request generation, clear stale session data, and reset scrolling on navigation. Apply checks to stdout, stderr and `onExited` for session lists, package details, notes and compare URLs. Give each running request immutable identity; changing a shared property on a reused process must not relabel callbacks from the stopped request. Ignore all callbacks from superseded generations, including cancellation exits. Verify Quickshell's actual exit behavior when setting `running = false` in the runtime acceptance checks.

### 4. High: large updates lose important facts

The 500-row cap applies before summary calculation. Only reboot-class events receive special retention; Omarchy events do not.

A reproduction containing 600 ordinary upgrades followed by an Omarchy upgrade:

- Lost the Omarchy version event.
- Reported no version jump.
- Reported `total: 500` despite 602 observed package events, including the keyring reinstall.
- Consequently lost the correct release-note association.

The version reducer also takes the **first** Omarchy event, so multiple Omarchy changes in one session report an intermediate destination. See [row retention](https://github.com/BVisagie/omarchy-what-changed/blob/59e1f25/bin/what-changed#L240) and [version reduction](https://github.com/BVisagie/omarchy-what-changed/blob/59e1f25/bin/what-changed#L355).

**Change (1.1.0):** compute totals and version transitions before display truncation. Preserve Omarchy and kernel facts independently of the row budget, and derive the transition from the first source version to the final destination.

Reduce `omarchy` and `omarchy-dev` events in recorded order. Removal of the active package clears its known version; an install or upgrade establishes the new active package/version. A stable-to-dev or dev-to-stable switch uses the removed package's source version and the final installed destination. Removal with no replacement leaves later sessions' version unknown, rather than carrying an empty string as a known version or substituting today's installed version. Compare links and release notes require two supported, distinct release versions. Same-version reinstalls do not create a release jump.

### 5. Medium: upstream breaks the shell-restart assumption

Stable 4.0.4 restarts the shell at the end. The inspected upstream flow now restarts it **before hooks, mise and AUR updates**.

The widget can therefore inspect a partially populated session. Because read state records only the session ID, reading it before AUR finishes also means later changes to that same session do not become unread. Failed updates and updates over SSH already expose weaknesses in restart-only refresh. See the [stable restart](https://github.com/omacom/omarchy/blob/v4.0.4/bin/omarchy-update-restart) and [upstream ordering](https://github.com/omacom/omarchy/blob/c05d901/bin/omarchy-update#L137).

**Change (subsequent release, separate design review):** watch pacman log changes, suppress mid-update unread notifications and track a session content fingerprint alongside its ID. The proposed refresh design is specified below; 1.1.0 retains the current restart/manual refresh behavior and documents the upstream limitation.

### 6. Medium: release-note failures are misclassified

A missing intermediate release returns curl failure, which is treated as "offline." Further uncached releases are skipped—even when the destination release exists. A controlled reproduction confirmed this.

Cache files are accepted without validation. A malformed cached release remained unusable without triggering repair. Writes are also non-atomic. Finally, GitHub release descriptions can be edited, so caching bodies forever can preserve outdated information. See [release fetching](https://github.com/BVisagie/omarchy-what-changed/blob/59e1f25/bin/what-changed#L460).

**Change (subsequent release):** distinguish missing releases, connection failures, rate limits and invalid cache data. Use curl's `--write-out '%{http_code}'` with an independently captured transport exit code instead of treating every `--fail` exit as offline. Continue past individual 404s; stop redundant network requests after transport failures or rate limits, while still serving valid cache hits. Validate cached JSON and expected field types before use; explicitly handle jq failures without leaking parse errors or relying on inherited errexit. Repair corrupt entries through a fresh fetch, with a cache-specific diagnostic if repair fails.

Write cache bodies and metadata through temporary files and atomic replacement. Revalidate on demand after 24 hours using a stored `ETag` and `If-None-Match`: a 304 keeps the validated body and updates its check time; a 200 validates and replaces it. Retain usable cached notes with a stale-data diagnostic when revalidation fails. Never issue background cache refreshes.

### 7. Medium: historical information looks like current machine status

Every historical kernel update displays **"reboot needed"**, even after the user has rebooted. Historical sessions also show today's channel without an on-screen qualification.

Additionally, `incomplete` only detects unfinished pacman transactions. An update that fails before starting a transaction can appear complete. The logs cannot establish whole-update success. See [session enrichment](https://github.com/BVisagie/omarchy-what-changed/blob/59e1f25/bin/what-changed#L380) and [header presentation](https://github.com/BVisagie/omarchy-what-changed/blob/59e1f25/Model.js#L352).

**Change (1.1.0):** preserve an actionable reboot signal using `btime` from `/proc/stat` and timestamped reboot-class events, including inferred migration events. Report `rebootRequired: true` when the latest relevant change is later than boot time; report false when a subsequent boot is observed. Add `rebootStatus: pending | rebooted | unknown | not-indicated` and retain historical reboot reasons even when the requirement has been satisfied. Equal-second timestamps, unreadable boot time or unparseable event times yield `unknown`, with historical wording rather than an urgent claim. This remains package-based reboot inference; boot time establishes whether a reboot followed, not which kernel was selected.

Correct the original premise: `omarchy-update-restart` does **not** clear `reboot-required` in stable or the pinned upstream. `omarchy-system-reboot` and `omarchy-system-shutdown` clear `re*-required`; other reboot paths can leave stale markers. Channel changes and Docker setup/removal can also set the marker. See [reboot](https://github.com/omacom/omarchy/blob/v4.0.4/bin/omarchy-system-reboot), [shutdown](https://github.com/omacom/omarchy/blob/v4.0.4/bin/omarchy-system-shutdown) and [channel changes](https://github.com/omacom/omarchy/blob/v4.0.4/bin/omarchy-channel-set).

Ignore marker mtimes older than the observed boot. Show a newer marker as a separate **Current system reboot request**, rather than attributing it to the newest update session; if boot time is unavailable, show its current applicability as unknown. Render `currentRebootRequest` in the overlay only. It must never create or restore the bar icon or affect unread fingerprints. Label the channel as current and describe `incomplete` specifically as an unfinished package transaction. Fix the README's marker claim and the corresponding CLI comment as part of 1.1.0; do not imply that completed package transactions prove whole-update success.

## Further improvements

- **Make older history accessible.** The UI silently stops at 50 sessions. A reproduced 1,500-session history exceeded the CLI output limit and failed, despite the error suggesting a narrowing option that does not exist. Add pagination and disclose available history. See the [session limit](https://github.com/BVisagie/omarchy-what-changed/blob/59e1f25/Model.js#L17).
- **Improve release-note usability.** Add Retry and Open official notes actions. Preserve safe links as structured actions while continuing to render prose as plain text. Show when bodies or Markdown blocks were shortened.
- **Improve narrow-screen layouts.** The header uses an unwrapped row beside dated navigation controls. Make the header wrap and hide navigation dates when space is limited; verify visually before release.
- **Clarify data coverage.** Explain that retained pacman logs bound history, command matching is heuristic, AUR provenance is inferred from invocation shape, and migration attribution uses timestamps.
- **Add automated regression checks.** There is no checked-in CI workflow. The existing suites are useful but currently miss the confirmed failures above.
- **Update documentation.** Replace the 4.0.3 compatibility statement and restart assumptions with a dated compatibility matrix. The CLI's "Up to date" read-status message should become "Latest recorded session already read," consistent with the product's purpose.

## Release sequence and interfaces

### 1.1.0: accuracy fixes

- Implement findings #1, #2, #3, #4 and the boot-time check and documentation corrections from #7. Keep refresh, read-marker format, cache behavior and pagination out of this release.
- Keep JSON schema version 1. Add row `attribution` (`update-command`, `migration-inferred` or `nearby-uncertain`), a separate `nearbyCounts` object using the existing operation-count shape, session `rebootStatus`, and top-level `currentRebootRequest` (`pending`, `stale`, `unknown` or `absent`). Update model intake and documented contracts with the CLI.
- Primary counts include update-command and migration-inferred events and are calculated before display truncation. `nearbyCounts` represents uncertain rows only. `counts.omitted` continues to describe omitted primary rows; nearby omission counts remain separate. Keep summaries, group counts and displayed attribution consistent.
- Retain existing session listing and direct-ID lookup behavior. The existing `last-read` file remains byte-compatible. Add test overrides for boot-time data and marker mtimes so tests cannot depend on the host's current boot.

### Subsequent release: refresh, cache and history

This work needs its own design review after the accuracy release. The proposed defaults below make the timer exception and compatibility changes visible for that review; they do not authorize implementation in the accuracy release.

- **Update gate:** expose `inProgress` as true, false or null. Detect an exclusive flock by the update lock file's device/inode tuple in `/proc/locks`, using `$XDG_RUNTIME_DIR/omarchy-update.lock` or upstream's `/tmp` fallback. Never acquire the lock, invoke `omarchy-update-lock held` or infer activity from file existence alone. If inspection is unavailable, report null instead of claiming the update finished.
- **Completion wake-up:** while activity is confirmed, hide the unread icon, show an in-progress message in an explicitly opened overlay and do not advance read state. Recheck lock state once per second until release; inspect only the lock during those checks and refresh session data once activity ends. Restarting the shell while the lock is held must restart this wait. This deliberately proposes a narrow exception to the existing no-Timer/no-polling invariant: activity checks run only during an observed update, with no idle polling. Amend the design rules explicitly if this subsequent design is accepted.
- **Write coalescing:** debounce log changes with a 250 ms single-shot timer. Do not restart a running status process for every line; queue at most one follow-up parse. This debounce is event coalescing, separate from the active-update lock check. Reattach watchers after log replacement/rotation and check current lock state at startup and on relevant changes.
- **Fingerprints and rollback:** preserve the exact single-line ID in `last-read`. Add a separate `last-read-fingerprint` file containing its associated session ID, digest and fingerprint algorithm version, initially 1. Increment the algorithm version when attribution rules, covered fields or canonical encoding change. A mismatched ID/version, missing or malformed sidecar, or torn pair means an unknown fingerprint. When `last-read` names the current session, adopt an unknown fingerprint quietly just like a legacy marker; it must not itself make the session unread. If `last-read` names a different session, that ID difference still means unread. Write through atomic replacement. Fingerprints cover all update-command and migration-inferred events, including rows omitted from display, matched migration IDs and transaction completeness. Exclude nearby-uncertain events, channel, live reboot marker, boot-dependent presentation and formatting. Later primary content restores unread state after adoption; adoption waits until no update is active. Quiet algorithm migration intentionally cannot recover changes that arrived before the new baseline was adopted.
- **Cache:** implement finding #6, retaining useful offline data and distinguishing HTTP, transport and cache failures. Add Retry/Open official notes actions and visible truncation diagnostics.
- **Pagination:** add `--limit` and `--before`, with `totalSessions`, `hasMore` and `nextBefore`. Default `sessions` to 50 entries and retain direct lookup of older IDs. Explicitly document this as a CLI behavior change under schema 1; additive JSON fields alone do not make that default backward-compatible. The overlay fetches additional pages for older navigation rather than silently truncating history.
- **Layout and CI:** complete narrow-header layout work and add the regression workflow. Preserve bounded rendering, fixed argv calls and plain-text prose across both releases.

## Acceptance checks

For **1.1.0**, add regression coverage for:

- The real 4.0.4 update as a minimized, sanitized fixture: six primary package events, including `linux-omarchy`, `pahole` and headers; migration attribution and historical reboot reasons survive; pending/rebooted status follows injected boot time.
- Both kernel families, header exclusion, pkg-add and first-run keyring install with/without `--`, pkg-drop, AUR `--needed` and direct replacements with `--ask 4`/`--ask=4`. General unrecognized transactions inside/outside the marker bracket, failed or missing markers and candidate timestamps equal to each bracket end. No uncertain-event extension of the fixed window; nearby manual installs do not change primary counts or reboot inference.
- A migration-triggered keyring run produces two documented reconstructed segments; the second has no system-upgrade bracket, candidate rows stay uncertain and no event is counted twice. A separate keyring-only update attempt is not silently merged away.
- More than 500 events, exact totals, retained Omarchy/kernel facts and transitions across multiple Omarchy events. Stable/dev switches, removal without replacement, subsequent unknown-version sessions and same-version reinstalls.
- Rapid A→B→C navigation during delayed notes, show and compare requests. Stopped requests' stdout, stderr and exit callbacks cannot alter the current view. Exercise Quickshell cancellation and both collector-before-exit and exit-before-collector orderings.
- Boot before/after/equal to relevant changes; unreadable boot data; stale/current reboot markers; markers created by unrelated actions; current-channel qualification and unknown whole-update outcome. A current reboot request is visible only in the overlay and never makes the bar icon appear.

For the **subsequent release**, add acceptance checks for:

- Mid-update writes on stable, upstream's early shell restart, AUR appends, failed updates and lock release with no final log write. The icon remains quiet during activity and refreshes afterward; observation never acquires a lock or disrupts a starting update.
- Event bursts coalesce, active lock checks stop after release, no idle timer runs, and watches survive log rotation/replacement. Unknown lock visibility is disclosed.
- New primary events after reading restore unread state; uncertain manual activity does not. Legacy-marker adoption, missing/malformed or mismatched sidecars, algorithm-version changes, interrupted writes and a rollback-to-1.0.0/re-upgrade cycle stay quiet when the read ID is current. A different newest ID remains unread regardless of fingerprint adoption.
- Missing intermediate releases followed by an available destination; HTTP 403/429; connection failure; corrupt caches while online; repair failure; interrupted writes; ETag 304/200 responses; usable stale data offline.
- More than 50 sessions, older-page navigation, direct old-ID lookup and histories exceeding the former output limit. Narrow displays, scaling and contrasting themes.

Run existing suites and both pinned manifest validators for each release. Live menu/bar opening, dismissal and multi-monitor checks are required before publishing. Record runtime findings, including Quickshell cancellation semantics, instead of treating static QML lint as proof of behavior.

## Assumptions and selected defaults

- Compatibility target: released Omarchy stable plus the inspected upstream development behavior. The early-restart refresh limitation remains documented in 1.1.0 until the subsequent design is accepted and implemented.
- Attribution policy: use completion markers to infer migration-phase changes, label the inference explicitly, and keep uncertain nearby activity separate. Do not add capture hooks or claim marker timestamps prove a command's caller.
- This PR is documentation only. Implementation, version bumps and release publication require subsequent work after plan review.
- The accuracy release retains the existing no-Timer/no-polling invariant. The subsequent refresh design explicitly proposes an active-update-only exception for lock-release detection and requires its own review.
- Other product boundaries remain requirements: no pending-update indicator, update action, polling daemon, Arch news, `.pacnew` handling, snapper diffs, AI summaries or invented per-session mise results.
