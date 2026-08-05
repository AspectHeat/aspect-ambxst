pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

// The AirVPN page's scrolling header content: setup card, connection card, Quick Connect,
// favorites, advanced settings, and service errors.
//
// The titlebar and the search field deliberately do NOT live here. They are pinned by
// AirVpnPanel outside the ListView, because a ListView re-lays-out its header on every model
// reset - and the model resets on every keystroke of the country filter, which took focus away
// from the search field after each character.
ColumnLayout {
    id: root

    property int contentWidth: 480
    readonly property bool advancedExpanded: advancedCard.expanded

    signal loginRequested

    spacing: 8

    // Both cards self-gate on service state, so the header does not duplicate those conditions.
    AirVpnSetupCard {
        Layout.fillWidth: true
    }

    AirVpnConnectionCard {
        Layout.fillWidth: true
    }

    // ------------------------------------------------------------ quick connect
    Button {
        id: quickConnectButton
        Layout.fillWidth: true
        // Hidden rather than disabled while logged out: the setup card immediately above already
        // says what is missing, and a dead primary button beside that explanation reads as a
        // broken widget rather than a prerequisite.
        visible: AirVpnService.available && !AirVpnService.connected
            && !AirVpnService.needsCredentials
            && !AirVpnService.permissionDenied && AirVpnService.daemonReachable
        flat: true
        implicitHeight: 40
        enabled: !AirVpnService.isMutating && !VpnService.busy
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

        // Reuses the last country-level pick, exactly as NordVPN's does. With no pick yet the
        // empty target lets Bluetit choose, which is what "best available" means here.
        onClicked: VpnService.requestProvider("airvpn", Config.system.airvpn.preferredCountry)
    }

    Text {
        Layout.fillWidth: true
        visible: quickConnectButton.visible
        text: Config.system.airvpn.preferredCountry !== ""
            ? "Reconnects to " + Config.system.airvpn.preferredCountry
                + " · " + (AirVpnService.wireGuardPreferred ? "WireGuard" : "OpenVPN")
            : "Best available · " + (AirVpnService.wireGuardPreferred ? "WireGuard" : "OpenVPN")
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
        checkable: true

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
                visible: AirVpnService.favoriteCountries.length > 0
                text: String(AirVpnService.favoriteCountries.length)
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-3)
                color: Colors.overSurfaceVariant
            }

            Item {
                Layout.fillWidth: true
            }

            Text {
                text: favoritesButton.checked ? Icons.caretDown : Icons.caretRight
                font.family: Icons.font
                font.pixelSize: Styling.fontSize(-1)
                color: Colors.overSurfaceVariant
            }
        }
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
                visible: AirVpnService.favoriteCountries.length === 0
                text: "Star a country below to add it here."
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
                wrapMode: Text.Wrap
            }

            Repeater {
                model: AirVpnService.favoriteCountries

                delegate: AirVpnCountryItem {
                    required property var modelData

                    Layout.fillWidth: true
                    country: modelData

                    onLoginRequested: root.loginRequested()
                }
            }
        }
    }

    AirVpnAdvancedCard {
        id: advancedCard

        Layout.fillWidth: true
    }

    // Service-level errors only. Handoff failure and its recovery action live in VpnHandoffCard,
    // which every host mounts - duplicating them here showed the same failure twice.
    Text {
        Layout.fillWidth: true
        visible: AirVpnService.lastError !== ""
        text: AirVpnService.lastError
        font.family: Config.theme.font
        font.pixelSize: Styling.fontSize(-2)
        color: Colors.error
        wrapMode: Text.Wrap
    }
}
