import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The unread marker.
//
// This is not an update indicator and must never become one: it says "there
// are notes you have not read", never "there are updates to install". That is
// `omarchy.system-update`'s job. Hence no badge, no count, and no presence at
// all once the newest session has been read -- and hence no Timer anywhere in
// this file: this release refreshes at shell startup and read-marker changes.
BarWidget {
  id: root
  moduleName: "io.github.bvisagie.what-changed"

  readonly property string pluginId: "io.github.bvisagie.what-changed"

  property bool unread: false
  property string sessionLabel: ""
  property string sessionJump: ""

  readonly property string cli:
    decodeURIComponent(String(Qt.resolvedUrl("bin/what-changed")).replace(/^file:\/\//, ""))

  readonly property string statePath: {
    var base = Quickshell.env("XDG_STATE_HOME")
    if (!base) base = Quickshell.env("HOME") + "/.local/state"
    return base + "/" + root.pluginId + "/last-read"
  }

  visible: root.unread
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  function refresh() {
    statusProc.running = false
    statusProc.running = true
  }

  function openOverlay() {
    // In-process where the bar handed us the shell facade; a fixed argv
    // fallback otherwise. Never a shell string.
    if (root.bar && root.bar.shell && typeof root.bar.shell.summon === "function")
      root.bar.shell.summon(root.pluginId, "{}")
    else
      Quickshell.execDetached(["omarchy-shell", "shell", "summon", root.pluginId])
  }

  function applyStatus(out) {
    var status = Model.parseStatus(out)
    root.unread = status.ok && status.unread && status.newest !== null
    root.sessionLabel = status.newest ? status.newest.label : ""
    root.sessionJump = status.newest ? Model.sessionVersion(status.newest) : ""
  }

  Component.onCompleted: root.refresh()

  // Manual refresh also covers failed updates, SSH/TTY runs without a shell
  // restart, and upstream restarting before later package steps finish.
  //   omarchy-shell -q io.github.bvisagie.what-changed refresh
  IpcHandler {
    target: "io.github.bvisagie.what-changed"

    function refresh(): void {
      root.broadcast("refresh")
    }
  }

  Process {
    id: statusProc
    command: [root.cli, "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
    onExited: function (code) {
      // No log, no sessions, no plugin state: stay out of the bar rather than
      // show something the user cannot act on.
      if (code !== 0) root.unread = false
    }
  }

  // Opening the overlay marks the newest session read, clearing the icon on
  // that write. Shell startup is the other refresh point. Stable restarts near
  // the end of an update; inspected upstream restarts before the later steps,
  // which need a manual refresh in this accuracy release.
  FileView {
    path: root.statePath
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
    onLoaded: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰌱"
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    tooltipText: {
      var parts = ["What changed"]
      if (root.sessionLabel) parts.push(root.sessionLabel)
      if (root.sessionJump) parts.push("omarchy " + root.sessionJump)
      return parts.join("  ·  ")
    }
    onPressed: root.openOverlay()
  }
}
