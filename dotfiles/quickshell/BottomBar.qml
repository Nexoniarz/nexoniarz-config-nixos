import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets

PanelWindow {
    id: root
    required property var screen
    required property var leftBar
    required property var rightBar

    // Right-click context menu state — set by whichever taskbar window
    // entry was right-clicked, cleared after an action or a second
    // right-click on the same entry. Anchored via anchor.window + a
    // one-shot computed x (not anchor.item!) — anchoring a popup directly
    // to a Repeater delegate crashed Quickshell (PopupAnchor::setItem /
    // onItemWindowChanged segfaults when the delegate it's watching gets
    // destroyed/recreated, which happens often since the window list
    // rebuilds its model on every toplevel change). root itself is a
    // stable, never-recreated window, so anchoring to it is safe — same
    // pattern the Left/RightBar flyouts already use successfully.
    property var ctxMenuToplevel: null
    property real ctxMenuX: 0
    function closeCtxMenu() {
        root.ctxMenuToplevel = null;
    }

    anchors { left: true; right: true; bottom: true }
    implicitHeight: 46
    exclusiveZone: 46
    color: Theme.bg
    focusable: false

    // Special workspaces (e.g. "special:showdesktop", used by the
    // Super+D show-desktop toggle) are an implementation detail, not a
    // real switchable workspace — Hyprland keeps their metadata around
    // even once empty, so they'd otherwise show up here forever.
    property var visibleWorkspaces: {
        var out = [];
        var all = Hyprland.workspaces.values;
        for (var i = 0; i < all.length; i++) {
            if (all[i].name.indexOf("special:") !== 0) out.push(all[i]);
        }
        return out;
    }

    // Only workspaces that actually exist (have windows, or are/were
    // focused) get a pill — showing all 10 possible slots took up too
    // much space. Always shown in numeric order (1, 2, 3, ...) regardless
    // of creation/focus order, matching the Super+1..9,0 keybinds.
    property var workspacePills: {
        var out = [];
        for (var i = 0; i < root.visibleWorkspaces.length; i++) {
            var w = root.visibleWorkspaces[i];
            out.push({ number: w.id, ws: w });
        }
        out.sort(function (a, b) { return a.number - b.number; });
        return out;
    }

    // Window list ordered by workspace number (1, then 2, ...) instead of
    // whatever arbitrary order the compositor reports toplevels in.
    //
    // The base list comes from ToplevelManager (the generic Wayland
    // wlr-foreign-toplevel-management module), NOT Hyprland.toplevels —
    // Hyprland.toplevels is built by parsing Hyprland's own IPC event
    // stream, and apps that open/close many short-lived helper windows
    // fast (Steam is the textbook case: steamwebhelper, dummy GL context
    // windows, etc.) can desync it from reality, leaving phantom entries
    // that `hyprctl clients` doesn't even show. ToplevelManager reflects
    // live protocol state directly, so it can't go stale like that.
    // Hyprland.toplevels is only used as a lookup to find each window's
    // workspace id for sorting — a lookup miss just sorts that window last,
    // it can't add a window that isn't really there.
    property var orderedToplevels: {
        var genList = ToplevelManager.toplevels.values;
        var hyprList = Hyprland.toplevels.values;
        var out = [];
        for (var i = 0; i < genList.length; i++) {
            var gt = genList[i];
            var wsId = 999999;
            for (var j = 0; j < hyprList.length; j++) {
                if (hyprList[j].wayland === gt) {
                    wsId = (hyprList[j].workspace && hyprList[j].workspace.id > 0) ? hyprList[j].workspace.id : 999999;
                    break;
                }
            }
            out.push({ tl: gt, wsId: wsId });
        }
        out.sort(function (a, b) { return a.wsId - b.wsId; });
        return out;
    }

    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.border }

    // --- Left bar toggle ---------------------------------------------
    Rectangle {
        id: leftToggle
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 32
        height: 32
        color: ltMa.containsMouse ? Theme.bgAlt : "transparent"
        border.width: root.leftBar.expanded ? 2 : 1
        border.color: root.leftBar.expanded ? Theme.accent : Theme.border
        Text {
            anchors.centerIn: parent
            text: root.leftBar.expanded ? "<" : ">"
            color: root.leftBar.expanded ? Theme.accent : Theme.fg
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 14
            font.bold: true
        }
        MouseArea {
            id: ltMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.leftBar.expanded = !root.leftBar.expanded;
                if (!root.leftBar.expanded) root.leftBar.activePanel = "";
            }
        }
    }

    Row {
        anchors.left: leftToggle.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 8
        spacing: 4

        Repeater {
            model: root.workspacePills
            delegate: Rectangle {
                property var ws: modelData.ws
                property int number: modelData.number
                width: 32
                height: 28
                color: ws.focused ? Theme.accent : (wsMa.containsMouse ? Theme.bgAlt : "transparent")
                border.width: 1
                border.color: ws.urgent ? Theme.danger : Theme.border
                Text {
                    anchors.centerIn: parent
                    text: number
                    color: ws.focused ? Theme.bg : Theme.fg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                }
                MouseArea {
                    id: wsMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: ws.activate()
                }
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: 8 + 32 + 8 + (root.workspacePills.length * 36) + 4
        anchors.top: parent.top
        anchors.topMargin: 6
        width: 1
        height: 28
        color: Theme.border
    }

    // --- Right bar toggle ---------------------------------------------
    Rectangle {
        id: rightToggle
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        width: 32
        height: 32
        color: rtMa.containsMouse ? Theme.bgAlt : "transparent"
        border.width: root.rightBar.expanded ? 2 : 1
        border.color: root.rightBar.expanded ? Theme.accent : Theme.border
        Text {
            anchors.centerIn: parent
            text: root.rightBar.expanded ? ">" : "<"
            color: root.rightBar.expanded ? Theme.accent : Theme.fg
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 14
            font.bold: true
        }
        MouseArea {
            id: rtMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.rightBar.expanded = !root.rightBar.expanded;
                if (!root.rightBar.expanded) root.rightBar.activePanel = "";
            }
        }
    }

    Row {
        anchors.left: parent.left
        anchors.leftMargin: 8 + 32 + 8 + (root.workspacePills.length * 36) + 16
        anchors.right: rightToggle.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        clip: true

        Repeater {
            model: root.orderedToplevels
            delegate: Rectangle {
                id: tlDelegate
                property var tl: modelData.tl
                // Resolved via the app's .desktop entry (matched by Wayland
                // app-id) rather than trusting a raw icon name/path from
                // the toplevel itself, which isn't exposed by the protocol.
                property string iconSrc: {
                    if (!tl.appId) return "";
                    var entry = DesktopEntries.heuristicLookup(tl.appId);
                    if (!entry || !entry.icon) return "";
                    return Quickshell.iconPath(entry.icon, "");
                }
                width: Math.min(220, label.implicitWidth + (iconSrc !== "" ? 46 : 24))
                height: 28
                color: tl.activated ? Theme.accent : (tlMa.containsMouse ? Theme.bgAlt : Theme.bgAlt)
                border.width: 1
                border.color: root.ctxMenuToplevel === tl ? Theme.accent : Theme.border

                IconImage {
                    id: appIcon
                    visible: tlDelegate.iconSrc !== ""
                    implicitSize: 16
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    source: tlDelegate.iconSrc
                }
                Text {
                    id: label
                    anchors.left: appIcon.visible ? appIcon.right : parent.left
                    anchors.leftMargin: appIcon.visible ? 6 : 8
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: tl.title || tl.appId || "?"
                    color: tl.activated ? Theme.bg : Theme.fg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                MouseArea {
                    id: tlMa
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) {
                            if (root.ctxMenuToplevel === tl) { root.closeCtxMenu(); return; }
                            var pos = tlDelegate.mapToItem(null, 0, 0);
                            root.ctxMenuX = pos.x;
                            root.ctxMenuToplevel = tl;
                            return;
                        }
                        if (mouse.button === Qt.MiddleButton) tl.close();
                        else tl.activate();
                    }
                }
            }
        }
    }

    // --- Taskbar entry context menu ------------------------------------
    // Window control options exposed by the wlr-foreign-toplevel-management
    // protocol (fullscreen/maximized are writable properties on any
    // toplevel — there's no per-app capability flag to check, so these are
    // always offered as a best-effort "if the app honors it" set).
    // Loaded lazily (not instantiated until first opened) so the popup
    // and its anchor only exist while actually needed.
    Loader {
        active: root.ctxMenuToplevel !== null
        sourceComponent: PopupWindow {
            id: ctxMenu
            visible: true
            anchor.window: root
            anchor.rect.x: root.ctxMenuX
            anchor.rect.y: 0
            anchor.edges: Edges.Top
            anchor.gravity: Edges.Top
            anchor.margins.bottom: 4
            implicitWidth: 150
            implicitHeight: ctxCol.implicitHeight + 12
            color: "transparent"

            Rectangle {
                anchors.fill: parent
                color: Theme.bg
                border.width: 1
                border.color: Theme.border

                Column {
                    id: ctxCol
                    x: 6
                    y: 6
                    width: parent.width - 12
                    spacing: 2

                    Repeater {
                        model: {
                            var tl = root.ctxMenuToplevel;
                            if (!tl) return [];
                            return [
                                { label: tl.fullscreen ? "Exit Fullscreen" : "Fullscreen", action: "fullscreen", danger: false },
                                { label: tl.maximized ? "Restore" : "Maximize", action: "maximize", danger: false },
                                { label: "Close", action: "close", danger: true }
                            ];
                        }
                        delegate: Rectangle {
                            width: parent.width
                            height: 26
                            color: itemMa.containsMouse ? Theme.bgAlt : "transparent"
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                color: modelData.danger ? Theme.danger : Theme.fg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                            }
                            MouseArea {
                                id: itemMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    var tl = root.ctxMenuToplevel;
                                    if (tl) {
                                        if (modelData.action === "fullscreen") tl.fullscreen = !tl.fullscreen;
                                        else if (modelData.action === "maximize") tl.maximized = !tl.maximized;
                                        else if (modelData.action === "close") tl.close();
                                    }
                                    root.closeCtxMenu();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
