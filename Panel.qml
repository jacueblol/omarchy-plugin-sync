import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Sync panel: owns the sync state, runs the plugin-sync helper, and keeps
// the bar icon (BarWidget.qml) informed through syncState/busy/headline.
//
// Three views share the panel: the sync overview, a confirmation that lists
// exactly what a push or pull will change, and this machine's settings. The
// helper reads the same settings from shell.json, so the panel only writes
// them and never passes them along.
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

  // ---- Settings (defaults match manifest.json and the helper).
  readonly property string mode: String(setting("mode", "Push automatically"))
  readonly property int intervalMinutes: Math.max(5, Number(setting("intervalMinutes", 15)) || 15)
  readonly property var localOnly: String(setting("localOnly", "")).split(/[\s,]+/).filter(function(s) { return s !== "" })

  property var status: ({ configured: false, state: "loading", plugins: [], unsyncable: [] })
  property string busy: ""          // "push" | "pull" | "auto" while running
  property string message: ""
  property string view: "main"      // "main" | "confirm" | "settings"
  property string confirmAction: "" // "push" | "pull"

  readonly property string syncState: status.state || "loading"
  readonly property bool needsAttention: ["local", "remote", "both", "new", "error"].indexOf(syncState) !== -1
  readonly property var stateText: ({
    loading: "Checking…",
    unconfigured: "Not set up yet",
    none: "In sync",
    local: "This machine has changes to push",
    remote: "Another machine has changes to pull",
    both: "Both machines changed. Pick which one wins",
    new: "First sync here. Pull to adopt the shared setup",
    error: status.error || "Sync error"
  })
  readonly property string headline: busy ? "Syncing…" : stateText[syncState] || syncState
  readonly property var pluginStatusText: ({
    synced: "synced",
    local: "only here",
    remote: "to install",
    machine: "this machine only",
    off: "not synced"
  })
  readonly property var plan: status.pullPlan || ({ install: [], remove: [], bar: false, pluginStates: false, other: false })
  readonly property var planLines: {
    var lines = []
    if (plan.install.length) lines.push("Install " + plan.install.join(", "))
    if (plan.remove.length) lines.push("Remove " + plan.remove.join(", "))
    if (plan.bar) lines.push("Replace the bar layout and widget settings")
    if (plan.pluginStates) lines.push("Update which plugins are enabled")
    if (plan.other) lines.push("Replace other shell settings (idle, lock, …)")
    return lines
  }
  readonly property string syncedSummary: {
    var s = status.settings || {}
    var parts = []
    if (s.plugins !== false) parts.push("plugins")
    if (s.bar !== false) parts.push("bar")
    if (s.other === true) parts.push("shell settings")
    return (parts.length ? "Syncs " + parts.join(", ") : "Syncs nothing") + " · " + mode
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function") return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function refresh(offline) {
    if (statusProc.running || busy) return
    statusProc.command = [helper].concat(offline ? ["status", "--offline"] : ["status"])
    statusProc.running = true
  }

  function runAction(action) {
    if (busy) return
    busy = action
    message = ""
    view = "main"
    actionProc.command = [helper, action]
    actionProc.running = true
  }

  // Pushing over another machine's changes, or pulling over this machine's
  // config, is confirmed first with the exact list of what changes.
  function request(action) {
    var overwritesOther = action === "push" && ["remote", "both", "new"].indexOf(syncState) !== -1
    var changesHere = action === "pull" && planLines.length > 0
    if (overwritesOther || changesHere) {
      confirmAction = action
      view = "confirm"
    } else {
      runAction(action)
    }
  }

  function saveSetting(key, value) {
    var entry = { id: moduleName }
    for (var k in settings) if (k !== "id") entry[k] = settings[k]
    entry[key] = value
    settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, entry)
    settingsSaved.restart()
  }

  function toggleLocalOnly(id) {
    var ids = localOnly.slice()
    var i = ids.indexOf(id)
    if (i === -1) ids.push(id)
    else ids.splice(i, 1)
    saveSetting("localOnly", ids.join(","))
  }

  // init may need to create a repo or log in, so it gets a terminal.
  function setUp() {
    root.close()
    Util.execArgv(["omarchy-launch-floating-terminal-with-presentation", Util.shellQuote(helper) + " init"])
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

  onOpenedChanged: {
    if (opened) refresh(false)
    else view = "main"
  }
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
        // Plugins installed or removed through Omaplug (or a bar change)
        // show up here as local changes. Pushing only touches the repo.
        if (root.mode !== "Manual" && root.syncState === "local") root.runAction("push")
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

  // shell.json is written by the shell; read the new settings back after it.
  Timer {
    id: settingsSaved
    interval: 600
    onTriggered: root.refresh(true)
  }

  // Cheap local check, so Omaplug installs and bar edits are noticed quickly.
  Timer {
    interval: 60 * 1000
    running: root.status.configured === true
    repeat: true
    onTriggered: root.refresh(true)
  }

  // Full check against the remote. The helper decides from the mode setting
  // whether to push, pull, or only report.
  Timer {
    interval: root.intervalMinutes * 60 * 1000
    running: root.status.configured === true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.runAction("auto")
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.view !== "main" ? root.view = "main" : root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (root.view !== "main") return
        if (t === "p") root.request("push")
        else if (t === "l") root.request("pull")
        else if (t === "m") root.openOmaplug()
        else if (t === "s") root.view = "settings"
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Header ----------
        Item {
          width: parent.width
          implicitHeight: header.implicitHeight

          Column {
            id: header
            anchors.left: parent.left
            anchors.right: settingsButton.left
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(4)

            Text {
              text: root.view === "settings" ? "Plugin Sync · Settings" : "Plugin Sync"
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
              visible: root.message !== "" && root.message.toLowerCase() !== root.headline.toLowerCase()
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

          PanelActionButton {
            id: settingsButton
            anchors.right: parent.right
            anchors.top: parent.top
            iconText: root.view === "settings" ? "󰅖" : "󰒓"
            tooltipText: root.view === "settings" ? "Back" : "Settings (s)"
            foreground: root.foreground
            onClicked: root.view = root.view === "settings" ? "main" : "settings"
          }
        }

        // ================= Main view =================
        Column {
          visible: root.view === "main"
          width: parent.width
          spacing: Style.space(12)

          Row {
            spacing: Style.space(8)

            Button {
              visible: root.status.configured !== true
              iconText: "󰊢"
              iconSize: Style.font.title
              text: "Set up sync repo"
              tooltipText: "Create or connect the git repo that holds your sync"
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
              tooltipText: "Share this machine's plugins and settings (p)"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              active: root.syncState === "local"
              onClicked: root.request("push")
            }

            Button {
              visible: root.status.configured === true
              enabled: root.busy === ""
              iconText: "󰇚"
              iconSize: Style.font.title
              text: "Pull"
              tooltipText: "Apply changes from your other machines (l)"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              active: root.syncState === "remote" || root.syncState === "new"
              onClicked: root.request("pull")
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

          Text {
            text: root.syncedSummary
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
                color: modelData.status === "local" || modelData.status === "remote" ? Color.accent : root.foreground
                opacity: modelData.status === "local" || modelData.status === "remote" ? 1 : 0.45
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

          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.PlainText
            text: "p push  ·  l pull  ·  m Omaplug  ·  s settings"
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        // ================= Confirm view =================
        Column {
          visible: root.view === "confirm"
          width: parent.width
          spacing: Style.space(10)

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.confirmAction === "pull"
              ? "Pulling will change this machine:"
              : "Pushing will replace what your other machines shared, for the parts this machine syncs."
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Repeater {
            model: root.confirmAction === "pull" ? root.planLines : []

            Text {
              required property string modelData
              width: parent.width
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: "•  " + modelData
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: root.confirmAction === "pull"
              ? (root.syncState === "both" ? "This machine's unsynced changes to those parts will be lost. " : "")
                + "shell.json is backed up first. Machine-specific plugins are never touched."
              : "Their changes stay in the repo's history."
            color: root.foreground
            opacity: 0.6
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            spacing: Style.space(8)

            Button {
              iconText: root.confirmAction === "pull" ? "󰇚" : "󰕒"
              iconSize: Style.font.title
              text: root.confirmAction === "pull" ? "Pull now" : "Push now"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              active: true
              onClicked: root.runAction(root.confirmAction)
            }

            Button {
              text: "Cancel"
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.view = "main"
            }
          }
        }

        // ================= Settings view =================
        Flickable {
          visible: root.view === "settings"
          width: parent.width
          height: Math.min(settingsColumn.implicitHeight, Style.space(560))
          contentHeight: settingsColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

        Column {
          id: settingsColumn
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader { text: "What this machine syncs"; foreground: root.foreground; fontFamily: root.fontFamily }

          Repeater {
            model: [
              { key: "syncPlugins", label: "Installed plugins", hint: "Install plugins added elsewhere; sync which are enabled", fallback: true },
              { key: "removePlugins", label: "Remove plugins removed elsewhere", hint: "Never removes plugins with local changes", fallback: true },
              { key: "syncBar", label: "Bar layout", hint: "Widget order, bar position, widget settings", fallback: true },
              { key: "syncShellSettings", label: "Other shell settings", hint: "Idle, lock, and the rest of shell.json", fallback: false },
              { key: "notify", label: "Notify after automatic pulls", hint: "", fallback: true }
            ]

            Item {
              id: toggleRow
              required property var modelData
              readonly property bool checked: root.setting(modelData.key, modelData.fallback) === true
              width: parent.width
              implicitHeight: Math.max(labels.implicitHeight, toggle.implicitHeight)

              Column {
                id: labels
                anchors.left: parent.left
                anchors.right: toggle.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  width: parent.width
                  text: toggleRow.modelData.label
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Text {
                  visible: toggleRow.modelData.hint !== ""
                  width: parent.width
                  text: toggleRow.modelData.hint
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              ToggleSwitch {
                id: toggle
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: toggleRow.checked
                foreground: root.foreground
                onToggled: root.saveSetting(toggleRow.modelData.key, !toggleRow.checked)
              }
            }
          }

          PanelSectionHeader { text: "When to sync"; foreground: root.foreground; fontFamily: root.fontFamily }

          Dropdown {
            width: parent.width
            label: "Automatic sync"
            value: root.mode
            options: ["Manual", "Push automatically", "Push and pull automatically"]
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function(v) { root.saveSetting("mode", v) }
          }

          Dropdown {
            width: parent.width
            label: "When both machines changed"
            value: String(root.setting("onConflict", "Ask"))
            options: ["Ask", "Keep this machine", "Use the repo"]
            foreground: root.foreground
            fontFamily: root.fontFamily
            onChanged: function(v) { root.saveSetting("onConflict", v) }
          }

          NumberField {
            width: parent.width
            label: "Check other machines every (minutes)"
            value: root.intervalMinutes
            from: 5
            to: 240
            stepSize: 5
            foreground: root.foreground
            fontFamily: root.fontFamily
            onModified: function(v) { root.saveSetting("intervalMinutes", v) }
          }

          PanelSectionHeader { text: "Machine-specific plugins"; foreground: root.foreground; fontFamily: root.fontFamily }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "Switched on plugins stay on this machine only: never installed, removed, or moved by a sync."
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            model: (root.status.plugins || []).filter(function(p) { return p.id !== root.moduleName && p.status !== "remote" })

            Item {
              id: localRow
              required property var modelData
              width: parent.width
              implicitHeight: localToggle.implicitHeight

              Text {
                anchors.left: parent.left
                anchors.right: localToggle.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: localRow.modelData.id
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              ToggleSwitch {
                id: localToggle
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: root.localOnly.indexOf(localRow.modelData.id) !== -1
                foreground: root.foreground
                onToggled: root.toggleLocalOnly(localRow.modelData.id)
              }
            }
          }

          PanelSectionHeader { text: "Sync repo"; foreground: root.foreground; fontFamily: root.fontFamily }

          TextField {
            width: parent.width
            text: String(root.setting("repo", ""))
            placeholderText: "owner/name or git URL"
            foreground: root.foreground
            accent: Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            onEditingFinished: if (text.trim() !== String(root.setting("repo", ""))) root.saveSetting("repo", text.trim())
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: "These settings apply to this machine only and are never synced."
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        }
      }
    }
  }
}
