pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

Item {
    id: root

    property int maxContentWidth: 480
    property bool showBackButton: false
    property string searchText: ""
    property bool p2pMode: Config.system.nordvpn.preferredMode === "p2p"
    signal backRequested

    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property var filteredCountries: NordVpnService.countries.filter(item => {
        const query = root.searchText.trim().toLowerCase();
        return query === "" || item.name.toLowerCase().includes(query) || item.code.toLowerCase().includes(query);
    })
    readonly property string statusText: {
        if (VpnService.isSwitching)
            return VpnService.phase;
        if (NordVpnService.lastError !== "")
            return NordVpnService.lastError;
        if (!NordVpnService.available)
            return "Not installed";
        if (NordVpnService.needsLogin)
            return "Log in required";
        if (NordVpnService.connecting)
            return "Connecting…";
        if (NordVpnService.connected)
            return NordVpnService.country || "Connected";
        return "Disconnected";
    }

    function positionAtBeginning(): void {
        countryList.positionViewAtBeginning();
    }

    function requestConnect(countryName = ""): void {
        const connect = function () {
            VpnService.switchToNord(countryName, root.p2pMode);
        };
        if (!TailscaleService.connected || Config.system.nordvpn.handoffPolicy !== "confirm") {
            connect();
            return;
        }
        if (!Visibilities.contextMenu)
            return;
        Visibilities.contextMenu.openCustomMenu([
            {
                text: "Switch from Tailscale to NordVPN",
                icon: Icons.vpn,
                onTriggered: connect
            },
            {
                text: "Cancel",
                icon: Icons.cancel,
                onTriggered: function () {}
            }
        ], 320, 36, "vpn-provider-handoff");
    }

    Component.onCompleted: {
        NordVpnService.refresh();
        NordVpnService.refreshCountries();
        Qt.callLater(() => root.positionAtBeginning());
    }

    ListView {
        id: countryList

        anchors.fill: parent
        clip: true
        spacing: 4
        cacheBuffer: 800
        boundsBehavior: Flickable.StopAtBounds
        model: root.filteredCountries

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        header: Item {
            width: countryList.width
            height: headerColumn.implicitHeight + 10

            ColumnLayout {
                id: headerColumn

                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                PanelTitlebar {
                    Layout.fillWidth: true
                    title: "NordVPN"
                    statusText: root.statusText
                    statusColor: NordVpnService.lastError !== "" || VpnService.lastError !== ""
                        ? Colors.error
                        : (!NordVpnService.available || NordVpnService.needsLogin ? Colors.warning : Styling.srItem("overprimary"))
                    showToggle: NordVpnService.available && !NordVpnService.needsLogin
                    toggleChecked: NordVpnService.connected
                    toggleEnabled: !NordVpnService.isUpdating && !VpnService.isSwitching
                    actions: (root.showBackButton ? [{
                        icon: Icons.caretLeft,
                        tooltip: "Back to VPN providers",
                        onClicked: function () {
                            root.backRequested();
                        }
                    }] : []).concat([{
                        icon: Icons.sync,
                        tooltip: "Refresh NordVPN",
                        loading: NordVpnService.isUpdating,
                        enabled: NordVpnService.available,
                        onClicked: function () {
                            NordVpnService.refresh();
                            NordVpnService.refreshCountries();
                        }
                    }])

                    onToggleChanged: {
                        if (NordVpnService.connected)
                            NordVpnService.disconnect();
                        else
                            root.requestConnect(Config.system.nordvpn.preferredCountry);
                    }
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: connectionColumn.implicitHeight + 24
                    variant: NordVpnService.connected ? "primary" : "internalbg"
                    radius: Styling.radius(4)

                    ColumnLayout {
                        id: connectionColumn

                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 7

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            StyledRect {
                                Layout.preferredWidth: 42
                                Layout.preferredHeight: 42
                                variant: NordVpnService.connected ? "focus" : "common"
                                radius: Styling.radius(2)

                                Text {
                                    anchors.centerIn: parent
                                    text: NordVpnService.connected
                                        ? NordVpnService.flagForCode(NordVpnService.countryCodes[NordVpnService.country] ?? "")
                                        : Icons.vpn
                                    font.family: NordVpnService.connected ? Config.theme.font : Icons.font
                                    font.pixelSize: NordVpnService.connected ? Styling.fontSize(6) : Styling.fontSize(3)
                                    color: NordVpnService.connected ? Styling.srItem("primary") : Colors.overBackground
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: NordVpnService.connected
                                        ? (NordVpnService.country || "NordVPN")
                                        : "Quick Connect"
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(1)
                                    font.weight: Font.Medium
                                    color: NordVpnService.connected ? Styling.srItem("primary") : Colors.overBackground
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: {
                                        if (!NordVpnService.available)
                                            return "Install the NordVPN Linux client to connect";
                                        if (NordVpnService.needsLogin)
                                            return "Sign in to your Nord Account";
                                        if (NordVpnService.connected)
                                            return [NordVpnService.city, NordVpnService.server, NordVpnService.technology].filter(value => value !== "").join(" · ");
                                        return root.p2pMode ? "Fastest P2P-optimized server" : "Fastest recommended server";
                                    }
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    color: NordVpnService.connected ? Styling.srItem("primary") : Colors.overSurfaceVariant
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        Button {
                            id: connectButton

                            Layout.fillWidth: true
                            visible: NordVpnService.available
                            enabled: !NordVpnService.isUpdating && !VpnService.isSwitching
                            text: NordVpnService.needsLogin ? "Log in"
                                : (NordVpnService.connected ? "Disconnect" : "Connect")

                            background: StyledRect {
                                variant: connectButton.hovered ? "focus" : "common"
                                radius: Styling.radius(-2)
                            }

                            contentItem: Text {
                                text: connectButton.text
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.Medium
                                color: Colors.overBackground
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            onClicked: {
                                if (NordVpnService.needsLogin)
                                    NordVpnService.login();
                                else if (NordVpnService.connected)
                                    NordVpnService.disconnect();
                                else
                                    root.requestConnect();
                            }
                        }
                    }
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: 42
                    visible: NordVpnService.available
                    variant: "internalbg"
                    radius: Styling.radius(4)

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 4

                        Repeater {
                            model: [
                                { label: "Fastest", p2p: false },
                                { label: "P2P optimized", p2p: true }
                            ]

                            delegate: Button {
                                id: modeButton

                                required property var modelData
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                flat: true

                                background: StyledRect {
                                    variant: root.p2pMode === modeButton.modelData.p2p
                                        ? "focus" : (modeButton.hovered ? "common" : "internalbg")
                                    radius: Styling.radius(-4)
                                }

                                contentItem: Text {
                                    text: modeButton.modelData.label
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    font.weight: root.p2pMode === modeButton.modelData.p2p ? Font.Medium : Font.Normal
                                    color: Colors.overBackground
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: {
                                    root.p2pMode = modelData.p2p;
                                    Config.system.nordvpn.preferredMode = modelData.p2p ? "p2p" : "fastest";
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.p2pMode && NordVpnService.available
                    text: "P2P optimized requests NordVPN's P2P server group. Standard servers also support peer-to-peer traffic."
                    wrapMode: Text.Wrap
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.overSurfaceVariant
                }

                SearchInput {
                    Layout.fillWidth: true
                    visible: NordVpnService.available && NordVpnService.countries.length > 0
                    placeholderText: "Search countries"
                    iconText: Icons.globe
                    onSearchTextChanged: text => root.searchText = text
                }

                Text {
                    Layout.fillWidth: true
                    visible: NordVpnService.available && NordVpnService.countries.length > 0
                    text: "Countries"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    font.weight: Font.Medium
                    color: Colors.overSurfaceVariant
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: setupText.implicitHeight + 24
                    visible: !NordVpnService.available
                    variant: "common"
                    radius: Styling.radius(4)

                    Text {
                        id: setupText
                        anchors.fill: parent
                        anchors.margins: 12
                        text: "NordVPN is not installed. Install the official Linux client, add this user to the nordvpn group if required, then restart the session."
                        wrapMode: Text.Wrap
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.warning
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: VpnService.lastError !== ""
                    text: VpnService.lastError
                    wrapMode: Text.Wrap
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.error
                }
            }
        }

        delegate: Item {
            id: countryDelegate

            required property var modelData
            width: countryList.width
            height: countryCard.height + 4

            StyledRect {
                id: countryCard

                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                implicitHeight: 54
                variant: countryMouseArea.containsMouse ? "focus" : "common"
                radius: Styling.radius(4)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Text {
                        Layout.preferredWidth: 30
                        text: countryDelegate.modelData.flag
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(4)
                        horizontalAlignment: Text.AlignHCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            text: countryDelegate.modelData.name
                            font.family: Config.theme.font
                            font.pixelSize: Config.theme.fontSize
                            font.weight: Font.Medium
                            color: Colors.overBackground
                            elide: Text.ElideRight
                        }

                        Text {
                            text: root.p2pMode ? "P2P optimized" : "Fastest available"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: Colors.overSurfaceVariant
                        }
                    }

                    Text {
                        text: NordVpnService.connected && NordVpnService.country === countryDelegate.modelData.name
                            ? Icons.shieldCheck : Icons.caretRight
                        font.family: Icons.font
                        font.pixelSize: Styling.fontSize(0)
                        color: NordVpnService.connected && NordVpnService.country === countryDelegate.modelData.name
                            ? Styling.srItem("overprimary") : Colors.overSurfaceVariant
                    }
                }

                MouseArea {
                    id: countryMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !NordVpnService.isUpdating && !VpnService.isSwitching
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        Config.system.nordvpn.preferredCountry = countryDelegate.modelData.name;
                        root.requestConnect(countryDelegate.modelData.name);
                    }
                }
            }
        }

        Text {
            anchors.centerIn: parent
            visible: NordVpnService.available && NordVpnService.countries.length > 0
                && countryList.count === 0
            text: "No matching countries"
            font.family: Config.theme.font
            font.pixelSize: Config.theme.fontSize
            color: Colors.overSurfaceVariant
        }
    }
}
