pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.services
import qs.modules.theme

Rectangle {
    id: root
    color: "transparent"
    implicitWidth: 600
    implicitHeight: 430

    readonly property var providers: AgentUsageService.providers
    property string selectedProviderId: ""
    property double nowMs: Date.now()

    readonly property int providerIndex: {
        for (let i = 0; i < providers.length; i++) {
            if (providers[i] && String(providers[i].id || "") === selectedProviderId)
                return i;
        }
        return 0;
    }
    readonly property var provider: providers.length > 0 ? providers[providerIndex] : null
    readonly property var modelRows: rowsForModels(provider)
    readonly property real maxDayTokens: peakDayTokens(provider)

    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(maximum, value));
    }

    function providerIcon(providerId) {
        if (providerId === "claude")
            return Qt.resolvedUrl("../../../../assets/aiproviders/claude.svg");
        if (providerId === "codex")
            return Qt.resolvedUrl("../../../../assets/aiproviders/openai.svg");
        if (providerId === "cursor")
            return Qt.resolvedUrl("../../../../assets/aiproviders/cursor.svg");
        if (providerId === "opencode-go")
            return Qt.resolvedUrl("../../../../assets/aiproviders/opencode-go.svg");
        return "";
    }

    function providerInitial(currentProvider) {
        const name = String(currentProvider && (currentProvider.name || currentProvider.id) || "A");
        return name.length > 0 ? name.charAt(0).toUpperCase() : "A";
    }

    function providerById(providerId) {
        for (let i = 0; i < providers.length; i++) {
            if (providers[i] && String(providers[i].id || "") === providerId)
                return providers[i];
        }
        return null;
    }

    function formatTokens(value) {
        const count = Math.max(0, Number(value) || 0);
        if (count >= 1000000000)
            return (count / 1000000000).toFixed(count >= 10000000000 ? 0 : 1) + "B";
        if (count >= 1000000)
            return (count / 1000000).toFixed(count >= 10000000 ? 0 : 1) + "M";
        if (count >= 1000)
            return (count / 1000).toFixed(count >= 10000 ? 0 : 1) + "K";
        return String(Math.round(count));
    }

    function formatPercent(value) {
        return Math.round(clamp(Number(value) || 0, 0, 1) * 100) + "%";
    }

    function planText(currentProvider) {
        const tier = String(currentProvider && currentProvider.tierLabel ? currentProvider.tierLabel : "");
        return tier === "" ? "Subscription" : tier.charAt(0).toUpperCase() + tier.slice(1);
    }

    function crashStatusText() {
        if (!CrashDiagnosticsService.available)
            return "systemd-coredump unavailable";
        if (AgentUsageService.defaultAgentId === "")
            return "Choose a default agent";
        if (!CrashDiagnosticsService.installed)
            return "Crash capture is not set up";
        if (!CrashDiagnosticsService.enabled)
            return "Crash notifications are off";
        return CrashDiagnosticsService.running ? "Watching for process crashes" : "Crash watcher is stopped";
    }

    function crashDetailText() {
        if (CrashDiagnosticsService.isolated)
            return "Setup applies to your real user account and follows this test checkout.";
        if (AgentUsageService.defaultAgentId === "")
            return "The selected agent opens crash records in plan, ask, or read-only mode.";
        if (!CrashDiagnosticsService.installed)
            return "Set up the user service and shared Ambxst diagnosis skills.";
        if (!CrashDiagnosticsService.skillsInstalled)
            return "The watcher is installed, but one or more agent skill links are missing.";
        return "Click a crash notification to diagnose its retained coredump with your default agent.";
    }

    function resetText(value) {
        if (!value)
            return "Reset time unavailable";
        const reset = new Date(String(value)).getTime();
        if (!isFinite(reset))
            return "Reset time unavailable";
        const remaining = reset - nowMs;
        if (remaining <= 0)
            return "Resets now";
        const minutes = Math.floor(remaining / 60000);
        const hours = Math.floor(minutes / 60);
        const days = Math.floor(hours / 24);
        if (days > 0)
            return "Resets in " + days + "d " + (hours % 24) + "h";
        if (hours > 0)
            return "Resets in " + hours + "h " + (minutes % 60) + "m";
        return "Resets in " + Math.max(1, minutes) + "m";
    }

    function updatedText(value) {
        if (!value)
            return "Not refreshed yet";
        const updated = new Date(String(value));
        if (isNaN(updated.getTime()))
            return "Updated recently";
        return "Updated " + updated.toLocaleTimeString(Qt.locale(), "hh:mm");
    }

    function dayLabel(value) {
        const date = new Date(String(value || "") + "T00:00:00");
        if (isNaN(date.getTime()))
            return String(value || "");
        const today = new Date(nowMs);
        const key = today.getFullYear() + "-" + String(today.getMonth() + 1).padStart(2, "0") + "-" + String(today.getDate()).padStart(2, "0");
        if (String(value) === key)
            return "Today";
        return date.toLocaleDateString(Qt.locale(), "ddd");
    }

    function dayTokens(day) {
        if (!day)
            return 0;
        return Number(day.totalTokens !== undefined ? day.totalTokens : day.messageCount) || 0;
    }

    function peakDayTokens(currentProvider) {
        let peak = 0;
        const days = currentProvider && Array.isArray(currentProvider.recentDays) ? currentProvider.recentDays : [];
        for (let i = 0; i < days.length; i++)
            peak = Math.max(peak, dayTokens(days[i]));
        return peak;
    }

    function rowsForModels(currentProvider) {
        const usage = currentProvider && currentProvider.modelUsage ? currentProvider.modelUsage : {};
        let rows = [];
        for (const model in usage) {
            const bucket = usage[model] || {};
            const total = Number(bucket.inputTokens || 0) + Number(bucket.outputTokens || 0)
                + Number(bucket.cacheReadInputTokens || 0) + Number(bucket.cacheCreationInputTokens || 0);
            rows.push({ name: model, total: total });
        }
        rows.sort((a, b) => b.total - a.total);
        return rows.slice(0, 5);
    }

    function selectInitialProvider() {
        if (providers.length === 0) {
            selectedProviderId = "";
            return;
        }
        if (!providerById(selectedProviderId))
            selectedProviderId = String(providers[0].id || "");
    }

    onProvidersChanged: selectInitialProvider()
    onVisibleChanged: {
        if (visible) {
            AgentUsageService.ensureFresh();
            CrashDiagnosticsService.refreshStatus();
        }
    }

    Component.onCompleted: {
        selectInitialProvider();
        AgentUsageService.ensureFresh();
        CrashDiagnosticsService.refreshStatus();
    }

    Timer {
        interval: 30000
        running: root.visible
        repeat: true
        onTriggered: root.nowMs = Date.now()
    }

    RowLayout {
        anchors.fill: parent
        spacing: 8

        StyledRect {
            Layout.preferredWidth: 152
            Layout.fillHeight: true
            variant: "common"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: Icons.robot
                        font.family: Icons.font
                        font.pixelSize: 22
                        color: Colors.overBackground
                    }

                    Text {
                        text: "Agents"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(2)
                        font.weight: Font.DemiBold
                        color: Colors.overBackground
                        Layout.fillWidth: true
                    }
                }

                Text {
                    text: "Subscription usage"
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-2)
                    color: Colors.overSurfaceVariant
                    Layout.fillWidth: true
                }

                ListView {
                    id: providerList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 58
                    model: root.providers
                    spacing: 8
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: ScrollBar {
                        policy: providerList.contentHeight > providerList.height
                            ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    }

                    delegate: Button {
                        id: providerButton
                        required property var modelData
                        required property int index

                        width: providerList.width
                        height: 58
                        flat: true
                        hoverEnabled: true

                        background: StyledRect {
                            variant: root.selectedProviderId === String(providerButton.modelData.id || "")
                                ? "primary" : (providerButton.hovered ? "focus" : "internalbg")
                            radius: Styling.radius(3)
                        }

                        contentItem: RowLayout {
                            spacing: 8

                            StyledRect {
                                Layout.preferredWidth: 30
                                Layout.preferredHeight: 30
                                variant: "primary"
                                radius: Styling.radius(2)

                                Image {
                                    id: providerListIcon
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    source: root.providerIcon(String(providerButton.modelData.id || ""))
                                    visible: source.toString() !== ""
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !providerListIcon.visible
                                    text: root.providerInitial(providerButton.modelData)
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(0)
                                    font.weight: Font.Bold
                                    color: Styling.srItem("primary")
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                Text {
                                    Layout.fillWidth: true
                                    text: String(providerButton.modelData.name || providerButton.modelData.id || "Agent")
                                    elide: Text.ElideRight
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                    font.weight: Font.DemiBold
                                    color: root.selectedProviderId === String(providerButton.modelData.id || "")
                                        ? Styling.srItem("primary") : Colors.overBackground
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: (AgentUsageService.defaultAgentId === String(providerButton.modelData.id || "")
                                        ? "Default · " : "") + root.planText(providerButton.modelData)
                                    elide: Text.ElideRight
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-3)
                                    color: root.selectedProviderId === String(providerButton.modelData.id || "")
                                        ? Styling.srItem("primary") : Colors.overSurfaceVariant
                                }
                            }
                        }

                        onClicked: root.selectedProviderId = String(modelData.id || "")
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: AgentUsageService.errorText !== ""
                    text: AgentUsageService.errorText
                    wrapMode: Text.Wrap
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-3)
                    color: Colors.error
                }

                Text {
                    Layout.fillWidth: true
                    Layout.minimumHeight: implicitHeight
                    text: root.updatedText(AgentUsageService.updatedAt)
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-3)
                    color: Colors.overSurfaceVariant
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.centerIn: parent
                width: Math.min(parent.width - 32, 320)
                spacing: 10
                visible: root.providers.length === 0

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: AgentUsageService.loading ? Icons.spinnerGap : Icons.robot
                    font.family: Icons.font
                    font.pixelSize: 42
                    color: Colors.overSurfaceVariant

                    RotationAnimation on rotation {
                        running: AgentUsageService.loading
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: AgentUsageService.loading ? "Reading agent subscriptions…" : "No supported agents found"
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(1)
                    font.weight: Font.DemiBold
                    color: Colors.overBackground
                }

                Text {
                    Layout.fillWidth: true
                    visible: !AgentUsageService.loading
                    text: "Install or connect a supported coding agent, then refresh."
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    font.family: Config.theme.font
                    font.pixelSize: Styling.fontSize(-1)
                    color: Colors.overSurfaceVariant
                }
            }

            Flickable {
                id: detailFlick
                anchors.fill: parent
                visible: root.provider !== null
                clip: true
                contentWidth: width
                contentHeight: details.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    policy: detailFlick.contentHeight > detailFlick.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                }

                ColumnLayout {
                    id: details
                    width: detailFlick.width - (detailFlick.contentHeight > detailFlick.height ? 8 : 0)
                    spacing: 8

                    StyledRect {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 76
                        variant: "pane"

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 12

                            StyledRect {
                                Layout.preferredWidth: 48
                                Layout.preferredHeight: 48
                                variant: "primary"
                                radius: Styling.radius(3)

                                Image {
                                    id: providerDetailIcon
                                    anchors.fill: parent
                                    anchors.margins: 9
                                    source: root.providerIcon(String(root.provider ? root.provider.id || "" : ""))
                                    visible: source.toString() !== ""
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !providerDetailIcon.visible
                                    text: root.providerInitial(root.provider)
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(2)
                                    font.weight: Font.Bold
                                    color: Styling.srItem("primary")
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: String(root.provider ? root.provider.name || "Agent" : "Agent")
                                    elide: Text.ElideRight
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(3)
                                    font.weight: Font.Bold
                                    color: Colors.overBackground
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.planText(root.provider)
                                    elide: Text.ElideRight
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                    color: Colors.overSurfaceVariant
                                }
                            }

                            Button {
                                id: defaultButton
                                readonly property bool isDefault: AgentUsageService.defaultAgentId
                                    === String(root.provider ? root.provider.id || "" : "")
                                Layout.preferredWidth: 88
                                Layout.preferredHeight: 38
                                flat: true
                                hoverEnabled: true
                                enabled: !isDefault && root.provider !== null

                                background: StyledRect {
                                    variant: defaultButton.isDefault ? "primary"
                                        : (defaultButton.hovered ? "focus" : "internalbg")
                                    radius: Styling.radius(3)
                                }

                                contentItem: Text {
                                    text: defaultButton.isDefault ? "Default" : "Set default"
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    font.weight: Font.DemiBold
                                    color: defaultButton.isDefault ? Styling.srItem("primary") : Colors.overBackground
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: AgentUsageService.setDefaultAgent(String(root.provider.id || ""))
                            }

                            Button {
                                id: refreshButton
                                Layout.preferredWidth: 38
                                Layout.preferredHeight: 38
                                flat: true
                                hoverEnabled: true
                                enabled: !AgentUsageService.loading

                                background: StyledRect {
                                    variant: refreshButton.hovered ? "focus" : "internalbg"
                                    radius: Styling.radius(3)
                                }

                                contentItem: Text {
                                    text: Icons.arrowCounterClockwise
                                    font.family: Icons.font
                                    font.pixelSize: 18
                                    color: Colors.overBackground
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter

                                    RotationAnimation on rotation {
                                        running: AgentUsageService.loading
                                        from: 0
                                        to: 360
                                        duration: 900
                                        loops: Animation.Infinite
                                    }
                                }

                                onClicked: AgentUsageService.refresh(true)
                            }
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        Layout.preferredHeight: statusColumn.implicitHeight + 20
                        visible: root.provider && String(root.provider.usageStatusText || "") !== ""
                        variant: "internalbg"

                        ColumnLayout {
                            id: statusColumn
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 4

                            Text {
                                Layout.fillWidth: true
                                text: String(root.provider ? root.provider.usageStatusText || "" : "")
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-1)
                                font.weight: Font.DemiBold
                                color: Colors.warning
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: String(root.provider ? root.provider.authHelpText || "" : "")
                                wrapMode: Text.Wrap
                                font.family: Config.theme.font
                                font.pixelSize: Styling.fontSize(-2)
                                color: Colors.overSurfaceVariant
                            }
                        }
                    }

                    StyledRect {
                        Layout.fillWidth: true
                        Layout.preferredHeight: crashColumn.implicitHeight + 20
                        variant: "internalbg"

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10

                            Text {
                                text: Icons.shieldCheck
                                font.family: Icons.font
                                font.pixelSize: 22
                                color: CrashDiagnosticsService.enabled && CrashDiagnosticsService.running
                                    ? Colors.primary : Colors.overSurfaceVariant
                            }

                            ColumnLayout {
                                id: crashColumn
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: root.crashStatusText()
                                    elide: Text.ElideRight
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                    font.weight: Font.DemiBold
                                    color: Colors.overBackground
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.crashDetailText()
                                    wrapMode: Text.Wrap
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-3)
                                    color: Colors.overSurfaceVariant
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: CrashDiagnosticsService.errorText !== ""
                                    text: CrashDiagnosticsService.errorText
                                    wrapMode: Text.Wrap
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-3)
                                    color: Colors.error
                                }
                            }

                            Button {
                                id: crashActionButton
                                Layout.preferredWidth: 86
                                Layout.preferredHeight: 38
                                flat: true
                                hoverEnabled: true
                                enabled: CrashDiagnosticsService.available
                                    && root.provider !== null
                                    && !CrashDiagnosticsService.loading

                                background: StyledRect {
                                    variant: crashActionButton.hovered ? "focus" : "common"
                                    radius: Styling.radius(3)
                                }

                                contentItem: Text {
                                    text: CrashDiagnosticsService.loading ? "Working…"
                                        : !CrashDiagnosticsService.installed ? "Set up"
                                        : CrashDiagnosticsService.enabled ? "Turn off" : "Turn on"
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-2)
                                    font.weight: Font.DemiBold
                                    color: Colors.overBackground
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                onClicked: {
                                    if (!CrashDiagnosticsService.installed)
                                        CrashDiagnosticsService.install(String(root.provider.id || ""));
                                    else
                                        CrashDiagnosticsService.setCaptureEnabled(!CrashDiagnosticsService.enabled);
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Usage limits"
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(0)
                        font.weight: Font.DemiBold
                        color: Colors.overBackground
                    }

                    Flow {
                        id: limitsFlow
                        Layout.fillWidth: true
                        Layout.preferredHeight: childrenRect.height
                        spacing: 8

                        Repeater {
                            model: root.provider && Array.isArray(root.provider.limits) ? root.provider.limits : []

                            StyledRect {
                                id: limitCard
                                required property var modelData
                                width: Math.max(190, (limitsFlow.width - limitsFlow.spacing) / 2)
                                height: 116
                                variant: "common"

                                readonly property real used: root.clamp(Number(modelData.percent) || 0, 0, 1)

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    spacing: 5

                                    RowLayout {
                                        Layout.fillWidth: true

                                        Text {
                                            Layout.fillWidth: true
                                            text: String(limitCard.modelData.title || limitCard.modelData.label || "Limit")
                                            elide: Text.ElideRight
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-1)
                                            font.weight: Font.DemiBold
                                            color: Colors.overBackground
                                        }

                                        Text {
                                            text: root.formatPercent(limitCard.used)
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(0)
                                            font.weight: Font.Bold
                                            color: limitCard.used >= 0.9 ? Colors.error : Colors.overBackground
                                        }
                                    }

                                    StyledRect {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 8
                                        variant: "internalbg"
                                        radius: height / 2

                                        StyledRect {
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            width: parent.width * limitCard.used
                                            variant: "primary"
                                            radius: height / 2
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: String(limitCard.modelData.detail || "")
                                        elide: Text.ElideRight
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-3)
                                        color: Colors.overSurfaceVariant
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.resetText(limitCard.modelData.resetsAt)
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-3)
                                        color: Colors.overSurfaceVariant
                                    }
                                }
                            }
                        }

                        Text {
                            width: limitsFlow.width
                            visible: !root.provider || !Array.isArray(root.provider.limits) || root.provider.limits.length === 0
                            text: "No usage limit windows are available yet."
                            wrapMode: Text.Wrap
                            font.family: Config.theme.font
                            font.pixelSize: Styling.fontSize(-1)
                            color: Colors.overSurfaceVariant
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: String(root.provider ? root.provider.limitsNote || "" : "")
                        wrapMode: Text.Wrap
                        font.family: Config.theme.font
                        font.pixelSize: Styling.fontSize(-3)
                        color: Colors.overSurfaceVariant
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.provider && root.provider.hasLocalStats === true
                        spacing: 8

                        Repeater {
                            model: [
                                { label: "Tokens today", value: root.formatTokens(root.provider ? root.provider.todayTotalTokens : 0) },
                                { label: "Prompts today", value: String(Number(root.provider ? root.provider.todayPrompts : 0) || 0) },
                                { label: "Sessions today", value: String(Number(root.provider ? root.provider.todaySessions : 0) || 0) }
                            ]

                            StyledRect {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: 64
                                variant: "internalbg"

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: 1

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.value
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(1)
                                        font.weight: Font.Bold
                                        color: Colors.overBackground
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: modelData.label
                                        font.family: Config.theme.font
                                        font.pixelSize: Styling.fontSize(-3)
                                        color: Colors.overSurfaceVariant
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        visible: root.provider && root.provider.hasLocalStats === true
                        spacing: 8

                        StyledRect {
                            Layout.fillWidth: true
                            Layout.preferredHeight: recentColumn.implicitHeight + 20
                            variant: "common"

                            ColumnLayout {
                                id: recentColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 10
                                spacing: 5

                                Text {
                                    text: "Last 7 days"
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                    font.weight: Font.DemiBold
                                    color: Colors.overBackground
                                }

                                Repeater {
                                    model: root.provider && Array.isArray(root.provider.recentDays) ? root.provider.recentDays : []

                                    RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Text {
                                            Layout.preferredWidth: 38
                                            text: root.dayLabel(modelData.date)
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-3)
                                            color: Colors.overSurfaceVariant
                                        }

                                        StyledRect {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 6
                                            variant: "internalbg"
                                            radius: height / 2

                                            StyledRect {
                                                anchors.left: parent.left
                                                anchors.top: parent.top
                                                anchors.bottom: parent.bottom
                                                width: root.maxDayTokens > 0
                                                    ? parent.width * root.dayTokens(modelData) / root.maxDayTokens : 0
                                                variant: "primary"
                                                radius: height / 2
                                            }
                                        }

                                        Text {
                                            Layout.preferredWidth: 36
                                            text: root.formatTokens(root.dayTokens(modelData))
                                            horizontalAlignment: Text.AlignRight
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-3)
                                            color: Colors.overSurfaceVariant
                                        }
                                    }
                                }
                            }
                        }

                        StyledRect {
                            Layout.fillWidth: true
                            Layout.preferredHeight: recentColumn.implicitHeight + 20
                            variant: "common"

                            ColumnLayout {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 10
                                spacing: 6

                                Text {
                                    text: "By model · " + String(root.provider && root.provider.localStatsWindow
                                        ? root.provider.localStatsWindow : "Local")
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-1)
                                    font.weight: Font.DemiBold
                                    color: Colors.overBackground
                                }

                                Repeater {
                                    model: root.modelRows

                                    RowLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Text {
                                            Layout.fillWidth: true
                                            text: String(modelData.name || "Unknown")
                                            elide: Text.ElideMiddle
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-3)
                                            color: Colors.overSurfaceVariant
                                        }

                                        Text {
                                            text: root.formatTokens(modelData.total)
                                            font.family: Config.theme.font
                                            font.pixelSize: Styling.fontSize(-3)
                                            font.weight: Font.DemiBold
                                            color: Colors.overBackground
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: root.modelRows.length === 0
                                    text: "No local model activity yet"
                                    wrapMode: Text.Wrap
                                    font.family: Config.theme.font
                                    font.pixelSize: Styling.fontSize(-3)
                                    color: Colors.overSurfaceVariant
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
