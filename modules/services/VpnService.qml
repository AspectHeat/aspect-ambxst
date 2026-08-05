pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.config

// Coordinates the VPN providers. Knows nothing about any CLI - it only reads their booleans
// and serializes transitions between them.
//
// Three rules this file exists to enforce:
//   1. handoffPhase is an ENUM and is never rendered. UI text comes from statusTextFor(),
//      which returns "" for any surface that is not the current handoff target. v1 rendered
//      a shared phase string everywhere, so the NordVPN page announced "Disconnecting
//      Tailscale...".
//   2. "connected" is not symmetric between providers, so a handoff is keyed on who owns
//      the DEFAULT ROUTE, not on who happens to be running.
//   3. Nothing here is per-provider except providerTable. Every helper was hard-coded binary
//      NordVPN <-> Tailscale before AirVPN, and otherProvider() in particular was a plain
//      boolean flip - with a third provider that silently returned the WRONG provider, so
//      handoff text and settle detection would both have lied. Adding a fourth provider
//      should be one table entry plus a connect case, and nothing else.
Singleton {
    id: root

    // ---------------------------------------------------------------- provider table
    // The single per-provider definition. `service` holds the singleton itself, so the helpers
    // below need no switch at all.
    //
    // settleOn distinguishes the two disciplines already in the codebase: the commercial CLIs
    // separate isReading from isMutating, so waiting on isUpdating there would also wait out
    // unrelated background polls and stretch every handoff by a poll cycle. TailscaleService is
    // push-driven and only exposes isUpdating.
    readonly property var providerTable: ({
        "tailscale": {
            label: "Tailscale",
            service: TailscaleService,
            settleOn: "isUpdating",
            disconnectMethod: "down"
        },
        "nordvpn": {
            label: "NordVPN",
            service: NordVpnService,
            settleOn: "isMutating",
            disconnectMethod: "disconnect"
        },
        "airvpn": {
            label: "AirVPN",
            service: AirVpnService,
            settleOn: "isMutating",
            disconnectMethod: "disconnect"
        }
    })

    function providerFor(provider): var {
        return root.providerTable[String(provider ?? "")] ?? null;
    }

    // ---------------------------------------------------------------- observed facts
    readonly property bool tailscaleUp: TailscaleService.connected
    readonly property bool nordUp: NordVpnService.connected
    readonly property bool airUp: AirVpnService.connected

    // Tailscale being up is not egress. It only owns the default route when an exit node is
    // set, so mesh-only Tailscale must never trigger a handoff prompt.
    //
    // Order is the tie-break when two commercial tunnels are somehow up at once. Arbitrary but
    // deterministic, which is what matters - a routeOwner that flapped between them would make
    // every handoff decision unstable.
    readonly property string routeOwner: root.nordUp ? "nordvpn"
        : root.airUp ? "airvpn"
        : (root.tailscaleUp && TailscaleService.exitNodeId !== "" ? "tailscale" : "none")

    // Providers can legitimately be connected at once (mesh + commercial egress). "both" is a
    // holdover from when there were two; it now means "two or more", which is all any consumer
    // ever asked of it.
    readonly property bool bothConnected: root.connectedCount > 1

    readonly property int connectedCount:
        (root.tailscaleUp ? 1 : 0) + (root.nordUp ? 1 : 0) + (root.airUp ? 1 : 0)

    // ---------------------------------------------------------------- handoff state
    // idle | confirming | disconnecting | connecting | failed
    property string handoffPhase: "idle"
    property string handoffTarget: ""
    property string lastError: ""

    // The provider that was torn down, so a failed handoff can offer to restore it rather
    // than silently mutating the network back.
    property string recoveryProvider: ""

    property string pendingSelection: ""
    property bool pendingP2p: false
    property int elapsedTicks: 0

    readonly property bool busy: root.handoffPhase === "disconnecting"
        || root.handoffPhase === "connecting"
    readonly property bool awaitingConfirmation: root.handoffPhase === "confirming"

    // 500 ms ticks. Independently bounded per leg, unlike v1's single shared 25 s budget.
    readonly property int disconnectTimeoutTicks: 24  // 12 s
    readonly property int connectTimeoutTicks: 50     // 25 s

    // ---------------------------------------------------------------- text mapping
    function labelFor(provider): string {
        return root.providerFor(provider)?.label ?? "";
    }

    // otherProvider() is deliberately GONE. With two providers a boolean flip happened to name
    // the one being torn down; with three it returns a provider that has nothing to do with the
    // handoff. recoveryProvider is the real answer - it is set to routeOwner at the start of
    // every handoff, which is precisely "the provider whose tunnel we are taking away".

    // The direction guard. A surface only ever sees its own phase.
    function statusTextFor(provider): string {
        if (root.handoffTarget !== provider)
            return "";

        switch (root.handoffPhase) {
        case "confirming":
            return "Switch to " + root.labelFor(provider) + "?";
        case "disconnecting":
            // recoveryProvider, not a flip of `provider`. Reached only from beginHandoff(),
            // which assigns it before setting this phase.
            return "Disconnecting " + root.labelFor(root.recoveryProvider) + "…";
        case "connecting":
            return "Connecting " + root.labelFor(provider) + "…";
        case "failed":
            return root.lastError !== "" ? root.lastError : "Switch failed";
        default:
            return "";
        }
    }

    // ---------------------------------------------------------------- lifecycle
    // Called when a provider page mounts, so a stale phase or error from an earlier attempt
    // cannot persist on screen. v1 rendered lastError indefinitely.
    function clearTransient(): void {
        // Also preserved while confirming: NordVpnPanel calls this on mount, and a handoff
        // started from the hub would otherwise be cancelled the moment the page opened.
        if (root.busy || root.awaitingConfirmation)
            return;
        handoffTimer.stop();
        root.handoffPhase = "idle";
        root.handoffTarget = "";
        root.lastError = "";
        root.recoveryProvider = "";
        root.elapsedTicks = 0;
    }

    function requestProvider(target, selection = "", p2p = false): void {
        // Also ignored while awaiting confirmation: otherwise a second country click
        // silently swapped pendingSelection while the prompt still named the first one.
        if (root.busy || root.awaitingConfirmation || target === "")
            return;

        if (root.providerFor(target) === null)
            return;

        root.pendingSelection = selection;
        root.pendingP2p = p2p;

        // Remember a country-level pick so Quick Connect and the primary toggle reuse it.
        // Nothing wrote this before, so "Quick Connect" always ignored the user's last
        // choice. Sub-country picks ("Country City") are deliberately not persisted - the
        // CLI's own recommended server within a country is the better default next time.
        if (selection !== "" && !selection.includes(" ")) {
            if (target === "nordvpn")
                Config.system.nordvpn.preferredCountry = selection;
            else if (target === "airvpn")
                Config.system.airvpn.preferredCountry = selection;
        }
        root.lastError = "";
        root.recoveryProvider = "";

        // Already connected: a location change is a plain reconnect, NOT a handoff. Routing it
        // through the handoff phases made handoffTimer see providerConnected() already true on
        // its first tick and declare success while the reconnect was still in flight.
        if (target === "nordvpn" && root.nordUp) {
            NordVpnService.connectTo(selection, p2p);
            return;
        }
        if (target === "airvpn" && root.airUp) {
            AirVpnService.connectTo(selection);
            return;
        }
        // Only a no-op when Tailscale ALREADY owns egress. If it is up mesh-only while
        // NordVPN owns the route, "switch to Tailscale" is a real request: release NordVPN
        // so traffic goes direct and the tailnet keeps working. Returning on tailscaleUp
        // alone made that click do nothing at all.
        if (target === "tailscale" && root.routeOwner === "tailscale")
            return;

        root.handoffTarget = target;

        // Nothing owns egress, or the target already does: connect directly.
        if (root.routeOwner === "none" || root.routeOwner === target) {
            root.connectTarget(target);
            return;
        }

        if (Config.system.vpn.handoffPolicy === "confirm") {
            root.handoffPhase = "confirming";
            return;
        }
        root.beginHandoff();
    }

    function confirmHandoff(): void {
        if (root.handoffPhase !== "confirming")
            return;
        root.beginHandoff();
    }

    function cancelHandoff(): void {
        // Only legal before a disconnect has been issued.
        if (root.handoffPhase !== "confirming")
            return;
        root.clearTransient();
    }

    function beginHandoff(): void {
        const owner = root.routeOwner;
        root.recoveryProvider = owner;
        root.handoffPhase = "disconnecting";
        root.elapsedTicks = 0;

        // A provider rejects a mutation while one is already in flight. Detect that instead
        // of showing "Disconnecting..." for 12 s against a command that never ran.
        // Table-driven, so a new provider needs no edit here. The method name differs
        // (Tailscale's is down(), the commercial ones disconnect()), which is why it is data.
        const entry = root.providerFor(owner);
        let started = true;
        if (entry !== null)
            started = entry.service[entry.disconnectMethod]();

        if (!started) {
            root.fail("Could not disconnect " + root.labelFor(owner) + " right now. Try again.");
            return;
        }

        handoffTimer.restart();
    }

    function connectTarget(target): void {
        root.handoffTarget = target;
        root.handoffPhase = "connecting";
        root.elapsedTicks = 0;

        // Already connected: the handoff's purpose was releasing the OTHER provider, which
        // has now happened. Issuing `tailscale up` again would be a pointless mutation and
        // the timer would succeed on its first tick anyway.
        if (root.providerConnected(target)) {
            root.succeed();
            return;
        }

        // Connect stays an explicit switch rather than table data, because the signatures
        // genuinely differ per provider and flattening them would mean inventing a lowest
        // common denominator that fits none of them. An unknown target must NOT fall through:
        // the old `else` branch ran TailscaleService.up(), so a third provider's connect
        // request would have brought up Tailscale instead.
        let started = false;
        if (target === "nordvpn")
            started = NordVpnService.connectTo(root.pendingSelection, root.pendingP2p);
        else if (target === "airvpn")
            started = AirVpnService.connectTo(root.pendingSelection);
        else if (target === "tailscale")
            started = TailscaleService.up();

        if (!started) {
            // Covers Tailscale needing a browser login as well as a busy provider: either way
            // there is no mutation to wait on, so say so instead of timing out.
            root.fail("Could not connect " + root.labelFor(target)
                + " right now. It may be busy or need you to log in.");
            return;
        }

        handoffTimer.restart();
    }

    function providerConnected(provider): bool {
        return root.providerFor(provider)?.service?.connected ?? false;
    }

    function providerSettled(provider): bool {
        const entry = root.providerFor(provider);
        // An unknown provider is NOT settled. Reporting true would let a handoff proceed to
        // connect while the old tunnel was still up.
        if (entry === null)
            return false;
        return !entry.service.connected && !entry.service[entry.settleOn];
    }

    function providerError(provider): string {
        return root.providerFor(provider)?.service?.lastError ?? "";
    }

    function succeed(): void {
        handoffTimer.stop();
        root.handoffPhase = "idle";
        root.handoffTarget = "";
        root.recoveryProvider = "";
        root.lastError = "";
        root.elapsedTicks = 0;
    }

    function fail(message): void {
        handoffTimer.stop();
        root.lastError = String(message ?? "") || "VPN switch failed";
        root.handoffPhase = "failed";
        root.elapsedTicks = 0;
    }

    // Explicit user recovery after a failed handoff. Never automatic - an unexpected
    // network mutation is worse than a visible failure.
    function recover(): void {
        if (root.recoveryProvider === "")
            return;
        const provider = root.recoveryProvider;
        root.lastError = "";
        root.connectTarget(provider);
    }

    function dismissFailure(): void {
        if (root.handoffPhase !== "failed")
            return;
        handoffTimer.stop();
        root.handoffPhase = "idle";
        root.handoffTarget = "";
        root.recoveryProvider = "";
        root.lastError = "";
        root.elapsedTicks = 0;
    }

    // Safety net: a confirmation can be requested from a surface that has no confirm UI
    // mounted (the tray popup can be dismissed mid-question). Auto-cancel rather than
    // leaving the coordinator wedged in "confirming" for the rest of the session.
    Timer {
        id: confirmTimeout
        interval: 30000
        repeat: false
        running: root.awaitingConfirmation
        onTriggered: if (root.awaitingConfirmation) root.cancelHandoff()
    }

    Timer {
        id: handoffTimer
        interval: 500
        repeat: true

        onTriggered: {
            root.elapsedTicks++;

            if (root.handoffPhase === "disconnecting") {
                // recoveryProvider is the one actually being torn down. The old
                // otherProvider(handoffTarget) flip happened to be right for two providers and
                // is wrong for three - it would have waited on a provider nobody touched, so
                // this branch would settle instantly and connect over a live tunnel.
                if (root.providerSettled(root.recoveryProvider)) {
                    root.connectTarget(root.handoffTarget);
                    return;
                }
                if (root.elapsedTicks > root.disconnectTimeoutTicks)
                    root.fail("Timed out disconnecting " + root.labelFor(root.recoveryProvider));
                return;
            }

            if (root.handoffPhase === "connecting") {
                if (root.providerConnected(root.handoffTarget)) {
                    root.succeed();
                    return;
                }
                const error = root.providerError(root.handoffTarget);
                if (error !== "") {
                    root.fail(error);
                    return;
                }
                if (root.elapsedTicks > root.connectTimeoutTicks)
                    root.fail("Timed out connecting " + root.labelFor(root.handoffTarget));
                return;
            }

            handoffTimer.stop();
        }
    }
}
