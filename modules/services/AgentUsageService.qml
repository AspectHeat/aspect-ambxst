pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    readonly property string scriptPath: Quickshell.shellDir + "/scripts/agent_usage.py"
    readonly property int refreshIntervalMs: 15 * 60 * 1000
    readonly property string settingsPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ambxst/agents.json"

    property var providers: []
    property string defaultAgentId: ""
    property bool loading: false
    property string errorText: ""
    property string updatedAt: ""
    property double lastRefreshMs: 0
    property bool refreshQueued: false
    property bool forceQueued: false

    signal refreshed

    function loadSettings() {
        try {
            const parsed = JSON.parse(agentSettings.text() || "{}");
            root.defaultAgentId = String(parsed.defaultAgent || "");
        } catch (error) {
            root.defaultAgentId = "";
        }
    }

    function setDefaultAgent(providerId) {
        const value = String(providerId || "");
        if (value !== "" && !root.providers.some(provider => provider && String(provider.id || "") === value))
            return;
        root.defaultAgentId = value;
        agentSettings.setText(JSON.stringify({ defaultAgent: value }, null, 2) + "\n");
        CrashDiagnosticsService.refreshStatus();
    }

    function refresh(force) {
        const forceRefresh = force === true;
        if (collector.running) {
            refreshQueued = true;
            forceQueued = forceQueued || forceRefresh;
            return;
        }

        let command = ["python3", root.scriptPath];
        if (forceRefresh)
            command.push("--force");
        collector.command = command;
        root.loading = true;
        root.errorText = "";
        collector.running = true;
    }

    function ensureFresh(maxAgeMs) {
        const allowedAge = maxAgeMs === undefined ? 2 * 60 * 1000 : Math.max(0, Number(maxAgeMs));
        if (!collector.running && (root.lastRefreshMs <= 0 || Date.now() - root.lastRefreshMs >= allowedAge))
            root.refresh(false);
    }

    function applyPayload(content) {
        try {
            const payload = JSON.parse(String(content || ""));
            if (!payload || payload.schemaVersion !== 1 || !Array.isArray(payload.providers))
                throw new Error("unsupported collector payload");

            root.providers = payload.providers;
            root.updatedAt = String(payload.updatedAt || "");
            root.lastRefreshMs = Date.now();
            root.errorText = "";
            root.refreshed();

            let shouldRetry = false;
            for (let i = 0; i < root.providers.length; i++) {
                if (root.providers[i] && root.providers[i].retryAdvised === true) {
                    shouldRetry = true;
                    break;
                }
            }
            if (shouldRetry)
                retryTimer.restart();
            else
                retryTimer.stop();
        } catch (error) {
            root.errorText = "Agent usage returned an unreadable response.";
            console.warn("AgentUsageService: Failed to parse collector output:", error);
        }
    }

    Process {
        id: collector
        running: false
        command: []

        stdout: StdioCollector {
            id: collectorOutput
            waitForEnd: true
        }

        stderr: StdioCollector {
            id: collectorError
            waitForEnd: true
        }

        onExited: exitCode => {
            root.loading = false;
            if (exitCode === 0 && collectorOutput.text.trim() !== "") {
                root.applyPayload(collectorOutput.text);
            } else {
                root.errorText = "Agent usage refresh failed. Existing data has been kept.";
                if (collectorError.text.trim() !== "")
                    console.warn("AgentUsageService:", collectorError.text.trim());
            }

            if (root.refreshQueued) {
                const queuedForce = root.forceQueued;
                root.refreshQueued = false;
                root.forceQueued = false;
                Qt.callLater(() => root.refresh(queuedForce));
            }
        }
    }

    FileView {
        id: agentSettings
        path: root.settingsPath
        watchChanges: true
        printErrors: false
        onLoaded: root.loadSettings()
        onFileChanged: reload()
    }

    Timer {
        interval: root.refreshIntervalMs
        running: true
        repeat: true
        onTriggered: root.refresh(false)
    }

    Timer {
        id: retryTimer
        interval: 30000
        repeat: false
        onTriggered: root.refresh(false)
    }

    Component.onCompleted: root.refresh(false)
}
