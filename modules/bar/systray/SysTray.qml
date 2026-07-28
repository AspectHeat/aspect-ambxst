import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import qs.config
import qs.modules.theme
import qs.modules.components
import qs.modules.services

StyledRect {
    variant: "bg"
    id: root

    // Hide when no tray items
    visible: hasItems

    topLeftRadius: root.vertical ? root.startRadius : root.startRadius
    topRightRadius: root.vertical ? root.startRadius : root.endRadius
    bottomLeftRadius: root.vertical ? root.endRadius : root.startRadius
    bottomRightRadius: root.vertical ? root.endRadius : root.endRadius

    required property var bar
    
    property real radius: 0
    property real startRadius: radius
    property real endRadius: radius

    // Orientación derivada de la barra
    property bool vertical: bar.orientation === "vertical"

    // Hide completely when empty - check both orientations
    readonly property bool tailscaleVisible: TailscaleService.available && Config.system.tailscale.enabled && Config.system.tailscale.showInBar
    readonly property bool hasItems: rowRepeater.count > 0 || columnRepeater.count > 0 || tailscaleVisible

    // Ajustes de tamaño dinámicos según orientación
    height: vertical ? implicitHeight : parent.height
    Layout.preferredWidth: hasItems ? ((vertical ? columnLayout.implicitWidth : rowLayout.implicitWidth) + 16) : 0
    implicitWidth: hasItems ? ((vertical ? columnLayout.implicitWidth : rowLayout.implicitWidth) + 16) : 0
    implicitHeight: hasItems ? ((vertical ? columnLayout.implicitHeight : rowLayout.implicitHeight) + 16) : 0

    RowLayout {
        id: rowLayout
        visible: !root.vertical
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        Repeater {
            id: rowRepeater
            model: SystemTray.items

            SysTrayItem {
                required property SystemTrayItem modelData
                bar: root.bar
                item: modelData
            }
        }

        TailscaleTrayItem {
            visible: root.tailscaleVisible
            bar: root.bar
        }
    }

    ColumnLayout {
        id: columnLayout
        visible: root.vertical
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        Repeater {
            id: columnRepeater
            model: SystemTray.items

            SysTrayItem {
                required property SystemTrayItem modelData
                bar: root.bar
                item: modelData
            }
        }

        TailscaleTrayItem {
            visible: root.tailscaleVisible
            bar: root.bar
        }
    }
}
