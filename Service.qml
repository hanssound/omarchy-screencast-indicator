import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Model.js" as Model

// One capture watcher for every bar (the widget exists once per monitor).
// No idle probes: it wakes on Hyprland screencast events and on the KMS
// socket gpu-screen-recorder creates, and polls only while something captures.
Item {
  id: root

  // Seconds the dot stays after a capture ends; the widget pushes its setting.
  property int lingerSeconds: 15

  property var hyprTargets: []
  readonly property bool hyprActive: hyprTargets.length > 0
  property bool probeActive: false
  readonly property bool active: hyprActive || probeActive
  property bool lingering: false
  property var history: []
  property string target: "Screen"
  property bool pending: false

  onActiveChanged: {
    var now = Date.now()
    if (active) {
      lingerTimer.stop()
      lingering = false
      history = Model.begin(history, now, hyprActive ? target : "Screen")
    } else {
      history = Model.finish(history, now)
      lingering = lingerSeconds > 0
      if (lingering) lingerTimer.restart()
    }
  }

  function refresh() {
    debounce.stop()
    if (probe.running) { pending = true; return }
    probe.running = true
  }

  // Every Wayland capture path (screencopy, toplevel export, portal shares,
  // one-frame screenshots, color pickers) reports here.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name !== "screencastv2") return
      var targets = Model.updateTargets(root.hyprTargets, event.data)
      if (targets === root.hyprTargets) return
      var on = String(event.data).charAt(0) === "1"
      if (on) root.target = Model.targetFromEvent(event.data)
      root.hyprTargets = targets
      // Probe at once on start: a screenshot tool may exit within ~100 ms.
      if (on) root.refresh()
      else debounce.restart()
    }
  }

  // KMS capture bypasses Hyprland entirely; gsr-kms-server's socket in /tmp
  // appearing and vanishing is the only cue.
  Process {
    id: kmsWatch
    command: ["inotifywait", "-m", "-q", "-e", "create,delete", "--include", "gsr-kms-socket", "--format", "%e", "/tmp"]
    running: true
    stdout: SplitParser { onRead: debounce.restart() }
    onExited: kmsRetry.start()
  }
  Timer { id: kmsRetry; interval: 5000; onTriggered: kmsWatch.running = true }

  Timer { id: debounce; interval: 150; onTriggered: root.refresh() }
  // Shares and recordings can end without any event (app quits, frames pause).
  Timer { interval: 2000; repeat: true; running: root.active; onTriggered: root.refresh() }
  Timer { id: lingerTimer; interval: root.lingerSeconds * 1000; onTriggered: root.lingering = false }

  Process {
    id: probe
    command: ["timeout", "-k", "0.2s", "2s", "bash", decodeURIComponent(String(Qt.resolvedUrl("probe.sh")).replace(/^file:\/\//, ""))]
    stdout: StdioCollector {
      id: probeOutput
      waitForEnd: true
    }
    onExited: function(exitCode) {
      // A failed probe must not erase the last known capture state.
      if (exitCode === 0) {
        var result = Model.parseProbe(probeOutput.text)
        root.probeActive = result.active
        root.history = Model.addApps(root.history, result.names, Date.now())
      }
      if (root.pending) { root.pending = false; Qt.callLater(root.refresh) }
    }
  }

  Component.onCompleted: refresh()
}
