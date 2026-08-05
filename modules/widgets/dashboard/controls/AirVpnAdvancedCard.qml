pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

// Collapsed "Advanced" section: VPN type, OpenVPN TLS mode, device key, Network Lock,
// LAN access, IPv6, and DNS behavior.
//
// Everything here is a CONNECT-TIME PREFERENCE, not a live mutation, which is the significant
// difference from NordVpnAdvancedCard. Goldcrest takes these as flags on --air-connect rather
// than as standalone `set` subcommands, so writing Config and applying it on the next connect is
// both the simpler design and the safer one. Nothing in this card touches the network when
// clicked; the observed state still comes from --bluetit-status.
ColumnLayout {
    id: root

    property bool expanded: false

    // Only a genuinely unusable provider hides this. needsCredentials does NOT: choosing a VPN
    // type or starring a country before logging in is perfectly reasonable, and these controls
    // write Config rather than the network.
    readonly property bool usable: AirVpnService.available
        && !AirVpnService.permissionDenied
        && AirVpnService.daemonReachable

    spacing: 6

    component PreferenceRow: RowLayout {
        id: preferenceRow

        property string label: ""
        property string description: ""
        property bool checked: false
        signal toggled(bool value)

        property bool _updating: false

        function sync(): void {
            if (_updating || preferenceSwitch.checked === preferenceRow.checked)
                return;
            _updating = true;
            preferenceSwitch.checked = preferenceRow.checked;
            _updating = false;
        }

        onCheckedChanged: preferenceRow.sync()

        Layout.fillWidth: true
        spacing: 8

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            Text {
                Layout.fillWidth: true
                text: preferenceRow.label
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-1)
                color: Colors.overBackground
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                text: preferenceRow.description
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-3)
                color: Colors.overSurfaceVariant
                wrapMode: Text.Wrap
            }
        }

        Switch {
            id: preferenceSwitch
            checked: preferenceRow.checked
            onToggled: if (!preferenceRow._updating) preferenceRow.toggled(checked)

            indicator: Rectangle {
                implicitWidth: 36
                implicitHeight: 18
                x: preferenceSwitch.leftPadding
                y: parent.height / 2 - height / 2
                radius: height / 2
                color: preferenceSwitch.checked
                    ? Styling.srItem("overprimary") : Colors.surfaceBright
                border.color: preferenceSwitch.checked
                    ? Styling.srItem("overprimary") : Colors.outline

                Rectangle {
                    x: preferenceSwitch.checked ? parent.width - width - 2 : 2
                    y: 2
                    width: parent.height - 4
                    height: width
                    radius: width / 2
                    color: preferenceSwitch.checked
                        ? Colors.background : Colors.overSurfaceVariant
                }
            }

            background: null
        }
    }

    Button {
        id: discloseButton
        Layout.fillWidth: true
        visible: root.usable
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
                text: root.expanded ? Icons.caretDown : Icons.caretRight
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

            // ---------------------------------------------------------- vpn type
            Text {
                Layout.fillWidth: true
                text: "VPN type"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                font.weight: Font.Medium
                color: Colors.overSurfaceVariant
            }

            SegmentedSwitch {
                id: typeSwitch
                Layout.fillWidth: true
                buttonSize: 30
                options: [
                    { label: "WireGuard", tooltip: "Faster and the AirVPN Suite default." },
                    { label: "OpenVPN", tooltip: "Older, more compatible, usually slower." }
                ]
                currentIndex: AirVpnService.wireGuardPreferred ? 0 : 1

                // currentIndex self-assigns on click and breaks its binding (plan §9.4), so the
                // value is always re-derived from the service afterwards rather than trusted.
                onIndexChanged: index => {
                    AirVpnService.setPreferredVpnType(index === 1 ? "openvpn" : "wireguard");
                }

                function syncFromService(): void {
                    const want = AirVpnService.wireGuardPreferred ? 0 : 1;
                    if (typeSwitch.currentIndex !== want)
                        typeSwitch.currentIndex = want;
                }

                Connections {
                    target: AirVpnService

                    function onWireGuardPreferredChanged() {
                        typeSwitch.syncFromService();
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                text: AirVpnService.connected
                    ? "Applies on the next connect. Reconnect to change the running tunnel."
                    : "Applies to the next connection."
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-3)
                color: Colors.overSurfaceVariant
                wrapMode: Text.Wrap
            }

            Text {
                Layout.fillWidth: true
                visible: !AirVpnService.wireGuardPreferred
                text: "OpenVPN TLS mode"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                font.weight: Font.Medium
                color: Colors.overSurfaceVariant
            }

            SegmentedSwitch {
                id: tlsSwitch
                Layout.fillWidth: true
                visible: !AirVpnService.wireGuardPreferred
                buttonSize: 30
                options: [
                    { label: "Automatic", tooltip: "Let AirVPN choose the compatible TLS mode." },
                    { label: "TLS Crypt", tooltip: "Encrypt and authenticate the OpenVPN control channel." },
                    { label: "TLS Auth", tooltip: "Authenticate the OpenVPN control channel." }
                ]
                currentIndex: Config.system.airvpn.preferredTlsMode === "crypt" ? 1
                    : Config.system.airvpn.preferredTlsMode === "auth" ? 2 : 0

                onIndexChanged: index => AirVpnService.setPreferredTlsMode(
                    index === 1 ? "crypt" : index === 2 ? "auth" : "auto")
            }

            // ---------------------------------------------------------- device key
            // Hidden entirely unless the credentialed key list actually came back, per the §3
            // degradation rule - a picker with nothing in it is worse than no picker.
            Text {
                Layout.fillWidth: true
                visible: AirVpnService.keysLoaded && AirVpnService.keys.length > 1
                text: "Device key"
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-2)
                font.weight: Font.Medium
                color: Colors.overSurfaceVariant
            }

            Flow {
                Layout.fillWidth: true
                visible: AirVpnService.keysLoaded && AirVpnService.keys.length > 1
                spacing: 6

                Repeater {
                    model: AirVpnService.keys

                    delegate: Button {
                        id: keyButton

                        required property var modelData

                        readonly property bool selected:
                            Config.system.airvpn.preferredKey === String(keyButton.modelData)

                        flat: true
                        implicitHeight: 28
                        implicitWidth: Math.max(64, keyLabel.implicitWidth + 20)

                        background: StyledRect {
                            variant: keyButton.selected ? "primary"
                                : (keyButton.hovered ? "focus" : "common")
                            radius: Styling.radius(-4)
                        }

                        contentItem: Text {
                            id: keyLabel
                            text: String(keyButton.modelData)
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-2)
                            color: keyButton.selected
                                ? Styling.srItem("primary") : Colors.overBackground
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        // Re-clicking the selected key clears it, which is how the user gets back
                        // to "whatever the account default is" without a separate reset control.
                        onClicked: AirVpnService.setPreferredKey(
                            keyButton.selected ? "" : String(keyButton.modelData))
                    }
                }
            }

            // ---------------------------------------------------------- network lock
            Separator {
                Layout.fillWidth: true
            }

            PreferenceRow {
                label: "Allow local network"
                description: "Reach printers, TVs, and other devices at home while Network Lock is on."
                checked: Config.system.airvpn.allowPrivateNetwork
                onToggled: value => AirVpnService.setAllowPrivateNetwork(value)
            }

            PreferenceRow {
                label: "IPv6"
                description: "Route IPv6 through AirVPN instead of disabling it for the connection."
                checked: Config.system.airvpn.ipv6
                onToggled: value => AirVpnService.setIpv6Preference(value)
            }

            PreferenceRow {
                label: "Use AirVPN DNS"
                description: "Use AirVPN's private DNS while connected. Turn off to keep system DNS."
                checked: Config.system.airvpn.useAirVpnDns
                onToggled: value => AirVpnService.setUseAirVpnDns(value)
            }

            Separator {
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        Layout.fillWidth: true
                        text: "Network Lock"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-1)
                        color: Colors.overBackground
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Block all traffic outside the tunnel. Applied on the next connect."
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-3)
                        color: Colors.overSurfaceVariant
                        wrapMode: Text.Wrap
                    }
                }

                // A plain Switch is safe here where NordVpnAdvancedCard needed its latch-and-echo
                // SettingRow: this writes Config directly and Config is the single source of
                // truth, so there is no CLI round-trip that could reject the change and leave the
                // control lying about state.
                Switch {
                    id: lockSwitch
                    checked: Config.system.airvpn.networkLock

                    onToggled: AirVpnService.setNetworkLockPreference(lockSwitch.checked)

                    indicator: Rectangle {
                        implicitWidth: 36
                        implicitHeight: 18
                        x: lockSwitch.leftPadding
                        y: parent.height / 2 - height / 2
                        radius: height / 2
                        color: lockSwitch.checked
                            ? Styling.srItem("overprimary") : Colors.surfaceBright
                        border.color: lockSwitch.checked
                            ? Styling.srItem("overprimary") : Colors.outline

                        Rectangle {
                            x: lockSwitch.checked ? parent.width - width - 2 : 2
                            y: 2
                            width: parent.height - 4
                            height: width
                            radius: width / 2
                            color: lockSwitch.checked
                                ? Colors.background : Colors.overSurfaceVariant

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

            // Not a generic caution. On this machine the lock genuinely can sever the only two
            // ways in, and it is off by default precisely because of that.
            Text {
                Layout.fillWidth: true
                visible: Config.system.airvpn.networkLock
                text: "Warning: with the lock on, anything outside the tunnel is dropped — "
                    + "including SSH and Tailscale. If the tunnel fails on a remote machine you "
                    + "can lose access to it until the lock is cleared."
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-3)
                color: Colors.warning
                wrapMode: Text.Wrap
            }

            // Deliberately NOT exposed, though goldcrest --help lists them:
            //   --network-lock on a RUNNING session - a live kill switch that can strand a
            //                        remote machine; only ever applied at connect time here.
            //   --air-white/black-server/country-list, --cipher, --proto, --port, --mtu,
            //   --proxy-*         - take values, not on/off, so they need real input UI.
            //   --recover-network, --remove-wireguard-device
            //                      - crash-recovery break-glass; wrong shape for a one-tap
            //                        switch, and reaching for them implies reading the docs.
            //   airconnectatboot / networklockpersist
            //                      - Bluetit daemon config in /etc/airvpn, not per-user state.
            // Anyone needing these still has goldcrest, and that is the honest trade rather than
            // shipping a switch that can strand the machine offline.
            Text {
                Layout.fillWidth: true
                Layout.topMargin: 2
                text: "Custom server filters, ciphers, ports, proxies, and network recovery "
                    + "remain in goldcrest because they need validated values or recovery flows."
                font.family: Config.theme.font
                font.pixelSize: Styling.fontSize(-3)
                color: Colors.overSurfaceVariant
                wrapMode: Text.Wrap
            }
        }
    }
}
