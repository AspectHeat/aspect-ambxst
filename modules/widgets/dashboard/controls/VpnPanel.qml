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
                            text: TailscaleService.connected ? "Connected" : "Off"
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
                enabled: TailscaleService.available
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
                            text: !NordVpnService.available ? "Not installed"
                                : (NordVpnService.connected ? "Connected" : "Off")
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: NordVpnService.connected ? Styling.srItem("overprimary")
                                : (!NordVpnService.available ? Colors.warning : Colors.overSurfaceVariant)
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Countries, fast servers, and P2P routing"
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
                cursorShape: Qt.PointingHandCursor
                onClicked: root.currentSection = "nordvpn"
            }
        }

        Text {
            Layout.fillWidth: true
            visible: VpnService.isSwitching || VpnService.lastError !== ""
            text: VpnService.isSwitching ? VpnService.phase : VpnService.lastError
            wrapMode: Text.Wrap
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-2)
            color: VpnService.lastError !== "" ? Colors.error : Colors.overSurfaceVariant
        }
    }

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
