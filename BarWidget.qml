import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "alex.ci"

  readonly property var engine: bar && bar.shell && typeof bar.shell.serviceFor === "function"
    ? bar.shell.serviceFor("alex.ci")
    : null
  readonly property int failing: engine ? engine.failing : 0
  readonly property int running: engine ? engine.running : 0
  readonly property bool live: running > 0
  readonly property color failColor: bar ? bar.urgent : Color.urgent

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.engine = root.engine
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onEngineChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // The bar face is MonoLisa, which has no octocat. Pin the nerd font so
    // U+F09B draws the GitHub mark instead of a missing glyph.
    fontFamily: "JetBrainsMono Nerd Font"
    text: "\u{f09b}"
    tooltipText: root.failing > 0
      ? (root.failing + (root.failing === 1 ? " workflow falhou" : " workflows falharam"))
      : (root.live ? "Workflow rodando" : "Actions do devaction-labs")
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }

  // Sits in the padding around the glyph, so the octocat stays put.
  Item {
    visible: root.failing > 0
    width: 7
    height: 7
    anchors.right: button.right
    anchors.top: button.top
    anchors.rightMargin: 3
    anchors.topMargin: 5

    Rectangle {
      anchors.centerIn: parent
      width: 7
      height: 7
      radius: 3.5
      color: Color.bar.background
    }

    Rectangle {
      anchors.centerIn: parent
      width: 5
      height: 5
      radius: 2.5
      color: root.failColor
    }
  }

  Item {
    id: runTrack
    visible: root.live
    anchors.left: button.left
    anchors.right: button.right
    anchors.bottom: button.bottom
    anchors.leftMargin: 5
    anchors.rightMargin: 5
    anchors.bottomMargin: 4
    height: 2

    Rectangle {
      anchors.fill: parent
      radius: 1
      color: Color.accent
      opacity: 0.28
    }

    Rectangle {
      width: Math.max(8, parent.width * 0.46)
      height: parent.height
      radius: 1
      color: Color.accent
      x: phase * Math.max(0, parent.width - width)

      property real phase: 0
      SequentialAnimation on phase {
        running: root.live
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 1; duration: 900; easing.type: Easing.InOutCubic }
        NumberAnimation { from: 1; to: 0; duration: 900; easing.type: Easing.InOutCubic }
      }
    }
  }
}
