pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.globals
import "nordvpn-parse.js" as Parse

// NordVPN provider service. Owns CLI discovery, normalized state, the country/city model,
// settings, and mutations. Coordination with Tailscale lives in VpnService, not here.
//
// All output parsing is delegated to nordvpn-parse.js so it stays testable under node via
// lab/test-nordvpn-parse.sh. This file must contain no string-scraping of its own.
Singleton {
    id: root

    // ---------------------------------------------------------------- state
    property bool available: false
    readonly property bool enabled: Config.system.nordvpn.enabled

    // unavailable | loggedOut | disconnected | connecting | connected | disconnecting | error
    property string state: "unavailable"

    readonly property bool connected: root.state === "connected"
    readonly property bool connecting: root.state === "connecting"
    readonly property bool disconnecting: root.state === "disconnecting"
    readonly property bool needsLogin: root.state === "loggedOut"
    readonly property bool inError: root.state === "error"

    // Connection detail. Every one is empty-safe; the panel hides a row rather than
    // rendering a blank label (plan section 3 degradation rules).
    property string country: ""
    property string city: ""
    property string server: ""
    property string technology: ""
    property string protocol: ""
    property string uptime: ""

    // Deliberately absent: the assigned IP. nordvpn-parse.js drops it at the parser
    // boundary, so no property here could leak it into a log or a screenshot.

    // Reads and mutations are tracked SEPARATELY and this matters a lot.
    // Conflating them (as v1 did, and as TailscaleService can afford to because it is
    // push-driven) means every background poll makes the whole UI look busy: buttons grey
    // out for reasons the user did not cause, and runMutation's guard silently swallows
    // clicks. A poll runs at least every 5 s, so that is a permanent feel-of-lag bug.
    // Only isMutating may gate a control or reject a user action.
    property bool isReading: false
    property bool isMutating: false

    // Kept for spinner-style "something is happening" affordances only. Never gate a
    // control or a mutation on this.
    readonly property bool isUpdating: root.isReading || root.isMutating

    property string lastError: ""

    // True from clicking "Log in" until the next status read resolves the account state.
    // Without it the detached browser flow looks like a click that did nothing.
    property bool loginPending: false

    // Promoted failure class, mirroring TailscaleService.operatorMissing: a permissions
    // problem needs one-time setup guidance, not a raw CLI string thrown at the user.
    property bool permissionDenied: false

    // False when the daemon is unreachable. Distinct from needsLogin so the panel never
    // offers a login flow that cannot possibly succeed.
    property bool daemonReachable: true

    // ---------------------------------------------------------------- model
    readonly property list<NordVpnCountry> countries: []
    property list<var> sortedCountries: []
    readonly property int countryCount: root.countries.length

    // What the user last asked to connect to, so feedback can say "Connecting to Japan..."
    // instead of a bare spinner. Cleared on disconnect.
    property string requestedTarget: ""

    // Pending city lookups; the CLI takes one country at a time.
    property list<var> cityQueue: []

    property var settings: ({})
    property bool supportsP2p: false
    property string p2pToken: "P2P"

    // Anything that is not "p2p" means standard. Compared this way on purpose: a persisted
    // config may still hold v1's "fastest", and an exact match on "standard" would silently
    // flip those users into P2P.
    readonly property bool p2pPreferred: Config.system.nordvpn.preferredMode === "p2p"

    property int refreshPartsRemaining: 0

    // ---------------------------------------------------------------- async mutation
    Component {
        id: asyncProcessComp

        Process {
            id: internalProc

            property var resolve
            property var reject
            property string buffer: ""
            property string errorBuffer: ""

            environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })

            stdout: SplitParser {
                onRead: data => internalProc.buffer += data + "\n"
            }

            stderr: SplitParser {
                onRead: data => internalProc.errorBuffer += data + "\n"
            }

            onExited: (exitCode, exitStatus) => {
                if (exitCode === 0)
                    resolve(buffer.trim());
                else
                    reject(errorBuffer.trim() || buffer.trim() || `Process exited with code ${exitCode}`);
                destroy();
            }
        }
    }

    function runAsync(command) {
        return new Promise((resolve, reject) => {
            const proc = asyncProcessComp.createObject(root, {
                command: command,
                resolve: resolve,
                reject: reject
            });
            proc.running = true;
        });
    }

    // ---------------------------------------------------------------- refresh
    // Public entry point is debounced so back-to-back callers (panel open, mutation
    // completion, poll tick) coalesce into one CLI burst - TailscaleService.qml:269-274.
    function refresh(): void {
        refreshDebouncer.restart();
    }

    function performRefresh(): void {
        // Deliberately NOT gated on isMutating: reading state while a connect is in flight
        // is exactly when the UI most needs fresh data.
        if (!root.available || !root.enabled || root.isReading)
            return;
        if (statusProc.running || settingsProc.running)
            return;

        root.isReading = true;
        root.refreshPartsRemaining = 2;
        statusProc.run();
        settingsProc.run();

        // Static lists: fetch once, then only on explicit demand.
        if (root.countries.length === 0 && !countriesProc.running)
            countriesProc.run();
        if (!root.supportsP2p && !groupsProc.running)
            groupsProc.run();
    }

    // isUpdating must not clear until every part has landed, or VpnService's handoff waits
    // read a half-refreshed snapshot. v1 cleared it on a blind 900 ms timer instead.
    function finishRefreshPart(): void {
        root.refreshPartsRemaining = Math.max(0, root.refreshPartsRemaining - 1);
        if (root.refreshPartsRemaining === 0)
            root.isReading = false;
    }

    function refreshCountries(): void {
        if (root.available && root.enabled && !countriesProc.running)
            countriesProc.run();
    }

    // ---------------------------------------------------------------- country model
    // Reconcile by identity rather than clear-and-rebuild, so delegates keep their objects
    // and an expanded row does not collapse on every poll - TailscaleService.qml:122-155.
    function syncCountries(tokens): void {
        const current = root.countries;

        for (let i = current.length - 1; i >= 0; i--) {
            if (!tokens.includes(current[i].token)) {
                const stale = current[i];
                current.splice(i, 1);
                stale.destroy();
            }
        }

        for (const token of tokens) {
            if (!current.some(entry => entry.token === token))
                current.push(countryComp.createObject(root, { token: token }));
        }

        root.updateDerivedLists();
    }

    function updateDerivedLists(): void {
        root.sortedCountries = [...root.countries].sort((a, b) => a.name.localeCompare(b.name));
    }

    function countryForToken(token) {
        return root.countries.find(entry => entry.token === token) ?? null;
    }

    // Cities cost one CLI call each, so they are fetched only when a row is expanded.
    // Requests QUEUE rather than being dropped: expanding a second country while the first
    // is still loading previously left the second row permanently blank with no spinner.
    function loadCities(token): void {
        if (!root.available || !root.enabled || !token)
            return;
        const country = root.countryForToken(token);
        if (!country || country.citiesLoaded || country.citiesLoading)
            return;

        // Set before queuing, so the row shows a spinner immediately even while waiting.
        country.citiesLoading = true;

        if (citiesProc.running) {
            if (!root.cityQueue.includes(token))
                root.cityQueue = root.cityQueue.concat([token]);
            return;
        }
        root.startCityFetch(token);
    }

    function startCityFetch(token): void {
        citiesProc.pendingToken = token;
        citiesProc.run();
    }

    function drainCityQueue(): void {
        if (citiesProc.running || root.cityQueue.length === 0)
            return;
        const next = root.cityQueue[0];
        root.cityQueue = root.cityQueue.slice(1);

        const country = root.countryForToken(next);
        if (!country || country.citiesLoaded) {
            root.drainCityQueue();
            return;
        }
        root.startCityFetch(next);
    }

    // ---------------------------------------------------------------- mutations
    // Returns false when the request was rejected, so callers (and the coordinator) can tell
    // "started" from "silently dropped" instead of waiting on a mutation that never ran.
    function runMutation(command): bool {
        if (!root.available || !root.enabled || root.isMutating)
            return false;

        root.isMutating = true;
        root.lastError = "";
        root.runAsync(command).then(() => {
            root.permissionDenied = false;
            root.isMutating = false;
            root.refresh();
        }).catch(error => {
            root.handleMutationError(error);
            root.isMutating = false;
            root.refresh();
        });
        return true;
    }

    function handleMutationError(error): void {
        const message = String(error ?? "").trim();
        if (/permission denied|nordvpn group|access denied/i.test(message)) {
            root.permissionDenied = true;
            root.lastError = "";
        } else {
            root.lastError = message;
        }
    }

    // target: "" for recommended, else a country token, an ISO code, or "Country City".
    // Argument grammar verified from lab/fixtures/nordvpn/help-connect.txt.
    function connectTo(target = "", p2p = false): bool {
        const command = ["nordvpn", "connect"];
        if (p2p && root.supportsP2p)
            command.push("--group", root.p2pToken);

        const trimmed = String(target ?? "").trim();
        if (trimmed !== "") {
            // "Country City" arrives as one string but the CLI wants two arguments.
            for (const part of trimmed.split(/\s+/))
                command.push(part);
        }

        if (!root.runMutation(command))
            return false;

        // Optimistic, corrected by the next status read. Applied unconditionally - including
        // when already connected - because switching country is a reconnect, and gating this
        // on "disconnected" left the UI showing the OLD location with no sign of activity.
        root.requestedTarget = trimmed;
        root.state = "connecting";
        return true;
    }

    function connectToCity(countryToken, cityToken): bool {
        if (!countryToken || !cityToken)
            return false;
        return root.connectTo(countryToken + " " + cityToken, root.p2pPreferred);
    }

    function disconnect(): bool {
        if (!root.runMutation(["nordvpn", "disconnect"]))
            return false;
        root.requestedTarget = "";
        root.state = "disconnecting";
        return true;
    }

    function toggle(): void {
        if (root.permissionDenied || root.isMutating)
            return;
        if (root.connected)
            root.disconnect();
        else
            root.connectTo(Config.system.nordvpn.preferredCountry, root.p2pPreferred);
    }

    function login(): void {
        if (!root.available || !root.enabled)
            return;
        // Detached browser flow: nothing here can observe its outcome, so mark it pending and
        // poll faster until the account state resolves. Otherwise the click looks inert.
        root.loginPending = true;
        Quickshell.execDetached(["nordvpn", "login"]);
        loginPollTimer.restart();
    }

    function setTechnology(value): void {
        if (!["NordLynx", "OpenVPN"].includes(value))
            return;
        root.runMutation(["nordvpn", "set", "technology", value]);
    }

    function setBoolSetting(key, value): void {
        if (!key)
            return;
        root.runMutation(["nordvpn", "set", key, value ? "on" : "off"]);
    }

    // ---------------------------------------------------------------- timers
    Timer {
        id: refreshDebouncer
        interval: 200
        repeat: false
        onTriggered: root.performRefresh()
    }

    // Visibility-gated per BluetoothService.qml:246-253 rather than carrying a second
    // interval config key. Keeps polling while connected or transitioning so the UI does
    // not go stale behind a closed dashboard mid-handoff.
    Timer {
        id: pollingTimer
        interval: Math.max(5, Config.system.nordvpn.pollInterval) * 1000
        repeat: true
        running: root.available && root.enabled && !SuspendManager.isSuspending
            && (GlobalStates.dashboardOpen || GlobalStates.launcherOpen || GlobalStates.overviewOpen
                || root.connected || root.connecting || root.disconnecting)
        onTriggered: root.refresh()
    }

    // While a detached `nordvpn login` browser flow is open, poll faster than the normal
    // interval so the panel flips out of "waiting for login" promptly instead of up to 20 s
    // later. Bounded so a login the user abandoned does not poll forever.
    Timer {
        id: loginPollTimer
        interval: 2000
        repeat: true
        running: root.loginPending && root.available && root.enabled
        property int ticks: 0

        onTriggered: {
            ticks++;
            // 60 s, not 3 minutes: we cannot observe the user closing the browser, so the
            // ceiling is the only exit. Three minutes of a false "Waiting..." is worse than
            // giving up early - the Log in button stays live for a retry either way.
            if (ticks > 30) {
                root.loginPending = false;
                ticks = 0;
                return;
            }
            root.refresh();
        }

        onRunningChanged: if (!running) ticks = 0
    }

    // Tunnel state is routinely stale across resume; neither VPN service handled this in v1.
    property var suspendConnections: Connections {
        target: SuspendManager

        function onWakingUp() {
            if (root.available && root.enabled)
                root.refresh();
        }
    }

    // ---------------------------------------------------------------- processes
    // One read-command shape, declared once. Every NordVPN read is "run argv, accumulate
    // both streams, parse once on exit under Qt.callLater" - repeating that block five
    // times (as v1 did) is where transcription bugs live.
    component CliRead: Process {
        id: cli

        property string buffer: ""
        property string errorBuffer: ""

        // Deferred via Qt.callLater by the emitter, so handlers may safely mutate lists -
        // required by modules/services/AGENTS.md:33.
        signal parsed(string output, string error, int code)

        environment: ({
            LANG: "C.UTF-8",
            LC_ALL: "C.UTF-8"
        })

        function run(): void {
            cli.buffer = "";
            cli.errorBuffer = "";
            cli.running = true;
        }

        stdout: SplitParser {
            onRead: data => cli.buffer += data + "\n"
        }

        stderr: SplitParser {
            onRead: data => cli.errorBuffer += data + "\n"
        }

        onExited: (exitCode, exitStatus) => {
            // Snapshot then clear, so the deferred closure reads a stable value.
            const output = cli.buffer;
            const error = cli.errorBuffer.trim();
            cli.buffer = "";
            cli.errorBuffer = "";
            Qt.callLater(() => cli.parsed(output, error, exitCode));
        }
    }

    Process {
        id: availabilityProbe
        command: ["which", "nordvpn"]

        onExited: exitCode => {
            root.available = exitCode === 0;
            if (!root.available) {
                root.state = "unavailable";
                return;
            }
            if (root.enabled)
                root.refresh();
        }
    }

    CliRead {
        id: statusProc
        command: ["nordvpn", "status"]

        onParsed: (output, error, code) => {
            // Classify before parsing: a permissions or daemon failure is not a tunnel
            // state, and must not be flattened into "disconnected".
            const combined = error + "\n" + output;

            if (/permission denied|nordvpn group/i.test(combined)) {
                root.permissionDenied = true;
                root.state = "error";
                root.lastError = "";
                // Not a login problem, so stop claiming we are waiting on a browser.
                root.loginPending = false;
            } else if (/not logged in|log in/i.test(combined)) {
                root.state = "loggedOut";
                root.daemonReachable = true;
                root.lastError = "";
            } else if (/daemon|socket|connection refused/i.test(combined)) {
                root.daemonReachable = false;
                root.state = "error";
                root.lastError = "NordVPN daemon is not reachable";
                // A login cannot complete against a dead daemon; drop the pending state so
                // the card shows the real problem instead of "Waiting for browser".
                root.loginPending = false;
            } else if (code === 0) {
                // A successful status read means we are past the logged-out state, so a
                // pending browser login has resolved. Clearing this only on the 3-minute
                // timeout left the setup card stuck on "Waiting for browser".
                root.loginPending = false;
                const parsed = Parse.parseStatus(output);
                root.state = parsed.state;
                root.country = parsed.country;
                root.city = parsed.city;
                root.server = parsed.server;
                root.protocol = parsed.protocol;
                root.uptime = parsed.uptime;
                if (parsed.technology !== "")
                    root.technology = parsed.technology;
                root.daemonReachable = true;
                root.permissionDenied = false;
                root.lastError = "";
            } else {
                root.state = "error";
                root.lastError = error || output.trim() || "Could not read NordVPN status";
            }

            root.finishRefreshPart();
        }
    }

    CliRead {
        id: settingsProc
        command: ["nordvpn", "settings"]

        onParsed: (output, error, code) => {
            if (code === 0) {
                const parsed = Parse.parseSettings(output);
                root.settings = parsed;
                if (parsed.technology !== "")
                    root.technology = parsed.technology;
            }
            root.finishRefreshPart();
        }
    }

    CliRead {
        id: countriesProc
        command: ["nordvpn", "countries"]

        onParsed: (output, error, code) => {
            if (code === 0)
                root.syncCountries(Parse.parseList(output));
        }
    }

    CliRead {
        id: groupsProc
        command: ["nordvpn", "groups"]

        onParsed: (output, error, code) => {
            if (code !== 0)
                return;
            const parsed = Parse.parseGroups(output);
            root.supportsP2p = parsed.supportsP2p;
            if (parsed.p2pToken !== "")
                root.p2pToken = parsed.p2pToken;
        }
    }

    CliRead {
        id: citiesProc

        property string pendingToken: ""

        command: ["nordvpn", "cities", citiesProc.pendingToken]

        onParsed: (output, error, code) => {
            const token = citiesProc.pendingToken;
            citiesProc.pendingToken = "";

            // Drain unconditionally. If the country model refreshed and dropped this token
            // mid-fetch, an early return here stranded every queued row spinning forever.
            const country = root.countryForToken(token);
            if (country) {
                country.cities = code === 0 ? Parse.parseList(output) : [];
                country.citiesLoaded = true;
                country.citiesLoading = false;
            }
            root.drainCityQueue();
        }
    }

    Component {
        id: countryComp

        NordVpnCountry {}
    }

    onEnabledChanged: {
        if (root.enabled && root.available)
            root.refresh();
    }

    Component.onCompleted: availabilityProbe.running = true
}
