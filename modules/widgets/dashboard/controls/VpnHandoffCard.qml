pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

// Confirmation, in-flight phase, and failure recovery for a provider handoff.
//
// This exists as its own component because a handoff can be STARTED from four places - the
// provider hub, the NordVPN page, the Tailscale page, and the Tailscale tray popup - and the
// confirmation must be reachable from all of them. Previously the confirm controls lived
// inside the hub's column, which is hidden whenever a provider page is open, so confirming a
// switch from a provider page was impossible: the titlebar asked "Switch to NordVPN?" and
// offered no way to answer. Self-gates on VpnService, so a host only has to place it.
StyledRect {
    id: root

    // Lets a host suppress the card without fighting its internal visibility. Needed because
    // TailscalePanel is reused in both full settings (where VpnPanel already provides one)
    // and the tray popup (where it must provide its own).
    property bool hostEnabled: true

    readonly property bool active: VpnService.awaitingConfirmation
        || VpnService.busy
        || VpnService.handoffPhase === "failed"

    visible: root.hostEnabled && root.active
    implicitHeight: root.visible ? contentColumn.implicitHeight + 20 : 0
    variant: "internalbg"
    radius: Styling.radius(4)

    ColumnLayout {
        id: contentColumn

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 6

        Text {
            Layout.fillWidth: true
            // Scoped through statusTextFor(), so this never shows the other provider's phase.
            text: VpnService.statusTextFor(VpnService.handoffTarget)
            wrapMode: Text.Wrap
            font.family: Config.theme.font
            font.pixelSize: Config.theme.fontSize
            font.weight: VpnService.awaitingConfirmation ? Font.Medium : Font.Normal
            color: VpnService.handoffPhase === "failed" ? Colors.error : Colors.overBackground
        }

        Text {
            Layout.fillWidth: true
            visible: VpnService.awaitingConfirmation
            // Names the consequence in plain language. "Handoff" and "default route" mean
            // nothing to someone who just wants their VPN on.
            text: VpnService.labelFor(VpnService.routeOwner)
                + " is carrying your internet traffic right now and will be turned off first."
                + " Your connection will drop for a few seconds."
            wrapMode: Text.Wrap
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-2)
            color: Colors.overSurfaceVariant
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            visible: VpnService.awaitingConfirmation
            spacing: 8

            Button {
                id: confirmButton
                Layout.fillWidth: true
                flat: true
                implicitHeight: 32

                background: StyledRect {
                    variant: confirmButton.hovered ? "primaryfocus" : "primary"
                    radius: Styling.radius(-2)
                }

                contentItem: Text {
                    text: Icons.accept + "  Switch to " + VpnService.labelFor(VpnService.handoffTarget)
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    color: Styling.srItem("primary")
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                onClicked: VpnService.confirmHandoff()
            }

            Button {
                id: cancelButton
                Layout.preferredWidth: 96
                flat: true
                implicitHeight: 32

                background: StyledRect {
                    variant: cancelButton.hovered ? "focus" : "common"
                    radius: Styling.radius(-2)
                }

                contentItem: Text {
                    text: Icons.cancel + "  Cancel"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    color: Colors.overBackground
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: VpnService.cancelHandoff()
            }
        }

        // Explicit recovery only - a failed handoff never silently restores the previous
        // provider, because a surprise network change is worse than a visible error.
        Button {
            id: recoverButton
            Layout.fillWidth: true
            Layout.topMargin: 2
            visible: VpnService.handoffPhase === "failed" && VpnService.recoveryProvider !== ""
            flat: true
            implicitHeight: 30

            background: StyledRect {
                variant: recoverButton.hovered ? "focus" : "common"
                radius: Styling.radius(-2)
            }

            contentItem: Text {
                text: "Reconnect " + VpnService.labelFor(VpnService.recoveryProvider)
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                color: Colors.overBackground
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: VpnService.recover()
        }

        Button {
            id: dismissButton
            Layout.fillWidth: true
            visible: VpnService.handoffPhase === "failed"
            flat: true
            implicitHeight: 28

            background: StyledRect {
                variant: dismissButton.hovered ? "focus" : "common"
                radius: Styling.radius(-2)
            }

            contentItem: Text {
                text: "Dismiss"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            // Without this a failed handoff has no exit: the strip would persist until some
            // other action happened to clear it.
            onClicked: VpnService.dismissFailure()
        }
    }
}
