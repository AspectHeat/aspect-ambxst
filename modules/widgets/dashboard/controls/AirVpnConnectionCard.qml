pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

// The connected-state detail card. Every field is independently optional: the connected form of
// `goldcrest --bluetit-status` is still unverified (an unauthenticated Suite never prints it, and
// Bostrom is not logged in), so each line composes from whatever is present and disappears when
// nothing is. Per plan §3 a missing field hides its row rather than rendering a blank label.
StyledRect {
    id: root

    readonly property string locationLine:
        AirVpnService.country !== "" ? AirVpnService.country : "Connected"

    readonly property string detailLine: {
        const parts = [];
        if (AirVpnService.server !== "")
            parts.push(AirVpnService.server);
        if (AirVpnService.technology !== "")
            parts.push(AirVpnService.technology);
        // Only stated when the CLI actually reported it, so "lock off" is never a guess.
        if (AirVpnService.networkLockKnown)
            parts.push(AirVpnService.networkLock ? "lock on" : "lock off");
        return parts.join(" · ");
    }

    visible: AirVpnService.connected
    implicitHeight: contentColumn.implicitHeight + 20
    variant: "internalbg"
    radius: Styling.radius(4)

    ColumnLayout {
        id: contentColumn

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 4

        Text {
            Layout.fillWidth: true
            text: root.locationLine
            font.family: Config.theme.font
            font.pixelSize: Config.theme.fontSize
            font.weight: Font.Medium
            color: Colors.overBackground
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            visible: root.detailLine !== ""
            text: root.detailLine
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-2)
            color: Colors.overSurfaceVariant
            elide: Text.ElideRight
        }

        // Warned about here rather than only at the toggle, because this is the surface the user
        // is looking at while the lock is actually in force.
        Text {
            Layout.fillWidth: true
            visible: AirVpnService.networkLockKnown && AirVpnService.networkLock
            text: "Network Lock is active. If the tunnel drops, all other traffic — including "
                + "SSH and Tailscale — stops until it recovers."
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-3)
            color: Colors.warning
            wrapMode: Text.Wrap
        }

        Button {
            id: disconnectButton
            Layout.topMargin: 4
            Layout.fillWidth: true
            // The detail text keeps the card's 12px reading inset, while the primary action
            // reaches slightly farther toward the card edges to align with the wider controls
            // below it.
            Layout.leftMargin: -6
            Layout.rightMargin: -6
            flat: true
            implicitHeight: 32
            // Disabled during a handoff as well as a local mutation, so the user cannot issue a
            // second network change while one is already in flight.
            enabled: !AirVpnService.isMutating && !VpnService.busy

            background: StyledRect {
                variant: disconnectButton.hovered ? "focus" : "common"
                radius: Styling.radius(-2)
            }

            contentItem: Text {
                text: "Disconnect"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                color: disconnectButton.enabled ? Colors.overBackground : Colors.outline
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: AirVpnService.disconnect()
        }
    }
}
