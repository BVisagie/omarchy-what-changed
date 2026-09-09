#!/bin/bash
# Fixture tests for the session parser. No network: curl is shimmed to fail, so
# any accidental fetch shows up as a failure rather than a slow, flaky pass.
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
CLI="$ROOT/bin/what-changed"
FIXTURE="$ROOT/test/fixtures/pacman.log"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/nonet"; printf '#!/bin/sh\necho "network disabled in tests" >&2\nexit 6\n' >"$TMP/nonet/curl"
chmod +x "$TMP/nonet/curl"
PATH="$TMP/nonet:$PATH"

mkdir -p "$TMP/state/migrations" "$TMP/cache"
export WHAT_CHANGED_PACMAN_LOG="$FIXTURE"
export WHAT_CHANGED_STATE_DIR="$TMP/state"
export WHAT_CHANGED_CACHE_DIR="$TMP/cache"
export WHAT_CHANGED_STATE_HOME="$TMP/marker"

pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
no()  { fail=$((fail+1)); printf '  FAIL %s\n     expected: %s\n     actual:   %s\n' "$1" "$2" "$3"; }
is()  { [[ $2 == "$3" ]] && ok "$1" || no "$1" "$3" "$2"; }
has() { [[ $2 == *"$3"* ]] && ok "$1" || no "$1" "contains: $3" "$2"; }

echo "session segmentation"
J=$("$CLI" sessions --json)
is "two sessions from a log holding seven transactions" "$(jq '.sessions|length' <<<"$J")" 2
is "newest session first" "$(jq -r '.sessions[0].id' <<<"$J")" "20260909T063521Z"
is "session id is the UTC start" "$(jq -r '.sessions[1].id' <<<"$J")" "20260908T184129Z"

echo
echo "the update session"
A=$("$CLI" show 20260908T184129Z --json)
is "omarchy from"            "$(jq -r '.session.omarchy.from' <<<"$A")" "4.0.2-1"
is "omarchy to"              "$(jq -r '.session.omarchy.to' <<<"$A")" "4.0.3-1"
is "omarchy jumped"          "$(jq -r '.session.omarchy.jumped' <<<"$A")" "true"
is "keyring + syu + 2 AUR + orphans merge into one session" \
   "$(jq -r '[.groups[].items[]?|select(.kind=="pkg")]|length' <<<"$A")" \
   "$(jq -r '.session.counts.total - (.groups[]|select(.id=="other").count)' <<<"$A")"
is "upgraded count"    "$(jq -r '.session.counts.upgraded' <<<"$A")" 7
is "installed count"   "$(jq -r '.session.counts.installed' <<<"$A")" 1
is "removed count"     "$(jq -r '.session.counts.removed' <<<"$A")" 3
is "reinstalled count" "$(jq -r '.session.counts.reinstalled' <<<"$A")" 1
is "AUR attributed from the yay cache path" "$(jq -r '.session.counts.aur' <<<"$A")" 2
is "kernel drives rebootRequired" "$(jq -r '.session.rebootRequired' <<<"$A")" "true"
is "reboot reason names the kernel" "$(jq -r '.session.rebootReason|index("linux")!=null' <<<"$A")" "true"
is "source is the log" "$(jq -r '.session.source' <<<"$A")" "pacman-log"
is "complete session" "$(jq -r '.session.incomplete' <<<"$A")" "false"

echo
echo "invocations that are not part of the update"
ALL=$(for i in 20260908T184129Z 20260909T063521Z; do "$CLI" show $i --json --expand other; done | jq -s '.')
for p in gthumb geeqie ripgrep; do
  is "$p (omarchy pkg add/remove) is in no session" \
     "$(jq -r --arg p "$p" '[.[].groups[].items[]?|select(.name==$p)]|length' <<<"$ALL")" 0
done
is "the orphan -Rns without --noconfirm IS part of the update" \
   "$(jq -r '[.[].groups[].items[]?|select(.name=="qpdf")]|length' <<<"$ALL")" 1

echo
echo "grouping"
is "fixed group order" \
   "$(jq -r '[.groups[].id]|join(",")' <<<"$A")" "omarchy,reboot,apps,aur,other"
is "omarchy group holds both packages" "$(jq -r '.groups[]|select(.id=="omarchy").items|length' <<<"$A")" 2
is "kernel is in the reboot group" "$(jq -r '.groups[]|select(.id=="reboot").items[0].name' <<<"$A")" "linux"
is "other is collapsed"          "$(jq -r '.groups[]|select(.id=="other").collapsed' <<<"$A")" "true"
is "other carries a count"       "$(jq -r '.groups[]|select(.id=="other").count>0' <<<"$A")" "true"
is "other has no items until asked" "$(jq -r '.groups[]|select(.id=="other").items|length' <<<"$A")" 0
E=$("$CLI" show 20260908T184129Z --json --expand other)
is "--expand other fills the items" \
   "$(jq -r '.groups[]|select(.id=="other")|(.items|length)==.count' <<<"$E")" "true"

echo
echo "version carried across sessions"
B=$("$CLI" show 20260909T063521Z --json)
is "a session that did not move Omarchy reports no jump" "$(jq -r '.session.omarchy.jumped' <<<"$B")" "false"
is "and carries the version forward"  "$(jq -r '.session.omarchy.to' <<<"$B")" "4.0.3-1"
is "no kernel, no reboot"             "$(jq -r '.session.rebootRequired' <<<"$B")" "false"

echo
echo "migrations"
touch -d "2026-09-08T20:44:00+0200" "$TMP/state/migrations/1788577553.sh"
touch -d "2026-09-08T20:44:00+0200" "$TMP/state/migrations/1788619462.sh"
touch -d "2026-08-01T09:00:00+0200" "$TMP/state/migrations/1700000000.sh"
touch -d "2026-09-09T08:35:41+0200" "$TMP/state/migrations/1788999999.sh"
M=$("$CLI" show 20260908T184129Z --json)
is "markers inside the window are attributed" \
   "$(jq -r '.groups[]|select(.id=="migrations").items|map(.name)|join(",")' <<<"$M")" "1788577553,1788619462"
is "a marker from the next session is not" \
   "$(jq -r '[.groups[]|select(.id=="migrations").items[]|select(.name=="1788999999")]|length' <<<"$M")" 0

echo
echo "row cap"
BIG="$TMP/big.log"
{
  echo "[2026-09-08T20:41:29+0200] [PACMAN] Running 'pacman -Sy --noconfirm archlinux-keyring'"
  echo "[2026-09-08T20:41:35+0200] [PACMAN] Running 'pacman -Syu --noconfirm --overwrite /usr/share/omarchy/*'"
  echo "[2026-09-08T20:42:01+0200] [ALPM] transaction started"
  for i in $(seq 1 600); do
    printf '[2026-09-08T20:42:%02d+0200] [ALPM] upgraded filler%03d (1.0-1 -> 1.0-2)\n' $((i % 60)) "$i"
  done
  echo "[2026-09-08T20:43:59+0200] [ALPM] upgraded linux (7.1.9.arch1-2 -> 7.2.3.arch1-3)"
  echo "[2026-09-08T20:43:59+0200] [ALPM] transaction completed"
} >"$BIG"
C=$(WHAT_CHANGED_PACMAN_LOG="$BIG" "$CLI" show --json --expand other)
is "cap reports what it dropped" "$(jq -r '.session.counts.omitted>0' <<<"$C")" "true"
is "cap keeps the kernel"        "$(jq -r '[.groups[].items[]?|select(.name=="linux")]|length' <<<"$C")" 1
is "cap holds the row limit"     "$(jq -r '[.groups[].items[]?|select(.kind=="pkg")]|length<=500' <<<"$C")" "true"

echo
echo "incomplete sessions"
INC="$TMP/incomplete.log"
{
  echo "[2026-09-08T20:41:29+0200] [PACMAN] Running 'pacman -Sy --noconfirm archlinux-keyring'"
  echo "[2026-09-08T20:41:35+0200] [PACMAN] Running 'pacman -Syu --noconfirm --overwrite /usr/share/omarchy/*'"
  echo "[2026-09-08T20:42:01+0200] [ALPM] transaction started"
  echo "[2026-09-08T20:42:02+0200] [ALPM] upgraded zlib (1:1.3.1-2 -> 1:1.3.1-3)"
} >"$INC"
is "a transaction that never completed is flagged" \
   "$(WHAT_CHANGED_PACMAN_LOG="$INC" "$CLI" show --json | jq -r '.session.incomplete')" "true"

echo
echo "untrusted text"
EVIL="$TMP/evil.log"
{
  echo "[2026-09-08T20:41:29+0200] [PACMAN] Running 'pacman -Sy --noconfirm archlinux-keyring'"
  echo "[2026-09-08T20:41:35+0200] [PACMAN] Running 'pacman -Syu --noconfirm --overwrite /usr/share/omarchy/*'"
  printf '[2026-09-08T20:42:02+0200] [ALPM] upgraded evil"pkg (1.0-1 -> 1.0-2)\n'
  printf '[2026-09-08T20:42:03+0200] [ALPM] upgraded ok-pkg (1.0-1 -> "1.0\\-2)\n'
} >"$EVIL"
O=$(WHAT_CHANGED_PACMAN_LOG="$EVIL" "$CLI" show --json 2>/dev/null)
is "output stays valid JSON when the log does not" "$(jq -e . >/dev/null 2>&1 <<<"$O"; echo $?)" 0
is "a name with a quote is rejected, not emitted raw" \
   "$(jq -r '[.groups[].items[]?|select(.name|test("\""))]|length' <<<"$O")" 0

echo
echo "notes without a network"
N=$("$CLI" notes 20260909T063521Z --json)
is "no version change means no fetch" "$(jq -r '.status' <<<"$N")" "no-jump"
mkdir -p "$TMP/cache/releases"
cp "$ROOT/test/fixtures/release-v4.0.3.json" "$TMP/cache/releases/v4.0.3.json"
N2=$("$CLI" notes 20260908T184129Z --json)
is "a cached tag renders offline"  "$(jq -r '.status' <<<"$N2")" "ok"
is "and carries the release body"  "$(jq -r '.releases[0].tag' <<<"$N2")" "v4.0.3"
rm -f "$TMP/cache/releases/v4.0.3.json"
N3=$("$CLI" notes 20260908T184129Z --json)
is "an uncached tag degrades, it does not crash" "$(jq -r '.status' <<<"$N3")" "unavailable"
is "machine view is unaffected by the network" \
   "$("$CLI" show 20260908T184129Z --json | jq -r '.session.omarchy.to')" "4.0.3-1"
is "compare url is built from the jump" \
   "$("$CLI" compare-url 20260908T184129Z)" "https://github.com/omacom/omarchy/compare/v4.0.2...v4.0.3"

echo
echo "failure modes"
out=$(WHAT_CHANGED_PACMAN_LOG=/nope/pacman.log "$CLI" sessions 2>&1); rc=$?
is  "missing log exits non-zero" "$rc" 1
has "missing log says which file" "$out" "/nope/pacman.log"
: >"$TMP/empty.log"
out=$(WHAT_CHANGED_PACMAN_LOG="$TMP/empty.log" "$CLI" sessions 2>&1); rc=$?
is  "a log with no sessions exits non-zero" "$rc" 1
has "and says so plainly" "$out" "no update sessions found"
touch "$TMP/locked.log"; chmod 000 "$TMP/locked.log"
out=$(WHAT_CHANGED_PACMAN_LOG="$TMP/locked.log" "$CLI" sessions 2>&1); rc=$?
is  "an unreadable log exits non-zero" "$rc" 1
has "and names readability" "$out" "not readable"
out=$("$CLI" bogus 2>&1); rc=$?
is "an unknown command exits non-zero" "$rc" 1
out=$("$CLI" show 19990101T000000Z 2>&1); rc=$?
is "an unknown session exits non-zero" "$rc" 1

echo
echo "version"
is "--version matches the manifest, not the schema version" \
   "$("$CLI" --version)" "what-changed $(jq -r .version "$ROOT/manifest.json")"

echo
echo "read marker"
rm -rf "$TMP/marker"
S=$("$CLI" status --json)
is "a fresh install starts quiet"        "$(jq -r '.unread' <<<"$S")" "false"
is "and adopts the newest session"       "$(jq -r '.lastRead == .newest.id' <<<"$S")" "true"
is "newest is the newest session"        "$(jq -r '.newest.id' <<<"$S")" "20260909T063521Z"
is "the marker directory is private"     "$(stat -c '%a' "$TMP/marker")" "700"
is "the marker file is private"          "$(stat -c '%a' "$TMP/marker/last-read")" "600"
is "status carries no event payload"     "$(jq -r '.newest | has("events")' <<<"$S")" "false"

"$CLI" mark-read 20260908T184129Z
is "an older session read means unread"  "$("$CLI" status --json | jq -r '.unread')" "true"
"$CLI" mark-read
is "marking the newest read goes quiet"  "$("$CLI" status --json | jq -r '.unread')" "false"
"$CLI" mark-read; "$CLI" mark-read
is "mark-read is idempotent"             "$("$CLI" status --json | jq -r '.unread')" "false"

printf 'not-a-session-id\n' >"$TMP/marker/last-read"
is "a marker naming nothing known is unread" "$("$CLI" status --json | jq -r '.unread')" "true"
printf '19990101T000000Z\n' >"$TMP/marker/last-read"
is "a marker naming an unknown session is unread" "$("$CLI" status --json | jq -r '.unread')" "true"

echo
echo "the marker never breaks the caller"
chmod 500 "$TMP/marker"
"$CLI" mark-read >/dev/null 2>&1; rc=$?
is "mark-read exits 0 when state is unwritable" "$rc" 0
chmod 700 "$TMP/marker"
rm -rf "$TMP/marker"
out=$(WHAT_CHANGED_PACMAN_LOG="$TMP/empty.log" "$CLI" status --json 2>/dev/null); rc=$?
is "status answers for a machine with no history" "$rc" 0
is "and reports nothing unread"                   "$(jq -r '.unread' <<<"$out")" "false"
is "with a null newest"                           "$(jq -r '.newest' <<<"$out")" "null"

echo
echo "a session does not own the days after it"
DRIFT="$TMP/drift.log"
{
  echo "[2026-09-08T20:41:29+0200] [PACMAN] Running 'pacman -Sy --noconfirm archlinux-keyring'"
  echo "[2026-09-08T20:41:35+0200] [PACMAN] Running 'pacman -Syu --noconfirm --overwrite /usr/share/omarchy/*'"
  echo "[2026-09-08T20:42:01+0200] [ALPM] transaction started"
  echo "[2026-09-08T20:42:02+0200] [ALPM] upgraded omarchy (4.0.2-1 -> 4.0.3-1)"
  echo "[2026-09-08T20:43:59+0200] [ALPM] transaction completed"
  # Still inside the run: yay upgrading AUR packages, then the orphan sweep.
  echo "[2026-09-08T20:45:31+0200] [PACMAN] Running 'pacman -U --noconfirm --config /etc/pacman.conf -- /home/t/.cache/yay/inrun-bin/inrun-bin-2.0-1-x86_64.pkg.tar.zst'"
  echo "[2026-09-08T20:45:31+0200] [ALPM] upgraded inrun-bin (1.0-1 -> 2.0-1)"
  echo "[2026-09-08T20:47:10+0200] [PACMAN] Running 'pacman -Rns sweptorphan'"
  echo "[2026-09-08T20:47:10+0200] [ALPM] removed sweptorphan (1.0-1)"
  # Two days later, by hand. Same shapes, different event.
  echo "[2026-09-10T14:00:00+0200] [PACMAN] Running 'pacman -U --noconfirm --config /etc/pacman.conf -- /home/t/.cache/yay/later-bin/later-bin-1.0-1-x86_64.pkg.tar.zst'"
  echo "[2026-09-10T14:00:01+0200] [ALPM] installed later-bin (1.0-1)"
  echo "[2026-09-10T14:05:00+0200] [PACMAN] Running 'pacman -Rns leftover'"
  echo "[2026-09-10T14:05:00+0200] [ALPM] removed leftover (2.0-1)"
} >"$DRIFT"
D=$(WHAT_CHANGED_PACMAN_LOG="$DRIFT" "$CLI" show --json --expand other)
is "an AUR upgrade inside the run is kept" \
   "$(jq -r '[.groups[].items[]?|select(.name=="inrun-bin")]|length' <<<"$D")" 1
is "the orphan sweep inside the run is kept" \
   "$(jq -r '[.groups[].items[]?|select(.name=="sweptorphan")]|length' <<<"$D")" 1
is "an AUR install two days later is not" \
   "$(jq -r '[.groups[].items[]?|select(.name=="later-bin")]|length' <<<"$D")" 0
is "nor is a hand-run -Rns two days later" \
   "$(jq -r '[.groups[].items[]?|select(.name=="leftover")]|length' <<<"$D")" 0
is "and the counts agree" "$(jq -r '.session.counts.total' <<<"$D")" 3

# yay -S --needed is `omarchy pkg aur add`; yay -Sua, which the update runs,
# never passes it. So this is excluded even while the window is open.
ADD="$TMP/aur-add.log"
{
  echo "[2026-09-08T20:41:29+0200] [PACMAN] Running 'pacman -Sy --noconfirm archlinux-keyring'"
  echo "[2026-09-08T20:41:35+0200] [PACMAN] Running 'pacman -Syu --noconfirm --overwrite /usr/share/omarchy/*'"
  echo "[2026-09-08T20:42:02+0200] [ALPM] upgraded omarchy (4.0.2-1 -> 4.0.3-1)"
  echo "[2026-09-08T20:44:00+0200] [PACMAN] Running 'pacman -U --needed --noconfirm --config /etc/pacman.conf -- /home/t/.cache/yay/handadded/handadded-1.0-1-x86_64.pkg.tar.zst'"
  echo "[2026-09-08T20:44:01+0200] [ALPM] installed handadded (1.0-1)"
} >"$ADD"
is "omarchy pkg aur add is excluded even inside the window" \
   "$(WHAT_CHANGED_PACMAN_LOG="$ADD" "$CLI" show --json --expand other \
      | jq -r '[.groups[].items[]?|select(.name=="handadded")]|length')" 0

echo
echo "grouping does not mistake libraries for applications"
GRP="$TMP/group.log"
{
  echo "[2026-09-08T20:41:29+0200] [PACMAN] Running 'pacman -Sy --noconfirm archlinux-keyring'"
  echo "[2026-09-08T20:41:35+0200] [PACMAN] Running 'pacman -Syu --noconfirm --overwrite /usr/share/omarchy/*'"
  for n in codec2 vim-runtime mesa-utils dockerfile-language-server emacs-lisp-mode git-lfs \
           code vim mesa helix-git ghostty-bin mise-bin brave-origin-bin docker-compose \
           nvidia-utils linux-firmware-nvidia; do
    echo "[2026-09-08T20:42:02+0200] [ALPM] upgraded $n (1.0-1 -> 1.0-2)"
  done
} >"$GRP"
G=$(WHAT_CHANGED_PACMAN_LOG="$GRP" "$CLI" show --json --expand other)
group_of() { jq -r --arg n "$1" '[.groups[]|select(.items|map(.name)|index($n))|.id][0] // "missing"' <<<"$G"; }
for n in codec2 vim-runtime mesa-utils dockerfile-language-server emacs-lisp-mode git-lfs; do
  is "$n is not an app" "$(group_of "$n")" "other"
done
for n in code vim helix-git ghostty-bin mise-bin brave-origin-bin docker-compose; do
  is "$n is an app" "$(group_of "$n")" "apps"
done
for n in mesa nvidia-utils linux-firmware-nvidia; do
  is "$n wants a reboot" "$(group_of "$n")" "reboot"
done

echo
echo "options fail loudly"
out=$("$CLI" --expand 2>&1); rc=$?
is  "--expand with no argument exits non-zero" "$rc" 1
has "and says what it wanted" "$out" "requires a group name"
out=$("$CLI" show --expand 2>&1); rc=$?
is  "--expand as the last argument exits non-zero" "$rc" 1
out=$("$CLI" show --expand --json 2>&1); rc=$?
is  "--expand followed by a flag is refused" "$rc" 1
is  "--expand=other still works" \
    "$("$CLI" show 20260908T184129Z --json --expand=other | jq -r '.groups[]|select(.id=="other")|(.items|length)==.count')" "true"

echo
echo "a migration id that is not an id is skipped, not fatal"
# Its own state dir: the migration-window tests above populate the shared one.
mkdir -p "$TMP/hostile/migrations"
touch -d "2026-09-08T20:44:00+0200" "$TMP/hostile/migrations/1788577553.sh"
touch -d "2026-09-08T20:44:00+0200" "$TMP/hostile/migrations/bad\"quote.sh"
M2=$(WHAT_CHANGED_STATE_DIR="$TMP/hostile" "$CLI" show 20260908T184129Z --json)
is "the good migration survives" \
   "$(jq -r '[.groups[]|select(.id=="migrations").items[].name]|join(",")' <<<"$M2")" "1788577553"
is "the quoted one is skipped, not fatal" \
   "$(jq -r '.groups[]|select(.id=="migrations").summary' <<<"$M2")" "1 migration ran"

echo
echo "output cap"
for cmd in sessions show notes status; do
  n=$("$CLI" $cmd --json 2>/dev/null | wc -c)
  [[ $n -le 524288 ]] && ok "$cmd --json stays under the 512 KiB cap" \
    || no "$cmd --json stays under the 512 KiB cap" "<=524288" "$n"
done

echo
echo "human output"
has "sessions line carries the jump" "$("$CLI" sessions)" "4.0.2 → 4.0.3"
has "show header carries the jump"   "$("$CLI" show 20260908T184129Z)" "omarchy 4.0.2 → 4.0.3"
has "the pkgrel is stripped from the header" "$("$CLI" show 20260908T184129Z | head -1)" "4.0.2 → 4.0.3"
is  "labels read as dates, not stamps" \
    "$("$CLI" sessions --json | jq -r '.sessions[1].label')" "8 Sep 20:41"
has "counts lead with the total"     "$("$CLI" show 20260908T184129Z)" "packages changed"
has "and name what arrived and left" "$("$CLI" show 20260908T184129Z)" "removed"
is  "migrations collapse to a count, not a wall of ids" \
    "$("$CLI" show 20260908T184129Z --json | jq -r '.groups[]|select(.id=="migrations").summary')" \
    "2 migrations ran"
has "and the text view shows that summary" "$("$CLI" show 20260908T184129Z)" "2 migrations ran"
has "show header flags the reboot"   "$("$CLI" show 20260908T184129Z)" "reboot needed"
is  "no trailing whitespace in human output" \
    "$("$CLI" show 20260908T184129Z | grep -c ' $')" 0

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
