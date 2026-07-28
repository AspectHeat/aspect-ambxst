pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
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

                    Text {
                        anchors.centerIn: parent
                        text: TailscaleService.connected ? Icons.shieldCheck : Icons.vpn
                        font.family: Icons.font
                        font.pixelSize: Styling.fontSize(3)
                        color: TailscaleService.connected ? Styling.srItem("primary") : Colors.overBackground
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
                    text: Icons.caretRight
                    font.family: Icons.font
                    font.pixelSize: Styling.fontSize(0)
                    color: Colors.overSurfaceVariant
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

        Text {
            Layout.fillWidth: true
            visible: !TailscaleService.available
            text: "Tailscale is not installed on this system."
            wrapMode: Text.Wrap
            font.family: Config.theme.font
            font.pixelSize: Styling.fontSize(-2)
            color: Colors.overSurfaceVariant
        }
    }

    Loader {
        id: providerLoader
        anchors.fill: parent
        active: root.currentSection === "tailscale"
        source: active ? "TailscalePanel.qml" : ""
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
