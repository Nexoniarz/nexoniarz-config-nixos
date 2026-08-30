import QtQuick

// Read-only horizontal usage bar — CPU/RAM/GPU/VRAM/disk meters in the
// System Monitor panel all need the same "filled fraction of a track"
// visual, just with a different value/color each time.
Item {
    id: root
    property real value: 0 // 0..1
    property color barColor: Theme.accent
    implicitHeight: 8

    Rectangle {
        anchors.fill: parent
        color: Theme.bgAlt
        border.width: 1
        border.color: Theme.borderDim
    }
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 1
        width: Math.max(0, (parent.width - 2) * Math.min(1, Math.max(0, root.value)))
        color: root.barColor
    }
}
