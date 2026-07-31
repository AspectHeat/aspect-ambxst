pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

// The connected-state detail card. Every field is independently optional: the connected form
// of `nordvpn status` is still unverified (a logged-out CLI never prints it), so each line
// composes from whatever is present and disappears when nothing is. Per plan section 3, a
// missing field hides its row rather than rendering a blank label or a placeholder.
StyledRect {
    id: root

    readonly property string locationLine: {
        const parts = [];
        if (NordVpnService.country !== "")
            parts.push(NordVpnService.country);
        if (NordVpnService.city !== "")
            parts.push(NordVpnService.city);
        return parts.length > 0 ? parts.join(" · ") : "Connected";
    }

    readonly property string detailLine: {
        const parts = [];
        if (NordVpnService.server !== "")
            parts.push(NordVpnService.server);
        if (NordVpnService.technology !== "")
            parts.push(NordVpnService.technology);
        if (NordVpnService.uptime !== "")
            parts.push("up " + NordVpnService.uptime);
        return parts.join(" · ");
    }

    visible: NordVpnService.connected
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

        Button {
            id: disconnectButton
            Layout.topMargin: 4
            Layout.fillWidth: true
            flat: true
            implicitHeight: 32
            // Disabled during a handoff as well as a local mutation, so the user cannot
            // issue a second network change while one is already in flight.
            enabled: !NordVpnService.isMutating && !VpnService.busy

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

            onClicked: NordVpnService.disconnect()
        }
    }
}
