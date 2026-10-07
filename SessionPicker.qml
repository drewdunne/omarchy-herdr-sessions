import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string filterText: ""
  property int selectedIndex: 0
  property bool cursorActive: false
  property var sessions: []
  // Enabled SSH machines saved with `herdr machine add`, and the latest
  // `herdr machine status` result for each, keyed by profile id.
  property var machines: []
  property var machineStatus: ({})

  property bool creatingNew: false
  property string deleteTargetSession: ""

  readonly property string home: Quickshell.env("HOME")

  // Shares the [menu] surface tokens, like the built-in clipboard picker,
  // so themes that style the menu also style this picker.
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int footerHeight: Style.font.caption + Style.spacing.sm * 2
  property int rowHeight: Math.max(Style.space(50), Style.font.title + Style.font.caption + Style.spacing.rowPaddingX * 2)
  property int rowPadding: Style.spacing.rowPaddingX
  property int markerWidth: Style.space(16)
  property int cardWidth: Math.min(Style.space(600), panel.width - Style.gapsOut * 2)
  property int listRows: Math.max(3, displayModel.count)
  property int contentHeight: root.headerHeight + Style.normalBorderWidth + root.footerHeight + root.contentSpacing * 3
    + root.listRows * root.rowHeight + (root.listRows - 1) * Style.space(4)
  property int cardHeight: Math.min(card.contentTopInset + card.contentBottomInset + root.contentHeight,
    Style.space(460), panel.height - Style.gapsOut * 2)

  function open(payloadJson) {
    root.opened = true
    root.filterText = ""
    root.selectedIndex = 0
    root.cursorActive = true
    root.creatingNew = false
    root.deleteTargetSession = ""
    root.disarmPointer()
    root.refreshSessions()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.creatingNew = false
    root.deleteTargetSession = ""
  }

  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") {
      root.shell.hide((root.manifest && root.manifest.id) || "io.github.houtvongsak.herdr-sessions")
    }
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function refreshSessions() {
    if (!listProc.running) listProc.running = true
    if (!machineListProc.running) machineListProc.running = true
  }

  function parseSessions(raw) {
    try {
      var data = JSON.parse(raw)
      root.sessions = data.sessions || []
    } catch (e) {
      console.warn("herdr session parser error:", e, raw)
      root.sessions = []
    }
    root.rebuildDisplay()
  }

  // Herdr before 0.9 has no `machine` command and prints nothing on stdout,
  // which leaves the picker showing local sessions only.
  function parseMachines(raw) {
    var rows = []
    if (raw.trim()) {
      try {
        rows = JSON.parse(raw) || []
      } catch (e) {
        console.warn("herdr machine parser error:", e, raw)
      }
    }
    root.machines = rows.filter(function(m) { return m.enabled === true })
    root.rebuildDisplay()
    // The status check is a fresh SSH round trip per machine, so the list is
    // drawn first and each row's status fills in when the check returns.
    if (root.machines.length > 0 && !machineStatusProc.running) machineStatusProc.running = true
  }

  function parseMachineStatus(raw) {
    var next = {}
    try {
      var rows = JSON.parse(raw) || []
      for (var i = 0; i < rows.length; i++) next[rows[i].id] = rows[i].status
    } catch (e) {
      console.warn("herdr machine status parser error:", e, raw)
      for (var j = 0; j < root.machines.length; j++) next[root.machines[j].id] = "unknown"
    }
    root.machineStatus = next
    root.rebuildDisplay()
  }

  function machineStatusText(id) {
    var status = root.machineStatus[id]
    if (status === undefined) return "checking…"
    if (status === "error") return "unreachable"
    return status
  }

  function machineMatches(m, search) {
    return [m.label, m.target, m.session].some(function(value) {
      return String(value || "").toLowerCase().indexOf(search) !== -1
    })
  }

  function prettyPath(path) {
    if (root.home && path.indexOf(root.home) === 0) return "~" + path.slice(root.home.length)
    return path
  }

  function rebuildDisplay() {
    displayModel.clear()
    var search = root.filterText.trim().toLowerCase()

    for (var i = 0; i < root.sessions.length; i++) {
      var s = root.sessions[i]
      if (search && s.name.toLowerCase().indexOf(search) === -1) continue
      displayModel.append({
        isNewButton: false,
        isMachine: false,
        name: s.name,
        running: s.running === true,
        isDefault: s.default === true,
        sessionDir: root.prettyPath(s.session_dir || ""),
        target: "",
        remoteSession: "",
        status: ""
      })
    }

    // A saved machine targets one session on its host, so it is one row.
    for (var j = 0; j < root.machines.length; j++) {
      var m = root.machines[j]
      if (search && !root.machineMatches(m, search)) continue
      var remoteSession = m.session || "default"
      displayModel.append({
        isNewButton: false,
        isMachine: true,
        name: m.label,
        running: root.machineStatus[m.id] === "reachable",
        isDefault: false,
        sessionDir: m.target + " · " + (remoteSession === "default" ? "default session" : "session " + remoteSession),
        target: m.target,
        remoteSession: remoteSession,
        status: root.machineStatusText(m.id)
      })
    }

    if (!search) {
      displayModel.append({ isNewButton: true, isMachine: false, name: "", running: false, isDefault: false,
        sessionDir: "", target: "", remoteSession: "", status: "" })
    }

    if (displayModel.count === 0) selectedIndex = 0
    else if (selectedIndex >= displayModel.count) selectedIndex = displayModel.count - 1
    else if (selectedIndex < 0) selectedIndex = 0

    Qt.callLater(function() {
      if (displayModel.count > 0) sessionList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function select(delta) {
    if (displayModel.count === 0) return
    root.disarmPointer()
    if (!cursorActive) {
      cursorActive = true
      selectedIndex = delta < 0 ? displayModel.count - 1 : 0
    } else {
      selectedIndex = (selectedIndex + delta + displayModel.count) % displayModel.count
    }
    sessionList.positionViewAtIndex(selectedIndex, ListView.Contain)
  }

  function selectedRow() {
    if (!root.cursorActive || root.selectedIndex < 0 || root.selectedIndex >= displayModel.count) return null
    return displayModel.get(root.selectedIndex)
  }

  function activate(row) {
    if (!row) return
    if (row.isNewButton) root.startCreateNew()
    else if (row.isMachine) root.launchMachine(row.target, row.remoteSession)
    else root.launchSession(row.name)
  }

  // Attach the way herdr's own docs give for a saved machine. Running it in a
  // terminal also lets SSH ask for a passphrase or a new host key when the
  // status check says "auth required".
  function launchMachine(target, remoteSession) {
    root.dismiss()
    var command = ["omarchy-launch-terminal", "herdr", "--remote", target]
    if (remoteSession && remoteSession !== "default") command.push("--session", remoteSession)
    Quickshell.execDetached(command)
  }

  function launchSession(name) {
    root.dismiss()
    if (name === "default") {
      Quickshell.execDetached(["omarchy-launch-terminal", "herdr"])
    } else {
      Quickshell.execDetached(["omarchy-launch-terminal", "herdr", "--session", name])
    }
  }

  function stopSession(row) {
    // Herdr does not forward session management to saved machines.
    if (!row || row.isNewButton || row.isMachine || !row.running) return
    if (row.isDefault) {
      Quickshell.execDetached(["herdr", "server", "stop"])
    } else {
      Quickshell.execDetached(["herdr", "session", "stop", row.name])
    }
    refreshTimer.restart()
  }

  function requestDeleteSession(row) {
    if (!row || row.isNewButton || row.isMachine || row.running || row.isDefault) return
    confirmDialog.selectedIndex = 1
    root.deleteTargetSession = row.name
  }

  function cancelDelete() {
    root.deleteTargetSession = ""
    root.disarmPointer()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function executeDeleteSession() {
    var target = root.deleteTargetSession
    root.cancelDelete()
    if (!target) return
    Quickshell.execDetached(["herdr", "session", "delete", target])
    refreshTimer.restart()
  }

  function startCreateNew() {
    root.creatingNew = true
    newSessionInput.text = ""
    Qt.callLater(function() { newSessionInput.forceActiveFocus() })
  }

  function cancelCreateNew() {
    root.creatingNew = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function submitNewSession() {
    var name = newSessionInput.text.trim()
    if (!name) return
    root.creatingNew = false
    root.launchSession(name)
  }

  function setFilter(next) {
    root.filterText = next
    root.selectedIndex = 0
    root.cursorActive = true
    root.disarmPointer()
    root.rebuildDisplay()
  }

  function disarmPointer() {
    pointerGate.reset()
  }

  function selectFromPointer(index, item, mouse) {
    if (!pointerGate.moved(item, mouse)) return
    root.cursorActive = true
    root.selectedIndex = index
  }

  ListModel { id: displayModel }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  Process {
    id: listProc
    command: ["herdr", "session", "list", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseSessions(text)
    }
  }

  Process {
    id: machineListProc
    command: ["herdr", "machine", "list", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseMachines(text)
    }
  }

  Process {
    id: machineStatusProc
    command: ["herdr", "machine", "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseMachineStatus(text)
    }
  }

  Timer {
    id: refreshTimer
    interval: 350
    repeat: false
    onTriggered: root.refreshSessions()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-herdr-sessions"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        z: root.deleteTargetSession !== "" ? 20 : 0
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (confirmDialog.opened) {
            if (confirmDialog.handleKey(event)) event.accepted = true
            return
          }

          if (event.key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.dismiss()
            event.accepted = true
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.select(-1)
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.select(1)
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activate(root.selectedRow())
            event.accepted = true
          } else if (event.key === Qt.Key_Delete || (event.key === Qt.Key_D && !event.modifiers && !root.filterText)) {
            root.requestDeleteSession(root.selectedRow())
            event.accepted = true
          } else if (event.key === Qt.Key_S && !event.modifiers && !root.filterText) {
            root.stopSession(root.selectedRow())
            event.accepted = true
          } else if (event.key === Qt.Key_N && !event.modifiers && !root.filterText) {
            root.startCreateNew()
            event.accepted = true
          } else if (event.key === Qt.Key_R && !event.modifiers && !root.filterText) {
            root.refreshSessions()
            event.accepted = true
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127) {
            root.setFilter(root.filterText + event.text)
            event.accepted = true
          }
        }

        ConfirmDialog {
          id: confirmDialog
          anchors.fill: parent
          z: 10
          opened: root.deleteTargetSession !== ""
          message: "Delete session “" + root.deleteTargetSession + "”?"
          confirmText: "Delete"
          background: root.background
          foreground: root.foreground
          scrim: root.scrim
          selectedBackground: root.selectedBackground
          selectedText: root.selectedText
          fontFamily: root.fontFamily
          cornerRadius: root.cornerRadius
          onCanceled: root.cancelDelete()
          onConfirmed: root.executeDeleteSession()
        }
      }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        // Header: live filter text on the left, session count on the right
        Item {
          id: header
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: root.headerHeight

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: countText.left
            anchors.rightMargin: root.contentSpacing
            anchors.verticalCenter: parent.verticalCenter
            text: root.creatingNew ? "New session" : (root.filterText || "Search sessions…")
            color: root.foreground
            opacity: root.filterText || root.creatingNew ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          Text {
            id: countText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.sessions.length + (root.sessions.length === 1 ? " session" : " sessions")
              + (root.machines.length === 0 ? ""
                : " · " + root.machines.length + (root.machines.length === 1 ? " machine" : " machines"))
            color: root.foreground
            opacity: 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Rectangle {
          id: headerRule
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: header.bottom
          anchors.topMargin: root.contentSpacing
          height: Style.normalBorderWidth
          color: Util.alpha(root.border, 0.28)
        }

        Item {
          id: content
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: headerRule.bottom
          anchors.topMargin: root.contentSpacing
          anchors.bottom: footer.top
          anchors.bottomMargin: root.contentSpacing

          ListView {
            id: sessionList
            anchors.fill: parent
            visible: !root.creatingNew
            model: displayModel
            clip: true
            spacing: Style.space(4)
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: row
              required property int index
              required property bool isNewButton
              required property bool isMachine
              required property string name
              required property bool running
              required property bool isDefault
              required property string sessionDir
              required property string target
              required property string remoteSession
              required property string status

              readonly property bool hasCursor: root.cursorActive && index === root.selectedIndex
              readonly property color textColor: hasCursor ? root.selectedText : root.foreground

              width: ListView.view.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: function(mouse) { root.selectFromPointer(row.index, row, mouse) }
                onClicked: {
                  root.cursorActive = true
                  root.selectedIndex = row.index
                  root.activate(displayModel.get(row.index))
                }
              }

              // Leading marker column: status dot, or "+" for the new row
              Item {
                id: marker
                anchors.left: parent.left
                anchors.leftMargin: root.rowPadding
                anchors.verticalCenter: parent.verticalCenter
                width: root.markerWidth
                height: parent.height

                Rectangle {
                  visible: !row.isNewButton
                  anchors.centerIn: parent
                  width: Style.space(8)
                  height: width
                  radius: width / 2
                  color: row.running ? Color.accent : "transparent"
                  border.width: row.running ? 0 : Style.normalBorderWidth
                  border.color: Util.alpha(root.foreground, 0.45)
                }

                Text {
                  visible: row.isNewButton
                  anchors.centerIn: parent
                  text: "+"
                  color: row.textColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                }
              }

              Column {
                anchors.left: marker.right
                anchors.leftMargin: Style.space(10)
                anchors.right: trailing.left
                anchors.rightMargin: root.contentSpacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Row {
                  spacing: Style.space(8)

                  Text {
                    textFormat: Text.PlainText
                    text: row.isNewButton ? "New session" : row.name
                    color: row.textColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                  }

                  Text {
                    visible: row.isDefault || row.isMachine
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.isMachine ? "remote" : "default"
                    color: root.foreground
                    opacity: 0.5
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  text: row.isNewButton ? "Create and launch a new herdr session" : row.sessionDir
                  color: root.foreground
                  opacity: 0.5
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideMiddle
                }
              }

              // Trailing column: actions on the cursor row, status otherwise
              Item {
                id: trailing
                anchors.right: parent.right
                anchors.rightMargin: root.rowPadding
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(statusText.implicitWidth, actions.implicitWidth)
                height: parent.height
                visible: !row.isNewButton

                Text {
                  id: statusText
                  visible: !row.hasCursor
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: row.isMachine ? row.status : (row.running ? "running" : "stopped")
                  color: row.running ? Color.accent : root.foreground
                  opacity: row.running ? 0.9 : 0.4
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                // Pull icon buttons out by their padding so glyphs line up
                // with the status text edge.
                Row {
                  id: actions
                  visible: row.hasCursor
                  anchors.right: parent.right
                  anchors.rightMargin: -Style.spacing.controlPaddingX
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Button {
                    visible: row.running && !row.isMachine
                    iconText: ""
                    tooltipText: "Stop (s)"
                    foreground: root.foreground
                    onClicked: root.stopSession(displayModel.get(row.index))
                  }

                  Button {
                    visible: !row.running && !row.isDefault && !row.isMachine
                    iconText: ""
                    tooltipText: "Delete (d)"
                    foreground: root.foreground
                    onClicked: root.requestDeleteSession(displayModel.get(row.index))
                  }

                  Button {
                    iconText: ""
                    tooltipText: "Open (Enter)"
                    foreground: root.selectedText
                    onClicked: root.activate(displayModel.get(row.index))
                  }
                }
              }
            }
          }

          // Empty filter result
          Text {
            anchors.centerIn: parent
            visible: !root.creatingNew && displayModel.count === 0
            textFormat: Text.PlainText
            text: "No sessions match “" + root.filterText + "”"
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }

          // New session form
          Column {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: root.rowPadding
            anchors.rightMargin: root.rowPadding
            anchors.topMargin: root.rowPadding
            visible: root.creatingNew
            spacing: Style.spacing.lg

            Text {
              text: "Session name"
              color: root.foreground
              opacity: 0.58
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            TextField {
              id: newSessionInput
              width: parent.width
              placeholderText: "e.g. project-x"
              foreground: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              onAccepted: root.submitNewSession()
              Keys.onEscapePressed: root.cancelCreateNew()
            }

            Row {
              anchors.right: parent.right
              spacing: Style.space(10)

              Button {
                text: "Cancel"
                bordered: true
                fontFamily: root.fontFamily
                foreground: root.foreground
                onClicked: root.cancelCreateNew()
              }

              Button {
                text: "Create"
                bordered: true
                fontFamily: root.fontFamily
                foreground: root.selectedText
                onClicked: root.submitNewSession()
              }
            }
          }
        }

        // Footer key hints
        Text {
          id: footer
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: root.footerHeight
          verticalAlignment: Text.AlignBottom
          text: root.creatingNew
            ? "enter create · esc cancel"
            : "↑↓ select · enter open · n new · s stop · d delete · esc close"
          color: root.foreground
          opacity: 0.45
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
