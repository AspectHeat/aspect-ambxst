pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.globals

Singleton {
    id: root

    // "connected" | "connecting" | "disconnected"
    property string status: "disconnected"
    property string city: ""
    property string country: ""
    property string server: ""
    property string ip: ""

    readonly property bool connected: status === "connected"
    readonly property bool connecting: status === "connecting"

    property list<string> countries: []
    property bool loadingCountries: false
    property bool isUpdating: false

    Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: root.updateStatus()
    }

    Component.onCompleted: updateStatus()

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

    function parseStatus(output) {
        const lines = output.split('\n');
        const data = {};
        for (const line of lines) {
            const idx = line.indexOf(': ');
            if (idx !== -1) {
                data[line.substring(0, idx).trim().toLowerCase()] = line.substring(idx + 2).trim();
            }
        }
        const s = (data['status'] || '').toLowerCase();
        if (s === 'connected') {
            root.status = 'connected';
            root.city = data['city'] || '';
            root.country = data['country'] || '';
            root.server = data['hostname'] || '';
            root.ip = data['ip'] || '';
        } else if (s === 'connecting') {
            root.status = 'connecting';
        } else {
            root.status = 'disconnected';
            root.city = '';
            root.country = '';
            root.server = '';
            root.ip = '';
        }
    }

    function updateStatus() {
        runAsync(["nordvpn", "status"]).then(output => {
            parseStatus(output);
        }).catch(() => {
            root.status = 'disconnected';
        });
    }

    function connect() {
        if (isUpdating) return;
        isUpdating = true;
        root.status = 'connecting';
        runAsync(["nordvpn", "connect"]).then(() => {
            updateStatus();
            isUpdating = false;
        }).catch(() => {
            updateStatus();
            isUpdating = false;
        });
    }

    function connectToCountry(countryCode) {
        if (isUpdating) return;
        isUpdating = true;
        root.status = 'connecting';
        runAsync(["nordvpn", "connect", countryCode]).then(() => {
            updateStatus();
            isUpdating = false;
        }).catch(() => {
            updateStatus();
            isUpdating = false;
        });
    }

    function disconnect() {
        if (isUpdating) return;
        isUpdating = true;
        runAsync(["nordvpn", "disconnect"]).then(() => {
            updateStatus();
            isUpdating = false;
        }).catch(() => {
            updateStatus();
            isUpdating = false;
        });
    }

    function toggle() {
        if (connected || connecting) disconnect();
        else connect();
    }

    function fetchCountries() {
        if (loadingCountries || countries.length > 0) return;
        loadingCountries = true;
        runAsync(["nordvpn", "countries"]).then(output => {
            // nordvpn outputs countries in tab/space-separated columns;
            // multi-word countries use underscores (e.g. United_States)
            const items = output.split(/[\s,]+/)
                .map(c => c.trim())
                .filter(c => c.length > 1 && /^[A-Z]/.test(c))
                .sort();
            root.countries = items;
            loadingCountries = false;
        }).catch(() => {
            loadingCountries = false;
        });
    }
}
