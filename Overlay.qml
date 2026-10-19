import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons as Commons
import "Model.js" as Model

// What Changed — a reading surface for the update that just ran.
//
// Every fact on screen comes from `bin/what-changed --json`. That is a boundary,
// not an implementation detail: the CLI is the only thing this file executes, so
// each Process command stays a fixed argv array and every string it returns is
// rendered as Text.PlainText.
Item {
  id: root

  // Injected by the shell's panel Loader when it mounts this plugin. Without
  // them a dismissal can only hide the window; the host still counts the plugin
  // as open and keeps the Loader mounted for the rest of the shell session.
  property var shell: null
  property var manifest: null

  property bool opened: false
  property string tab: "machine"          // "machine" | "notes"

  property var sessions: []
  property int sessionIndex: 0
  property string sessionsError: ""
  property bool sessionsLoading: true
  // An empty history and an unreadable log are different answers, and only one
  // of them is fixed by running an update. The CLI separates them with exit 3.
  property bool sessionsUnavailable: false
  property string sessionsStderr: ""

  property string currentRebootRequest: "absent"

  property var session: null
  property var groups: []
  property string showError: ""
  property bool showLoading: false
  property bool expanded: false
  property bool outputTruncated: false

  property var notes: null
  property bool notesLoading: false
  property bool notesLoaded: false

  // The CLI ships inside the plugin, so resolve it from this file rather than
  // guessing at $HOME — the plugin folder is wherever the user installed it.
  readonly property string cli:
    decodeURIComponent(String(Qt.resolvedUrl("bin/what-changed")).replace(/^file:\/\//, ""))

  // Shares the [menu] surface tokens, so a theme that styles the Omarchy menu
  // styles this too.
  readonly property color background: Commons.Color.menu.background
  readonly property color foreground: Commons.Color.menu.text
  readonly property color selectedBackground: Commons.Color.menu.selectedBackground
  readonly property color selectedText: Commons.Color.menu.selectedText

  readonly property string fontFamily: Commons.Style.font.menuFamily
  readonly property int cornerRadius: Commons.Style.cornerRadius
  readonly property int contentMargin: Commons.Style.spacing.panelPadding

  readonly property var currentSession:
    (sessionIndex >= 0 && sessionIndex < sessions.length) ? sessions[sessionIndex] : null

  // ------------------------------------------------------------- lifecycle

  function open(payloadJson) {
    root.opened = true
    root.tab = "machine"
    root.expanded = false
    root.applyPayload(payloadJson)
    root.reloadSessions()
    root.markRead()
    Qt.callLater(function () {
      if (!root.opened) return
      readingWindow.minimized = false
      keyCatcher.forceActiveFocus()
      if (keyCatcher.Window.window) keyCatcher.Window.window.requestActivate()
    })
  }

  // Opening the viewer answers "anything since I last looked?", so it clears
  // the whole backlog rather than only the session you happen to browse.
  function markRead() {
    markReadProc.running = false
    markReadProc.running = true
  }

  // Host-initiated teardown (`shell hide` lands here). It must not call back
  // into shell.hide(), which is what invoked it.
  function close() { root.opened = false; root.cancelRequests() }

  // Every user-initiated dismissal — Esc, q, window close — goes through the host
  // so `keepLoaded: false` actually unloads us again.
  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.bvisagie.what-changed")
    else
      root.close()
  }

  function toggle() { if (root.opened) root.dismiss(); else root.open("{}") }

  property string requestedSessionId: ""

  function applyPayload(payloadJson) {
    root.requestedSessionId = ""
    if (!payloadJson) return
    try {
      var p = JSON.parse(String(payloadJson))
      if (!p || typeof p !== "object") return
      if (typeof p.session === "string") root.requestedSessionId = Model.text(p.session, 32)
      if (p.tab === "notes" || p.tab === "machine") root.tab = p.tab
    } catch (e) {
      // A malformed payload just means "open at the newest session".
    }
  }

  // ------------------------------------------------------------- data load

  // Each launch owns a separate Process and a frozen identity. Stopping an
  // older process cannot relabel its collector/exit callbacks as a new request.
  property var requests: ({})
  property int requestGeneration: 0

  function isCurrentRequest(proc) {
    return root.opened && root.requests[proc.identity.kind] === proc
      && ((proc.identity.kind === "sessions" || proc.identity.kind === "system-status")
          || (root.currentSession && root.currentSession.id === proc.identity.sessionId))
  }

  function cancelRequest(kind) {
    var proc = root.requests[kind]
    if (!proc) return
    root.requests[kind] = null
    proc.running = false
    proc.destroy()
  }

  function cancelRequests() {
    for (var kind in root.requests) root.cancelRequest(kind)
  }

  function startRequest(kind, argv, sessionId) {
    root.cancelRequest(kind)
    var identity = Object.freeze({kind: kind, sessionId: sessionId || "",
                                  generation: ++root.requestGeneration, argv: Object.freeze(argv.slice())})
    var proc = requestProcess.createObject(root, {identity: identity})
    root.requests[kind] = proc
    proc.running = true
  }

  function clearSession() {
    root.cancelRequest("show")
    root.cancelRequest("notes")
    root.cancelRequest("compare")
    root.cancelRequest("system-status")
    root.session = null
    root.groups = []
    root.showError = ""
    root.showLoading = false
    root.outputTruncated = false
    root.notes = null
    root.notesLoading = false
    root.notesLoaded = false
    body.scrollTo(0)
  }

  function reloadSessions() {
    root.clearSession()
    root.sessionsLoading = true
    root.sessionsError = ""
    root.sessionsUnavailable = false
    root.sessionsStderr = ""
    root.startRequest("sessions", [root.cli, "sessions", "--json"], "")
  }

  function onSessionsRead(out) {
    var r = Model.parseSessions(out)
    root.sessionsLoading = false
    root.sessions = r.sessions
    root.sessionsError = r.error
    root.currentRebootRequest = r.currentRebootRequest || "absent"
    var index = 0
    if (root.requestedSessionId)
      for (var i = 0; i < r.sessions.length; i++)
        if (r.sessions[i].id === root.requestedSessionId) { index = i; break }
    root.sessionIndex = index
    root.requestedSessionId = ""
    if (r.sessions.length > 0) root.loadSession()
  }

  function loadSession() {
    root.clearSession()
    if (!root.currentSession) return
    root.showLoading = true
    root.requestShow()
    if (root.tab === "notes") root.loadNotes()
  }

  function requestShow() {
    if (!root.currentSession || root.sessionsLoading) return
    var id = root.currentSession.id
    var argv = [root.cli, "show", id, "--json"]
    if (root.expanded) argv = argv.concat(["--expand", "other"])
    root.startRequest("show", argv, id)
  }

  function onShowRead(out, sessionId) {
    var r = Model.parseShow(out)
    root.showLoading = false
    if (r.session && r.session.id !== sessionId) {
      root.showError = "Could not read this session."
      return
    }
    root.session = r.session
    root.groups = r.groups
    root.showError = r.error
    root.outputTruncated = r.outputTruncated === true
    root.currentRebootRequest = r.currentRebootRequest || "absent"
  }

  function loadNotes() {
    if (root.notesLoaded || root.notesLoading || root.sessionsLoading || !root.currentSession) return
    root.notesLoading = true
    var id = root.currentSession.id
    root.startRequest("notes", [root.cli, "notes", id, "--json"], id)
  }

  function onNotesRead(out) {
    root.notes = Model.parseNotes(out)
    root.notesLoading = false
    root.notesLoaded = true
  }

  // Wait for both collectors and exit before consuming a result. Quickshell
  // can deliver these in either order, including on cancellation.
  function finishRequest(proc) {
    if (!root.isCurrentRequest(proc) || !proc.stdoutDone || !proc.stderrDone || !proc.exitDone) return
    var kind = proc.identity.kind
    var code = proc.exitCode
    var diagnostic = Model.sentence(String(proc.errorText || "").replace(/^what-changed:\s*/, "").trim())
    if (kind === "sessions") {
      if (code === 0) root.onSessionsRead(proc.outputText)
      else {
        root.sessionsLoading = false
        root.sessions = []
        root.sessionsUnavailable = code !== 3
        root.sessionsError = diagnostic || (code === 3
          ? "No update sessions found in /var/log/pacman.log." : "Could not read /var/log/pacman.log.")
        // status still answers for an empty history, so an unrelated current
        // reboot request remains visible without changing sessions exit code 3.
        if (code === 3) root.startRequest("system-status", [root.cli, "status", "--json"], "")
      }
    } else if (kind === "system-status") {
      if (code === 0) root.currentRebootRequest = Model.parseRebootRequest(proc.outputText)
    } else if (kind === "show") {
      if (code === 0) root.onShowRead(proc.outputText, proc.identity.sessionId)
      else { root.showLoading = false; root.showError = diagnostic || "Could not read this session." }
    } else if (kind === "notes") {
      if (code === 0) root.onNotesRead(proc.outputText)
      else {
        root.notesLoading = false
        root.notesLoaded = true
        root.notes = {ok: false, status: "error", releases: [],
                      message: diagnostic || "Release notes are unavailable."}
      }
    } else if (kind === "compare" && code === 0) root.onCompareRead(proc.outputText)
    if (root.requests[kind] === proc) root.requests[kind] = null
    proc.destroy()
  }

  // --------------------------------------------------------------- actions

  function step(delta) {
    if (root.sessionsLoading || root.sessions.length === 0) return
    var next = root.sessionIndex + delta
    if (next < 0 || next >= root.sessions.length) return
    root.sessionIndex = next
    root.expanded = false
    root.loadSession()
  }

  function setTab(name) {
    if (root.tab === name) return
    root.tab = name
    if (name === "notes") root.loadNotes()
  }

  function toggleTab() { root.setTab(root.tab === "machine" ? "notes" : "machine") }

  function expandOther() {
    if (root.expanded || root.sessionsLoading || !root.currentSession) return
    root.expanded = true
    root.showLoading = true
    root.requestShow()
  }

  function onCompareRead(out) {
    var url = Model.safeUrl(String(out).split("\n")[0])
    if (url) Quickshell.execDetached(["xdg-open", url])
  }

  function openCompare() {
    if (root.sessionsLoading || !root.currentSession || !root.currentSession.omarchy.jumped) return
    var id = root.currentSession.id
    root.startRequest("compare", [root.cli, "compare-url", id], id)
  }

  // ----------------------------------------------------------------- procs

  Process {
    id: markReadProc
    command: [root.cli, "mark-read"]
  }

  Component {
    id: requestProcess
    Process {
      id: proc
      required property var identity
      property string outputText: ""
      property string errorText: ""
      property bool stdoutDone: false
      property bool stderrDone: false
      property bool exitDone: false
      property int exitCode: 0
      command: identity.argv
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          if (!root.isCurrentRequest(proc)) return
          proc.outputText = text
          proc.stdoutDone = true
          root.finishRequest(proc)
        }
      }
      stderr: StdioCollector {
        waitForEnd: true
        onStreamFinished: {
          if (!root.isCurrentRequest(proc)) return
          proc.errorText = text
          proc.stderrDone = true
          root.finishRequest(proc)
        }
      }
      onExited: function(code) {
        if (!root.isCurrentRequest(proc)) return
        proc.exitCode = code
        proc.exitDone = true
        root.finishRequest(proc)
      }
    }
  }

  // ---------------------------------------------------------------- window

  FloatingWindow {
    id: readingWindow
    objectName: "readingWindow"
    // Public window-rule target; keep this title stable across releases.
    title: "What Changed"
    visible: root.opened
    color: root.background
    readonly property int availableWidth: Math.max(1,
      (screen ? screen.width : Commons.Style.space(900)) - Commons.Style.gapsOut * 2)
    readonly property int availableHeight: Math.max(1,
      (screen ? screen.height : Commons.Style.space(620)) - Commons.Style.gapsOut * 2)
    implicitWidth: Math.min(Commons.Style.space(900), availableWidth)
    implicitHeight: Math.min(Commons.Style.space(620), availableHeight)
    // Wrapping must not raise the minimum while the user narrows the window.
    // Both hints fit the screen even with large font-scaled spacing.
    minimumSize: Qt.size(Math.min(Commons.Style.space(360), availableWidth),
      Math.min(Commons.Style.space(240), availableHeight))
    onClosed: root.dismiss()

    // Hyprland owns the window's size, position, border and rounding. Content
    // fills the actual size, including when tiled or fullscreen.
    Flickable {
      id: viewport
      objectName: "readingViewport"
      anchors.fill: parent
      anchors.margins: root.contentMargin
      clip: true
      contentWidth: width
      contentHeight: keyCatcher.height
      boundsBehavior: Flickable.StopAtBounds

      readonly property real chromeHeight: chrome.height + Commons.Style.spacing.lg
        + Commons.Style.spacing.md + footer.height
        + (rebootRequest.visible ? rebootRequest.height + Commons.Style.spacing.sm : 0)
      // Some compositors ignore size hints for tiles. In a short tile the
      // whole page scrolls; otherwise only the reading area scrolls, leaving
      // session controls and hints in place.
      readonly property bool compactHeight: height < chromeHeight + Commons.Style.space(80)
      onCompactHeightChanged: {
        // The outer viewport owns the offset in whole-page mode. Do not rely
        // on the nested Flickable fixing up its previous body-only offset.
        if (compactHeight && body) body.contentY = 0
      }
      interactive: compactHeight
      readonly property real maxScroll: Math.max(0, contentHeight - height)
      function scrollTo(y) { contentY = Math.max(0, Math.min(y, maxScroll)) }
      onHeightChanged: scrollTo(contentY)
      onContentHeightChanged: scrollTo(contentY)

      Item {
        id: keyCatcher
        objectName: "readingKeys"
        width: viewport.width
        height: viewport.compactHeight
          ? Math.max(viewport.height, viewport.chromeHeight + content.height) : viewport.height
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          // Leave modified keys to the desktop rather than interpreting, for
          // example, Super+J as the reader's plain j scroll action.
          // Keep Shift available for Backtab and bracket-key layouts.
          if (event.modifiers & (Qt.MetaModifier | Qt.ControlModifier | Qt.AltModifier)) {
            event.accepted = false
            return
          }
          if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
            root.dismiss(); event.accepted = true
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.toggleTab(); event.accepted = true
          } else if (event.key === Qt.Key_BracketLeft) {
            root.step(1); event.accepted = true          // older
          } else if (event.key === Qt.Key_BracketRight) {
            root.step(-1); event.accepted = true         // newer
          } else if (event.key === Qt.Key_O) {
            root.openCompare(); event.accepted = true
          } else if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
            body.scrollBy(Commons.Style.space(60)); event.accepted = true
          } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
            body.scrollBy(-Commons.Style.space(60)); event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            body.scrollBy(body.pageHeight * 0.9); event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            body.scrollBy(-body.pageHeight * 0.9); event.accepted = true
          } else if (event.key === Qt.Key_Home) {
            body.scrollTo(0); event.accepted = true
          } else if (event.key === Qt.Key_End) {
            body.scrollTo(body.maxScroll); event.accepted = true
          } else if (event.key === Qt.Key_E) {
            root.expandOther(); event.accepted = true
          }
        }

        Column {
          id: chrome
          objectName: "readingHeader"
          anchors { top: parent.top; left: parent.left; right: parent.right }
          spacing: Commons.Style.spacing.md

          // Keep the tabs below the title when they no longer fit beside it.
          Item {
            id: heading
            width: parent.width
            readonly property bool stacked: title.implicitWidth + tabs.implicitWidth + Commons.Style.spacing.lg > width
            height: stacked ? title.height + Commons.Style.spacing.sm + tabs.height : Math.max(tabs.height, title.height)

            Text {
              id: title
              width: Math.min(implicitWidth, parent.width)
              y: heading.stacked ? 0 : (parent.height - height) / 2
              text: "What changed"
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.heading
            }

            RowLayout {
              id: tabs
              width: heading.stacked ? parent.width : implicitWidth
              x: heading.stacked ? 0 : parent.width - width
              y: heading.stacked ? title.height + Commons.Style.spacing.sm : (parent.height - height) / 2
              spacing: Commons.Style.spacing.xs

              Repeater {
                model: [
                  { id: "machine", label: "This machine" },
                  { id: "notes", label: "Release notes" }
                ]
                delegate: Rectangle {
                  id: tabChip
                  required property var modelData
                  readonly property bool active: root.tab === tabChip.modelData.id
                  radius: Commons.Style.cornerRadius
                  color: active ? root.selectedBackground : "transparent"
                  implicitWidth: tabLabel.implicitWidth + Commons.Style.spacing.controlPaddingX * 2
                  implicitHeight: tabLabel.implicitHeight + Commons.Style.spacing.controlPaddingY * 2
                  Layout.fillWidth: true
                  Layout.minimumWidth: 0

                  Text {
                    id: tabLabel
                    anchors.fill: parent
                    anchors.leftMargin: Commons.Style.spacing.controlPaddingX
                    anchors.rightMargin: Commons.Style.spacing.controlPaddingX
                    anchors.topMargin: Commons.Style.spacing.controlPaddingY
                    anchors.bottomMargin: Commons.Style.spacing.controlPaddingY
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: tabChip.modelData.label
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: tabChip.active ? root.selectedText : root.foreground
                    opacity: tabChip.active ? 1.0 : 0.65
                    font.family: root.fontFamily
                    font.pixelSize: Commons.Style.font.body
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setTab(tabChip.modelData.id)
                  }
                }
              }
            }
          }

          SessionHeader {
            width: parent.width
            session: root.session
            fallbackSession: root.currentSession
            index: root.sessionIndex
            total: root.sessions.length
            olderLabel: root.sessionIndex + 1 < root.sessions.length
              ? root.sessions[root.sessionIndex + 1].label : ""
            newerLabel: root.sessionIndex > 0
              ? root.sessions[root.sessionIndex - 1].label : ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            onOlder: root.step(1)
            onNewer: root.step(-1)
          }
        }

        Text {
          id: rebootRequest
          anchors { top: chrome.bottom; topMargin: Commons.Style.spacing.sm; left: parent.left; right: parent.right }
          visible: root.currentRebootRequest === "pending" || root.currentRebootRequest === "unknown"
          text: root.currentRebootRequest === "pending"
            ? "Current system reboot request: pending (may come from another system action)."
            : "Current system reboot request: applicability unknown."
          textFormat: Text.PlainText
          color: root.foreground
          wrapMode: Text.Wrap
          font.family: root.fontFamily
          font.pixelSize: Commons.Style.font.caption
        }

        // ------------------------------------------------------------ body

        Flickable {
          id: body
          objectName: "readingBody"
          anchors {
            top: rebootRequest.visible ? rebootRequest.bottom : chrome.bottom; topMargin: Commons.Style.spacing.lg
            left: parent.left; right: parent.right
            bottom: footer.top; bottomMargin: Commons.Style.spacing.md
          }
          clip: true
          interactive: !viewport.compactHeight
          contentWidth: width
          contentHeight: content.height
          boundsBehavior: Flickable.StopAtBounds
          onHeightChanged: scrollTo(contentY)
          onContentHeightChanged: scrollTo(contentY)

          readonly property real maxScroll: viewport.compactHeight
            ? viewport.maxScroll : Math.max(0, contentHeight - height)
          readonly property real pageHeight: viewport.compactHeight ? viewport.height : height
          function scrollBy(delta) {
            scrollTo((viewport.compactHeight ? viewport.contentY : contentY) + delta)
          }
          function scrollTo(y) {
            if (viewport.compactHeight) viewport.scrollTo(y)
            else contentY = Math.max(0, Math.min(y, maxScroll))
          }

          Item {
            id: content
            width: body.width
            height: activeView.item ? activeView.item.implicitHeight : 0

            Loader {
              id: activeView
              width: parent.width
              sourceComponent: {
                if (root.sessionsLoading) return loadingView
                if (root.sessions.length === 0) return emptyView
                return root.tab === "machine" ? machineView : notesView
              }
            }
          }
        }

        Component {
          id: machineView
          MachineView {
            width: content.width
            groups: root.groups
            session: root.session
            loading: root.showLoading
            error: root.showError
            outputTruncated: root.outputTruncated
            foreground: root.foreground
            selectedText: root.selectedText
            fontFamily: root.fontFamily
            onExpandRequested: root.expandOther()
          }
        }

        Component {
          id: notesView
          NotesView {
            width: content.width
            notes: root.notes
            loading: root.notesLoading
            session: root.session
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
        }

        Component {
          id: loadingView
          Item {
            implicitHeight: Commons.Style.space(80)
            Text {
              anchors.centerIn: parent
              text: "Reading the update log…"
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.body
            }
          }
        }

        Component {
          id: emptyView
          Column {
            spacing: Commons.Style.spacing.md

            Text {
              width: content.width
              text: root.sessionsError || "No update sessions found."
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.subtitle
            }
            Text {
              text: root.sessionsUnavailable
                ? "Every session is reconstructed from that file, so there is nothing to show until it reads."
                : "Sessions are read from /var/log/pacman.log. Run an update, then reopen this."
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.6
              wrapMode: Text.Wrap
              width: content.width
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.body
            }
          }
        }

        // ---------------------------------------------------------- footer

        Flow {
          id: footer
          objectName: "readingFooter"
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
          spacing: Commons.Style.spacing.lg * 2
          // `o` only resolves a compare URL when the session actually jumped
          // versions, so it is only offered when it will do something.
          readonly property bool canCompare:
            !!(root.currentSession && root.currentSession.omarchy && root.currentSession.omarchy.jumped)
          Repeater {
            model: [root.tab === "machine" ? "Tab notes" : "Tab machine", "[ ] session", "j k scroll"]
              .concat(root.tab === "machine" ? ["e expand"] : (footer.canCompare ? ["o compare on GitHub"] : []))
              .concat(["Esc / q close"])
            delegate: Text {
              required property string modelData
              width: Math.min(implicitWidth, footer.width)
              text: modelData
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              color: root.foreground
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Commons.Style.font.caption
            }
          }
        }
      }
    }
  }
}
