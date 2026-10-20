#!/usr/bin/env python3
"""Exercise the complete viewer against installed Omarchy components offscreen.

Checks rendered bounds in wide/short tiles, font-scaled spacing, scrolling and
native close/reopen. The CLI is a fixture; no desktop or plugin files are changed.
"""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
COMMONS = Path(os.environ.get('OMARCHY_PATH') or '/usr/share/omarchy').expanduser() / 'shell/Commons'
missing = []
if shutil.which('qs') is None:
    missing.append('Quickshell (qs) on PATH')
if not (COMMONS / 'qmldir').is_file():
    missing.append('Omarchy Commons at ' + str(COMMONS))
if missing:
    print('SKIP window.test.py: requires ' + ' and '.join(missing))
    raise SystemExit(0)

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
    'sessions': {'defaultSessionId': session['id'],
                 'sessions': [{**session, 'id': '20261019T052000Z', 'label': '19 Oct 07:20',
                               'counts': {'total': 0}, 'incomplete': False},
                              session, {**session, 'id': '20261017T061200Z', 'label': '17 Oct 08:12'}]},
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
  property var minimumByStyle: ({})
  property var cases: [
    {width: 360, height: 220, tab: "machine"},
    {width: 1100, height: 850, tab: "machine"},
    {width: 360, height: 220, tab: "machine"}, {width: 360, height: 220, tab: "notes"},
    {width: 900, height: 850, tab: "notes"}, {width: 600, height: 850, tab: "machine"},
    {width: 420, height: 850, tab: "notes"}, {width: 360, height: 850, tab: "machine"},
    {width: 360, height: 850, tab: "notes"},
    {width: 360, height: 850, tab: "machine", font: 18, scaleSpacing: false},
    {width: 360, height: 850, tab: "notes", font: 18, scaleSpacing: false},
    {width: 360, height: 220, tab: "machine", font: 18},
    {width: 360, height: 220, tab: "notes", font: 18},
    {width: 640, height: 850, tab: "notes", font: 18},
    {width: 790, height: 790, tab: "machine", font: 48},
    {width: 790, height: 790, tab: "notes", font: 48}
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
    check(header.y + header.height <= footer.y, "header overlaps footer in a short tile")
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
    var viewport = find(viewer, "readingViewport")
    var scroll = viewport && viewport.compactHeight ? viewport : body
    if (viewport && viewport.compactHeight)
      check(Math.abs(body.contentY) < 1, "whole-page mode does not also offset the nested body")
    check(scroll.clip && scroll.height > 0, "active scroller clips to a usable viewport")
    check(body.maxScroll > 0, "long content scrolls")
    body.scrollTo(body.maxScroll + 100)
    check(Math.abs(scroll.contentY - body.maxScroll) < 1, "scroll clamps at bottom")
    var footerTexts = []
    textRects(footer, window.contentItem, footerTexts)
    check(footerTexts.some(function(t) { return t.text === "Esc / q close" }), "footer advertises the reader's close keys")
    if (viewport && viewport.compactHeight) {
      var p = footer.mapToItem(viewport, 0, 0)
      check(p.y >= -1 && p.y + footer.height <= viewport.height + 1, "short tile can scroll to the whole footer")
    }
    body.scrollTo(-100)
    check(scroll.contentY === 0, "scroll clamps at top")
    body.scrollBy(60)
    check(scroll.contentY > 0, "reading shortcuts scroll the active viewport")
    body.scrollTo(0)
    check(Math.abs(body.pageHeight - scroll.height) < 1, "page keys use the visible scroll viewport")
    body.scrollBy(body.pageHeight * 0.9)
    check(scroll.contentY > 0 && scroll.contentY <= scroll.height, "page scroll advances at most one visible page")
    // Leave a scroll offset so the next case also exercises mode changes
    // while reading, including a wide-to-short resize without changing tabs.
    body.scrollTo(Math.min(60, body.maxScroll))
    var minimum = window.minimumSize
    var style = Commons.Style.fontBaseSize + ":" + Commons.Style.spacingScaleWithFont
    if (runner.minimumByStyle[style]) {
      check(minimum.width === runner.minimumByStyle[style].width
        && minimum.height === runner.minimumByStyle[style].height, "minimum size is independent of wrapping")
    } else runner.minimumByStyle[style] = {width: minimum.width, height: minimum.height}
    check(minimum.width > 0 && minimum.height > 0, "advertised size hints survive forced tile geometry")
    check(minimum.width <= window.screen.width && minimum.height <= window.screen.height, "minimum fits the screen")
    console.log("PASS " + viewer.tab + " size=" + window.width + "x" + window.height
      + " font=" + Commons.Style.fontBaseSize + " scaledSpacing=" + Commons.Style.spacingScaleWithFont)
  }
  function resizeTile(c) {
    // Tiled compositors may ignore size hints. Bypass only the backing Qt
    // window's enforcement; keep the viewer's advertised minimum for checks.
    var native = window.contentItem.Window.window
    native.minimumWidth = 0
    native.minimumHeight = 0
    native.width = c.width
    native.height = c.height
  }
  Component.onCompleted: viewer.open("{}")
  Timer {
    interval: 150; repeat: true; running: true
    onTriggered: {
      if (viewer.sessionsLoading || viewer.showLoading || viewer.notesLoading) return
      if (stage === 0) {
        window = find(viewer, "readingWindow")
        check(window !== null, "normal window loads")
        check(viewer.sessionIndex === 1 && viewer.session.id === viewer.sessions[1].id,
          "viewer opens the CLI default behind a newer no-op")
        Commons.Style.spacingScale = 1
        stage = 1
      } else if (stage === 1) {
        var c = cases[sample]
        Commons.Style.fontBaseSize = c.font || 12
        Commons.Style.spacingScaleWithFont = c.scaleSpacing !== false
        viewer.setTab(c.tab)
        stage = 2
      } else if (stage === 2) {
        resizeTile(cases[sample])
        stage = 3
      } else if (stage === 3) {
        // Give width-dependent layout a frame to settle before enforcing the
        // tile again, just as a compositor can override new size hints.
        resizeTile(cases[sample])
        stage = 4
      } else if (stage === 4) {
        check(Math.abs(window.width - cases[sample].width) < 1, "requested width is exercised")
        check(Math.abs(window.height - cases[sample].height) < 1, "requested height is exercised")
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
        stage = 5
      } else {
        check(viewer.opened && window.visible && viewer.session, "viewer reopens after native close")
        check(viewer.sessionIndex === 1, "reopening preserves the CLI default selection")
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
                                env=env, capture_output=True, text=True, timeout=25)
    except subprocess.TimeoutExpired as error:
        print((error.stdout or b'').decode() + (error.stderr or b'').decode())
        raise SystemExit('Quickshell window acceptance timed out') from error
    output = result.stdout + result.stderr
    print(output)
    if result.returncode or 'WINDOW_OK' not in output or re.search(r'FAIL |\bERROR(?:\s|:)|Binding loop', output):
        raise SystemExit('Quickshell window acceptance failed')
