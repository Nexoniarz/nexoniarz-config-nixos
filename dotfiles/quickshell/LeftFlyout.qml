import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets

Rectangle {
    id: root
    property string activePanel: ""
    property var screen: null
    signal requestClose()

    width: 320
    implicitHeight: header.height + loader.item.implicitHeight + 16
    color: Theme.bg
    border.width: 2
    border.color: Theme.border

    property var titles: ({
        theme: "Theme",
        settings: "Displays",
        wallpapers: "Wallpapers",
        booru: "Booru",
        cursor: "Cursor"
    })

    Item {
        id: header
        width: parent.width
        height: 40

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: root.titles[root.activePanel] || ""
            color: Theme.fg
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 14
            font.bold: true
        }

        CloseButton {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.requestClose()
        }
    }
    Rectangle { anchors.top: header.bottom; width: parent.width; height: 1; color: Theme.border }

    Loader {
        id: loader
        y: header.height + 8
        x: 12
        width: parent.width - 24
        sourceComponent: {
            switch (root.activePanel) {
            case "theme": return themePanel;
            case "settings": return settingsPanel;
            case "wallpapers": return wallpapersPanel;
            case "booru": return booruPanel;
            case "cursor": return cursorPanel;
            default: return emptyPanel;
            }
        }
    }

    Component {
        id: emptyPanel
        Item { implicitHeight: 1 }
    }

    // --- Theme --------------------------------------------------------------
    // Everything here just calls Theme.setAccent/setDark/randomAccent —
    // Theme.qml itself owns the disk persistence, so there's nothing to
    // wire up here beyond the picker UI.
    Component {
        id: themePanel
        Column {
            width: loader.width
            spacing: 16

            Column {
                width: parent.width
                spacing: 8
                Text {
                    text: "ACCENT COLOR"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    font.bold: true
                }
                Flow {
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: Theme.accentNames
                        delegate: Rectangle {
                            property string name: modelData
                            property color swatch: Theme.accentPalette[name]
                            width: 40; height: 40
                            color: swatch
                            border.width: Theme.accentName === name ? 3 : 1
                            border.color: Theme.accentName === name ? Theme.fg : Theme.border
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Theme.setAccent(name)
                            }
                        }
                    }
                    Rectangle {
                        width: 40; height: 40
                        color: Theme.bgAlt
                        border.width: 1
                        border.color: Theme.border
                        Text {
                            anchors.centerIn: parent
                            text: "RND"
                            color: Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                            font.bold: true
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Theme.randomAccent()
                        }
                    }
                }
            }

            Column {
                width: parent.width
                spacing: 8
                Text {
                    text: "MODE"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    font.bold: true
                }
                Row {
                    spacing: 6
                    Repeater {
                        model: [
                            { label: "Dark", value: true },
                            { label: "Light", value: false }
                        ]
                        delegate: Rectangle {
                            property bool val: modelData.value
                            width: 90; height: 30
                            color: Theme.dark === val ? Theme.accent : (modeMa.containsMouse ? Theme.bgAlt : "transparent")
                            border.width: 1
                            border.color: Theme.dark === val ? Theme.accent : Theme.border
                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: Theme.dark === val ? Theme.bg : Theme.fg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                                font.bold: true
                            }
                            MouseArea {
                                id: modeMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Theme.setDark(val)
                            }
                        }
                    }
                }
            }

            Text {
                text: "Applies everywhere immediately. GTK apps (Thunar) follow separately\nand may need a restart to fully match."
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                wrapMode: Text.WordWrap
                width: parent.width
            }
        }
    }

    // --- Displays ---------------------------------------------------------
    // Mode/scale/rotation/color are edited locally per monitor (starting
    // from its current live values) and only actually applied when "Apply"
    // is clicked, via `hyprctl keyword monitor ...` — same mechanism
    // Hyprland itself uses, so it's an immediate, real change, not a
    // config-file edit. display-set (modules/scripts/display-set.sh) then
    // also persists the exact same descriptor into display.conf so it
    // survives a Hyprland restart.
    Component {
        id: settingsPanel
        Column {
            id: dispRoot
            width: loader.width
            spacing: 16

            // Hyprland's `monitor` keyword takes the FULL descriptor every
            // time — there's no way to change just one field. hyprctl's own
            // readback (Hyprland.monitors / lastIpcObject) covers most of
            // that (mode, scale, transform, bitdepth via currentFormat, cm,
            // sdrBrightness/Saturation, vrr) but NOT icc (never reported
            // back anywhere in `hyprctl monitors -j`). So this tracks
            // whatever WE last applied per monitor, keyed by name, and
            // every apply (including a plain drag-to-reposition on the
            // canvas below) resends the last-known-good value for every
            // field, live-readback for anything never customized —
            // otherwise repositioning a monitor with a custom ICC profile
            // would silently drop that profile on the next apply.
            property var overrides: ({})
            function ovr(name) { return dispRoot.overrides[name] || ({}); }
            function setOvr(name, patch) {
                var updated = {};
                for (var k in dispRoot.overrides) updated[k] = dispRoot.overrides[k];
                var merged = {};
                var cur = updated[name] || ({});
                for (var k2 in cur) merged[k2] = cur[k2];
                for (var k3 in patch) merged[k3] = patch[k3];
                updated[name] = merged;
                dispRoot.overrides = updated;
            }
            function posFor(name, lx, ly) {
                var o = dispRoot.overrides[name];
                return (o && o.x !== undefined) ? { x: o.x, y: o.y } : { x: lx, y: ly };
            }

            Text {
                visible: Hyprland.monitors.values.length === 0
                text: "No monitor data"
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
            }

            // -- Arrangement canvas --------------------------------------
            // Drag-to-position, like every other DE's display panel — the
            // only way to set position at all before this (previously the
            // per-monitor Apply always resent the monitor's own current
            // x/y unchanged, so multi-monitor layout couldn't be edited
            // from this panel).
            Column {
                id: arrColumn
                visible: Hyprland.monitors.values.length > 0
                width: parent.width
                spacing: 6

                Text {
                    text: "Arrangement"
                    color: Theme.fg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 13
                    font.bold: true
                }
                Text {
                    text: "Drag to position screens — edges snap together."
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                }

                // Logical (post-scale) bounding box of every monitor's
                // current-or-pending position, fit into the canvas — this
                // is what Hyprland actually tiles monitors in, not raw
                // pixel mode size.
                property real cScale: {
                    var maxX = 1, maxY = 1;
                    for (var i = 0; i < Hyprland.monitors.values.length; i++) {
                        var mm = Hyprland.monitors.values[i];
                        var p = dispRoot.posFor(mm.name, mm.x, mm.y);
                        maxX = Math.max(maxX, p.x + mm.width / mm.scale);
                        maxY = Math.max(maxY, p.y + mm.height / mm.scale);
                    }
                    return Math.min((loader.width - 4) / maxX, 130 / maxY);
                }

                Item {
                    id: arrCanvas
                    width: loader.width
                    height: 140

                    Repeater {
                        model: Hyprland.monitors
                        delegate: Rectangle {
                            id: monRect
                            property var m: modelData
                            property real lw: m.width / m.scale
                            property real lh: m.height / m.scale
                            property var pos: dispRoot.posFor(m.name, m.x, m.y)
                            property bool dragging: false
                            property real baseX: pos.x * arrColumn.cScale
                            property real baseY: pos.y * arrColumn.cScale
                            property real offX: 0
                            property real offY: 0
                            width: Math.max(28, lw * arrColumn.cScale)
                            height: Math.max(28, lh * arrColumn.cScale)
                            x: baseX + (dragging ? offX : 0)
                            y: baseY + (dragging ? offY : 0)
                            color: dragging ? Theme.accent : Theme.bgAlt
                            border.width: 2
                            border.color: m.focused ? Theme.accent : Theme.border

                            Text {
                                anchors.centerIn: parent
                                text: monRect.m.name
                                color: monRect.dragging ? Theme.bg : Theme.fg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                            }

                            Process { id: moveProc }

                            MouseArea {
                                anchors.fill: parent
                                // Nothing to arrange a single screen relative
                                // to — disabled outright rather than just
                                // no-op-ing onReleased, so it doesn't even
                                // hover/cursor-hint as draggable.
                                enabled: Hyprland.monitors.values.length > 1
                                hoverEnabled: true
                                cursorShape: Qt.SizeAllCursor
                                property real pressX: 0
                                property real pressY: 0
                                onPressed: (mouse) => {
                                    monRect.dragging = true;
                                    pressX = mouse.x;
                                    pressY = mouse.y;
                                }
                                onPositionChanged: (mouse) => {
                                    if (!monRect.dragging) return;
                                    monRect.offX += (mouse.x - pressX);
                                    monRect.offY += (mouse.y - pressY);
                                }
                                onReleased: {
                                    var scale = arrColumn.cScale;
                                    var rawX = (monRect.baseX + monRect.offX) / scale;
                                    var rawY = (monRect.baseY + monRect.offY) / scale;

                                    // Snap to any other monitor's edges within a
                                    // small threshold — hand-aligning pixel-exact
                                    // is otherwise a losing game against a
                                    // ~300px canvas representing a desktop
                                    // that's thousands of pixels wide.
                                    var snapPx = 10 / scale;
                                    var bestX = rawX, bestY = rawY, bestDX = snapPx, bestDY = snapPx;
                                    for (var i = 0; i < Hyprland.monitors.values.length; i++) {
                                        var other = Hyprland.monitors.values[i];
                                        if (other.name === monRect.m.name) continue;
                                        var op = dispRoot.posFor(other.name, other.x, other.y);
                                        var ow = other.width / other.scale, oh = other.height / other.scale;
                                        var xs = [op.x - monRect.lw, op.x, op.x + ow - monRect.lw, op.x + ow];
                                        var ys = [op.y - monRect.lh, op.y, op.y + oh - monRect.lh, op.y + oh];
                                        for (var xi = 0; xi < xs.length; xi++) {
                                            var dx = Math.abs(xs[xi] - rawX);
                                            if (dx < bestDX) { bestDX = dx; bestX = xs[xi]; }
                                        }
                                        for (var yi = 0; yi < ys.length; yi++) {
                                            var dy = Math.abs(ys[yi] - rawY);
                                            if (dy < bestDY) { bestDY = dy; bestY = ys[yi]; }
                                        }
                                    }

                                    var finalX = Math.round(bestX);
                                    var finalY = Math.round(bestY);
                                    monRect.dragging = false;
                                    monRect.offX = 0;
                                    monRect.offY = 0;

                                    var ov = dispRoot.ovr(monRect.m.name);
                                    var ipc = monRect.m.lastIpcObject || ({});
                                    var bitdepth = ov.bitdepth !== undefined ? ov.bitdepth :
                                        ((ipc.currentFormat && ipc.currentFormat.indexOf("2101010") !== -1) ? "10" : "8");
                                    var cm = ov.cm !== undefined ? ov.cm : (ipc.colorManagementPreset || "srgb");
                                    var sdrB = ov.sdrBrightness !== undefined ? ov.sdrBrightness : (ipc.sdrBrightness !== undefined ? ipc.sdrBrightness : 1.0);
                                    var sdrS = ov.sdrSaturation !== undefined ? ov.sdrSaturation : (ipc.sdrSaturation !== undefined ? ipc.sdrSaturation : 1.0);
                                    var vrr = ov.vrr !== undefined ? ov.vrr : !!ipc.vrr;
                                    var icc = ov.icc !== undefined ? ov.icc : "";
                                    var mode = monRect.m.width + "x" + monRect.m.height + "@" + (ipc.refreshRate || 60).toFixed(2) + "Hz";
                                    var tail = mode + "," + finalX + "x" + finalY + "," + monRect.m.scale.toFixed(2)
                                        + ",transform," + (ipc.transform || 0)
                                        + ",bitdepth," + bitdepth
                                        + ",cm," + cm
                                        + ",sdrbrightness," + sdrB.toFixed(2)
                                        + ",sdrsaturation," + sdrS.toFixed(2)
                                        + ",vrr," + (vrr ? "1" : "0")
                                        + (icc.length > 0 ? ",icc," + icc : "");

                                    dispRoot.setOvr(monRect.m.name, {
                                        x: finalX, y: finalY, bitdepth: bitdepth, cm: cm,
                                        sdrBrightness: sdrB, sdrSaturation: sdrS, vrr: vrr, icc: icc
                                    });
                                    moveProc.command = ["display-set", monRect.m.name, tail];
                                    moveProc.running = true;
                                }
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.borderDim }

            Repeater {
                model: Hyprland.monitors
                delegate: Column {
                    id: monDelegate
                    width: loader.width
                    spacing: 8
                    property var mon: modelData
                    property var ipc: mon.lastIpcObject || ({})
                    property var modes: ipc.availableModes || []
                    property var ov: dispRoot.ovr(mon.name)
                    // Picks the mode matching both the current resolution
                    // AND the closest actual refresh rate — matching on
                    // resolution alone (and just taking whichever mode
                    // happened to be listed first for it) was showing
                    // "60Hz" as "current" regardless of what the monitor
                    // was really running at, since 60Hz is what this
                    // monitor's availableModes lists first per resolution.
                    property string selectedMode: {
                        var cur = mon.width + "x" + mon.height;
                        var curRate = ipc.refreshRate || 0;
                        var best = "";
                        var bestDiff = 999999;
                        for (var i = 0; i < monDelegate.modes.length; i++) {
                            var m = monDelegate.modes[i];
                            if (m.indexOf(cur + "@") !== 0) continue;
                            var rate = parseFloat(m.substring(m.indexOf("@") + 1));
                            var diff = Math.abs(rate - curRate);
                            if (diff < bestDiff) { bestDiff = diff; best = m; }
                        }
                        if (best !== "") return best;
                        return monDelegate.modes.length > 0 ? monDelegate.modes[0] : (cur + "@60.00Hz");
                    }
                    property real selectedScale: mon.scale
                    property int selectedTransform: ipc.transform || 0
                    property bool modesOpen: false

                    // Bit depth Hyprland actually requests from the GPU for
                    // this output — 8 or 10 only. Not the monitor panel's
                    // real physical depth (plenty of "8-bit" panels are
                    // 6-bit+FRC underneath): Hyprland has no way to query or
                    // change that, it's fixed in the panel's own hardware.
                    property string selectedBitdepth: monDelegate.ov.bitdepth !== undefined ? monDelegate.ov.bitdepth :
                        ((ipc.currentFormat && ipc.currentFormat.indexOf("2101010") !== -1) ? "10" : "8")
                    property string selectedCm: monDelegate.ov.cm !== undefined ? monDelegate.ov.cm : (ipc.colorManagementPreset || "srgb")
                    property real selectedSdrBrightness: monDelegate.ov.sdrBrightness !== undefined ? monDelegate.ov.sdrBrightness :
                        (ipc.sdrBrightness !== undefined ? ipc.sdrBrightness : 1.0)
                    property real selectedSdrSaturation: monDelegate.ov.sdrSaturation !== undefined ? monDelegate.ov.sdrSaturation :
                        (ipc.sdrSaturation !== undefined ? ipc.sdrSaturation : 1.0)
                    property bool selectedVrr: monDelegate.ov.vrr !== undefined ? monDelegate.ov.vrr : !!ipc.vrr
                    // Never read back from hyprctl (see dispRoot.overrides
                    // comment above) — blank here just means "nothing typed
                    // this session", not "no profile is active".
                    property string selectedIcc: monDelegate.ov.icc !== undefined ? monDelegate.ov.icc : ""

                    Process { id: applyProc; command: [] }

                    Text {
                        text: mon.name + (mon.focused ? "  (focused)" : "")
                        color: mon.focused ? Theme.accent : Theme.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        font.bold: true
                    }
                    Text {
                        text: ipc.description || ""
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                    }

                    // -- Mode picker --
                    Text {
                        text: "Resolution / refresh rate"
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        font.bold: true
                    }
                    Rectangle {
                        width: monDelegate.width
                        height: 30
                        color: modeMa.containsMouse ? Theme.bgAlt : "transparent"
                        border.width: 1
                        border.color: Theme.border
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: monDelegate.selectedMode
                            color: Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: monDelegate.modesOpen ? "▲" : "▼"
                            color: Theme.fgDim
                            font.pixelSize: 10
                        }
                        MouseArea {
                            id: modeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: monDelegate.modesOpen = !monDelegate.modesOpen
                        }
                    }
                    Flickable {
                        visible: monDelegate.modesOpen
                        width: monDelegate.width
                        // Bounded by the actual content height (never a
                        // self-reference back to this Flickable's own
                        // height — that circular binding was collapsing
                        // this to 0 and silently hiding every mode but the
                        // current one) capped at 160 so a long mode list
                        // scrolls instead of growing the flyout forever.
                        height: Math.min(160, modeListCol.height)
                        contentHeight: modeListCol.height
                        clip: true

                        Column {
                            id: modeListCol
                            width: monDelegate.width
                            Repeater {
                                model: monDelegate.modes
                                delegate: Rectangle {
                                    width: monDelegate.width
                                    height: 26
                                    color: modeItemMa.containsMouse ? Theme.bgAlt : "transparent"
                                    border.width: 1
                                    border.color: Theme.borderDim
                                    Text {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: modelData
                                        color: monDelegate.selectedMode === modelData ? Theme.accent : Theme.fg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 11
                                    }
                                    MouseArea {
                                        id: modeItemMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            monDelegate.selectedMode = modelData;
                                            monDelegate.modesOpen = false;
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // -- Scale --
                    Text {
                        text: "Scale: " + monDelegate.selectedScale.toFixed(2) + "x"
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        font.bold: true
                    }
                    Row {
                        spacing: 6
                        Rectangle {
                            width: 30; height: 26
                            color: scaleDownMa.containsMouse ? Theme.bgAlt : "transparent"
                            border.width: 1
                            border.color: Theme.border
                            Text { anchors.centerIn: parent; text: "-"; color: Theme.fg; font.pixelSize: 14 }
                            MouseArea {
                                id: scaleDownMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: monDelegate.selectedScale = Math.max(0.5, Math.round((monDelegate.selectedScale - 0.05) * 100) / 100)
                            }
                        }
                        Rectangle {
                            width: 30; height: 26
                            color: scaleUpMa.containsMouse ? Theme.bgAlt : "transparent"
                            border.width: 1
                            border.color: Theme.border
                            Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.pixelSize: 14 }
                            MouseArea {
                                id: scaleUpMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: monDelegate.selectedScale = Math.min(3.0, Math.round((monDelegate.selectedScale + 0.05) * 100) / 100)
                            }
                        }
                    }

                    // -- Rotation --
                    Text {
                        text: "Rotation"
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        font.bold: true
                    }
                    Row {
                        spacing: 6
                        Repeater {
                            model: [0, 1, 2, 3]
                            delegate: Rectangle {
                                property int t: modelData
                                width: 50; height: 26
                                color: monDelegate.selectedTransform === t ? Theme.accent : (rotMa.containsMouse ? Theme.bgAlt : "transparent")
                                border.width: 1
                                border.color: monDelegate.selectedTransform === t ? Theme.accent : Theme.border
                                Text {
                                    anchors.centerIn: parent
                                    text: [0, 90, 180, 270][t] + "°"
                                    color: monDelegate.selectedTransform === t ? Theme.bg : Theme.fg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                }
                                MouseArea {
                                    id: rotMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: monDelegate.selectedTransform = t
                                }
                            }
                        }
                    }

                    // -- Bit depth --
                    Text {
                        text: "Bit depth"
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        font.bold: true
                    }
                    Row {
                        spacing: 6
                        Repeater {
                            model: ["8", "10"]
                            delegate: Rectangle {
                                property string bd: modelData
                                width: 64; height: 26
                                color: monDelegate.selectedBitdepth === bd ? Theme.accent : (bdMa.containsMouse ? Theme.bgAlt : "transparent")
                                border.width: 1
                                border.color: monDelegate.selectedBitdepth === bd ? Theme.accent : Theme.border
                                Text {
                                    anchors.centerIn: parent
                                    text: bd + "-bit"
                                    color: monDelegate.selectedBitdepth === bd ? Theme.bg : Theme.fg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                }
                                MouseArea {
                                    id: bdMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: monDelegate.selectedBitdepth = bd
                                }
                            }
                        }
                    }

                    // -- Color management preset --
                    Text {
                        text: "Color profile"
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        font.bold: true
                    }
                    Row {
                        spacing: 6
                        Repeater {
                            model: [
                                { v: "srgb", label: "sRGB" },
                                { v: "wide", label: "Wide" },
                                { v: "edid", label: "EDID" },
                                { v: "hdredid", label: "HDR" }
                            ]
                            delegate: Rectangle {
                                property string cv: modelData.v
                                width: (monDelegate.width - 18) / 4; height: 26
                                color: monDelegate.selectedCm === cv ? Theme.accent : (cmMa.containsMouse ? Theme.bgAlt : "transparent")
                                border.width: 1
                                border.color: monDelegate.selectedCm === cv ? Theme.accent : Theme.border
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: monDelegate.selectedCm === cv ? Theme.bg : Theme.fg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 10
                                }
                                MouseArea {
                                    id: cmMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: monDelegate.selectedCm = cv
                                }
                            }
                        }
                    }

                    // -- SDR brightness/saturation -- only meaningful once
                    // the panel isn't running straight sRGB (Hyprland warns
                    // about exactly this: wide/HDR presets need these to
                    // compensate tone-mapping, sRGB doesn't touch them).
                    Text {
                        visible: monDelegate.selectedCm !== "srgb"
                        text: "SDR brightness: " + monDelegate.selectedSdrBrightness.toFixed(2) + "x"
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        font.bold: true
                    }
                    Row {
                        visible: monDelegate.selectedCm !== "srgb"
                        spacing: 6
                        Rectangle {
                            width: 30; height: 26
                            color: sdrBDownMa.containsMouse ? Theme.bgAlt : "transparent"
                            border.width: 1
                            border.color: Theme.border
                            Text { anchors.centerIn: parent; text: "-"; color: Theme.fg; font.pixelSize: 14 }
                            MouseArea {
                                id: sdrBDownMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: monDelegate.selectedSdrBrightness = Math.max(0.1, Math.round((monDelegate.selectedSdrBrightness - 0.05) * 100) / 100)
                            }
                        }
                        Rectangle {
                            width: 30; height: 26
                            color: sdrBUpMa.containsMouse ? Theme.bgAlt : "transparent"
                            border.width: 1
                            border.color: Theme.border
                            Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.pixelSize: 14 }
                            MouseArea {
                                id: sdrBUpMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: monDelegate.selectedSdrBrightness = Math.min(3.0, Math.round((monDelegate.selectedSdrBrightness + 0.05) * 100) / 100)
                            }
                        }
                    }
                    Text {
                        visible: monDelegate.selectedCm !== "srgb"
                        text: "SDR saturation: " + monDelegate.selectedSdrSaturation.toFixed(2) + "x"
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        font.bold: true
                    }
                    Row {
                        visible: monDelegate.selectedCm !== "srgb"
                        spacing: 6
                        Rectangle {
                            width: 30; height: 26
                            color: sdrSDownMa.containsMouse ? Theme.bgAlt : "transparent"
                            border.width: 1
                            border.color: Theme.border
                            Text { anchors.centerIn: parent; text: "-"; color: Theme.fg; font.pixelSize: 14 }
                            MouseArea {
                                id: sdrSDownMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: monDelegate.selectedSdrSaturation = Math.max(0.1, Math.round((monDelegate.selectedSdrSaturation - 0.05) * 100) / 100)
                            }
                        }
                        Rectangle {
                            width: 30; height: 26
                            color: sdrSUpMa.containsMouse ? Theme.bgAlt : "transparent"
                            border.width: 1
                            border.color: Theme.border
                            Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.pixelSize: 14 }
                            MouseArea {
                                id: sdrSUpMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: monDelegate.selectedSdrSaturation = Math.min(2.0, Math.round((monDelegate.selectedSdrSaturation + 0.05) * 100) / 100)
                            }
                        }
                    }

                    // -- ICC profile --
                    Text {
                        text: "ICC profile (optional)"
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        font.bold: true
                    }
                    Row {
                        spacing: 6
                        Rectangle {
                            width: monDelegate.width - 62
                            height: 30
                            color: Theme.bgAlt
                            border.width: 1
                            border.color: Theme.border
                            TextInput {
                                id: iccInput
                                anchors.fill: parent
                                anchors.margins: 8
                                text: monDelegate.selectedIcc
                                onTextEdited: monDelegate.selectedIcc = text
                                color: Theme.fg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                clip: true
                                Text {
                                    visible: iccInput.text.length === 0
                                    text: "/path/to/profile.icc"
                                    color: Theme.fgDim
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                }
                            }
                        }
                        Rectangle {
                            width: 56; height: 30
                            color: clearIccMa.containsMouse ? Theme.bgAlt : "transparent"
                            border.width: 1
                            border.color: Theme.border
                            Text { anchors.centerIn: parent; text: "Clear"; color: Theme.fg; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 10 }
                            MouseArea {
                                id: clearIccMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: monDelegate.selectedIcc = ""
                            }
                        }
                    }

                    // -- VRR --
                    Item {
                        width: monDelegate.width
                        height: 26
                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Variable refresh rate"
                            color: Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }
                        ToggleSwitch {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            checked: monDelegate.selectedVrr
                            onToggled: monDelegate.selectedVrr = !monDelegate.selectedVrr
                        }
                    }

                    // -- Apply --
                    Rectangle {
                        width: monDelegate.width
                        height: 30
                        color: applyMa.containsMouse ? Theme.bgAlt : "transparent"
                        border.width: 2
                        border.color: Theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: "Apply"
                            color: Theme.accent
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            font.bold: true
                        }
                        MouseArea {
                            id: applyMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                var pos = dispRoot.posFor(monDelegate.mon.name, monDelegate.mon.x, monDelegate.mon.y);
                                var tail = monDelegate.selectedMode + "," + pos.x + "x" + pos.y + "," + monDelegate.selectedScale.toFixed(2)
                                    + ",transform," + monDelegate.selectedTransform
                                    + ",bitdepth," + monDelegate.selectedBitdepth
                                    + ",cm," + monDelegate.selectedCm
                                    + ",sdrbrightness," + monDelegate.selectedSdrBrightness.toFixed(2)
                                    + ",sdrsaturation," + monDelegate.selectedSdrSaturation.toFixed(2)
                                    + ",vrr," + (monDelegate.selectedVrr ? "1" : "0")
                                    + (monDelegate.selectedIcc.length > 0 ? ",icc," + monDelegate.selectedIcc : "");

                                dispRoot.setOvr(monDelegate.mon.name, {
                                    x: pos.x, y: pos.y, bitdepth: monDelegate.selectedBitdepth, cm: monDelegate.selectedCm,
                                    sdrBrightness: monDelegate.selectedSdrBrightness, sdrSaturation: monDelegate.selectedSdrSaturation,
                                    vrr: monDelegate.selectedVrr, icc: monDelegate.selectedIcc
                                });
                                applyProc.command = ["display-set", monDelegate.mon.name, tail];
                                applyProc.running = true;
                            }
                        }
                    }

                    Rectangle { width: monDelegate.width; height: 1; color: Theme.border }
                }
            }
        }
    }

    // --- Wallpapers -------------------------------------------------------
    Component {
        id: wallpapersPanel
        Column {
            id: wpCol
            width: loader.width
            spacing: 14
            property var staticImages: []
            property var animatedImages: []
            property string current: ""
            // $HOME/Wallpapers rather than $HOME/Pictures/Wallpapers: this
            // system's locale (pl_PL) means the real Pictures dir is
            // ~/Obrazy, not ~/Pictures — living under $HOME sidesteps that.
            property string wallpapersDir: Quickshell.env("HOME") + "/Wallpapers"

            // Real disk-backed persistence — PersistentProperties turned
            // out not to actually survive a Quickshell restart (verified:
            // no backing file for it exists anywhere on disk), so this
            // reads/writes its own small JSON file under Quickshell's
            // state dir instead.
            Item {
                id: wpSettings
                property string fitMode: "cover"  // static only: cover|contain
                property string muted: "1"        // animated only: 1|0
                property string speed: "1.0"       // animated only
                property string autoPause: "1"     // animated only: 1|0
                property string stateFile: Quickshell.stateDir + "/wallpaper-settings.json"

                function save() {
                    var json = JSON.stringify({
                        fitMode: wpSettings.fitMode,
                        muted: wpSettings.muted,
                        speed: wpSettings.speed,
                        autoPause: wpSettings.autoPause
                    });
                    wpSaveProc.command = ["sh", "-c",
                        "mkdir -p \"$(dirname \"$2\")\" && printf '%s' \"$1\" > \"$2\"",
                        "--", json, wpSettings.stateFile];
                    wpSaveProc.running = true;
                }

                Process { id: wpSaveProc }
                Process {
                    id: wpLoadProc
                    command: ["cat", wpSettings.stateFile]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            try {
                                var d = JSON.parse(text);
                                if (d.fitMode) wpSettings.fitMode = d.fitMode;
                                if (d.muted) wpSettings.muted = d.muted;
                                if (d.speed) wpSettings.speed = d.speed;
                                if (d.autoPause) wpSettings.autoPause = d.autoPause;
                            } catch (e) { /* no state file yet — defaults stand */ }
                        }
                    }
                }
                Component.onCompleted: wpLoadProc.running = true
            }

            function refresh() {
                staticListProc.running = true;
                animatedListProc.running = true;
                currentProc.running = true;
            }

            // Reads back the actually-active wallpaper so the grid can
            // highlight it on open — wpCol.current previously only ever
            // got set by clicking a tile *this session*, so a wallpaper
            // set before Quickshell last restarted (including the normal
            // wallpaper-restore-on-login path) never showed as selected
            // even though it really was active. wallpaper-set's own state
            // file is a real `wallpaper-set <path> ...` command line
            // (shell-quoted via printf %q) — sourcing it with the
            // function shadowed to just echo its first argument is a
            // simple, correct way to pull the path back out without
            // re-implementing shell-quote parsing in JS.
            Process {
                id: currentProc
                command: ["bash", "-c",
                    'wallpaper-set() { printf "%s\\n" "$1"; }; source "$1" 2>/dev/null',
                    "--", Quickshell.env("HOME") + "/.config/hypr/wallpaper.conf"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        var p = text.trim();
                        if (p.length > 0) wpCol.current = p;
                    }
                }
            }

            function apply(path) {
                setProc.command = ["wallpaper-set", path, wpSettings.fitMode,
                    wpSettings.muted, wpSettings.speed, wpSettings.autoPause];
                setProc.running = true;
                wpCol.current = path;
            }

            function deleteWallpaper(path) {
                // Moves to the freedesktop trash (same as Thunar's own
                // delete) rather than `rm`, which would permanently
                // destroy the file with zero undo — there's no confirm
                // dialog on this button, so it needs to be recoverable.
                deleteProc.command = ["wallpaper-delete", path];
                deleteProc.running = true;
            }

            Process {
                id: staticListProc
                command: ["find", wpCol.wallpapersDir, "-maxdepth", "1", "-type", "f",
                    "(", "-iname", "*.jpg", "-o", "-iname", "*.jpeg", "-o", "-iname", "*.png",
                    "-o", "-iname", "*.webp", "-o", "-iname", "*.bmp", ")"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        wpCol.staticImages = text.split("\n").filter((s) => s.length > 0);
                    }
                }
            }
            Process {
                id: animatedListProc
                command: ["find", wpCol.wallpapersDir, "-maxdepth", "1", "-type", "f",
                    "(", "-iname", "*.mp4", "-o", "-iname", "*.webm", "-o", "-iname", "*.mkv",
                    "-o", "-iname", "*.mov", "-o", "-iname", "*.gif", ")"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        wpCol.animatedImages = text.split("\n").filter((s) => s.length > 0);
                        wpCol.refreshThumbs();
                    }
                }
            }

            // path -> cached preview JPEG, filled in by wallpaper-thumbs
            // (modules/scripts/wallpaper-thumbs.sh) once it's generated a
            // real first-frame thumbnail for each animated file — a tile
            // with no entry here just falls back to the play-icon glyph
            // (thumbnail not generated yet, or ffmpeg couldn't read that
            // file). Re-run any time the animated file list changes, not
            // just once, so newly-added videos get a thumbnail without
            // needing a full panel close/reopen.
            property var thumbMap: ({})
            property string thumbCacheDir: Quickshell.cacheDir + "/wallpaper-thumbs"
            function refreshThumbs() {
                if (wpCol.animatedImages.length === 0) return;
                thumbProc.command = ["wallpaper-thumbs", wpCol.thumbCacheDir].concat(wpCol.animatedImages);
                thumbProc.running = true;
            }
            Process {
                id: thumbProc
                stdout: StdioCollector {
                    onStreamFinished: {
                        var map = {};
                        var lines = text.split("\n").filter((s) => s.length > 0);
                        for (var i = 0; i < lines.length; i++) {
                            var parts = lines[i].split("\t");
                            if (parts.length === 2) map[parts[0]] = parts[1];
                        }
                        wpCol.thumbMap = map;
                    }
                }
            }

            Component.onCompleted: wpCol.refresh()

            Process { id: setProc; command: [] }
            Process { id: deleteProc; onExited: wpCol.refresh() }

            Text {
                text: "Add images/videos to " + wpCol.wallpapersDir
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
                wrapMode: Text.WordWrap
                width: wpCol.width
            }

            // -- Search --
            property string filterText: ""
            property var filteredStatic: {
                if (wpCol.filterText.length === 0) return wpCol.staticImages;
                var q = wpCol.filterText.toLowerCase();
                return wpCol.staticImages.filter((p) => p.toLowerCase().indexOf(q) !== -1);
            }
            property var filteredAnimated: {
                if (wpCol.filterText.length === 0) return wpCol.animatedImages;
                var q = wpCol.filterText.toLowerCase();
                return wpCol.animatedImages.filter((p) => p.toLowerCase().indexOf(q) !== -1);
            }
            Rectangle {
                width: wpCol.width
                height: 30
                color: Theme.bgAlt
                border.width: 1
                border.color: Theme.border
                TextInput {
                    id: filterInput
                    anchors.fill: parent
                    anchors.margins: 8
                    text: wpCol.filterText
                    onTextEdited: wpCol.filterText = text
                    color: Theme.fg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    clip: true
                    Text {
                        visible: filterInput.text.length === 0
                        text: "Filter by filename..."
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                    }
                }
            }

            // -- Settings --
            Column {
                width: wpCol.width
                spacing: 8

                Text {
                    text: "SETTINGS"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    font.bold: true
                }

                Rectangle {
                    width: wpCol.width
                    height: 30
                    color: shuffleMa.containsMouse ? Theme.bgAlt : "transparent"
                    border.width: 1
                    border.color: Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: "Shuffle"
                        color: Theme.accent
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        font.bold: true
                    }
                    MouseArea {
                        id: shuffleMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var all = wpCol.staticImages.concat(wpCol.animatedImages);
                            if (all.length === 0) return;
                            wpCol.apply(all[Math.floor(Math.random() * all.length)]);
                        }
                    }
                }

                Text {
                    text: "Fit mode (static images)"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                }
                Row {
                    spacing: 6
                    Repeater {
                        model: ["cover", "contain"]
                        delegate: Rectangle {
                            property string mode: modelData
                            width: 76; height: 26
                            color: wpSettings.fitMode === mode ? Theme.accent : (fitMa.containsMouse ? Theme.bgAlt : "transparent")
                            border.width: 1
                            border.color: wpSettings.fitMode === mode ? Theme.accent : Theme.border
                            Text {
                                anchors.centerIn: parent
                                text: mode
                                color: wpSettings.fitMode === mode ? Theme.bg : Theme.fg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                            }
                            MouseArea {
                                id: fitMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    wpSettings.fitMode = mode;
                                    wpSettings.save();
                                    if (wpCol.current !== "" && wpCol.staticImages.indexOf(wpCol.current) !== -1) wpCol.apply(wpCol.current);
                                }
                            }
                        }
                    }
                }

                Text {
                    text: "Animated wallpaper playback"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                }
                Row {
                    spacing: 6
                    Rectangle {
                        width: 60; height: 26
                        color: wpSettings.muted === "1" ? Theme.accent : (muteMa.containsMouse ? Theme.bgAlt : "transparent")
                        border.width: 1
                        border.color: wpSettings.muted === "1" ? Theme.accent : Theme.border
                        Text {
                            anchors.centerIn: parent
                            text: "Muted"
                            color: wpSettings.muted === "1" ? Theme.bg : Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }
                        MouseArea {
                            id: muteMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { wpSettings.muted = wpSettings.muted === "1" ? "0" : "1"; wpSettings.save(); }
                        }
                    }
                    Rectangle {
                        width: 110; height: 26
                        color: pauseMa.containsMouse ? Theme.bgAlt : "transparent"
                        border.width: 1
                        border.color: wpSettings.autoPause === "1" ? Theme.accent : Theme.border
                        Text {
                            anchors.centerIn: parent
                            text: "Auto-pause"
                            color: wpSettings.autoPause === "1" ? Theme.accent : Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }
                        MouseArea {
                            id: pauseMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { wpSettings.autoPause = wpSettings.autoPause === "1" ? "0" : "1"; wpSettings.save(); }
                        }
                    }
                }
                Row {
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Speed: " + parseFloat(wpSettings.speed).toFixed(2) + "x"
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                    }
                    Rectangle {
                        width: 26; height: 26
                        color: speedDownMa.containsMouse ? Theme.bgAlt : "transparent"
                        border.width: 1
                        border.color: Theme.border
                        Text { anchors.centerIn: parent; text: "-"; color: Theme.fg; font.pixelSize: 14 }
                        MouseArea {
                            id: speedDownMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { wpSettings.speed = String(Math.max(0.25, Math.round((parseFloat(wpSettings.speed) - 0.25) * 100) / 100)); wpSettings.save(); }
                        }
                    }
                    Rectangle {
                        width: 26; height: 26
                        color: speedUpMa.containsMouse ? Theme.bgAlt : "transparent"
                        border.width: 1
                        border.color: Theme.border
                        Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.pixelSize: 14 }
                        MouseArea {
                            id: speedUpMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { wpSettings.speed = String(Math.min(4.0, Math.round((parseFloat(wpSettings.speed) + 0.25) * 100) / 100)); wpSettings.save(); }
                        }
                    }
                }
                Text {
                    visible: wpSettings.muted !== "1" || parseFloat(wpSettings.speed) !== 1.0 || wpSettings.autoPause !== "1"
                    text: "Applies next time you pick an animated wallpaper (or re-click the current one)."
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    wrapMode: Text.WordWrap
                    width: wpCol.width
                }

                Rectangle { width: wpCol.width; height: 1; color: Theme.border }
            }

            Text {
                visible: wpCol.staticImages.length === 0 && wpCol.animatedImages.length === 0
                text: "No wallpapers found"
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
            }
            Text {
                visible: (wpCol.staticImages.length > 0 || wpCol.animatedImages.length > 0)
                    && wpCol.filteredStatic.length === 0 && wpCol.filteredAnimated.length === 0
                text: "No wallpapers match \"" + wpCol.filterText + "\""
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
            }

            Column {
                visible: wpCol.filteredStatic.length > 0
                width: wpCol.width
                spacing: 8

                Text {
                    text: "STATIC"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    font.bold: true
                }

                Flow {
                    width: wpCol.width
                    spacing: 8

                    Repeater {
                        model: wpCol.filteredStatic
                        delegate: Rectangle {
                            id: staticTile
                            property string path: modelData
                            // 2 per row rather than the old fixed 92px (3
                            // cramped columns) — bigger previews are the
                            // whole point of a wallpaper picker.
                            width: (wpCol.width - 8) / 2
                            height: width
                            color: Theme.bgAlt
                            border.width: wpCol.current === path ? 2 : 1
                            border.color: wpCol.current === path ? Theme.accent : Theme.borderDim

                            HoverHandler { id: staticHover }

                            Image {
                                anchors.fill: parent
                                anchors.margins: 2
                                source: "file://" + path
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                clip: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: wpCol.apply(path)
                            }

                            DeleteTileButton {
                                visible: staticHover.hovered
                                onClicked: wpCol.deleteWallpaper(staticTile.path)
                            }
                        }
                    }
                }
            }

            Column {
                visible: wpCol.filteredAnimated.length > 0
                width: wpCol.width
                spacing: 8

                Text {
                    text: "ANIMATED"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 9
                    font.bold: true
                }

                Flow {
                    width: wpCol.width
                    spacing: 8

                    Repeater {
                        model: wpCol.filteredAnimated
                        delegate: Rectangle {
                            id: animTile
                            property string path: modelData
                            property string fileName: path.split("/").pop()
                            property string thumb: wpCol.thumbMap[path] || ""
                            width: (wpCol.width - 8) / 2
                            height: width
                            color: Theme.bgAlt
                            border.width: wpCol.current === path ? 2 : 1
                            border.color: wpCol.current === path ? Theme.accent : Theme.borderDim

                            HoverHandler { id: animHover }

                            // Real first-frame preview once wallpaper-thumbs
                            // has generated one (see wpCol.thumbMap above);
                            // falls back to a play glyph + filename until
                            // then, or if ffmpeg couldn't read that file.
                            Image {
                                id: animThumb
                                anchors.fill: parent
                                anchors.margins: 2
                                source: animTile.thumb.length > 0 ? ("file://" + animTile.thumb) : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                clip: true
                                visible: status === Image.Ready
                            }
                            Text {
                                visible: !animThumb.visible
                                anchors.centerIn: parent
                                text: "▶"
                                color: Theme.fgDim
                                font.pixelSize: 22
                                anchors.verticalCenterOffset: -10
                            }
                            // Small corner badge marking it as a video even
                            // once a real thumbnail is showing — otherwise
                            // it'd be indistinguishable from a static image.
                            Text {
                                visible: animThumb.visible
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 4
                                text: "▶"
                                color: Theme.fg
                                font.pixelSize: 12
                                style: Text.Outline
                                styleColor: Theme.bg
                            }
                            Text {
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 6
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                horizontalAlignment: Text.AlignHCenter
                                text: fileName
                                color: animThumb.visible ? Theme.fg : Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                                elide: Text.ElideMiddle
                                style: animThumb.visible ? Text.Outline : Text.Normal
                                styleColor: Theme.bg
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: wpCol.apply(path)
                            }

                            DeleteTileButton {
                                visible: animHover.hovered
                                onClicked: wpCol.deleteWallpaper(animTile.path)
                            }
                        }
                    }
                }
            }
        }
    }

    // --- Booru (Danbooru, e621, Yande.re, Konachan — Gelbooru/Rule34.xxx
    // need a registered account + API key, skipped for that reason) -------
    // Defaults to Safe content rating; the Content rating tiers (Safe/
    // Moderate/Explicit) control how far that's relaxed. Clicking a result
    // opens a bigger preview rather than downloading immediately —
    // Download is an explicit separate action (saves to downloadsDir, not
    // the Wallpapers folder), and "Set as Wallpaper" only appears once the
    // file actually exists locally.
    Component {
        id: booruPanel
        Column {
            id: booruCol
            width: loader.width
            spacing: 10
            property string query: ""
            // Real disk-backed persistence — PersistentProperties doesn't
            // actually survive a Quickshell restart (verified: no backing
            // file for it exists anywhere on disk), so this reads/writes
            // its own small state file instead, same as wpSettings above.
            Item {
                id: booruSettings
                // "safe" | "moderate" | "explicit" — moderate excludes only
                // explicit-rated posts (allows questionable through),
                // replacing the old binary lewds on/off which couldn't
                // express that middle ground at all.
                property string rating: "safe"
                property string source: "danbooru"
                // "newest" (site default/no tag) | "score" | "random"
                property string sortOrder: "newest"
                property string stateFile: Quickshell.stateDir + "/booru-settings.json"

                function save() {
                    var json = JSON.stringify({
                        rating: booruSettings.rating, source: booruSettings.source,
                        sortOrder: booruSettings.sortOrder
                    });
                    booruSaveProc.command = ["sh", "-c",
                        "mkdir -p \"$(dirname \"$2\")\" && printf '%s' \"$1\" > \"$2\"",
                        "--", json, booruSettings.stateFile];
                    booruSaveProc.running = true;
                }

                Process { id: booruSaveProc }
                Process {
                    id: booruLoadProc
                    command: ["cat", booruSettings.stateFile]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            try {
                                var d = JSON.parse(text);
                                // Migrate the old binary lewds flag for
                                // anyone whose state file predates the
                                // rating tiers — 1 mapped to "no filter at
                                // all" (explicit), 0 to the old default
                                // (safe), same behavior as before just
                                // expressed in the new setting.
                                if (d.rating) booruSettings.rating = d.rating;
                                else if (d.lewds !== undefined) booruSettings.rating = d.lewds === "1" ? "explicit" : "safe";
                                if (d.source) booruSettings.source = d.source;
                                if (d.sortOrder) booruSettings.sortOrder = d.sortOrder;
                                // This load is async (cat running as a
                                // subprocess) while booruCol.doSearch() in
                                // Component.onCompleted below runs
                                // synchronously right on startup — that first
                                // search always fires before this file finishes
                                // loading, using the hardcoded defaults
                                // (Danbooru/Safe/Newest) rather than whatever
                                // was actually saved. Re-run it now that the
                                // real settings are in, or the panel opens
                                // showing the wrong source/rating/sort with no
                                // indication anything's off — as seen live: a
                                // "of 548508" Danbooru page count left over
                                // and displayed under a Konachan-labeled grid.
                                booruCol.doSearch();
                            } catch (e) { /* no state file yet — defaults stand */ }
                        }
                    }
                }
                Component.onCompleted: booruLoadProc.running = true
            }

            // -- Multi-source support --
            // Gelbooru and Rule34.xxx both now require a registered
            // account + API key to use their APIs at all (verified live,
            // both return an auth error with no key) — skipped for that
            // reason, same call as Gelbooru earlier. These four don't
            // need any key.
            //
            // ratingTags: verified live against each API — Danbooru and
            // Yande.re/Konachan (moebooru) write rating tags as full words
            // (rating:general/explicit), e621 uses single-letter codes
            // (rating:s/e) even though the query GRAMMAR is otherwise the
            // same "order:"/"-tag" syntax across all four (also verified
            // live: `tags=order:score` and `tags=-rating:e` both work
            // identically on Danbooru, e621, and moebooru sites).
            readonly property var sources: ({
                danbooru: {
                    label: "Danbooru", hasCount: true, hasAutocomplete: true,
                    ratingTags: { safe: "rating:general", moderate: "-rating:explicit", explicit: "" }
                },
                e621: {
                    label: "e621", hasCount: false, hasAutocomplete: false,
                    ratingTags: { safe: "rating:s", moderate: "-rating:e", explicit: "" }
                },
                yandere: {
                    label: "Yande.re", hasCount: false, hasAutocomplete: false,
                    ratingTags: { safe: "rating:safe", moderate: "-rating:explicit", explicit: "" }
                },
                konachan: {
                    label: "Konachan", hasCount: false, hasAutocomplete: false,
                    ratingTags: { safe: "rating:safe", moderate: "-rating:explicit", explicit: "" }
                }
            })
            readonly property var sourceNames: ["danbooru", "e621", "yandere", "konachan"]
            readonly property string userAgent: "QuickshellBooruPanel/1.0 (by nexoniarz)"

            // Every source has a different JSON shape — this maps whatever
            // came back into one common shape so the rest of the panel
            // (grid, detail view, download) doesn't need to know which
            // source it came from.
            function normalizePost(raw, source) {
                if (source === "danbooru") {
                    if (!raw.file_url || !raw.preview_file_url) return null;
                    return {
                        id: raw.id,
                        previewUrl: raw.preview_file_url,
                        largeUrl: raw.large_file_url || raw.file_url,
                        fileUrl: raw.file_url,
                        fileExt: raw.file_ext || "jpg",
                        rating: raw.rating || "g",
                        tagString: raw.tag_string || "",
                        width: raw.image_width || 0,
                        height: raw.image_height || 0
                    };
                }
                if (source === "e621") {
                    if (!raw.file || !raw.file.url || !raw.preview || !raw.preview.url) return null;
                    var tags = [];
                    if (raw.tags) {
                        for (var cat in raw.tags) tags = tags.concat(raw.tags[cat]);
                    }
                    var r1 = raw.rating === "e" ? "e" : (raw.rating === "q" ? "q" : "g");
                    return {
                        id: raw.id,
                        previewUrl: raw.preview.url,
                        largeUrl: (raw.sample && raw.sample.has && raw.sample.url) ? raw.sample.url : raw.file.url,
                        fileUrl: raw.file.url,
                        fileExt: raw.file.ext || "jpg",
                        rating: r1,
                        tagString: tags.join(" "),
                        width: raw.file.width || 0,
                        height: raw.file.height || 0
                    };
                }
                if (source === "yandere" || source === "konachan") {
                    if (!raw.file_url || !raw.preview_url) return null;
                    var r2 = raw.rating === "e" ? "e" : (raw.rating === "q" ? "q" : "g");
                    return {
                        id: raw.id,
                        previewUrl: raw.preview_url,
                        largeUrl: raw.sample_url || raw.file_url,
                        fileUrl: raw.file_url,
                        fileExt: raw.file_ext || "jpg",
                        rating: r2,
                        tagString: raw.tags || "",
                        width: raw.width || 0,
                        height: raw.height || 0
                    };
                }
                return null;
            }
            property var results: []
            property var selected: null
            property string downloadedPath: ""
            property bool downloading: false
            property bool searching: false
            property string downloadTarget: ""
            property bool previewReady: false
            // Video formats obviously can't decode as an Image — but this
            // Qt build also can't decode webp (confirmed live: "Unsupported
            // image format" even for a plain static one), so it gets the
            // same "no preview, download to view" treatment.
            readonly property bool selectedNoPreview: {
                if (!booruCol.selected) return false;
                var ext = (booruCol.selected.fileExt || "").toLowerCase();
                return ["mp4", "webm", "mov", "avi", "webp"].indexOf(ext) !== -1;
            }
            property string previewLocalPath: ""
            property int page: 1
            // Whether the last fetch came back full — if so there's
            // probably a next page; Danbooru doesn't expose a total count
            // on this endpoint, so "did we get a full page" is the signal.
            property bool hasNextPage: false
            // Downloads land here, NOT directly in Wallpapers — previously
            // every single Download (even ones never actually set as
            // wallpaper) wrote straight into ~/Wallpapers, silently
            // cluttering that picker's grid. "Set as Wallpaper" now copies
            // from here into wallpapersDir explicitly, so only images the
            // user actually chose show up there.
            property string downloadsDir: Quickshell.env("HOME") + "/Booru"
            property string wallpapersDir: Quickshell.env("HOME") + "/Wallpapers"
            // cdn.donmai.us returns 403 to QML's Image networking (its
            // default request looks bot-like to whatever's fronting the
            // CDN) even though plain curl works fine — so thumbnails and
            // previews are fetched via curl into a local cache dir first,
            // and Image only ever points at the local file.
            property string cacheDir: Quickshell.cacheDir + "/booru"

            // Sized to the actual screen instead of a fixed count, so a
            // page of results never grows the flyout past the bottom of
            // the screen (that was cutting images off entirely rather than
            // just needing a scrollbar, since the popup has no scroll area).
            // 2 columns (was 3, at a cramped fixed 92px) — bigger tiles,
            // sized off the panel's real width instead of a hardcoded pixel
            // value.
            readonly property int columns: 2
            readonly property real tileSize: (booruCol.width - 8) / 2
            readonly property real tileSlot: booruCol.tileSize + 8
            property int visibleRows: {
                var screenH = (root.screen && root.screen.height) ? root.screen.height : 1080;
                // Reserve space for the taskbar, the flyout header, the
                // search/rating/sort/source rows above the grid, and
                // margins — bumped from 340 when the old single-row Lewds
                // toggle became two full rating+sort rows with their own
                // labels.
                var reserved = 400;
                return Math.max(2, Math.floor((screenH - reserved) / booruCol.tileSlot));
            }
            property int pageSize: booruCol.columns * booruCol.visibleRows
            // -1 = not known yet (count request still in flight / failed).
            property int totalCount: -1
            property int totalPages: booruCol.totalCount >= 0
                ? Math.max(1, Math.ceil(booruCol.totalCount / booruCol.pageSize)) : -1

            function buildTagsParam() {
                var tagParts = booruCol.query.trim().length > 0
                    ? booruCol.query.trim().split(/\s+/).map(encodeURIComponent)
                    : [];
                var ratingTag = booruCol.sources[booruSettings.source].ratingTags[booruSettings.rating];
                if (ratingTag) tagParts.push(ratingTag);
                // order: is a tag, not a URL param, on all four sources
                // (verified live — a plain ?order= query param is silently
                // ignored on the moebooru sites). Danbooru is the one
                // exception: `order:random` as a TAG reliably times out
                // server-side even scoped to a single rating tag (verified
                // live — "ActiveRecord::QueryCanceled, database timed
                // out"), which read as "Random doesn't work, only Score
                // does" from the UI (empty results). Danbooru has a
                // separate, fast `random=true` URL param specifically to
                // avoid this — handled in fetchPage() instead, so it's
                // deliberately skipped here for danbooru.
                if (booruSettings.sortOrder === "score") tagParts.push("order:score");
                else if (booruSettings.sortOrder === "random" && booruSettings.source !== "danbooru") tagParts.push("order:random");
                return tagParts.join("+");
            }

            function doSearch() {
                booruCol.page = 1;
                booruCol.totalCount = -1;
                var meta = booruCol.sources[booruSettings.source];
                if (meta.hasCount) {
                    var tagsParam = booruCol.buildTagsParam();
                    countProc.command = ["curl", "-s", "-A", booruCol.userAgent,
                        "https://danbooru.donmai.us/counts/posts.json" + (tagsParam ? "?tags=" + tagsParam : "")];
                    countProc.running = true;
                }
                booruCol.fetchPage();
            }

            // -- Tag autocomplete --
            // Suggests based on whatever's after the last space, so
            // completing one tag doesn't disturb tags already typed
            // before it.
            property var suggestions: []

            Timer {
                id: autocompleteTimer
                interval: 250
                repeat: false
                onTriggered: booruCol.fetchSuggestions()
            }

            function currentPartialTag() {
                var text = booruCol.query;
                var lastSpace = text.lastIndexOf(" ");
                return (lastSpace >= 0 ? text.substring(lastSpace + 1) : text).trim();
            }

            function fetchSuggestions() {
                if (!booruCol.sources[booruSettings.source].hasAutocomplete) {
                    booruCol.suggestions = [];
                    return;
                }
                var partial = booruCol.currentPartialTag();
                if (partial.length < 2) {
                    booruCol.suggestions = [];
                    return;
                }
                var url = "https://danbooru.donmai.us/autocomplete.json?search%5Bquery%5D="
                    + encodeURIComponent(partial) + "&search%5Btype%5D=tag_query&limit=8";
                // If a previous keystroke's request is still in flight (curl
                // hasn't returned yet), reassigning .command and setting
                // .running = true on an already-running Process is a no-op
                // — running:true -> true is not a change, so nothing
                // restarts and the newer query silently never gets sent.
                // That's the "sometimes works, sometimes not" flakiness:
                // explicitly stop it first so the new request actually
                // fires.
                if (autocompleteProc.running) autocompleteProc.running = false;
                autocompleteProc.requestedPartial = partial;
                autocompleteProc.command = ["curl", "-s", "-A", booruCol.userAgent, url];
                autocompleteProc.running = true;
            }

            function applySuggestion(value) {
                var text = booruCol.query;
                var lastSpace = text.lastIndexOf(" ");
                var prefix = lastSpace >= 0 ? text.substring(0, lastSpace + 1) : "";
                booruCol.query = prefix + value + " ";
                queryField.text = booruCol.query;
                queryField.cursorPosition = queryField.text.length;
                booruCol.suggestions = [];
                queryField.forceActiveFocus();
            }

            function fetchPage() {
                var tagsParam = booruCol.buildTagsParam();
                var tagsQuery = tagsParam ? "&tags=" + tagsParam : "";
                var url = "";
                switch (booruSettings.source) {
                case "danbooru":
                    url = "https://danbooru.donmai.us/posts.json?limit=" + booruCol.pageSize + "&page=" + booruCol.page + tagsQuery;
                    // Fast path around the order:random timeout (see
                    // buildTagsParam) — Danbooru's own random=true redirects
                    // to a URL with real random ordering baked in, which is
                    // cheap; page doesn't really apply to "a random
                    // sample," so it's left out for this one request.
                    if (booruSettings.sortOrder === "random") url = "https://danbooru.donmai.us/posts.json?limit=" + booruCol.pageSize + "&random=true" + tagsQuery;
                    break;
                case "e621":
                    url = "https://e621.net/posts.json?limit=" + booruCol.pageSize + "&page=" + booruCol.page + tagsQuery;
                    break;
                case "yandere":
                    url = "https://yande.re/post.json?limit=" + booruCol.pageSize + "&page=" + booruCol.page + tagsQuery;
                    break;
                case "konachan":
                    url = "https://konachan.com/post.json?limit=" + booruCol.pageSize + "&page=" + booruCol.page + tagsQuery;
                    break;
                }
                searchProc.requestedSource = booruSettings.source;
                // -L: danbooru's random=true responds with a redirect —
                // without following it, that request comes back as an
                // empty body (verified live).
                searchProc.command = ["curl", "-s", "-L", "-A", booruCol.userAgent, url];
                booruCol.searching = true;
                booruCol.results = [];
                searchProc.running = true;
            }

            Process { id: mkdirProc; command: ["mkdir", "-p", booruCol.cacheDir, booruCol.downloadsDir] }
            Component.onCompleted: {
                mkdirProc.running = true;
                booruCol.doSearch();
            }

            Process {
                id: searchProc
                property string requestedSource: ""
                stdout: StdioCollector {
                    onStreamFinished: {
                        var rawPosts = [];
                        try {
                            var data = JSON.parse(text);
                            if (searchProc.requestedSource === "e621") {
                                rawPosts = (data && Array.isArray(data.posts)) ? data.posts : [];
                            } else {
                                rawPosts = Array.isArray(data) ? data : [];
                            }
                        } catch (e) { rawPosts = []; }

                        var posts = [];
                        for (var i = 0; i < rawPosts.length; i++) {
                            var n = booruCol.normalizePost(rawPosts[i], searchProc.requestedSource);
                            if (n) posts.push(n);
                        }

                        booruCol.hasNextPage = booruCol.totalPages >= 0
                            ? booruCol.page < booruCol.totalPages
                            : posts.length >= booruCol.pageSize;

                        if (posts.length === 0) {
                            booruCol.searching = false;
                            booruCol.results = [];
                            return;
                        }

                        var cmd = ["curl", "-s"];
                        for (var j = 0; j < posts.length; j++) {
                            posts[j].localThumb = booruCol.cacheDir + "/thumb_" + searchProc.requestedSource + "_" + posts[j].id + ".jpg";
                            cmd.push(posts[j].previewUrl);
                            cmd.push("-o");
                            cmd.push(posts[j].localThumb);
                        }
                        thumbProc.pendingResults = posts;
                        thumbProc.command = cmd;
                        thumbProc.running = true;
                    }
                }
            }
            Process {
                id: thumbProc
                property var pendingResults: []
                onExited: {
                    booruCol.searching = false;
                    booruCol.results = thumbProc.pendingResults;
                }
            }
            Process {
                id: countProc
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            var d = JSON.parse(text);
                            booruCol.totalCount = d.counts.posts;
                        } catch (e) { booruCol.totalCount = -1; }
                    }
                }
            }
            Process {
                id: autocompleteProc
                property string requestedPartial: ""
                stdout: StdioCollector {
                    onStreamFinished: {
                        // Drop stale responses: even with the running-guard
                        // above, a slow request can still resolve after a
                        // faster, newer one — without this check whichever
                        // curl happens to finish last wins, regardless of
                        // which one actually matches what's typed now.
                        if (autocompleteProc.requestedPartial !== booruCol.currentPartialTag()) return;
                        try {
                            var d = JSON.parse(text);
                            booruCol.suggestions = Array.isArray(d) ? d : [];
                        } catch (e) { booruCol.suggestions = []; }
                    }
                }
            }

            Process {
                id: previewProc
                onExited: (code) => {
                    if (code === 0) booruCol.previewReady = true;
                }
            }

            Process {
                id: downloadProc
                onExited: (code) => {
                    booruCol.downloading = false;
                    if (code === 0) booruCol.downloadedPath = booruCol.downloadTarget;
                }
            }

            property bool wallpaperSetDone: false
            Process {
                id: setWpProc
                command: []
                onExited: (code) => { if (code === 0) booruCol.wallpaperSetDone = true; }
            }

            // -- Search bar --
            Row {
                width: booruCol.width
                spacing: 6
                Rectangle {
                    width: parent.width - 66
                    height: 30
                    color: Theme.bgAlt
                    border.width: 1
                    border.color: Theme.border
                    TextInput {
                        id: queryField
                        anchors.fill: parent
                        anchors.margins: 8
                        color: Theme.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        text: booruCol.query
                        onTextChanged: {
                            booruCol.query = text;
                            autocompleteTimer.restart();
                        }
                        Keys.onReturnPressed: {
                            booruCol.suggestions = [];
                            booruCol.doSearch();
                        }
                        Keys.onEscapePressed: booruCol.suggestions = []
                    }
                }
                Rectangle {
                    width: 60
                    height: 30
                    color: searchMa.containsMouse ? Theme.bgAlt : "transparent"
                    border.width: 1
                    border.color: Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: "Search"
                        color: Theme.accent
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                    }
                    MouseArea {
                        id: searchMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { booruCol.suggestions = []; booruCol.doSearch(); }
                    }
                }
            }

            Column {
                visible: booruCol.suggestions.length > 0
                width: booruCol.width
                spacing: 2

                Repeater {
                    model: booruCol.suggestions
                    delegate: Rectangle {
                        property var sug: modelData
                        width: booruCol.width
                        height: 24
                        color: sugMa.containsMouse ? Theme.bgAlt : Theme.bgAlt2
                        border.width: 1
                        border.color: Theme.borderDim
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: sug.label
                            color: Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: sug.post_count
                            color: Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                        }
                        MouseArea {
                            id: sugMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: booruCol.applySuggestion(sug.value)
                        }
                    }
                }
            }

            // Replaces the old binary Lewds on/off — "moderate" lets
            // questionable-rated posts through while still excluding
            // explicit, a middle ground the old toggle couldn't express.
            Text {
                text: "Content rating"
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                font.bold: true
            }
            Row {
                spacing: 6
                Repeater {
                    model: [
                        { v: "safe", label: "Safe" },
                        { v: "moderate", label: "Moderate" },
                        { v: "explicit", label: "Explicit" }
                    ]
                    delegate: Rectangle {
                        property string rv: modelData.v
                        readonly property bool active: booruSettings.rating === rv
                        width: (booruCol.width - 12) / 3; height: 26
                        color: active ? (rv === "explicit" ? Theme.danger : Theme.accent) : (ratingMa.containsMouse ? Theme.bgAlt : "transparent")
                        border.width: 1
                        border.color: active ? (rv === "explicit" ? Theme.danger : Theme.accent) : Theme.border
                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: active ? Theme.bg : Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            font.bold: true
                        }
                        MouseArea {
                            id: ratingMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (booruSettings.rating === rv) return;
                                // save() here, not just the property
                                // assignment: this rating setting not
                                // sticking on its own (only saving as a
                                // side effect of also switching source
                                // afterward) was a real persistence bug on
                                // the old Lewds toggle — keep saving
                                // explicitly so it can't regress the same way.
                                booruSettings.rating = rv;
                                booruSettings.save();
                                booruCol.doSearch();
                            }
                        }
                    }
                }
            }

            Text {
                text: "Sort"
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
                font.bold: true
            }
            Row {
                spacing: 6
                Repeater {
                    model: [
                        { v: "newest", label: "Newest" },
                        { v: "score", label: "Score" },
                        { v: "random", label: "Random" }
                    ]
                    delegate: Rectangle {
                        property string sv: modelData.v
                        readonly property bool active: booruSettings.sortOrder === sv
                        width: (booruCol.width - 12) / 3; height: 26
                        color: active ? Theme.accent : (sortMa.containsMouse ? Theme.bgAlt : "transparent")
                        border.width: 1
                        border.color: active ? Theme.accent : Theme.border
                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: active ? Theme.bg : Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                        }
                        MouseArea {
                            id: sortMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (booruSettings.sortOrder === sv) return;
                                booruSettings.sortOrder = sv;
                                booruSettings.save();
                                booruCol.doSearch();
                            }
                        }
                    }
                }
            }

            Row {
                spacing: 6
                Repeater {
                    model: booruCol.sourceNames
                    delegate: Rectangle {
                        property string src: modelData
                        width: 62; height: 22
                        color: booruSettings.source === src ? Theme.accent : (srcMa.containsMouse ? Theme.bgAlt : "transparent")
                        border.width: 1
                        border.color: booruSettings.source === src ? Theme.accent : Theme.border
                        Text {
                            anchors.centerIn: parent
                            text: booruCol.sources[src].label
                            color: booruSettings.source === src ? Theme.bg : Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 9
                        }
                        MouseArea {
                            id: srcMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (booruSettings.source === src) return;
                                booruSettings.source = src;
                                booruSettings.save();
                                booruCol.selected = null;
                                booruCol.suggestions = [];
                                booruCol.doSearch();
                            }
                        }
                    }
                }
            }

            // -- Grid / detail --
            Loader {
                width: booruCol.width
                sourceComponent: booruCol.selected ? booruDetail : booruGrid
            }

            Component {
                id: booruGrid
                Column {
                    width: booruCol.width
                    spacing: 8
                    Text {
                        visible: booruCol.searching
                        text: "Searching..."
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                    }
                    Text {
                        visible: !booruCol.searching && booruCol.results.length === 0
                        text: "No results"
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                    }
                    Flow {
                        width: booruCol.width
                        spacing: 8
                        Repeater {
                            model: booruCol.results
                            delegate: Rectangle {
                                property var post: modelData
                                width: booruCol.tileSize
                                height: booruCol.tileSize
                                color: Theme.bgAlt
                                border.width: 1
                                border.color: (post.rating === "e" || post.rating === "q") ? Theme.danger : Theme.borderDim
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 2
                                    source: "file://" + post.localThumb
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    clip: true
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        booruCol.selected = post;
                                        booruCol.downloadedPath = "";
                                        booruCol.wallpaperSetDone = false;
                                        booruCol.previewReady = false;
                                        var ext = (post.fileExt || "jpg").toLowerCase();
                                        // Image can't decode video files (largeUrl for a
                                        // video post IS the video itself, not a still
                                        // frame) or, on this Qt build, webp — so skip the
                                        // preview fetch entirely for those rather than
                                        // trying (and failing) to load it.
                                        if (["mp4", "webm", "mov", "avi", "webp"].indexOf(ext) !== -1) {
                                            booruCol.previewLocalPath = "";
                                            return;
                                        }
                                        var previewPath = booruCol.cacheDir + "/preview_" + booruSettings.source + "_" + post.id + "." + ext;
                                        booruCol.previewLocalPath = previewPath;
                                        previewProc.command = ["curl", "-s", post.largeUrl, "-o", previewPath];
                                        previewProc.running = true;
                                    }
                                }
                            }
                        }
                    }

                    // -- Pagination --
                    // Flow, not Row: Row lays out children at their natural
                    // width regardless of the width assigned to the Row
                    // itself, so when Prev + "Page" + the page field + "of
                    // N" + Next added up to more than booruCol.width (which
                    // happened often enough — "of N" varies in width with
                    // page count, and it was already close to the edge) the
                    // Next button rendered past the flyout's right edge,
                    // off the visible screen. Flow wraps overflow onto a
                    // second line instead of spilling past the edge.
                    Flow {
                        // Danbooru's random=true (see fetchPage) is a fresh
                        // random sample every request, not a real page
                        // sequence — no &page= param is even sent for it, so
                        // "Page N"/Next wouldn't actually mean anything there.
                        readonly property bool isDanbooruRandom: booruSettings.source === "danbooru" && booruSettings.sortOrder === "random"
                        visible: !booruCol.searching && !isDanbooruRandom && (booruCol.page > 1 || booruCol.hasNextPage)
                        width: booruCol.width
                        spacing: 8
                        Rectangle {
                            width: 70; height: 26
                            opacity: booruCol.page > 1 ? 1 : 0.4
                            color: prevMa.containsMouse ? Theme.bgAlt : "transparent"
                            border.width: 1
                            border.color: Theme.border
                            Text {
                                anchors.centerIn: parent
                                text: "< Prev"
                                color: Theme.fg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                            }
                            MouseArea {
                                id: prevMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (booruCol.page <= 1) return;
                                    booruCol.page -= 1;
                                    booruCol.fetchPage();
                                }
                            }
                        }
                        // Flow does NOT support anchors on its direct children —
                        // Qt silently disables the ENTIRE Flow's layout the
                        // moment it sees one ("Flow will not function", logged
                        // as a warning), collapsing/overlapping every control
                        // in it. This is why pagination looked broken/missing:
                        // the three anchored items below were direct Flow
                        // children. Fix: push the anchor one level down into a
                        // plain Item wrapper, which Flow lays out normally.
                        Item {
                            width: pageLabelText.implicitWidth
                            height: 26
                            Text {
                                id: pageLabelText
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Page"
                                color: Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                            }
                        }
                        Rectangle {
                            width: 40; height: 26
                            color: Theme.bgAlt
                            border.width: 1
                            border.color: Theme.border
                            TextInput {
                                id: pageField
                                anchors.fill: parent
                                anchors.margins: 4
                                horizontalAlignment: TextInput.AlignHCenter
                                color: Theme.fg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                text: String(booruCol.page)
                                validator: IntValidator { bottom: 1; top: 999999 }
                                Keys.onReturnPressed: {
                                    var n = parseInt(pageField.text);
                                    if (isNaN(n) || n < 1) { pageField.text = String(booruCol.page); return; }
                                    booruCol.page = booruCol.totalPages > 0 ? Math.min(n, booruCol.totalPages) : n;
                                    booruCol.fetchPage();
                                }
                            }
                        }
                        Item {
                            visible: booruCol.totalPages > 0
                            width: ofPagesText.implicitWidth
                            height: 26
                            Text {
                                id: ofPagesText
                                anchors.verticalCenter: parent.verticalCenter
                                text: booruCol.totalPages > 0 ? ("of " + booruCol.totalPages) : ""
                                color: Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                            }
                        }
                        Rectangle {
                            width: 70; height: 26
                            opacity: booruCol.hasNextPage ? 1 : 0.4
                            color: nextMa.containsMouse ? Theme.bgAlt : "transparent"
                            border.width: 1
                            border.color: Theme.border
                            Text {
                                anchors.centerIn: parent
                                text: "Next >"
                                color: Theme.fg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                            }
                            MouseArea {
                                id: nextMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (!booruCol.hasNextPage) return;
                                    booruCol.page += 1;
                                    booruCol.fetchPage();
                                }
                            }
                        }
                    }
                }
            }

            Component {
                id: booruDetail
                Column {
                    width: booruCol.width
                    spacing: 8

                    Rectangle {
                        width: 60
                        height: 26
                        color: backMa.containsMouse ? Theme.bgAlt : "transparent"
                        border.width: 1
                        border.color: Theme.border
                        Text {
                            anchors.centerIn: parent
                            text: "< Back"
                            color: Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                        }
                        MouseArea {
                            id: backMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: booruCol.selected = null
                        }
                    }

                    Rectangle {
                        width: booruCol.width
                        height: 240
                        color: "#000000"
                        border.width: 1
                        border.color: Theme.borderDim
                        clip: true
                        Image {
                            anchors.fill: parent
                            source: booruCol.previewReady ? ("file://" + booruCol.previewLocalPath) : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }
                        Text {
                            visible: !booruCol.previewReady && !booruCol.selectedNoPreview
                            anchors.centerIn: parent
                            text: "Loading preview..."
                            color: Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }
                        Text {
                            visible: booruCol.selectedNoPreview
                            anchors.centerIn: parent
                            text: "Video post — no preview.\nDownload to view it."
                            horizontalAlignment: Text.AlignHCenter
                            color: Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }
                    }

                    Text {
                        visible: !!booruCol.selected
                        text: booruCol.selected
                            ? (booruCol.selected.width + "x" + booruCol.selected.height + " · rating: " + booruCol.selected.rating)
                            : ""
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                    }
                    Text {
                        visible: !!(booruCol.selected && booruCol.selected.tagString)
                        text: booruCol.selected ? booruCol.selected.tagString : ""
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        wrapMode: Text.WordWrap
                        width: booruCol.width
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }

                    Rectangle {
                        width: booruCol.width
                        height: 30
                        color: dlMa.containsMouse ? Theme.bgAlt : "transparent"
                        border.width: 2
                        border.color: Theme.accent
                        opacity: booruCol.downloading ? 0.6 : 1
                        Text {
                            anchors.centerIn: parent
                            text: booruCol.downloading ? "Downloading..." : (booruCol.downloadedPath !== "" ? "Downloaded" : "Download")
                            color: Theme.accent
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            font.bold: true
                        }
                        MouseArea {
                            id: dlMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (booruCol.downloading || booruCol.downloadedPath !== "" || !booruCol.selected) return;
                                var post = booruCol.selected;
                                var ext = post.fileExt || "jpg";
                                var target = booruCol.downloadsDir + "/" + booruSettings.source + "_" + post.id + "." + ext;
                                booruCol.downloadTarget = target;
                                downloadProc.command = ["curl", "-sL", post.fileUrl, "-o", target];
                                booruCol.downloading = true;
                                downloadProc.running = true;
                            }
                        }
                    }

                    Rectangle {
                        visible: booruCol.downloadedPath !== ""
                        width: booruCol.width
                        height: 30
                        color: setMa.containsMouse ? Theme.bgAlt : "transparent"
                        border.width: 1
                        border.color: Theme.border
                        Text {
                            anchors.centerIn: parent
                            text: booruCol.wallpaperSetDone ? "Wallpaper set!" : "Set as Wallpaper"
                            color: booruCol.wallpaperSetDone ? Theme.accent : Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: setMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!booruCol.selected) return;
                                var post = booruCol.selected;
                                var ext = post.fileExt || "jpg";
                                // Downloaded files live in downloadsDir now, not
                                // wallpapersDir directly (see downloadsDir
                                // comment above) — copy into wallpapersDir only
                                // on this explicit action, then apply it.
                                var wpTarget = booruCol.wallpapersDir + "/" + booruSettings.source + "_" + post.id + "." + ext;
                                setWpProc.command = ["sh", "-c",
                                    'cp "$1" "$2" && wallpaper-set "$2"',
                                    "--", booruCol.downloadedPath, wpTarget];
                                setWpProc.running = true;
                            }
                        }
                    }
                }
            }
        }
    }

    // --- Cursor -------------------------------------------------------
    Component {
        id: cursorPanel
        Column {
            id: cursorCol
            spacing: 6
            width: loader.width
            property var themes: []
            property bool previewsReady: false
            // Xcursor files are a binary format, not something Image can
            // load directly — cursor-preview-all renders a PNG per theme
            // into this cache dir (skipping ones already rendered).
            property string previewDir: Quickshell.cacheDir + "/cursors"

            Process {
                id: listThemesProc
                command: ["list-cursor-themes"]
                stdout: StdioCollector {
                    onStreamFinished: cursorCol.themes = text.split("\n").filter((s) => s.length > 0)
                }
            }
            Process {
                id: previewGenProc
                command: ["cursor-preview-all", cursorCol.previewDir]
                onExited: cursorCol.previewsReady = true
            }
            Component.onCompleted: {
                listThemesProc.running = true;
                previewGenProc.running = true;
            }

            Process { id: applyProc; command: [] }

            Text {
                text: "Click a theme to apply"
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
            }
            Text {
                visible: cursorCol.themes.length === 0
                text: "No cursor themes found"
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
            }

            Repeater {
                model: cursorCol.themes
                delegate: Rectangle {
                    id: curTile
                    property string themeName: modelData
                    property string previewSrc: cursorCol.previewsReady
                        ? "file://" + cursorCol.previewDir + "/" + themeName + ".png" : ""
                    width: loader.width
                    height: 36
                    color: curMa.containsMouse ? Theme.bgAlt : "transparent"
                    border.width: 1
                    border.color: Theme.borderDim

                    IconImage {
                        id: curIcon
                        visible: curTile.previewSrc !== "" && status === Image.Ready
                        implicitSize: 24
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        source: curTile.previewSrc
                    }
                    Text {
                        anchors.left: curIcon.visible ? curIcon.right : parent.left
                        anchors.leftMargin: curIcon.visible ? 8 : 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: curTile.themeName
                        color: Theme.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: curMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { applyProc.command = ["cursor-set", curTile.themeName]; applyProc.running = true; }
                    }
                }
            }
        }
    }
}
