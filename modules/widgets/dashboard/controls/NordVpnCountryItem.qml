pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

// One country row in the NordVPN browser. Extracted per plan section 8 rather than inlined,
// following TailscalePeerItem.qml / BluetoothDeviceItem.qml.
Item {
    id: root

    required property NordVpnCountry country
    property bool compactMode: false

    readonly property bool isConnected: NordVpnService.connected
        && (root.country?.matchesStatusName(NordVpnService.country) ?? false)
    // isMutating, NOT isUpdating: gating on reads greys out every row on each poll tick.
    readonly property bool busy: NordVpnService.isMutating || VpnService.busy
    readonly property bool canExpand: (root.country?.cityCount ?? 0) > 0
        || !(root.country?.citiesLoaded ?? false)

    property bool expanded: false

    implicitHeight: contentColumn.implicitHeight + 16

    // The list uses reuseItems, so local UI state must be reset when the delegate is
    // rebound to a different country - TailscalePeerItem.qml:47-50. Without this, an
    // expanded row leaks its open state onto whatever country scrolls into its place.
    onCountryChanged: {
        root.expanded = false;
    }

    Behavior on implicitHeight {
        enabled: Config.animDuration > 0

        NumberAnimation {
            duration: Config.animDuration / 2
            easing.type: Easing.OutCubic
        }
    }

    StyledRect {
        anchors.fill: parent
        variant: rowMouseArea.containsMouse ? "focus" : "common"
        radius: Styling.radius(4)
    }

    // Covers the header row only, so clicks on an expanded city list are not swallowed.
    // Declared before contentColumn so the expand button and city buttons sit above it.
    MouseArea {
        id: rowMouseArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 44
        hoverEnabled: true
        enabled: !root.busy
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        // Through VpnService, not NordVpnService: a direct call bypasses the confirmation and
        // the Tailscale teardown when Tailscale owns the default route.
        onClicked: VpnService.requestProvider("nordvpn", root.country?.token ?? "",
            NordVpnService.p2pPreferred)
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
            spacing: 10

            // Emoji flag when the font has the glyph pair, otherwise a two-letter ISO
            // badge. Decided at runtime from the ISO map, never fetched.
            Item {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 20

                Text {
                    anchors.centerIn: parent
                    visible: root.country?.hasFlag ?? false
                    text: root.country?.flag ?? ""
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(2)
                }

                StyledRect {
                    anchors.fill: parent
                    visible: !(root.country?.hasFlag ?? false)
                    variant: "internalbg"
                    radius: Styling.radius(-6)

                    Text {
                        anchors.centerIn: parent
                        text: root.country?.badge ?? "??"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-3)
                        font.weight: Font.DemiBold
                        color: Colors.overSurfaceVariant
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: root.country?.name ?? ""
                font.family: Config.theme.font
                font.pixelSize: Config.theme.fontSize
                color: Colors.overBackground
                elide: Text.ElideRight
            }

            Text {
                visible: root.isConnected
                text: "Connected"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Styling.srItem("overprimary")
            }

            // City drill-down. Hidden entirely when the CLI gave us no cities, per the
            // section 3 degradation rule.
            Button {
                id: expandButton
                visible: root.canExpand
                flat: true
                implicitWidth: 28
                implicitHeight: 28
                enabled: !root.busy

                background: StyledRect {
                    variant: expandButton.hovered ? "focus" : "common"
                    radius: Styling.radius(-4)
                }

                contentItem: Text {
                    text: root.country?.citiesLoading ? Icons.sync
                        : (root.expanded ? Icons.caretDown : Icons.caretRight)
                    font.family: Icons.font
                    font.pixelSize: Styling.fontSize(-1)
                    color: expandButton.enabled ? Colors.overSurfaceVariant : Colors.outline
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter

                    RotationAnimation on rotation {
                        running: root.country?.citiesLoading ?? false
                        from: 0
                        to: 360
                        duration: 1000
                        loops: Animation.Infinite
                    }
                }

                onClicked: {
                    root.expanded = !root.expanded;
                    if (root.expanded)
                        NordVpnService.loadCities(root.country?.token ?? "");
                }

                StyledToolTip {
                    visible: expandButton.hovered
                    tooltipText: root.expanded ? "Hide cities" : "Show cities"
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            visible: root.expanded
            spacing: 2

            Text {
                Layout.fillWidth: true
                visible: (root.country?.citiesLoaded ?? false) && (root.country?.cityCount ?? 0) === 0
                text: "No cities reported for this country"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                color: Colors.overSurfaceVariant
            }

            Repeater {
                model: root.expanded ? (root.country?.cities ?? []) : []

                delegate: Button {
                    id: cityButton
                    required property var modelData

                    Layout.fillWidth: true
                    flat: true
                    implicitHeight: 30
                    enabled: !root.busy

                    background: StyledRect {
                        variant: cityButton.hovered ? "focus" : "internalbg"
                        radius: Styling.radius(-4)
                    }

                    contentItem: Text {
                        text: Icons.mapPin + "  " + String(cityButton.modelData).replace(/_/g, " ")
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-2)
                        color: Colors.overBackground
                        leftPadding: 8
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    onClicked: VpnService.requestProvider("nordvpn",
                        (root.country?.token ?? "") + " " + String(cityButton.modelData),
                        NordVpnService.p2pPreferred)
                }
            }
        }
    }
}
