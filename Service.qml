import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Model.js" as Model

// Everything the widget knows about Grok Bot, read from what the app already
// leaves on disk and what the compositor already knows. Nothing here talks
// to Grok Bot's servers, and nothing writes into its directories.
Item {
  id: root

  property var settings: ({})

  // Presence.
  property bool installed: true
  property bool markerAlive: false
  property bool crashed: false
  property string appVersion: ""
  readonly property var appWindow: grokWindow()
  readonly property bool windowOpen: appWindow !== null
  readonly property bool focused: windowOpen && appWindow.activated === true
  readonly property bool running: windowOpen || markerAlive

  // Roster.
  property var rawAgents: []
  property bool rosterFound: false
  property bool schemaUnsupported: false
  property string lastError: ""
  property string actionStatus: ""
  property string persistDir: (Quickshell.env("HOME") || "") + "/.config/Grok Bot/sand-client-persistence"
  property string markerPath: (Quickshell.env("HOME") || "") + "/.config/Grok Bot/sand-session-marker.json"
  property string rosterFile: ""
  property var transcriptFiles: ({})

  // Transcript churn per agent id, the only local trace of "working".
  property var activityAt: ({})
  property real nowMs: Date.now()

  readonly property int workingWindowMs: Math.max(3, Math.min(120, setting("workingWindowSec", 12))) * 1000
  readonly property int markerStaleMs: 150000
  readonly property int maxRosterChars: 1 << 20
  readonly property int commandTimeoutMs: 4000
  readonly property int actionStatusMs: 3200

  readonly property var agents: Model.decorate(rawAgents, nowMs, activityAt, workingWindowMs)
  readonly property var counts: Model.countStates(agents)
  readonly property var waitingNames: Model.namesIn(agents, Model.STATE_WAITING)
  readonly property var workingNames: Model.namesIn(agents, Model.STATE_WORKING)
  readonly property bool anyWorking: counts.working > 0
  readonly property string mood: Model.mood(running, counts)
  readonly property bool busy: commandProcess.running

  signal waitingArrived(string name)

  property int _lastWaiting: 0
  property string _commandErrorText: ""
  property bool _commandTimedOut: false
  property var _afterCommand: null
  property int _watchRestarts: 0

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function grokWindow() {
    var list = ToplevelManager.toplevels.values
    for (var i = 0; i < list.length; i++) {
      if (list[i] && Model.isGrokAppId(list[i].appId)) return list[i]
    }
    return null
  }

  function refresh() {
    nowMs = Date.now()
    listProcess.running = false
    listProcess.running = true
    markerFile.reload()
    if (rosterFile !== "") rosterView.reload()
  }

  Component.onCompleted: refresh()

  onCountsChanged: {
    if (counts.waiting > _lastWaiting && waitingNames.length > 0) waitingArrived(waitingNames[0])
    _lastWaiting = counts.waiting
  }

  // ---- roster -------------------------------------------------------------

  function _applyListing(text) {
    var names = String(text).split("\n").filter(function (n) { return n !== "" })
    transcriptFiles = Model.transcriptIndex(names)
    var roster = Model.findRosterFile(names)
    rosterFound = roster !== ""
    if (roster !== rosterFile) {
      rosterFile = roster
      if (roster !== "") rosterView.reload()
    }
    if (!rosterFound) rawAgents = []
  }

  function _applyRoster(text) {
    var s = String(text)
    if (s.length > maxRosterChars) {
      lastError = "roster file is too large"
      return
    }
    var parsed = Model.parseRoster(s)
    schemaUnsupported = parsed.schemaTooNew === true
    if (!parsed.ok) {
      lastError = parsed.error
      return
    }
    lastError = ""
    nowMs = Date.now()
    rawAgents = parsed.rows
  }

  function _noteActivity(agentId) {
    if (!agentId) return
    var next = {}
    for (var k in activityAt) next[k] = activityAt[k]
    next[agentId] = Date.now()
    nowMs = next[agentId]
    activityAt = next
  }

  function _onWatchLine(line) {
    var parts = String(line).split("|")
    if (parts.length < 2) return
    var events = parts[0]
    var file = parts.slice(1).join("|")
    if (events.indexOf("DELETE_SELF") >= 0 || events.indexOf("UNMOUNT") >= 0) {
      rawAgents = []
      rosterFound = false
      return
    }
    var known = transcriptFiles[file]
    if (known) {
      _noteActivity(known)
      return
    }
    var info = Model.classifyBlob(file)
    if (info.kind === "transcript") {
      var next = {}
      for (var k in transcriptFiles) next[k] = transcriptFiles[k]
      next[file] = info.agentId
      transcriptFiles = next
      _noteActivity(info.agentId)
    } else if (info.kind === "roster") {
      if (file !== rosterFile) {
        rosterFile = file
        rosterFound = true
      }
      rosterView.reload()
    }
  }

  Process {
    id: listProcess
    running: true
    command: ["ls", "-1", root.persistDir]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._applyListing(text)
    }
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root.rosterFound = false
        root.rosterFile = ""
        root.rawAgents = []
      }
    }
  }

  FileView {
    id: rosterView
    path: root.rosterFile !== "" ? root.persistDir + "/" + root.rosterFile : ""
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root._applyRoster(text())
    onLoadFailed: {
      if (root.rosterFile !== "") {
        // The app replaced the file under us; the directory watcher names the new one.
        listProcess.running = true
      }
    }
  }

  // Streams every write in the persistence directory: the roster to reload,
  // a transcript to stamp as active. Cheaper than any poll and immediate.
  Process {
    id: watchProcess
    running: root.installed
    command: ["inotifywait", "-m", "-q", "-e", "close_write", "-e", "moved_to", "-e", "create", "-e", "delete_self", "--format", "%e|%f", root.persistDir]
    stdout: SplitParser {
      onRead: function (data) { root._onWatchLine(data) }
    }
    stderr: SplitParser {
      splitMarker: ""
      onRead: function (data) { /* drop: a missing directory is reported by exit */ }
    }
    onExited: function () {
      root._watchRestarts += 1
      watchRestart.interval = Math.min(60000, 5000 * root._watchRestarts)
      watchRestart.restart()
    }
  }

  Timer {
    id: watchRestart
    repeat: false
    onTriggered: {
      if (!watchProcess.running) {
        listProcess.running = true
        watchProcess.running = true
      }
    }
  }

  // Ticks only while something is working, so "working" can lapse on time.
  Timer {
    interval: 1000
    running: root.anyWorking
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  // Row timestamps and the heartbeat stay honest without any file changing.
  Timer {
    interval: 20000
    running: true
    repeat: true
    onTriggered: {
      root.nowMs = Date.now()
      markerFile.reload()
    }
  }

  // ---- presence -----------------------------------------------------------

  FileView {
    id: markerFile
    path: root.markerPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var marker = Model.parseMarker(text(), Date.now(), root.markerStaleMs)
      root.markerAlive = marker.alive
      root.crashed = marker.crashed
      if (marker.version) root.appVersion = marker.version
      if (marker.ok) root.installed = true
    }
    onLoadFailed: {
      root.markerAlive = false
      root.crashed = false
    }
  }

  Process {
    id: whichProcess
    running: true
    command: ["sh", "-c", "command -v grok-bot >/dev/null 2>&1 || test -x '/opt/Grok Bot/grok-bot'"]
    onExited: function (exitCode) { root.installed = exitCode === 0 || root.markerAlive }
  }

  // ---- actions ------------------------------------------------------------

  function focusApp() {
    if (appWindow) {
      appWindow.activate()
      return
    }
    launch()
  }

  function launch() {
    if (!installed) {
      _status("Grok Bot is not installed")
      return
    }
    Quickshell.execDetached(["setsid", "-f", "grok-bot"])
    _status(running ? "Opening Grok Bot" : "Starting Grok Bot")
  }

  function openSettings() {
    if (!installed) return
    Quickshell.execDetached(["setsid", "-f", "grok-bot", "grokbot://app/v1/settings"])
  }

  function quit() {
    if (!running) return
    _run(["pkill", "-x", "grok-bot"], null)
    _status("Quitting Grok Bot")
  }

  function restart() {
    if (!running) {
      launch()
      return
    }
    _run(["pkill", "-x", "grok-bot"], function () { relaunch.restart() })
    _status("Restarting Grok Bot")
  }

  Timer {
    id: relaunch
    interval: 900
    repeat: false
    onTriggered: Quickshell.execDetached(["setsid", "-f", "grok-bot"])
  }

  function _status(text) {
    actionStatus = text
    actionStatusTimer.restart()
  }

  function _run(argv, after) {
    if (commandProcess.running) return
    _commandErrorText = ""
    _commandTimedOut = false
    _afterCommand = after
    commandProcess.command = argv
    commandTimeoutTimer.restart()
    commandProcess.running = true
  }

  Timer {
    id: actionStatusTimer
    interval: root.actionStatusMs
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: commandTimeoutTimer
    interval: root.commandTimeoutMs
    repeat: false
    onTriggered: {
      if (commandProcess.running) {
        root._commandTimedOut = true
        commandProcess.signal(9)
      }
    }
  }

  Process {
    id: commandProcess
    running: false
    command: []
    stderr: SplitParser {
      splitMarker: ""
      onRead: function (data) {
        var remaining = 512 - root._commandErrorText.length
        if (remaining > 0) root._commandErrorText += String(data).slice(0, remaining)
      }
    }
    onExited: function (exitCode) {
      commandTimeoutTimer.stop()
      var after = root._afterCommand
      root._afterCommand = null
      // pkill exits 1 when nothing matched, which is not a failure here.
      if (exitCode > 1 || root._commandTimedOut) {
        root._status(Model.elideError(root._commandTimedOut ? "command timed out" : (root._commandErrorText || "command failed")))
        return
      }
      if (after) after()
    }
  }
}
