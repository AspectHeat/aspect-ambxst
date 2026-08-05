pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.globals
import "airvpn-parse.js" as Parse

// AirVPN provider service (AirVPN Suite: goldcrest talking to the bluetit daemon). Owns CLI
// discovery, normalized state, the country model, and mutations. Coordination with the other
// providers lives in VpnService, not here.
//
// All output parsing is delegated to airvpn-parse.js so it stays testable under node via
// lab/test-airvpn-parse.sh. This file must contain no string-scraping of its own.
//
// ===========================================================================================
// SAFETY - read this before adding any goldcrest invocation.
// ===========================================================================================
// An unauthenticated `goldcrest --air-user-info` / `--air-key-list` / `--air-connect` does NOT
// fail. It prompts on stdin ("AirVPN Username: ") and blocks. Quickshell's Process hands its
// child EOF on stdin, and on EOF goldcrest re-prompts in a tight loop - measured at 3.97 GB of
// stdout in 12 seconds on Bostrom. Accumulating that into cli.buffer would OOM the shell and
// take the desktop down with it, because Ambxst is Bostrom's primary shell.
//
// Three independent mitigations, all of which must stay in place:
//   1. credentialsConfigured is derived by READING ~/.config/goldcrest.rc (rcFile below), not
//      by probing the CLI. A file read cannot hang or flood. Nothing credential-requiring is
//      invoked unless it is true.
//   2. Every invocation is timeout-wrapped (see goldcrest()).
//   3. CliRead enforces a byte ceiling and kills the process when it is breached.
//
// See docs/airvpn-recon-findings.md §1.
Singleton {
    id: root

    // ---------------------------------------------------------------- state
    property bool available: false
    readonly property bool enabled: Config.system.airvpn.enabled

    // unavailable | needsCredentials | disconnected | connecting | connected | disconnecting | error
    property string state: "unavailable"

    readonly property bool connected: root.state === "connected"
    readonly property bool connecting: root.state === "connecting"
    readonly property bool disconnecting: root.state === "disconnecting"
    readonly property bool inError: root.state === "error"

    // An OR, not a state assignment: the rc-file read and the status read are independent and
    // their order is not guaranteed. Same shape as NordVpnService.needsLogin.
    readonly property bool needsCredentials: root.state === "needsCredentials"
        || (root.available && !root.credentialsConfigured)

    // Authoritative credentials signal, from the rc file rather than the CLI. See SAFETY.
    property bool credentialsConfigured: false
    // Username only. The password is never read out of the parser, let alone stored here.
    property string accountUser: ""
    property bool hasDeviceKey: false

    // False when bluetit is down or D-Bus policy refuses this user. Distinct from
    // needsCredentials so the panel never offers a login flow that cannot succeed.
    property bool daemonReachable: true
    property bool permissionDenied: false

    // Connection detail. Every one is empty-safe; the panel hides a row rather than rendering
    // a blank label (plan §3 degradation rules).
    property string country: ""
    property string server: ""
    property string technology: ""

    // Deliberately absent: the assigned/exit IP. airvpn-parse.js drops it at the parser
    // boundary, so no property here could leak it into a log or a screenshot.

    // Network filter and lock, as OBSERVED from status. networkLockKnown distinguishes "off"
    // from "this build never said", so the panel can hide the row instead of rendering a
    // control that does nothing.
    property bool networkLock: false
    property bool networkLockKnown: false

    // Reads and mutations are tracked SEPARATELY, and this matters a lot. Conflating them
    // means every background poll makes the UI look busy: buttons grey out for reasons the
    // user did not cause, and runMutation's guard silently swallows clicks. Only isMutating
    // may gate a control or reject a user action.
    property bool isReading: false
    property bool isMutating: false

    // Spinner-style "something is happening" affordances only. Never gate a control on this.
    readonly property bool isUpdating: root.isReading || root.isMutating

    property string lastError: ""

    // Set when lastError came from a mutation. A mutation failure triggers an immediate
    // refresh, and the successful status read that follows would otherwise clear the error
    // within ~200 ms - before VpnService's 500 ms handoff tick ever observed it, leaving the
    // user watching "Connecting…" until timeout instead of seeing the reason.
    property bool errorFromMutation: false

    // ---------------------------------------------------------------- timeouts
    // `timeout` is coreutils, so it is always present. -k sends KILL if TERM is ignored.
    // Read ceiling is below readWatchdog's, and the mutation ceiling below mutationWatchdog's,
    // so the process dies before the latch does and the watchdog stays a backstop rather than
    // the primary mechanism.
    readonly property int readTimeoutSecs: 15
    readonly property int mutationTimeoutSecs: 40

    function goldcrest(args, seconds): var {
        return ["timeout", "-k", "2", String(seconds), "goldcrest"].concat(args ?? []);
    }

    // buildConnectArgv() already yields ["goldcrest", …]; this wraps it without a second
    // hard-coded binary name.
    function withTimeout(argv, seconds): var {
        return ["timeout", "-k", "2", String(seconds)].concat(argv ?? []);
    }

    // ---------------------------------------------------------------- model
    readonly property list<AirVpnCountry> countries: []
    property list<var> sortedCountries: []
    readonly property int countryCount: root.countries.length

    readonly property list<string> favoriteTokens: Config.system.airvpn.favoriteCountries ?? []
    readonly property var favoriteCountries: root.sortedCountries.filter(country =>
        root.favoriteTokens.includes(country.token))

    // True once a country fetch has completed, so the panel can tell "not fetched yet" from
    // "fetched and genuinely empty".
    property bool countriesLoaded: false
    property bool countriesLoading: false

    property list<string> keys: []
    property bool keysLoaded: false

    // What the user last asked to connect to, so feedback can say "Connecting to Switzerland…"
    // instead of a bare spinner. Cleared on disconnect.
    property string requestedTarget: ""

    // Anything that is not "openvpn" means WireGuard, per plan §2. Compared this way on
    // purpose: a typo or a stale persisted value must not flip the default away from the
    // Suite's own default.
    readonly property bool wireGuardPreferred:
        Parse.vpnTypeArgument(Config.system.airvpn.preferredVpnType) === "wireguard"

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
        Config.system.airvpn.favoriteCountries = next;
    }

    // ---------------------------------------------------------------- async mutation
    Component {
        id: asyncProcessComp

        Process {
            id: internalProc

            property var resolve
            property var reject
            property string buffer: ""
            property string errorBuffer: ""

            // Bounded for the same reason CliRead is - a mutation is the one path that can
            // legitimately reach a credential prompt if the rc file was emptied between the
            // read and the click.
            readonly property int maxBytes: 65536

            environment: ({
                LANG: "C.UTF-8",
                LC_ALL: "C.UTF-8"
            })

            stdout: SplitParser {
                onRead: data => {
                    if (internalProc.buffer.length > internalProc.maxBytes)
                        return;
                    internalProc.buffer += data + "\n";
                }
            }

            stderr: SplitParser {
                onRead: data => {
                    if (internalProc.errorBuffer.length > internalProc.maxBytes)
                        return;
                    internalProc.errorBuffer += data + "\n";
                }
            }

            onExited: (exitCode, exitStatus) => {
                // A prompt in a mutation's output means the rc file lost its credentials
                // between the last read and this click. Report it as a credentials problem
                // rather than as a mysterious timeout.
                if (Parse.detectsCredentialPrompt(buffer + "\n" + errorBuffer))
                    reject("AirVPN credentials are not configured");
                else if (exitCode === 0)
                    resolve(buffer.trim());
                else if (exitCode === 124 || exitCode === 137)
                    reject("AirVPN command timed out");
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
    // Debounced so back-to-back callers (panel open, mutation completion, poll tick) coalesce
    // into one CLI burst.
    function refresh(): void {
        refreshDebouncer.restart();
    }

    function performRefresh(): void {
        // Deliberately NOT gated on isMutating: reading state while a connect is in flight is
        // exactly when the UI most needs fresh data.
        if (!root.available || !root.enabled || root.isReading)
            return;
        if (statusProc.running)
            return;

        // Re-read the rc file every refresh. It is the credentials signal, it is cheap, and
        // the user editing it is precisely how they log in - so a stale read would pin the
        // setup card open after a successful login.
        rcFile.reload();

        root.isReading = true;
        statusProc.run();

        // Countries are NOT fetched here. `--air-list` prints "Bluetit options successfully
        // reset" - it mutates daemon option state - so it must never run on a poll tick.
        // The panel calls ensureCountries() instead. findings.md §3.
    }

    function finishRead(): void {
        root.isReading = false;
    }

    // Called by the panel when the country list is actually needed. Fetched once; a poll never
    // triggers it. Uncredentialed browse is verified to work, so this is not gated on
    // credentialsConfigured - which is the whole reason the page is useful before login.
    function ensureCountries(): void {
        if (!root.available || !root.enabled)
            return;
        if (root.countriesLoaded || root.countriesLoading || countriesProc.running)
            return;
        // Never while a mutation is in flight: resetting Bluetit's staged options underneath
        // an in-progress connect is asking for a confusing failure.
        if (root.isMutating)
            return;

        root.countriesLoading = true;
        countriesProc.run();
    }

    // Explicit user-initiated re-fetch, e.g. a Refresh affordance. Same option-reset caveat,
    // which is why it is never automatic.
    function refreshCountries(): void {
        if (root.isMutating)
            return;
        root.countriesLoaded = false;
        root.ensureCountries();
    }

    // Device keys are a credentialed read and therefore one of the two prompt-loop hazards.
    // Guarded on credentialsConfigured, not merely on `available`.
    function ensureKeys(): void {
        if (!root.available || !root.enabled || !root.credentialsConfigured)
            return;
        if (root.keysLoaded || keysProc.running)
            return;
        keysProc.run();
    }

    // ---------------------------------------------------------------- country model
    // Reconcile by identity rather than clear-and-rebuild, so delegates keep their objects and
    // an expanded row does not collapse on every fetch.
    function syncCountries(entries): void {
        const rows = entries ?? [];
        const codes = rows.map(entry => entry.code);
        const current = root.countries;

        for (let i = current.length - 1; i >= 0; i--) {
            if (!codes.includes(current[i].code)) {
                const stale = current[i];
                current.splice(i, 1);
                stale.destroy();
            }
        }

        for (const entry of rows) {
            const existing = current.find(item => item.code === entry.code);
            if (existing) {
                // Live figures, so an existing row updates in place rather than being
                // destroyed and rebuilt.
                existing.name = entry.name;
                existing.servers = entry.servers;
                existing.users = entry.users;
                existing.load = entry.load;
            } else {
                current.push(countryComp.createObject(root, {
                    code: entry.code,
                    name: entry.name,
                    servers: entry.servers,
                    users: entry.users,
                    load: entry.load
                }));
            }
        }

        root.updateDerivedLists();
    }

    function updateDerivedLists(): void {
        root.sortedCountries = [...root.countries].sort((a, b) => a.name.localeCompare(b.name));
    }

    function countryForToken(token) {
        return root.countries.find(entry => entry.token === token) ?? null;
    }

    // ---------------------------------------------------------------- mutations
    // Returns false when the request was rejected, so callers (and VpnService) can tell
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
        if (/permission denied|access denied|not authorized|airvpn group/i.test(message)) {
            root.permissionDenied = true;
            root.lastError = "";
        } else {
            root.lastError = message;
        }
    }

    // target: "" for Bluetit's own choice, else an ISO code, a country name, or a continent
    // code - all three are valid --air-country patterns.
    //
    // The argv is built entirely in airvpn-parse.js so that --async and the network-lock
    // default are structurally guaranteed and harness-asserted, rather than remembered here.
    function connectTo(target = "", options = {}): bool {
        // Last line of defence, and the one that matters most: an unauthenticated
        // --air-connect prompts on stdin and loops. The panel hides connect affordances while
        // needsCredentials, but a status read can land before the rc read, so for a moment the
        // UI may still offer them.
        if (root.needsCredentials || root.permissionDenied || !root.daemonReachable)
            return false;

        const opts = options ?? {};
        const trimmed = String(target ?? "").trim();

        const argv = Parse.buildConnectArgv({
            country: trimmed,
            vpnType: opts.vpnType ?? Config.system.airvpn.preferredVpnType,
            key: opts.key ?? Config.system.airvpn.preferredKey,
            // Never implicitly on. The observed lock state is not used as the default, because
            // enabling the filter can drop Tailscale and SSH on this host - which is the only
            // remote access we have to it.
            networkLock: opts.networkLock === true
                || (opts.networkLock === undefined && Config.system.airvpn.networkLock === true)
        });

        if (!root.runMutation(root.withTimeout(argv, root.mutationTimeoutSecs)))
            return false;

        // Optimistic, corrected by the next status read. Applied unconditionally - including
        // when already connected - because switching country is a reconnect, and gating this
        // on "disconnected" would leave the UI showing the OLD location with no sign of
        // activity.
        root.requestedTarget = trimmed;
        root.state = "connecting";
        return true;
    }

    function disconnect(): bool {
        // Not gated on credentials: this is the safety valve. If a tunnel is somehow up, the
        // user must always be able to take it down. `--disconnect` acts on the running
        // session and has no reason to prompt.
        if (!root.runMutation(root.goldcrest(["--disconnect"], root.mutationTimeoutSecs)))
            return false;
        root.requestedTarget = "";
        root.state = "disconnecting";
        return true;
    }

    function reconnect(): bool {
        if (root.needsCredentials || !root.daemonReachable)
            return false;
        return root.runMutation(root.goldcrest(["--reconnect"], root.mutationTimeoutSecs));
    }

    // Network Lock is a CONNECT-TIME preference in v1, not a live mutation.
    //
    // `--network-lock on` applied to a running session installs a kill switch that can drop
    // Tailscale and SSH to Bostrom, and Bostrom is administered exclusively over those two.
    // A widget toggle that can sever its own remote access is not worth the convenience, so
    // the setting is stored and applied on the next connect, where the user is already
    // choosing to change the tunnel. The observed state is still displayed from status.
    function setNetworkLockPreference(value): void {
        Config.system.airvpn.networkLock = value === true;
    }

    function setPreferredVpnType(value): void {
        const normalized = Parse.vpnTypeArgument(value);
        Config.system.airvpn.preferredVpnType = normalized;
        // Reflect the choice immediately; the next status read remains authoritative for what
        // is actually running.
        if (!root.connected)
            root.technology = normalized === "openvpn" ? "OpenVPN" : "WireGuard";
    }

    function setPreferredKey(value): void {
        Config.system.airvpn.preferredKey = String(value ?? "");
    }

    // ---------------------------------------------------------------- run control file
    // The credentials signal. A file read cannot hang or flood, which is exactly why this and
    // not `--air-user-info` is authoritative. See SAFETY at the top.
    //
    // HOME-based rather than XDG_CONFIG_HOME-based on purpose: goldcrest itself reports
    // "Reading run control directives from file $HOME/.config/goldcrest.rc", so this must
    // mirror that path or the two would disagree about whether credentials exist. Using
    // Quickshell.env keeps it correct under lab/run-isolated.sh, which repoints HOME.
    readonly property string rcPath: Quickshell.env("HOME") + "/.config/goldcrest.rc"

    FileView {
        id: rcFile

        path: root.rcPath
        watchChanges: true
        // Absent is the normal first-run state, not an error worth logging every poll.
        printErrors: false

        onLoaded: root.ingestRunControl(rcFile.text())
        onFileChanged: rcFile.reload()

        // A missing or unreadable file means "not configured", which is a legitimate state
        // rather than a failure. 0600 is the documented mode, so an unreadable file would be
        // someone else's rc, and treating that as configured would invite the prompt loop.
        onLoadFailed: {
            root.credentialsConfigured = false;
            root.accountUser = "";
            root.hasDeviceKey = false;
        }
    }

    function ingestRunControl(text): void {
        const parsed = Parse.parseRunControl(text);
        root.credentialsConfigured = parsed.credentialsConfigured;
        root.accountUser = parsed.user;
        root.hasDeviceKey = parsed.hasKey;

        // Newly logged in: the credentialed reads that were refused until now become legal.
        if (parsed.credentialsConfigured)
            root.ensureKeys();
        else
            root.keysLoaded = false;
    }

    // ---------------------------------------------------------------- timers
    // Watchdogs. Both flags are latches that gate everything downstream: performRefresh
    // early-returns on isReading and runMutation rejects on isMutating, so a goldcrest that
    // never exits would freeze all state reads or make every button permanently dead for the
    // rest of the session. The timeout wrapper should always fire first; these are the
    // backstop for the case where it does not.
    Timer {
        id: readWatchdog
        interval: (root.readTimeoutSecs + 5) * 1000
        repeat: false
        running: root.isReading
        onTriggered: {
            root.isReading = false;
            root.lastError = "Timed out reading AirVPN state";
        }
    }

    Timer {
        id: mutationWatchdog
        interval: (root.mutationTimeoutSecs + 5) * 1000
        repeat: false
        running: root.isMutating
        onTriggered: {
            root.isMutating = false;
            root.lastError = "AirVPN command timed out";
            root.errorFromMutation = true;
            root.refresh();
        }
    }

    // A mutation error is preserved against the refresh it triggers, but not forever: without
    // a ceiling one failed connect would pin the error banner for the rest of the session even
    // after the tunnel recovered. Long enough for VpnService's 500 ms tick and for a human to
    // read it.
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

    // Visibility-gated, so a closed dashboard costs nothing. Keeps polling while connected or
    // transitioning so the UI does not go stale behind a closed dashboard mid-handoff.
    Timer {
        id: pollingTimer
        interval: Math.max(5, Config.system.airvpn.pollInterval) * 1000
        repeat: true
        running: root.available && root.enabled && !SuspendManager.isSuspending
            && (GlobalStates.dashboardOpen || GlobalStates.launcherOpen || GlobalStates.overviewOpen
                || root.connected || root.connecting || root.disconnecting)
        onTriggered: root.refresh()
    }

    // Tunnel state is routinely stale across resume. bluetit-suspend/bluetit-resume units are
    // enabled on Bostrom, so the daemon itself may have torn the tunnel down while asleep.
    property var suspendConnections: Connections {
        target: SuspendManager

        function onWakingUp() {
            if (root.available && root.enabled)
                root.refresh();
        }
    }

    // ---------------------------------------------------------------- processes
    // One read-command shape, declared once: run argv, accumulate both streams, parse once on
    // exit under Qt.callLater.
    //
    // maxBytes is a safety mechanism, not tidiness. See SAFETY at the top of this file: a
    // goldcrest that reaches its stdin prompt emits the prompt in an unbounded loop, and
    // without this ceiling cli.buffer grows at hundreds of MB per second.
    component CliRead: Process {
        id: cli

        property string buffer: ""
        property string errorBuffer: ""

        // 256 KiB. The largest legitimate read is the country table at a few KiB, so this is
        // ~50x headroom and still four orders of magnitude below the flood.
        readonly property int maxBytes: 262144
        property bool overflowed: false

        // Deferred via Qt.callLater by the emitter, so handlers may safely mutate lists -
        // required by modules/services/AGENTS.md.
        signal parsed(string output, string error, int code, bool overflowed)

        environment: ({
            LANG: "C.UTF-8",
            LC_ALL: "C.UTF-8"
        })

        function run(): void {
            cli.buffer = "";
            cli.errorBuffer = "";
            cli.overflowed = false;
            cli.running = true;
        }

        // Kills the child the moment the ceiling is breached. onExited still fires, so the
        // normal parse path reports it via the `overflowed` argument.
        function guard(): bool {
            if (cli.buffer.length + cli.errorBuffer.length <= cli.maxBytes)
                return true;
            if (!cli.overflowed) {
                cli.overflowed = true;
                cli.running = false;
            }
            return false;
        }

        stdout: SplitParser {
            onRead: data => {
                if (!cli.guard())
                    return;
                cli.buffer += data + "\n";
            }
        }

        stderr: SplitParser {
            onRead: data => {
                if (!cli.guard())
                    return;
                cli.errorBuffer += data + "\n";
            }
        }

        onExited: (exitCode, exitStatus) => {
            // Snapshot then clear, so the deferred closure reads a stable value.
            const output = cli.buffer;
            const error = cli.errorBuffer.trim();
            const overflowed = cli.overflowed;
            cli.buffer = "";
            cli.errorBuffer = "";
            Qt.callLater(() => cli.parsed(output, error, exitCode, overflowed));
        }
    }

    Process {
        id: availabilityProbe
        command: ["which", "goldcrest"]

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
        // Verified safe without credentials, and verified NOT to reset Bluetit's options -
        // which is what makes it the only command allowed on a poll tick. findings.md §3.
        command: root.goldcrest(["--bluetit-status"], root.readTimeoutSecs)

        onParsed: (output, error, code, overflowed) => {
            // An overflow means the prompt loop was hit despite every guard above. Report it
            // as a credentials problem, which is the only thing that causes it, and do not
            // parse the flood.
            if (overflowed) {
                root.state = "needsCredentials";
                root.credentialsConfigured = false;
                root.lastError = "";
                root.finishRead();
                return;
            }

            const parsed = Parse.parseBluetitStatus(error + "\n" + output, code);

            root.daemonReachable = parsed.daemonReachable;
            root.permissionDenied = !parsed.daemonReachable
                && /permission denied|access denied|not authorized|airvpn group/i
                    .test(error + "\n" + output);

            if (parsed.networkLockKnown) {
                root.networkLock = parsed.networkLock;
                root.networkLockKnown = true;
            }

            if (parsed.needsCredentials) {
                // The rc file is authoritative, but a prompting status read is proof.
                root.credentialsConfigured = false;
                root.state = "needsCredentials";
                root.finishRead();
                return;
            }

            if (!parsed.daemonReachable) {
                root.state = "error";
                root.lastError = root.permissionDenied
                    ? "" : "The AirVPN Bluetit daemon is not reachable";
                root.finishRead();
                return;
            }

            root.state = parsed.state;
            root.country = parsed.country;
            root.server = parsed.server;
            if (parsed.technology !== "")
                root.technology = parsed.technology;

            // Only clear a READ-originated error. A failed mutation triggers an immediate
            // refresh, and clearing here unconditionally would erase the reason ~200 ms later,
            // before VpnService's 500 ms handoff tick could observe it.
            if (!root.errorFromMutation)
                root.lastError = "";

            // Never leave an unrecognized status as a bare "Error" with no detail. This is the
            // one place that knows what the CLI actually said - and the phrasing it captures is
            // what a future connected-state fixture will be built from.
            if (parsed.state === "error" && parsed.unknownStatus !== undefined) {
                root.lastError = "Unexpected AirVPN status: " + parsed.unknownStatus;
                root.errorFromMutation = false;
            }

            root.finishRead();
        }
    }

    CliRead {
        id: countriesProc
        // Uncredentialed browse is verified to work (findings.md §2), which is what lets the
        // country list populate before login. Note this command DOES reset Bluetit's staged
        // options, so it is fetched on demand only - never on a poll.
        command: root.goldcrest(["--air-list", "--air-country", "all"], root.readTimeoutSecs)

        onParsed: (output, error, code, overflowed) => {
            root.countriesLoading = false;

            if (overflowed)
                return;

            const parsed = Parse.parseCountryList(error + "\n" + output);

            if (parsed.needsCredentials) {
                // Should be unreachable - browse does not need credentials - but if a future
                // Suite version changes that, fail closed rather than looping.
                root.credentialsConfigured = false;
                return;
            }

            if (parsed.error !== "" || parsed.countries.length === 0)
                return;

            root.syncCountries(parsed.countries);
            root.countriesLoaded = true;
        }
    }

    CliRead {
        id: keysProc
        // CREDENTIALED. Only ever started via ensureKeys(), which requires
        // credentialsConfigured. Never call keysProc.run() directly.
        command: root.goldcrest(["--air-key-list"], root.readTimeoutSecs)

        onParsed: (output, error, code, overflowed) => {
            if (overflowed) {
                root.credentialsConfigured = false;
                return;
            }

            const parsed = Parse.parseKeyList(error + "\n" + output);
            if (parsed.needsCredentials) {
                root.credentialsConfigured = false;
                return;
            }
            if (code !== 0)
                return;

            root.keys = parsed.keys;
            root.keysLoaded = true;
        }
    }

    Component {
        id: countryComp

        AirVpnCountry {}
    }

    onEnabledChanged: {
        if (root.enabled && root.available)
            root.refresh();
    }

    Component.onCompleted: availabilityProbe.running = true
}
