import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Always-on-top "a study session is running" badge.
//
// Why this exists: `studydash session toggle` is asymmetric. Stopping a
// session rewrites stats.json, so the dashboard visibly changes; starting
// one only writes session.current, which nothing else on screen reads.
// With no visible change on start, a running session is invisible and gets
// left running for hours.
//
// Why an overlay rather than a bar widget: the Omarchy bar can be toggled
// off, and a bar widget would then have nowhere to draw. A layer-shell
// overlay is independent of the bar and survives it being hidden.
//
// Read-only by construction: blockWrites means this surface can never corrupt
// session state. It reads one file and renders it; it shells out only when
// you click it, to stop the session.
Item {
  id: root

  // The bundled CLI, resolved by Dashboard.qml from the plugin's own folder,
  // so the badge works before `studydash setup` has put anything on PATH.
  property string cliPath: ""

  readonly property string sessionPath:
    Quickshell.env("HOME") + "/.local/state/studydash/session.current"

  // Minutes after which a session is probably one you forgot to stop. Fed
  // from stats.json, so the badge turns red when the desktop nudge fires.
  property int warnAfterMinutes: 180

  // Epoch ms of the session start, or 0 when nothing is running.
  property real startedMs: 0
  property real nowMs: Date.now()

  readonly property bool running: startedMs > 0
  readonly property int elapsedSeconds:
    running ? Math.max(0, Math.floor((nowMs - startedMs) / 1000)) : 0
  readonly property bool overdue:
    running && warnAfterMinutes > 0 && elapsedSeconds >= warnAfterMinutes * 60

  readonly property color badgeColor: overdue ? Color.urgent : Color.accent

  function formatSpan(totalSeconds) {
    var total = Math.max(0, Math.floor(totalSeconds))
    var hours = Math.floor(total / 3600)
    var minutes = Math.floor((total % 3600) / 60)
    if (hours > 0)
      return hours + "h " + (minutes < 10 ? "0" : "") + minutes + "m"
    return minutes + "m"
  }

  // studydash writes an ISO-8601 timestamp with a UTC offset, e.g.
  // "2026-11-14T09:35:00+01:00". Date.parse handles that directly; anything
  // unparseable is treated as "not running" rather than guessing a start.
  function ingest(text) {
    var raw = String(text || "").trim()
    if (!raw) {
      root.startedMs = 0
      return
    }
    var parsed = Date.parse(raw)
    root.startedMs = isNaN(parsed) ? 0 : parsed
  }

  FileView {
    id: sessionFile
    path: root.sessionPath
    watchChanges: true
    printErrors: false
    // Lazy by default; without preload the indicator never reads the file.
    preload: true
    // Structural guarantee that the indicator cannot write session state.
    blockWrites: true

    onLoaded: root.ingest(sessionFile.text())
    // fileChanged() only reports that the watcher saw a change -- it does not
    // refetch text(). Without an explicit reload() the indicator would keep
    // re-parsing content cached at the last real load and freeze on a stale
    // session. reload() re-triggers the load cycle, ending in onLoaded.
    onFileChanged: sessionFile.reload()
    // No file means session_stop() unlinked it, or none ever started.
    onLoadFailed: root.startedMs = 0
  }

  // One tick per second while running so the elapsed label stays honest.
  // Idle costs nothing: the timer stops entirely.
  Timer {
    interval: 1000
    repeat: true
    running: root.running
    onTriggered: root.nowMs = Date.now()
  }

  // Stopping from the badge runs the same code path as the keybind, so the
  // two can never disagree about what "stop" means.
  Process {
    id: stopProc
    command: [root.cliPath, "session", "stop"]
  }

  PanelWindow {
    id: panel
    // The surface only exists while a session runs, so anything visible in
    // the corner unambiguously means "you are still clocked in".
    visible: root.running
    anchors { top: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-studydash-badge"
    WlrLayershell.layer: WlrLayer.Overlay
    // Never takes the keyboard: this is a passive indicator and must not
    // swallow a keystroke mid-sentence.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Ignore, so the badge floats over windows instead of shrinking their
    // usable area the way a bar would.
    exclusionMode: ExclusionMode.Ignore

    readonly property int pad: Style.space(14)
    implicitWidth: badge.implicitWidth + pad * 2
    implicitHeight: badge.implicitHeight + pad * 2

    // Only the badge itself is clickable; the rest of the surface is
    // click-through so it costs the windows underneath nothing.
    mask: Region {
      x: badge.x
      y: badge.y
      width: badge.width
      height: badge.height
    }

    BackgroundEffect.blurRegion: Region {
      x: badge.x
      y: badge.y
      width: badge.width
      height: badge.height
    }

    Rectangle {
      id: badge
      x: panel.pad
      y: panel.pad
      implicitWidth: row.implicitWidth + Style.space(24)
      implicitHeight: row.implicitHeight + Style.space(14)
      radius: height / 2
      color: Util.alpha(Color.menu.background, 0.72)
      border.width: 1
      border.color: Util.alpha(root.badgeColor, 0.55)

      Row {
        id: row
        anchors.centerIn: parent
        spacing: Style.space(9)

        // The dot breathes while a session is live. Motion is what catches
        // the eye in peripheral vision; a static icon is what got ignored in
        // the first place.
        Rectangle {
          id: dot
          width: Style.space(9)
          height: width
          radius: width / 2
          anchors.verticalCenter: parent.verticalCenter
          color: root.badgeColor

          SequentialAnimation {
            running: root.running
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation {
              target: dot; property: "opacity"
              from: 1.0; to: 0.3; duration: 1100
              easing.type: Easing.InOutQuad
            }
            NumberAnimation {
              target: dot; property: "opacity"
              from: 0.3; to: 1.0; duration: 1100
              easing.type: Easing.InOutQuad
            }
            onStopped: dot.opacity = 1.0
          }
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.overdue
            ? "Studying " + root.formatSpan(root.elapsedSeconds) + " — still running?"
            : "Studying " + root.formatSpan(root.elapsedSeconds)
          color: root.overdue ? root.badgeColor : Color.menu.text
          font.family: Style.fontFamily
          font.pixelSize: Style.space(13)
        }
      }

      // Click the badge to stop the session.
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.cliPath) stopProc.running = true
      }
    }
  }
}
