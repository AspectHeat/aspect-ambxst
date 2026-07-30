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
    property bool showLocations: false
    signal backRequested

    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property var filteredServers: NordVpnService.recommendedServers.filter(item => {
        const query = root.searchText.trim().toLowerCase();
        const matchesMode = root.p2pMode ? item.supportsP2p : item.supportsStandard;
        const searchValue = [item.name, item.hostname, item.country, item.city, item.subdivision]
            .join(" ").toLowerCase();
        return matchesMode && (query === "" || searchValue.includes(query));
    }).map(item => Object.assign({ kind: "server" }, item))
    readonly property var filteredCountries: NordVpnService.countries.filter(item => {
        const query = root.searchText.trim().toLowerCase();
        return query === "" || item.name.toLowerCase().includes(query)
            || item.code.toLowerCase().includes(query);
    }).map(item => Object.assign({ kind: "country" }, item))
    readonly property var visibleItems: showLocations ? filteredCountries : filteredServers
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
        serverList.positionViewAtBeginning();
    }

    function setLocationsVisible(value): void {
        showLocations = value;
        searchText = "";
        browserSearch.clear();
        Qt.callLater(() => root.positionAtBeginning());
    }

    function requestConnect(countryName = ""): void {
        VpnService.switchToNord(countryName, root.p2pMode);
    }

    function requestServer(serverKey): void {
        VpnService.switchToNordServer(serverKey);
    }

    function loadColor(load): color {
        if (load <= 35)
            return Colors.success;
        if (load <= 70)
            return Colors.warning;
        return Colors.error;
    }

    Component.onCompleted: NordVpnService.refresh()

    ListView {
        id: serverList

        anchors.fill: parent
        clip: true
        spacing: 6
        cacheBuffer: 800
        boundsBehavior: Flickable.StopAtBounds
        model: root.visibleItems

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        header: Item {
            width: serverList.width
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
                        : (!NordVpnService.available || NordVpnService.needsLogin
                            ? Colors.warning : Styling.srItem("overprimary"))
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
                        tooltip: "Refresh live NordVPN servers",
                        loading: NordVpnService.isUpdating || NordVpnService.recommendationsUpdating,
                        enabled: NordVpnService.available,
                        onClicked: function () {
                            NordVpnService.refresh();
                        }
                    }])

                    onToggleChanged: {
                        if (NordVpnService.connected)
                            NordVpnService.disconnect();
                        else
                            root.requestConnect();
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
                        spacing: 8

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
                                        ? NordVpnService.flagForCode(
                                            NordVpnService.countryCodeForName(NordVpnService.country))
                                        : Icons.vpn
                                    font.family: NordVpnService.connected ? Config.theme.font : Icons.font
                                    font.pixelSize: NordVpnService.connected
                                        ? Styling.fontSize(6) : Styling.fontSize(3)
                                    color: NordVpnService.connected
                                        ? Styling.srItem("primary") : Colors.overBackground
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: NordVpnService.connected
                                        ? (NordVpnService.country || "NordVPN")
                                        : (root.p2pMode ? "Quick Connect · P2P" : "Quick Connect")
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(1)
                                    font.weight: Font.Medium
                                    color: NordVpnService.connected
                                        ? Styling.srItem("primary") : Colors.overBackground
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
                                            return [NordVpnService.city, NordVpnService.server,
                                                NordVpnService.technology]
                                                .filter(value => value !== "").join(" · ");
                                        return root.p2pMode
                                            ? "Best live P2P route for this network"
                                            : "Best live route for this network";
                                    }
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    color: NordVpnService.connected
                                        ? Styling.srItem("primary") : Colors.overSurfaceVariant
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
                                : (NordVpnService.connected ? "Disconnect" : "Quick Connect")

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
                    implicitHeight: browserColumn.implicitHeight + 24
                    visible: NordVpnService.available
                    variant: "internalbg"
                    radius: Styling.radius(4)

                    ColumnLayout {
                        id: browserColumn

                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 9

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: "Connection profile"
                                    font.family: Config.theme.font
                                    font.pixelSize: Config.theme.fontSize
                                    font.weight: Font.Medium
                                    color: Colors.overBackground
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.p2pMode
                                        ? "Prioritizes servers optimized for peer-to-peer traffic"
                                        : "Balances distance, capacity, and current server load"
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    color: Colors.overSurfaceVariant
                                    wrapMode: Text.Wrap
                                }
                            }
                        }

                        SegmentedSwitch {
                            Layout.fillWidth: true
                            buttonSize: 34
                            options: [
                                { label: "Standard", icon: Icons.globe },
                                { label: "P2P", icon: Icons.lightning }
                            ]
                            currentIndex: root.p2pMode ? 1 : 0

                            onIndexChanged: index => {
                                root.p2pMode = index === 1;
                                Config.system.nordvpn.preferredMode = root.p2pMode ? "p2p" : "fastest";
                                if (root.showLocations)
                                    root.setLocationsVisible(false);
                            }
                        }
                    }
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

                SearchInput {
                    id: browserSearch

                    Layout.fillWidth: true
                    visible: NordVpnService.available
                    placeholderText: root.showLocations
                        ? "Search all locations" : "Search live servers"
                    iconText: root.showLocations ? Icons.globe : Icons.vpn
                    onSearchTextChanged: text => root.searchText = text
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: NordVpnService.available
                    spacing: 8

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            Layout.fillWidth: true
                            text: root.showLocations ? "All locations" : "Recommended now"
                            font.family: Config.theme.font
                            font.pixelSize: Config.theme.fontSize
                            font.weight: Font.Medium
                            color: Colors.overBackground
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.showLocations
                                ? NordVpnService.countries.length + " live NordVPN locations"
                                : (NordVpnService.recommendationsUpdating
                                    && NordVpnService.recommendedServers.length === 0
                                    ? "Loading NordVPN's live feed…"
                                    : "Live load · updated "
                                        + (NordVpnService.recommendationsUpdatedAt || "just now"))
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: Colors.overSurfaceVariant
                            elide: Text.ElideRight
                        }
                    }

                    Button {
                        id: locationButton

                        implicitHeight: 32
                        text: root.showLocations ? "Live picks" : "All locations"
                        flat: true

                        background: StyledRect {
                            variant: locationButton.hovered ? "focus" : "common"
                            radius: Styling.radius(-4)
                        }

                        contentItem: Text {
                            text: locationButton.text
                            leftPadding: 10
                            rightPadding: 10
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            font.weight: Font.Medium
                            color: Colors.overBackground
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: root.setLocationsVisible(!root.showLocations)
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: !root.showLocations && NordVpnService.recommendationsError !== ""
                    text: NordVpnService.recommendationsError
                    wrapMode: Text.Wrap
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.warning
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
            id: serverDelegate

            required property var modelData
            width: serverList.width
            height: serverCard.height + 2

            readonly property bool isServer: modelData.kind === "server"
            readonly property bool isCurrentServer: isServer && NordVpnService.connected
                && NordVpnService.server.startsWith(modelData.serverKey)

            StyledRect {
                id: serverCard

                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                implicitHeight: serverDelegate.isServer ? 68 : 58
                variant: serverMouseArea.containsMouse ? "focus" : "common"
                radius: Styling.radius(4)

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10

                    Text {
                        Layout.preferredWidth: 32
                        text: serverDelegate.modelData.flag
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(5)
                        horizontalAlignment: Text.AlignHCenter
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            Layout.fillWidth: true
                            text: serverDelegate.isServer
                                ? [serverDelegate.modelData.country, serverDelegate.modelData.city]
                                    .filter(value => value !== "").join(" · ")
                                : serverDelegate.modelData.name
                            font.family: Config.theme.font
                            font.pixelSize: Config.theme.fontSize
                            font.weight: Font.Medium
                            color: Colors.overBackground
                            elide: Text.ElideRight
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                Layout.fillWidth: true
                                text: serverDelegate.isServer
                                    ? serverDelegate.modelData.hostname
                                    : (serverDelegate.modelData.serverCount
                                        + (serverDelegate.modelData.serverCount === 1
                                            ? " server · " : " servers · ")
                                        + serverDelegate.modelData.cityCount
                                        + (serverDelegate.modelData.cityCount === 1
                                            ? " city" : " cities"))
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                color: Colors.overSurfaceVariant
                                elide: Text.ElideRight
                            }

                            StyledRect {
                                implicitWidth: p2pLabel.implicitWidth + 10
                                implicitHeight: 20
                                visible: serverDelegate.isServer
                                    && serverDelegate.modelData.supportsP2p
                                variant: "internalbg"
                                radius: Styling.radius(-6)

                                Text {
                                    id: p2pLabel

                                    anchors.centerIn: parent
                                    text: "P2P"
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-3)
                                    font.weight: Font.Medium
                                    color: Colors.overSurfaceVariant
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        visible: serverDelegate.isServer
                        Layout.preferredWidth: 48
                        spacing: 3

                        Text {
                            Layout.alignment: Qt.AlignRight
                            text: serverDelegate.modelData.load + "%"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            font.weight: Font.Medium
                            color: root.loadColor(serverDelegate.modelData.load)
                        }

                        StyledRect {
                            Layout.preferredWidth: 48
                            Layout.preferredHeight: 4
                            variant: "internalbg"
                            radius: 2

                            StyledRect {
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: parent.width * serverDelegate.modelData.load / 100
                                variant: "focus"
                                color: root.loadColor(serverDelegate.modelData.load)
                                radius: 2
                            }
                        }
                    }

                    Text {
                        text: serverDelegate.isCurrentServer
                            || (!serverDelegate.isServer && NordVpnService.connected
                                && NordVpnService.country === serverDelegate.modelData.name)
                            ? Icons.shieldCheck : Icons.caretRight
                        font.family: Icons.font
                        font.pixelSize: Styling.fontSize(0)
                        color: serverDelegate.isCurrentServer
                            ? Styling.srItem("overprimary") : Colors.overSurfaceVariant
                    }
                }

                MouseArea {
                    id: serverMouseArea

                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: !NordVpnService.isUpdating && !VpnService.isSwitching
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (serverDelegate.isServer) {
                            root.requestServer(serverDelegate.modelData.serverKey);
                        } else {
                            Config.system.nordvpn.preferredCountry = serverDelegate.modelData.name;
                            root.requestConnect(serverDelegate.modelData.name);
                        }
                    }
                }
            }
        }

        footer: Item {
            width: serverList.width
            height: emptyState.visible ? emptyState.implicitHeight + 36 : 18

            Text {
                id: emptyState

                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 14
                visible: NordVpnService.available && serverList.count === 0
                    && !NordVpnService.recommendationsUpdating
                text: root.searchText !== ""
                    ? "No matching " + (root.showLocations ? "locations" : "live servers")
                    : (root.showLocations ? "No locations available"
                        : "No live recommendations available")
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                font.family: Config.theme.font
                font.pixelSize: Config.theme.fontSize
                color: Colors.overSurfaceVariant
            }
        }
    }
}
