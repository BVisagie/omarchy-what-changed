import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Which update you are looking at: when it ran, the Omarchy jump it made, the
// channel, and whether it wants a reboot.
//
// The parts are drawn separately rather than joined into one grey line, because
// they are not equally important: "reboot needed" is the one thing here you may
// have to act on, so it gets the urgent colour and everything else recedes.
Item {
  id: root

  // `session` is the fully loaded record; `fallbackSession` is the lighter row
  // from the session list, so the header stays populated while show reloads.
  property var session: null
  property var fallbackSession: null
  property int index: 0
  property int total: 0
  property string olderLabel: ""
  property string newerLabel: ""
  property color foreground: "white"
  property color urgent: Color.urgent
  property string fontFamily: ""

  signal older()
  signal newer()

  readonly property var current: session ? session : fallbackSession
  implicitHeight: Math.max(text.implicitHeight, nav.implicitHeight)

  Column {
    id: text
    anchors { left: parent.left; right: nav.left; rightMargin: Style.spacing.lg }
    spacing: Style.spacing.xxs

    Row {
      id: headline
      width: parent.width
      spacing: 0

      Repeater {
        model: root.current ? Model.headerParts(root.current) : []

        delegate: Row {
          id: part
          required property var modelData
          required property int index
          spacing: 0

          Text {
            text: "  ·  "
            textFormat: Text.PlainText
            visible: part.index > 0
            color: root.foreground
            opacity: 0.35
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
          }

          Text {
            text: part.modelData.text
            textFormat: Text.PlainText
            color: part.modelData.kind === "urgent" ? root.urgent : root.foreground
            opacity: part.modelData.kind === "urgent" ? 1.0 : 0.9
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
          }
        }
      }
    }

    Text {
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
      opacity: root.current && root.current.incomplete ? 0.85 : 0.5
      elide: Text.ElideRight
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  // Older sits left of newer, matching the way the list reads. Each arrow says
  // which session it will take you to, so stepping is not a guess.
  Row {
    id: nav
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.spacing.md

    NavStep {
      glyph: "⟨"
      label: root.olderLabel
      labelFirst: false
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
      opacity: 0.35
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    NavStep {
      glyph: "⟩"
      label: root.newerLabel
      labelFirst: true
      enabled: root.index > 0
      foreground: root.foreground
      fontFamily: root.fontFamily
      onActivated: root.newer()
    }
  }

  component NavStep: Rectangle {
    id: step
    property string glyph: ""
    property string label: ""
    property bool labelFirst: false
    property color foreground: "white"
    property string fontFamily: ""
    signal activated()

    width: row.implicitWidth + Style.spacing.sm * 2
    height: Style.space(24)
    radius: Style.cornerRadius
    color: hover.containsMouse && step.enabled ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
    opacity: step.enabled ? 1.0 : 0.25

    Row {
      id: row
      anchors.centerIn: parent
      spacing: Style.spacing.xs

      Text {
        visible: step.labelFirst && step.label !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: step.label
        textFormat: Text.PlainText
        color: step.foreground
        opacity: 0.5
        font.family: step.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: step.glyph
        textFormat: Text.PlainText
        color: step.foreground
        opacity: 0.8
        font.family: step.fontFamily
        font.pixelSize: Style.font.body
      }

      Text {
        visible: !step.labelFirst && step.label !== ""
        anchors.verticalCenter: parent.verticalCenter
        text: step.label
        textFormat: Text.PlainText
        color: step.foreground
        opacity: 0.5
        font.family: step.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: hover
      anchors.fill: parent
      hoverEnabled: true
      enabled: step.enabled
      cursorShape: step.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: step.activated()
    }
  }
}
