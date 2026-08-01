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
    // Either signal is sufficient, and they arrive from two independent async reads whose
    // order is not guaranteed - so this must be an OR, not a state assignment.
    readonly property bool needsLogin: root.state === "loggedOut"
        || (root.available && !root.loggedIn)
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

    // True once an automatic login attempt has run its full course without the account
    // becoming logged in. This is what gates the manual paste path in the setup card.
    //
    // Offering that path up front made the ordinary one-click flow look unreliable, but it
    // cannot be absent either: the browser's nordvpn:// hand-back is outside this widget and
    // when it breaks the UI is otherwise a dead end. Showing it exactly when the automatic
    // flow has demonstrably not worked is the honest middle - invisible on a healthy desktop,
    // present the moment it is needed. Set only on the poll ceiling, because that is the one
    // failure the manual link can actually repair: the user reached the browser, finished
    // signing in, and the reply never arrived. A `nordvpn login` that errors outright never
    // produced a Continue button to copy, so pasting cannot help there.
    property bool loginNeedsManual: false

    // Set when lastError came from a mutation. A mutation failure triggers an immediate
    // refresh, and the successful status read that follows would otherwise clear the error
    // within ~200ms - before VpnService's 500ms handoff tick ever observed it, leaving the
    // user watching "Connecting..." until timeout instead of seeing the reason.
    property bool errorFromMutation: false

    // Promoted failure class, mirroring TailscaleService.operatorMissing: a permissions
    // problem needs one-time setup guidance, not a raw CLI string thrown at the user.
    property bool permissionDenied: false

    // False when the daemon is unreachable. Distinct from needsLogin so the panel never
    // offers a login flow that cannot possibly succeed.
    property bool daemonReachable: true

    // From `nordvpn account`. This is load-bearing: on a logged-out machine
    // `nordvpn status` prints only "Status: Disconnected" (see
    // lab/fixtures/nordvpn/status-disconnected.txt, captured while logged out), so status
    // alone can NEVER tell us we are logged out. Without this the panel offers Quick
    // Connect and 149 countries that all fail.
    property bool loggedIn: true

    // ---------------------------------------------------------------- model
    readonly property list<NordVpnCountry> countries: []
    property list<var> sortedCountries: []
    readonly property int countryCount: root.countries.length
    readonly property list<string> favoriteTokens: Config.system.nordvpn.favoriteCountries
        ?? []
    readonly property var favoriteCountries: root.sortedCountries.filter(country =>
        root.favoriteTokens.includes(country.token))

    function isFavorite(token): bool {
        return root.favoriteTokens.includes(String(token ?? ""));
    }

    function toggleFavorite(token): void {
        const normalized = String(token ?? "");
        if (normalized === "")
            return;

        const next = [...root.favoriteTokens];
        const index = next.indexOf(normalized);
        if (index >= 0)
            next.splice(index, 1);
        else
            next.push(normalized);
        Config.system.nordvpn.favoriteCountries = next;
    }

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
        // All three parts, not just two. accountProc was missing here, and it is the slowest
        // of the three: a refresh could re-arm refreshPartsRemaining to 3 while the previous
        // account read was still in flight, so that stale reply decremented the NEW budget and
        // isReading cleared one part early - defeating the invariant finishRefreshPart() exists
        // to hold, which is that VpnService never reads a half-refreshed snapshot.
        if (statusProc.running || settingsProc.running || accountProc.running)
            return;

        root.isReading = true;
        root.refreshPartsRemaining = 3;
        statusProc.run();
        settingsProc.run();
        accountProc.run();

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
        root.errorFromMutation = false;
        root.runAsync(command).then(() => {
            root.permissionDenied = false;
            root.isMutating = false;
            root.refresh();
        }).catch(error => {
            root.handleMutationError(error);
            root.errorFromMutation = root.lastError !== "";
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
        // Last line of defence. The panel hides connect affordances while logged out, but a
        // status read can land before the account read, so for a moment the UI may still
        // offer them. Refusing here means the worst case is a no-op rather than a CLI error
        // the user has to interpret.
        if (root.needsLogin || root.permissionDenied || !root.daemonReachable)
            return false;

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


    function disconnect(): bool {
        if (!root.runMutation(["nordvpn", "disconnect"]))
            return false;
        root.requestedTarget = "";
        root.state = "disconnecting";
        return true;
    }

    // `nordvpn login` does NOT open a browser. It prints
    //     Continue in the browser: https://api.nordvpn.com/v1/users/oauth/login-redirect?...
    // to stdout and exits 0. Running it detached threw that line away, so clicking "Log in"
    // did visibly nothing. Capture the output, pull the URL out, and hand it to the desktop's
    // default handler via xdg-open - the same idiom TailscaleService uses for its admin
    // console link.
    //
    // Opening the URL is only HALF the flow, and the other half is not ours: the browser
    // finishes by handing `nordvpn://login?...&exchange_token=...` back to the desktop, which
    // must route it to `nordvpn click`. When that hop is broken the browser shows its
    // "open this link" prompt, the user accepts, and nothing happens - see loginWithCallback()
    // for the escape hatch, and lab/check-prereqs.sh for detecting the broken hop.
    function login(): void {
        // loginPending, not just isMutating: login() does not run through runMutation, so
        // isMutating is never set here and two quick clicks would otherwise start two OAuth
        // attempts and open two browser tabs.
        if (!root.available || !root.enabled || root.isMutating || root.loginPending)
            return;

        root.loginPending = true;
        // A failed earlier attempt must not keep its error, or its manual fallback, on screen
        // while a fresh one is still in its own window.
        root.lastError = "";
        root.loginNeedsManual = false;
        loginPollTimer.restart();

        root.runAsync(["nordvpn", "login"]).then(output => {
            const url = root.extractLoginUrl(output);
            if (url !== "") {
                Quickshell.execDetached(["xdg-open", url]);
                return;
            }
            // Logged in already, or a build that opens its own browser: either way the next
            // poll resolves it. Only complain if we got something we cannot act on.
            if (!/already logged in/i.test(output))
                root.lastError = "Could not get a login link from NordVPN";
            root.loginPending = false;
        }).catch(error => {
            root.loginPending = false;
            root.handleMutationError(error);
        });
    }

    // The manual completion path, for when the browser's hand-back never reaches the CLI.
    // `nordvpn login --callback "<url>"` is NordVPN's own documented remedy ("Complete the
    // login manually if your browser fails to open the app"): the user copies the link behind
    // the browser's "Continue" button and pastes it here.
    //
    // This exists because the hand-back is genuinely fragile and is NOT something the widget
    // can repair. On Bostrom it was broken outright: /usr/share/applications/nordvpn.desktop
    // declares `Terminal=true`, so GLib refuses to launch `nordvpn click` unless it recognizes
    // an installed terminal - and it knows nothing about kitty or alacritty, which is all this
    // machine has. `gio launch` failed with "Unable to find terminal required for application"
    // while the browser reported success, which is exactly the reported symptom: log in, click
    // Continue, accept the prompt, stay logged out.
    //
    // No shell is involved, so the URL is passed as a single argv element and the quoting the
    // CLI's help asks for is neither needed nor wanted.
    function loginWithCallback(url): bool {
        if (!root.available || !root.enabled || root.isMutating)
            return false;

        const trimmed = String(url ?? "").trim();
        // Checked before spending a process: the CLI answers a malformed argument with
        // "Expected a url.", which tells the user nothing about what went wrong.
        if (!/^nordvpn:\/\/\S+$/.test(trimmed)) {
            root.lastError = "That does not look like a NordVPN login link. "
                + "It should start with nordvpn://";
            return false;
        }

        root.loginPending = true;
        root.lastError = "";

        root.runAsync(["nordvpn", "login", "--callback", trimmed]).then(() => {
            // Success is confirmed by the account read, not assumed here.
            root.refresh();
        }).catch(error => {
            root.loginPending = false;
            root.handleMutationError(error);
        });
        return true;
    }

    // Matches any http(s) URL in the CLI's output rather than the surrounding prose, so a
    // reworded message or a localized build still works.
    function extractLoginUrl(output): string {
        const match = String(output ?? "").match(/https?:\/\/\S+/);
        return match ? match[0] : "";
    }

    function setTechnology(value): void {
        if (!["NordLynx", "OpenVPN"].includes(value))
            return;
        if (!root.runMutation(["nordvpn", "set", "technology", value]))
            return;

        // Keep the service-backed control on the accepted selection while the CLI command
        // and verification read run. Without this, the control's external value remained
        // stale and its reconciliation path visibly bounced old -> new after every click.
        root.technology = value;
        root.settings = Object.assign({}, root.settings, { technology: value });
    }

    function setBoolSetting(key, value): void {
        if (!key)
            return;
        if (!root.runMutation(["nordvpn", "set", key, value ? "on" : "off"]))
            return;

        // CLI spelling -> normalized parser/service property. Optimistically update only
        // after runMutation accepts the command; its mandatory refresh remains authoritative
        // and rolls this snapshot back if the command fails.
        const propertyForKey = {
            "killswitch": "killSwitch",
            "autoconnect": "autoConnect",
            "lan-discovery": "lanDiscovery",
            "threatprotectionlite": "threatProtection",
            "virtual-location": "virtualLocation",
            "post-quantum": "postQuantum"
        };
        const propertyName = propertyForKey[key];
        if (propertyName) {
            const nextSettings = Object.assign({}, root.settings);
            nextSettings[propertyName] = value;
            root.settings = nextSettings;
        }
    }

    // ---------------------------------------------------------------- timers
    // Watchdogs. Both flags are latches that gate everything downstream: performRefresh
    // early-returns on isReading, and runMutation rejects on isMutating. If a `nordvpn`
    // invocation never exits - a wedged daemon is the realistic case - the corresponding
    // latch would stay set for the rest of the session, silently freezing all state reads
    // or making every button permanently dead. Neither failure is recoverable without
    // restarting the shell, so both get a ceiling.
    Timer {
        id: readWatchdog
        interval: 20000
        repeat: false
        running: root.isReading
        onTriggered: {
            root.isReading = false;
            root.refreshPartsRemaining = 0;
            root.lastError = "Timed out reading NordVPN state";
        }
    }

    Timer {
        id: mutationWatchdog
        // Generous: a real connect legitimately takes many seconds.
        interval: 45000
        repeat: false
        running: root.isMutating
        onTriggered: {
            root.isMutating = false;
            root.lastError = "NordVPN command timed out";
            root.errorFromMutation = true;
            root.refresh();
        }
    }

    // A mutation error is preserved against the refresh it triggers, but it must not be
    // preserved forever: without a ceiling, one failed connect would pin the error banner
    // for the rest of the session even after the tunnel recovered. Long enough for the
    // coordinator's 500ms tick and for a human to read it, then it becomes clearable again.
    Timer {
        id: mutationErrorTtl
        interval: 10000
        repeat: false
        running: root.errorFromMutation
        onTriggered: root.errorFromMutation = false
    }

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
        repeat: true
        running: root.loginPending && root.available && root.enabled

        // Elapsed time, not a tick count, because the interval changes partway through.
        property int elapsedMs: 0

        // Two-phase on purpose. A flat 2 s for the full five minutes would be 150 refresh
        // bursts of three CLI calls each, sustained, for a window that is mostly the user
        // reading an email. Fast while they are plausibly still on our screen, then relaxed.
        readonly property int fastPhaseMs: 30000
        interval: loginPollTimer.elapsedMs < loginPollTimer.fastPhaseMs ? 2000 : 5000

        // Five minutes. The old 60 s ceiling assumed the only thing worth bounding was a
        // false "Waiting..." after an abandoned login, but a real login routinely takes
        // longer than that - 2FA, or fetching a code out of email - and giving up mid-flow
        // reverted the card to "Log in required" while the browser was still open, which
        // reads as a second failure. The button stays live for a retry throughout either way.
        readonly property int ceilingMs: 300000

        onTriggered: {
            loginPollTimer.elapsedMs += loginPollTimer.interval;
            if (loginPollTimer.elapsedMs >= loginPollTimer.ceilingMs) {
                root.loginPending = false;
                // The browser flow was opened and never came back. This is the one failure the
                // manual callback link can repair, so reveal it now.
                root.loginNeedsManual = true;
                return;
            }
            root.refresh();
        }

        onRunningChanged: if (!running) loginPollTimer.elapsedMs = 0
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
            // Anchored phrases, not a bare "log in" substring. `nordvpn status` is the one
            // read that runs while CONNECTED, and the CLI is happy to append promotional or
            // hint lines to it; a bare match would let any of them demote a live tunnel to
            // "logged out" and hide the whole panel behind the setup card. Missing an unusual
            // phrasing here is cheap because `nordvpn account` is the authoritative signal and
            // needsLogin ORs the two.
            } else if (/not logged in|please log in|log in to nordvpn/i.test(combined)) {
                root.state = "loggedOut";
                root.daemonReachable = true;
                // Same rule as the success branch below: a mutation's error must survive the
                // refresh that mutation triggered. Clearing unconditionally here meant a
                // connect that failed on a logged-out account lost its reason immediately.
                if (!root.errorFromMutation)
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

                // Only clear a READ-originated error. A failed mutation triggers an
                // immediate refresh, and clearing here unconditionally erased the reason
                // ~200ms later - before VpnService's 500ms handoff tick could observe it, so
                // the user watched "Connecting..." until timeout instead of seeing why.
                if (!root.errorFromMutation)
                    root.lastError = "";

                // Never leave an unrecognized status as a bare "Error" with no detail. This
                // is the one place that knows what the CLI actually said.
                if (parsed.state === "error" && parsed.unknownStatus !== undefined) {
                    root.lastError = "Unexpected VPN status: " + parsed.unknownStatus;
                    root.errorFromMutation = false;
                }
            } else {
                root.state = "error";
                root.lastError = error || output.trim() || "Could not read NordVPN status";
            }

            root.finishRefreshPart();
        }
    }

    CliRead {
        id: accountProc
        command: ["nordvpn", "account"]

        onParsed: (output, error, code) => {
            const parsed = Parse.parseAccount(error + "\n" + output, code);
            root.loggedIn = parsed.loggedIn;
            if (!parsed.daemonReachable)
                root.daemonReachable = false;
            if (parsed.loggedIn) {
                root.loginPending = false;
                // Cleared on success so a later logout starts from the plain card rather than
                // inheriting the previous session's fallback.
                root.loginNeedsManual = false;
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
