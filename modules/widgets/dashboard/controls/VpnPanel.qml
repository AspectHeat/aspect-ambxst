pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

Item {
    id: root

    property int maxContentWidth: 480
    property string currentSection: ""
    readonly property int contentWidth: Math.min(width, maxContentWidth)

    ColumnLayout {
        visible: root.currentSection === ""
        width: root.contentWidth
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8

        PanelTitlebar {
            Layout.fillWidth: true
            title: "VPN"
        }

        Text {
            Layout.fillWidth: true
            text: "Providers"
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-2)
            font.weight: Font.Medium
            color: Colors.overSurfaceVariant
        }

        StyledRect {
            id: tailscaleCard

            Layout.fillWidth: true
            implicitHeight: 72
            variant: tailscaleMouseArea.containsMouse ? "focus" : "common"
            radius: Styling.radius(4)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12

                StyledRect {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    variant: TailscaleService.connected ? "primary" : "internalbg"
                    radius: Styling.radius(2)

                    Image {
                        anchors.centerIn: parent
                        width: 24
                        height: 24
                        source: Qt.resolvedUrl("../../../../assets/tailscale/tailscale-icon-white.svg")
                        sourceSize: Qt.size(48, 48)
                        smooth: true

                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1
                            colorizationColor: TailscaleService.connected ? Styling.srItem("primary") : Colors.overBackground
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Tailscale"
                            font.family: Config.theme.font
                            font.pixelSize: Config.theme.fontSize
                            font.weight: Font.Medium
                            color: Colors.overBackground
                        }

                        Text {
                            // "Connected" alone was misleading: Tailscale can be up for mesh
                            // access without owning egress. Naming that distinction here is
                            // what makes the handoff rules legible.
                            text: !TailscaleService.connected ? "Off"
                                : (VpnService.routeOwner === "tailscale" ? "Exit node" : "Mesh only")
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: TailscaleService.connected ? Styling.srItem("overprimary") : Colors.overSurfaceVariant
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Mesh VPN, devices, exit nodes, and profiles"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                Text {
                    text: TailscaleService.connected ? Icons.shieldCheck : Icons.caretRight
                    font.family: Icons.font
                    font.pixelSize: Styling.fontSize(0)
                    color: TailscaleService.connected ? Styling.srItem("overprimary") : Colors.overSurfaceVariant
                }
            }

            MouseArea {
                id: tailscaleMouseArea
                anchors.fill: parent
                hoverEnabled: true
                // Both cards are inert during a handoff, so a second network mutation
                // cannot be started while one is in flight.
                enabled: TailscaleService.available && !VpnService.busy
                    && !VpnService.awaitingConfirmation
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.currentSection = "tailscale"
            }
        }

        StyledRect {
            id: nordVpnCard

            Layout.fillWidth: true
            implicitHeight: 72
            variant: nordVpnMouseArea.containsMouse ? "focus" : "common"
            radius: Styling.radius(4)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12

                StyledRect {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    variant: NordVpnService.connected ? "primary" : "internalbg"
                    radius: Styling.radius(2)

                    Text {
                        anchors.centerIn: parent
                        text: Icons.vpn
                        font.family: Icons.font
                        font.pixelSize: Styling.fontSize(3)
                        color: NordVpnService.connected ? Styling.srItem("primary") : Colors.overBackground
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "NordVPN"
                            font.family: Config.theme.font
                            font.pixelSize: Config.theme.fontSize
                            font.weight: Font.Medium
                            color: Colors.overBackground
                        }

                        Text {
                            // Mirrors the section 7.3 matrix so the hub never shows a state
                            // the provider page would describe differently.
                            text: !NordVpnService.available ? "Not installed"
                                : NordVpnService.permissionDenied ? "Permission denied"
                                : !NordVpnService.daemonReachable ? "Daemon unavailable"
                                : NordVpnService.needsLogin ? "Login required"
                                : NordVpnService.connecting ? "Connecting…"
                                : NordVpnService.disconnecting ? "Disconnecting…"
                                : NordVpnService.connected ? "Connected" : "Off"
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: NordVpnService.connected ? Styling.srItem("overprimary")
                                : (!NordVpnService.available || NordVpnService.needsLogin
                                    || NordVpnService.permissionDenied
                                    || !NordVpnService.daemonReachable
                                    ? Colors.warning : Colors.overSurfaceVariant)
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Live servers, locations, and P2P routing"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                Text {
                    text: NordVpnService.connected ? Icons.shieldCheck : Icons.caretRight
                    font.family: Icons.font
                    font.pixelSize: Styling.fontSize(0)
                    color: NordVpnService.connected ? Styling.srItem("overprimary") : Colors.overSurfaceVariant
                }
            }

            MouseArea {
                id: nordVpnMouseArea
                anchors.fill: parent
                hoverEnabled: true
                enabled: !VpnService.busy && !VpnService.awaitingConfirmation
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                // Opens the page even when the CLI is missing, so the setup card can explain
                // what to install rather than the row being a dead end.
                onClicked: root.currentSection = "nordvpn"
            }
        }

        // Route-owner strip. Appears only when something actually owns egress - Tailscale
        // merely running is not egress unless an exit node is set (VpnService.routeOwner).
        StyledRect {
            Layout.fillWidth: true
            visible: VpnService.routeOwner !== "" && VpnService.routeOwner !== "none"
                && VpnService.handoffPhase === "idle"
            implicitHeight: 34
            variant: "internalbg"
            radius: Styling.radius(4)

            Text {
                anchors.centerIn: parent
                width: parent.width - 20
                text: VpnService.labelFor(VpnService.routeOwner) + " currently owns the default route"
                    + (VpnService.bothConnected ? " · both providers connected" : "")
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
            }
        }

    }

    // Floating, and a sibling of BOTH the hub column and the provider Loader, because a
    // handoff can be started from the hub or from either provider page - all three render
    // inside this item. When the confirm controls lived in the hub column (hidden whenever
    // currentSection !== ""), confirming a switch from a provider page was impossible.
    VpnHandoffCard {
        // Above the provider Loader. Declaration order alone is not enough: the Loader is
        // declared later and fills the panel, so with default z it painted OVER this card and
        // a confirmation started from a provider page was still unanswerable.
        z: 1
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 8
        width: root.contentWidth
    }

    // Drop any stale phase or error from a previous visit so it cannot linger on screen.
    // Preserves an in-flight or awaiting-confirmation handoff (see VpnService.clearTransient).
    Component.onCompleted: VpnService.clearTransient()

    Loader {
        id: providerLoader
        anchors.fill: parent
        active: root.currentSection === "tailscale" || root.currentSection === "nordvpn"
        source: root.currentSection === "tailscale" ? "TailscalePanel.qml"
            : (root.currentSection === "nordvpn" ? "NordVpnPanel.qml" : "")
        asynchronous: true

        onLoaded: {
            if (item) {
                item.maxContentWidth = root.maxContentWidth;
                item.showBackButton = true;
                Qt.callLater(() => item.positionAtBeginning());
            }
        }
    }

    Connections {
        target: providerLoader.item
        ignoreUnknownSignals: true

        function onBackRequested() {
            root.currentSection = "";
        }
    }
}
