import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Sync panel: owns the sync state, runs the plugin-sync helper, and keeps
// the bar icon (BarWidget.qml) informed through syncState/busy/headline.
Panel {
  id: root
  moduleName: "io.github.jacueblol.plugin-sync"
  manageIpc: false

  property var anchorItem: null
  // The bar identifies a panel by the widget in its slot, not this nested
  // panel, so popout and Tab switching go through hostWidget.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color urgentColor: bar ? bar.urgent : Color.urgent

  readonly property string helper: String(Qt.resolvedUrl("plugin-sync")).replace(/^file:\/\//, "")
  readonly property string repo: String(setting("repo", ""))
  readonly property bool autoSync: setting("autoSync", true) === true
  readonly property int intervalMinutes: Math.max(5, Number(setting("intervalMinutes", 15)) || 15)
  readonly property var helperArgv: repo ? ["env", "PLUGIN_SYNC_REPO=" + repo, helper] : [helper]

  property var status: ({ configured: false, state: "loading", plugins: [], unsyncable: [] })
  property string busy: ""          // "push" | "pull" | "auto" while running
  property string message: ""

  readonly property string syncState: status.state || "loading"
  readonly property bool needsAttention: ["local", "remote", "both", "new", "error"].indexOf(syncState) !== -1
  readonly property var stateText: ({
    loading: "Checking…",
    unconfigured: "Not set up yet",
    none: "In sync",
    local: "This machine has changes to push",
    remote: "The other machine has changes to pull",
    both: "Both machines changed. Pick which one wins",
    new: "First sync here. Pull to adopt the shared setup",
    error: status.error || "Sync error"
  })
  readonly property string headline: busy ? "Syncing…" : stateText[syncState] || syncState
  readonly property var pluginStatusText: ({
    synced: "synced",
    local: "only here",
    remote: "only in sync"
  })

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function refresh(offline) {
    if (statusProc.running || busy) return
    statusProc.command = helperArgv.concat(offline ? ["status", "--offline"] : ["status"])
    statusProc.running = true
  }

  function runAction(action) {
    if (busy) return
    busy = action
    message = ""
    actionProc.command = helperArgv.concat([action])
    actionProc.running = true
  }

  // init may need to create a repo or log in, so it gets a terminal.
  function setUp() {
    root.close()
    Util.execArgv(["omarchy-launch-floating-terminal-with-presentation",
      helperArgv.map(Util.shellQuote).join(" ") + " init"])
  }

  function openOmaplug() {
    root.close()
    Util.execArgv(["omarchy-shell", "shell", "toggle", "omaplug"])
  }

  function relativeTime(iso) {
    if (!iso) return ""
    var mins = Math.round((Date.now() - new Date(iso).getTime()) / 60000)
    if (mins < 1) return "just now"
    if (mins < 60) return mins + " min ago"
    if (mins < 1440) return Math.round(mins / 60) + " h ago"
    return Math.round(mins / 1440) + " d ago"
  }

  onOpenedChanged: if (opened) refresh(false)
  onRepoChanged: refresh(false)
  Component.onCompleted: refresh(true)

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.status = JSON.parse(text)
        } catch (e) {
          root.status = { configured: true, state: "error", error: "Could not read sync status", plugins: [], unsyncable: [] }
        }
        // Plugins installed or removed through Omaplug (or a layout change)
        // show up here as local changes; push them right away.
        if (root.autoSync && root.syncState === "local") root.runAction("push")
      }
    }
  }

  Process {
    id: actionProc
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(exitCode) {
      var out = (actionOut.text + actionErr.text).trim().split("\n")
      root.message = out[out.length - 1] || (exitCode === 0 ? "Done" : "Failed")
      root.busy = ""
      root.refresh(true)
    }
  }

  // Cheap local check, so Omaplug installs and bar edits are noticed quickly.
  Timer {
    interval: 60 * 1000
    running: root.status.configured === true
    repeat: true
    onTriggered: root.refresh(true)
  }

  // Full check against the remote.
  Timer {
    interval: root.intervalMinutes * 60 * 1000
    running: root.status.configured === true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.autoSync ? root.runAction("auto") : root.refresh(false)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "p") root.runAction("push")
        else if (t === "l") root.runAction("pull")
        else if (t === "m") root.openOmaplug()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Header ----------
        Column {
          width: parent.width
          spacing: Style.space(4)

          Text {
            text: "Plugin Sync"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.headline.toUpperCase()
            color: root.syncState === "both" || root.syncState === "error" ? root.urgentColor : Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
            wrapMode: Text.WordWrap
          }

          Text {
            visible: root.status.configured === true
            width: parent.width
            textFormat: Text.PlainText
            text: String(root.status.repo || "").replace(/^https:\/\/github\.com\//, "").replace(/\.git$/, "")
              + (root.status.lastHost ? " · last sync from " + root.status.lastHost + " " + root.relativeTime(root.status.lastTime) : "")
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          Text {
            visible: root.message !== ""
            width: parent.width
            textFormat: Text.PlainText
            text: root.message
            color: root.foreground
            opacity: 0.8
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }

        // ---------- Actions ----------
        Row {
          spacing: Style.space(8)

          Button {
            visible: root.status.configured !== true
            iconText: "󰊢"
            iconSize: Style.font.title
            text: "Set up sync repo"
            tooltipText: "Create or connect a private GitHub repo"
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.setUp()
          }

          Button {
            visible: root.status.configured === true
            enabled: root.busy === ""
            iconText: "󰕒"
            iconSize: Style.font.title
            text: "Push"
            tooltipText: "Make the sync repo match this machine (p)"
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            active: root.syncState === "local"
            onClicked: root.runAction("push")
          }

          Button {
            visible: root.status.configured === true
            enabled: root.busy === ""
            iconText: "󰇚"
            iconSize: Style.font.title
            text: "Pull"
            tooltipText: "Make this machine match the sync repo (l)"
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            active: root.syncState === "remote" || root.syncState === "new"
            onClicked: root.runAction("pull")
          }

          Button {
            iconText: "󱓖"
            iconSize: Style.font.title
            text: "Omaplug"
            tooltipText: "Install, update, and arrange plugins in Omaplug (m)"
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.openOmaplug()
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ---------- Plugins ----------
        Column {
          width: parent.width
          spacing: Style.space(6)

          Text {
            text: (root.status.plugins || []).length + " plugins"
              + (root.status.layoutChanged ? " · bar layout differs" : "")
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
            font.letterSpacing: 1.2
          }

          Repeater {
            model: root.status.plugins || []

            Item {
              required property var modelData
              width: parent.width
              implicitHeight: Math.max(name.implicitHeight, pill.implicitHeight)

              Text {
                id: name
                anchors.left: parent.left
                anchors.right: pill.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: modelData.id
                color: root.foreground
                opacity: modelData.status === "synced" ? 0.85 : 1
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Text {
                id: pill
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.pluginStatusText[modelData.status] || modelData.status
                color: modelData.status === "synced" ? root.foreground : Color.accent
                opacity: modelData.status === "synced" ? 0.45 : 1
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          Text {
            visible: (root.status.unsyncable || []).length > 0
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: "Not synced (no git origin): " + (root.status.unsyncable || []).join(", ")
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: "p push  ·  l pull  ·  m open Omaplug" + (root.autoSync ? "  ·  auto-sync on" : "")
          color: root.foreground
          opacity: 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
