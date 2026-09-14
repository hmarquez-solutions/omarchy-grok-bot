import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.hmarquez-solutions.grok-bot"
  ipcTarget: "grok-bot"
  manageIpc: false

  readonly property bool showNameInBar: setting("showNameInBar", true) === true
  readonly property bool hideWhenNotInstalled: setting("hideWhenNotInstalled", true) === true
  readonly property int nudgeIntervalMs: Math.max(0, Math.min(120, Number(setting("nudgeIntervalSec", 8)) || 0)) * 1000

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property bool barHidden: bar && bar.barHidden === true

  readonly property var agents: grok.agents
  readonly property var counts: grok.counts
  readonly property string mood: grok.mood

  // The face takes the bar's urgent tone only when a human is needed; a
  // stopped app dims the same mark rather than swapping it.
  readonly property color faceColor: mood === "waiting" ? urgent
    : mood === "asleep" ? Qt.darker(barForeground, 1.55)
    : barForeground
  readonly property string badge: Model.badgeText(counts)
  readonly property color badgeColor: counts.waiting > 0 ? urgent : accent
  readonly property string barLabel: showNameInBar && !vertical && counts.waiting > 0 ? Model.pillLabel(grok.waitingNames) : ""
  readonly property string tooltip: Model.tooltip(grok.installed, grok.running, agents, counts)

  property int phraseIndex: 0
  readonly property int phraseIntervalMs: 2800
  readonly property string heroMetaText: Model.heroMeta(grok.installed, grok.running, agents, counts, phraseIndex)

  // Keyboard cursor: one stop per agent row, then the action row.
  property int cursorIndex: 0
  property bool cursorActive: false
  property int actionIndex: 0

  readonly property var actions: [
    { key: "open", label: grok.running ? "Open" : "Launch", hint: "o", enabled: grok.installed },
    { key: "settings", label: "Settings", hint: "s", enabled: grok.installed },
    { key: "restart", label: "Restart", hint: "R", enabled: grok.installed },
    { key: "quit", label: "Quit", hint: "Q", enabled: grok.running }
  ]

  readonly property var cursorRows: {
    var rows = []
    for (var i = 0; i < agents.length; i++) rows.push("agent:" + agents[i].id)
    rows.push("actions")
    return rows
  }
  readonly property string cursorRow: cursorRows[Math.max(0, Math.min(cursorIndex, cursorRows.length - 1))]

  function rowHasCursor(name) {
    return cursorActive && cursorRow === name
  }

  function focusRow(name) {
    var at = cursorRows.indexOf(name)
    if (at < 0) return
    cursorActive = true
    cursorIndex = at
  }

  function moveCursor(dy) {
    cursorActive = true
    cursorIndex = Math.max(0, Math.min(cursorRows.length - 1, cursorIndex + dy))
  }

  function nudgeCursor(dx) {
    if (cursorRow !== "actions") return
    actionIndex = Math.max(0, Math.min(actions.length - 1, actionIndex + dx))
  }

  function activateCursor() {
    if (cursorRow === "actions") runAction(actions[actionIndex].key)
    else grok.focusApp()
  }

  function runAction(key) {
    if (key === "open") grok.focusApp()
    else if (key === "settings") grok.openSettings()
    else if (key === "restart") grok.restart()
    else if (key === "quit") grok.quit()
  }

  visible: grok.installed || !hideWhenNotInstalled
  implicitWidth: vertical ? button.implicitWidth : button.implicitWidth + (nameLabel.visible ? nameLabel.implicitWidth + Style.space(9) : 0)
  implicitHeight: vertical ? button.implicitHeight + 0 : button.implicitHeight

  Behavior on implicitWidth { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = 0
    actionIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    grok.refresh()
    Qt.callLater(function () { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: grok
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function focus(): string { grok.focusApp(); return "ok" }
    function refresh(): string { grok.refresh(); return "ok" }
    function status(): string {
      return JSON.stringify({
        running: grok.running,
        mood: grok.mood,
        waiting: grok.waitingNames,
        working: grok.workingNames,
        unread: grok.counts.unread,
        agents: grok.counts.total,
        rosterFound: grok.rosterFound,
        schemaUnsupported: grok.schemaUnsupported,
        error: grok.lastError
      })
    }
  }

  // ---- bar ----------------------------------------------------------------

  BarIconButton {
    id: button
    anchors.left: parent.left
    anchors.top: parent.top
    bar: root.bar
    tooltipText: root.tooltip
    dimmed: false
    iconComponent: Component {
      Item {
        Face {
          anchors.centerIn: parent
          iconSize: Style.bar.iconCanvas
          color: root.faceColor
          eyeColor: Color.bar.background
          mood: root.mood
          animate: !root.barHidden
          nudgeIntervalMs: root.nudgeIntervalMs
        }

        // Count of agents that need you, or with news. Sits on the head's shoulder.
        Rectangle {
          visible: root.badge !== ""
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.rightMargin: -Style.space(2)
          anchors.topMargin: -Style.space(2)
          width: Math.max(implicitWidth, height)
          height: Style.space(9)
          implicitWidth: badgeText.implicitWidth + Style.space(4)
          radius: height / 2
          color: root.badgeColor
          border.width: 1
          border.color: Color.bar.background
          scale: visible ? 1 : 0

          Behavior on color { ColorAnimation { duration: 200 } }

          Text {
            id: badgeText
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: root.badge
            color: Color.bar.background
            font.family: root.fontFamily
            font.pixelSize: Style.space(7)
            font.bold: true
          }
        }
      }
    }
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.RightButton) grok.focusApp()
      else if (buttonCode === Qt.MiddleButton) grok.refresh()
      else root.toggle()
    }
  }

  // The waiting agent's name, so the bar says who, not just that.
  Text {
    id: nameLabel
    textFormat: Text.PlainText
    visible: root.barLabel !== ""
    anchors.left: button.right
    anchors.leftMargin: -Style.space(1)
    anchors.verticalCenter: button.verticalCenter
    text: root.barLabel
    color: root.urgent
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.bold: true
    renderType: Text.NativeRendering

    MouseArea {
      anchors.fill: parent
      anchors.rightMargin: -Style.space(8)
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      hoverEnabled: true
      onEntered: if (root.bar) root.bar.showTooltip(button, root.tooltip)
      onExited: if (root.bar) root.bar.hideTooltip(button)
      onClicked: function (mouse) { button.triggerPress(mouse.button) }
    }
  }

  // ---- panel --------------------------------------------------------------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function (dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.nudgeCursor(dx)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        var key = String(t)
        if (key === "r") grok.refresh()
        else if (key === "o") grok.focusApp()
        else if (key === "s") grok.openSettings()
        else if (key === "R") grok.restart()
        else if (key === "Q") grok.quit()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "Grok Bot"
            detail: grok.appVersion !== "" && grok.running ? "v" + grok.appVersion : ""
            meta: root.heroMetaText
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: grok.running ? 1.0 : 0.55
            iconComponent: Component {
              Face {
                iconSize: Style.space(40)
                color: root.mood === "waiting" ? root.urgent : (grok.running ? root.foreground : root.dim)
                eyeColor: Color.popups.background
                mood: root.mood
                animate: root.opened
                nudgeIntervalMs: root.nudgeIntervalMs
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: grok.actionStatus !== "" || grok.lastError !== "" || grok.crashed
            width: parent.width
            text: grok.actionStatus !== "" ? grok.actionStatus
              : grok.lastError !== "" ? grok.lastError
              : "Grok Bot recorded a crash in its last session"
            color: grok.actionStatus !== "" ? root.dim : root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // Agents blocked on you come first and get their own heading.
          Column {
            visible: root.counts.waiting > 0
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "NEEDS YOU"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.agents.filter(function (a) { return a.state === "waiting" })
              AgentRow { width: column.width; agent: modelData }
            }
          }

          PanelSeparator {
            visible: root.counts.waiting > 0 && root.agents.length > root.counts.waiting
            foreground: root.foreground
          }

          Column {
            visible: root.agents.length > root.counts.waiting
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "AGENTS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.agents.filter(function (a) { return a.state !== "waiting" })
              AgentRow { width: column.width; agent: modelData }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.agents.length === 0
            width: parent.width
            text: !grok.installed ? "Install Grok Bot from the Omarchy repo: sudo pacman -S grok-bot"
              : !grok.running ? "Grok Bot is not running. Press o to launch it."
              : grok.schemaUnsupported ? "Grok Bot changed its roster format. Update this plugin."
              : grok.rosterFound ? "No agents yet. Create one in Grok Bot and it shows up here."
              : "Sign in to Grok Bot to see your agents here."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }

          PanelSeparator {
            foreground: root.foreground
          }

          ActionRow {
            width: parent.width
          }
        }
      }
    }
  }

  // Idle phrases rotate the way the stock panels do.
  Timer {
    interval: root.phraseIntervalMs
    running: root.opened && grok.running && root.counts.waiting === 0 && root.counts.working === 0 && root.counts.unread === 0 && root.agents.length > 0
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation { target: hero; property: "metaOpacity"; to: 0.0; duration: 180; easing.type: Easing.OutQuad }
    ScriptAction { script: root.phraseIndex = (root.phraseIndex + 1) % Model.IDLE_PHRASES.length }
    PropertyAnimation { target: hero; property: "metaOpacity"; to: 1.0; duration: 260; easing.type: Easing.InQuad }
  }

  // One agent: state mark, name, what it last said, and how long ago.
  component AgentRow: CursorSurface {
    id: agentRow
    property var agent: ({})

    readonly property string rowName: "agent:" + (agent ? agent.id : "")
    readonly property bool waiting: agent && agent.state === "waiting"
    readonly property bool working: agent && agent.state === "working"
    readonly property bool unread: agent && agent.state === "unread"
    readonly property string caption: waiting ? Model.reasonText(agent)
      : (agent && agent.lastText !== "" ? agent.lastText : (working ? "Working" : "Nothing yet"))

    hasCursor: root.rowHasCursor(rowName)
    foreground: root.foreground
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.focusRow(agentRow.rowName)
      onClicked: grok.focusApp()
    }

    RowLayout {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(10)

      StateMark {
        Layout.alignment: Qt.AlignVCenter
        state: agentRow.agent ? agentRow.agent.state : "idle"
        animate: root.opened
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          Text {
            textFormat: Text.PlainText
            Layout.fillWidth: true
            text: agentRow.agent ? agentRow.agent.name : ""
            color: agentRow.waiting ? root.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: agentRow.waiting || agentRow.unread
            elide: Text.ElideRight
          }

          BorderSurface {
            visible: agentRow.unread && agentRow.agent.unread > 1
            implicitWidth: unreadText.implicitWidth + Style.space(8)
            implicitHeight: unreadText.implicitHeight + Style.space(2)
            color: "transparent"
            borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
            radius: Style.cornerRadius

            Text {
              id: unreadText
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: agentRow.agent ? String(agentRow.agent.unread) : ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: agentRow.caption
          color: agentRow.waiting ? root.foreground : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        textFormat: Text.PlainText
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: Style.space(30)
        horizontalAlignment: Text.AlignRight
        text: Model.relTime(agentRow.agent ? agentRow.agent.lastActivityAt : 0, grok.nowMs)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // The dot before a row: pulsing while working, urgent while waiting, accent
  // for unread, faint when idle.
  component StateMark: Item {
    id: mark
    property string state: "idle"
    property bool animate: true

    implicitWidth: Style.space(10)
    implicitHeight: Style.space(10)

    readonly property color tone: state === "waiting" ? root.urgent
      : state === "unread" ? root.accent
      : state === "working" ? root.foreground
      : Qt.darker(root.foreground, 2.6)

    Rectangle {
      id: dot
      anchors.centerIn: parent
      width: Style.space(6)
      height: width
      radius: width / 2
      color: mark.tone
      Behavior on color { ColorAnimation { duration: 200 } }

      SequentialAnimation on opacity {
        running: mark.animate && mark.state === "working"
        loops: Animation.Infinite
        onStopped: dot.opacity = 1
        NumberAnimation { to: 0.25; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
      }
    }

    // A halo that breathes out while an agent works.
    Rectangle {
      anchors.centerIn: parent
      width: Style.space(10)
      height: width
      radius: width / 2
      color: "transparent"
      border.width: 1
      border.color: mark.tone
      visible: mark.state === "working"
      opacity: 0

      SequentialAnimation on opacity {
        running: mark.animate && mark.state === "working"
        loops: Animation.Infinite
        NumberAnimation { to: 0.6; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0.0; duration: 700; easing.type: Easing.InOutSine }
      }
    }
  }

  // Open as a wide button, then Settings, Restart and Quit as icon buttons, one
  // cursor row; h and l walk the four.
  component ActionRow: CursorSurface {
    id: actionRow
    hasCursor: root.rowHasCursor("actions")
    foreground: root.foreground
    implicitHeight: actionLayout.implicitHeight + Style.space(10)

    HoverHandler {
      onHoveredChanged: if (hovered) root.focusRow("actions")
    }

    RowLayout {
      id: actionLayout
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(6)

      Button {
        Layout.fillWidth: true
        text: root.actions[0].label + " Grok Bot"
        iconText: grok.running ? "󰁔" : "󰐊"
        fontSize: Style.font.body
        foreground: root.foreground
        fontFamily: root.fontFamily
        bordered: true
        enabled: root.actions[0].enabled
        opacity: enabled ? 1 : 0.45
        tooltipText: (grok.running ? "Open Grok Bot" : "Launch Grok Bot") + "  ·  o"
        hasCursor: root.rowHasCursor("actions") && root.actionIndex === 0
        onClicked: root.runAction("open")
        onHovered: function (h) { if (h) { root.focusRow("actions"); root.actionIndex = 0 } }
      }

      Repeater {
        model: [
          { key: "settings", icon: "󰒓", tip: "Grok Bot settings  ·  s", index: 1 },
          { key: "restart", icon: "󰜉", tip: "Restart Grok Bot  ·  Shift+R", index: 2 },
          { key: "quit", icon: "󰅖", tip: "Quit Grok Bot  ·  Shift+Q", index: 3 }
        ]

        PanelActionButton {
          required property var modelData
          Layout.alignment: Qt.AlignVCenter
          iconText: modelData.icon
          tooltipText: modelData.tip
          foreground: root.foreground
          fontFamily: root.fontFamily
          fontSize: Style.font.iconLarge
          bordered: true
          enabled: root.actions[modelData.index].enabled
          opacity: enabled ? 1 : 0.45
          hasCursor: root.rowHasCursor("actions") && root.actionIndex === modelData.index
          onClicked: root.runAction(modelData.key)
          onHovered: function (h) { if (h) { root.focusRow("actions"); root.actionIndex = modelData.index } }
        }
      }
    }
  }
}
