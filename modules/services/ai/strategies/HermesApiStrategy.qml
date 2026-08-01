import QtQuick
import "../hermes-sse.js" as HermesSse

OpenAiApiStrategy {
    property string pendingEvent: ""

    function resetStream() {
        pendingEvent = "";
    }

    function getHeadersForSession(apiKey, sessionId) {
        let headers = getHeaders(apiKey);
        headers.push("X-Hermes-Session-Id: " + sessionId);
        return headers;
    }

    function parseStreamChunk(line) {
        let parsed = HermesSse.parseLine(line, pendingEvent);
        pendingEvent = parsed.pendingEvent;
        if (parsed.handled)
            return parsed;
        return parseOpenAiStreamChunk(line);
    }
}
