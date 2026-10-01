// Exercise the actual Overlay lifecycle functions with controlled callbacks.
// Quickshell integration and cancellation are covered by runtime.test.py.
const fs = require('node:fs')
const vm = require('node:vm')
const assert = require('node:assert/strict')
const Model = require('../Model.js')
const source = fs.readFileSync(require.resolve('../Overlay.qml'), 'utf8')
const methods = source.slice(source.indexOf('  function isCurrentRequest('), source.indexOf('  // ----------------------------------------------------------------- procs'))
  .replace(/^  property .*$/gm, '')
const launches = []
const urls = []
const body = {contentY: 200, scrollTo(y) { this.contentY = y }}
const root = {opened: true, requests: {}, requestGeneration: 0, cli: '/fake/cli', tab: 'notes',
  sessionIndex: 0, sessions: ['A', 'B', 'C'].map(id => ({id, omarchy: {jumped: true}})),
  requestedSessionId: '', expanded: false}
Object.defineProperty(root, 'currentSession', {get() { return this.sessions[this.sessionIndex] || null }})
const requestProcess = {createObject(parent, options) {
  const proc = {...options, stdoutDone: false, stderrDone: false, exitDone: false, exitCode: 0,
    outputText: '', errorText: '', running: false, destroy() { this.destroyed = true }}
  launches.push(proc)
  return proc
}}
const context = {root, Model, body, requestProcess, Quickshell: {execDetached(argv) { urls.push(argv) }}}
vm.createContext(context)
vm.runInContext(methods, context)
for (const key of Object.keys(context)) if (typeof context[key] === 'function') root[key] = context[key]

let pass = 0
function check(name, test) { test(); pass++; console.log('  ok   ' + name) }
function result(proc, payload, order, code = 0, error = '') {
  proc.outputText = payload
  proc.errorText = error
  proc.exitCode = code
  for (const event of order) {
    proc[event + 'Done'] = true
    root.finishRequest(proc)
  }
}
const show = id => JSON.stringify({session: {id, omarchy: {}}, groups: [{id, items: []}], currentRebootRequest: 'pending'})
const notes = id => JSON.stringify({status: 'ok', releases: [{tag: id, body: 'Notes for ' + id}]})

root.loadSession()
root.openCompare()
const first = launches.slice()
root.step(1)
root.openCompare()
const second = launches.slice(first.length)
root.step(1)
root.openCompare()
check('navigation clears stale data and scroll', () => {
  assert.equal(root.session, null)
  assert.equal(root.notes, null)
  assert.equal(root.notesLoading, true)
  assert.equal(root.groups.length, 0)
  assert.equal(body.contentY, 0)
})
check('every superseded request is stopped and destroyed', () => {
  assert.ok(first.concat(second).every(p => !p.running && p.destroyed))
  assert.ok(first.concat(second).every(p => !root.isCurrentRequest(p)))
  assert.ok(Object.isFrozen(first[0].identity))
  assert.equal(new Set(launches.map(p => p.identity.generation)).size, launches.length)
})
for (const proc of first.concat(second)) {
  const kind = proc.identity.kind
  result(proc, kind === 'show' ? show(proc.identity.sessionId) : kind === 'notes' ? notes(proc.identity.sessionId)
    : 'https://github.com/omacom/omarchy/compare/v4.0.2...v4.0.3', ['exit', 'stderr', 'stdout'], 15, 'old error')
}
check('stale stdout stderr and cancellation exits cannot change C', () => {
  assert.equal(root.session, null)
  assert.equal(root.notes, null)
  assert.equal(root.showError, '')
  assert.equal(root.showLoading, true)
  assert.equal(root.notesLoading, true)
  assert.equal(urls.length, 0)
})
const cShow = root.requests.show
cShow.exitCode = 0
cShow.exitDone = true
root.finishRequest(cShow)
check('exit before collectors does not consume unfinished output', () => assert.equal(root.session, null))
result(cShow, show('C'), ['stderr', 'stdout'])
result(root.requests.notes, notes('C'), ['stdout', 'stderr', 'exit'])
check('both callback orders produce C data', () => {
  assert.equal(root.session.id, 'C')
  assert.equal(root.notes.releases[0].tag, 'C')
  assert.equal(root.showLoading, false)
  assert.equal(root.notesLoading, false)
  assert.equal(root.currentRebootRequest, 'pending')
})
result(root.requests.compare, 'https://github.com/omacom/omarchy/compare/v4.0.3...v4.0.4', ['stdout', 'exit', 'stderr'])
check('only current compare opens a validated URL', () => {
  assert.equal(urls.length, 1)
  assert.equal(urls[0][0], 'xdg-open')
})
root.loadSession()
result(root.requests.show, show('A'), ['stdout', 'stderr', 'exit'])
check('a mismatched response ID is rejected', () => {
  assert.equal(root.session, null)
  assert.equal(root.showError, 'Could not read this session.')
})
root.reloadSessions()
const staleList = root.requests.sessions
root.reloadSessions()
result(staleList, JSON.stringify({sessions: [{id: 'A'}]}), ['exit', 'stdout', 'stderr'], 1, 'stale list error')
check('superseded session list callbacks are ignored', () => assert.equal(root.sessionsLoading, true))
result(root.requests.sessions, '', ['exit', 'stdout', 'stderr'], 3, 'what-changed: no update sessions found')
check('failed list exit and stderr produce a specific empty-history answer', () => {
  assert.equal(root.sessionsUnavailable, false)
  assert.equal(root.sessionsLoading, false)
  assert.equal(root.sessionsError, 'No update sessions found.')
  assert.equal(root.sessions.length, 0)
})
result(root.requests['system-status'], JSON.stringify({unread: false, newest: null, currentRebootRequest: 'pending'}), ['stdout', 'stderr', 'exit'])
check('a current reboot request is visible with empty history', () => assert.equal(root.currentRebootRequest, 'pending'))
root.startRequest('sessions', [root.cli, 'sessions', '--json'], '')
result(root.requests.sessions, '', ['stdout', 'stderr', 'exit'], 1, 'what-changed: pacman log is not readable')
check('collector before exit preserves the real log diagnostic', () => {
  assert.equal(root.sessionsUnavailable, true)
  assert.equal(root.sessionsError, 'Pacman log is not readable.')
})
root.cancelRequests()
const emptyLaunchCount = launches.length
root.sessionsLoading = false
root.expanded = false
root.expandOther()
root.step(1)
root.openCompare()
root.loadNotes()
check('empty-history actions cannot launch invalid requests', () => assert.equal(launches.length, emptyLaunchCount))
console.log(pass + ' passed, 0 failed')
