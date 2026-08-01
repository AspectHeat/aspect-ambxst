pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

// The NordVPN page's scrolling header content: setup card, connection card, Quick Connect,
// mode selector, advanced settings, and service errors.
//
// The titlebar and the search field deliberately do NOT live here. They are pinned by
// NordVpnPanel outside the ListView, because a ListView re-lays-out its header on every
// model reset - and the model resets on every keystroke of the country filter, which took
// focus away from the search field after each character. SettingsTab uses the same
// SearchInput outside a ListView and does not have the problem.
ColumnLayout {
    id: root

    property int contentWidth: 480
    readonly property bool advancedExpanded: advancedCard.expanded

    spacing: 8

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

    // ------------------------------------------------------------ favorites
    Button {
        id: favoritesButton

        Layout.fillWidth: true
        flat: true
        implicitHeight: 32
        leftPadding: 12
        rightPadding: 12

        background: StyledRect {
            variant: favoritesButton.hovered ? "focus" : "common"
            radius: Styling.radius(-2)
        }

        contentItem: RowLayout {
            spacing: 6

            Text {
                text: "Favorites"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                color: Colors.overBackground
            }

            Text {
                visible: NordVpnService.favoriteCountries.length > 0
                text: String(NordVpnService.favoriteCountries.length)
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-3)
                color: Colors.overSurfaceVariant
            }

            Item {
                Layout.fillWidth: true
            }

            Text {
                text: favoritesButton.checked ? Icons.caretUp : Icons.caretDown
                font.family: Icons.font
                font.pixelSize: Styling.fontSize(-1)
                color: Colors.overSurfaceVariant
            }
        }

        checkable: true
    }

    StyledRect {
        Layout.fillWidth: true
        visible: favoritesButton.checked
        implicitHeight: favoritesColumn.implicitHeight + 20
        variant: "internalbg"
        radius: Styling.radius(4)

        ColumnLayout {
            id: favoritesColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 10
            spacing: 6

            Text {
                Layout.fillWidth: true
                visible: NordVpnService.favoriteCountries.length === 0
                text: "Star a country below to add it here."
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
                wrapMode: Text.Wrap
            }

            Repeater {
                model: NordVpnService.favoriteCountries

                delegate: NordVpnCountryItem {
                    required property var modelData

                    Layout.fillWidth: true
                    country: modelData
                }
            }
        }
    }

    NordVpnAdvancedCard {
        id: advancedCard

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
}
