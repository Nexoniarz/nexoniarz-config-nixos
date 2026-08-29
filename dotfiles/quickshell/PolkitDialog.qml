import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit

// Custom-themed polkit authentication agent, replacing hyprpolkitagent's
// default (unthemed, light) dialog. PolkitAgent/AuthFlow handle the actual
// D-Bus/PAM plumbing internally — this file is purely the UI around it.
//
// Rendered as a slim layer-shell bar anchored to the top-center of the
// screen (like mako's notification popups) rather than a normal toplevel
// window — this sidesteps Hyprland window placement entirely, so there's
// no need for float/center window rules.
Item {
    id: root

    PolkitAgent {
        id: agent
    }

    PanelWindow {
        id: dialogWindow
        visible: agent.flow !== null
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "polkit-dialog"

        anchors { top: true }
        margins.top: 12
        exclusiveZone: 0
        focusable: visible
        color: "transparent"

        implicitWidth: 420
        implicitHeight: content.implicitHeight + 24

        onVisibleChanged: if (visible) responseField.forceActiveFocus()

        Rectangle {
            anchors.fill: parent
            color: Theme.bg
            border.width: 2
            border.color: Theme.accent

            Row {
                id: content
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 10

                Rectangle {
                    width: 4
                    height: infoCol.implicitHeight
                    color: Theme.accent
                }

                Column {
                    id: infoCol
                    width: content.width - 4 - 10 - actionRow.width - 10
                    spacing: 4

                    Text {
                        text: agent.flow ? agent.flow.message : ""
                        color: Theme.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        font.bold: true
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Text {
                        visible: !!(agent.flow && agent.flow.supplementaryMessage)
                        text: agent.flow ? agent.flow.supplementaryMessage : ""
                        color: (agent.flow && agent.flow.supplementaryIsError) ? Theme.danger : Theme.accent
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }

                    Rectangle {
                        visible: !!(agent.flow && agent.flow.isResponseRequired)
                        width: parent.width
                        height: 26
                        color: Theme.bgAlt
                        border.width: 1
                        border.color: Theme.border

                        Text {
                            visible: responseField.text.length === 0
                            anchors.verticalCenter: parent.verticalCenter
                            x: 8
                            text: agent.flow ? agent.flow.inputPrompt : ""
                            color: Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                        }

                        TextInput {
                            id: responseField
                            anchors.fill: parent
                            anchors.margins: 6
                            echoMode: (agent.flow && agent.flow.responseVisible) ? TextInput.Normal : TextInput.Password
                            color: Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            focus: true

                            Keys.onReturnPressed: submitResponse()
                            Keys.onEnterPressed: submitResponse()
                            Keys.onEscapePressed: if (agent.flow) agent.flow.cancelAuthenticationRequest()

                            function submitResponse() {
                                if (agent.flow) {
                                    agent.flow.submit(text);
                                    text = "";
                                }
                            }
                        }
                    }
                }

                Row {
                    id: actionRow
                    anchors.verticalCenter: infoCol.verticalCenter
                    spacing: 6

                    Rectangle {
                        width: 90
                        height: 26
                        color: authMa.containsMouse ? Theme.bgAlt : "transparent"
                        border.width: 2
                        border.color: Theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: "Authenticate"
                            color: Theme.accent
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                            font.bold: true
                        }
                        MouseArea {
                            id: authMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: responseField.submitResponse()
                        }
                    }
                    Rectangle {
                        width: 70
                        height: 26
                        color: cancelMa.containsMouse ? Theme.bgAlt : "transparent"
                        border.width: 1
                        border.color: Theme.border
                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                        }
                        MouseArea {
                            id: cancelMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (agent.flow) agent.flow.cancelAuthenticationRequest()
                        }
                    }
                }
            }
        }
    }
}
