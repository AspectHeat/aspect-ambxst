pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.globals
import qs.modules.services
import qs.modules.theme

Item {
    id: root

    property int maxContentWidth: 480
    property bool compactMode: false
    property bool showBackButton: false
    property bool resetScrollAfterRefresh: false
    signal backRequested
    signal settingsRequested

    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property real sideMargin: (width - contentWidth) / 2
    readonly property var allSelfRows: [
        {
            label: "IPv4",
            value: TailscaleService.selfIPv4
        },
        {
            label: "IPv6",
            value: TailscaleService.selfIPv6
        },
        {
            label: "MagicDNS",
            value: TailscaleService.selfDNSName
        }
    ].filter(row => row.value !== "")
    readonly property var selfRows: compactMode ? allSelfRows.filter(row => row.label === "IPv4").slice(0, 1) : allSelfRows
    readonly property string statusText: {
        if (TailscaleService.lastError !== "")
            return TailscaleService.lastError;
        if (TailscaleService.operatorMissing)
            return "Setup required";
        if (TailscaleService.needsLogin)
            return "Log in required";
        if (TailscaleService.backendState === "Starting")
            return "Connecting…";
        if (TailscaleService.exitNodeName !== "")
            return "Exit node: " + TailscaleService.exitNodeName;
        if (TailscaleService.connected)
            return compactMode ? TailscaleService.onlineCount + "/" + TailscaleService.peerCount + " online" : TailscaleService.onlineCount + " of " + TailscaleService.peerCount + " online";
        return "Disconnected";
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

    function confirmProfile(profile): void {
        if (!Visibilities.contextMenu)
            return;
        Visibilities.contextMenu.openCustomMenu([
            {
                text: "Switch to " + profile.name,
                icon: Icons.accept,
                onTriggered: function () {
                    TailscaleService.switchProfile(profile.id);
                }
            },
            {
                text: "Cancel",
                icon: Icons.cancel,
                onTriggered: function () {}
            }
        ], 280, 36, "tailscale-profile");
    }

    function positionAtBeginning(): void {
        peerList.contentY = peerList.headerItem ? peerList.headerItem.y : peerList.originY;
    }

    function openSettings(): void {
        GlobalStates.settingsRequestedSubSection = "tailscale";
        if (!GlobalStates.settingsWindowVisible)
            GlobalShortcuts.toggleSettings();
        root.settingsRequested();
    }

    Component.onCompleted: {
        initialRefreshTimer.start();
        Qt.callLater(() => root.positionAtBeginning());
    }

    Timer {
        id: initialRefreshTimer
        interval: 300
        repeat: false
        onTriggered: {
            root.resetScrollAfterRefresh = true;
            TailscaleService.refresh();
            TailscaleService.refreshProfiles();
        }
    }

    Connections {
        target: TailscaleService

        function onIsUpdatingChanged() {
            if (root.resetScrollAfterRefresh && !TailscaleService.isUpdating) {
                root.resetScrollAfterRefresh = false;
                Qt.callLater(() => root.positionAtBeginning());
            }
        }
    }

    ListView {
        id: peerList
        anchors.fill: parent
        clip: true
        spacing: 4
        cacheBuffer: 1000
        reuseItems: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick

        model: TailscaleService.friendlyPeers

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
        }

        header: Item {
            width: peerList.width
            height: headerColumn.implicitHeight + 8

            ColumnLayout {
                id: headerColumn
                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                PanelTitlebar {
                    id: titlebar
                    Layout.fillWidth: true
                    title: "Tailscale"
                    statusText: root.statusText
                    statusColor: TailscaleService.lastError !== "" ? Colors.error : ((TailscaleService.operatorMissing || TailscaleService.needsLogin) ? Colors.warning : Styling.srItem("overprimary"))
                    showToggle: true
                    toggleChecked: TailscaleService.connected
                    toggleEnabled: !TailscaleService.operatorMissing && !TailscaleService.isUpdating

                    actions: (root.showBackButton ? [{
                        icon: Icons.caretLeft,
                        tooltip: "Back to VPN providers",
                        onClicked: function () {
                            root.backRequested();
                        }
                    }] : []).concat(root.compactMode ? [
                        {
                            icon: Icons.gear,
                            tooltip: "Open Tailscale settings",
                            onClicked: function () {
                                root.openSettings();
                            }
                        },
                        {
                            icon: Icons.popOpen,
                            tooltip: "Open Tailscale admin console",
                            onClicked: function () {
                                TailscaleService.openAdminConsole();
                            }
                        },
                        {
                            icon: Icons.sync,
                            tooltip: "Refresh Tailscale",
                            loading: TailscaleService.isUpdating,
                            onClicked: function () {
                                TailscaleService.refresh();
                                TailscaleService.refreshProfiles();
                            }
                        }
                    ] : [
                        {
                            icon: Icons.globe,
                            tooltip: "Stop using exit node",
                            enabled: TailscaleService.exitNodeId !== "" && !TailscaleService.operatorMissing,
                            onClicked: function () {
                                TailscaleService.clearExitNode();
                            }
                        },
                        {
                            icon: Icons.popOpen,
                            tooltip: "Open Tailscale admin console",
                            onClicked: function () {
                                TailscaleService.openAdminConsole();
                            }
                        },
                        {
                            icon: Icons.sync,
                            tooltip: "Refresh Tailscale",
                            loading: TailscaleService.isUpdating,
                            onClicked: function () {
                                TailscaleService.refresh();
                                TailscaleService.refreshProfiles();
                            }
                        }
                    ])

                    onToggleChanged: TailscaleService.toggle()
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: selfColumn.implicitHeight + 16
                    variant: "internalbg"
                    radius: Styling.radius(4)

                    ColumnLayout {
                        id: selfColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        spacing: 6

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Text {
                                Layout.fillWidth: true
                                text: TailscaleService.selfHostName || "This device"
                                font.family: Config.theme.font
                                font.pixelSize: Config.theme.fontSize
                                font.weight: Font.Medium
                                color: Colors.overBackground
                                elide: Text.ElideRight
                            }

                            Text {
                                visible: TailscaleService.connected
                                text: Icons.shieldCheck
                                font.family: Icons.font
                                font.pixelSize: Styling.fontSize(1)
                                color: Styling.srItem("overprimary")
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            visible: !root.compactMode && TailscaleService.selfDNSName !== ""
                            text: TailscaleService.shortDnsName(TailscaleService.selfDNSName)
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: Colors.overSurfaceVariant
                            elide: Text.ElideMiddle
                        }

                        Repeater {
                            model: root.selfRows

                            delegate: RowLayout {
                                id: selfAddressRow

                                required property var modelData
                                property bool valueRevealed: modelData.label !== "IPv4"

                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    Layout.preferredWidth: 64
                                    text: selfAddressRow.modelData.label
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    color: Colors.overSurfaceVariant
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: selfAddressValue.implicitHeight

                                    Text {
                                        id: selfAddressValue

                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        text: selfAddressRow.modelData.value
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-1)
                                        color: Colors.overBackground
                                        elide: Text.ElideMiddle

                                        layer.enabled: !selfAddressRow.valueRevealed
                                        layer.effect: MultiEffect {
                                            blurEnabled: true
                                            blur: 1
                                            blurMax: 24
                                        }
                                    }

                                    MouseArea {
                                        id: selfAddressMouseArea

                                        width: Math.min(selfAddressValue.implicitWidth, parent.width)
                                        height: parent.height
                                        enabled: selfAddressRow.modelData.label === "IPv4"
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: selfAddressRow.valueRevealed = !selfAddressRow.valueRevealed
                                    }

                                    StyledToolTip {
                                        show: selfAddressMouseArea.containsMouse
                                        tooltipText: selfAddressRow.valueRevealed ? "Hide IPv4 address" : "Reveal IPv4 address"
                                    }
                                }

                                CopyButton {
                                    value: selfAddressRow.modelData.value
                                    tooltipText: "Copy " + selfAddressRow.modelData.label
                                }
                            }
                        }
                    }
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: exitNodeRow.implicitHeight + 16
                    visible: TailscaleService.exitNodeOptions.length > 0
                    variant: "common"
                    radius: Styling.radius(4)

                    RowLayout {
                        id: exitNodeRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                text: "Exit node"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(0)
                                color: Colors.overBackground
                            }

                            Text {
                                Layout.fillWidth: true
                                text: TailscaleService.exitNodeName || "None (direct)"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                color: Colors.overSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }

                        Button {
                            id: exitNodeMenuButton
                            flat: true
                            implicitWidth: 32
                            implicitHeight: 32
                            enabled: !TailscaleService.operatorMissing && !TailscaleService.isUpdating

                            background: StyledRect {
                                variant: exitNodeMenuButton.hovered ? "focus" : "common"
                                radius: Styling.radius(-4)
                            }

                            contentItem: Text {
                                text: Icons.caretDown
                                font.family: Icons.font
                                font.pixelSize: Styling.fontSize(-1)
                                color: exitNodeMenuButton.enabled ? Colors.overBackground : Colors.outline
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            onClicked: exitNodeMenu.popup()
                        }

                        OptionsMenu {
                            id: exitNodeMenu
                            items: [{
                                text: "None (direct)",
                                icon: Icons.globe,
                                onTriggered: function () {
                                    TailscaleService.clearExitNode();
                                }
                            }].concat(TailscaleService.exitNodeOptions.map(peer => ({
                                text: peer.displayName,
                                icon: TailscaleService.peerIcon(peer),
                                onTriggered: function () {
                                    TailscaleService.setExitNode(peer.nodeId);
                                }
                            })))
                        }
                    }
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: lanAccessRow.implicitHeight + 16
                    visible: TailscaleService.exitNodeId !== ""
                    variant: "common"
                    radius: Styling.radius(4)

                    RowLayout {
                        id: lanAccessRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                text: "Allow LAN access"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(0)
                                color: Colors.overBackground
                            }

                            Text {
                                text: "Keep local devices reachable through the exit node"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                color: Colors.overSurfaceVariant
                            }
                        }

                        Button {
                            id: lanAccessToggle
                            checkable: true
                            checked: TailscaleService.allowLanAccess
                            enabled: !TailscaleService.operatorMissing && !TailscaleService.isUpdating
                            implicitWidth: 40
                            implicitHeight: 24

                            background: StyledRect {
                                variant: lanAccessToggle.checked ? "primary" : "common"
                                radius: Styling.radius(-6)
                            }

                            contentItem: Text {
                                text: lanAccessToggle.checked ? Icons.accept : Icons.cancel
                                font.family: Icons.font
                                font.pixelSize: Styling.fontSize(-2)
                                color: lanAccessToggle.checked ? Styling.srItem("primary") : Colors.overSurfaceVariant
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            onToggled: TailscaleService.setAllowLanAccess(checked)
                        }
                    }
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: profileRow.implicitHeight + 16
                    visible: TailscaleService.profiles.length > 1
                    variant: "common"
                    radius: Styling.radius(4)

                    RowLayout {
                        id: profileRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            Text {
                                text: "Tailnet profile"
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(0)
                                color: Colors.overBackground
                            }

                            Text {
                                Layout.fillWidth: true
                                text: {
                                    const active = TailscaleService.profiles.find(profile => profile.active);
                                    return active ? active.name : "Choose profile";
                                }
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                color: Colors.overSurfaceVariant
                                elide: Text.ElideRight
                            }
                        }

                        Button {
                            id: profileMenuButton
                            flat: true
                            implicitWidth: 32
                            implicitHeight: 32
                            enabled: !TailscaleService.operatorMissing && !TailscaleService.isUpdating

                            background: StyledRect {
                                variant: profileMenuButton.hovered ? "focus" : "common"
                                radius: Styling.radius(-4)
                            }

                            contentItem: Text {
                                text: Icons.caretDown
                                font.family: Icons.font
                                font.pixelSize: Styling.fontSize(-1)
                                color: profileMenuButton.enabled ? Colors.overBackground : Colors.outline
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            onClicked: profileMenu.popup()
                        }

                        OptionsMenu {
                            id: profileMenu
                            items: TailscaleService.profiles.map(profile => ({
                                text: (profile.active ? "✓ " : "") + profile.name,
                                icon: Icons.user,
                                onTriggered: function () {
                                    if (!profile.active)
                                        root.confirmProfile(profile);
                                }
                            }))
                        }
                    }
                }

                StyledRect {
                    Layout.fillWidth: true
                    implicitHeight: setupRow.implicitHeight + 16
                    visible: TailscaleService.operatorMissing
                    variant: "common"
                    radius: Styling.radius(4)

                    RowLayout {
                        id: setupRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: "Tailscale controls need one-time setup: sudo tailscale set --operator=$USER"
                            wrapMode: Text.Wrap
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: Colors.warning
                        }

                        CopyButton {
                            value: "sudo tailscale set --operator=$USER"
                            tooltipText: "Copy setup command"
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    text: "Devices"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    font.weight: Font.Medium
                    color: Colors.overSurfaceVariant
                }
            }
        }

        delegate: Item {
            required property var modelData

            width: peerList.width
            height: peerItem.height

            TailscalePeerItem {
                id: peerItem
                width: root.contentWidth
                anchors.horizontalCenter: parent.horizontalCenter
                peer: parent.modelData
                compactMode: root.compactMode
            }
        }

        Text {
            anchors.centerIn: parent
            visible: peerList.count === 0 && !TailscaleService.isUpdating
            text: TailscaleService.connected ? "No devices" : "Not connected"
            font.family: Config.theme.font
            font.pixelSize: Config.theme.fontSize
            color: Colors.overSurfaceVariant
        }
    }
}
