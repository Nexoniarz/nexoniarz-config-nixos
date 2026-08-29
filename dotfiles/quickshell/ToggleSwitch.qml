import QtQuick

Row {
    id: root
    property bool checked: false
    property string onLabel: "On"
    property string offLabel: "Off"
    signal toggled()
    spacing: 8

    Rectangle {
        width: 44
        height: 22
        anchors.verticalCenter: parent.verticalCenter
        color: root.checked ? Theme.accent : Theme.bgAlt
        border.width: 1
        border.color: Theme.border

        Rectangle {
            width: 18
            height: 18
            y: 2
            x: root.checked ? parent.width - width - 2 : 2
            color: root.checked ? Theme.bg : Theme.fgDim
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggled()
        }
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.checked ? root.onLabel : root.offLabel
        color: root.checked ? Theme.accent : Theme.fgDim
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 11
    }
}
