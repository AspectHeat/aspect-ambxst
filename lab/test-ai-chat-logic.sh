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

const aiSource = fs.readFileSync("modules/services/Ai.qml", "utf8");
const sidebarSource = fs.readFileSync("modules/sidebar/AssistantSidebar.qml", "utf8");
const codeSource = fs.readFileSync("modules/sidebar/CodeBlock.qml", "utf8");
check("no raw currentChat model remains", !/\bcurrentChat\b/.test(aiSource));
check("stream timer is bounded", /interval:\s*50\b/.test(aiSource));
check("stream callback mutates live object", /message\.content\s*=\s*Markdown\.displayContent\(responseBuffer\)/.test(aiSource));
check("sidebar models stable IDs", /model:\s*Ai\.messageIDs\.filter/.test(sidebarSource));
check("sidebar consumes message blocks", /message\.blocks/.test(sidebarSource));
check("clipboard avoids generated Process", !/Qt\.createQmlObject/.test(codeSource));
check("highlighter is completion gated", /active:\s*root\.highlightEnabled/.test(codeSource));

if (failures.length > 0) {
    console.error(`AI chat logic: ${passed} passed, ${failures.length} failed`);
    failures.forEach(failure => console.error(`FAIL ${failure}`));
    process.exit(1);
}
console.log(`AI chat logic: ${passed} passed, 0 failed`);
NODE
