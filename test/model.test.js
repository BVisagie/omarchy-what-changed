// Intake tests for Model.js. The overlay renders whatever survives this layer,
// so these check that unknown fields are dropped, untrusted text is flattened,
// and a collapsed group stays collapsed until it is explicitly expanded.
//
// Run: node test/model.test.js

const M = require('../Model.js')

// Control characters as code points, so this file holds none of its own.
const C = code => String.fromCharCode(code)

let pass = 0
let fail = 0

function ok(name) { pass++; console.log('  ok   ' + name) }
function no(name, expected, actual) {
  fail++
  console.log('  FAIL ' + name)
  console.log('     expected: ' + expected)
  console.log('     actual:   ' + actual)
}
function is(name, actual, expected) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  a === e ? ok(name) : no(name, e, a)
}
function truthy(name, actual) { actual ? ok(name) : no(name, 'truthy', JSON.stringify(actual)) }

const SHOW = {
  schemaVersion: 1,
  session: {
    id: '20260908T184129Z',
    label: '2026-09-08 20:41',
    channel: 'stable',
    source: 'pacman-log',
    incomplete: false,
    rebootRequired: true,
    rebootReason: ['linux', 'mesa'],
    omarchy: { package: 'omarchy', from: '4.0.2-1', to: '4.0.3-1', jumped: true },
    counts: { upgraded: 135, installed: 5, removed: 4, downgraded: 0,
              reinstalled: 1, aur: 2, total: 145, omitted: 0 }
  },
  groups: [
    { id: 'omarchy', title: 'Omarchy',
      items: [{ kind: 'pkg', op: 'upgraded', name: 'omarchy', from: '4.0.2-1', to: '4.0.3-1', aur: false }] },
    { id: 'migrations', title: 'Migrations', items: [{ kind: 'migration', name: '1788577553' }] },
    { id: 'other', title: '127 other packages', collapsed: true, count: 127, items: [] }
  ]
}

console.log('intake drops what it does not know')
{
  const withJunk = JSON.parse(JSON.stringify(SHOW))
  withJunk.session.evilField = 'boo'
  withJunk.session.omarchy.evilField = 'boo'
  withJunk.groups[0].evilField = 'boo'
  withJunk.groups[0].items[0].evilField = 'boo'
  withJunk.topLevelJunk = { a: 1 }
  const r = M.parseShow(JSON.stringify(withJunk))
  truthy('payload still parses', r.ok)
  is('unknown session field dropped', r.session.evilField, undefined)
  is('unknown omarchy field dropped', r.session.omarchy.evilField, undefined)
  is('unknown group field dropped', r.groups[0].evilField, undefined)
  is('unknown item field dropped', r.groups[0].items[0].evilField, undefined)
  is('session keys are exactly the known set',
    Object.keys(r.session).sort(),
    ['channel', 'counts', 'id', 'incomplete', 'label', 'omarchy',
     'rebootReason', 'rebootRequired', 'source'])
  is('item keys are exactly the known set',
    Object.keys(r.groups[0].items[0]).sort(),
    ['aur', 'from', 'kind', 'name', 'op', 'to'])
  is('counts keys are exactly the known set',
    Object.keys(r.session.counts).sort(),
    ['aur', 'downgraded', 'installed', 'omitted', 'reinstalled',
     'removed', 'total', 'upgraded'])
}

console.log('')
console.log('untrusted text is flattened')
{
  is('control characters become spaces',
    M.text('ev' + C(0) + 'il' + C(27) + 'pkg' + C(7), 128), 'ev il pkg')
  is('newlines collapse in single-line text',
    M.text('one\ntwo\r\nthree', 128), 'one two three')
  is('bidi and zero-width overrides are stripped',
    M.text('safe‮gnp.exe​', 128), 'safe gnp.exe')
  is('long names are capped', M.text('x'.repeat(400), 16), 'x'.repeat(16) + '…')
  is('null becomes empty, not the string null', M.text(null, 16), '')
  is('numbers survive as text', M.text(42, 16), '42')

  const evil = { kind: 'pkg', op: 'upgraded', name: 'a' + C(0) + 'b\nc', from: 'x' + C(1), to: 'y', aur: false }
  const item = M.intakeItem(evil)
  is('item name is flattened', item.name, 'a b c')
  is('item version is flattened', item.from, 'x')
  truthy('no control characters survive intake',
    !JSON.stringify(item).split('').some(ch => ch.charCodeAt(0) < 32))
}

console.log('')
console.log('CLI diagnostics become sentences')
{
  is('a lowercase diagnostic is capitalised and stopped',
     M.sentence('pacman log is not readable: /var/log/pacman.log'),
     'Pacman log is not readable: /var/log/pacman.log.')
  is('an existing full stop is not doubled',
     M.sentence('no update sessions found.'), 'No update sessions found.')
  is('an ellipsis counts as terminal', M.sentence('reading…'), 'Reading…')
  is('nothing in, nothing out', M.sentence(''), '')
  is('a null message does not become "Null."', M.sentence(null), '')
  is('controls are flattened like any other untrusted text',
     M.sentence('bad' + C(27) + '[31m news'), 'Bad [31m news.')
  truthy('a runaway message is capped', M.sentence('x'.repeat(5000)).length <= 210)
}

console.log('')
console.log('release bodies keep their shape but not their controls')
{
  is('newlines survive', M.multiline('# Title\n\nBody text', 1000), '# Title\n\nBody text')
  is('carriage returns normalise', M.multiline('a\r\nb', 1000), 'a\nb')
  is('other controls still go', M.multiline('a' + C(0) + C(27) + 'b', 1000), 'a  b')
  is('runs of blank lines are bounded', M.multiline('a\n\n\n\n\n\nb', 1000), 'a\n\n\nb')
  truthy('a huge body is truncated', M.multiline('x'.repeat(500000), 1000).length < 1100)
}

console.log('')
console.log('collapsed groups')
{
  const r = M.parseShow(JSON.stringify(SHOW))
  const other = r.groups.filter(g => g.id === 'other')[0]
  is('collapsed flag survives', other.collapsed, true)
  is('count survives', other.count, 127)
  is('but no items are present', other.items.length, 0)

  const expanded = JSON.parse(JSON.stringify(SHOW))
  expanded.groups[2].items = Array.from({ length: 127 }, (_, i) =>
    ({ kind: 'pkg', op: 'upgraded', name: 'pkg' + i, from: '1', to: '2', aur: false }))
  const r2 = M.parseShow(JSON.stringify(expanded))
  const other2 = r2.groups.filter(g => g.id === 'other')[0]
  is('expanding fills the items', other2.items.length, 127)
  is('and the count still matches', other2.count, 127)

  const lying = JSON.parse(JSON.stringify(SHOW))
  lying.groups[2].count = -5
  is('a negative count is clamped',
    M.parseShow(JSON.stringify(lying)).groups.filter(g => g.id === 'other')[0].count, 0)
}

console.log('')
console.log('malformed payloads degrade')
{
  is('unparseable JSON', M.parseShow('not json').ok, false)
  is('and says so', M.parseShow('not json').error, 'Could not read this session.')
  is('empty string', M.parseShow('').ok, false)
  is('null session', M.parseShow('{"session":null}').ok, false)
  is('session without an id is refused', M.intakeSession({ label: 'x' }), null)
  is('groups that are not an array', M.parseShow('{"session":{"id":"a"},"groups":"x"}').groups, [])
  is('items that are not an array',
    M.intakeGroup({ id: 'x', title: 'X', items: 'nope' }).items, [])
  is('sessions list without an array', M.parseSessions('{}').ok, false)
  is('an empty sessions list is an error', M.parseSessions('{"sessions":[]}').ok, false)
}

console.log('')
console.log('links are restricted')
{
  is('a GitHub compare url passes',
    M.safeUrl('https://github.com/omacom/omarchy/compare/v4.0.2...v4.0.3'),
    'https://github.com/omacom/omarchy/compare/v4.0.2...v4.0.3')
  is('javascript: is refused', M.safeUrl('javascript:alert(1)'), '')
  is('http is refused', M.safeUrl('http://github.com/omacom/omarchy/releases/tag/v4.0.3'), '')
  is('another host is refused', M.safeUrl('https://evil.example/omacom/omarchy/x'), '')
  is('an embedded space is refused', M.safeUrl('https://github.com/a b/c/'), '')
}

console.log('')
console.log('notes intake')
{
  const notes = {
    status: 'ok',
    releases: [{ tag: 'v4.0.3', name: 'v4.0.3',
                 url: 'https://github.com/omacom/omarchy/releases/tag/v4.0.3',
                 body: 'Body\n\nMore', evilField: 'boo' }],
    message: ''
  }
  const r = M.parseNotes(JSON.stringify(notes))
  truthy('a fetched release is usable', r.ok)
  is('release keys are exactly the known set',
    Object.keys(r.releases[0]).sort(), ['blocks', 'body', 'name', 'tag', 'url'])
  is('no-jump is not renderable', M.parseNotes('{"status":"no-jump","releases":[]}').ok, false)
  is('unavailable is not renderable', M.parseNotes('{"status":"unavailable","releases":[]}').ok, false)
  is('ok with no releases is not renderable', M.parseNotes('{"status":"ok","releases":[]}').ok, false)
  is('garbage notes degrade', M.parseNotes('{{{').status, 'error')
}

console.log('')
console.log('header hierarchy')
{
  const s = M.parseShow(JSON.stringify(SHOW)).session
  const parts = M.headerParts(s)
  is('the header is parts, not one string', Array.isArray(parts), true)
  is('reboot is the last part', parts[parts.length - 1].text, 'reboot needed')
  is('and is marked urgent so the view can colour it',
    parts[parts.length - 1].kind, 'urgent')
  is('everything else is plain',
    parts.slice(0, -1).every(p => p.kind === 'plain'), true)

  const quiet = JSON.parse(JSON.stringify(SHOW))
  quiet.session.rebootRequired = false
  const q = M.headerParts(M.parseShow(JSON.stringify(quiet)).session)
  is('no reboot, no urgent part', q.some(p => p.kind === 'urgent'), false)
  is('an unknown channel is omitted',
    M.headerParts({ label: 'x', channel: 'unknown', omarchy: {}, counts: {} }).length, 2)
}

console.log('')
console.log('release notes are parsed to blocks, not left as markdown')
{
  const b = M.parseBlocks(
    '## Additional agentware\n\n### Add OpenClaw by @x\n\n' +
    'See [the team](https://omarchy.org/teams/#security) and _Install > AI_.\n\n' +
    '- First\n- Second **bold**\n\n---\n\nDownload: https://x/y.iso\nSHA256: abc\n')
  const types = b.map(x => x.type)
  is('headings are headings, not hashes', types[0], 'h2')
  is('sub-headings too', types[1], 'h3')
  is('heading text loses its markers', b[0].text, 'Additional agentware')
  is('links keep their label and drop the url',
    b[2].text, 'See the team and Install > AI.')
  is('bullets are bullets', b.filter(x => x.type === 'li').length, 2)
  is('emphasis markers go', b.filter(x => x.type === 'li')[1].text, 'Second bold')
  is('a rule is a rule', types.indexOf('rule') > -1, true)
  const last = b[b.length - 1]
  is('a single newline stays a line break, as GitHub renders it',
    last.text, 'Download: https://x/y.iso\nSHA256: abc')
  is('no markdown heading markers survive anywhere',
    b.some(x => /^#{1,6}\s/.test(x.text)), false)
  is('no inline link syntax survives',
    b.some(x => /\]\(/.test(x.text)), false)
  is('empty input yields no blocks', M.parseBlocks('').length, 0)
  is('a fenced block is kept verbatim',
    M.parseBlocks('```\n  keep  me\n```')[0].type, 'code')
}

console.log('')
console.log('status intake')
{
  const raw = {
    unread: true, lastRead: '20260908T184129Z',
    newest: { id: '20260909T063521Z', label: '2026-09-09 08:35',
              omarchy: { package: 'omarchy', from: '4.0.3-1', to: '4.0.3-1', jumped: false },
              counts: { upgraded: 1 }, evilField: 'boo' },
    evilTop: 'boo'
  }
  const r = M.parseStatus(JSON.stringify(raw))
  truthy('a status payload parses', r.ok)
  is('unread survives', r.unread, true)
  is('lastRead survives', r.lastRead, '20260908T184129Z')
  is('unknown fields are dropped from newest', r.newest.evilField, undefined)
  is('and from the top level', r.evilTop, undefined)
  is('garbage status degrades', M.parseStatus('{{{').ok, false)
  is('and reports nothing unread', M.parseStatus('{{{').unread, false)
  is('a status with no newest session', M.parseStatus('{"unread":false,"newest":null}').newest, null)
  is('unread is strictly boolean', M.parseStatus('{"unread":"yes"}').unread, false)
}

console.log('')
console.log('truncated output is surfaced')
{
  const big = JSON.parse(JSON.stringify(SHOW))
  big.outputTruncated = true
  is('parseShow reports it', M.parseShow(JSON.stringify(big)).outputTruncated, true)
  is('and defaults to false', M.parseShow(JSON.stringify(SHOW)).outputTruncated, false)
}

console.log('')
console.log('formatting')
{
  const s = M.parseShow(JSON.stringify(SHOW)).session
  is('header reads as one line',
    M.headerText(s), '2026-09-08 20:41  ·  omarchy 4.0.2 → 4.0.3  ·  stable  ·  reboot needed')
  is('the pkgrel is stripped', M.jumpText(s), 'omarchy 4.0.2 → 4.0.3')
  is('counts lead with the total and name arrivals and departures',
    M.countsText(s.counts), '145 packages changed  ·  5 added  ·  4 removed')
  is('upgrades and reinstalls are not itemised',
    M.countsText({ upgraded: 9, reinstalled: 1, total: 10 }), '10 packages changed')
  is('one change is singular',
    M.countsText({ upgraded: 1, total: 1 }), '1 package changed')
  is('no changes at all', M.countsText({ total: 0 }), 'No package changes')
  is('session summary', M.sessionSummary(s), '135↑ 5+ 4- 1↻')
  is('session version strips the pkgrel', M.sessionVersion(s), '4.0.2 → 4.0.3')
  is('a session with no jump shows one version',
    M.sessionVersion({ omarchy: { jumped: false, to: '4.0.3-1' } }), '4.0.3')
  is('upgrade row', M.versionText({ kind: 'pkg', op: 'upgraded', from: 'a', to: 'b' }), 'a → b')
  is('install row', M.versionText({ kind: 'pkg', op: 'installed', from: '', to: 'b' }), 'installed b')
  is('remove row', M.versionText({ kind: 'pkg', op: 'removed', from: 'a', to: '' }), 'removed a')
  is('migration row has no version', M.versionText({ kind: 'migration', name: '1' }), '')
}

console.log('')
console.log(pass + ' passed, ' + fail + ' failed')
process.exit(fail === 0 ? 0 : 1)
