#!/usr/bin/env python3
"""Exercise the complete viewer against installed Omarchy components offscreen.

Checks rendered text bounds, header collisions, scrolling and native close /
reopen lifecycle. The CLI is a fixture; no desktop or plugin files are changed.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
COMMONS = Path('/usr/share/omarchy/shell/Commons')
session = {
    'id': '20261019T051000Z', 'label': '19 Oct 07:10', 'channel': 'stable',
    'omarchy': {'from': '4.0.4-1', 'to': '4.0.5-1', 'jumped': True},
    'rebootStatus': 'unknown', 'rebootReason': ['linux'], 'incomplete': True,
    'counts': {'total': 337, 'installed': 16, 'removed': 4},
}
items = [{'name': 't3code-nightly-bin-' + 'long-package-name-' * 5,
          'op': 'upgraded', 'from': '0.1.1_nightly.20261017.3238-' + '1' * 32,
          'to': '0.1.1_nightly.20261018.3302-' + '2' * 32}] * 40
responses = {
    'sessions': {'sessions': [session, {**session, 'id': '20261017T061200Z',
                                      'label': '17 Oct 08:12'}]},
    'show': {'session': session, 'groups': [{'id': 'apps', 'title': 'Apps', 'items': items}],
             'currentRebootRequest': 'pending'},
    'notes': {'status': 'ok', 'releases': [{
        'tag': 'v4.0.5', 'name': 'Release ' + 'long-title-' * 10,
        'url': 'https://github.com/omacom/omarchy/releases/tag/v4.0.5',
        'body': '# Improvements\n\n' + '\n'.join([
            '- SHA256: ' + '73fd4334f1f67b19' * 8,
            '- Download: https://iso.omarchy.org/' + 'long-unbroken-path' * 10,
            'A paragraph of release notes with words that should wrap naturally.\n',
        ] * 20),
    }]},
}

QML = r'''import Quickshell
import QtQuick
import qs.Commons as Commons
ShellRoot {
  id: runner
  property int closeCalls: 0
  property int stage: 0
  property int sample: 0
  property var window: null
  property var cases: [
    {width: 1100, tab: "machine"}, {width: 900, tab: "notes"},
    {width: 600, tab: "machine"}, {width: 420, tab: "notes"},
    {width: 360, tab: "machine"}, {width: 360, tab: "notes"},
    {width: 360, tab: "machine", font: 18}, {width: 360, tab: "notes", font: 18}
  ]
  Overlay {
    id: viewer
    shell: QtObject {
      function hide(id) { runner.closeCalls++; viewer.close() }
    }
  }
  function check(ok, message) {
    if (!ok) { console.error("FAIL " + message); Qt.quit(); throw new Error(message) }
  }
  function find(node, name) {
    if (node.objectName === name) return node
    var children = node.data || node.children || []
    for (var i = 0; i < children.length; i++) {
      var found = find(children[i], name)
      if (found) return found
    }
    return node.contentItem ? find(node.contentItem, name) : null
  }
  function textRects(node, target, result) {
    if (!node.visible) return
    if (node.text !== undefined && node.contentWidth !== undefined && node.text !== "") {
      var p = node.mapToItem(target, 0, 0)
      check(node.contentWidth <= node.width + 1, "text exceeds its width: " + node.text.slice(0, 60))
      check(p.x >= -1 && p.x + node.width <= target.width + 1, "text outside window: " + node.text.slice(0, 60))
      result.push({x: p.x, y: p.y, width: node.width, height: node.height, text: node.text})
    }
    var children = node.children || []
    for (var i = 0; i < children.length; i++) textRects(children[i], target, result)
  }
  function inspect() {
    var header = find(viewer, "readingHeader")
    var body = find(viewer, "readingBody")
    var footer = find(viewer, "readingFooter")
    check(header.y + header.height <= body.y, "header overlaps body")
    check(body.height >= 79, "reading area remains usable")
    check(body.y + body.height <= footer.y, "body overlaps footer")
    var all = []
    textRects(window.contentItem, window.contentItem, all)
    check(all.length > 20, "loaded view contains rendered fixture text")
    var chrome = []
    textRects(header, window.contentItem, chrome)
    for (var i = 0; i < chrome.length; i++) for (var j = i + 1; j < chrome.length; j++) {
      var a = chrome[i], b = chrome[j]
      var x = Math.min(a.x + a.width, b.x + b.width) - Math.max(a.x, b.x)
      var y = Math.min(a.y + a.height, b.y + b.height) - Math.max(a.y, b.y)
      check(x <= 1 || y <= 1, "header collision: " + a.text + " / " + b.text)
    }
    check(body.maxScroll > 0, "long content scrolls")
    body.scrollTo(body.maxScroll + 100)
    check(Math.abs(body.contentY - body.maxScroll) < 1, "scroll clamps at bottom")
    body.scrollTo(-100)
    check(body.contentY === 0, "scroll clamps at top")
    console.log("PASS " + viewer.tab + " width=" + window.width + " font=" + Commons.Style.fontBaseSize)
  }
  Component.onCompleted: viewer.open("{}")
  Timer {
    interval: 150; repeat: true; running: true
    onTriggered: {
      if (viewer.sessionsLoading || viewer.showLoading || viewer.notesLoading) return
      if (stage === 0) {
        window = find(viewer, "readingWindow")
        check(window !== null, "normal window loads")
        Commons.Style.spacingScaleWithFont = false
        Commons.Style.spacingScale = 1
        stage = 1
      } else if (stage === 1) {
        var c = cases[sample]
        Commons.Style.fontBaseSize = c.font || 12
        window.contentItem.Window.window.width = c.width
        window.contentItem.Window.window.height = 850
        viewer.setTab(c.tab)
        stage = 2
      } else if (stage === 2) {
        check(Math.abs(window.width - cases[sample].width) < 1, "requested width is exercised")
        check(viewer.background === Commons.Color.menu.background, "viewer uses the Omarchy palette")
        inspect()
        sample++
        if (sample < cases.length) { stage = 1; return }
        viewer.startRequest("probe", [viewer.cli, "probe"], viewer.currentSession.id)
        window.contentItem.Window.window.close()
        check(!viewer.opened && runner.closeCalls === 1, "native close notifies host once")
        check(Object.keys(viewer.requests).every(function(k) { return !viewer.requests[k] }), "close cancels requests")
        // The test runner must survive a reader close, as the real shell does.
        viewer.open("{}")
        stage = 3
      } else {
        check(viewer.opened && window.visible && viewer.session, "viewer reopens after native close")
        viewer.dismiss()
        check(!viewer.opened && runner.closeCalls === 2, "keyboard dismissal uses same host lifecycle")
        console.log("WINDOW_OK")
        Qt.quit()
      }
    }
  }
}
'''

with tempfile.TemporaryDirectory(prefix='what-changed-window-') as temporary:
    work = Path(temporary)
    for name in ['Overlay.qml', 'SessionHeader.qml', 'MachineView.qml', 'NotesView.qml', 'Model.js']:
        shutil.copy(ROOT / name, work)
    (work / 'Commons').symlink_to(COMMONS, target_is_directory=True)
    (work / 'bin').mkdir()
    (work / 'responses.json').write_text(json.dumps(responses))
    cli = work / 'bin/what-changed'
    cli.write_text('''#!/usr/bin/env python3
import json, pathlib, sys, time
if sys.argv[1] == 'probe':
    time.sleep(5)
responses = json.loads((pathlib.Path(__file__).resolve().parents[1] / 'responses.json').read_text())
if sys.argv[1] in responses:
    print(json.dumps(responses[sys.argv[1]]))
''')
    cli.chmod(0o755)
    (work / 'shell.qml').write_text(QML)
    (work / 'runtime').mkdir(mode=0o700)
    env = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': '',
           'QT_QUICK_BACKEND': 'software', 'XDG_STATE_HOME': str(work / 'state'),
           'XDG_CACHE_HOME': str(work / 'cache'), 'XDG_RUNTIME_DIR': str(work / 'runtime')}
    env.pop('WAYLAND_DISPLAY', None)
    try:
        result = subprocess.run(['qs', '--no-color', '-p', str(work / 'shell.qml')],
                                env=env, capture_output=True, text=True, timeout=15)
    except subprocess.TimeoutExpired as error:
        print((error.stdout or b'').decode() + (error.stderr or b'').decode())
        raise SystemExit('Quickshell window acceptance timed out') from error
    output = result.stdout + result.stderr
    print(output)
    if result.returncode or 'WINDOW_OK' not in output or re.search(r'FAIL |\bERROR(?:\s|:)|Binding loop', output):
        raise SystemExit('Quickshell window acceptance failed')
