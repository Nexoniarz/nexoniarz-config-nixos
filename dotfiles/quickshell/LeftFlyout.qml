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
    // Mode/scale/rotation are edited locally per monitor (starting from its
    // current live values) and only actually applied when "Apply" is
    // clicked, via `hyprctl keyword monitor ...` — same mechanism Hyprland
    // itself uses, so it's an immediate, real change, not a config-file edit.
    Component {
        id: settingsPanel
        Column {
            width: loader.width
            spacing: 16

            Text {
                visible: Hyprland.monitors.values.length === 0
                text: "No monitor data"
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
            }

            Repeater {
                model: Hyprland.monitors
                delegate: Column {
                    id: monDelegate
                    width: loader.width
                    spacing: 8
                    property var mon: modelData
                    property var ipc: mon.lastIpcObject || ({})
                    property var modes: ipc.availableModes || []
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
                                applyProc.command = ["display-set", monDelegate.mon.name,
                                    monDelegate.selectedMode, String(monDelegate.mon.x), String(monDelegate.mon.y),
                                    monDelegate.selectedScale.toFixed(2), String(monDelegate.selectedTransform)];
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

            Column {
                visible: wpCol.staticImages.length > 0
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
                        model: wpCol.staticImages
                        delegate: Rectangle {
                            id: staticTile
                            property string path: modelData
                            width: 92
                            height: 92
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
                visible: wpCol.animatedImages.length > 0
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
                        model: wpCol.animatedImages
                        delegate: Rectangle {
                            id: animTile
                            property string path: modelData
                            property string fileName: path.split("/").pop()
                            width: 92
                            height: 92
                            color: Theme.bgAlt
                            border.width: wpCol.current === path ? 2 : 1
                            border.color: wpCol.current === path ? Theme.accent : Theme.borderDim

                            HoverHandler { id: animHover }

                            // No live thumbnail for video files — a play
                            // glyph + filename instead of the expense/
                            // complexity of extracting a preview frame.
                            Text {
                                anchors.centerIn: parent
                                text: "▶"
                                color: Theme.fgDim
                                font.pixelSize: 22
                                anchors.verticalCenterOffset: -10
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
                                color: Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 9
                                elide: Text.ElideMiddle
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

    // --- Booru (Danbooru only for now — Gelbooru's API needs an account
    // API key which hasn't been set up) ------------------------------------
    // Defaults to safe content (rating:general appended to the tag query);
    // the Lewds toggle removes that restriction. Clicking a result opens a
    // bigger preview rather than downloading immediately — Download is an
    // explicit separate action, and "Set as Wallpaper" only appears once
    // the file actually exists locally.
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
                property string lewds: "0"
                property string source: "danbooru"
                property string stateFile: Quickshell.stateDir + "/booru-settings.json"

                function save() {
                    var json = JSON.stringify({ lewds: booruSettings.lewds, source: booruSettings.source });
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
                                if (d.lewds) booruSettings.lewds = d.lewds;
                                if (d.source) booruSettings.source = d.source;
                            } catch (e) { /* no state file yet — defaults stand */ }
                        }
                    }
                }
                Component.onCompleted: booruLoadProc.running = true
            }
            readonly property bool lewds: booruSettings.lewds === "1"

            // -- Multi-source support --
            // Gelbooru and Rule34.xxx both now require a registered
            // account + API key to use their APIs at all (verified live,
            // both return an auth error with no key) — skipped for that
            // reason, same call as Gelbooru earlier. These four don't
            // need any key.
            readonly property var sources: ({
                danbooru: { label: "Danbooru", safeTag: "rating:general", hasCount: true, hasAutocomplete: true },
                e621: { label: "e621", safeTag: "rating:s", hasCount: false, hasAutocomplete: false },
                yandere: { label: "Yande.re", safeTag: "rating:safe", hasCount: false, hasAutocomplete: false },
                konachan: { label: "Konachan", safeTag: "rating:safe", hasCount: false, hasAutocomplete: false }
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
            // $HOME/Wallpapers, same folder the Wallpapers panel reads from
            // — a downloaded post shows up there automatically.
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
            readonly property int columns: 3
            readonly property int tileSlot: 100 // 92px tile + 8px spacing
            property int visibleRows: {
                var screenH = (root.screen && root.screen.height) ? root.screen.height : 1080;
                // Reserve space for the taskbar, the flyout header, the
                // search/lewds/source rows above the grid, and margins.
                var reserved = 340;
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
                if (!booruCol.lewds) tagParts.push(booruCol.sources[booruSettings.source].safeTag);
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
                searchProc.command = ["curl", "-s", "-A", booruCol.userAgent, url];
                booruCol.searching = true;
                booruCol.results = [];
                searchProc.running = true;
            }

            Process { id: mkdirProc; command: ["mkdir", "-p", booruCol.cacheDir] }
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

            Process { id: setWpProc; command: [] }

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

            Row {
                spacing: 8
                Rectangle {
                    width: 80
                    height: 26
                    color: booruCol.lewds ? Theme.danger : (lewdMa.containsMouse ? Theme.bgAlt : "transparent")
                    border.width: 1
                    border.color: Theme.danger
                    Text {
                        anchors.centerIn: parent
                        text: booruCol.lewds ? "Lewds: ON" : "Lewds"
                        color: booruCol.lewds ? Theme.bg : Theme.danger
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        font.bold: true
                    }
                    MouseArea {
                        id: lewdMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // save() here, not just the property assignment:
                            // this was the actual persistence bug — toggling
                            // Lewds never wrote to disk on its own, only the
                            // source-switcher below called save(). So Lewds
                            // only ever "stuck" as a side effect of also
                            // switching source afterward, and turning it
                            // back off never stuck at all — reopening Booru
                            // always reloaded whatever was last written that
                            // way instead of the toggle's actual state.
                            booruSettings.lewds = booruCol.lewds ? "0" : "1";
                            booruSettings.save();
                            booruCol.doSearch();
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
                                width: 92
                                height: 92
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
                        visible: !booruCol.searching && (booruCol.page > 1 || booruCol.hasNextPage)
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
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Page"
                            color: Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
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
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: booruCol.totalPages > 0 ? ("of " + booruCol.totalPages) : ""
                            color: Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
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
                                var target = booruCol.wallpapersDir + "/" + booruSettings.source + "_" + post.id + "." + ext;
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
                            text: "Set as Wallpaper"
                            color: Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: setMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                setWpProc.command = ["wallpaper-set", booruCol.downloadedPath];
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
