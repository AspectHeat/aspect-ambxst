pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.theme

Singleton {
    id: root

    property bool available: false
    readonly property bool enabled: Config.system.tailscale.enabled
    property string backendState: "NoState"
    readonly property bool connected: backendState === "Running"
    readonly property bool needsLogin: backendState === "NeedsLogin"
    property bool isUpdating: false
    property bool operatorMissing: false
    property string lastError: ""

    property string selfIPv4: ""
    property string selfIPv6: ""
    property string selfHostName: ""
    property string selfDNSName: ""
    property string magicDNSSuffix: ""

    property string exitNodeId: ""
    property string exitNodeName: ""
    property bool allowLanAccess: false
    property bool acceptRoutes: false
    property bool acceptDNS: false
    property bool shieldsUp: false

    readonly property list<TailscalePeer> peers: []
    property list<var> friendlyPeers: []
    property list<var> exitNodeOptions: []
    property list<var> profiles: []
    readonly property int peerCount: peers.length
    readonly property int onlineCount: friendlyPeers.filter(peer => peer.online).length

    property int refreshPartsRemaining: 0
    property bool watcherFailed: false

    signal copied(string text)

    Component {
        id: asyncProcessComp

        Process {
            id: internalProc

            property var resolve
            property var reject
            property string buffer: ""
            property string errorBuffer: ""

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
                    reject(errorBuffer.trim() || `Process exited with code ${exitCode}`);
                destroy();
            }
        }
    }

    function runAsync(command, environment = {}) {
        return new Promise((resolve, reject) => {
            const proc = asyncProcessComp.createObject(root, {
                command: command,
                environment: environment,
                resolve: resolve,
                reject: reject
            });
            proc.running = true;
        });
    }

    function refresh(): void {
        refreshDebouncer.restart();
    }

    function performRefresh(): void {
        if (!available || !enabled || isUpdating || statusProc.running || prefsProc.running)
            return;

        isUpdating = true;
        refreshPartsRemaining = 2;
        statusProc.run();
        prefsProc.run();
    }

    function finishRefreshPart(): void {
        refreshPartsRemaining = Math.max(0, refreshPartsRemaining - 1);
        if (refreshPartsRemaining === 0)
            isUpdating = false;
    }

    function updateDerivedLists(): void {
        friendlyPeers = [...peers].sort((a, b) => {
            if (a.online !== b.online)
                return a.online ? -1 : 1;
            if (a.exitNodeOption !== b.exitNodeOption)
                return a.exitNodeOption ? -1 : 1;
            return a.displayName.localeCompare(b.displayName);
        });
        exitNodeOptions = friendlyPeers.filter(peer => peer.exitNodeOption);

        const activePeer = peers.find(peer => peer.nodeId === exitNodeId || peer.isExitNode);
        exitNodeName = activePeer ? activePeer.displayName : "";
    }

    function syncPeers(peerData): void {
        const incoming = [];
        const peerMap = peerData ?? {};
        const keys = Object.keys(peerMap);

        for (let i = 0; i < keys.length; i++) {
            const data = peerMap[keys[i]];
            if (data && data.ID)
                incoming.push(data);
        }

        const current = root.peers;
        for (let i = current.length - 1; i >= 0; i--) {
            const peer = current[i];
            if (!incoming.find(data => data.ID === peer.nodeId)) {
                current.splice(i, 1);
                peer.destroy();
            }
        }

        for (let i = 0; i < incoming.length; i++) {
            const data = incoming[i];
            const existing = current.find(peer => peer.nodeId === data.ID);
            if (existing) {
                existing.lastIpcObject = data;
            } else {
                current.push(peerComp.createObject(root, {
                    lastIpcObject: data
                }));
            }
        }

        updateDerivedLists();
    }

    function handleMutationError(error): void {
        const message = String(error ?? "").trim();
        if (/access denied/i.test(message)) {
            operatorMissing = true;
            lastError = "";
        } else {
            lastError = message;
        }
    }

    function runMutation(command): void {
        if (!available || !enabled || isUpdating)
            return;

        isUpdating = true;
        lastError = "";
        runAsync(command).then(() => {
            operatorMissing = false;
            isUpdating = false;
            refresh();
            refreshProfiles();
        }).catch(error => {
            handleMutationError(error);
            isUpdating = false;
            refresh();
        });
    }

    function up(): void {
        if (needsLogin) {
            login();
            return;
        }
        runMutation(["tailscale", "up"]);
    }

    function down(): void {
        runMutation(["tailscale", "down"]);
    }

    function toggle(): void {
        if (operatorMissing || isUpdating)
            return;
        if (connected)
            down();
        else
            up();
    }

    function login(): void {
        if (!available || !enabled)
            return;
        Quickshell.execDetached(["tailscale", "login"]);
    }

    function setExitNode(nodeIdOrIp): void {
        if (!nodeIdOrIp)
            return;
        runMutation(["tailscale", "set", "--exit-node=" + nodeIdOrIp]);
    }

    function clearExitNode(): void {
        runMutation(["tailscale", "set", "--exit-node="]);
    }

    function setAllowLanAccess(allowed): void {
        runMutation(["tailscale", "set", "--exit-node-allow-lan-access=" + (allowed ? "true" : "false")]);
    }

    function switchProfile(idOrName): void {
        if (!idOrName)
            return;
        runMutation(["tailscale", "switch", idOrName]);
    }

    function refreshProfiles(): void {
        if (!available || !enabled || profilesProc.running)
            return;
        profilesProc.run();
    }

    function copyText(text): void {
        if (!text || text.length === 0)
            return;
        copyProc.command = ["wl-copy", "--", text];
        copyProc.running = true;
        copied(text);
    }

    function openAdminConsole(): void {
        const url = Config.system.tailscale.adminConsoleUrl;
        if (url)
            Quickshell.execDetached(["xdg-open", url]);
    }

    function peerIcon(peer): string {
        const os = (peer?.os ?? "").toLowerCase();
        if (os.includes("windows"))
            return Icons.windowsLogo;
        if (os.includes("android") || os.includes("ios"))
            return Icons.phone;
        return Icons.cube;
    }

    function shortDnsName(dnsName): string {
        let name = String(dnsName ?? "").replace(/\.$/, "");
        const suffix = String(magicDNSSuffix ?? "").replace(/^\./, "").replace(/\.$/, "");
        if (suffix && name.toLowerCase().endsWith("." + suffix.toLowerCase()))
            name = name.slice(0, -(suffix.length + 1));
        return name;
    }

    Timer {
        id: refreshDebouncer
        interval: 200
        repeat: false
        onTriggered: root.performRefresh()
    }

    Timer {
        id: fallbackTimer
        interval: Math.max(5, Config.system.tailscale.pollInterval) * 1000
        repeat: true
        running: root.available && root.enabled && !watcher.running
        onTriggered: root.refresh()
    }

    Process {
        id: availabilityProbe
        command: ["which", "tailscale"]

        onExited: (exitCode, exitStatus) => {
            root.available = exitCode === 0;
            if (root.available && root.enabled) {
                watcher.running = true;
                root.refresh();
            }
        }
    }

    Process {
        id: watcher
        command: ["tailscale", "debug", "watch-ipn"]

        stdout: SplitParser {
            onRead: root.refresh()
        }

        onExited: (exitCode, exitStatus) => {
            if (root.available && root.enabled)
                root.watcherFailed = true;
        }
    }

    Process {
        id: statusProc

        property string buffer: ""
        property string errorBuffer: ""

        command: ["tailscale", "status", "--json"]

        function run(): void {
            buffer = "";
            errorBuffer = "";
            running = true;
        }

        stdout: SplitParser {
            onRead: data => statusProc.buffer += data + "\n"
        }

        stderr: SplitParser {
            onRead: data => statusProc.errorBuffer += data + "\n"
        }

        onExited: (exitCode, exitStatus) => {
            const output = buffer;
            const error = errorBuffer.trim();
            buffer = "";
            errorBuffer = "";

            Qt.callLater(() => {
                if (exitCode === 0) {
                    try {
                        const status = JSON.parse(output);
                        const self = status.Self ?? {};
                        const addresses = self.TailscaleIPs ?? status.TailscaleIPs ?? [];

                        root.backendState = status.BackendState ?? "NoState";
                        root.magicDNSSuffix = status.MagicDNSSuffix ?? "";
                        root.selfHostName = self.HostName ?? "";
                        root.selfDNSName = String(self.DNSName ?? "").replace(/\.$/, "");
                        root.selfIPv4 = addresses.find(address => !address.includes(":")) ?? "";
                        root.selfIPv6 = addresses.find(address => address.includes(":")) ?? "";
                        root.syncPeers(status.Peer ?? {});
                        root.lastError = "";
                    } catch (error) {
                        root.lastError = "Could not read Tailscale status";
                    }
                } else if (error) {
                    root.lastError = error;
                }
                root.finishRefreshPart();
            });
        }
    }

    Process {
        id: prefsProc

        property string buffer: ""
        property string errorBuffer: ""

        command: ["tailscale", "debug", "prefs"]

        function run(): void {
            buffer = "";
            errorBuffer = "";
            running = true;
        }

        stdout: SplitParser {
            onRead: data => prefsProc.buffer += data + "\n"
        }

        stderr: SplitParser {
            onRead: data => prefsProc.errorBuffer += data + "\n"
        }

        onExited: (exitCode, exitStatus) => {
            const output = buffer;
            const error = errorBuffer.trim();
            buffer = "";
            errorBuffer = "";

            Qt.callLater(() => {
                if (exitCode === 0) {
                    try {
                        const prefs = JSON.parse(output);
                        root.exitNodeId = prefs.ExitNodeID ?? "";
                        root.allowLanAccess = prefs.ExitNodeAllowLANAccess ?? false;
                        root.acceptRoutes = prefs.RouteAll ?? false;
                        root.acceptDNS = prefs.CorpDNS ?? false;
                        root.shieldsUp = prefs.ShieldsUp ?? false;
                        root.updateDerivedLists();
                    } catch (error) {
                        root.lastError = "Could not read Tailscale preferences";
                    }
                } else if (error) {
                    root.lastError = error;
                }
                root.finishRefreshPart();
            });
        }
    }

    Process {
        id: profilesProc

        property string buffer: ""
        property string errorBuffer: ""

        command: ["tailscale", "switch", "--list"]
        environment: ({
            LANG: "C.UTF-8",
            LC_ALL: "C.UTF-8"
        })

        function run(): void {
            buffer = "";
            errorBuffer = "";
            running = true;
        }

        stdout: SplitParser {
            onRead: data => profilesProc.buffer += data + "\n"
        }

        stderr: SplitParser {
            onRead: data => profilesProc.errorBuffer += data + "\n"
        }

        onExited: (exitCode, exitStatus) => {
            const output = buffer.trim();
            const error = errorBuffer.trim();
            buffer = "";
            errorBuffer = "";

            Qt.callLater(() => {
                if (exitCode !== 0) {
                    root.profiles = [];
                    if (/access denied/i.test(error))
                        root.operatorMissing = true;
                    return;
                }

                const parsed = [];
                const lines = output.split("\n");
                for (let i = 1; i < lines.length; i++) {
                    const fields = lines[i].trim().split(/\s+/);
                    if (fields.length < 3)
                        continue;

                    let tailnet = fields.slice(2).join(" ");
                    const active = tailnet.endsWith("*");
                    tailnet = tailnet.replace(/\*$/, "");
                    parsed.push({
                        id: fields[0],
                        name: tailnet || fields[0],
                        account: fields[1],
                        tailnet: tailnet,
                        active: active
                    });
                }
                root.operatorMissing = false;
                root.profiles = parsed;
            });
        }
    }

    Process {
        id: copyProc
        command: ["wl-copy", "--", ""]
    }

    Component {
        id: peerComp
        TailscalePeer {}
    }

    onEnabledChanged: {
        if (!available)
            return;
        if (enabled) {
            if (!watcher.running && !watcherFailed)
                watcher.running = true;
            refresh();
        } else {
            watcher.running = false;
        }
    }

    Component.onCompleted: availabilityProbe.running = true
}
