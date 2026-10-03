import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "z.theme-roulette"
  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property bool opened: popup.opened
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  function open() { popup.open() }
  function close() { popup.close() }
  function toggle() { popup.toggle() }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.vertical ? "󰏘" : "󰏘 " + (root.service ? root.service.pool : "Any")
    dimmed: !root.service || !root.service.autoEnabled
    active: root.service && root.service.lastError !== ""
    tooltipText: "Theme Roulette · " + (root.service && root.service.autoEnabled ? "Every " + root.service.intervalMinutes + " min" : "Off")
      + (root.service ? "\n" + root.service.currentTheme : "")
    onPressed: function(code) {
      if (code === Qt.MiddleButton && root.service) root.service.switchNow(false)
      else root.toggle()
    }
  }
  ControlsPanel {
    id: popup
    bar: root.bar
    anchorItem: button
    hostWidget: root
    service: root.service
  }
}
