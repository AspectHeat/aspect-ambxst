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
        const raw = String(output ?? "").replace(/^countries\s*:\s*/i, "");
        let names = raw.split(/[,\n]/).map(value => normalizedCountry(value)).filter(value => value !== "");
        if (names.length <= 1)
            names = raw.split(/\s{2,}/).map(value => normalizedCountry(value)).filter(value => value !== "");

        const unique = [...new Set(names)];
        countries = unique.map(name => {
            const code = countryCodes[name] ?? "";
            return {
                name: name,
                code: code,
                flag: flagForCode(code),
                cliValue: name.replace(/ /g, "_")
            };
        }).sort((a, b) => a.name.localeCompare(b.name));
    }

    function refresh(): void {
        if (!available || !enabled || statusProc.running)
            return;
        statusProc.run();
        if (countries.length === 0 && !countriesProc.running)
            countriesProc.run();
    }

    function refreshCountries(): void {
        if (available && enabled && !countriesProc.running)
            countriesProc.run();
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

        command: ["nordvpn", "countries"]
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

    onEnabledChanged: {
        if (enabled && available)
            refresh();
    }

    Component.onCompleted: availabilityProbe.running = true
}
