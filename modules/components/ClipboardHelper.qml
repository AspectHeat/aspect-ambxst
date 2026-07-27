import QtQuick
import Quickshell.Io

QtObject {
    id: root

    readonly property string ioScript: Qt.resolvedUrl("../../scripts/ai_io.py").toString().replace("file://", "")

    function copyText(text) {
        copyProcess.content = text || "";
        copyProcess.running = true;
    }

    property Process copyProcess: Process {
        property string content: ""

        stdinEnabled: true
        command: ["python3", root.ioScript, "clipboard"]

        onStarted: {
            write(content);
            stdinEnabled = false;
        }

        onExited: {
            stdinEnabled = true;
        }
    }
}
