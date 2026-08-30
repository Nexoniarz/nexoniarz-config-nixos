import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import Quickshell.Wayland

PanelWindow {
    id: root
    required property var screen
    property string activePanel: ""
    property bool expanded: false

    // Keeps the default sink's PwNode subscribed so audio properties
    // (volume/muted) actually receive live updates.
    PwObjectTracker {
        objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : []
    }

    anchors { top: true; right: true; bottom: true }
    // Collapsed = zero reserved space; expand/collapse is triggered from
    // the taskbar (BottomBar), not a button on this bar itself.
    implicitWidth: expanded ? 220 : 0
    exclusiveZone: expanded ? 220 : 0
    color: Theme.bg
    // Never take keyboard focus — this bar has no text input, and leaving
    // it focusable was stealing the keyboard grab from things like slurp's
    // screenshot selection overlay.
    focusable: false

    // Only "network" needs the popup's keyboard grab (hotspot/wifi
    // password fields).
    function needsGrab(panel) { return panel === "network"; }

    function toggle(panel) {
        if (root.activePanel === panel) {
            root.activePanel = "";
            return;
        }
        if (root.activePanel !== "" && root.needsGrab(root.activePanel) !== root.needsGrab(panel)) {
            // See LeftBar.qml's toggle() for why: an xdg_popup's grab
            // can't be toggled on an already-mapped surface, only
            // established fresh — so force a close+reopen when crossing
            // that boundary instead of just changing the panel in place.
            root.activePanel = "";
            Qt.callLater(function () { root.activePanel = panel; });
            return;
        }
        root.activePanel = panel;
    }

    Column {
        visible: root.expanded
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: 14
        spacing: 14
        width: parent.width - 24

        DigitalClock {
            anchors.horizontalCenter: parent.horizontalCenter
        }

        // System tray (StatusNotifierItem) — background/status apps like
        // Steam, Discord, KDE Connect that register a tray icon. Sits
        // right under the clock, separate from the categorized sections
        // below the divider.
        Row {
            id: trayRow
            visible: SystemTray.items.values.length > 0
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            Repeater {
                model: SystemTray.items.values
                delegate: IconImage {
                    id: trayIcon
                    implicitSize: 18
                    // Only resolve through the icon theme when this is
                    // actually a themed icon name (e.g. Steam's
                    // "steam_tray_mono"). Apps that only ever supply a raw
                    // IconPixmap over the SNI protocol and no IconName at
                    // all (confirmed via busctl: Vesktop's tray item has no
                    // IconName property) get an already-usable image:// URL
                    // back from modelData.icon instead — running that
                    // through iconPath(), a name/path resolver, mangled it
                    // into nothing, which is what rendered as a broken-
                    // texture checkerboard instead of the actual icon.
                    source: modelData.icon.includes("://")
                        ? modelData.icon
                        : Quickshell.iconPath(modelData.icon, "")
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton) {
                                if (modelData.hasMenu) {
                                    var pos = trayIcon.mapToItem(null, 0, trayIcon.height);
                                    modelData.display(root, pos.x, pos.y);
                                } else {
                                    modelData.secondaryActivate();
                                }
                            } else {
                                modelData.activate();
                            }
                        }
                    }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Theme.borderDim }

        Column {
            width: parent.width
            spacing: 6

            Text {
                text: "CONNECTIVITY"
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                font.bold: true
            }
            SidebarRow {
                label: "Wi-Fi & Network"
                active: root.activePanel === "network"
                onClicked: root.toggle("network")
            }
            SidebarRow {
                label: "Bluetooth"
                active: root.activePanel === "bluetooth"
                onClicked: root.toggle("bluetooth")
            }
            SidebarRow {
                label: "Messages"
                active: root.activePanel === "messages"
                onClicked: root.toggle("messages")
            }
        }

        Column {
            width: parent.width
            spacing: 6

            Text {
                text: "SYSTEM"
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                font.bold: true
            }
            SidebarRow {
                label: "Screenshot"
                active: root.activePanel === "screenshot"
                onClicked: root.toggle("screenshot")
            }
            SidebarRow {
                label: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted)
                    ? "Volume (muted)" : "Volume"
                active: root.activePanel === "volume"
                onClicked: root.toggle("volume")
            }
            SidebarRow {
                label: "Brightness"
                active: root.activePanel === "brightness"
                onClicked: root.toggle("brightness")
            }
            SidebarRow {
                label: "Devices"
                active: root.activePanel === "devices"
                onClicked: root.toggle("devices")
            }
            SidebarRow {
                label: "System Monitor"
                active: root.activePanel === "system"
                onClicked: root.toggle("system")
            }
            SidebarRow {
                label: "Weather"
                active: root.activePanel === "weather"
                onClicked: root.toggle("weather")
            }
        }
    }

    SidebarRow {
        visible: root.expanded
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - 24
        label: "Power"
        fg: Theme.danger
        active: root.activePanel === "power"
        onClicked: root.toggle("power")
    }

    PanelWindow {
        id: flyout
        screen: root.screen
        anchors { top: true; right: true }
        // No margin here on purpose: Hyprland already insets layer-shell
        // surfaces past other surfaces' exclusive zones on the same edge
        // (confirmed via `hyprctl layers` — BottomBar gets the same
        // treatment for free, spanning right up to x=1700 with zero
        // margin of its own). A margin of 220 here was stacking on top
        // of that automatic inset, pushing the flyout 220px further left
        // than intended and leaving a ~220px gap between it and the
        // sidebar.
        visible: root.activePanel !== ""
        implicitWidth: 320
        implicitHeight: content.implicitHeight
        exclusiveZone: 0
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        // On-demand layer-shell focus, not an xdg_popup grab: this used to
        // be a PopupWindow with grabFocus, but an xdg_popup grab gets
        // dismissed by the compositor the instant anything else so much as
        // touches focus/surface state elsewhere (confirmed: even an
        // unrelated hyprpaper/mpvpaper surface change was enough), which
        // silently closed the whole flyout AND dropped keyboard input —
        // that's what let keystrokes fall through to whatever window was
        // focused before the flyout opened instead of reaching the text
        // field. OnDemand only claims focus when something inside is
        // actually clicked, and isn't torn down by unrelated surfaces.
        // Panels with no text input don't need it at all.
        WlrLayershell.keyboardFocus: root.needsGrab(root.activePanel)
            ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        RightFlyout {
            id: content
            anchors.fill: parent
            activePanel: root.activePanel
            onRequestClose: root.activePanel = ""
        }
    }
}
