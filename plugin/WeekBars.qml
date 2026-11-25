import QtQuick
import qs.Commons

// Zone 2 — one bar per week for the last four weeks, against the target line.
//
// The only arithmetic here is turning an hours value into a pixel height.
// That is layout, not derived data: every number shown as text comes
// straight off `weeks` and `targetWeekly` as the collector wrote them.
Item {
  id: root

  property var weeks: []
  property real targetWeekly: 0
  property color barColor: Color.foreground
  property color labelColor: Color.muted

  // Scale so the target line always has room above it, even in a dead month.
  readonly property real scaleMax: {
    var top = root.targetWeekly
    for (var i = 0; i < root.weeks.length; i++) {
      var h = Number(root.weeks[i].hours)
      if (isFinite(h) && h > top) top = h
    }
    return top > 0 ? top * 1.15 : 1
  }

  readonly property int labelHeight: Style.font.caption + Style.spacing.sm
  readonly property int plotHeight: Math.max(Style.space(20), height - labelHeight)

  Item {
    id: plot
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: root.plotHeight

    // The 5h line. Sits behind the bars so a bar crossing it reads as over.
    Rectangle {
      visible: root.targetWeekly > 0
      anchors.left: parent.left
      anchors.right: parent.right
      height: Math.max(1, Style.space(1))
      color: Util.alpha(root.labelColor, 0.55)
      y: Math.round(plot.height - (root.targetWeekly / root.scaleMax) * plot.height)
    }

    Text {
      visible: root.targetWeekly > 0
      textFormat: Text.PlainText
      text: root.targetWeekly.toFixed(0) + "h"
      color: root.labelColor
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      anchors.right: parent.right
      y: Math.round(plot.height - (root.targetWeekly / root.scaleMax) * plot.height)
         - Style.font.caption - Style.spacing.xxs
    }

    Row {
      anchors.fill: parent
      spacing: Style.spacing.lg

      Repeater {
        model: root.weeks

        Item {
          required property var modelData

          width: (plot.width - Style.spacing.lg * Math.max(0, root.weeks.length - 1))
                 / Math.max(1, root.weeks.length)
          height: plot.height

          readonly property real hoursValue: isFinite(Number(modelData.hours)) ? Number(modelData.hours) : 0

          Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.max(parent.hoursValue > 0 ? Style.space(2) : 0,
                             Math.round((parent.hoursValue / root.scaleMax) * plot.height))
            color: Util.alpha(root.barColor, 0.75)
            radius: Style.cornerRadius
          }

          Text {
            textFormat: Text.PlainText
            text: parent.hoursValue.toFixed(1)
            color: root.labelColor
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round((parent.hoursValue / root.scaleMax) * plot.height)
                                  + Style.spacing.xxs
          }
        }
      }
    }
  }

  Row {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: plot.bottom
    anchors.topMargin: Style.spacing.sm
    spacing: Style.spacing.lg

    Repeater {
      model: root.weeks

      Text {
        required property var modelData
        textFormat: Text.PlainText
        width: (plot.width - Style.spacing.lg * Math.max(0, root.weeks.length - 1))
               / Math.max(1, root.weeks.length)
        text: String(modelData.week_start || "").slice(5)
        color: root.labelColor
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
      }
    }
  }
}
