pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme
import qs.modules.widgets.dashboard.controls

MouseArea {
    id: root

    required property var bar

    property int trayItemSize: 20
    property bool isHovered: false

    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor
    Layout.fillHeight: bar.orientation === "horizontal"
    Layout.fillWidth: bar.orientation === "vertical"
    implicitWidth: trayItemSize
    implicitHeight: trayItemSize

    onClicked: tailscalePopup.toggle()

    Text {
        anchors.centerIn: parent
        text: TailscaleService.connected ? Icons.shieldCheck : Icons.vpn
        font.family: Icons.font
        font.pixelSize: 18
        color: Styling.srItem("overprimary")
    }

    HoverHandler {
        onHoveredChanged: root.isHovered = hovered
    }

    StyledToolTip {
        show: root.isHovered && !tailscalePopup.isOpen
        tooltipText: TailscaleService.connected
            ? (TailscaleService.exitNodeName !== ""
                ? "Tailscale: via " + TailscaleService.exitNodeName
                : "Tailscale: Connected")
            : "Tailscale: Off"
    }

    BarPopup {
        id: tailscalePopup

        anchorItem: root
        bar: root.bar
        visualMargin: 16
        contentWidth: 320
        contentHeight: 340

        TailscalePanel {
            anchors.fill: parent
            maxContentWidth: width
            compactMode: true
        }
    }
}
