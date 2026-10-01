#!/usr/bin/env python3
"""Run the overlay request code in a separate offscreen Quickshell instance.

No installed plugin or desktop configuration is modified. Timers belong only
in this test harness, to force overlapping CLI requests and observe SIGTERM.
"""
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'Overlay.qml').read_text()
methods = source[source.index('  // Each launch owns'):source.index('  // ----------------------------------------------------------------- procs')]
process = source[source.index('  Component {\n    id: requestProcess'):source.index('  // ---------------------------------------------------------------- window')]
with tempfile.TemporaryDirectory(prefix='what-changed-runtime-') as temporary:
    work = Path(temporary)
    shutil.copy(ROOT / 'Model.js', work)
    fake_cli = work / 'fake-cli'
    fake_cli.write_text('''#!/usr/bin/env python3
import json, signal, sys, time
kind = sys.argv[1]
sid = sys.argv[2] if len(sys.argv) > 2 else ''
def terminated(*args):
    print('cancelled stdout', flush=True)
    print('cancelled stderr', file=sys.stderr, flush=True)
    sys.exit(23)
signal.signal(signal.SIGTERM, terminated)
if kind == 'cancel-probe':
    print('ready', flush=True)
    time.sleep(3)
    sys.exit(0)
time.sleep(0.6 if sid in ['A','B'] else 0.05)
if kind == 'show':
    print(json.dumps({'session': {'id': sid, 'omarchy': {}}, 'groups': [{'id': sid, 'items': []}], 'currentRebootRequest': 'pending'}))
elif kind == 'notes':
    print(json.dumps({'status': 'ok', 'releases': [{'tag': sid, 'body': 'Notes for ' + sid}]}))
elif kind == 'compare-url':
    print('https://github.com/omacom/omarchy/compare/v4.0.3...v4.0.4')
''')
    fake_cli.chmod(0o755)
    prefix = '''import Quickshell
import Quickshell.Io
import QtQuick
import "Model.js" as Model
ShellRoot {
  Item {
    id: root
    property bool opened: true
    property string cli: CLI_PATH
    property string tab: "notes"
    property var sessions: [{id: "A", omarchy: {jumped: true}}, {id: "B", omarchy: {jumped: true}}, {id: "C", omarchy: {jumped: true}}]
    property int sessionIndex: 0
    readonly property var currentSession: sessions[sessionIndex] || null
    property var session: null
    property var groups: []
    property string showError: ""
    property bool showLoading: false
    property bool expanded: false
    property bool outputTruncated: false
    property var notes: null
    property bool notesLoading: false
    property bool notesLoaded: false
    property bool sessionsLoading: false
    property bool sessionsUnavailable: false
    property string sessionsError: ""
    property string sessionsStderr: ""
    property string currentRebootRequest: "absent"
    property string requestedSessionId: ""
    property int compared: 0
    property var probeOrder: []
    property bool probeCancellationRequested: false
    Item { id: body; property int contentY: 200; function scrollTo(y) { contentY = y } }
    function check(value, message) {
      if (!value) { console.error("FAIL " + message); Qt.quit() }
      else console.log("PASS " + message)
    }
'''.replace('CLI_PATH', json.dumps(str(fake_cli)))
    # Keep URL validation but intercept opening a browser in the test process.
    methods = methods.replace('Quickshell.execDetached(["xdg-open", url])', 'root.compared++')
    suffix = '''
    Component.onCompleted: { root.loadSession(); root.openCompare(); probe.running = true }
    Timer { interval: 120; running: true; onTriggered: {
      root.step(1); root.openCompare(); root.check(root.session === null, "B clears session")
    } }
    Timer { interval: 240; running: true; onTriggered: {
      root.step(1); root.openCompare(); root.check(body.contentY === 0, "navigation resets scroll")
    } }
    Timer { interval: 1200; running: true; onTriggered: {
      root.check(root.session && root.session.id === "C", "delayed show settles on C")
      root.check(root.notes && root.notes.releases[0].tag === "C", "delayed notes settle on C")
      root.check(root.showError === "", "cancelled exit cannot overwrite C")
      root.check(!root.showLoading && !root.notesLoading, "current requests finish")
      root.check(root.compared === 1, "only C compare action completes")
      root.check(root.currentRebootRequest === "pending", "overlay receives current reboot request")
      root.check(probe.exitDone && probe.stdoutDone && probe.stderrDone, "running false finishes both collectors and exit")
      root.check(probe.exitCode === 23, "running false sends SIGTERM and preserves handler exit code")
      console.log("CANCELLATION_ORDER " + root.probeOrder.join(","))
      console.log("RUNTIME_OK")
      Qt.quit()
    } }
    Process {
      id: probe
      property bool exitDone: false
      property bool stdoutDone: false
      property bool stderrDone: false
      property int exitCode: -1
      command: [root.cli, "cancel-probe"]
      stdout: StdioCollector {
        waitForEnd: false
        onTextChanged: {
          if (!root.probeCancellationRequested && text.indexOf("ready") >= 0) {
            root.probeCancellationRequested = true
            probe.running = false
          }
        }
        onStreamFinished: {
        probe.stdoutDone = true; root.probeOrder.push("stdout")
        root.check(text.indexOf("cancelled stdout") >= 0, "cancelled process flushes stdout")
      } }
      stderr: StdioCollector { onStreamFinished: {
        probe.stderrDone = true; root.probeOrder.push("stderr")
        root.check(text.indexOf("cancelled stderr") >= 0, "cancelled process flushes stderr")
      } }
      onExited: function(code) {
        probe.exitDone = true; probe.exitCode = code
        root.probeOrder.push("exit")
      }
    }
  }
}
'''
    (work / 'shell.qml').write_text(prefix + methods + process + suffix)
    env = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': '', 'QT_QUICK_BACKEND': 'software', 'XDG_STATE_HOME': str(work / 'state'),
           'XDG_CACHE_HOME': str(work / 'cache'), 'XDG_RUNTIME_DIR': str(work / 'runtime')}
    env.pop('WAYLAND_DISPLAY', None)
    (work / 'runtime').mkdir(mode=0o700)
    result = subprocess.run(['qs', '--no-color', '-p', str(work / 'shell.qml')],
                            env=env, capture_output=True, text=True, timeout=10)
    output = result.stdout + result.stderr
    print(output)
    if result.returncode or 'RUNTIME_OK' not in output or 'FAIL ' in output or re.search(r'\bERROR(?:\s|:)', output):
        raise SystemExit('Quickshell runtime acceptance failed')
