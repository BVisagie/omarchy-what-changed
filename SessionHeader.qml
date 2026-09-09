import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The one line that says which update you are looking at: when it ran, the
// Omarchy jump it made, the channel, and whether it wants a reboot. Prev/next
// move through the recorded sessions without leaving the overlay.
Item {
  id: root

  // `session` is the fully loaded record; `fallbackSession` is the lighter row
  // from the session list, so the header stays populated while show reloads.
  property var session: null
  property var fallbackSession: null
  property int index: 0
  property int total: 0
  property color foreground: "white"
  property string fontFamily: ""

  signal older()
  signal newer()

  readonly property var current: session ? session : fallbackSession
  implicitHeight: Math.max(headline.implicitHeight + sub.implicitHeight + Style.spacing.xxs,
                           nav.implicitHeight)

  Column {
    anchors { left: parent.left; right: nav.left; rightMargin: Style.spacing.md }
    spacing: Style.spacing.xxs

    Text {
      id: headline
      width: parent.width
      text: root.current ? Model.headerText(root.current) : ""
      textFormat: Text.PlainText
      color: root.foreground
      elide: Text.ElideRight
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
    }

    Text {
      id: sub
      width: parent.width
      text: {
        if (!root.current) return ""
        var line = Model.countsText(root.current.counts)
        if (root.current.incomplete)
          line += "   ·   This session may be incomplete."
        return line
      }
      textFormat: Text.PlainText
      color: root.foreground
      opacity: root.current && root.current.incomplete ? 0.85 : 0.6
      elide: Text.ElideRight
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  Row {
    id: nav
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.sm

    // Older sits left of newer, matching the way the list reads.
    NavButton {
      glyph: "⟨"
      hint: "older"
      enabled: root.index < root.total - 1
      foreground: root.foreground
      fontFamily: root.fontFamily
      onActivated: root.older()
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.total > 0 ? (root.index + 1) + " / " + root.total : ""
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.5
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    NavButton {
      glyph: "⟩"
      hint: "newer"
      enabled: root.index > 0
      foreground: root.foreground
      fontFamily: root.fontFamily
      onActivated: root.newer()
    }
  }

  component NavButton: Rectangle {
    id: button
    property string glyph: ""
    property string hint: ""
    property color foreground: "white"
    property string fontFamily: ""
    signal activated()

    width: Style.space(24)
    height: Style.space(24)
    radius: Style.cornerRadius
    color: hover.containsMouse && enabled ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

    Text {
      anchors.centerIn: parent
      text: button.glyph
      textFormat: Text.PlainText
      color: button.foreground
      opacity: button.enabled ? 0.8 : 0.25
      font.family: button.fontFamily
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: hover
      anchors.fill: parent
      hoverEnabled: true
      enabled: button.enabled
      cursorShape: button.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: button.activated()
    }
  }
}
