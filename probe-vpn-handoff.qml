import QtQuick
import Quickshell
import qs.modules.services

// Assertion probe for the table-driven VpnService. Run it, do not import it.
//
//   cd ~/Projects/aspect-ambxst
//   QT_QPA_PLATFORM=offscreen qs -p probe-vpn-handoff.qml
//
// Gate 05's coordinator half. The live half - actually handing the default route between two
// commercial tunnels - needs AirVPN credentials on this machine, so it is not attempted here.
//
// TOUCHES NO NETWORK, deliberately and by construction:
//   - Every helper under test is pure.
//   - The phase properties are plain properties, so the direction-scoping cases are set up by
//     assignment rather than by running a handoff.
//   - requestProvider() is called for "airvpn" and for a bogus id ONLY. AirVPN has no
//     credentials, so AirVpnService.connectTo() refuses before spawning anything, and a bogus
//     id must return before touching a provider at all. It is NEVER called for "nordvpn"
//     (logged in on Bostrom, so it would really connect) or for "tailscale" (would run
//     `tailscale up`).
//
// What it is really guarding: every one of these assertions passes trivially with two providers
// and FAILS with the pre-refactor binary helpers once a third exists.
ShellRoot {
    id: root

    property int pass: 0
    property int fail: 0
    property var problems: []

    function check(name: string, condition: bool, detail: string): void {
        if (condition) {
            root.pass++;
            return;
        }
        root.fail++;
        root.problems = root.problems.concat([name + ": " + detail]);
    }

    function checkEqual(name: string, got, want): void {
        root.check(name, got === want,
            "got " + JSON.stringify(got) + " want " + JSON.stringify(want));
    }

    readonly property var allProviders: ["tailscale", "nordvpn", "airvpn"]

    function runTableTests(): void {
        // ---- the table covers every provider, and nothing else
        for (const provider of root.allProviders) {
            root.check("providerFor(" + provider + ") exists",
                VpnService.providerFor(provider) !== null, "missing table entry");
            root.check("labelFor(" + provider + ") non-empty",
                VpnService.labelFor(provider) !== "", "no label");
            root.check("providerFor(" + provider + ").service resolved",
                VpnService.providerFor(provider)?.service !== undefined
                    && VpnService.providerFor(provider)?.service !== null,
                "service singleton did not resolve");
        }

        root.checkEqual("labelFor(tailscale)", VpnService.labelFor("tailscale"), "Tailscale");
        root.checkEqual("labelFor(nordvpn)", VpnService.labelFor("nordvpn"), "NordVPN");
        root.checkEqual("labelFor(airvpn)", VpnService.labelFor("airvpn"), "AirVPN");

        // ---- unknown providers must degrade safely, never guess
        root.checkEqual("providerFor(bogus)", VpnService.providerFor("bogus"), null);
        root.checkEqual("labelFor(bogus)", VpnService.labelFor("bogus"), "");
        root.checkEqual("labelFor('')", VpnService.labelFor(""), "");
        root.checkEqual("providerConnected(bogus)", VpnService.providerConnected("bogus"), false);
        root.checkEqual("providerError(bogus)", VpnService.providerError("bogus"), "");

        // THE important one. providerSettled() gates the disconnect->connect transition, so a
        // true here would let a handoff connect over a tunnel that is still up.
        root.checkEqual("providerSettled(bogus) is FALSE",
            VpnService.providerSettled("bogus"), false);

        // ---- the helpers agree with the services they are wrapping
        root.checkEqual("providerConnected(tailscale) tracks service",
            VpnService.providerConnected("tailscale"), TailscaleService.connected);
        root.checkEqual("providerConnected(nordvpn) tracks service",
            VpnService.providerConnected("nordvpn"), NordVpnService.connected);
        root.checkEqual("providerConnected(airvpn) tracks service",
            VpnService.providerConnected("airvpn"), AirVpnService.connected);

        // settleOn differs per provider on purpose: the commercial CLIs separate reads from
        // mutations, Tailscale only exposes isUpdating.
        root.checkEqual("settleOn(tailscale)",
            VpnService.providerFor("tailscale").settleOn, "isUpdating");
        root.checkEqual("settleOn(nordvpn)",
            VpnService.providerFor("nordvpn").settleOn, "isMutating");
        root.checkEqual("settleOn(airvpn)",
            VpnService.providerFor("airvpn").settleOn, "isMutating");
        root.checkEqual("disconnectMethod(tailscale)",
            VpnService.providerFor("tailscale").disconnectMethod, "down");
        root.checkEqual("disconnectMethod(nordvpn)",
            VpnService.providerFor("nordvpn").disconnectMethod, "disconnect");
        root.checkEqual("disconnectMethod(airvpn)",
            VpnService.providerFor("airvpn").disconnectMethod, "disconnect");

        // Every named disconnect method must actually exist on its service, or beginHandoff()
        // would throw mid-handoff with a tunnel already torn down.
        for (const provider of root.allProviders) {
            const entry = VpnService.providerFor(provider);
            root.check("disconnectMethod(" + provider + ") is callable",
                typeof entry.service[entry.disconnectMethod] === "function",
                "service has no " + entry.disconnectMethod + "()");
        }
    }

    function runRouteOwnerTests(): void {
        // Mesh-only Tailscale is NOT egress. This is the rule that stops a mesh connection from
        // triggering a handoff prompt.
        if (TailscaleService.connected && TailscaleService.exitNodeId === ""
            && !NordVpnService.connected && !AirVpnService.connected) {
            root.checkEqual("routeOwner is none for mesh-only tailscale",
                VpnService.routeOwner, "none");
        }

        // Whatever the live state, routeOwner must be a value the table knows or "none" -
        // connectTarget() and beginHandoff() both index the table with it.
        root.check("routeOwner is a known id or none",
            VpnService.routeOwner === "none"
                || VpnService.providerFor(VpnService.routeOwner) !== null,
            "got " + JSON.stringify(VpnService.routeOwner));

        root.checkEqual("connectedCount matches the three booleans",
            VpnService.connectedCount,
            (TailscaleService.connected ? 1 : 0) + (NordVpnService.connected ? 1 : 0)
                + (AirVpnService.connected ? 1 : 0));
        root.checkEqual("bothConnected means two or more",
            VpnService.bothConnected, VpnService.connectedCount > 1);
    }

    // Direction scoping. Set up by assignment - no handoff is run.
    function runStatusTextTests(): void {
        VpnService.handoffTarget = "airvpn";
        VpnService.recoveryProvider = "nordvpn";
        VpnService.handoffPhase = "confirming";

        root.checkEqual("confirming names the target",
            VpnService.statusTextFor("airvpn"), "Switch to AirVPN?");
        // The v1 cross-talk bug: a surface that is not the target must say NOTHING.
        root.checkEqual("confirming is silent on nordvpn",
            VpnService.statusTextFor("nordvpn"), "");
        root.checkEqual("confirming is silent on tailscale",
            VpnService.statusTextFor("tailscale"), "");

        VpnService.handoffPhase = "connecting";
        root.checkEqual("connecting names the target",
            VpnService.statusTextFor("airvpn"), "Connecting AirVPN…");
        root.checkEqual("connecting is silent on nordvpn",
            VpnService.statusTextFor("nordvpn"), "");

        // ---- the otherProvider() regression, isolated.
        // Target nordvpn while airvpn owns the route. Correct text names AIRVPN, because that is
        // the tunnel being torn down. The old binary flip computed
        // otherProvider("nordvpn") === "tailscale" and would have said "Disconnecting
        // Tailscale…" about a provider nobody touched.
        VpnService.handoffTarget = "nordvpn";
        VpnService.recoveryProvider = "airvpn";
        VpnService.handoffPhase = "disconnecting";
        root.checkEqual("disconnecting names the ROUTE OWNER, not a flip",
            VpnService.statusTextFor("nordvpn"), "Disconnecting AirVPN…");
        root.check("disconnecting does not mention Tailscale",
            !VpnService.statusTextFor("nordvpn").includes("Tailscale"),
            "the pre-refactor otherProvider() flip is still in play");

        // And the mirror case, which the old flip happened to get right.
        VpnService.handoffTarget = "airvpn";
        VpnService.recoveryProvider = "tailscale";
        root.checkEqual("disconnecting tailscale for airvpn",
            VpnService.statusTextFor("airvpn"), "Disconnecting Tailscale…");

        VpnService.handoffPhase = "failed";
        VpnService.lastError = "probe-injected failure";
        root.checkEqual("failed surfaces lastError",
            VpnService.statusTextFor("airvpn"), "probe-injected failure");
        root.checkEqual("failed is silent on other surfaces",
            VpnService.statusTextFor("tailscale"), "");

        VpnService.handoffPhase = "idle";
        VpnService.handoffTarget = "";
        VpnService.recoveryProvider = "";
        VpnService.lastError = "";
        root.checkEqual("idle is silent everywhere",
            VpnService.statusTextFor("airvpn"), "");
    }

    // The no-fallthrough test. connectTarget() used to end in a bare `else` that ran
    // TailscaleService.up(), so ANY unrecognized target connected Tailscale.
    function runNoFallthroughTests(): void {
        const tailscaleBefore = TailscaleService.connected;
        const tailscaleUpdatingBefore = TailscaleService.isUpdating;

        // A bogus id must be rejected before any provider is consulted.
        VpnService.clearTransient();
        VpnService.requestProvider("bogus-provider", "", false);
        root.checkEqual("bogus request leaves phase idle", VpnService.handoffPhase, "idle");
        root.checkEqual("bogus request sets no target", VpnService.handoffTarget, "");
        root.checkEqual("bogus request did not touch Tailscale",
            TailscaleService.isUpdating, tailscaleUpdatingBefore);

        VpnService.requestProvider("", "", false);
        root.checkEqual("empty request leaves phase idle", VpnService.handoffPhase, "idle");

        // A real AirVPN request with no credentials. Safe: AirVpnService.connectTo() refuses on
        // needsCredentials before spawning a process. The coordinator must report that as an
        // AirVPN failure and must NOT have brought Tailscale up instead.
        root.check("precondition: airvpn needs credentials",
            AirVpnService.needsCredentials, "this probe assumes a logged-out AirVPN");

        VpnService.clearTransient();
        VpnService.requestProvider("airvpn", "CH", false);

        root.checkEqual("airvpn request targets airvpn", VpnService.handoffTarget, "airvpn");
        root.checkEqual("airvpn request without credentials fails",
            VpnService.handoffPhase, "failed");
        root.check("failure names AirVPN",
            VpnService.lastError.includes("AirVPN"),
            "got " + JSON.stringify(VpnService.lastError));
        root.check("failure does not name Tailscale",
            !VpnService.lastError.includes("Tailscale"),
            "got " + JSON.stringify(VpnService.lastError));
        root.checkEqual("Tailscale connection state untouched",
            TailscaleService.connected, tailscaleBefore);

        // A failure must be dismissable, or the error banner outlives the attempt. Note that
        // requestProvider persists the country BEFORE attempting the connect, so a refused
        // attempt still updates preferredCountry - that is NordVPN's existing shipped behaviour
        // and AirVPN matches it deliberately rather than inventing a second rule.
        VpnService.dismissFailure();
        root.checkEqual("failure is dismissable", VpnService.handoffPhase, "idle");
        root.checkEqual("dismissal clears the error", VpnService.lastError, "");
        root.checkEqual("dismissal clears the target", VpnService.handoffTarget, "");
    }

    function report(): void {
        console.log("");
        console.log("  " + root.pass + " passed, " + root.fail + " failed");
        console.log("");
        if (root.fail > 0) {
            console.log("  failures:");
            for (const problem of root.problems)
                console.log("    - " + problem);
            console.log("");
        }
    }

    // Force the singletons to CONSTRUCT now, so their availability probes and first reads are
    // in flight before the timer below asserts anything.
    //
    // Without this the probe reported available=false and needsCredentials=false for a Suite
    // that is installed: QML constructs a singleton on first access, nothing referenced these
    // until the assertion ran, so every async read was still outstanding at that instant.
    // Reading a property is what forces construction - the same idiom, and the same reason, as
    // shell.qml's deferred service-init tier.
    Component.onCompleted: {
        let _ = TailscaleService.connected;
        _ = NordVpnService.available;
        _ = AirVpnService.available;
        _ = VpnService.routeOwner;
        console.log("probe-vpn-handoff: singletons constructed, waiting for first reads");
    }

    // Deferred, so the services' first availability probes and reads have landed. The
    // preconditions this asserts (AirVPN logged out) are read from the live services.
    Timer {
        interval: 8000
        repeat: false
        running: true

        onTriggered: {
            console.log("probe-vpn-handoff: live state -> routeOwner="
                + VpnService.routeOwner
                + " tailscale=" + TailscaleService.connected
                + " (exitNode=" + JSON.stringify(TailscaleService.exitNodeId) + ")"
                + " nord=" + NordVpnService.connected
                + " air=" + AirVpnService.connected
                + " airNeedsCreds=" + AirVpnService.needsCredentials);

            root.runTableTests();
            root.runRouteOwnerTests();
            root.runStatusTextTests();
            root.runNoFallthroughTests();
            root.report();
            Qt.quit();
        }
    }
}
