import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Bluetooth
import Quickshell.Networking

Rectangle {
    id: root
    property string activePanel: ""
    signal requestClose()

    width: 320
    implicitHeight: header.height + loader.item.implicitHeight + 16
    color: Theme.bg
    border.width: 2
    border.color: Theme.border

    property var titles: ({
        network: "Network",
        messages: "Messages",
        bluetooth: "Bluetooth",
        screenshot: "Screenshot",
        volume: "Volume",
        brightness: "Brightness",
        devices: "Devices",
        power: "Power"
    })

    // Lives here, not inside messagesPanel's own Column — that Component
    // gets destroyed every time the panel closes (the Loader tears it
    // down), which was silently resetting this to [] on every reopen and
    // making "cleared" messages reappear. `root` itself persists for the
    // life of the popup, so this survives closing/reopening the panel
    // (though not a full Quickshell restart — mako's own history is just
    // as ephemeral, so there'd be nothing to hide-filter after one anyway).
    property var hiddenMessageIds: []
    function hideMessageId(id) {
        var ids = root.hiddenMessageIds.slice();
        if (ids.indexOf(id) === -1) ids.push(id);
        root.hiddenMessageIds = ids;
    }
    function clearAllMessages(currentIds) {
        var ids = root.hiddenMessageIds.slice();
        for (var i = 0; i < currentIds.length; i++) {
            if (ids.indexOf(currentIds[i]) === -1) ids.push(currentIds[i]);
        }
        root.hiddenMessageIds = ids;
    }

    Item {
        id: header
        width: parent.width
        height: 40

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: root.titles[root.activePanel] || ""
            color: Theme.fg
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 14
            font.bold: true
        }

        CloseButton {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            onClicked: root.requestClose()
        }
    }
    Rectangle { anchors.top: header.bottom; width: parent.width; height: 1; color: Theme.border }

    Loader {
        id: loader
        y: header.height + 8
        x: 12
        width: parent.width - 24
        sourceComponent: {
            switch (root.activePanel) {
            case "network": return networkPanel;
            case "messages": return messagesPanel;
            case "bluetooth": return bluetoothPanel;
            case "screenshot": return screenshotPanel;
            case "volume": return volumePanel;
            case "brightness": return brightnessPanel;
            case "devices": return devicesPanel;
            case "power": return powerPanel;
            default: return emptyPanel;
            }
        }
    }

    Component {
        id: emptyPanel
        Item { implicitHeight: 1 }
    }

    // --- Network -------------------------------------------------------
    Component {
        id: networkPanel
        Column {
            id: netCol
            spacing: 10
            width: loader.width
            property var selected: null // a Network, or a NetworkDevice (wired fallback)
            property bool selectedIsDevice: netCol.selected !== null && netCol.selected.networks !== undefined

            // --- List view ---------------------------------------------
            Column {
                visible: netCol.selected === null
                width: parent.width
                spacing: 10

                Item {
                    width: parent.width
                    height: 22
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Wi-Fi"
                        color: Theme.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        font.bold: true
                    }
                    ToggleSwitch {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        checked: Networking.wifiEnabled
                        onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                    }
                }

                Text {
                    visible: Networking.devices.values.length === 0
                    text: "No network devices"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                }

                Repeater {
                    model: Networking.devices
                    delegate: Column {
                        width: loader.width
                        spacing: 4
                        property var device: modelData

                        // Turn on active scanning while this panel is open so
                        // the network list shows more than just whatever we're
                        // already connected to.
                        Component.onCompleted: if (device.scannerEnabled !== undefined) device.scannerEnabled = true;
                        Component.onDestruction: if (device.scannerEnabled !== undefined) device.scannerEnabled = false;

                        Text {
                            text: device.name
                            color: Theme.fgDim
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 10
                        }

                        // Wired devices report a single phantom "network" entry with no
                        // signal strength, so detect Wi-Fi by scannerEnabled (only WifiDevice
                        // has that property) instead of by networks-list emptiness.
                        property bool isWifi: device.scannerEnabled !== undefined

                        // Non-Wi-Fi devices — show link state directly instead of a list.
                        Rectangle {
                            visible: !isWifi
                            width: loader.width
                            height: 32
                            color: wiredMa.containsMouse ? Theme.bgAlt : "transparent"
                            border.width: 1
                            border.color: device.connected ? Theme.accent : Theme.borderDim
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: device.connected ? "Connected" : "No link"
                                color: device.connected ? Theme.accent : Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                            }
                            MouseArea {
                                id: wiredMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: netCol.selected = device
                            }
                        }

                        Repeater {
                            model: (isWifi && device.networks) ? device.networks : []
                            delegate: Rectangle {
                                width: loader.width
                                height: 40
                                color: netMa.containsMouse ? Theme.bgAlt : "transparent"
                                border.width: 1
                                border.color: net.connected ? Theme.accent : Theme.borderDim
                                property var net: modelData

                                Column {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1
                                    Text {
                                        text: net.name
                                        color: net.connected ? Theme.accent : Theme.fg
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 12
                                    }
                                    Text {
                                        text: (net.connected ? "Connected" : (net.known ? "Saved" : "Available"))
                                            + " · " + net.signalStrength + "%"
                                            + " · " + WifiSecurityType.toString(net.security)
                                        color: Theme.fgDim
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: 10
                                    }
                                }

                                MouseArea {
                                    id: netMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: netCol.selected = net
                                }
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.borderDim }

                Column {
                    id: hotspotCol
                    width: loader.width
                    spacing: 8
                    property bool hotspotActive: false
                    property bool canStart: ssidInput.text.length > 0 && pskInput.text.length >= 8

                    // Persists SSID/password/security/band across Quickshell
                    // restarts, blank/default otherwise.
                    PersistentProperties {
                        id: hotspotState
                        property string ssid: ""
                        property string password: ""
                        property string security: "wpa2"
                        property string band: "auto"
                    }

                    Text {
                        text: "Hotspot"
                        color: Theme.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Process { id: hotspotProc; command: [] }
                    Process {
                        id: hotspotStatusProc
                        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"]
                        stdout: StdioCollector {
                            onStreamFinished: hotspotCol.hotspotActive = text.indexOf("Hotspot") !== -1
                        }
                    }
                    Component.onCompleted: hotspotStatusProc.running = true

                    Rectangle {
                        width: loader.width
                        height: 30
                        color: Theme.bgAlt
                        border.width: 1
                        border.color: Theme.border
                        TextInput {
                            id: ssidInput
                            anchors.fill: parent
                            anchors.margins: 8
                            text: hotspotState.ssid
                            onTextEdited: hotspotState.ssid = text
                            color: Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            clip: true

                            Text {
                                visible: ssidInput.text.length === 0
                                text: "SSID"
                                color: Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                            }
                        }
                    }
                    Rectangle {
                        width: loader.width
                        height: 30
                        color: Theme.bgAlt
                        border.width: 1
                        border.color: Theme.border
                        TextInput {
                            id: pskInput
                            anchors.fill: parent
                            anchors.margins: 8
                            text: hotspotState.password
                            onTextEdited: hotspotState.password = text
                            echoMode: TextInput.Password
                            color: Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            clip: true

                            Text {
                                visible: pskInput.text.length === 0
                                text: "Password"
                                color: Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                            }
                        }
                    }

                    Text {
                        text: "Security"
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                    }
                    Row {
                        spacing: 6
                        Repeater {
                            model: [
                                { key: "wpa2", label: "WPA2" },
                                { key: "wpa3", label: "WPA3" }
                            ]
                            delegate: Rectangle {
                                width: (loader.width - 6) / 2
                                height: 28
                                color: modelData.key === hotspotState.security ? Theme.bgAlt : (secMa.containsMouse ? Theme.bgAlt : "transparent")
                                border.width: modelData.key === hotspotState.security ? 2 : 1
                                border.color: modelData.key === hotspotState.security ? Theme.accent : Theme.borderDim
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: modelData.key === hotspotState.security ? Theme.accent : Theme.fg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                }
                                MouseArea {
                                    id: secMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: hotspotState.security = modelData.key
                                }
                            }
                        }
                    }

                    Text {
                        text: "Band"
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 10
                    }
                    Row {
                        spacing: 6
                        Repeater {
                            model: [
                                { key: "auto", label: "Auto" },
                                { key: "bg", label: "2.4GHz" },
                                { key: "a", label: "5GHz" }
                            ]
                            delegate: Rectangle {
                                width: (loader.width - 12) / 3
                                height: 28
                                color: modelData.key === hotspotState.band ? Theme.bgAlt : (bandMa.containsMouse ? Theme.bgAlt : "transparent")
                                border.width: modelData.key === hotspotState.band ? 2 : 1
                                border.color: modelData.key === hotspotState.band ? Theme.accent : Theme.borderDim
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: modelData.key === hotspotState.band ? Theme.accent : Theme.fg
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: 11
                                }
                                MouseArea {
                                    id: bandMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: hotspotState.band = modelData.key
                                }
                            }
                        }
                    }

                    Rectangle {
                        id: hsButton
                        width: loader.width
                        height: 32
                        opacity: (hotspotCol.hotspotActive || hotspotCol.canStart) ? 1 : 0.4
                        color: hsMa.containsMouse ? Theme.bgAlt : "transparent"
                        border.width: 1
                        border.color: hotspotCol.hotspotActive ? Theme.danger : Theme.accent
                        Text {
                            anchors.centerIn: parent
                            text: hotspotCol.hotspotActive ? "Stop Hotspot" : "Start Hotspot"
                            color: hotspotCol.hotspotActive ? Theme.danger : Theme.accent
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            font.bold: true
                        }
                        MouseArea {
                            id: hsMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (hotspotCol.hotspotActive) {
                                    hotspotProc.command = ["nmcli", "connection", "down", "Hotspot"];
                                    hotspotProc.running = true;
                                    hotspotCol.hotspotActive = false;
                                } else if (hotspotCol.canStart) {
                                    hotspotProc.command = ["hotspot-start", ssidInput.text, pskInput.text, hotspotState.security, hotspotState.band];
                                    hotspotProc.running = true;
                                    hotspotCol.hotspotActive = true;
                                }
                            }
                        }
                    }

                    Text {
                        text: "Password needs at least 8 characters."
                        color: Theme.fgDim
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 9
                        wrapMode: Text.WordWrap
                        width: loader.width
                    }
                }
            }

            // --- Detail view ---------------------------------------------
            Column {
                id: netDetail
                visible: netCol.selected !== null
                width: parent.width
                spacing: 10

                property var sel: netCol.selected
                property bool needsPassword: !!(sel && !netCol.selectedIsDevice && !sel.known && !sel.connected)

                // NetworkDevice.address is actually the MAC address, not an IP —
                // the real IP has to come from nmcli.
                property string deviceName: sel ? (netCol.selectedIsDevice ? sel.name : (sel.device ? sel.device.name : "")) : ""
                property string ip: ""
                Process {
                    id: ipProc
                    command: netDetail.deviceName ? ["nmcli", "-g", "IP4.ADDRESS", "device", "show", netDetail.deviceName] : []
                    stdout: StdioCollector {
                        onStreamFinished: netDetail.ip = text.split("/")[0].split("\n")[0].trim()
                    }
                }
                onDeviceNameChanged: { ip = ""; if (deviceName) ipProc.running = true; }
                Component.onCompleted: if (deviceName) ipProc.running = true

                Process { id: netActionProc; command: [] }

                Rectangle {
                    width: parent.width
                    height: 26
                    color: "transparent"
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "< Back"
                        color: Theme.accent
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                    }
                    MouseArea { anchors.fill: parent; onClicked: netCol.selected = null }
                }

                Text {
                    text: netCol.selected ? netCol.selected.name : ""
                    color: Theme.fg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 15
                    font.bold: true
                }

                Column {
                    width: parent.width
                    spacing: 4

                    property var rows: {
                        if (!netCol.selected) return [];
                        if (netCol.selectedIsDevice) {
                            return [
                                { label: "Status", value: netCol.selected.connected ? "Connected" : "No link" },
                                { label: "IP Address", value: netDetail.ip || "—" },
                                { label: "MAC Address", value: netCol.selected.address || "—" }
                            ];
                        }
                        var r = [
                            { label: "Status", value: netCol.selected.connected ? "Connected" : (netCol.selected.known ? "Saved" : "Available") },
                            { label: "Signal", value: netCol.selected.signalStrength + "%" },
                            { label: "Security", value: WifiSecurityType.toString(netCol.selected.security) }
                        ];
                        if (netCol.selected.connected)
                            r.push({ label: "IP Address", value: netDetail.ip || "—" });
                        if (netCol.selected.device && netCol.selected.device.address)
                            r.push({ label: "MAC Address", value: netCol.selected.device.address });
                        return r;
                    }

                    Repeater {
                        model: parent.rows
                        delegate: Item {
                            width: loader.width
                            height: 20
                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                color: Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.value
                                color: Theme.fg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.borderDim }

                Column {
                    visible: !netCol.selectedIsDevice && netDetail.needsPassword
                    width: parent.width
                    spacing: 8

                    Rectangle {
                        width: parent.width
                        height: 30
                        color: Theme.bgAlt
                        border.width: 1
                        border.color: Theme.border
                        TextInput {
                            id: detailPskField
                            anchors.fill: parent
                            anchors.margins: 8
                            echoMode: TextInput.Password
                            color: Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            clip: true

                            Text {
                                visible: detailPskField.text.length === 0
                                text: "Password"
                                color: Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                            }
                        }
                    }
                }

                Rectangle {
                    visible: !netCol.selectedIsDevice
                    width: parent.width
                    height: 34
                    property bool canSubmit: !netDetail.needsPassword || detailPskField.text.length >= 8
                    opacity: canSubmit ? 1 : 0.4
                    color: connMa.containsMouse ? Theme.bgAlt : "transparent"
                    border.width: 2
                    border.color: (netCol.selected && netCol.selected.connected) ? Theme.danger : Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: (netCol.selected && netCol.selected.connected) ? "Disconnect"
                            : (netDetail.needsPassword ? "Connect with password" : "Connect")
                        color: (netCol.selected && netCol.selected.connected) ? Theme.danger : Theme.accent
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        font.bold: true
                    }
                    MouseArea {
                        id: connMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (!netCol.selected) return;
                            if (netCol.selected.connected) netCol.selected.disconnect();
                            else if (netDetail.needsPassword) {
                                if (detailPskField.text.length >= 8) netCol.selected.connectWithPsk(detailPskField.text);
                            } else netCol.selected.connect();
                        }
                    }
                }

                Text {
                    visible: !netCol.selectedIsDevice && netCol.selected && netCol.selected.known
                    text: "Forget this network"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11

                    MouseArea {
                        anchors.fill: parent
                        onClicked: { netCol.selected.forget(); netCol.selected = null; }
                    }
                }
            }
        }
    }

    // --- Bluetooth -------------------------------------------------------
    Component {
        id: bluetoothPanel
        Column {
            id: btCol
            spacing: 10
            width: loader.width
            property var selected: null

            // --- List view ---------------------------------------------
            Column {
                visible: btCol.selected === null
                width: parent.width
                spacing: 10

                Item {
                    width: parent.width
                    height: 22
                    visible: Bluetooth.defaultAdapter !== null
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Bluetooth"
                        color: Theme.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                        font.bold: true
                    }
                    ToggleSwitch {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        checked: !!(Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled)
                        onToggled: if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.enabled = !Bluetooth.defaultAdapter.enabled
                    }
                }

                Text {
                    visible: Bluetooth.defaultAdapter === null
                    text: "No Bluetooth adapter found"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                }

                Rectangle {
                    visible: !!(Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.enabled)
                    width: loader.width
                    height: 30
                    color: scanMa.containsMouse ? Theme.bgAlt : "transparent"
                    border.width: 1
                    border.color: Theme.borderDim
                    Text {
                        anchors.centerIn: parent
                        text: (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering) ? "Scanning…" : "Scan for devices"
                        color: (Bluetooth.defaultAdapter && Bluetooth.defaultAdapter.discovering) ? Theme.accent : Theme.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: scanMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: if (Bluetooth.defaultAdapter) Bluetooth.defaultAdapter.discovering = !Bluetooth.defaultAdapter.discovering
                    }
                }

                Text {
                    text: "Paired & nearby devices"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                }
                Text {
                    visible: Bluetooth.defaultAdapter !== null && Bluetooth.devices.values.length === 0
                    text: "No devices"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                }

                Repeater {
                    model: Bluetooth.devices
                    delegate: Rectangle {
                        width: loader.width
                        height: 40
                        color: btMa.containsMouse ? Theme.bgAlt : "transparent"
                        border.width: 1
                        border.color: dev.connected ? Theme.accent : Theme.borderDim
                        property var dev: modelData

                        Column {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1
                            Text {
                                text: dev.name
                                color: dev.connected ? Theme.accent : Theme.fg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 12
                            }
                            Text {
                                text: (dev.connected ? "Connected" : (dev.paired ? "Paired" : "Available"))
                                    + (dev.batteryAvailable ? " · " + Math.round(dev.battery <= 1 ? dev.battery * 100 : dev.battery) + "%" : "")
                                color: Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                            }
                        }

                        MouseArea {
                            id: btMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: btCol.selected = dev
                        }
                    }
                }
            }

            // --- Detail view ---------------------------------------------
            Column {
                visible: btCol.selected !== null
                width: parent.width
                spacing: 10

                Process { id: btActionProc; command: [] }

                Rectangle {
                    width: parent.width
                    height: 26
                    color: "transparent"
                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "< Back"
                        color: Theme.accent
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                    }
                    MouseArea { anchors.fill: parent; onClicked: btCol.selected = null }
                }

                Text {
                    text: btCol.selected ? btCol.selected.name : ""
                    color: Theme.fg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 15
                    font.bold: true
                }

                Column {
                    width: parent.width
                    spacing: 4

                    property var rows: {
                        if (!btCol.selected) return [];
                        var d = btCol.selected;
                        var r = [
                            { label: "Status", value: d.connected ? "Connected" : (d.paired ? "Paired" : "Available") },
                            { label: "MAC Address", value: d.address || "—" },
                            { label: "Type", value: d.icon || "unknown" },
                            { label: "Trusted", value: d.trusted ? "Yes" : "No" }
                        ];
                        if (d.batteryAvailable)
                            r.push({ label: "Battery", value: Math.round(d.battery <= 1 ? d.battery * 100 : d.battery) + "%" });
                        return r;
                    }

                    Repeater {
                        model: parent.rows
                        delegate: Item {
                            width: loader.width
                            height: 20
                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                color: Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.value
                                color: Theme.fg
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                Rectangle { width: parent.width; height: 1; color: Theme.borderDim }

                Rectangle {
                    width: parent.width
                    height: 34
                    color: btConnMa.containsMouse ? Theme.bgAlt : "transparent"
                    border.width: 2
                    border.color: (btCol.selected && btCol.selected.connected) ? Theme.danger : Theme.accent
                    Text {
                        anchors.centerIn: parent
                        text: (btCol.selected && btCol.selected.connected) ? "Disconnect"
                            : (btCol.selected && btCol.selected.paired) ? "Connect" : "Pair"
                        color: (btCol.selected && btCol.selected.connected) ? Theme.danger : Theme.accent
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 12
                        font.bold: true
                    }
                    MouseArea {
                        id: btConnMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (!btCol.selected) return;
                            if (btCol.selected.connected) btCol.selected.disconnect();
                            else if (btCol.selected.paired) btCol.selected.connect();
                            else btCol.selected.pair();
                        }
                    }
                }

                Text {
                    visible: !!(btCol.selected && btCol.selected.paired)
                    text: "Forget this device"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11

                    MouseArea {
                        anchors.fill: parent
                        onClicked: { btCol.selected.forget(); btCol.selected = null; }
                    }
                }
            }
        }
    }

    // --- Messages (notification history, via mako) -----------------------
    // mako's IPC has no way to actually delete a history entry (only
    // `dismiss` for currently-displayed notifications and a read-only
    // `history` list) — so "clearing" is done client-side by remembering
    // hidden ids across restarts and filtering them out of the list. The
    // hidden ids naturally become irrelevant once mako's own history ring
    // buffer rolls them out.
    Component {
        id: messagesPanel
        Column {
            id: msgCol
            spacing: 6
            width: loader.width
            property var history: []
            // The hidden-id list itself lives on `root` now (see top of
            // file) — this Column gets destroyed every time the panel
            // closes, so anything stored here alone would silently reset.
            property var visibleHistory: {
                var hidden = root.hiddenMessageIds;
                var out = [];
                for (var i = 0; i < msgCol.history.length; i++) {
                    if (hidden.indexOf(msgCol.history[i].id) === -1) out.push(msgCol.history[i]);
                }
                return out;
            }

            function refresh() { historyProc.running = true; }
            function hideId(id) { root.hideMessageId(id); }
            function clearAll() {
                var ids = [];
                for (var i = 0; i < msgCol.history.length; i++) ids.push(msgCol.history[i].id);
                root.clearAllMessages(ids);
            }

            Process {
                id: historyProc
                command: ["makoctl", "history", "-j"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            msgCol.history = JSON.parse(text);
                        } catch (e) { msgCol.history = []; }
                    }
                }
            }
            Component.onCompleted: msgCol.refresh()

            Process { id: invokeProc; command: [] }

            Item {
                width: parent.width
                height: 22
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Recent notifications"
                    color: Theme.fgDim
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 10
                }
                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12
                    Text {
                        visible: msgCol.visibleHistory.length > 0
                        text: "Clear all"
                        color: Theme.danger
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        MouseArea { anchors.fill: parent; onClicked: msgCol.clearAll() }
                    }
                    Text {
                        text: "Refresh"
                        color: Theme.accent
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        MouseArea { anchors.fill: parent; onClicked: msgCol.refresh() }
                    }
                }
            }

            Text {
                visible: msgCol.visibleHistory.length === 0
                text: "No notifications yet"
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
            }

            Repeater {
                model: msgCol.visibleHistory
                delegate: Rectangle {
                    id: msgRow
                    width: loader.width
                    height: bodyText.implicitHeight + summaryText.implicitHeight + 20
                    color: rowHover.hovered ? Theme.bgAlt : "transparent"
                    border.width: 1
                    border.color: Theme.borderDim
                    property var entry: modelData

                    HoverHandler { id: rowHover }

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 10
                        anchors.rightMargin: 30
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2

                        Row {
                            width: parent.width
                            Text {
                                text: entry.app_name || "unknown"
                                color: Theme.fgDim
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 10
                            }
                        }
                        Text {
                            id: summaryText
                            width: parent.width
                            text: entry.summary || ""
                            color: Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            font.bold: true
                            elide: Text.ElideRight
                        }
                        Text {
                            id: bodyText
                            width: parent.width
                            text: entry.body || ""
                            color: Theme.fgDim2
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 11
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: msgMa
                        anchors.fill: parent
                        onClicked: {
                            invokeProc.command = ["makoctl", "invoke", "-n", String(entry.id)];
                            invokeProc.running = true;
                        }
                    }

                    Rectangle {
                        id: closeBtn
                        z: 1
                        visible: rowHover.hovered
                        width: 18
                        height: 18
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.top: parent.top
                        anchors.topMargin: 6
                        color: closeMa.containsMouse ? Theme.danger : "transparent"
                        border.width: 1
                        border.color: Theme.danger
                        Text {
                            anchors.centerIn: parent
                            text: "×"
                            color: closeMa.containsMouse ? Theme.bg : Theme.danger
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                            font.bold: true
                        }
                        MouseArea {
                            id: closeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: msgCol.hideId(entry.id)
                        }
                    }
                }
            }
        }
    }

    // --- Screenshot -------------------------------------------------------
    Component {
        id: screenshotPanel
        Column {
            id: ssCol
            spacing: 14
            width: loader.width
            property string mode: "region"
            property string action: "both"

            property var modes: [
                { key: "region", label: "Region (drag to select)" },
                { key: "full", label: "Full screen" },
                { key: "window", label: "Active window" }
            ]
            property var actions: [
                { key: "both", label: "Save file + copy" },
                { key: "file", label: "Save file only" },
                { key: "clipboard", label: "Copy only" }
            ]

            Text {
                text: "Capture"
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
            }
            Column {
                width: parent.width
                spacing: 4
                Repeater {
                    model: ssCol.modes
                    delegate: Rectangle {
                        width: loader.width
                        height: 32
                        color: modelData.key === ssCol.mode ? Theme.bgAlt : (modeMa.containsMouse ? Theme.bgAlt : "transparent")
                        border.width: modelData.key === ssCol.mode ? 2 : 1
                        border.color: modelData.key === ssCol.mode ? Theme.accent : Theme.borderDim
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: modelData.key === ssCol.mode ? Theme.accent : Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: modeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: ssCol.mode = modelData.key
                        }
                    }
                }
            }

            Text {
                text: "Save"
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
            }
            Column {
                width: parent.width
                spacing: 4
                Repeater {
                    model: ssCol.actions
                    delegate: Rectangle {
                        width: loader.width
                        height: 32
                        color: modelData.key === ssCol.action ? Theme.bgAlt : (actionMa.containsMouse ? Theme.bgAlt : "transparent")
                        border.width: modelData.key === ssCol.action ? 2 : 1
                        border.color: modelData.key === ssCol.action ? Theme.accent : Theme.borderDim
                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: modelData.key === ssCol.action ? Theme.accent : Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                        }
                        MouseArea {
                            id: actionMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: ssCol.action = modelData.key
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 36
                color: captureMa.containsMouse ? Theme.bgAlt : "transparent"
                border.width: 2
                border.color: Theme.accent
                Text {
                    anchors.centerIn: parent
                    text: "Capture"
                    color: Theme.accent
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 13
                    font.bold: true
                }
                MouseArea {
                    id: captureMa
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        // execDetached, not a local Process: closing the panel
                        // right after this swaps the Loader's sourceComponent,
                        // which destroys this whole Component (and any Process
                        // owned by it) before it would ever get to actually run.
                        Quickshell.execDetached(["screenshot", ssCol.mode, ssCol.action]);
                        root.requestClose();
                    }
                }
            }

            Text {
                text: "Saves to ~/Screenshots"
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 9
            }
        }
    }

    // --- Volume -------------------------------------------------------
    Component {
        id: volumePanel
        Column {
            spacing: 12
            width: loader.width

            Item {
                width: parent.width
                height: 18
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: pct.left
                    anchors.rightMargin: 8
                    text: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.description : "No output"
                    color: Theme.fg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                Text {
                    id: pct
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio)
                        ? Math.round(Pipewire.defaultAudioSink.audio.volume * 100) + "%" : "--"
                    color: Theme.accent
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                    font.bold: true
                }
            }

            SquareSlider {
                width: parent.width
                value: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio) ? Pipewire.defaultAudioSink.audio.volume : 0
                onMoved: (v) => {
                    if (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio)
                        Pipewire.defaultAudioSink.audio.volume = v;
                }
            }

            Item {
                width: parent.width
                height: 22
                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Mute"
                    color: Theme.fg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 12
                }
                ToggleSwitch {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    onLabel: "Muted"
                    offLabel: "Unmuted"
                    checked: !!(Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio && Pipewire.defaultAudioSink.audio.muted)
                    onToggled: if (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.audio)
                        Pipewire.defaultAudioSink.audio.muted = !Pipewire.defaultAudioSink.audio.muted
                }
            }

            Rectangle { width: parent.width; height: 1; color: Theme.borderDim }

            Text {
                text: "Output device"
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 10
            }

            Repeater {
                model: Pipewire.nodes
                delegate: Rectangle {
                    property var node: modelData
                    visible: node.isSink && !node.isStream
                    width: loader.width
                    height: 32
                    color: outMa.containsMouse ? Theme.bgAlt : "transparent"
                    border.width: 1
                    border.color: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.id === node.id) ? Theme.accent : Theme.borderDim

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: node.description
                        color: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.id === node.id) ? Theme.accent : Theme.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        id: outMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: Pipewire.preferredDefaultAudioSink = node
                    }
                }
            }
        }
    }

    // --- Brightness -------------------------------------------------------
    Component {
        id: brightnessPanel
        Column {
            spacing: 10
            width: loader.width

            property int pct: 50

            Process {
                id: getProc
                command: ["brightness-ctl", "get"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        var n = parseInt(text.trim(), 10);
                        if (!isNaN(n)) slider.value = n / 100;
                    }
                }
            }
            Process {
                id: setProc
                command: []
            }

            Component.onCompleted: getProc.running = true

            Text {
                text: "Monitor brightness"
                color: Theme.fg
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
            }
            SquareSlider {
                id: slider
                width: parent.width
                onMoved: (v) => {
                    setProc.command = ["brightness-ctl", "set", String(Math.round(v * 100))];
                    setProc.running = true;
                }
            }
        }
    }

    // --- Devices (removable drives) -------------------------------------
    Component {
        id: devicesPanel
        Column {
            id: devCol
            spacing: 6
            width: loader.width
            property var drives: []

            function refresh() { lsblkProc.running = true; }

            Process {
                id: lsblkProc
                command: ["lsblk", "-J", "-o", "NAME,LABEL,SIZE,RM,TYPE,MOUNTPOINT,PATH,FSTYPE"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        try {
                            var data = JSON.parse(text);
                            var out = [];
                            function walk(devs) {
                                for (var i = 0; i < devs.length; i++) {
                                    var d = devs[i];
                                    // Any data partition that isn't the running system
                                    // itself — not just literally-removable (RM) ones,
                                    // since internal secondary drives count too.
                                    if (d.type === "part" && d.fstype !== "swap"
                                        && d.mountpoint !== "/" && d.mountpoint !== "/boot") {
                                        out.push(d);
                                    }
                                    if (d.children) walk(d.children);
                                }
                            }
                            walk(data.blockdevices || []);
                            devCol.drives = out;
                        } catch (e) { devCol.drives = []; }
                    }
                }
            }
            Component.onCompleted: devCol.refresh()

            Text {
                visible: devCol.drives.length === 0
                text: "No extra drives found"
                color: Theme.fgDim
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
            }

            Repeater {
                model: devCol.drives
                delegate: Rectangle {
                    width: loader.width
                    height: 44
                    color: "transparent"
                    property var drive: modelData

                    Process {
                        id: mountProc
                        command: []
                        onExited: devCol.refresh()
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: (drive.label || drive.name) + "  " + drive.size
                            color: Theme.fg
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 12
                        }
                        Row {
                            spacing: 10
                            Text {
                                text: drive.mountpoint ? "Unmount" : "Mount"
                                color: Theme.accent
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        mountProc.command = drive.mountpoint
                                            ? ["udisksctl", "unmount", "-b", drive.path]
                                            : ["udisksctl", "mount", "-b", drive.path];
                                        mountProc.running = true;
                                    }
                                }
                            }
                            Text {
                                visible: !!drive.mountpoint
                                text: "Open"
                                color: Theme.accent
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 11
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        mountProc.command = ["thunar", drive.mountpoint];
                                        mountProc.running = true;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // --- Power -------------------------------------------------------
    Component {
        id: powerPanel
        Column {
            spacing: 4
            width: loader.width

            Process { id: powerProc; command: [] }

            property var actions: [
                { label: " Lock", cmd: ["hyprlock"] },
                { label: " Suspend", cmd: ["systemctl", "suspend"] },
                { label: " Reboot", cmd: ["systemctl", "reboot"] },
                { label: " Shutdown", cmd: ["systemctl", "poweroff"] },
                { label: " Log out", cmd: ["hyprctl", "dispatch", "exit"] }
            ]

            Repeater {
                model: parent.actions
                delegate: Rectangle {
                    width: loader.width
                    height: 32
                    color: pma.containsMouse ? Theme.bgAlt : "transparent"
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: 8
                        text: modelData.label
                        color: Theme.fg
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: pma
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: { powerProc.command = modelData.cmd; powerProc.running = true; }
                    }
                }
            }
        }
    }
}
