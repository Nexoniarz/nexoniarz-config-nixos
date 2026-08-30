//@ pragma UseQApplication
// Quickshell entry point.
// Deployed as the whole directory -> ~/.config/quickshell via
// systemd.tmpfiles in modules/desktop.nix (relative imports need the full
// directory present, not just this file).
// UseQApplication is required for SystemTray items' native right-click
// menu (item.display()) — without it, Quickshell logs "Cannot display
// PlatformMenuEntry ... was not started in QApplication mode" and the
// menu silently does nothing.
import QtQuick
import Quickshell
import Quickshell.Io

ShellRoot {
    PolkitDialog {}
    Osd {}

    Variants {
        model: Quickshell.screens

        Item {
            required property var modelData

            LeftBar { id: leftBarInstance; screen: modelData }
            RightBar { id: rightBarInstance; screen: modelData }
            BottomBar { screen: modelData; leftBar: leftBarInstance; rightBar: rightBarInstance }

            // Lets Hyprland keybinds (Super+Shift+Z/X, see hyprland.conf)
            // toggle the sidebars via `quickshell ipc call sidebars
            // toggleLeft/toggleRight` — same open/close behavior as
            // clicking the arrows on BottomBar.
            IpcHandler {
                target: "sidebars"
                function toggleLeft(): void {
                    leftBarInstance.expanded = !leftBarInstance.expanded;
                    if (!leftBarInstance.expanded) leftBarInstance.activePanel = "";
                }
                function toggleRight(): void {
                    rightBarInstance.expanded = !rightBarInstance.expanded;
                    if (!rightBarInstance.expanded) rightBarInstance.activePanel = "";
                }
            }
        }
    }
}
