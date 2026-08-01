pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

// Collapsed "Advanced" section: technology plus the safe on/off settings.
//
// This closes the gap where NordVpnService.setTechnology() and setBoolSetting() existed but
// were unreachable from any UI, so kill switch, auto-connect, LAN discovery and threat
// protection all still required the terminal.
//
// Subcommand names are verified from lab/fixtures/nordvpn/help-set.txt (NordVPN 5.2.0):
// killswitch, autoconnect, lan-discovery, threatprotectionlite, technology.
// Each row hides itself when this CLI build did not report its label, per plan section 3 -
// a switch that silently does nothing is worse than no switch.
ColumnLayout {
    id: root

    property bool expanded: false

    readonly property var settings: NordVpnService.settings ?? ({})
    readonly property var has: root.settings.has ?? ({})
    readonly property bool busy: NordVpnService.isMutating || VpnService.busy

    spacing: 6

    // One service-backed switch. Same latch discipline as ShellPanel.qml's ToggleRow
    // (:149-222): only the outer value is bound, the inner Switch is re-asserted
    // imperatively, and _updating suppresses the echo. Also re-asserts when the row becomes
    // enabled again, which is how a FAILED mutation gets corrected - the service value never
    // changed, so no value-change signal would ever fire.
    component SettingRow: RowLayout {
        id: settingRow

        property string label: ""
        property string description: ""
        property bool checked: false
        property bool rowEnabled: true
        signal toggled(bool value)

        property bool _updating: false

        function sync(): void {
            if (_updating || rowSwitch.checked === settingRow.checked)
                return;
            _updating = true;
            rowSwitch.checked = settingRow.checked;
            _updating = false;
        }

        onCheckedChanged: settingRow.sync()
        onRowEnabledChanged: if (settingRow.rowEnabled) settingRow.sync()

        Layout.fillWidth: true
        spacing: 8

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: settingRow.label
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                color: Colors.overBackground
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                visible: settingRow.description !== ""
                text: settingRow.description
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-3)
                color: Colors.overSurfaceVariant
                wrapMode: Text.Wrap
            }
        }

        Switch {
            id: rowSwitch
            checked: settingRow.checked
            enabled: settingRow.rowEnabled

            onToggled: settingRow.toggled(checked)

            indicator: Rectangle {
                implicitWidth: 36
                implicitHeight: 18
                x: rowSwitch.leftPadding
                y: parent.height / 2 - height / 2
                radius: height / 2
                color: rowSwitch.checked ? Styling.srItem("overprimary") : Colors.surfaceBright
                border.color: rowSwitch.checked ? Styling.srItem("overprimary") : Colors.outline

                Rectangle {
                    x: rowSwitch.checked ? parent.width - width - 2 : 2
                    y: 2
                    width: parent.height - 4
                    height: width
                    radius: width / 2
                    color: rowSwitch.checked ? Colors.background : Colors.overSurfaceVariant

                    Behavior on x {
                        enabled: Config.animDuration > 0

                        NumberAnimation {
                            duration: Config.animDuration / 2
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }

            background: null
        }
    }

    Button {
        id: discloseButton
        Layout.fillWidth: true
        visible: NordVpnService.available && !NordVpnService.needsLogin
            && !NordVpnService.permissionDenied
        flat: true
        implicitHeight: 32
        leftPadding: 12
        rightPadding: 12

        background: StyledRect {
            variant: discloseButton.hovered ? "focus" : "common"
            radius: Styling.radius(-2)
        }

        contentItem: RowLayout {
            spacing: 6

            Text {
                text: "Advanced"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                color: Colors.overBackground
            }

            Item {
                Layout.fillWidth: true
            }

            Text {
                text: root.expanded ? Icons.caretUp : Icons.caretDown
                font.family: Icons.font
                font.pixelSize: Styling.fontSize(-1)
                color: Colors.overSurfaceVariant
            }
        }

        onClicked: root.expanded = !root.expanded
    }

    StyledRect {
        Layout.fillWidth: true
        visible: root.expanded && discloseButton.visible
        implicitHeight: advancedColumn.implicitHeight + 20
        variant: "internalbg"
        radius: Styling.radius(4)

        ColumnLayout {
            id: advancedColumn

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 10

            Text {
                Layout.fillWidth: true
                visible: root.has.technology === true
                text: "Protocol"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                font.weight: Font.Medium
                color: Colors.overSurfaceVariant
            }

            SegmentedSwitch {
                id: protocolSwitch
                Layout.fillWidth: true
                visible: root.has.technology === true
                // SegmentedSwitch assigns currentIndex imperatively on click, so without a
                // busy gate a rejected setTechnology() leaves the selection visibly wrong.
                enabled: !root.busy
                buttonSize: 30
                options: [
                    { label: "NordLynx", tooltip: "WireGuard-based. Faster; the default." },
                    { label: "OpenVPN", tooltip: "Older, more compatible, usually slower." }
                ]
                currentIndex: NordVpnService.technology === "OpenVPN" ? 1 : 0

                // currentIndex self-assigns on click and breaks its binding (plan 9.4), so
                // the value is always re-read from the service afterwards.
                onIndexChanged: index => {
                    const wanted = index === 1 ? "OpenVPN" : "NordLynx";
                    if (wanted !== NordVpnService.technology)
                        NordVpnService.setTechnology(wanted);
                    protocolResync.restart();
                }

                // SegmentedSwitch assigns currentIndex imperatively on click, destroying the
                // binding above - the same hazard as PanelTitlebar's Switch. Re-assert from
                // the service so a rejected mutation, or a change made in another terminal,
                // cannot leave the selected segment lying.
                function syncFromService(): void {
                    const want = NordVpnService.technology === "OpenVPN" ? 1 : 0;
                    if (protocolSwitch.currentIndex !== want)
                        protocolSwitch.currentIndex = want;
                }

                Timer {
                    id: protocolResync
                    interval: 400
                    repeat: false
                    onTriggered: protocolSwitch.syncFromService()
                }

                Connections {
                    target: NordVpnService

                    function onTechnologyChanged() {
                        protocolSwitch.syncFromService();
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                visible: root.has.technology === true && NordVpnService.connected
                text: "Changing protocol while connected will reconnect the VPN."
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-3)
                color: Colors.warning
                wrapMode: Text.Wrap
            }

            SettingRow {
                visible: root.has.killSwitch === true
                label: "Kill switch"
                // Deliberately plain language: "kill switch" is jargon, and this is the one
                // setting here that can take the whole machine offline.
                description: "Block all internet access if the VPN drops. Safer, but the network stops working until the VPN reconnects."
                checked: root.settings.killSwitch ?? false
                rowEnabled: !root.busy
                onToggled: value => NordVpnService.setBoolSetting("killswitch", value)
            }

            SettingRow {
                visible: root.has.autoConnect === true
                label: "Connect on startup"
                description: "Turn the VPN on automatically when you log in."
                checked: root.settings.autoConnect ?? false
                rowEnabled: !root.busy
                onToggled: value => NordVpnService.setBoolSetting("autoconnect", value)
            }

            SettingRow {
                visible: root.has.lanDiscovery === true
                label: "Allow local network"
                description: "Reach printers, TVs, and other devices at home while the VPN is on."
                checked: root.settings.lanDiscovery ?? false
                rowEnabled: !root.busy
                onToggled: value => NordVpnService.setBoolSetting("lan-discovery", value)
            }

            SettingRow {
                visible: root.has.threatProtection === true
                label: "Block ads and trackers"
                description: "NordVPN's Threat Protection Lite. Blocks malicious sites and ads."
                checked: root.settings.threatProtection ?? false
                rowEnabled: !root.busy
                onToggled: value => NordVpnService.setBoolSetting("threatprotectionlite", value)
            }

            SettingRow {
                visible: root.has.virtualLocation === true
                label: "Virtual locations"
                description: "Offer countries that NordVPN serves from hardware elsewhere. More places to pick from."
                checked: root.settings.virtualLocation ?? false
                rowEnabled: !root.busy
                onToggled: value => NordVpnService.setBoolSetting("virtual-location", value)
            }

            SettingRow {
                visible: root.has.postQuantum === true
                label: "Post-quantum encryption"
                // The CLI's own help states this is NordLynx-only and incompatible with
                // Meshnet, so the constraint is surfaced rather than letting it fail silently.
                // help-set.txt states two constraints, not one: NordLynx only, AND not
                // compatible with Meshnet. Both are surfaced so the switch is never offered
                // in a state where the CLI would refuse it.
                description: NordVpnService.technology === "OpenVPN"
                    ? "Requires the NordLynx protocol. Switch protocol above to enable."
                    : (root.settings.meshnet ?? false)
                        ? "Not available while Meshnet is enabled."
                        : "Extra protection against future quantum attacks. Standard NordLynx servers only."
                checked: root.settings.postQuantum ?? false
                rowEnabled: !root.busy && NordVpnService.technology !== "OpenVPN"
                    && !(root.settings.meshnet ?? false)
                onToggled: value => NordVpnService.setBoolSetting("post-quantum", value)
            }

            // Deliberately NOT exposed, though help-set.txt lists them:
            //   routing, firewall  - turning either off silently breaks the tunnel; a
            //                        one-tap switch is the wrong affordance for that.
            //   dns, fwmark        - take values, not on/off, so they need real input UI.
            //   defaults           - destructive reset; needs a confirmation flow of its own.
            //   analytics, notify, tray, arp-ignore, meshnet
            //                      - not VPN-connection behavior; belong elsewhere or nowhere.
            // Anyone needing these still has the CLI, and that is the honest trade rather
            // than shipping a switch that can strand the machine offline.
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 2
                text: "Custom DNS, firewall, and routing are intentionally left to the CLI — "
                    + "a single tap there can take the machine offline."
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-3)
                color: Colors.overSurfaceVariant
                wrapMode: Text.Wrap
            }
        }
    }
}
