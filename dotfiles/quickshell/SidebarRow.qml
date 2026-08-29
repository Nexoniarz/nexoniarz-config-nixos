import QtQuick

Rectangle {
    id: root
    property string label: ""
    property bool active: false
    property color fg: Theme.fg
    property color accent: Theme.accent
    signal clicked()

    width: parent ? parent.width : 200
    height: 40
    color: mouseArea.containsMouse ? Theme.bgAlt : "transparent"
    border.width: active ? 2 : 1
    border.color: active ? accent : Theme.borderDim
    radius: 0

    Text {
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: root.active ? root.accent : root.fg
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 12
        font.bold: root.active
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
