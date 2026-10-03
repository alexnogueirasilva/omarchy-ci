import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// One poller for the whole shell. The bar builds a widget per monitor, so the
// GitHub calls live here and every panel only reads this object.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string pluginId: "alex.ci"
  readonly property string scriptPath: (Quickshell.env("HOME") || "")
    + "/.config/omarchy/plugins/alex.ci/bin/ci.py"

  property var runs: []
  property var pollErrors: []
  property string errorText: ""
  property bool polling: false
  property string checkedAt: ""

  property string logKey: ""
  property string logText: ""
  property bool logBusy: false
  property string logError: ""

  readonly property int failing: countState(["failure", "timed_out", "startup_failure"])
  readonly property int running: countState(["in_progress", "queued", "waiting"])

  function countState(names) {
    var total = 0
    for (var i = 0; i < runs.length; i++) {
      var state = String(runs[i].conclusion || runs[i].status || "")
      if (names.indexOf(state) !== -1) total++
    }
    return total
  }

  function stateOf(run) {
    return String((run && (run.conclusion || run.status)) || "")
  }

  function refresh() {
    if (poller.running) return
    root.polling = true
    poller.running = true
  }

  function loadLog(repo, runId) {
    var key = String(repo) + "#" + String(runId)
    if (root.logKey === key && root.logText !== "") return
    root.logKey = key
    root.logText = ""
    root.logError = ""
    root.logBusy = true
    logFetch.command = ["python3", root.scriptPath, "log", String(repo), String(runId)]
    logFetch.running = true
  }

  function copyLog() {
    var text = root.logText
    if (text === "") return "empty"
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
    return "ok"
  }

  function openUrl(url) {
    if (!url) return
    Quickshell.execDetached(["xdg-open", String(url)])
  }

  Process {
    id: poller
    command: ["python3", root.scriptPath, "poll"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.polling = false
        var parsed = null
        try { parsed = JSON.parse(text || "") } catch (e) { parsed = null }
        if (!parsed || !parsed.runs) {
          root.errorText = parsed && parsed.error ? String(parsed.error) : "Não consegui ler as Actions."
          return
        }
        root.runs = parsed.runs
        root.pollErrors = parsed.errors || []
        root.errorText = ""
        root.checkedAt = new Date().toLocaleTimeString(Qt.locale(), "HH:mm")
      }
    }
  }

  Process {
    id: logFetch
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.logBusy = false
        var parsed = null
        try { parsed = JSON.parse(text || "") } catch (e) { parsed = null }
        if (!parsed || typeof parsed.text !== "string") {
          root.logError = parsed && parsed.error ? String(parsed.error) : "Não consegui baixar o log."
          root.logText = ""
          return
        }
        root.logError = ""
        root.logText = parsed.text
      }
    }
  }

  Timer {
    interval: 120000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: "alex.ci"
    function refresh(): string { root.refresh(); return "ok" }
  }
}
