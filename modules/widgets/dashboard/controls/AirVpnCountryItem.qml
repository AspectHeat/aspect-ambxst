pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

// One country row in the AirVPN browser. Extracted per plan §8 rather than inlined, following
// NordVpnCountryItem.qml / TailscalePeerItem.qml.
//
// Simpler than the NordVPN row by design: there is no city drill-down, because AirVPN's second
// level is individual servers and plan §1 rules a per-server browser out of v1. The row is a
// single line with no expandable region, so there is no reuseItems state to reset either.
Item {
    id: root

    required property AirVpnCountry country
    property bool compactMode: false

    readonly property bool isConnected: AirVpnService.connected
        && (root.country?.matchesStatusName(AirVpnService.country) ?? false)

    // isMutating, NOT isUpdating: gating on reads greys out every row on each poll tick.
    //
    // needsCredentials is deliberately NOT in here, unlike the NordVPN row. Browse works
    // uncredentialed, so the rows stay live and a click explains what is missing instead of the
    // whole list going inert - which is the pre-login UX this feature was asked for. connectTo()
    // still refuses, so the worst case is the banner below, never a stray CLI call.
    readonly property bool busy: AirVpnService.isMutating || VpnService.busy
        || VpnService.awaitingConfirmation
        || AirVpnService.permissionDenied
        || !AirVpnService.daemonReachable

    // A click that cannot connect must say why rather than doing nothing.
    readonly property bool gated: AirVpnService.needsCredentials

    signal loginRequested

    implicitHeight: contentRow.implicitHeight + 16

    StyledRect {
        anchors.fill: parent
        variant: rowMouseArea.containsMouse ? "focus" : "common"
        radius: Styling.radius(4)
    }

    // Declared before contentRow so the favorite button sits above it.
    MouseArea {
        id: rowMouseArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: !root.busy
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

        // Through VpnService, not AirVpnService: a direct call bypasses the confirmation and the
        // teardown of whichever provider currently owns the default route.
        onClicked: {
            if (root.gated) {
                root.loginRequested();
                return;
            }
            VpnService.requestProvider("airvpn", root.country?.token ?? "");
        }
    }

    RowLayout {
        id: contentRow

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 10

        // Emoji flag when the font has the glyph pair, otherwise a two-letter ISO badge. AirVPN
        // reports ISO alpha-2 natively, so no token->code map is involved.
        Item {
            Layout.preferredWidth: 26
            Layout.preferredHeight: 20

            Text {
                anchors.centerIn: parent
                visible: root.country?.hasFlag ?? false
                text: root.country?.flag ?? ""
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(2)
            }

            StyledRect {
                anchors.fill: parent
                visible: !(root.country?.hasFlag ?? false)
                variant: "internalbg"
                radius: Styling.radius(-6)

                Text {
                    anchors.centerIn: parent
                    text: root.country?.badge ?? "??"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-3)
                    font.weight: Font.DemiBold
                    color: Colors.overSurfaceVariant
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: root.country?.name ?? ""
                font.family: Config.theme.font
                font.pixelSize: Config.theme.fontSize
                color: Colors.overBackground
                elide: Text.ElideRight
            }

            // Server count is worth showing where NordVPN showed cities: it is the honest
            // measure of how much choice a country actually has, and it comes free in the same
            // table row. Hidden when the CLI did not report it, per §3.
            Text {
                Layout.fillWidth: true
                visible: !root.compactMode && (root.country?.servers ?? 0) > 0
                text: (root.country?.servers ?? 0) + ((root.country?.servers ?? 0) === 1
                        ? " server" : " servers")
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-3)
                color: Colors.overSurfaceVariant
                elide: Text.ElideRight
            }
        }

        Text {
            visible: root.isConnected
            text: "Connected"
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-2)
            color: Styling.srItem("overprimary")
        }

        // Load percentage. Colour-coded because the number only means anything relative to a
        // threshold, and -1 (not reported) hides the row entirely rather than showing 0%.
        Text {
            visible: (root.country?.hasLoad ?? false) && !root.isConnected
            text: (root.country?.load ?? 0) + "%"
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-2)
            color: (root.country?.load ?? 0) >= 85 ? Colors.error
                : (root.country?.load ?? 0) >= 65 ? Colors.warning
                : Colors.overSurfaceVariant

            StyledToolTip {
                visible: loadHover.hovered
                tooltipText: "Current load across this country's servers"
            }

            HoverHandler {
                id: loadHover
            }
        }

        // Persistent favorite toggle. Config-only, so it stays available while a network
        // mutation is in flight and while logged out.
        Button {
            id: favoriteButton

            flat: true
            implicitWidth: 28
            implicitHeight: 28

            readonly property bool selected: AirVpnService.isFavorite(root.country?.token ?? "")

            background: StyledRect {
                variant: favoriteButton.hovered ? "focus" : "common"
                radius: Styling.radius(-4)
            }

            contentItem: Text {
                text: favoriteButton.selected ? "★" : "☆"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(1)
                color: favoriteButton.selected
                    ? Styling.srItem("overprimary") : Colors.overSurfaceVariant
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: AirVpnService.toggleFavorite(root.country?.token ?? "")

            StyledToolTip {
                visible: favoriteButton.hovered
                tooltipText: favoriteButton.selected
                    ? "Remove from favorites" : "Add to favorites"
            }
        }
    }
}
