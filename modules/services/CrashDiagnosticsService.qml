pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

Singleton {
    id: root

    readonly property string integrationScript: Quickshell.shellDir + "/scripts/agent_integration.py"
    readonly property string diagnosisScript: Quickshell.shellDir + "/scripts/agent_crash.py"

    property bool available: false
    property bool installed: false
    property bool enabled: false
    property bool running: false
    property bool skillsInstalled: false
    property bool isolated: false
    property bool loading: false
    property string errorText: ""

    function applyStatus(content) {
        try {
            const status = JSON.parse(String(content || "{}"));
            root.available = status.available === true;
            root.installed = status.installed === true;
            root.enabled = status.enabled === true;
            root.running = status.running === true;
            root.skillsInstalled = status.skillsInstalled === true;
            root.isolated = status.isolated === true;
            root.errorText = "";
        } catch (error) {
            root.errorText = "Crash integration returned an unreadable response.";
        }
    }

    function refreshStatus() {
        if (statusProcess.running || mutationProcess.running)
            return;
        statusProcess.command = ["python3", root.integrationScript, "status"];
        statusProcess.running = true;
    }

    function install() {
        if (mutationProcess.running)
            return;
        root.loading = true;
        root.errorText = "";
        mutationProcess.command = ["python3", root.integrationScript, "install"];
        mutationProcess.running = true;
    }

    function setCaptureEnabled(value) {
        if (mutationProcess.running || !root.installed)
            return;
        root.loading = true;
        root.errorText = "";
        mutationProcess.command = ["python3", root.integrationScript, "toggle", value ? "on" : "off"];
        mutationProcess.running = true;
    }

    function notifyCrash(pid, processName, executable, signalName, happenedAt) {
        const crashPid = String(pid || "");
        const name = String(processName || "unknown");
        const exe = String(executable || "unknown");
        const signal = String(signalName || "unknown");
        const timestamp = String(happenedAt || "unknown");
        const provider = AgentUsageService.defaultAgentId;
        if (!/^\d+$/.test(crashPid) || provider === "")
            return;

        Notifications.notifyInternal({
            appName: "Ambxst Crash Capture",
            appIcon: "dialog-error",
            summary: "Process crashed: " + name,
            body: signal + " · PID " + crashPid + " · Diagnose with your default agent",
            urgency: NotificationUrgency.Critical,
            historyPriority: 100,
            expireTimeout: 12000,
            actions: [{ identifier: "diagnose", text: "Diagnose" }],
            actionHandlers: {
                diagnose: function() {
                    Quickshell.execDetached([
                        "python3", root.diagnosisScript, crashPid,
                        "--comm", name,
                        "--exe", exe,
                        "--signal", signal,
                        "--time", timestamp
                    ]);
                }
            }
        });
    }

    Process {
        id: statusProcess
        running: false
        stdout: StdioCollector {
            id: statusOutput
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: statusError
            waitForEnd: true
        }
        onExited: exitCode => {
            if (exitCode === 0)
                root.applyStatus(statusOutput.text);
            else
                root.errorText = statusError.text.trim() || "Crash integration status is unavailable.";
        }
    }

    Process {
        id: mutationProcess
        running: false
        stdout: StdioCollector {
            id: mutationOutput
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: mutationError
            waitForEnd: true
        }
        onExited: exitCode => {
            root.loading = false;
            if (exitCode === 0)
                root.applyStatus(mutationOutput.text);
            else
                root.errorText = mutationError.text.trim() || "Crash integration could not be changed.";
        }
    }
}
