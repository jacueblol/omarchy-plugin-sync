import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Sync icon for the bar, and the host for the sync panel. The panel owns the
// sync state and the helper processes; this widget shows that state on the
// icon (spinning while busy, a dot when something needs a push or pull).
BarWidget {
  id: root
  moduleName: "io.github.jacueblol.plugin-sync"

  readonly property var panelItem: panelLoader.item
  readonly property bool busy: panelItem ? panelItem.busy !== "" : false
  readonly property string syncState: panelItem ? panelItem.syncState : "loading"
  readonly property bool needsAttention: panelItem ? panelItem.needsAttention === true : false

  // ---- Panel lifecycle. Bar.findPanelWidget requires open/close/opened on
  //      the bar-widget root for shell summon/hide/toggle routing.
  readonly property bool opened: panelItem ? panelItem.opened === true : false
  readonly property bool popoutSwitchClosing: panelItem ? panelItem.popoutSwitchClosing === true : false

  function open() { if (panelItem) panelItem.open() }
  function close() { if (panelItem) panelItem.close() }
  function toggle() { if (panelItem) panelItem.toggle() }
  function closeForPopoutSwitch() { if (panelItem) panelItem.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.jacueblol.plugin-sync"

    function refresh(): void { if (root.panelItem) root.panelItem.refresh(false) }
    function sync(): void { if (root.panelItem) root.panelItem.runAction("auto") }
    function push(): void { if (root.panelItem) root.panelItem.runAction("push") }
    function pull(): void { if (root.panelItem) root.panelItem.runAction("pull") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰓦"
    tooltipText: "Plugin Sync · " + (root.panelItem ? root.panelItem.headline : "Checking…")
    onPressed: function(b) {
      if (b === Qt.LeftButton) root.toggle()
    }

    RotationAnimator on rotation {
      running: root.busy
      from: 0; to: 360; duration: 1200
      loops: Animation.Infinite
      onRunningChanged: if (!running) button.rotation = 0
    }
  }

  Rectangle {
    visible: root.needsAttention && !root.busy
    anchors.top: button.top
    anchors.right: button.right
    anchors.margins: Style.space(3)
    width: Style.space(7)
    height: width
    radius: width / 2
    color: root.syncState === "both" || root.syncState === "error"
      ? (root.bar ? root.bar.urgent : Color.urgent)
      : Color.accent
  }
}
