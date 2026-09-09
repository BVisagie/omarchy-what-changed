import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The official release notes for the version jump this session made.
//
// Parsing to headings, bullets and paragraphs is structure, not rich text: it
// is what stops "## Heading" and "[label](https://long.url)" from landing in
// the middle of a sentence, and it is why every block below can still be a
// Text.PlainText that never reaches a rich-text renderer.
//
// In this release no per-bullet status is claimed: an honest wall of notes
// beats a wrong checkmark.
Column {
  id: root

  property var notes: null
  property var session: null
  property bool loading: false
  property color foreground: "white"
  property string fontFamily: ""

  spacing: Style.spacing.lg

  Text {
    visible: root.loading
    text: "Fetching release notes…"
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  // Nothing to show: no version change, offline, rate limited, or an edge
  // checkout with no tag to point at. Each says which, and stops there.
  Column {
    visible: !root.loading && root.notes && !root.notes.ok
    width: root.width
    spacing: Style.spacing.sm

    Text {
      width: parent.width
      text: root.notes ? (root.notes.message || "Release notes are unavailable.") : ""
      textFormat: Text.PlainText
      color: root.foreground
      wrapMode: Text.WordWrap
      font.family: root.fontFamily
      font.pixelSize: Style.font.subtitle
    }

    Text {
      width: parent.width
      visible: root.notes && root.notes.status === "no-jump"
      text: "This machine still changed — see This machine."
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.6
      wrapMode: Text.WordWrap
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      width: parent.width
      visible: root.notes && root.notes.status === "unavailable"
      text: "Notes are fetched once per release and then cached, so this will fill in when you are back online."
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.6
      wrapMode: Text.WordWrap
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  Repeater {
    model: (root.notes && root.notes.ok) ? root.notes.releases : []

    delegate: Column {
      id: release
      required property var modelData
      width: root.width
      spacing: Style.spacing.sm

      Text {
        text: release.modelData.name || release.modelData.tag
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.display
      }

      Text {
        width: parent.width
        visible: release.modelData.url !== ""
        text: release.modelData.url
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.4
        elide: Text.ElideRight
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: release.modelData.blocks

        delegate: Item {
          id: block
          required property var modelData
          width: release.width
          implicitHeight: line.implicitHeight + block.spaceAbove
          height: implicitHeight

          // Headings need air above them; runs of bullets should not drift
          // apart. The spacing is the structure doing its job.
          readonly property int spaceAbove: {
            var t = block.modelData.type
            if (t === "h1" || t === "h2") return Style.spacing.lg
            if (t === "h3") return Style.spacing.md
            if (t === "rule") return Style.spacing.md
            return Style.spacing.xxs
          }

          Text {
            id: line
            y: block.spaceAbove
            x: block.modelData.type === "li" ? Style.spacing.md : 0
            width: parent.width - x
            visible: block.modelData.type !== "rule"
            text: block.modelData.type === "li"
              ? "•   " + block.modelData.text
              : block.modelData.text
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: {
              var t = block.modelData.type
              if (t === "h1" || t === "h2") return Style.font.heading
              if (t === "h3") return Style.font.subtitle
              if (t === "code") return Style.font.bodySmall
              return Style.font.body
            }
            opacity: {
              var t = block.modelData.type
              if (t === "h1" || t === "h2" || t === "h3") return 1.0
              if (t === "code" || t === "quote") return 0.65
              return 0.85
            }
            font.weight: {
              var t = block.modelData.type
              return (t === "h1" || t === "h2" || t === "h3")
                ? Font.DemiBold : Font.Normal
            }
          }

          Rectangle {
            visible: block.modelData.type === "rule"
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 1
            color: root.foreground
            opacity: 0.15
          }
        }
      }
    }
  }

  Text {
    visible: root.notes && root.notes.ok && root.notes.status === "partial"
    width: root.width
    text: root.notes ? root.notes.message : ""
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.6
    wrapMode: Text.WordWrap
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }
}
