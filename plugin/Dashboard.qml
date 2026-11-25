import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Study dashboard. It answers exactly one question:
// am I on pace to finish Cyber Security 101 by 15 Dec 2026?
//
// This file reads one file and renders it. It does not fetch, does not
// shell out, and does not compute anything it displays — every number and
// every status string is a field the collector already decided. If a value
// looks wrong on screen, the bug is in `studydash collect`, not here.
//
// The surface is a full-screen layer-shell window with its input region
// masked down to the panel, which is how every floating surface in Omarchy
// is built (see Ui/KeyboardPanel.qml). Clicks outside the panel reach the
// windows underneath; the compositor blurs what is behind the panel rect.
Item {
  id: root

  // Injected by the shell's plugin loader.
  property var shell: null
  property var manifest: null

  property bool opened: false

  // The one input. `null` until the file loads, and back to `null` if it
  // goes missing or fails to parse.
  property var stats: null

  readonly property var courseData: (stats && stats.course) ? stats.course : null
  readonly property var hoursData: (stats && stats.hours) ? stats.hours : null
  readonly property var revisionData: (stats && stats.revision) ? stats.revision : null
  readonly property var loadData: (stats && stats.load) ? stats.load : null
  readonly property bool hasData: courseData !== null

  // Shares the [menu] surface tokens, so a theme that styles the menu
  // styles this too. Every colour is a live binding on the Color singleton:
  // theme switches arrive by IPC into that singleton and repaint in place.
  readonly property color foreground: Color.menu.text
  readonly property string fontFamily: Style.font.family

  // The five roles the shell actually exposes to plugins. `unknown` is muted
  // on purpose — a status we cannot compute must never render as a pass.
  function statusColor(status) {
    if (status === "behind") return Color.urgent
    if (status === "ahead") return Color.accent
    if (status === "on_track") return root.foreground
    return Color.muted
  }

  // Zone 4 is a cost, never an achievement: muted when quiet, warning when
  // loud, and never accent-coloured.
  function loadColor(count) {
    var n = Number(count)
    if (!isFinite(n)) return Color.muted
    if (n >= 5) return Color.urgent
    return Color.muted
  }

  function num(value, digits) {
    var n = Number(value)
    if (value === null || value === undefined || !isFinite(n)) return null
    return n.toFixed(digits === undefined ? 1 : digits)
  }

  // No forceActiveFocus here: the window is OnDemand, so opening it must not
  // take the keyboard away from whatever you were typing into.
  function open(payloadJson) {
    root.opened = true
    statsFile.reload()
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "ra.studydash")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  FileView {
    id: statsFile
    path: Quickshell.env("HOME") + "/.local/state/studydash/stats.json"
    watchChanges: true
    printErrors: false
    // `text()` is stale inside the change signal, so route every path through
    // reload() -> onLoaded and always parse fresh content.
    onFileChanged: reload()
    onLoaded: {
      try {
        root.stats = JSON.parse(text())
      } catch (e) {
        console.warn("studydash: stats.json did not parse: " + e)
        root.stats = null
      }
    }
    onLoadFailed: root.stats = null
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-studydash"
    WlrLayershell.layer: WlrLayer.Overlay
    // OnDemand, never Exclusive: the panel takes the keyboard only once you
    // click it, so opening it mid-sentence does not swallow your typing.
    // SUPER+ALT+D closes it either way, so there is no stuck state.
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.OnDemand
                                             : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // One rectangle, used three times: the panel's geometry, the input mask,
    // and the blur region. Sharing the source means they cannot drift apart.
    readonly property int cardW: Math.min(Math.round(width * 0.72), Style.space(1100))
    readonly property int cardH: Math.min(Math.round(height * 0.78), Style.space(700))
    readonly property int cardX: Math.round((width - cardW) / 2)
    readonly property int cardY: Math.round((height - cardH) / 2)

    // Everything outside the panel is click-through, so the surface being
    // full-screen costs the windows underneath nothing.
    mask: Region {
      x: panel.cardX
      y: panel.cardY
      width: panel.cardW
      height: panel.cardH
    }

    // Compositor-side blur via ext_background_effect_v1. A Wayland client
    // cannot read the pixels behind its own surface, so this is the only way
    // to frost the real wallpaper rather than a copy of it.
    BackgroundEffect.blurRegion: Region {
      x: panel.cardX
      y: panel.cardY
      width: panel.cardW
      height: panel.cardH
    }

    // ------------------------------------------------------------- the panel
    Rectangle {
      id: card
      x: panel.cardX
      y: panel.cardY
      width: panel.cardW
      height: panel.cardH
      radius: Style.space(24)
      color: Util.alpha(Color.menu.background, 0.65)
      border.width: Math.max(1, Style.space(1))
      border.color: Util.alpha(Color.menu.border, 0.3)

      // Clicking the panel is what hands it keyboard focus, which is what
      // makes ESC work. It deliberately does not dismiss — this is a window
      // you look at, not a modal you swat away.
      MouseArea {
        anchors.fill: parent
        onClicked: keyCatcher.forceActiveFocus()
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
            root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_R) {
            statsFile.reload()
            event.accepted = true
          }
        }
      }

      // No data is its own state. Rendering zeros here would read as
      // "0% complete and on track", which is the exact lie to avoid.
      Column {
        anchors.centerIn: parent
        spacing: Style.spacing.md
        visible: !root.hasData

        Text {
          textFormat: Text.PlainText
          text: "no data"
          color: Color.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.displayLarge
          anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
          textFormat: Text.PlainText
          text: "run: studydash collect"
          color: Color.muted
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }

      Item {
        id: content
        visible: root.hasData
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding

        readonly property int gap: Style.spacing.lg
        readonly property int zoneFourHeight: Style.font.body + Style.spacing.lg * 2
        readonly property int zoneOneHeight: Math.round((height - zoneFourHeight - gap * 2) * 0.52)

        // ----------------------------------------------------------- ZONE 1
        // The number. Everything else on screen is context for it, so it gets
        // the most room and the most whitespace.
        ZoneCard {
          id: zoneOne
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: content.zoneOneHeight
          padding: Style.spacing.xl

          Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            spacing: Style.spacing.sm

            Text {
              textFormat: Text.PlainText
              text: root.courseData ? String(root.courseData.percent) + "%" : ""
              color: root.foreground
              font.family: root.fontFamily
              // No Style token goes near this size; scale off the card so it
              // stays dominant on any monitor. The multiplier is bounded so
              // the three lines beneath it always fit.
              font.pixelSize: Math.max(Style.font.displayLarge,
                                       Math.round(zoneOne.height * 0.30))
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: root.courseData ? String(root.courseData.days_remaining) + " days left" : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }

            Text {
              textFormat: Text.PlainText
              text: root.courseData
                    ? String(root.courseData.name || "") + " · "
                      + String(root.courseData.target_date || "")
                    : ""
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Item { width: 1; height: Style.spacing.lg }

            // The colour-coded line. Required pace against what is actually
            // happening.
            Text {
              textFormat: Text.PlainText
              color: root.statusColor(root.courseData ? root.courseData.status : "unknown")
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              text: {
                if (!root.courseData) return ""
                var required = root.num(root.courseData.percent_per_week_required)
                var actual = root.num(root.courseData.percent_per_week_actual)
                var head = (required === null ? "—" : required + "%/wk") + " needed"
                // A pace we cannot compute is said plainly, never rounded to
                // a number that would imply we know.
                var tail = (actual === null) ? "not enough data yet"
                                             : actual + "%/wk actual"
                return head + "   ·   " + tail
              }
            }

            Text {
              textFormat: Text.PlainText
              color: Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              text: {
                if (!root.courseData) return ""
                var status = String(root.courseData.status || "unknown").replace("_", " ")
                var days = root.courseData.days_since_last_progress
                if (days === null || days === undefined)
                  return status + "   ·   no progress logged yet"
                var n = Number(days)
                return status + "   ·   last progress "
                       + (n === 0 ? "today" : n === 1 ? "1 day ago" : n + " days ago")
              }
            }
          }
        }

        // ------------------------------------------------- ZONES 2 AND 3
        Item {
          id: middle
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: zoneOne.bottom
          anchors.topMargin: content.gap
          anchors.bottom: zoneFour.top
          anchors.bottomMargin: content.gap

          readonly property int columnWidth: Math.round((width - content.gap) / 2)

          // --------------------------------------------------------- ZONE 2
          ZoneCard {
            id: zoneTwo
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: middle.columnWidth

            Column {
              anchors.fill: parent
              spacing: Style.spacing.md

              Text {
                textFormat: Text.PlainText
                color: root.statusColor(root.hoursData ? root.hoursData.status : "unknown")
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                text: {
                  if (!root.hoursData) return "hours"
                  var avg = root.num(root.hoursData.rolling_4wk_weekly_avg)
                  var target = root.num(root.hoursData.target_weekly, 0)
                  return (avg === null ? "—" : avg) + "h/wk average"
                         + (target === null ? "" : "   ·   " + target + "h target")
                }
              }

              WeekBars {
                width: parent.width
                height: Math.max(Style.space(50),
                                 zoneTwo.height - zoneTwo.padding * 2
                                 - Style.font.subtitle - Style.font.caption
                                 - Style.spacing.md * 3)
                weeks: (root.hoursData && root.hoursData.weeks) ? root.hoursData.weeks : []
                targetWeekly: root.hoursData ? Number(root.hoursData.target_weekly) : 0
                barColor: root.foreground
                labelColor: Color.muted
              }

              // A healthy-looking average is never shown without its caveat.
              Text {
                visible: root.hoursData && Number(root.hoursData.truncated_count) > 0
                textFormat: Text.PlainText
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                text: {
                  if (!root.hoursData) return ""
                  var n = Number(root.hoursData.truncated_count)
                  return n + (n === 1 ? " session" : " sessions") + " capped at 4h"
                }
              }
            }
          }

          // --------------------------------------------------------- ZONE 3
          ZoneCard {
            id: zoneThree
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: middle.columnWidth

            Column {
              anchors.fill: parent
              spacing: Style.spacing.md

              Text {
                textFormat: Text.PlainText
                color: Color.muted
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                text: "revision"
              }

              RevisionList {
                width: parent.width
                height: Math.max(Style.space(50),
                                 zoneThree.height - zoneThree.padding * 2
                                 - Style.font.subtitle - Style.spacing.md * 2)
                due: (root.revisionData && root.revisionData.due) ? root.revisionData.due : []
                dueCount: root.revisionData ? Number(root.revisionData.due_count) : 0
                coldTopics: (root.revisionData && root.revisionData.cold_topics)
                            ? root.revisionData.cold_topics : []
                textColor: root.foreground
                mutedColor: Color.muted
                overdueColor: Color.urgent
              }
            }
          }
        }

        // ----------------------------------------------------------- ZONE 4
        // The cost card. Small, muted, bottom. A high number here is bad.
        ZoneCard {
          id: zoneFour
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: content.zoneFourHeight

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            color: root.loadColor(root.loadData ? root.loadData.repos_touched_7d : null)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            text: root.loadData
                  ? "repos touched this week: " + String(root.loadData.repos_touched_7d)
                    + "   ·   28d: " + String(root.loadData.repos_touched_28d)
                  : ""
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            color: Util.alpha(Color.muted, 0.6)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            text: root.stats
                  ? "updated " + String(root.stats.generated_at || "").slice(0, 16).replace("T", " ")
                  : ""
          }
        }
      }
    }
  }
}
