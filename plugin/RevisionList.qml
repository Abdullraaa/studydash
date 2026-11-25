import QtQuick
import qs.Commons

// Zone 3 — the three most overdue rooms, and what has gone cold.
//
// Deliberately inert. There is no button here, and there must never be one:
// clearing a review means redoing the practical or answering the room's
// questions cold, which is a `studydash review <room>` call made after doing
// the work — not a click made while looking at this screen.
Item {
  id: root

  property var due: []
  property int dueCount: 0
  property var coldTopics: []
  property color textColor: Color.foreground
  property color mutedColor: Color.muted
  property color overdueColor: Color.urgent

  readonly property var shown: root.due.slice(0, 3)
  readonly property int hiddenCount: Math.max(0, root.dueCount - root.shown.length)

  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Style.spacing.md

    Repeater {
      model: root.shown

      Row {
        required property var modelData
        width: parent.width
        spacing: Style.spacing.md

        Text {
          textFormat: Text.PlainText
          text: String(parent.modelData.room || "")
          color: root.textColor
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          elide: Text.ElideRight
          width: Math.max(0, parent.width - intervalLabel.width - overdueLabel.width
                             - Style.spacing.md * 2)
        }

        Text {
          id: intervalLabel
          textFormat: Text.PlainText
          text: String(parent.modelData.interval || "")
          color: root.mutedColor
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }

        Text {
          id: overdueLabel
          textFormat: Text.PlainText
          // 0 means due today, not "0 days late" — say so rather than
          // printing a number that reads like nothing is wrong.
          text: Number(parent.modelData.overdue_days) > 0
                ? Number(parent.modelData.overdue_days) + "d overdue"
                : "due today"
          color: Number(parent.modelData.overdue_days) > 0 ? root.overdueColor : root.mutedColor
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }
      }
    }

    Text {
      visible: root.hiddenCount > 0
      textFormat: Text.PlainText
      text: "+" + root.hiddenCount + " more due"
      color: root.mutedColor
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    // Not a celebration. Not a streak. Just the fact.
    Text {
      visible: root.dueCount === 0
      textFormat: Text.PlainText
      text: "nothing due"
      color: root.mutedColor
      font.family: Style.font.family
      font.pixelSize: Style.font.title
    }

    Text {
      visible: root.coldTopics.length > 0
      textFormat: Text.PlainText
      text: "cold 90d+: " + root.coldTopics.join(", ")
      color: root.mutedColor
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      width: parent.width
      wrapMode: Text.WordWrap
      elide: Text.ElideRight
      maximumLineCount: 2
    }
  }
}
