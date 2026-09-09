import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The official release notes for the version jump this session made.
//
// Bodies are rendered as plain text, never as rich HTML or markdown: they are
// authored upstream and arrive over the network, so they get the same treatment
// as any other untrusted string. In this release no per-bullet status is
// claimed — an honest wall of notes beats a wrong checkmark.
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
      required property var modelData
      width: root.width
      spacing: Style.spacing.sm

      Text {
        text: modelData.name || modelData.tag
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      Text {
        width: parent.width
        visible: modelData.url !== ""
        text: modelData.url
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.45
        elide: Text.ElideRight
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        text: modelData.body
        textFormat: Text.PlainText
        color: root.foreground
        opacity: 0.85
        wrapMode: Text.WordWrap
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
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
