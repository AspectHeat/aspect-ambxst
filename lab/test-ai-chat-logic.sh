#!/usr/bin/env bash
# Pure logic and source-contract gate for the AI chat stability implementation.

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root" || exit 1

if ! command -v node >/dev/null 2>&1; then
    echo "test-ai-chat-logic: node is required but not installed" >&2
    exit 127
fi

exec node - <<'NODE'
const fs = require("fs");

function loadLibrary(file, exported) {
    const src = fs.readFileSync(file, "utf8").replace(/^\s*\.pragma\s+library\s*/, "");
    const tail = exported.map(name =>
        `exports.${name}=typeof ${name}!=="undefined"?${name}:undefined;`).join("");
    const mod = {};
    new Function("exports", src + ";" + tail)(mod);
    return mod;
}

const Markdown = loadLibrary("modules/services/ai/markdown.js", ["splitMarkdownBlocks", "displayContent"]);
const Messages = loadLibrary("modules/services/ai/message-utils.js", ["serializeMessage", "messageForApi"]);
const Hermes = loadLibrary("modules/services/ai/hermes-sse.js", ["parseLine"]);
const HermesConfig = loadLibrary("modules/services/ai/hermes-config.js", [
    "normalizeEndpoint", "parseModelsResponse", "connectionError"
]);

let passed = 0;
const failures = [];

function check(name, condition, detail = "") {
    if (condition) {
        passed++;
    } else {
        failures.push(`${name}${detail ? `: ${detail}` : ""}`);
    }
}

function same(actual, expected) {
    return JSON.stringify(actual) === JSON.stringify(expected);
}

function blocks(text) {
    return Markdown.splitMarkdownBlocks(text);
}

check("plain markdown", same(blocks("hello"), [
    {type: "text", content: "hello", language: "", unfinished: false}
]));
check("complete c++ fence", same(blocks("before\n```c++\nint x;\n```\nafter"), [
    {type: "text", content: "before\n", language: "", unfinished: false},
    {type: "code", content: "int x;", language: "c++", unfinished: false},
    {type: "text", content: "after", language: "", unfinished: false}
]));
check("unfinished fence", same(blocks("```shell-session\n$ echo hi"), [
    {type: "code", content: "$ echo hi", language: "shell-session", unfinished: true}
]));
check("empty fence", same(blocks("```\n```"), [
    {type: "code", content: "", language: "text", unfinished: false}
]));
check("tilde c# fence", same(blocks("~~~c#\nConsole.WriteLine();\n~~~"), [
    {type: "code", content: "Console.WriteLine();", language: "c#", unfinished: false}
]));
check("missing opening newline", same(blocks("```js const x = 1;\n```"), [
    {type: "code", content: "const x = 1;", language: "js", unfinished: false}
]));
check("think marker inside code", same(blocks("```txt\n<think>not reasoning</think>\n```"), [
    {type: "code", content: "<think>not reasoning</think>", language: "txt", unfinished: false}
]));
check("closed think", same(blocks("A<think>hidden **work**</think>B"), [
    {type: "text", content: "A", language: "", unfinished: false},
    {type: "think", content: "hidden **work**", language: "", unfinished: false},
    {type: "text", content: "B", language: "", unfinished: false}
]));
check("unfinished think", same(blocks("A<think>still working"), [
    {type: "text", content: "A", language: "", unfinished: false},
    {type: "think", content: "still working", language: "", unfinished: true}
]));
check("stray think close is prose", same(blocks("A</think>B"), [
    {type: "text", content: "A</think>B", language: "", unfinished: false}
]));
check("display content removes think section", Markdown.displayContent("A<think>secret</think>B") === "AB");
check("display content preserves ordinary markdown exactly", Markdown.displayContent("**A**\n```c++\nx++;\n```") === "**A**\n```c++\nx++;\n```");

const legacy = {
    role: "assistant",
    content: "legacy",
    model: "old-model",
    attachments: [{type: "image", mimeType: "image/png", base64: "AA=="}],
    geminiParts: [{text: "legacy"}],
    functionCall: {name: "run_shell_command", args: {command: "printf hi"}},
    functionPending: false,
    functionApproved: true,
    name: "tool-name",
    annotations: [{type: "citation"}],
    annotationSources: [{url: "https://example.test"}],
    searchQueries: ["query"],
    visibleToUser: false,
    unknownProviderPayload: {nested: [1, 2, 3]}
};

function runtime(source) {
    return Object.assign({
        sourceData: JSON.parse(JSON.stringify(source)),
        role: source.role || "assistant",
        content: source.content || "",
        rawContent: source.rawContent || source.content || "",
        model: source.model || "",
        name: source.name || "",
        attachments: source.attachments,
        geminiParts: source.geminiParts,
        functionCall: source.functionCall,
        functionPending: source.functionPending === true,
        functionApproved: source.functionApproved === true,
        fileMimeType: source.fileMimeType || "",
        fileUri: source.fileUri || "",
        localFilePath: source.localFilePath || "",
        functionName: source.functionName || "",
        functionResponse: source.functionResponse || "",
        annotations: source.annotations,
        annotationSources: source.annotationSources,
        searchQueries: source.searchQueries,
        visibleToUser: source.visibleToUser !== false,
        done: true,
        thinking: false,
        toolStatus: "terminal · running"
    }, source);
}

const legacyRuntime = runtime(legacy);
const roundTrip = Messages.serializeMessage(legacyRuntime);
check("legacy fixture round-trips losslessly", same(roundTrip, legacy),
    `got ${JSON.stringify(roundTrip)}`);
check("transient tool status omitted", !("toolStatus" in roundTrip));

legacyRuntime.content = "edited";
legacyRuntime.rawContent = "edited";
const edited = Messages.serializeMessage(legacyRuntime);
check("edit updates persisted content", edited.content === "edited");
check("edit does not add redundant rawContent", !("rawContent" in edited));
check("unknown metadata survives edit", same(edited.unknownProviderPayload, legacy.unknownProviderPayload));

legacyRuntime.rawContent = "canonical provider text";
legacyRuntime.content = "display text";
const apiMessage = Messages.messageForApi(legacyRuntime);
check("API uses canonical raw content", apiMessage.content === "canonical provider text");
check("API preserves attachments", same(apiMessage.attachments, legacy.attachments));
check("API excludes unknown display-only metadata", !("unknownProviderPayload" in apiMessage));

let hermesState = "";
let event = Hermes.parseLine("event: hermes.tool.progress", hermesState);
hermesState = event.pendingEvent;
check("Hermes event line retained", event.handled && hermesState === "hermes.tool.progress");
event = Hermes.parseLine('data: {"tool":"terminal","status":"running"}', hermesState);
check("Hermes progress isolated", event.handled && event.toolStatus === "terminal · running"
    && event.content === "" && event.pendingEvent === "");
event = Hermes.parseLine('data: {"choices":[]}', "");
check("normal SSE delegated", event.handled === false && event.pendingEvent === "");

check("Hermes endpoint defaults to local API",
    HermesConfig.normalizeEndpoint("") === "http://127.0.0.1:8642/v1");
check("Hermes endpoint appends v1",
    HermesConfig.normalizeEndpoint("http://127.0.0.1:8642/") === "http://127.0.0.1:8642/v1");
check("Hermes endpoint adds local HTTP scheme",
    HermesConfig.normalizeEndpoint("127.0.0.1:8642") === "http://127.0.0.1:8642/v1");
check("Hermes endpoint preserves profile v1",
    HermesConfig.normalizeEndpoint("https://agent.example/p/coder/v1/") === "https://agent.example/p/coder/v1");
check("Hermes endpoint strips models resource",
    HermesConfig.normalizeEndpoint("http://127.0.0.1:8642/v1/models") === "http://127.0.0.1:8642/v1");

let catalog = HermesConfig.parseModelsResponse(
    '{"object":"list","data":[{"id":"hermes-agent"},{"id":"hermes-agent"},{"id":"coder"}]}');
check("Hermes catalog parses and de-duplicates",
    catalog.error === "" && same(catalog.modelIds, ["hermes-agent", "coder"]));
check("Hermes invalid catalog is actionable",
    HermesConfig.parseModelsResponse("not json").error === "Hermes returned invalid JSON");
check("Hermes auth errors preserve API message",
    HermesConfig.connectionError(22, "", '{"error":{"message":"Invalid gateway API key"}}')
        === "Invalid gateway API key");
check("Hermes connection refusal is actionable",
    HermesConfig.connectionError(7, "", "") === "Hermes gateway is not reachable");

const aiSource = fs.readFileSync("modules/services/Ai.qml", "utf8");
const configSource = fs.readFileSync("config/Config.qml", "utf8");
const aiPanelSource = fs.readFileSync("modules/widgets/config/AiPanel.qml", "utf8");
const sidebarSource = fs.readFileSync("modules/sidebar/AssistantSidebar.qml", "utf8");
const codeSource = fs.readFileSync("modules/sidebar/CodeBlock.qml", "utf8");
check("no raw currentChat model remains", !/\bcurrentChat\b/.test(aiSource));
check("stream timer is bounded", /interval:\s*50\b/.test(aiSource));
check("stream callback mutates live object", /message\.content\s*=\s*Markdown\.displayContent\(responseBuffer\)/.test(aiSource));
check("sidebar models stable IDs", /model:\s*Ai\.messageIDs\.filter/.test(sidebarSource));
check("sidebar consumes message blocks", /message\.blocks/.test(sidebarSource));
check("clipboard avoids generated Process", !/Qt\.createQmlObject/.test(codeSource));
check("highlighter is completion gated", /active:\s*root\.highlightEnabled/.test(codeSource));
check("tool callback defers structural mutation",
    /id:\s*commandExecutionProc[\s\S]*?onExited:[\s\S]*?Qt\.callLater\(\(\)\s*=>\s*\{[\s\S]*?appendMessage/.test(aiSource));
check("Hermes fallback publishes before discovery",
    /function\s+startHermesModelFetch[\s\S]*?if\s*\(!hasHermesModels\(\)\)[\s\S]*?publishHermesModels\(\["hermes-agent"\]\)[\s\S]*?fetchProcessHermes\.running\s*=\s*true/.test(aiSource));
check("overlapping model refreshes are queued",
    /if\s*\(fetchingModels\)\s*\{[\s\S]*?modelRefreshPending\s*=\s*true/.test(aiSource));
check("curl waits for request body save",
    /id:\s*requestBodyFileFactory[\s\S]*?onSaved:\s*root\.completeBodyWrite/.test(aiSource));
check("each request gets an isolated body writer",
    /requestBodyFileFactory\.createObject\(root,[\s\S]*?path:\s*payload\.bodyPath[\s\S]*?writer\.setText\(payload\.body\)/.test(aiSource));
check("missing AI config uses enum and retries after mkdir",
    /error\s*===\s*FileViewError\.FileNotFound[\s\S]*?aiLoader\.setText/.test(configSource)
    && /id:\s*ensureConfigDir[\s\S]*?onExited:[\s\S]*?aiLoader\.reload/.test(configSource));
check("AI settings render explicit legible hints",
    /component\s+LegibleTextField:\s*TextField/.test(aiPanelSource)
    && /placeholderText:\s*""/.test(aiPanelSource)
    && /z:\s*10[\s\S]*?color:\s*Colors\.overSurfaceVariant/.test(aiPanelSource)
    && (aiPanelSource.match(/hintText:/g) || []).length === 6
    && /Accessible\.name:\s*accessibleName/.test(aiPanelSource)
    && (aiPanelSource.match(/accessibleName:/g) || []).length === 6);
check("Hermes settings expose connection validation",
    /property\s+string\s+hermesConnectionState:\s*"unconfigured"/.test(aiSource)
    && /--fail-with-body/.test(aiSource)
    && /function\s+testHermesConnection\(\)/.test(aiSource)
    && /modelData\s*===\s*"hermes"\s*\?\s*"Save & Test"/.test(aiPanelSource)
    && /text:\s*Ai\.hermesConnectionMessage/.test(aiPanelSource)
    && /API_SERVER_KEY/.test(aiPanelSource));
check("Hermes connection test is provider-isolated and generation-guarded",
    /function\s+testHermesConnection\(\)[\s\S]*?startHermesModelFetch\(false\)/.test(aiSource)
    && /property\s+int\s+hermesFetchGeneration/.test(aiSource)
    && /hermesRunningGeneration\s*=\s*hermesFetchGeneration/.test(aiSource)
    && /completedGeneration\s*=\s*hermesRunningGeneration/.test(aiSource)
    && /completedGeneration\s*===\s*hermesFetchGeneration/.test(aiSource)
    && /fetchProcessHermes\.running[\s\S]*?hermesFetchGeneration\+\+[\s\S]*?hermesTestPending\s*=\s*true/.test(aiSource)
    && /if\s*\(hermesTestPending\)[\s\S]*?startHermesModelFetch\(false\)/.test(aiSource)
    && /if\s*\(countsTowardRefresh\)\s*checkFetchCompletion\(\)/.test(aiSource));
check("Hermes refresh preserves matching model identity",
    /function\s+hasHermesModels\(\)/.test(aiSource)
    && /incoming\.model\s*===\s*existingProviderModels\[j\]\.model/.test(aiSource)
    && /currentStillPresent[\s\S]*?currentBelongsToProvider\s*&&\s*!currentStillPresent/.test(aiSource)
    && /supersededModels\[i\]\.destroy\(\)/.test(aiSource));

if (failures.length > 0) {
    console.error(`AI chat logic: ${passed} passed, ${failures.length} failed`);
    failures.forEach(failure => console.error(`FAIL ${failure}`));
    process.exit(1);
}
console.log(`AI chat logic: ${passed} passed, 0 failed`);
NODE
