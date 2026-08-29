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

ShellRoot {
    PolkitDialog {}

    Variants {
        model: Quickshell.screens

        Item {
            required property var modelData

            LeftBar { id: leftBarInstance; screen: modelData }
            RightBar { id: rightBarInstance; screen: modelData }
            BottomBar { screen: modelData; leftBar: leftBarInstance; rightBar: rightBarInstance }
        }
    }
}
