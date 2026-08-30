import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pipewire

// On-screen display: a themed top-center popup (same placement/layer-shell
// pattern as PolkitDialog and mako notifications) for volume, mic mute,
// brightness, and media changes — the transient overlay every other DE
// shows instead of making you open a panel to check.
//
// Volume/mic react directly to Pipewire, so they fire for ANY change
// (function keys, the RightBar sliders, pavucontrol, etc.), not just ones
// that went through our own keybinds. Brightness has no such live service
// to bind to (DDC/CI writes aren't broadcast anywhere), so its two
// hyprland.conf binds explicitly call `quickshell ipc call osd
// brightness <pct>` after brightness-ctl. Media is driven by two
// long-running `playerctl --follow` processes (status, and metadata for
// track-change detection).
Item {
    id: root

    property string osdText: ""
    property bool showBar: false
    property real barValue: 0
    property bool barDanger: false

    function present(text, bar, value, danger) {
        root.osdText = text;
        root.showBar = bar;
        root.barValue = value || 0;
        root.barDanger = !!danger;
        osdWindow.visible = true;
        hideTimer.restart();
    }

    IpcHandler {
        target: "osd"
        function brightness(pct: string): void {
            var v = parseInt(pct);
            if (isNaN(v)) return;
            root.present("Brightness " + v + "%", true, v / 100, false);
        }
    }

    Timer {
        id: hideTimer
        interval: 1600
        onTriggered: osdWindow.visible = false
    }

    // -- Volume / mic --
    PwObjectTracker {
        objects: {
            var arr = [];
            if (Pipewire.defaultAudioSink) arr.push(Pipewire.defaultAudioSink);
            if (Pipewire.defaultAudioSource) arr.push(Pipewire.defaultAudioSource);
            return arr;
        }
    }

    // Pipewire reports the already-current volume/mute state once as soon
    // as it connects — without these guards that fires an OSD on every
    // Quickshell start/login, not just on real changes.
    property bool sinkReady: false
    property bool sourceReady: false

    Connections {
        target: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null
        function onVolumesChanged() {
            if (!root.sinkReady) { root.sinkReady = true; return; }
            var sink = Pipewire.defaultAudioSink;
            if (sink.audio.muted) return; // covered by onMutedChanged instead
            root.present("Volume " + Math.round(sink.audio.volume * 100) + "%", true, sink.audio.volume, false);
        }
        function onMutedChanged() {
            if (!root.sinkReady) { root.sinkReady = true; return; }
            var sink = Pipewire.defaultAudioSink;
            root.present(sink.audio.muted ? "Volume Muted" : "Volume " + Math.round(sink.audio.volume * 100) + "%",
                !sink.audio.muted, sink.audio.volume, sink.audio.muted);
        }
    }
    Connections {
        target: Pipewire.defaultAudioSource ? Pipewire.defaultAudioSource.audio : null
        function onMutedChanged() {
            if (!root.sourceReady) { root.sourceReady = true; return; }
            var source = Pipewire.defaultAudioSource;
            root.present(source.audio.muted ? "Microphone Muted" : "Microphone Unmuted",
                false, 0, source.audio.muted);
        }
    }

    // -- Media (MPRIS via playerctl) --
    property string lastTitle: ""
    property double lastMetaAt: 0

    Process {
        id: statusFollow
        command: ["playerctl", "--follow", "status"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (data) => {
                var status = data.trim();
                if (status === "Paused") {
                    root.present("⏸ Paused", false, 0, false);
                } else if (status === "Stopped") {
                    root.present("⏹ Stopped", false, 0, false);
                    root.lastTitle = "";
                } else if (status === "Playing") {
                    // A track change fires both a metadata line and a
                    // Playing status line in short order — the metadata
                    // handler below already popped the OSD for that case,
                    // so only announce "Resumed" if nothing else just did.
                    if (Date.now() - root.lastMetaAt > 400) {
                        root.present("▶ Resumed", false, 0, false);
                    }
                }
            }
        }
    }

    Process {
        id: metadataFollow
        command: ["playerctl", "--follow", "metadata", "--format", "{{title}}\t{{artist}}"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (data) => {
                var parts = data.split("\t");
                var title = (parts[0] || "").trim();
                var artist = (parts[1] || "").trim();
                if (!title || title === root.lastTitle) return;
                root.lastTitle = title;
                root.lastMetaAt = Date.now();
                root.present("▶ " + title + (artist ? " — " + artist : ""), false, 0, false);
            }
        }
    }

    Component.onCompleted: {
        statusFollow.running = true;
        metadataFollow.running = true;
    }

    PanelWindow {
        id: osdWindow
        visible: false
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "osd"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        focusable: false
        anchors { top: true }
        margins.top: 12
        exclusiveZone: 0
        color: "transparent"

        implicitWidth: 300
        implicitHeight: osdContent.implicitHeight + 24

        Rectangle {
            anchors.fill: parent
            color: Theme.bg
            border.width: 2
            border.color: root.barDanger ? Theme.danger : Theme.accent

            Column {
                id: osdContent
                x: 14
                y: 12
                width: parent.width - 28
                spacing: 8

                Text {
                    width: parent.width
                    text: root.osdText
                    color: Theme.fg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    font.bold: true
                    elide: Text.ElideRight
                }

                Rectangle {
                    visible: root.showBar
                    width: parent.width
                    height: 6
                    color: Theme.bgAlt
                    border.width: 1
                    border.color: Theme.border

                    Rectangle {
                        width: parent.width * Math.max(0, Math.min(1, root.barValue))
                        height: parent.height
                        color: root.barDanger ? Theme.danger : Theme.accent
                    }
                }
            }
        }
    }
}
