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

    required property TailscalePeer peer

    property bool expanded: false
    property bool compactMode: false
    property bool ipv4Revealed: false
    readonly property bool activeExitNode: (peer?.isExitNode ?? false) || (peer?.nodeId ?? "") === TailscaleService.exitNodeId
    readonly property string primaryCopyValue: {
        const format = Config.system.tailscale.copyFormat;
        if (format === "ipv6")
            return peer?.ipv6 ?? "";
        if (format === "dnsname")
            return TailscaleService.shortDnsName(peer?.dnsName ?? "");
        return peer?.ipv4 ?? "";
    }
    readonly property var addressRows: [
        {
            label: "IPv4",
            value: peer?.ipv4 ?? ""
        },
        {
            label: "IPv6",
            value: peer?.ipv6 ?? ""
        },
        {
            label: "MagicDNS",
            value: TailscaleService.shortDnsName(peer?.dnsName ?? "")
        }
    ].filter(row => row.value !== "")

    implicitHeight: contentColumn.implicitHeight + 16

    onPeerChanged: ipv4Revealed = false

    Behavior on implicitHeight {
        enabled: Config.animDuration > 0
        NumberAnimation {
            duration: Config.animDuration
            easing.type: Easing.OutCubic
        }
    }

    component CopyButton: Button {
        id: copyButton

        required property string value
        property string tooltipText: "Copy"
        property bool copied: false

        flat: true
        implicitWidth: 28
        implicitHeight: 28
        enabled: value !== ""

        background: StyledRect {
            variant: copyButton.hovered ? "focus" : "common"
            radius: Styling.radius(-4)
        }

        contentItem: Text {
            text: copyButton.copied ? Icons.accept : Icons.copy
            font.family: Icons.font
            font.pixelSize: Styling.fontSize(-1)
            color: copyButton.copied ? Styling.srItem("overprimary") : (copyButton.enabled ? Colors.overBackground : Colors.outline)
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter

            Behavior on color {
                enabled: Config.animDuration > 0
                ColorAnimation {
                    duration: Config.animDuration / 2
                }
            }
        }

        onClicked: {
            TailscaleService.copyText(value);
            copied = true;
            copiedTimer.restart();
        }

        Timer {
            id: copiedTimer
            interval: 1200
            repeat: false
            onTriggered: copyButton.copied = false
        }

        StyledToolTip {
            visible: copyButton.hovered
            tooltipText: copyButton.tooltipText
        }
    }

    function relativeLastSeen(): string {
        const value = peer?.lastSeen ?? "";
        if (!value)
            return "Offline";

        const elapsed = Math.max(0, Date.now() - Date.parse(value));
        const minutes = Math.floor(elapsed / 60000);
        if (minutes < 1)
            return "Last seen just now";
        if (minutes < 60)
            return "Last seen " + minutes + " min ago";

        const hours = Math.floor(minutes / 60);
        if (hours < 24)
            return "Last seen " + hours + " h ago";

        const days = Math.floor(hours / 24);
        return "Last seen " + days + " d ago";
    }

    StyledRect {
        anchors.fill: parent
        variant: mouseArea.containsMouse ? "focus" : "common"
        radius: Styling.radius(4)
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: {
            if (!root.compactMode)
                root.expanded = !root.expanded;
        }
    }

    ColumnLayout {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.topMargin: 8
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            spacing: 12

            Item {
                width: 24
                height: 24

                Text {
                    anchors.centerIn: parent
                    text: TailscaleService.peerIcon(root.peer)
                    font.family: Icons.font
                    font.pixelSize: 20
                    color: root.peer?.online ? Styling.srItem("overprimary") : Colors.overBackground
                }

                Text {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: -2
                    visible: root.activeExitNode
                    text: Icons.globe
                    font.family: Icons.font
                    font.pixelSize: 10
                    color: Styling.srItem("overprimary")
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: root.peer?.displayName ?? "Unknown device"
                    font.family: Config.theme.font
                    font.pixelSize: Config.theme.fontSize
                    font.weight: Font.Medium
                    color: Colors.overBackground
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: (root.peer?.online ?? false) || root.expanded
                    spacing: 5

                    Text {
                        text: {
                            if (root.activeExitNode)
                                return "Exit node — in use";
                            if (root.peer?.online)
                                return "Online";
                            return root.relativeLastSeen();
                        }
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                        elide: Text.ElideRight
                    }

                    Text {
                        visible: (root.peer?.ipv4 ?? "") !== ""
                        text: "•"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                    }

                    Item {
                        id: concealedIp

                        visible: (root.peer?.ipv4 ?? "") !== ""
                        Layout.preferredWidth: Math.min(ipText.implicitWidth, 88)
                        Layout.preferredHeight: ipText.implicitHeight

                        Text {
                            id: ipText
                            text: root.peer?.ipv4 ?? ""
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: Colors.overSurfaceVariant

                            layer.enabled: !root.ipv4Revealed
                            layer.effect: MultiEffect {
                                blurEnabled: true
                                blur: 1
                                blurMax: 24
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                root.ipv4Revealed = !root.ipv4Revealed;
                                mouse.accepted = true;
                            }
                        }

                        StyledToolTip {
                            show: ipRevealHover.hovered
                            tooltipText: root.ipv4Revealed ? "Hide IPv4 address" : "Reveal IPv4 address"
                        }

                        HoverHandler {
                            id: ipRevealHover
                        }
                    }
                }
            }

            StyledRect {
                visible: root.peer?.exitNodeOption ?? false
                variant: "common"
                implicitWidth: 32
                implicitHeight: 18
                radius: Styling.radius(-4)

                Text {
                    anchors.centerIn: parent
                    text: "EXIT"
                    font.family: Config.theme.font
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    color: Colors.overSurfaceVariant
                }
            }

            CopyButton {
                value: root.primaryCopyValue
                tooltipText: "Copy preferred address"
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.expanded
            spacing: 8
            opacity: root.expanded ? 1 : 0

            Behavior on opacity {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration / 2
                }
            }

            Repeater {
                model: root.addressRows

                delegate: RowLayout {
                    id: addressRow

                    required property var modelData

                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        Layout.preferredWidth: 64
                        text: addressRow.modelData.label
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overSurfaceVariant
                    }

                    Text {
                        Layout.fillWidth: true
                        text: addressRow.modelData.value
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        color: Colors.overBackground
                        elide: Text.ElideMiddle
                    }

                    CopyButton {
                        value: addressRow.modelData.value
                        tooltipText: "Copy " + addressRow.modelData.label
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: (root.peer?.exitNodeOption ?? false) || root.activeExitNode
                spacing: 8

                Item {
                    Layout.fillWidth: true
                }

                Button {
                    id: exitNodeButton
                    flat: true
                    implicitWidth: 112
                    implicitHeight: 32
                    enabled: !TailscaleService.operatorMissing && !TailscaleService.isUpdating

                    background: StyledRect {
                        variant: root.activeExitNode ? "internalbg" : "primary"
                        radius: Styling.radius(4)
                    }

                    contentItem: Text {
                        text: root.activeExitNode ? "Stop using" : "Use exit node"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        color: root.activeExitNode ? Colors.overSurfaceVariant : Styling.srItem("primary")
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: {
                        if (root.activeExitNode)
                            TailscaleService.clearExitNode();
                        else
                            TailscaleService.setExitNode(root.peer.nodeId);
                    }
                }
            }
        }
    }
}
