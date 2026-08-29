import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: root
    required property var screen
    property string activePanel: ""
    property bool expanded: false

    anchors { top: true; left: true; bottom: true }
    // Collapsed = zero reserved space; expand/collapse is triggered from
    // the taskbar (BottomBar), not a button on this bar itself.
    implicitWidth: expanded ? 220 : 0
    exclusiveZone: expanded ? 220 : 0
    color: Theme.bg
    focusable: false

    Process { id: launcher; command: [] }
    function launch(cmd) { launcher.command = cmd; launcher.running = true; }

    // Only "booru" needs the popup's keyboard grab (it's the only panel
    // with a text field).
    function needsGrab(panel) { return panel === "booru"; }

    function toggle(panel) {
        if (root.activePanel === panel) {
            root.activePanel = "";
            return;
        }
        if (root.activePanel !== "" && root.needsGrab(root.activePanel) !== root.needsGrab(panel)) {
            // Switching directly between a grabbing and a non-grabbing
            // panel without closing the popup first doesn't work — an
            // xdg_popup's grab can only be established when the surface
            // is first created, not toggled on one that's already
            // mapped. Force a close, then reopen on the next tick so the
            // popup actually gets torn down and recreated with the right
            // grab state.
            root.activePanel = "";
            Qt.callLater(function () { root.activePanel = panel; });
            return;
        }
        root.activePanel = panel;
    }

    // Resolves the real, locale-correct Pictures folder at click time
    // (e.g. ~/Obrazy on pl_PL) instead of assuming the English name.
    Process {
        id: picturesLauncher
        command: ["sh", "-c", "thunar \"$(xdg-user-dir PICTURES)\""]
    }

    Column {
        visible: root.expanded
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 14
        spacing: 14
        width: parent.width - 24

        Column {
            width: parent.width
            spacing: 6

            Text {
                text: "SHORTCUTS"
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                font.bold: true
            }
            SidebarRow {
                label: "Dotfiles / NixOS"
                onClicked: root.launch(["thunar", "/etc/nixos"])
            }
            SidebarRow {
                label: "Pictures"
                onClicked: picturesLauncher.running = true
            }
        }

        Column {
            width: parent.width
            spacing: 6

            Text {
                text: "APPEARANCE"
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                font.bold: true
            }
            SidebarRow {
                label: "Theme"
                active: root.activePanel === "theme"
                onClicked: root.toggle("theme")
            }
            SidebarRow {
                label: "Display Settings"
                active: root.activePanel === "settings"
                onClicked: root.toggle("settings")
            }
            SidebarRow {
                label: "Wallpapers"
                active: root.activePanel === "wallpapers"
                onClicked: root.toggle("wallpapers")
            }
            SidebarRow {
                label: "Booru"
                active: root.activePanel === "booru"
                onClicked: root.toggle("booru")
            }
            SidebarRow {
                label: "Cursor"
                active: root.activePanel === "cursor"
                onClicked: root.toggle("cursor")
            }
        }
    }

    PanelWindow {
        id: flyout
        screen: root.screen
        anchors { top: true; left: true }
        // No margin here on purpose: Hyprland already insets layer-shell
        // surfaces past other surfaces' exclusive zones on the same edge
        // (confirmed via `hyprctl layers` — BottomBar gets the same
        // treatment for free, sitting at x=220 with zero margin of its
        // own). A margin of 220 here was stacking on top of that
        // automatic inset, pushing the flyout 220px further right than
        // intended and leaving a ~220px gap between it and the sidebar.
        visible: root.activePanel !== ""
        implicitWidth: 320
        implicitHeight: flyoutContent.implicitHeight
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        // On-demand layer-shell focus, not an xdg_popup grab: this used to
        // be a PopupWindow with grabFocus, but an xdg_popup grab gets
        // dismissed by the compositor the instant anything else so much as
        // touches focus/surface state elsewhere — mapping mpvpaper's
        // layer-shell surface (or even hyprpaper's own "wallpaper" IPC call
        // recreating its surface) was enough to trigger that, silently
        // closing the whole flyout AND dropping keyboard input, which is
        // what let keystrokes fall through to whatever window was focused
        // before the flyout opened instead of reaching the text field.
        // OnDemand only claims focus when something inside is actually
        // clicked, and isn't torn down by unrelated surfaces. Panels with
        // no text input don't need it at all.
        WlrLayershell.keyboardFocus: root.needsGrab(root.activePanel)
            ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        LeftFlyout {
            id: flyoutContent
            anchors.fill: parent
            screen: root.screen
            activePanel: root.activePanel
            onRequestClose: root.activePanel = ""
        }
    }
}
