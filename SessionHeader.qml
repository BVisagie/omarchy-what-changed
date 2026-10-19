import QtQuick
import qs.Commons as Commons
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
  property color urgent: Commons.Color.urgent
  property string fontFamily: ""

  signal older()
  signal newer()

  readonly property var current: session ? session : fallbackSession
  readonly property bool stackedNavigation:
    counts.implicitWidth + Commons.Style.spacing.lg + nav.implicitWidth > width
  implicitHeight: Math.max(counts.y + counts.height, nav.y + nav.height)

  // Metadata uses the full width and wraps independently of navigation. A Row
  // still paints beyond its width, which let long reboot text cover the arrows.
  Flow {
    id: headline
    width: parent.width
    spacing: Commons.Style.spacing.lg * 2

    Repeater {
      model: root.current ? Model.headerParts(root.current) : []

      delegate: Text {
        required property var modelData
        width: Math.min(implicitWidth, headline.width)
        text: modelData.text
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: modelData.kind === "urgent" ? root.urgent : root.foreground
        opacity: modelData.kind === "urgent" ? 1.0 : 0.9
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.subtitle
      }
    }
  }

  Text {
    id: counts
    y: headline.height + Commons.Style.spacing.sm
    width: root.stackedNavigation ? parent.width : Math.max(0, parent.width - nav.width - Commons.Style.spacing.lg)
    text: {
      if (!root.current) return ""
      var line = Model.countsText(root.current.counts)
      if (root.current.incomplete)
        line += "   ·   Unfinished package transaction."
      return line
    }
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: root.foreground
    opacity: root.current && root.current.incomplete ? 0.85 : 0.5
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.caption
  }

  // Older sits left of newer, matching the way the list reads. Each arrow says
  // which session it will take you to, so stepping is not a guess.
  Row {
    id: nav
    anchors.right: parent.right
    y: root.stackedNavigation ? counts.y + counts.height + Commons.Style.spacing.sm : counts.y
    spacing: Commons.Style.spacing.md

    NavStep {
      glyph: "⟨"
      label: root.olderLabel
      labelFirst: false
      maximumWidth: Math.max(0, (root.width - position.implicitWidth - nav.spacing * 2) / 2)
      enabled: root.index < root.total - 1
      foreground: root.foreground
      fontFamily: root.fontFamily
      onActivated: root.older()
    }

    Text {
      id: position
      anchors.verticalCenter: parent.verticalCenter
      text: root.total > 0 ? (root.index + 1) + " / " + root.total : ""
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.35
      font.family: root.fontFamily
      font.pixelSize: Commons.Style.font.caption
    }

    NavStep {
      glyph: "⟩"
      label: root.newerLabel
      labelFirst: true
      maximumWidth: Math.max(0, (root.width - position.implicitWidth - nav.spacing * 2) / 2)
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
    property real maximumWidth: 0
    signal activated()

    width: row.implicitWidth + Commons.Style.spacing.sm * 2
    height: Math.max(Commons.Style.space(24), row.implicitHeight + Commons.Style.spacing.xxs * 2)
    radius: Commons.Style.cornerRadius
    color: hover.containsMouse && step.enabled ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
    opacity: step.enabled ? 1.0 : 0.25

    Row {
      id: row
      anchors.centerIn: parent
      spacing: Commons.Style.spacing.xs
      layoutDirection: step.labelFirst ? Qt.RightToLeft : Qt.LeftToRight

      Text {
        id: glyph
        anchors.verticalCenter: parent.verticalCenter
        text: step.glyph
        textFormat: Text.PlainText
        color: step.foreground
        opacity: 0.8
        font.family: step.fontFamily
        font.pixelSize: Commons.Style.font.body
      }

      Text {
        visible: step.label !== ""
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Math.max(0,
          step.maximumWidth - glyph.implicitWidth - row.spacing - Commons.Style.spacing.sm * 2))
        text: step.label
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: step.foreground
        opacity: 0.5
        font.family: step.fontFamily
        font.pixelSize: Commons.Style.font.caption
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
