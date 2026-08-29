import QtQuick

// Small "x" corner button for deleting a grid tile (wallpapers) — only
// meant to be shown while the tile itself is hovered, matching the
// hover-to-reveal pattern used for clearing a single notification.
Rectangle {
    id: root
    signal clicked()

    width: 18
    height: 18
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: 4
    z: 1
    color: mouseArea.containsMouse ? Theme.danger : Theme.bg
    border.width: 1
    border.color: Theme.danger

    Text {
        anchors.centerIn: parent
        text: "×"
        color: mouseArea.containsMouse ? Theme.bg : Theme.danger
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 12
        font.bold: true
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
