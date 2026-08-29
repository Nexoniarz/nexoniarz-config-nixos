import QtQuick

Rectangle {
    id: root
    property string glyph: ""
    property bool active: false
    property color fg: Theme.fg
    property color accent: Theme.accent
    signal clicked()

    width: 48
    height: 48
    color: mouseArea.containsMouse ? Theme.bgAlt : "transparent"
    border.width: active ? 2 : 1
    border.color: active ? accent : Theme.borderDim
    radius: 0

    Text {
        anchors.centerIn: parent
        text: root.glyph
        color: root.active ? root.accent : root.fg
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 21
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
