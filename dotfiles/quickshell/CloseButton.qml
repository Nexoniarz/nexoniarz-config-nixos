import QtQuick

// Small close button using a plain "x" glyph, not a nerd-font icon — the
// left-bar icons taught us those can silently fail to render.
Rectangle {
    id: root
    signal clicked()

    width: 24
    height: 24
    color: mouseArea.containsMouse ? Theme.borderDim : "transparent"
    border.width: 1
    border.color: Theme.border

    Text {
        anchors.centerIn: parent
        text: "x"
        color: Theme.fgDim2
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
