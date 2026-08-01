.pragma library

function progressLabel(payload) {
    if (!payload)
        return "Hermes tool running";
    let name = payload.tool || payload.tool_name || payload.name || payload.label || "Hermes tool";
    let status = payload.status || payload.message || payload.phase || "running";
    return name + " · " + status;
}

function parseLine(line, pendingEvent) {
    let trimmed = String(line || "").trim();
    let currentEvent = pendingEvent || "";
    if (trimmed.startsWith("event:")) {
        return {
            handled: true,
            pendingEvent: trimmed.substring(6).trim(),
            content: "",
            done: false,
            error: null
        };
    }

    if (currentEvent === "hermes.tool.progress" && trimmed.startsWith("data:")) {
        let payload = null;
        try {
            payload = JSON.parse(trimmed.substring(5).trim());
        } catch (e) {
            payload = null;
        }
        return {
            handled: true,
            pendingEvent: "",
            content: "",
            done: false,
            error: null,
            event: currentEvent,
            toolStatus: progressLabel(payload)
        };
    }

    return {
        handled: false,
        pendingEvent: trimmed.startsWith("data:") ? "" : currentEvent
    };
}
