pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Airplane mode toggle. All the real work (rfkill block/unblock, remembering
// which radios were live before blocking) lives in the ambxst-airplane script
// so the keybind and this tile share one source of truth.
Singleton {
    id: root

    property bool active: false
    property bool busy: false

    Process {
        id: statusProcess
        running: true
        command: ["ambxst-airplane", "status"]
        stdout: SplitParser {
            onRead: data => {
                root.active = data.trim() === "on";
            }
        }
    }

    Process {
        id: toggleProcess
        running: false
        command: ["ambxst-airplane", "toggle"]
        onExited: code => {
            if (code !== 0)
                console.warn("AirplaneService: toggle failed with code", code);
            root.busy = false;
            root.refresh();
        }
    }

    function refresh(): void {
        if (!statusProcess.running)
            statusProcess.running = true;
    }

    function toggle(): void {
        if (busy)
            return;
        busy = true;
        toggleProcess.running = true;
    }

    // rfkill state can also change from the hardware key or the wifi/bluetooth
    // tiles, so poll rather than trusting our own last write.
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
