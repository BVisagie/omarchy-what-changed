import QtQuick
import qs.Commons as Commons
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

  spacing: Commons.Style.spacing.lg

  Text {
    visible: root.error !== ""
    width: root.width
    text: root.error
    textFormat: Text.PlainText
    color: root.foreground
    wrapMode: Text.Wrap
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.body
  }

  Text {
    visible: root.loading && root.groups.length === 0
    text: "Reading this session…"
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.body
  }

  Text {
    visible: root.session && root.session.nearbyCounts.total > 0
    width: root.width
    text: root.session ? root.session.nearbyCounts.total + " other changes during this window (excluded from update totals)." : ""
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.caption
  }

  Repeater {
    model: root.groups

    delegate: Column {
      id: group
      required property var modelData
      width: root.width
      spacing: Commons.Style.spacing.xs
      visible: modelData.items.length > 0 || modelData.count > 0

      // Keep groups aligned on wide windows; narrow tiles put versions beneath
      // names. Both fields can grow vertically without dropping version text.
      readonly property bool stacked: root.width < Commons.Style.space(600)
      readonly property int nameColumn: stacked ? root.width : Math.round(root.width * 0.34)

      Text {
        width: group.width
        text: group.modelData.title
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.caption
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
      }

      Text {
        visible: group.modelData.explanation !== ""
        width: group.width
        text: group.modelData.explanation
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.caption
      }

      // A group that carries a summary says its size in one line. Migration
      // ids are timestamps: nine rows of them is nine rows of nothing a person
      // can read.
      Text {
        visible: group.modelData.summary !== ""
        width: group.width
        text: group.modelData.summary
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: root.foreground
        opacity: 0.8
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.body
      }

      Repeater {
        model: group.modelData.summary === "" ? group.modelData.items : []

        delegate: Item {
          id: packageRow
          required property var modelData
          width: group.width
          height: (group.stacked
            ? rowName.height + (rowVersion.text !== "" ? Commons.Style.spacing.xxs + rowVersion.height : 0)
            : Math.max(rowName.height, rowVersion.height)) + Commons.Style.spacing.xs

          Text {
            id: rowName
            anchors.left: parent.left
            width: group.nameColumn
            text: packageRow.modelData.name + (packageRow.modelData.attribution === "migration-inferred" ? " (inferred)" : "")
            textFormat: Text.PlainText
            color: root.foreground
            wrapMode: Text.Wrap
            font.family: root.fontFamily
            font.pixelSize: Commons.Style.font.body
          }

          Text {
            id: rowVersion
            x: group.stacked ? 0 : rowName.width + Commons.Style.spacing.lg
            y: group.stacked ? rowName.height + Commons.Style.spacing.xxs : 0
            width: Math.max(0, parent.width - x)
            text: Model.versionText(packageRow.modelData)
            textFormat: Text.PlainText
            color: root.foreground
            opacity: 0.6
            wrapMode: Text.Wrap
            font.family: root.fontFamily
            font.pixelSize: Commons.Style.font.body
          }
        }
      }

      Text {
        visible: group.modelData.omitted > 0
        width: group.width
        text: group.modelData.omitted + " package rows omitted from this group."
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: root.foreground
        opacity: 0.5
        font.family: root.fontFamily
        font.pixelSize: Commons.Style.font.caption
      }

      // A collapsed group states its size and stays shut until asked.
      Item {
        visible: group.modelData.collapsed && group.modelData.items.length === 0
        width: group.width
        height: visible ? expandLabel.implicitHeight + Commons.Style.spacing.sm : 0

        Text {
          id: expandLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Show them  (e)"
          textFormat: Text.PlainText
          color: root.selectedText
          opacity: expandHover.containsMouse ? 1.0 : 0.75
          font.family: root.fontFamily
          font.pixelSize: Commons.Style.font.body
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
    visible: root.outputTruncated || (root.session && (root.session.counts.omitted > 0 || root.session.nearbyCounts.omitted > 0))
    width: root.width
    text: {
      if (!root.session) return ""
      var parts = []
      if (root.session.counts.omitted > 0)
        parts.push(root.session.counts.omitted + " further package rows omitted.")
      if (root.session.nearbyCounts.omitted > 0)
        parts.push(root.session.nearbyCounts.omitted + " further nearby rows omitted.")
      if (root.outputTruncated)
        parts.push("This session is too large to list in full.")
      return parts.join(" ")
    }
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.5
    wrapMode: Text.Wrap
    font.family: root.fontFamily
    font.pixelSize: Commons.Style.font.caption
  }
}
