pragma Singleton

import QtQuick
import Quickshell
import qs.config

Singleton {
    id: root

    property bool isSwitching: false
    property string phase: ""
    property string targetProvider: ""
    property string pendingCountry: ""
    property bool pendingP2p: false
    property int attempts: 0
    property string lastError: ""

    readonly property string activeProvider: NordVpnService.connected ? "nordvpn" : (TailscaleService.connected ? "tailscale" : "")

    function switchToNord(country = "", p2p = false): void {
        if (isSwitching || NordVpnService.connected)
            return;
        pendingCountry = country;
        pendingP2p = p2p;
        targetProvider = "nordvpn";
        lastError = "";
        attempts = 0;
        isSwitching = true;
        if (TailscaleService.connected) {
            phase = "Disconnecting Tailscale…";
            TailscaleService.down();
            handoffTimer.restart();
        } else {
            connectTarget();
        }
    }

    function switchToTailscale(): void {
        if (isSwitching || TailscaleService.connected)
            return;
        targetProvider = "tailscale";
        lastError = "";
        attempts = 0;
        isSwitching = true;
        if (NordVpnService.connected) {
            phase = "Disconnecting NordVPN…";
            NordVpnService.disconnect();
            handoffTimer.restart();
        } else {
            connectTarget();
        }
    }

    function connectTarget(): void {
        attempts = 0;
        if (targetProvider === "nordvpn") {
            phase = "Connecting NordVPN…";
            NordVpnService.connectTo(pendingCountry, pendingP2p);
        } else {
            phase = "Connecting Tailscale…";
            TailscaleService.up();
        }
        handoffTimer.restart();
    }

    function cancelWithError(message): void {
        handoffTimer.stop();
        lastError = message;
        phase = "";
        targetProvider = "";
        isSwitching = false;
    }

    Timer {
        id: handoffTimer
        interval: 500
        repeat: false

        onTriggered: {
            root.attempts++;
            if (root.attempts > 50) {
                root.cancelWithError("VPN switch timed out");
                return;
            }

            if (root.phase.startsWith("Disconnecting")) {
                const disconnected = root.targetProvider === "nordvpn"
                    ? !TailscaleService.connected && !TailscaleService.isUpdating
                    : !NordVpnService.connected && !NordVpnService.isUpdating;
                if (disconnected) {
                    root.connectTarget();
                    return;
                }
            } else {
                const connected = root.targetProvider === "nordvpn"
                    ? NordVpnService.connected
                    : TailscaleService.connected;
                const failed = root.targetProvider === "nordvpn"
                    ? NordVpnService.lastError !== ""
                    : TailscaleService.lastError !== "";
                if (connected) {
                    root.phase = "";
                    root.targetProvider = "";
                    root.isSwitching = false;
                    return;
                }
                if (failed) {
                    root.cancelWithError(root.targetProvider === "nordvpn"
                        ? NordVpnService.lastError : TailscaleService.lastError);
                    return;
                }
            }
            restart();
        }
    }
}
