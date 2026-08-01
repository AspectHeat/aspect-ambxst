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
    property bool tailscalePositioned: false
    property bool nordVpnPositioned: false
    readonly property int contentWidth: Math.min(width, maxContentWidth)

    function positionTailscaleOnFirstVisit(): void {
        if (root.tailscalePositioned || !tailscaleLoader.item)
            return;
        root.tailscalePositioned = true;
        // The retained panel may have compiled while its Loader was hidden and had no usable
        // viewport geometry. Wait until this visit has made it visible before positioning.
        Qt.callLater(() => tailscaleLoader.item.positionAtBeginning());
    }

    function positionNordVpnOnFirstVisit(): void {
        if (root.nordVpnPositioned || !nordVpnLoader.item)
            return;
        root.nordVpnPositioned = true;
        Qt.callLater(() => nordVpnLoader.item.positionAtBeginning());
    }

    onCurrentSectionChanged: {
        if (root.currentSection === "tailscale")
            root.positionTailscaleOnFirstVisit();
        else if (root.currentSection === "nordvpn")
            root.positionNordVpnOnFirstVisit();
    }

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
            Layout.preferredHeight: 56
            variant: tailscaleMouseArea.containsMouse ? "focus" : "pane"
            radius: Styling.radius(0)

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                StyledRect {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    variant: TailscaleService.connected ? "primary" : "internalbg"
                    radius: Styling.radius(2)

                    Image {
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        source: Qt.resolvedUrl("../../../../assets/tailscale/tailscale-icon-white.svg")
                        sourceSize: Qt.size(40, 40)
                        smooth: true

                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1
                            colorizationColor: TailscaleService.connected
                                ? Styling.srItem("primary") : Colors.overBackground
                        }
                    }
                }

                Text {
                    text: "Tailscale"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(0)
                    font.bold: true
                    color: Colors.overBackground
                }

                Text {
                    // "Connected" alone is misleading: mesh access is not egress.
                    text: !TailscaleService.connected ? "Off"
                        : (VpnService.routeOwner === "tailscale" ? "Exit node" : "Mesh only")
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    color: TailscaleService.connected ? Styling.srItem("overprimary") : Colors.overSurfaceVariant
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    text: Icons.caretRight
                    font.family: Icons.font
                    font.pixelSize: 20
                    color: Colors.overSurfaceVariant
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
            Layout.preferredHeight: 56
            variant: nordVpnMouseArea.containsMouse ? "focus" : "pane"
            radius: Styling.radius(0)

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                StyledRect {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    variant: NordVpnService.connected ? "primary" : "internalbg"
                    radius: Styling.radius(2)

                    Image {
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        source: Qt.resolvedUrl("../../../../assets/nordvpn/nordvpn.svg")
                        sourceSize: Qt.size(40, 40)
                        smooth: true
                        mipmap: true

                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1
                            colorizationColor: NordVpnService.connected
                                ? Styling.srItem("primary") : Colors.overBackground
                        }
                    }
                }

                Text {
                    text: "NordVPN"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(0)
                    font.bold: true
                    color: Colors.overBackground
                }

                Text {
                    // Mirrors the provider page's state vocabulary.
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

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    text: Icons.caretRight
                    font.family: Icons.font
                    font.pixelSize: 20
                    color: Colors.overSurfaceVariant
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

    // Floating, and a sibling of BOTH the hub column and the provider Loaders, because a
    // handoff can be started from the hub or from either provider page - all three render
    // inside this item. When the confirm controls lived in the hub column (hidden whenever
    // currentSection !== ""), confirming a switch from a provider page was impossible.
    VpnHandoffCard {
        // Above the provider Loaders. Declaration order alone is not enough: they fill the
        // panel, so with default z they painted OVER this card and
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

    // Compile both provider pages in the background as soon as the hub mounts, then retain
    // them. The previous single Loader started only after a provider click and destroyed its
    // item on every switch, so the user watched Tailscale construct itself in stages and lost
    // local scroll/expanded state. Visibility changes are now navigation-only.
    Loader {
        id: tailscaleLoader
        anchors.fill: parent
        active: true
        visible: root.currentSection === "tailscale"
        source: "TailscalePanel.qml"
        asynchronous: true

        onLoaded: {
            if (item) {
                item.maxContentWidth = root.maxContentWidth;
                item.showBackButton = true;
                if (root.currentSection === "tailscale")
                    root.positionTailscaleOnFirstVisit();
            }
        }
    }

    Loader {
        id: nordVpnLoader
        anchors.fill: parent
        active: true
        visible: root.currentSection === "nordvpn"
        source: "NordVpnPanel.qml"
        asynchronous: true

        onLoaded: {
            if (item) {
                item.maxContentWidth = root.maxContentWidth;
                item.showBackButton = true;
                if (root.currentSection === "nordvpn")
                    root.positionNordVpnOnFirstVisit();
            }
        }
    }

    Connections {
        target: tailscaleLoader.item
        ignoreUnknownSignals: true

        function onBackRequested() {
            root.currentSection = "";
        }
    }

    Connections {
        target: nordVpnLoader.item
        ignoreUnknownSignals: true

        function onBackRequested() {
            root.currentSection = "";
        }
    }
}
