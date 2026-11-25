import QtQuick
import qs.Commons

// One zone of the dashboard: a subtly raised card inside the frosted panel.
// The separation is the point — four numbers in four cards read as a
// dashboard; the same four in one column read as a paragraph.
//
// No colour here is a literal. Fill and border are the theme foreground at
// low alpha, so a theme switch repaints them along with everything else.
// Translucent surfaces are exactly where hardcoded greys creep in.
Rectangle {
  id: root

  default property alias content: body.data
  property int padding: Style.spacing.lg

  radius: Style.space(14)
  color: Util.alpha(Color.foreground, 0.04)
  border.width: Math.max(1, Style.space(1))
  border.color: Util.alpha(Color.foreground, 0.10)

  Item {
    id: body
    anchors.fill: parent
    anchors.margins: root.padding
  }
}
