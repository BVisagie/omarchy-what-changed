import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// What Changed — a reading surface for the update that just ran.
//
// The overlay never inspects the system itself: every fact on screen comes from
// `bin/what-changed --json`, which is the only thing this file executes. No
// pacman, no git, no network, and every Process command is a fixed argv array.
Item {
  id: root

  property bool opened: false
  property string tab: "machine"          // "machine" | "notes"

  property var sessions: []
  property int sessionIndex: 0
  property string sessionsError: ""
  property bool sessionsLoading: true

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
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color borderColor: Color.menu.border
  readonly property color scrim: Color.menu.scrim
  readonly property color selectedBackground: Color.menu.selectedBackground
  readonly property color selectedText: Color.menu.selectedText
  readonly property var borderSpec:
    Border.surfaceSpec("menu", "border", borderColor, Math.max(1, Style.space(2)))

  readonly property string fontFamily: Style.font.menuFamily
  readonly property int cornerRadius: Style.cornerRadius
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int cardWidth: Math.min(Style.space(900), panel.width - Style.gapsOut * 2)
  readonly property int maxCardHeight: Math.min(Style.space(620), panel.height - Style.gapsOut * 2)
  readonly property int minCardHeight: Style.space(200)

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
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  // Opening the overlay answers "anything since I last looked?", so it clears
  // the whole backlog rather than only the session you happen to browse.
  function markRead() {
    markReadProc.running = false
    markReadProc.running = true
  }

  function close() { root.opened = false }
  function toggle() { if (root.opened) root.close(); else root.open("{}") }

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

  function reloadSessions() {
    root.sessionsLoading = true
    root.sessionsError = ""
    sessionsProc.running = false
    sessionsProc.running = true
  }

  function onSessionsRead(out) {
    var r = Model.parseSessions(out)
    root.sessionsLoading = false
    root.sessions = r.sessions
    root.sessionsError = r.error

    var index = 0
    if (root.requestedSessionId)
      for (var i = 0; i < r.sessions.length; i++)
        if (r.sessions[i].id === root.requestedSessionId) { index = i; break }
    root.sessionIndex = index
    root.requestedSessionId = ""

    if (r.sessions.length > 0) root.loadSession()
  }

  function loadSession() {
    if (!root.currentSession) return
    root.showLoading = true
    root.showError = ""
    root.notes = null
    root.notesLoaded = false
    showProc.running = false
    showProc.running = true
    if (root.tab === "notes") root.loadNotes()
  }

  function onShowRead(out) {
    var r = Model.parseShow(out)
    root.showLoading = false
    root.session = r.session
    root.groups = r.groups
    root.showError = r.error
    root.outputTruncated = r.outputTruncated === true
  }

  function loadNotes() {
    if (root.notesLoaded || root.notesLoading || !root.currentSession) return
    root.notesLoading = true
    notesProc.running = false
    notesProc.running = true
  }

  function onNotesRead(out) {
    root.notes = Model.parseNotes(out)
    root.notesLoading = false
    root.notesLoaded = true
  }

  // --------------------------------------------------------------- actions

  function step(delta) {
    if (root.sessions.length === 0) return
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
    if (root.expanded) return
    root.expanded = true
    root.showLoading = true
    showProc.running = false
    showProc.running = true
  }

  function onCompareRead(out) {
    var url = Model.safeUrl(String(out).split("\n")[0])
    if (url) Quickshell.execDetached(["xdg-open", url])
  }

  function openCompare() {
    if (!root.currentSession || !root.currentSession.omarchy.jumped) return
    compareProc.running = false
    compareProc.running = true
  }

  // ----------------------------------------------------------------- procs

  Process {
    id: markReadProc
    command: [root.cli, "mark-read"]
  }

  Process {
    id: sessionsProc
    command: [root.cli, "sessions", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onSessionsRead(text)
    }
    onExited: function (code) {
      if (code !== 0 && root.sessionsLoading) {
        root.sessionsLoading = false
        root.sessions = []
        root.sessionsError = "No update sessions found in /var/log/pacman.log."
      }
    }
  }

  Process {
    id: showProc
    command: root.expanded
      ? [root.cli, "show", root.currentSession ? root.currentSession.id : "latest", "--json", "--expand", "other"]
      : [root.cli, "show", root.currentSession ? root.currentSession.id : "latest", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onShowRead(text)
    }
    onExited: function (code) {
      if (code !== 0 && root.showLoading) {
        root.showLoading = false
        root.showError = "Could not read this session."
      }
    }
  }

  Process {
    id: notesProc
    command: [root.cli, "notes", root.currentSession ? root.currentSession.id : "latest", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onNotesRead(text)
    }
    onExited: function (code) {
      if (code !== 0 && root.notesLoading) {
        root.notesLoading = false
        root.notesLoaded = true
        root.notes = { ok: false, status: "error", releases: [],
                       message: "Release notes are unavailable." }
      }
    }
  }

  // The CLI prints the compare URL; only a value that survives Model.safeUrl
  // is ever handed to the browser.
  Process {
    id: compareProc
    command: [root.cli, "compare-url", root.currentSession ? root.currentSession.id : "latest"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.onCompareRead(text)
    }
  }

  // ---------------------------------------------------------------- window

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-what-changed"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: root.scrim }

    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: card
      width: root.cardWidth

      // Hug the content rather than always opening at full height: a session
      // that only reinstalled the keyring should not read as a mostly empty
      // panel. Long sessions clamp to the maximum and scroll inside it.
      height: Math.max(root.minCardHeight, Math.min(root.maxCardHeight, contentHeight))
      readonly property int contentHeight:
        root.contentMargin * 2 + chrome.height + Style.spacing.lg
        + content.height + Style.spacing.md + footer.height

      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        anchors.margins: root.contentMargin
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
          if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
            root.close(); event.accepted = true
          } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.toggleTab(); event.accepted = true
          } else if (event.key === Qt.Key_BracketLeft) {
            root.step(1); event.accepted = true          // older
          } else if (event.key === Qt.Key_BracketRight) {
            root.step(-1); event.accepted = true         // newer
          } else if (event.key === Qt.Key_O) {
            root.openCompare(); event.accepted = true
          } else if (event.key === Qt.Key_J || event.key === Qt.Key_Down) {
            body.scrollBy(Style.space(60)); event.accepted = true
          } else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) {
            body.scrollBy(-Style.space(60)); event.accepted = true
          } else if (event.key === Qt.Key_PageDown) {
            body.scrollBy(body.height * 0.9); event.accepted = true
          } else if (event.key === Qt.Key_PageUp) {
            body.scrollBy(-body.height * 0.9); event.accepted = true
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
          anchors { top: parent.top; left: parent.left; right: parent.right }
          spacing: Style.spacing.md

          // Title row: name on the left, the two views on the right.
          Item {
            width: parent.width
            height: Math.max(tabs.height, title.height)

            Text {
              id: title
              anchors.verticalCenter: parent.verticalCenter
              text: "What changed"
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
            }

            Row {
              id: tabs
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.spacing.xs

              Repeater {
                model: [
                  { id: "machine", label: "This machine" },
                  { id: "notes", label: "Release notes" }
                ]
                delegate: Rectangle {
                  id: tabChip
                  required property var modelData
                  readonly property bool active: root.tab === tabChip.modelData.id
                  radius: Style.cornerRadius
                  color: active ? root.selectedBackground : "transparent"
                  width: tabLabel.implicitWidth + Style.spacing.controlPaddingX * 2
                  height: tabLabel.implicitHeight + Style.spacing.controlPaddingY * 2

                  Text {
                    id: tabLabel
                    anchors.centerIn: parent
                    text: tabChip.modelData.label
                    textFormat: Text.PlainText
                    color: tabChip.active ? root.selectedText : root.foreground
                    opacity: tabChip.active ? 1.0 : 0.65
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
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

        // ------------------------------------------------------------ body

        Flickable {
          id: body
          anchors {
            top: chrome.bottom; topMargin: Style.spacing.lg
            left: parent.left; right: parent.right
            bottom: footer.top; bottomMargin: Style.spacing.md
          }
          clip: true
          interactive: true
          contentWidth: width
          contentHeight: content.height
          boundsBehavior: Flickable.StopAtBounds

          readonly property real maxScroll: Math.max(0, contentHeight - height)
          function scrollBy(delta) { scrollTo(contentY + delta) }
          function scrollTo(y) { contentY = Math.max(0, Math.min(y, maxScroll)) }

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
            implicitHeight: Style.space(80)
            Text {
              anchors.centerIn: parent
              text: "Reading the update log…"
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }

        Component {
          id: emptyView
          Column {
            spacing: Style.spacing.md

            Text {
              text: root.sessionsError || "No update sessions found."
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
            }
            Text {
              text: "Sessions are read from /var/log/pacman.log. Run an update, then reopen this."
              textFormat: Text.PlainText
              color: root.foreground
              opacity: 0.6
              wrapMode: Text.WordWrap
              width: content.width
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }

        // ---------------------------------------------------------- footer

        Text {
          id: footer
          anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
          text: root.tab === "machine"
            ? "Tab notes   ·   [ ] session   ·   j k scroll   ·   e expand   ·   Esc close"
            : "Tab machine   ·   [ ] session   ·   j k scroll   ·   o compare on GitHub   ·   Esc close"
          textFormat: Text.PlainText
          color: root.foreground
          opacity: 0.45
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
