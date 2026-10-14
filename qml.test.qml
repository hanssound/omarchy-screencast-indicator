import QtQuick
import Quickshell
import "." as Plugin
import "Model.js" as Model

ShellRoot {
  id: test
  property int stage: 0
  property int baselineWrites: 0

  function check(condition, message) {
    if (!condition) throw new Error(message)
  }

  Plugin.Service {
    id: watcher
    property int historyWrites: 0
    onHistoryChanged: historyWrites++
  }

  Timer {
    interval: 250
    running: true
    repeat: true
    onTriggered: {
      try {
        if (test.stage === 0) {
          test.check(watcher.active, "probe output did not activate capture")
          test.check(Model.appsLabel(watcher.history[0]) === "Example browser", "probe names were lost at exit")
          test.baselineWrites = watcher.historyWrites
          watcher.refresh()
          watcher.refresh()
        } else if (test.stage === 1) {
          test.check(watcher.historyWrites === test.baselineWrites, "unchanged probes rebuilt history")
          watcher.refresh()
        } else {
          test.check(watcher.probeActive, "failed PipeWire probe erased capture state")
          test.check(watcher.historyWrites === test.baselineWrites, "unchanged probes rebuilt history")
          watcher.hyprTargets = Model.updateTargets([], "1,monitor,display")
          watcher.hyprTargets = Model.updateTargets(watcher.hyprTargets, "1,window,example")
          watcher.probeActive = false
          watcher.hyprTargets = Model.updateTargets(watcher.hyprTargets, "0,monitor,display")
          test.check(watcher.active && !watcher.history[0].end, "one stopped target hid another")
          watcher.lingerSeconds = 0
          watcher.hyprTargets = Model.updateTargets(watcher.hyprTargets, "0,window,example")
          test.check(!watcher.active && !watcher.lingering && watcher.history[0].end > 0, "zero linger did not finish capture")
          watcher.lingerSeconds = 15
          watcher.hyprTargets = Model.updateTargets([], "1,region,")
          test.check(watcher.active && watcher.history.length === 1, "brief pause did not merge")
          watcher.hyprTargets = []
          test.check(watcher.lingering, "finished capture did not linger")
          console.log("QML tests PASS (no screen capture)")
          Qt.quit()
        }
        test.stage++
      } catch (error) {
        console.error("QML tests FAIL: " + error.message)
        Qt.quit()
      }
    }
  }
}
