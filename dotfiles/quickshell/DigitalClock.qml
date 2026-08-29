import QtQuick
import Quickshell

// 24h time + "day monthname year" date, using the system locale (pl_PL) for
// the month name — matches how Poland actually writes dates.
Column {
    id: root
    spacing: 2

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
        enabled: true
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatTime(clock.date, "HH:mm")
        color: Theme.fg
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 20
        font.bold: true
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Qt.formatDate(clock.date, "d MMMM yyyy")
        color: Theme.fgDim
        font.family: "JetBrainsMono Nerd Font"
        font.pixelSize: 11
    }
}
