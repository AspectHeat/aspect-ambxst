pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

// NordVPN provider page. Shell only - the header and the row delegate live in their own
// files (plan section 8). This file owns the list, the filter, and the wiring.
Item {
    id: root

    property int maxContentWidth: 480
    property bool compactMode: false
    property bool showBackButton: false
    property string searchText: ""

    signal backRequested

    readonly property int contentWidth: Math.min(width, root.maxContentWidth)

    readonly property var visibleCountries: {
        const query = root.searchText.trim().toLowerCase();
        const all = NordVpnService.sortedCountries;
        if (query === "")
            return all;
        // searchKey is precomputed on NordVpnCountry so filtering 149 rows per keystroke
        // does not rebuild the haystack. Matches display name, CLI token, and ISO code.
        return all.filter(country => country.searchKey.includes(query));
    }

    // Section 7.3 state x surface matrix. Every state has defined copy. A handoff targeting
    // NordVPN takes precedence; one targeting Tailscale is deliberately NOT shown here -
    // that cross-talk is the v1 bug where this page announced "Disconnecting Tailscale...".
    readonly property string statusText: {
        const handoff = VpnService.statusTextFor("nordvpn");
        if (handoff !== "")
            return handoff;
        if (NordVpnService.permissionDenied)
            return "Permission denied";
        if (!NordVpnService.available)
            return "Not installed";
        if (!NordVpnService.daemonReachable)
            return "Daemon unavailable";
        if (NordVpnService.needsLogin)
            return "Log in required";
        if (NordVpnService.connecting)
            return "Connecting…";
        if (NordVpnService.disconnecting)
            return "Disconnecting…";
        if (NordVpnService.connected)
            return NordVpnService.country !== "" ? NordVpnService.country : "Connected";
        if (NordVpnService.inError)
            return NordVpnService.lastError !== "" ? NordVpnService.lastError : "Error";
        return "Disconnected";
    }

    readonly property color statusColor: {
        if (NordVpnService.inError || NordVpnService.lastError !== ""
            || VpnService.handoffPhase === "failed")
            return Colors.error;
        if (!NordVpnService.available || NordVpnService.needsLogin
            || NordVpnService.permissionDenied || !NordVpnService.daemonReachable)
            return Colors.warning;
        return Styling.srItem("overprimary");
    }

    function positionAtBeginning(): void {
        countryList.contentY = countryList.headerItem
            ? countryList.headerItem.y : countryList.originY;
    }

    function focusSearchInput(): void {
        if (countryList.headerItem)
            countryList.headerItem.focusSearch();
    }

    // Clear any stale handoff phase or error from a previous attempt on mount, so it cannot
    // persist on screen. v1 rendered lastError indefinitely.
    Component.onCompleted: {
        VpnService.clearTransient();
        initialRefreshTimer.start();
        Qt.callLater(() => root.positionAtBeginning());
    }

    Timer {
        id: initialRefreshTimer
        interval: 300
        repeat: false
        onTriggered: NordVpnService.refresh()
    }

    ListView {
        id: countryList

        anchors.fill: parent
        clip: true
        spacing: 4
        cacheBuffer: 1000
        reuseItems: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        model: root.visibleCountries

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        header: Item {
            id: headerWrapper

            width: countryList.width
            height: headerContent.implicitHeight + 8

            function focusSearch(): void {
                headerContent.focusSearchInput();
            }

            NordVpnPanelHeader {
                id: headerContent

                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                contentWidth: root.contentWidth
                showBackButton: root.showBackButton
                statusText: root.statusText
                statusColor: root.statusColor

                onBackRequested: root.backRequested()
                onSearchTextChanged: text => root.searchText = text
            }
        }

        delegate: Item {
            id: rowWrapper

            required property var modelData

            width: countryList.width
            height: countryItem.implicitHeight

            NordVpnCountryItem {
                id: countryItem

                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                country: rowWrapper.modelData
                compactMode: root.compactMode
            }
        }

        // Distinguishes "no results for this search" from "the CLI reported no countries",
        // which are different problems with different remedies.
        Text {
            anchors.centerIn: parent
            width: root.contentWidth - 24
            visible: countryList.count === 0 && NordVpnService.available
                && !NordVpnService.needsLogin && !NordVpnService.permissionDenied
            text: NordVpnService.countryCount === 0
                ? "No locations reported by the NordVPN CLI. Try refreshing."
                : "No countries match “" + root.searchText + "”"
            horizontalAlignment: Text.AlignHCenter
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-2)
            color: Colors.overSurfaceVariant
            wrapMode: Text.Wrap
        }
    }
}
