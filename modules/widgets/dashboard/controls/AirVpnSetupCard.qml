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

    property bool revealPassword: false

    function submitCredentials(): void {
        if (AirVpnService.saveCredentials(usernameInput.text, passwordInput.text)) {
            passwordInput.text = "";
        }
    }

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
            : "Sign in once with your AirVPN account. Your password is stored only in "
                + "Goldcrest's private credentials file on this device.";

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

        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 2
            visible: root.credentialsMissing
            spacing: 6

            SearchInput {
                id: usernameInput
                Layout.fillWidth: true
                implicitHeight: 40
                placeholderText: "AirVPN username"
                variant: "common"
                enabled: !AirVpnService.credentialSaveInProgress
                onAccepted: passwordInput.focusInput()
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                SearchInput {
                    id: passwordInput
                    Layout.fillWidth: true
                    implicitHeight: 40
                    placeholderText: "Password"
                    passwordMode: !root.revealPassword
                    variant: "common"
                    enabled: !AirVpnService.credentialSaveInProgress
                    onAccepted: root.submitCredentials()
                }

                Button {
                    id: revealButton
                    flat: true
                    implicitWidth: 54
                    implicitHeight: 40

                    background: StyledRect {
                        variant: revealButton.hovered ? "focus" : "common"
                        radius: Styling.radius(-2)
                    }

                    contentItem: Text {
                        text: root.revealPassword ? "Hide" : "Show"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overBackground
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: root.revealPassword = !root.revealPassword
                }
            }

            Text {
                Layout.fillWidth: true
                visible: AirVpnService.credentialSaveError !== ""
                text: AirVpnService.credentialSaveError
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.error
                wrapMode: Text.Wrap
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            visible: root.credentialsMissing
            spacing: 6

            Button {
                id: signInButton
                flat: true
                implicitHeight: 30
                Layout.fillWidth: true
                enabled: !AirVpnService.credentialSaveInProgress

                background: StyledRect {
                    variant: "primary"
                    radius: Styling.radius(-2)
                }

                contentItem: Text {
                    text: AirVpnService.credentialSaveInProgress ? "Signing in…" : "Sign in"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    color: Styling.srItem("primary")
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: root.submitCredentials()
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
                    text: "Create account"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    color: Colors.overBackground
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: AirVpnService.openClientArea()

                StyledToolTip {
                    visible: recheckButton.hovered
                    tooltipText: "Open the AirVPN client area in your browser"
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.credentialsMissing
            text: "Advanced: Goldcrest reads " + AirVpnService.rcPath
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-3)
            color: Colors.overSurfaceVariant
            elide: Text.ElideMiddle
        }
    }
}
