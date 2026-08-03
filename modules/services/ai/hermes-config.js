.pragma library

const defaultEndpoint = "http://127.0.0.1:8642/v1";

function normalizeEndpoint(value) {
    let endpoint = String(value || "").trim().replace(/\/+$/, "");
    if (!endpoint)
        return defaultEndpoint;

    if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(endpoint))
        endpoint = "http://" + endpoint;
    endpoint = endpoint.replace(/\/(?:models|chat\/completions)$/i, "");
    if (!/\/v1$/i.test(endpoint))
        endpoint += "/v1";
    return endpoint;
}

function parseModelsResponse(text) {
    try {
        let data = JSON.parse(String(text || ""));
        if (!data || !Array.isArray(data.data))
            return { modelIds: [], error: "Hermes returned an invalid model catalog" };

        let modelIds = [];
        for (let i = 0; i < data.data.length; i++) {
            let id = String(data.data[i] && data.data[i].id || "").trim();
            if (id && modelIds.indexOf(id) === -1)
                modelIds.push(id);
        }
        if (modelIds.length === 0)
            return { modelIds: [], error: "Hermes returned an empty model catalog" };
        return { modelIds: modelIds, error: "" };
    } catch (e) {
        return { modelIds: [], error: "Hermes returned invalid JSON" };
    }
}

function connectionError(exitCode, stderrText, stdoutText) {
    try {
        let body = JSON.parse(String(stdoutText || ""));
        let apiMessage = body && body.error && body.error.message;
        if (apiMessage)
            return String(apiMessage);
    } catch (e) {
    }

    switch (Number(exitCode)) {
    case 6:
        return "Hermes host could not be resolved";
    case 7:
        return "Hermes gateway is not reachable";
    case 22:
        return "Hermes rejected the endpoint or API key";
    case 28:
        return "Hermes connection timed out";
    default:
        let detail = String(stderrText || "").trim().split("\n")[0];
        return detail || "Could not connect to Hermes";
    }
}
