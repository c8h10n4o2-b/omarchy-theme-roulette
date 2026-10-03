import QtQuick
import QtQuick.Controls as QQC
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "z.theme-roulette"
  manageIpc: false
  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function open() { if (service) service.refresh(); controller.show() }
  function close() { controller.hide() }
  function toggle() { opened ? close() : open() }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(650))

    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }
        ColumnLayout {
          id: content
          width: parent.width
          spacing: Style.space(12)
          PanelHero {
            Layout.fillWidth: true
            title: "Theme Roulette"
            meta: root.service ? "Current: " + root.service.currentTheme.replace(/-/g, " ") : "Loading…"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
          Toggle {
            Layout.fillWidth: true
            label: "Automatic switching"
            description: "Choose a different theme each interval."
            checked: root.service ? root.service.autoEnabled : false
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: root.service !== null
            onClicked: root.service.setEnabled(!root.service.autoEnabled)
          }
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)
            Dropdown {
              Layout.fillWidth: true
              label: "Theme pool"
              options: ["Dark", "Light", "Any"]
              value: root.service ? root.service.pool : "Any"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(value) { if (root.service) root.service.save({pool: value}) }
            }
            Dropdown {
              Layout.fillWidth: true
              label: "Interval"
              options: [{value:"5",label:"5 minutes"}, {value:"15",label:"15 minutes"},
                {value:"30",label:"30 minutes"}, {value:"60",label:"1 hour"},
                {value:"120",label:"2 hours"}, {value:"240",label:"4 hours"}]
              value: root.service ? String(root.service.intervalMinutes) : "30"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onChanged: function(value) { if (root.service) root.service.save({intervalMinutes: Number(value)}) }
            }
          }
          Dropdown {
            Layout.fillWidth: true
            label: "Bar placement"
            options: [{value:"left",label:"Left"}, {value:"center",label:"Centre"}, {value:"right",label:"Right"}]
            value: root.service ? root.service.section : "right"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function(value) { if (root.service) { root.close(); root.service.moveTo(value) } }
          }
          Button {
            Layout.fillWidth: true
            text: root.service && root.service.busy ? "Switching…" : "Switch Theme Now"
            iconText: "󰑐"
            bordered: true
            focusable: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: root.service && !root.service.busy
            onClicked: root.service.switchNow(false)
          }
          Text {
            Layout.fillWidth: true
            text: root.service ? root.service.lastError || root.service.message : ""
            visible: text !== ""
            textFormat: Text.PlainText
            color: root.service && root.service.lastError ? Color.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
          Text {
            Layout.fillWidth: true
            text: "Theme changes also change the wallpaper. Auto Wallpaper continues with the new theme’s wallpapers."
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
          PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }
          PanelSectionHeader {
            Layout.fillWidth: true
            text: "EXCLUDED THEMES"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
          Text {
            Layout.fillWidth: true
            text: "Turn on a theme below to exclude it from random selection."
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
          Repeater {
            model: root.service ? root.service.themes : []
            delegate: Toggle {
              required property var modelData
              Layout.fillWidth: true
              label: modelData.name
              description: modelData.mode + (root.service && modelData.slug === root.service.currentTheme ? " · current" : "")
              checked: root.service && root.service.excludedThemes.indexOf(modelData.slug) >= 0
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: if (root.service) root.service.setExcluded(modelData.slug, !checked)
            }
          }
          Button {
            Layout.fillWidth: true
            text: root.service && root.service.refreshing ? "Refreshing…" : "Refresh Installed Themes"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: root.service && !root.service.refreshing
            onClicked: root.service.refresh()
          }
        }
      }
    }
  }
}
