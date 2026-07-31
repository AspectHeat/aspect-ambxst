pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

// Shown when NordVPN cannot be used yet: missing CLI, unreachable daemon, permission
// problem, or logged out. Each branch names the actual remedy - a daemon failure must never
// route the user to a login flow that cannot succeed, which is why daemonReachable is a
// separate service property from needsLogin.
StyledRect {
    id: root

    readonly property bool blocked: !NordVpnService.available
        || NordVpnService.needsLogin
        || NordVpnService.permissionDenied
        || !NordVpnService.daemonReachable

    readonly property string headline: !NordVpnService.available ? "NordVPN is not installed"
        : NordVpnService.permissionDenied ? "Permission denied"
        : !NordVpnService.daemonReachable ? "NordVPN daemon is not reachable"
        : NordVpnService.loginPending ? "Waiting for you to finish logging in"
        : "Log in required"

    readonly property string guidance: !NordVpnService.available
            ? "Install the NordVPN CLI to use this provider."
        : NordVpnService.permissionDenied
            ? "Add your user to the 'nordvpn' group, then log out and back in."
        : !NordVpnService.daemonReachable
            ? "Start the nordvpnd service, then refresh."
        : NordVpnService.loginPending
            ? "A browser window should have opened. Finish signing in there and this will update on its own."
            : "Log in to NordVPN to browse locations and connect."

    // Only offered when logging in is actually the blocker.
    readonly property bool canLogIn: NordVpnService.needsLogin
        && NordVpnService.daemonReachable
        && !NordVpnService.permissionDenied

    visible: root.blocked
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

        Button {
            id: loginButton
            visible: root.canLogIn
            Layout.topMargin: 2
            flat: true
            implicitHeight: 30
            implicitWidth: 110
            // Stays clickable so an abandoned or failed browser flow can be retried, rather
            // than trapping the user behind a disabled button for three minutes.
            opacity: NordVpnService.loginPending ? 0.7 : 1

            background: StyledRect {
                variant: loginButton.hovered ? "focus" : "common"
                radius: Styling.radius(-2)
            }

            contentItem: Text {
                text: NordVpnService.loginPending ? "Waiting…" : "Log in"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                color: Colors.overBackground
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            // Opens a browser flow out of process; the panel then waits for the next poll
            // to observe the new login state rather than assuming success.
            onClicked: NordVpnService.login()
        }
    }
}
