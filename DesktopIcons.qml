import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// Desktop icons: renders the top level of the user's Desktop folder on the
// background layer, above the wallpaper and below normal windows. They exist
// only in the floating workspace layout, the dock mode; tiled and scrolling
// workspaces stay clean. Single click selects, double click opens, right click
// offers file actions.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME") || ""

  property string desktopDir: ""
  property var entries: []
  property string selectedPath: ""

  // Omarchy has three workspace layouts: dwindle, scrolling, and floating.
  // The dock lives in floating, and so do these icons.
  property string workspaceLayout: ""
  readonly property bool dockMode: root.workspaceLayout === "floating"

  // Grid constants; the QML is the settings surface for this plugin.
  readonly property int iconSize: 46
  readonly property int cellWidth: 100
  readonly property int cellHeight: 98
  readonly property int cellSpacing: 4
  readonly property int edgeMargin: 22
  readonly property int topMargin: 48
  readonly property int bottomMargin: 44

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  function pluginDir() {
    return root.manifest && root.manifest.__sourceDir
      ? String(root.manifest.__sourceDir) : ""
  }

  function refresh() {
    if (root.desktopDir === "" || listProc.running) return
    listProc.command = ["/usr/bin/python3", root.pluginDir() + "/list-desktop.py", root.desktopDir]
    listProc.running = true
  }

  function sanitizeEntries(raw) {
    var out = []
    var parsed
    try {
      parsed = JSON.parse(String(raw || "[]"))
    } catch (error) {
      parsed = []
    }
    if (!Array.isArray(parsed)) return out
    var limit = Math.min(parsed.length, 500)
    for (var i = 0; i < limit; i++) {
      var entry = parsed[i]
      if (!entry || typeof entry.path !== "string" || typeof entry.name !== "string") continue
      out.push({
        name: String(entry.name).slice(0, 200),
        path: String(entry.path),
        isDir: entry.isDir === true,
        isImage: entry.isImage === true,
        isDesktop: entry.isDesktop === true,
        icon: String(entry.icon || (entry.isDir ? "folder" : "text-x-generic"))
      })
    }
    return out
  }

  function openPath(entry) {
    if (!entry || !entry.path || openProc.running) return
    var path = entry.path
    if (entry.isDesktop) {
      Quickshell.execDetached([
        "bash", "-c",
        'gio launch "$1" >/dev/null 2>&1 || xdg-open "$1" >/dev/null 2>&1',
        "open", path
      ])
      return
    }
    // Flea is Omarchy's opener, so it resolves the same MIME defaults the file
    // manager uses: text/plain goes to the configured editor (Neovim here),
    // video/mp4 to VLC, and so on. Fall back to xdg-open without Flea.
    openProc.path = path
    openProc.isDir = entry.isDir === true
    openProc.command = openProc.isDir
      ? ["bash", "-c",
        'if command -v flea >/dev/null 2>&1; then exec flea "$1"; else exec xdg-open "$1"; fi',
        "open", path]
      : ["bash", "-c",
        'if command -v flea >/dev/null 2>&1; then exec flea --open "$1"; else exec xdg-open "$1"; fi',
        "open", path]
    openProc.running = true
  }

  function openInTerminal(path) {
    if (!path) return
    Quickshell.execDetached(["setsid", "xdg-terminal-exec", "--dir=" + path])
  }

  function copyPath(path) {
    if (!path) return
    Quickshell.execDetached(["bash", "-c", 'printf %s "$1" | wl-copy', "copy", path])
  }

  function trashPath(path) {
    if (!path) return
    trashProc.path = path
    trashProc.command = ["gio", "trash", path]
    trashProc.running = true
  }

  function changeWallpaper() {
    Quickshell.execDetached([
      "bash", "-c",
      'background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set "$background"'
    ])
  }

  function hasPath(path) {
    for (var i = 0; i < root.entries.length; i++)
      if (root.entries[i].path === path) return true
    return false
  }

  function menuFor(path, isDir) {
    var items = []
    if (path === "") {
      items.push({ id: "openDesktop", label: strings.t("menu.openDesktop") })
      items.push({ id: "openDesktopTerminal", label: strings.t("menu.openDesktopTerminal") })
      items.push({ id: "changeWallpaper", label: strings.t("menu.changeWallpaper") })
      items.push({ id: "refresh", label: strings.t("menu.refresh") })
      return items
    }
    items.push({ id: "open", label: strings.t("menu.open") })
    if (isDir) items.push({ id: "openTerminal", label: strings.t("menu.openTerminal") })
    items.push({ id: "copyPath", label: strings.t("menu.copyPath") })
    items.push({ id: "trash", label: strings.t("menu.moveToTrash") })
    items.push({ id: "refresh", label: strings.t("menu.refresh") })
    return items
  }

  // A valid XDG desktop directory is used unless it points at $HOME (a common
  // misconfiguration that would turn the whole home folder into desktop icons).
  Process {
    id: resolveProc
    command: ["bash", "-c",
      'd="$(xdg-user-dir DESKTOP 2>/dev/null)"; d="${d%/}"; ' +
      'if [[ -z "$d" || "$d" == "$HOME" || ! -d "$d" ]]; then d="$HOME/Desktop"; fi; ' +
      'if [[ ! -d "$d" ]]; then mkdir -p "$d"; fi; printf "%s" "$d"']
    stdout: StdioCollector {
      id: resolveOut
      waitForEnd: true
    }
    onExited: {
      var resolved = String(resolveOut.text || "").trim()
      if (resolved === "") return
      root.desktopDir = resolved
      root.refresh()
      watchProc.running = true
    }
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      id: listOut
      waitForEnd: true
    }
    onExited: {
      var next = root.sanitizeEntries(listOut.text)
      if (JSON.stringify(next) !== JSON.stringify(root.entries)) root.entries = next
      if (root.selectedPath !== "" && !root.hasPath(root.selectedPath)) root.selectedPath = ""
    }
  }

  // Directory changes arrive here; a slow safety poll below covers the cases
  // where inotify cannot watch the folder.
  Process {
    id: watchProc
    command: ["inotifywait", "-m", "-q", "-e", "create,delete,move,close_write,attrib",
      "--format", "%f", root.desktopDir]
    stdout: SplitParser {
      onRead: refreshDebounce.restart()
    }
    onExited: if (root.desktopDir !== "") watchRestart.restart()
  }

  Timer {
    id: refreshDebounce
    interval: 180
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: watchRestart
    interval: 2000
    repeat: false
    onTriggered: if (root.desktopDir !== "") watchProc.running = true
  }

  Timer {
    interval: 15000
    repeat: true
    running: root.desktopDir !== ""
    onTriggered: root.refresh()
  }

  Process {
    id: trashProc
    property string path: ""
    onExited: {
      root.refresh()
      if (root.selectedPath === trashProc.path) root.selectedPath = ""
    }
  }

  // Flea reports why a launch failed: 3 means the path is really a directory,
  // 4 asks its run card and 5 asks Open with. A desktop icon has no card, so
  // those two hand the path to the system default instead.
  Process {
    id: openProc
    property string path: ""
    property bool isDir: false
    onExited: function(exitCode, exitStatus) {
      if (exitCode === 0) return
      if (exitCode === 3) {
        Quickshell.execDetached(["bash", "-c",
          'if command -v flea >/dev/null 2>&1; then exec flea "$1"; else exec xdg-open "$1"; fi',
          "open", openProc.path])
        return
      }
      if (exitCode === 4 || exitCode === 5) {
        Quickshell.execDetached(["xdg-open", openProc.path])
        return
      }
      Quickshell.execDetached([
        "omarchy-notification-send", strings.t("open.failed"), openProc.path
      ])
    }
  }

  function refreshLayout() {
    if (!layoutProc.running) layoutProc.running = true
  }

  Process {
    id: layoutProc
    command: ["omarchy-hyprland-workspace-layout-current"]
    stdout: StdioCollector {
      id: layoutOut
      waitForEnd: true
    }
    onExited: {
      var value = String(layoutOut.text || "").trim()
      if (value !== "" && value !== root.workspaceLayout) root.workspaceLayout = value
    }
  }

  // Layout toggles do not emit a workspace change, so this polls. The interval
  // is slow enough to be cheap and fast enough that the mode switch feels live.
  Timer {
    interval: 900
    repeat: true
    running: true
    onTriggered: root.refreshLayout()
  }

  Connections {
    target: Hyprland

    function onFocusedWorkspaceChanged() {
      root.refreshLayout()
    }
  }

  Component.onCompleted: {
    resolveProc.running = true
    root.refreshLayout()
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: win
        required property var modelData

        screen: modelData
        visible: root.desktopDir !== "" && root.dockMode
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omarchy-desktop-icons"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        onVisibleChanged: {
          if (visible) return
          root.selectedPath = ""
          closeMenu()
        }

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        property bool menuOpen: false
        property real menuX: 0
        property real menuY: 0
        property var menuEntries: []
        property string menuPath: ""
        property bool menuIsDir: false

        function openMenu(path, isDir, x, y) {
          win.menuPath = path
          win.menuIsDir = isDir
          win.menuEntries = root.menuFor(path, isDir)
          win.menuX = x
          win.menuY = y
          win.menuOpen = true
        }

        function closeMenu() {
          win.menuOpen = false
        }

        function runMenuAction(action) {
          var path = win.menuPath
          var isDir = win.menuIsDir
          win.closeMenu()
          if (action === "open") {
            for (var i = 0; i < root.entries.length; i++) {
              if (root.entries[i].path === path) {
                root.openPath(root.entries[i])
                return
              }
            }
          } else if (action === "openTerminal" || action === "openDesktopTerminal") {
            root.openInTerminal(isDir && path !== "" ? path : root.desktopDir)
          } else if (action === "openDesktop") {
            Quickshell.execDetached(["xdg-open", root.desktopDir])
          } else if (action === "copyPath") {
            root.copyPath(path)
          } else if (action === "trash") {
            root.trashPath(path)
          } else if (action === "changeWallpaper") {
            root.changeWallpaper()
          } else if (action === "refresh") {
            root.refresh()
          }
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onClicked: function(mouse) {
            win.closeMenu()
            root.selectedPath = ""
            if (mouse.button === Qt.RightButton) win.openMenu("", false, mouse.x, mouse.y)
          }
        }

        Flow {
          anchors.fill: parent
          anchors.topMargin: root.topMargin
          anchors.bottomMargin: root.bottomMargin
          anchors.leftMargin: root.edgeMargin
          anchors.rightMargin: root.edgeMargin
          flow: Flow.TopToBottom
          spacing: root.cellSpacing

          Repeater {
            model: root.entries

            delegate: Item {
              id: cell
              width: root.cellWidth
              height: root.cellHeight

              readonly property bool selected: root.selectedPath === modelData.path

              Rectangle {
                anchors.fill: parent
                radius: 10
                color: cell.selected
                  ? Util.alpha(Commons.Color.accent, 0.26)
                  : (cellMouse.containsMouse ? Util.alpha(Commons.Color.foreground, 0.10) : "transparent")
                border.width: cell.selected ? 1 : 0
                border.color: Util.alpha(Commons.Color.accent, 0.85)
              }

              Item {
                id: iconBox
                anchors.top: parent.top
                anchors.topMargin: 8
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.iconSize
                height: root.iconSize

                Image {
                  id: thumb
                  anchors.fill: parent
                  visible: modelData.isImage && thumb.status === Image.Ready
                  source: modelData.isImage ? Util.fileUrl(modelData.path) : ""
                  sourceSize.width: root.iconSize
                  sourceSize.height: root.iconSize
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  cache: false
                  smooth: true
                  mipmap: true
                }

                Image {
                  anchors.fill: parent
                  visible: !modelData.isImage || thumb.status !== Image.Ready
                  source: Quickshell.iconPath(modelData.icon, true)
                  sourceSize.width: root.iconSize
                  sourceSize.height: root.iconSize
                  asynchronous: true
                  smooth: true
                }

                Rectangle {
                  anchors.fill: parent
                  visible: modelData.isImage && thumb.status === Image.Ready
                  color: "transparent"
                  radius: 5
                  border.width: 1
                  border.color: Util.alpha(Commons.Color.foreground, 0.35)
                }
              }

              Text {
                anchors.top: iconBox.bottom
                anchors.topMargin: 5
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 3
                anchors.rightMargin: 3
                textFormat: Text.PlainText
                text: modelData.name
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                color: Commons.Color.foreground
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideMiddle
                style: Text.Outline
                styleColor: Util.alpha(Commons.Color.background, 0.65)
              }

              MouseArea {
                id: cellMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(mouse) {
                  win.closeMenu()
                  root.selectedPath = modelData.path
                  if (mouse.button === Qt.RightButton)
                    win.openMenu(modelData.path, modelData.isDir, mouse.x, mouse.y)
                }
                onDoubleClicked: function(mouse) {
                  if (mouse.button !== Qt.LeftButton) return
                  win.closeMenu()
                  root.openPath(modelData)
                }
              }
            }
          }
        }

        Rectangle {
          id: contextMenu
          visible: win.menuOpen
          z: 100
          width: 216
          height: menuColumn.implicitHeight + 12
          radius: 10
          color: Util.alpha(Commons.Color.background, 0.97)
          border.width: 1
          border.color: Util.alpha(Commons.Color.accent, 0.35)

          x: Math.max(6, Math.min(win.menuX, win.width - width - 6))
          y: Math.max(6, Math.min(win.menuY, win.height - height - 6))

          Column {
            id: menuColumn
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 6
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            spacing: 2

            Repeater {
              model: win.menuEntries

              delegate: Rectangle {
                height: 34
                width: menuColumn.width
                radius: 6
                color: rowMouse.containsMouse ? Util.alpha(Commons.Color.accent, 0.18) : "transparent"

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: 10
                  anchors.rightMargin: 10
                  textFormat: Text.PlainText
                  text: modelData.label
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  color: Commons.Color.foreground
                  elide: Text.ElideRight
                  horizontalAlignment: Commons.I18n.rightToLeft ? Text.AlignRight : Text.AlignLeft
                }

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  onClicked: win.runMenuAction(modelData.id)
                }
              }
            }
          }
        }
      }
    }
  }
}
