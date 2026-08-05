pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

// Shown when AirVPN cannot be used yet: missing Suite, unreachable Bluetit daemon, permission
// problem, or no credentials. Each branch names the actual remedy - a daemon failure must never
// route the user to a login flow that cannot succeed, which is why daemonReachable is a separate
// service property from needsCredentials.
//
// Unlike NordVPN this card is NOT always a blocker. Country browse is verified to work with no
// credentials at all (docs/airvpn-recon-findings.md §2), so for the credentials case this
// degrades to a banner and the country list below stays live. Only connecting is gated.
StyledRect {
    id: root

    // Hard blockers: nothing on the page can work.
    readonly property bool hardBlocked: !AirVpnService.available
        || AirVpnService.permissionDenied
        || !AirVpnService.daemonReachable

    // Soft blocker: browsing works, connecting does not.
    readonly property bool credentialsMissing: !root.hardBlocked && AirVpnService.needsCredentials

    readonly property string headline: !AirVpnService.available ? "AirVPN Suite is not installed"
        : AirVpnService.permissionDenied ? "Permission denied"
        : !AirVpnService.daemonReachable ? "The AirVPN Bluetit daemon is not reachable"
        : "Log in required"

    readonly property string guidance: !AirVpnService.available
            ? "Install the AirVPN Suite (bluetit + goldcrest) to use this provider."
        : AirVpnService.permissionDenied
            ? "Add your user to the 'airvpn' group, then restart your session — the shell has to "
                + "inherit the new group before it can talk to Bluetit."
        : !AirVpnService.daemonReachable
            ? "Start the bluetit service, then refresh."
        // The honest version of the credentials case: say what still works.
            : "You can browse countries now, but connecting needs your AirVPN account. Add your "
                + "credentials to the Goldcrest run-control file, then refresh.";

    visible: root.hardBlocked || root.credentialsMissing
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
        spacing: 6

        Text {
            Layout.fillWidth: true
            text: root.headline
            font.family: Config.theme.font
            font.pixelSize: Config.theme.fontSize
            font.weight: Font.Medium
            color: Colors.overBackground
            wrapMode: Text.Wrap
        }

        Text {
            Layout.fillWidth: true
            text: root.guidance
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-2)
            color: Colors.overSurfaceVariant
            wrapMode: Text.Wrap
        }

        // ---------------------------------------------------------- credentials detail
        // There is deliberately no password field here. Goldcrest reads credentials from one
        // place only, that file has a documented 0600 contract, and this is a public repo whose
        // Config is plain JSON in the user's home. Showing the exact path and the two directive
        // names is the whole instruction; the widget never handles the secret.
        StyledRect {
            Layout.fillWidth: true
            Layout.topMargin: 2
            visible: root.credentialsMissing
            implicitHeight: rcColumn.implicitHeight + 16
            variant: "common"
            radius: Styling.radius(-2)

            ColumnLayout {
                id: rcColumn

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: AirVpnService.rcPath
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-3)
                    color: Colors.overBackground
                    elide: Text.ElideMiddle
                }

                Text {
                    Layout.fillWidth: true
                    text: "air-user      <your username>\nair-password  <your password>"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-3)
                    color: Colors.overSurfaceVariant
                    wrapMode: Text.Wrap
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    text: "Then: chmod 600 that file. The panel notices on its own."
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-3)
                    color: Colors.overSurfaceVariant
                    wrapMode: Text.Wrap
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            visible: root.credentialsMissing
            spacing: 6

            Button {
                id: clientAreaButton
                flat: true
                implicitHeight: 30
                Layout.fillWidth: true

                background: StyledRect {
                    variant: clientAreaButton.hovered ? "focus" : "common"
                    radius: Styling.radius(-2)
                }

                contentItem: Text {
                    text: "AirVPN client area"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    color: Colors.overBackground
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: AirVpnService.openClientArea()

                StyledToolTip {
                    visible: clientAreaButton.hovered
                    tooltipText: "Open airvpn.org/client in your browser"
                }
            }

            Button {
                id: recheckButton
                flat: true
                implicitHeight: 30
                Layout.fillWidth: true

                background: StyledRect {
                    variant: recheckButton.hovered ? "focus" : "common"
                    radius: Styling.radius(-2)
                }

                contentItem: Text {
                    text: AirVpnService.isUpdating ? "Checking…" : "I've logged in"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    color: Colors.overBackground
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                // refresh() re-reads the run-control file, which is the credentials signal, so
                // this is the whole re-check. The FileView also watches the file, making this a
                // convenience rather than the only path.
                onClicked: AirVpnService.refresh()
            }
        }
    }
}
