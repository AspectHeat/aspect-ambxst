pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

// AirVPN provider page. Shell only - the header and the row delegate live in their own files
// (plan §8). This file owns the list, the filter, and the wiring.
Item {
    id: root

    property int maxContentWidth: 480
    property bool compactMode: false
    property bool showBackButton: false
    property string searchText: ""
    property bool awaitingAdvancedRelayout: false

    // Set when a country row was clicked while logged out, so the answer lands on the control
    // that explains it rather than nowhere. Cleared once the user has credentials.
    property bool loginHinted: false

    signal backRequested

    readonly property int contentWidth: Math.min(width, root.maxContentWidth)

    readonly property var visibleCountries: {
        const query = root.searchText.trim().toLowerCase();
        const all = AirVpnService.sortedCountries;
        if (query === "")
            return all;
        // searchKey is precomputed on AirVpnCountry so filtering per keystroke does not rebuild
        // the haystack. Matches display name and ISO code.
        return all.filter(country => country.searchKey.includes(query));
    }

    // Plan §7.3 state x surface matrix. Every state has defined copy. A handoff targeting AirVPN
    // takes precedence; one targeting another provider is deliberately NOT shown here - that
    // cross-talk is the v1 bug where the NordVPN page announced "Disconnecting Tailscale...".
    readonly property string statusText: {
        const handoff = VpnService.statusTextFor("airvpn");
        if (handoff !== "")
            return handoff;
        if (AirVpnService.permissionDenied)
            return "Permission denied";
        if (!AirVpnService.available)
            return "Not installed";
        if (!AirVpnService.daemonReachable)
            return "Daemon unavailable";
        if (AirVpnService.needsCredentials)
            return "Log in required";
        if (AirVpnService.connecting)
            return "Connecting…";
        if (AirVpnService.disconnecting)
            return "Disconnecting…";
        if (AirVpnService.connected)
            return AirVpnService.country !== "" ? AirVpnService.country : "Connected";
        if (AirVpnService.inError)
            return AirVpnService.lastError !== "" ? AirVpnService.lastError : "Error";
        return "Disconnected";
    }

    readonly property color statusColor: {
        if (AirVpnService.inError || AirVpnService.lastError !== ""
            || VpnService.handoffPhase === "failed")
            return Colors.error;
        if (!AirVpnService.available || AirVpnService.needsCredentials
            || AirVpnService.permissionDenied || !AirVpnService.daemonReachable)
            return Colors.warning;
        return Styling.srItem("overprimary");
    }

    function positionAtBeginning(): void {
        // Let ListView resolve its own origin. With an inline header, headerItem.y can track the
        // viewport after the header changes height; assigning that value back to contentY is then
        // a no-op. positionViewAtBeginning() accounts for the newly expanded header.
        countryList.positionViewAtBeginning();
    }

    function focusSearchInput(): void {
        countrySearch.focusInput();
    }

    // Clear any stale handoff phase or error from a previous attempt on mount, so it cannot
    // persist on screen.
    Component.onCompleted: {
        VpnService.clearTransient();
        initialRefreshTimer.start();
        // Browse works with no credentials, so the list is fetched on every visit regardless of
        // login state. The service latches this if its availability probe has not answered yet.
        AirVpnService.ensureCountries();
        Qt.callLater(() => root.positionAtBeginning());
    }

    Timer {
        id: initialRefreshTimer
        interval: 300
        repeat: false
        onTriggered: AirVpnService.refresh()
    }

    // Once credentials appear the hint has served its purpose; leaving it up would nag someone
    // who has already done the thing it asks for.
    Connections {
        target: AirVpnService

        function onNeedsCredentialsChanged() {
            if (!AirVpnService.needsCredentials)
                root.loginHinted = false;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        // Pinned, NOT inside the ListView. A ListView re-lays-out its header whenever the model
        // resets, and the model resets on every keystroke of the country filter, which was taking
        // focus off the search field after each character.
        //
        // PanelTitlebar declares Layout.fillWidth for use inside a bounded header column, so it
        // is wrapped rather than mounted directly in this full-width column - otherwise that hint
        // overrides contentWidth and spreads the title across the whole dashboard.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 36

            PanelTitlebar {
                width: root.contentWidth
                height: parent.height
                anchors.horizontalCenter: parent.horizontalCenter
                title: "AirVPN"
                statusText: root.statusText
                statusColor: root.statusColor
                showToggle: AirVpnService.available && !AirVpnService.needsCredentials
                    && !AirVpnService.permissionDenied
                toggleChecked: AirVpnService.connected
                toggleEnabled: !AirVpnService.isMutating && !VpnService.busy
                    && !VpnService.awaitingConfirmation

                actions: (root.showBackButton ? [{
                    icon: Icons.caretLeft,
                    tooltip: "Back to VPN providers",
                    onClicked: function () {
                        root.backRequested();
                    }
                }] : []).concat([{
                    icon: Icons.sync,
                    tooltip: "Refresh AirVPN state",
                    loading: AirVpnService.isUpdating,
                    enabled: AirVpnService.available,
                    onClicked: function () {
                        AirVpnService.refreshCountries();
                        AirVpnService.refresh();
                    }
                }])

                onToggleChanged: checked => {
                    if (checked)
                        VpnService.requestProvider("airvpn",
                            Config.system.airvpn.preferredCountry);
                    else
                        AirVpnService.disconnect();
                }
            }
        }

        SearchInput {
            id: countrySearch
            Layout.preferredWidth: root.contentWidth
            Layout.alignment: Qt.AlignHCenter
            // Not gated on credentials: the list it filters is available before login.
            visible: AirVpnService.available && AirVpnService.countryCount > 0
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

                // ListView preserves the first delegate's screen position when an inline header
                // grows, adjusting contentY after the Advanced click handler runs. React to the
                // resulting geometry change instead, then reset one event-loop turn later after
                // that compensation has been applied.
                onHeightChanged: {
                    if (root.awaitingAdvancedRelayout && headerContent.advancedExpanded) {
                        Qt.callLater(() => {
                            root.positionAtBeginning();
                            root.awaitingAdvancedRelayout = false;
                        });
                    }
                }

                AirVpnPanelHeader {
                    id: headerContent

                    width: root.contentWidth
                    anchors.horizontalCenter: parent.horizontalCenter
                    contentWidth: root.contentWidth

                    // Only an explicit closed -> open action earns a scroll reset. Connection and
                    // status updates also change this header's height; treating those as expansion
                    // relayouts jumped the user to the top after choosing a country.
                    onAdvancedExpandedChanged: {
                        root.awaitingAdvancedRelayout = headerContent.advancedExpanded;
                    }

                    onLoginRequested: root.noteLoginNeeded()
                }
            }

            delegate: Item {
                id: rowWrapper

                required property var modelData

                width: countryList.width
                height: countryItem.implicitHeight

                AirVpnCountryItem {
                    id: countryItem

                    width: root.contentWidth
                    anchors.horizontalCenter: parent.horizontalCenter
                    country: rowWrapper.modelData
                    compactMode: root.compactMode

                    onLoginRequested: root.noteLoginNeeded()
                }
            }

            // Distinguishes "no results for this search" from "the CLI reported no countries",
            // which are different problems with different remedies.
            Text {
                anchors.centerIn: parent
                width: root.contentWidth - 24
                visible: countryList.count === 0 && AirVpnService.available
                    && !AirVpnService.permissionDenied && AirVpnService.daemonReachable
                text: AirVpnService.countriesLoading
                        ? "Loading countries…"
                    : AirVpnService.countryCount === 0
                        ? "No locations reported by goldcrest. Try refreshing."
                        : "No countries match “" + root.searchText + "”"
                horizontalAlignment: Text.AlignHCenter
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
                wrapMode: Text.Wrap
            }
        }
    }

    // Answer to a country click made while logged out. The rows stay live on purpose - browse
    // works without credentials - so the click has to land somewhere, and scrolling the user back
    // to the setup card is more useful than a toast that disappears.
    function noteLoginNeeded(): void {
        if (!AirVpnService.needsCredentials)
            return;
        root.loginHinted = true;
        root.positionAtBeginning();
        hintTimer.restart();
    }

    Timer {
        id: hintTimer
        interval: 6000
        repeat: false
        onTriggered: root.loginHinted = false
    }

    // Floats over the list rather than displacing it, so the row the user clicked stays put.
    StyledRect {
        z: 2
        visible: root.loginHinted && AirVpnService.needsCredentials
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 8
        width: root.contentWidth
        implicitHeight: 34
        variant: "internalbg"
        radius: Styling.radius(4)

        Text {
            anchors.centerIn: parent
            width: parent.width - 20
            text: "Add your AirVPN credentials before connecting — see the card above"
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-2)
            color: Colors.warning
        }
    }
}
