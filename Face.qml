import QtQuick
import qs.Commons

// Grok Bot's face as a single-colour mark: the rounded head with two slanted
// pill eyes from the app icon, cut in the bar's background so it reads as a
// glyph in any theme. Everything expressive is a number the mood drives, so
// the pill and the panel hero share one component at two sizes.
//
// Moods:
//   asleep   dimmed, eyes nearly shut, nothing moves
//   idle     eyes open, blinks now and then, gaze wanders
//   working  eyes narrowed and scanning, slow breathing
//   unread   eyes soft, one hop when the news lands
//   waiting  wide-eyed and upright, a nudge every few seconds
Item {
  id: root

  property real iconSize: Style.bar.iconCanvas
  property color color: Color.foreground
  property color eyeColor: Color.bar.background
  property string mood: "idle"
  // Off while the bar is hidden or the panel is closed, so nothing ticks unseen.
  property bool animate: true
  // 0 nudges once on arrival and then holds still.
  property int nudgeIntervalMs: 8000

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize

  readonly property bool asleep: mood === "asleep"
  readonly property bool live: animate && visible && !asleep

  readonly property real headSize: Math.max(4, Math.round(iconSize * 0.94))
  readonly property real unit: headSize / 16
  readonly property real maxGaze: unit * 1.3

  // Resting values per mood. The animations below layer motion on top.
  readonly property real restEyeOpen: asleep ? 0.66
    : mood === "waiting" ? 1.22
    : mood === "working" ? 0.74
    : mood === "unread" ? 0.9
    : 1.0
  readonly property real restTilt: asleep ? -72 : mood === "waiting" ? -8 : mood === "working" ? -34 : -28
  readonly property real restGazeY: mood === "working" ? -unit * 0.6 : 0

  property real eyeOpen: restEyeOpen
  property real blink: 0
  property real tilt: restTilt
  property real gazeX: 0
  property real gazeY: restGazeY
  property real breath: 1
  property real wiggle: 0
  property real hop: 0

  Behavior on eyeOpen { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
  Behavior on tilt { NumberAnimation { duration: 320; easing.type: Easing.InOutCubic } }
  Behavior on gazeX { enabled: root.mood !== "working"; NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }
  Behavior on gazeY { NumberAnimation { duration: 420; easing.type: Easing.OutCubic } }

  onRestEyeOpenChanged: eyeOpen = restEyeOpen
  onRestTiltChanged: tilt = restTilt
  onRestGazeYChanged: gazeY = restGazeY

  onMoodChanged: {
    if (mood !== "working") gazeX = 0
    if (mood !== "working") breath = 1
    if (mood !== "waiting") wiggle = 0
    if (mood === "waiting" || mood === "unread") { if (live) arrival.restart() }
    else hop = 0
  }

  // A rare blink with the occasional double, only while awake.
  SequentialAnimation {
    running: root.live
    loops: Animation.Infinite
    PauseAnimation { duration: 2900 }
    NumberAnimation { target: root; property: "blink"; to: 1; duration: 60 }
    NumberAnimation { target: root; property: "blink"; to: 0; duration: 120 }
    PauseAnimation { duration: 4100 }
    NumberAnimation { target: root; property: "blink"; to: 1; duration: 60 }
    NumberAnimation { target: root; property: "blink"; to: 0; duration: 90 }
    NumberAnimation { target: root; property: "blink"; to: 1; duration: 60 }
    NumberAnimation { target: root; property: "blink"; to: 0; duration: 130 }
    PauseAnimation { duration: 3300 }
  }

  // Idle: glance somewhere new every few seconds.
  Timer {
    interval: 3400
    running: root.live && root.mood === "idle"
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      var side = Math.random() < 0.5 ? -1 : 1
      root.gazeX = side * root.maxGaze * (0.4 + Math.random() * 0.6)
      root.gazeY = (Math.random() - 0.5) * root.maxGaze * 0.8
    }
  }

  // Working: read left to right and breathe.
  SequentialAnimation {
    running: root.live && root.mood === "working"
    loops: Animation.Infinite
    onStopped: root.gazeX = 0
    NumberAnimation { target: root; property: "gazeX"; to: -root.maxGaze; duration: 760; easing.type: Easing.InOutSine }
    PauseAnimation { duration: 140 }
    NumberAnimation { target: root; property: "gazeX"; to: root.maxGaze; duration: 760; easing.type: Easing.InOutSine }
    PauseAnimation { duration: 140 }
  }

  SequentialAnimation {
    running: root.live && root.mood === "working"
    loops: Animation.Infinite
    onStopped: root.breath = 1
    NumberAnimation { target: root; property: "breath"; to: 1.06; duration: 1300; easing.type: Easing.InOutSine }
    NumberAnimation { target: root; property: "breath"; to: 1.0; duration: 1300; easing.type: Easing.InOutSine }
  }

  // Waiting: a quick head shake, repeated on the configured interval.
  SequentialAnimation {
    id: nudge
    running: root.live && root.mood === "waiting"
    loops: root.nudgeIntervalMs > 0 ? Animation.Infinite : 1
    onStopped: root.wiggle = 0
    PauseAnimation { duration: 900 }
    NumberAnimation { target: root; property: "wiggle"; to: -14; duration: 70; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "wiggle"; to: 12; duration: 120; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "wiggle"; to: -8; duration: 110; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "wiggle"; to: 5; duration: 100; easing.type: Easing.InOutQuad }
    NumberAnimation { target: root; property: "wiggle"; to: 0; duration: 130; easing.type: Easing.OutQuad }
    PauseAnimation { duration: Math.max(1500, root.nudgeIntervalMs) }
  }

  // The hop that says "something new".
  SequentialAnimation {
    id: arrival
    NumberAnimation { target: root; property: "hop"; to: -root.unit * 2.4; duration: 130; easing.type: Easing.OutQuad }
    NumberAnimation { target: root; property: "hop"; to: 0; duration: 420; easing.type: Easing.OutBounce }
  }

  Item {
    id: head
    width: root.headSize
    height: root.headSize
    anchors.centerIn: parent
    anchors.verticalCenterOffset: root.hop
    scale: root.breath
    rotation: root.wiggle
    transformOrigin: Item.Center

    Rectangle {
      anchors.fill: parent
      radius: width * 0.44
      color: root.color
      antialiasing: true
      Behavior on color { ColorAnimation { duration: 240 } }
    }

    Item {
      id: eyes
      anchors.centerIn: parent
      anchors.horizontalCenterOffset: root.gazeX
      anchors.verticalCenterOffset: root.gazeY + root.unit * 0.3
      width: parent.width
      height: parent.height

      readonly property real eyeWidth: Math.max(1.6, root.unit * 2.4)
      readonly property real eyeHeight: Math.max(eyeWidth, root.unit * 5.6 * root.eyeOpen * (1 - root.blink * 0.85))
      readonly property real gap: root.unit * 4.6

      // The icon's left eye sits a little lower than the right.
      Rectangle {
        width: eyes.eyeWidth
        height: eyes.eyeHeight
        radius: width / 2
        color: root.eyeColor
        antialiasing: true
        rotation: root.tilt
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: -eyes.gap / 2
        anchors.verticalCenterOffset: root.unit * 0.55
      }

      Rectangle {
        width: eyes.eyeWidth
        height: eyes.eyeHeight
        radius: width / 2
        color: root.eyeColor
        antialiasing: true
        rotation: root.tilt
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: eyes.gap / 2
        anchors.verticalCenterOffset: -root.unit * 0.55
      }
    }
  }
}
