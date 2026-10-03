import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property var shell: null
  readonly property string pluginId: "z.theme-roulette"
  readonly property string helper: decodeURIComponent(String(Qt.resolvedUrl("roulette.py")).replace(/^file:\/\//, ""))
  property var config: ({})
  property bool loaded: false
  property var themes: []
  property string currentTheme: ""
  property string section: "right"
  property string message: ""
  property string lastError: ""
  property double scheduleStartEpoch: Date.now()
  readonly property bool autoEnabled: config.enabled === true
  readonly property string pool: ["Dark", "Light", "Any"].indexOf(config.pool) >= 0 ? config.pool : "Any"
  readonly property int intervalMinutes: Number(config.intervalMinutes) >= 5 && Number(config.intervalMinutes) <= 240 ? Number(config.intervalMinutes) : 30
  readonly property var excludedThemes: Array.isArray(config.excludedThemes) ? config.excludedThemes : []
  readonly property bool busy: switchProcess.running
  readonly property bool refreshing: catalogProcess.running

  function readConfig(raw) {
    try {
      var document = JSON.parse(raw)
      var layout = (document.bar || {}).layout || {}
      var entry = null
      for (var s of ["left", "center", "right"]) {
        for (var e of (layout[s] || [])) {
          if (e.id === pluginId) { entry = e; root.section = s }
        }
      }
      if (!entry) for (var p of (document.plugins || [])) if (p.id === pluginId) entry = p
      var next = entry || {}
      if (loaded && (next.enabled !== config.enabled || next.intervalMinutes !== config.intervalMinutes)) scheduleStartEpoch = Date.now()
      config = next
      loaded = true
      arm()
    } catch (error) { lastError = "Cannot read shell settings: " + error; loaded = false; schedule.stop() }
  }
  function save(patch) {
    if (!shell || !loaded) return false
    // Omarchy replaces the entry: callers must pass the full merged settings.
    var next = Object.assign({}, config, patch)
    if (JSON.stringify(next) === JSON.stringify(config)) return true
    if (!shell.updateEntryInline(pluginId, next)) { lastError = "Could not save plugin settings"; return false }
    if (next.enabled !== config.enabled || next.intervalMinutes !== config.intervalMinutes) scheduleStartEpoch = Date.now()
    config = next
    arm()
    return true
  }
  function setEnabled(value) { save({enabled: value}) }
  function setExcluded(slug, excluded) {
    var next = excludedThemes.filter(function(t) { return t !== slug })
    if (excluded) next.push(slug)
    save({excludedThemes: next})
  }
  function moveTo(value) {
    if (["left", "center", "right"].indexOf(value) < 0 || moveProcess.running) return
    moveProcess.command = ["omarchy", "bar", "move", pluginId, "--section", value]
    moveProcess.running = true
  }
  function refresh() { if (!catalogProcess.running) catalogProcess.running = true }
  function arm() {
    schedule.stop()
    if (!loaded || !autoEnabled || busy) return
    var last = Math.max(scheduleStartEpoch, Number(config.lastAttemptEpoch) || 0)
    schedule.interval = Math.max(1000, Math.min(intervalMinutes * 60000, last + intervalMinutes * 60000 - Date.now()))
    schedule.start()
  }
  function switchNow(automatic) {
    if (busy || !loaded) return
    schedule.stop()
    lastError = ""
    message = "Choosing a theme…"
    switchProcess.command = ["python3", helper, automatic === true ? "automatic" : "switch"]
    switchProcess.running = true
  }
  function status() {
    return JSON.stringify({enabled: autoEnabled, pool: pool, intervalMinutes: intervalMinutes,
      excludedThemes: excludedThemes, section: section, current: currentTheme,
      themes: themes.length, busy: busy, timerRunning: schedule.running,
      message: message, error: lastError})
  }
  FileView {
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: root.readConfig(text())
    onFileChanged: reload()
    onLoadFailed: { root.loaded = false; schedule.stop(); root.lastError = "Cannot read shell.json" }
  }
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var next = text().trim()
      if (next !== root.currentTheme) {
        root.currentTheme = next
        root.scheduleStartEpoch = Date.now()
        root.arm()
      }
    }
    onFileChanged: reload()
  }
  Timer { id: schedule; repeat: false; onTriggered: root.switchNow(true) }
  Process {
    id: catalogProcess
    command: ["python3", root.helper, "catalog"]
    stdout: StdioCollector { id: catalogOutput; waitForEnd: true }
    onExited: function(code) {
      try {
        var result = JSON.parse(catalogOutput.text)
        if (code !== 0) throw new Error(result.error || "Discovery failed")
        root.themes = result.themes
        root.currentTheme = result.current
      } catch (error) { root.lastError = String(error) }
    }
  }
  Process {
    id: switchProcess
    stdout: StdioCollector { id: switchOutput; waitForEnd: true }
    stderr: StdioCollector { id: switchErrors; waitForEnd: true }
    onExited: function(code) {
      try {
        var result = JSON.parse(switchOutput.text)
        if (code !== 0) throw new Error(result.error || switchErrors.text || "Theme switch failed")
        root.message = result.message
      } catch (error) { root.lastError = String(error) }
      root.scheduleStartEpoch = Date.now()
      root.save({lastAttemptEpoch: root.scheduleStartEpoch})
      root.refresh()
      // Process.running becomes false after exited is delivered.
      Qt.callLater(root.arm)
    }
  }
  Process {
    id: moveProcess
    stderr: StdioCollector { id: moveErrors; waitForEnd: true }
    onExited: function(code) { if (code !== 0) root.lastError = moveErrors.text || "Could not move bar item" }
  }
  IpcHandler {
    target: "z.theme-roulette"
    function status(): string { return root.status() }
    function switchNow(): void { root.switchNow(false) }
    function enable(): void { root.setEnabled(true) }
    function disable(): void { root.setEnabled(false) }
    function refresh(): void { root.refresh() }
  }
  Component.onCompleted: refresh()
}
