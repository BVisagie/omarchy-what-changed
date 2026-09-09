import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// What landed on this machine, in the order the CLI bucketed it. The grouping
// is entirely the CLI's: this file decides nothing about which package belongs
// where, it only draws the rows it was handed.
Column {
  id: root

  property var groups: []
  property var session: null
  property bool loading: false
  property string error: ""
  property bool outputTruncated: false
  property color foreground: "white"
  property color selectedText: "white"
  property string fontFamily: ""

  signal expandRequested()

  spacing: Style.spacing.lg

  Text {
    visible: root.error !== ""
    width: root.width
    text: root.error
    textFormat: Text.PlainText
    color: root.foreground
    wrapMode: Text.WordWrap
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  Text {
    visible: root.loading && root.groups.length === 0
    text: "Reading this session…"
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  Repeater {
    model: root.groups

    delegate: Column {
      id: group
      required property var modelData
      width: root.width
      spacing: Style.spacing.xs
      visible: modelData.items.length > 0 || modelData.count > 0

      // A fixed proportional column keeps every group aligned on the same
      // gutter and costs no text measurement; long names elide.
      readonly property int nameColumn: Math.round(root.width * 0.42)

      Text {
        text: group.modelData.title
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
      }

      Repeater {
        model: group.modelData.items

        delegate: Item {
          required property var modelData
          width: group.width
          height: rowName.implicitHeight + Style.spacing.xs

          Text {
            id: rowName
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: group.nameColumn
            text: modelData.name
            textFormat: Text.PlainText
            color: root.foreground
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            anchors.left: rowName.right
            anchors.leftMargin: Style.spacing.lg
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: Model.versionText(modelData)
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.6
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }

      // A collapsed group states its size and stays shut until asked.
      Item {
        visible: group.modelData.collapsed && group.modelData.items.length === 0
        width: group.width
        height: visible ? expandLabel.implicitHeight + Style.spacing.sm : 0

        Text {
          id: expandLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Show them  (e)"
          textFormat: Text.PlainText
          color: root.selectedText
          opacity: expandHover.containsMouse ? 1.0 : 0.75
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        MouseArea {
          id: expandHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.expandRequested()
        }
      }
    }
  }

  Text {
    visible: root.outputTruncated || (root.session && root.session.counts.omitted > 0)
    width: root.width
    text: {
      if (!root.session) return ""
      var parts = []
      if (root.session.counts.omitted > 0)
        parts.push(root.session.counts.omitted + " further package rows omitted.")
      if (root.outputTruncated)
        parts.push("This session is too large to list in full.")
      return parts.join(" ")
    }
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.5
    wrapMode: Text.WordWrap
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
