pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
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

    onClicked: {
        const opening = !tailscalePopup.isOpen;
        tailscalePopup.toggle();
        if (opening)
            Qt.callLater(() => tailscalePanel.positionAtBeginning());
    }

    Image {
        anchors.centerIn: parent
        width: 18
        height: 18
        source: Qt.resolvedUrl("../../../assets/tailscale/tailscale-icon-white.svg")
        sourceSize: Qt.size(36, 36)
        smooth: true

        layer.enabled: true
        layer.effect: MultiEffect {
            colorization: 1
            colorizationColor: Styling.srItem("overprimary")
        }
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
        contentWidth: 380
        contentHeight: 340

        TailscalePanel {
            id: tailscalePanel
            anchors.fill: parent
            maxContentWidth: width
            compactMode: true
            onSettingsRequested: tailscalePopup.close()
        }
    }
}
