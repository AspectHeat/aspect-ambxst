pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.config

Singleton {
    id: root

    property bool available: false
    readonly property bool enabled: Config.system.nordvpn.enabled
    property string state: "unavailable"
    readonly property bool connected: state === "connected"
    readonly property bool connecting: state === "connecting"
    readonly property bool needsLogin: state === "loggedOut"
    property bool isUpdating: false
    property string lastError: ""
    property string country: ""
    property string city: ""
    property string server: ""
    property string technology: ""
    property string protocol: ""
    property string transfer: ""
    property list<var> countries: []
    property list<var> recommendedServers: []
    property bool recommendationsUpdating: false
    property string recommendationsError: ""
    property string recommendationsUpdatedAt: ""

    readonly property var countryCodes: ({
        "Albania": "AL", "Argentina": "AR", "Australia": "AU", "Austria": "AT",
        "Belgium": "BE", "Bosnia And Herzegovina": "BA", "Brazil": "BR", "Bulgaria": "BG",
        "Canada": "CA", "Chile": "CL", "Colombia": "CO", "Costa Rica": "CR",
        "Croatia": "HR", "Cyprus": "CY", "Czech Republic": "CZ", "Denmark": "DK",
        "Estonia": "EE", "Finland": "FI", "France": "FR", "Georgia": "GE",
        "Germany": "DE", "Greece": "GR", "Hong Kong": "HK", "Hungary": "HU",
        "Iceland": "IS", "India": "IN", "Indonesia": "ID", "Ireland": "IE",
        "Israel": "IL", "Italy": "IT", "Japan": "JP", "Latvia": "LV",
        "Lithuania": "LT", "Luxembourg": "LU", "Malaysia": "MY", "Mexico": "MX",
        "Moldova": "MD", "Netherlands": "NL", "New Zealand": "NZ", "North Macedonia": "MK",
        "Norway": "NO", "Poland": "PL", "Portugal": "PT", "Romania": "RO",
        "Serbia": "RS", "Singapore": "SG", "Slovakia": "SK", "Slovenia": "SI",
        "South Africa": "ZA", "South Korea": "KR", "Spain": "ES", "Sweden": "SE",
        "Switzerland": "CH", "Taiwan": "TW", "Thailand": "TH", "Turkey": "TR",
        "Ukraine": "UA", "United Arab Emirates": "AE", "United Kingdom": "GB",
        "United States": "US", "Vietnam": "VN"
    })

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

            onExited: exitCode => {
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
                environment: {
                    LANG: "C.UTF-8",
                    LC_ALL: "C.UTF-8"
                },
                resolve: resolve,
                reject: reject
            });
            proc.running = true;
        });
    }

    function normalizedCountry(value): string {
        return String(value ?? "").replace(/_/g, " ").trim().replace(/\b\w/g, match => match.toUpperCase());
    }

    function flagForCode(code): string {
        const normalized = String(code ?? "").toUpperCase();
        if (!/^[A-Z]{2}$/.test(normalized))
            return "🌐";
        return String.fromCodePoint(...[...normalized].map(character => 127397 + character.charCodeAt(0)));
    }

    function parseStatus(output): void {
        const values = {};
        String(output ?? "").split("\n").forEach(line => {
            const separator = line.indexOf(":");
            if (separator < 0)
                return;
            const key = line.slice(0, separator).trim().toLowerCase();
            values[key] = line.slice(separator + 1).trim();
        });

        const rawStatus = String(values.status ?? "").toLowerCase();
        if (rawStatus === "connected")
            state = "connected";
        else if (rawStatus === "connecting")
            state = "connecting";
        else
            state = "disconnected";

        country = normalizedCountry(values.country);
        city = normalizedCountry(values.city);
        server = values.hostname ?? values.server ?? "";
        technology = values.technology ?? "";
        protocol = values.protocol ?? "";
        transfer = values.transfer ?? "";
    }

    function parseCountries(output): void {
        try {
            const data = JSON.parse(String(output ?? ""));
            if (!Array.isArray(data))
                throw new Error("Unexpected response");
            countries = data.map(countryData => ({
                name: countryData.name ?? "",
                code: countryData.code ?? "",
                flag: flagForCode(countryData.code ?? ""),
                cliValue: String(countryData.name ?? "").replace(/ /g, "_"),
                serverCount: Number(countryData.serverCount ?? 0),
                cityCount: (countryData.cities ?? []).length
            })).filter(countryData => countryData.name !== "")
                .sort((a, b) => a.name.localeCompare(b.name));
        } catch (error) {
            countries = [];
        }
    }

    function countryCodeForName(countryName): string {
        const liveCountry = countries.find(countryData => countryData.name === countryName);
        return liveCountry?.code ?? countryCodes[countryName] ?? "";
    }

    function parseRecommendations(output): void {
        try {
            const data = JSON.parse(String(output ?? ""));
            if (!Array.isArray(data))
                throw new Error("Unexpected response");

            recommendedServers = data.map(serverData => {
                const location = serverData.locations?.[0] ?? {};
                const countryData = location.country ?? {};
                const groupIds = (serverData.groups ?? []).map(group => group.identifier ?? "");
                const technologyIds = (serverData.technologies ?? [])
                    .filter(technology => technology.pivot?.status === "online")
                    .map(technology => technology.identifier ?? "");
                return {
                    id: serverData.id ?? 0,
                    name: serverData.name ?? serverData.hostname ?? "NordVPN server",
                    hostname: serverData.hostname ?? "",
                    serverKey: String(serverData.hostname ?? "").split(".")[0],
                    load: Math.max(0, Math.min(100, Number(serverData.load ?? 0))),
                    status: serverData.status ?? "",
                    country: countryData.name ?? "",
                    countryCode: countryData.code ?? "",
                    city: countryData.city?.name ?? "",
                    subdivision: countryData.subdivision?.name ?? "",
                    flag: flagForCode(countryData.code ?? ""),
                    supportsP2p: groupIds.includes("legacy_p2p"),
                    supportsStandard: groupIds.includes("legacy_standard"),
                    supportsNordLynx: technologyIds.includes("wireguard_udp")
                };
            }).filter(server => server.hostname !== "" && server.status === "online");
            recommendationsError = "";
            recommendationsUpdatedAt = Qt.formatTime(new Date(), "h:mm AP");
        } catch (error) {
            recommendationsError = "Could not read NordVPN's live server feed";
        }
    }

    function refresh(): void {
        if (!available || !enabled || statusProc.running)
            return;
        statusProc.run();
        if (countries.length === 0 && !countriesProc.running)
            countriesProc.run();
        refreshRecommendations();
    }

    function refreshCountries(): void {
        if (available && enabled && !countriesProc.running)
            countriesProc.run();
    }

    function refreshRecommendations(): void {
        if (available && enabled && !recommendationsProc.running)
            recommendationsProc.run();
    }

    function runMutation(command): void {
        if (!available || !enabled || isUpdating)
            return;

        isUpdating = true;
        lastError = "";
        runAsync(command).then(() => {
            mutationRefreshTimer.restart();
        }).catch(error => {
            lastError = String(error ?? "");
            isUpdating = false;
            refresh();
        });
    }

    function connectTo(countryName = "", p2p = false): void {
        const command = ["nordvpn", "connect"];
        if (p2p)
            command.push("--group", "p2p");
        if (countryName)
            command.push(String(countryName).replace(/ /g, "_"));
        runMutation(command);
    }

    function disconnect(): void {
        runMutation(["nordvpn", "disconnect"]);
    }

    function connectToServer(serverKey): void {
        if (!serverKey)
            return;
        runMutation(["nordvpn", "connect", serverKey]);
    }

    function toggle(): void {
        if (connected)
            disconnect();
        else
            connectTo(Config.system.nordvpn.preferredCountry, Config.system.nordvpn.preferredMode === "p2p");
    }

    function login(): void {
        if (available && enabled)
            Quickshell.execDetached(["nordvpn", "login"]);
    }

    function setTechnology(value): void {
        if (!["NordLynx", "OpenVPN"].includes(value))
            return;
        runMutation(["nordvpn", "set", "technology", value]);
    }

    Timer {
        id: pollingTimer
        interval: Math.max(5, Config.system.nordvpn.pollInterval) * 1000
        repeat: true
        running: root.available && root.enabled
        onTriggered: root.refresh()
    }

    Timer {
        id: recommendationsTimer
        interval: 60000
        repeat: true
        running: root.available && root.enabled
        onTriggered: root.refreshRecommendations()
    }

    Timer {
        id: mutationRefreshTimer
        interval: 900
        repeat: false
        onTriggered: {
            root.isUpdating = false;
            root.refresh();
        }
    }

    Process {
        id: availabilityProbe
        command: ["which", "nordvpn"]

        onExited: exitCode => {
            root.available = exitCode === 0;
            root.state = root.available ? "disconnected" : "unavailable";
            if (root.available && root.enabled)
                root.refresh();
        }
    }

    Process {
        id: statusProc

        property string buffer: ""
        property string errorBuffer: ""

        command: ["nordvpn", "status"]
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
            onRead: data => statusProc.buffer += data + "\n"
        }

        stderr: SplitParser {
            onRead: data => statusProc.errorBuffer += data + "\n"
        }

        onExited: exitCode => {
            const output = buffer.trim();
            const error = errorBuffer.trim();
            buffer = "";
            errorBuffer = "";

            Qt.callLater(() => {
                if (exitCode === 0) {
                    root.parseStatus(output);
                    root.lastError = "";
                } else if (/not logged in|log in/i.test(error + output)) {
                    root.state = "loggedOut";
                    root.lastError = "";
                } else {
                    root.state = "error";
                    root.lastError = error || output || "Could not read NordVPN status";
                }
            });
        }
    }

    Process {
        id: countriesProc

        property string buffer: ""
        property string errorBuffer: ""

        command: [
            "curl",
            "-fsS",
            "--max-time",
            "10",
            "--header",
            "Accept: application/json",
            "https://api.nordvpn.com/v1/servers/countries"
        ]

        function run(): void {
            buffer = "";
            errorBuffer = "";
            running = true;
        }

        stdout: SplitParser {
            onRead: data => countriesProc.buffer += data + "\n"
        }

        stderr: SplitParser {
            onRead: data => countriesProc.errorBuffer += data + "\n"
        }

        onExited: exitCode => {
            const output = buffer.trim();
            buffer = "";
            errorBuffer = "";
            if (exitCode === 0)
                Qt.callLater(() => root.parseCountries(output));
        }
    }

    Process {
        id: recommendationsProc

        property string buffer: ""
        property string errorBuffer: ""

        command: [
            "curl",
            "-fsS",
            "--max-time",
            "10",
            "--header",
            "Accept: application/json",
            "https://api.nordvpn.com/v1/servers/recommendations?limit=32"
        ]

        function run(): void {
            buffer = "";
            errorBuffer = "";
            root.recommendationsUpdating = true;
            running = true;
        }

        stdout: SplitParser {
            onRead: data => recommendationsProc.buffer += data + "\n"
        }

        stderr: SplitParser {
            onRead: data => recommendationsProc.errorBuffer += data + "\n"
        }

        onExited: exitCode => {
            const output = buffer.trim();
            const error = errorBuffer.trim();
            buffer = "";
            errorBuffer = "";
            Qt.callLater(() => {
                root.recommendationsUpdating = false;
                if (exitCode === 0)
                    root.parseRecommendations(output);
                else
                    root.recommendationsError = error || "NordVPN's live server feed is unavailable";
            });
        }
    }

    onEnabledChanged: {
        if (enabled && available)
            refresh();
    }

    Component.onCompleted: availabilityProbe.running = true
}
