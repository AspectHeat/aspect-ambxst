pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

// The NordVPN page's ListView.header content: titlebar, connection card, mode selector,
// search, and error/recovery strip. Extracted per plan section 8 - v1 inlined ~340 lines
// of this directly into the ListView.
ColumnLayout {
    id: root

    property int contentWidth: 480
    property bool showBackButton: false
    property string statusText: ""
    property color statusColor: Styling.srItem("overprimary")

    signal backRequested
    signal searchTextChanged(string text)

    function clearSearch(): void {
        countrySearch.clear();
    }

    function focusSearchInput(): void {
        countrySearch.focusInput();
    }

    spacing: 8

    PanelTitlebar {
        Layout.fillWidth: true
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

    // Both cards self-gate on service state, so the header does not duplicate those
    // conditions. Extracted per plan section 8 - v1 inlined all of this.
    NordVpnSetupCard {
        Layout.fillWidth: true
    }

    NordVpnConnectionCard {
        Layout.fillWidth: true
    }

    // ------------------------------------------------------------ quick connect
    Button {
        id: quickConnectButton
        Layout.fillWidth: true
        visible: NordVpnService.available && !NordVpnService.connected
            && !NordVpnService.needsLogin && !NordVpnService.permissionDenied
        flat: true
        implicitHeight: 40
        enabled: !NordVpnService.isMutating && !VpnService.busy
            && !VpnService.awaitingConfirmation

        background: StyledRect {
            variant: quickConnectButton.hovered ? "primaryfocus" : "primary"
            radius: Styling.radius(-2)
        }

        contentItem: Text {
            text: Icons.lightning + "  Quick Connect"
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-1)
            font.weight: Font.Medium
            color: Styling.srItem("primary")
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }

        onClicked: VpnService.requestProvider("nordvpn",
            Config.system.nordvpn.preferredCountry, NordVpnService.p2pPreferred)
    }

    // ------------------------------------------------------------ mode selector
    // Hidden entirely when `nordvpn groups` did not report a P2P group, per section 3.
    SegmentedSwitch {
        Layout.fillWidth: true
        visible: NordVpnService.available && NordVpnService.supportsP2p
        buttonSize: 32
        options: [
            { label: "Standard", icon: Icons.globe, tooltip: "Recommended servers" },
            { label: "P2P", icon: Icons.lightning, tooltip: "Request the P2P-optimized group" }
        ]
        currentIndex: NordVpnService.p2pPreferred ? 1 : 0

        // currentIndex self-assigns on click and breaks its binding (see plan 9.4), so the
        // value is re-derived from Config rather than trusted from the component.
        onIndexChanged: index => {
            Config.system.nordvpn.preferredMode = index === 1 ? "p2p" : "standard";
        }
    }

    Text {
        Layout.fillWidth: true
        visible: NordVpnService.available && NordVpnService.supportsP2p
        text: "Standard servers also carry P2P traffic. P2P mode explicitly requests the optimized group."
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(-3)
        color: Colors.overSurfaceVariant
        wrapMode: Text.Wrap
    }

    NordVpnAdvancedCard {
        Layout.fillWidth: true
    }

    // Service-level errors only. Handoff failure and its recovery action live in
    // VpnHandoffCard, which every host mounts - duplicating them here showed the same
    // failure twice.
    Text {
        Layout.fillWidth: true
        visible: NordVpnService.lastError !== ""
        text: NordVpnService.lastError
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(-2)
        color: Colors.error
        wrapMode: Text.Wrap
    }

    // ------------------------------------------------------------ search
    SearchInput {
        id: countrySearch
        Layout.fillWidth: true
        visible: NordVpnService.available && NordVpnService.countryCount > 0
        implicitHeight: 40
        variant: "internalbg"
        placeholderText: "Search countries"
        iconText: Icons.globe
        onSearchTextChanged: text => root.searchTextChanged(text)
    }
}
