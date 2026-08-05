import QtQuick
import Quickshell
import qs.modules.services

// Headless smoke test for AirVpnService. Run it, do not import it.
//
//   cd ~/Projects/aspect-ambxst
//   QT_QPA_PLATFORM=offscreen qs -p lab/probe-airvpn.qml
//
// Why this exists: `qs -p shell.qml` under QT_QPA_PLATFORM=offscreen cannot load the real
// shell, because ContextMenu pulls in PanelWindow and offscreen has no layer-shell backend
// ("No PanelWindow backend loaded"). So the offscreen trick in CLAUDE.md gotcha 9 verifies
// type resolution for plain components but not for anything reachable from a window.
//
// A ShellRoot that declares no windows sidesteps that entirely, which makes this the way to
// exercise a service's real QML type resolution, bindings, and CLI reads without touching the
// running desktop. It creates no surfaces and competes with nothing.
//
// It exercises live goldcrest reads, so it is also the fastest way to see what the service
// actually derives on a machine whose login state you are unsure of. Safe by construction:
// every read it can trigger is uncredentialed, and the service refuses credentialed
// subcommands unless the run-control file already has credentials.
ShellRoot {
    id: root

    property int ticks: 0

    function dump(label: string): void {
        console.log("---- " + label + " ----");
        console.log("  available            = " + AirVpnService.available);
        console.log("  enabled              = " + AirVpnService.enabled);
        console.log("  state                = " + AirVpnService.state);
        console.log("  daemonReachable      = " + AirVpnService.daemonReachable);
        console.log("  permissionDenied     = " + AirVpnService.permissionDenied);
        console.log("  credentialsConfigured= " + AirVpnService.credentialsConfigured);
        console.log("  needsCredentials     = " + AirVpnService.needsCredentials);
        console.log("  accountUser          = " + JSON.stringify(AirVpnService.accountUser));
        console.log("  hasDeviceKey         = " + AirVpnService.hasDeviceKey);
        console.log("  connected            = " + AirVpnService.connected);
        console.log("  networkLock          = " + AirVpnService.networkLock
            + " (known=" + AirVpnService.networkLockKnown + ")");
        console.log("  technology           = " + JSON.stringify(AirVpnService.technology));
        console.log("  country / server     = " + JSON.stringify(AirVpnService.country)
            + " / " + JSON.stringify(AirVpnService.server));
        console.log("  isReading/isMutating = " + AirVpnService.isReading
            + " / " + AirVpnService.isMutating);
        console.log("  lastError            = " + JSON.stringify(AirVpnService.lastError));
        console.log("  countryCount         = " + AirVpnService.countryCount
            + " (loaded=" + AirVpnService.countriesLoaded
            + " loading=" + AirVpnService.countriesLoading + ")");
        console.log("  wireGuardPreferred   = " + AirVpnService.wireGuardPreferred);
        console.log("  rcPath               = " + AirVpnService.rcPath);
    }

    Component.onCompleted: {
        console.log("probe-airvpn: instantiating AirVpnService");
        root.dump("t=0 (before any read completes)");
        // The panel calls this on mount; do the same so the country parser runs against live
        // output rather than only against the committed fixture.
        AirVpnService.ensureCountries();
    }

    Timer {
        interval: 2000
        repeat: true
        running: true

        onTriggered: {
            root.ticks++;
            root.dump("t=" + (root.ticks * 2) + "s");

            if (root.ticks < 6)
                return;

            const countries = AirVpnService.sortedCountries;
            console.log("---- country model ----");
            console.log("  rows = " + countries.length);
            for (let i = 0; i < Math.min(4, countries.length); i++) {
                const entry = countries[i];
                console.log("  " + entry.code + " " + JSON.stringify(entry.name)
                    + " flag=" + entry.flag + " hasFlag=" + entry.hasFlag
                    + " badge=" + entry.badge
                    + " servers=" + entry.servers + " users=" + entry.users
                    + " load=" + entry.load + " hasLoad=" + entry.hasLoad
                    + " searchKey=" + JSON.stringify(entry.searchKey));
            }
            const swiss = AirVpnService.countryForToken("CH");
            console.log("  countryForToken('CH') = "
                + (swiss ? swiss.name + " / matchesStatusName('Switzerland')="
                    + swiss.matchesStatusName("Switzerland") : "null"));
            console.log("probe-airvpn: done");
            Qt.quit();
        }
    }
}
