pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
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
        // Let ListView resolve its own origin. With an inline header, headerItem.y can track
        // the viewport after the header changes height; assigning that value back to contentY
        // is then a no-op. positionViewAtBeginning() accounts for the newly expanded header
        // and returns to its actual leading edge.
        countryList.positionViewAtBeginning();
    }

    function focusSearchInput(): void {
        countrySearch.focusInput();
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

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // Pinned, NOT inside the ListView. A ListView re-lays-out its header whenever the
        // model resets, and the model resets on every keystroke of the country filter, which
        // was taking focus off the search field after each character. Keeping both out of the
        // view also means the back button and the filter stay reachable while scrolling 149
        // countries, which is better for a list this long anyway.
        // PanelTitlebar declares Layout.fillWidth for use inside a bounded header column.
        // Mounting it directly in this full-width column let that hint override the requested
        // contentWidth, spreading the title and toggle across the whole dashboard. Tailscale
        // contains it in a content-width header; this wrapper gives NordVPN the same contract.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 36

            PanelTitlebar {
                width: root.contentWidth
                height: parent.height
                anchors.horizontalCenter: parent.horizontalCenter
                title: "NordVPN"
                statusText: root.statusText
                statusColor: root.statusColor
                showToggle: NordVpnService.available && !NordVpnService.needsLogin
                    && !NordVpnService.permissionDenied
                toggleChecked: NordVpnService.connected
                toggleEnabled: !NordVpnService.isMutating && !VpnService.busy
                    && !VpnService.awaitingConfirmation

                actions: (root.showBackButton ? [{
                    icon: Icons.caretLeft,
                    tooltip: "Back to VPN providers",
                    onClicked: function () {
                        root.backRequested();
                    }
                }] : []).concat([{
                    icon: Icons.sync,
                    tooltip: "Refresh NordVPN state",
                    loading: NordVpnService.isUpdating,
                    enabled: NordVpnService.available,
                    onClicked: function () {
                        NordVpnService.refreshCountries();
                        NordVpnService.refresh();
                    }
                }])

                onToggleChanged: checked => {
                    if (checked)
                        VpnService.requestProvider("nordvpn", Config.system.nordvpn.preferredCountry,
                            NordVpnService.p2pPreferred);
                    else
                        NordVpnService.disconnect();
                }
            }
        }

        SearchInput {
            id: countrySearch
            Layout.preferredWidth: root.contentWidth
            Layout.alignment: Qt.AlignHCenter
            visible: NordVpnService.available && NordVpnService.countryCount > 0
            implicitHeight: 40
            variant: "internalbg"
            placeholderText: "Search countries"
            iconText: Icons.globe
            onSearchTextChanged: text => root.searchText = text
        }

        ListView {
            id: countryList

            Layout.fillWidth: true
            Layout.fillHeight: true
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
                id: countryHeader

                width: countryList.width
                height: headerContent.implicitHeight + 8

                // ListView preserves the first delegate's screen position when an inline
                // header grows, adjusting contentY after the Advanced click handler runs.
                // React to the resulting geometry change instead, then reset one event-loop
                // turn later after that compensation has been applied.
                onHeightChanged: {
                    if (headerContent.advancedExpanded)
                        Qt.callLater(() => root.positionAtBeginning());
                }

                NordVpnPanelHeader {
                    id: headerContent

                    width: root.contentWidth
                    anchors.horizontalCenter: parent.horizontalCenter
                    contentWidth: root.contentWidth
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
}
