import QtQuick

// Reusable 0..1 drag slider with a visible handle, used by the volume and
// brightness panels.
Item {
    id: root
    property real value: 0
    signal moved(real value)
    height: 28

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        color: Theme.bgAlt
        border.width: 1
        border.color: Theme.border

        Rectangle {
            width: track.width * Math.max(0, Math.min(1, root.value))
            height: parent.height
            color: Theme.accent
        }
    }

    Rectangle {
        id: handle
        width: 14
        height: 20
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(track.width - width, track.width * Math.max(0, Math.min(1, root.value)) - width / 2))
        color: Theme.fg
        border.width: 1
        border.color: Theme.border
    }

    MouseArea {
        anchors.fill: parent
        onPositionChanged: (mouse) => { if (pressed) update(mouse.x) }
        onPressed: (mouse) => update(mouse.x)
        function update(x) {
            var v = Math.max(0, Math.min(1, x / width));
            root.value = v;
            root.moved(v);
        }
    }
}
