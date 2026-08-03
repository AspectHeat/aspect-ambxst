pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.config
import qs.modules.services
import "ai"
import "ai/hermes-config.js" as HermesConfig
import "ai/markdown.js" as Markdown
import "ai/message-utils.js" as MessageUtils
import "ai/strategies"

Singleton {
    id: root

    // ============================================
    // PROPERTIES
    // ============================================

    property string chatDir: Quickshell.env("HOME") + "/.local/share/ambxst/chats"
    property string tmpDir: "/tmp/ambxst-ai"

    property list<AiModel> models: []

    property AiModel currentModel: models.length > 0 ? models[0] : null
    property bool persistenceReady: false
    property string savedModelId: ""
    property bool isRestored: false

    onCurrentModelChanged: {
        if (activeRequest)
            cancelActiveRequest(true);
        if (persistenceReady && currentModel && isRestored) {
            StateService.set("lastAiModel", currentModel.model);
        }
        updateStrategy();
    }

    function restoreModel() {
        const lastModelId = StateService.get("lastAiModel", "gemini-2.0-flash");
        savedModelId = lastModelId;
        tryRestore();
        persistenceReady = true;
    }

    function tryRestore() {
        if (isRestored || models.length === 0)
            return;

        let found = false;

        for (let i = 0; i < models.length; i++) {
            if (models[i].model === savedModelId) {
                currentModel = models[i];
                found = true;
                break;
            }
        }

        if (!found && savedModelId) {
            for (let i = 0; i < models.length; i++) {
                if (models[i].model.endsWith(savedModelId) || models[i].model.endsWith("/" + savedModelId)) {
                    currentModel = models[i];
                    found = true;
                    break;
                }
            }
        }

        if (found)
            isRestored = true;
    }

    Connections {
        target: StateService
        function onStateLoaded() {
            restoreModel();
        }
    }

    Connections {
        target: KeyStore
        function onKeysChanged() {
            Qt.callLater(() => fetchAvailableModels());
        }
    }

    Component.onCompleted: {
        if (StateService.initialized)
            restoreModel();

        if (models.length === 0)
            fetchAvailableModels();

        reloadHistory();
        createNewChat();
    }

    // ============================================
    // STRATEGIES
    // ============================================

    property OpenAiApiStrategy openaiStrategy: OpenAiApiStrategy {}
    property GeminiApiStrategy geminiStrategy: GeminiApiStrategy {}
    property AnthropicApiStrategy anthropicStrategy: AnthropicApiStrategy {}
    property MistralApiStrategy mistralStrategy: MistralApiStrategy {}
    property GroqApiStrategy groqStrategy: GroqApiStrategy {}
    property OllamaApiStrategy ollamaStrategy: OllamaApiStrategy {}
    property MiniMaxApiStrategy minimaxStrategy: MiniMaxApiStrategy {}
    property HermesApiStrategy hermesStrategy: HermesApiStrategy {}

    property ApiStrategy currentStrategy: openaiStrategy

    function getStrategyForProvider(providerName) {
        switch (providerName) {
        case "openai": return openaiStrategy;
        case "gemini": return geminiStrategy;
        case "anthropic": return anthropicStrategy;
        case "mistral": return mistralStrategy;
        case "groq": return groqStrategy;
        case "ollama": return ollamaStrategy;
        case "minimax": return minimaxStrategy;
        case "hermes": return hermesStrategy;
        case "custom": return openaiStrategy; // custom endpoints use OpenAI-compatible format by default
        default: return openaiStrategy;
        }
    }

    function updateStrategy() {
        if (currentModel)
            currentStrategy = getStrategyForProvider(currentModel.provider);
        else
            currentStrategy = openaiStrategy;
    }

    // ============================================
    // STATE
    // ============================================

    property bool isLoading: false
    property string lastError: ""
    property string responseBuffer: ""
    property string pendingDisplayBuffer: ""

    // Runtime chat state. The array contains stable IDs only; message objects are
    // reactive QtObjects and are never replaced while a response streams.
    property var messageIDs: []
    property var messageByID: ({})
    property string currentChatId: ""
    property int nextMessageSerial: 0

    property int requestGeneration: 0
    property var activeRequest: null
    property var pendingRequestPayload: null
    property bool requestProcessBusy: false
    property bool curlProcessBusy: false
    property int streamChunkCount: 0
    property int streamFlushCount: 0
    property int requestFinishCount: 0
    property int createdMessageCount: 0
    property int destroyedMessageCount: 0

    property var chatHistory: []
    property var saveQueue: []
    property var activeSave: null
    property int loadGeneration: 0
    property string pendingLoadId: ""
    property bool loadProcessBusy: false

    FileView {
        id: chatFileView
        printErrors: false
    }

    Timer {
        id: streamFlushTimer
        interval: 50
        repeat: false
        onTriggered: root.flushStream(root.activeRequest)
    }

    // ============================================
    // MESSAGE OWNERSHIP
    // ============================================

    function newMessageId() {
        nextMessageSerial++;
        return currentChatId + "-" + Date.now().toString() + "-" + nextMessageSerial.toString();
    }

    function messageAt(index) {
        if (index < 0 || index >= messageIDs.length)
            return null;
        return messageByID[messageIDs[index]] || null;
    }

    function messageForId(messageId) {
        return messageByID[messageId] || null;
    }

    function createMessage(plainMessage, options) {
        let plain = MessageUtils.cloneValue(plainMessage || {}) || {};
        let opts = options || {};
        let storedContent = plain.content === undefined || plain.content === null ? "" : String(plain.content);
        let rawContent = plain.rawContent === undefined || plain.rawContent === null ? storedContent : String(plain.rawContent);
        let content = plain.rawContent === undefined || plain.rawContent === null
            ? Markdown.displayContent(rawContent) : storedContent;
        let message = aiMessageFactory.createObject(root, {
            messageId: opts.messageId || newMessageId(),
            role: plain.role || "assistant",
            content: content,
            rawContent: rawContent,
            done: opts.done === undefined ? true : opts.done,
            thinking: opts.thinking === true,
            model: plain.model || "",
            functionCall: plain.functionCall,
            functionPending: plain.functionPending === true,
            functionApproved: plain.functionApproved === true,
            name: plain.name || "",
            attachments: plain.attachments,
            geminiParts: plain.geminiParts,
            fileMimeType: plain.fileMimeType || "",
            fileUri: plain.fileUri || "",
            localFilePath: plain.localFilePath || "",
            functionName: plain.functionName || "",
            functionResponse: plain.functionResponse || "",
            annotations: plain.annotations,
            annotationSources: plain.annotationSources,
            searchQueries: plain.searchQueries,
            visibleToUser: plain.visibleToUser !== false,
            toolStatus: opts.toolStatus || "",
            sourceData: plain
        });
        if (message)
            createdMessageCount++;
        return message;
    }

    function appendMessage(plainMessage, options) {
        let message = createMessage(plainMessage, options);
        if (!message)
            return null;
        let nextMap = Object.assign({}, messageByID);
        nextMap[message.messageId] = message;
        messageByID = nextMap;
        messageIDs = messageIDs.concat([message.messageId]);
        chatModelChanged();
        return message;
    }

    function destroyMessage(message) {
        if (!message)
            return;
        destroyedMessageCount++;
        Qt.callLater(() => message.destroy());
    }

    function removeMessagesFrom(index) {
        if (index < 0 || index >= messageIDs.length)
            return;
        let removedIds = messageIDs.slice(index);
        messageIDs = messageIDs.slice(0, index);
        chatModelChanged();
        let nextMap = Object.assign({}, messageByID);
        let removedMessages = [];
        for (let i = 0; i < removedIds.length; i++) {
            if (nextMap[removedIds[i]])
                removedMessages.push(nextMap[removedIds[i]]);
            delete nextMap[removedIds[i]];
        }
        messageByID = nextMap;
        for (let i = 0; i < removedMessages.length; i++)
            destroyMessage(removedMessages[i]);
    }

    function clearChat() {
        let oldMap = messageByID;
        let oldIds = messageIDs.slice();
        messageIDs = [];
        chatModelChanged();
        messageByID = ({});
        for (let i = 0; i < oldIds.length; i++)
            destroyMessage(oldMap[oldIds[i]]);
    }

    function replaceChat(plainMessages) {
        let source = Array.isArray(plainMessages) ? plainMessages : [];
        let oldMap = messageByID;
        let oldIds = messageIDs.slice();
        let nextMap = ({});
        let nextIds = [];
        for (let i = 0; i < source.length; i++) {
            let message = createMessage(source[i], { done: true });
            if (!message)
                continue;
            nextMap[message.messageId] = message;
            nextIds.push(message.messageId);
        }
        messageByID = nextMap;
        messageIDs = nextIds;
        chatModelChanged();
        for (let i = 0; i < oldIds.length; i++)
            destroyMessage(oldMap[oldIds[i]]);
    }

    function serializeMessage(message) {
        return MessageUtils.serializeMessage(message);
    }

    function serializeCurrentChat() {
        let output = [];
        for (let i = 0; i < messageIDs.length; i++) {
            let message = messageByID[messageIDs[i]];
            if (message)
                output.push(serializeMessage(message));
        }
        return output;
    }

    function messagesForApi() {
        let output = [];
        for (let i = 0; i < messageIDs.length; i++) {
            let message = messageByID[messageIDs[i]];
            if (message)
                output.push(MessageUtils.messageForApi(message));
        }
        return output;
    }

    // ============================================
    // TOOLS
    // ============================================

    function regenerateResponse(index) {
        if (index < 0 || index >= messageIDs.length)
            return;
        cancelActiveRequest(true);
        removeMessagesFrom(index);
        lastError = "";
        makeRequest();
    }

    function updateMessage(index, newContent) {
        let message = messageAt(index);
        if (!message)
            return;
        message.content = newContent;
        message.rawContent = newContent;
        saveCurrentChat();
    }

    property var systemTools: [
        {
            name: "run_shell_command",
            description: "Execute a shell command on the user's system (Linux). Use this to list files, control the system, or run utilities. Output will be returned.",
            parameters: {
                type: "object",
                properties: {
                    command: {
                        type: "string",
                        description: "The shell command to run (e.g. 'ls -la', 'ip addr')"
                    }
                },
                required: ["command"]
            }
        }
    ]

    // ============================================
    // CHAT MANAGEMENT
    // ============================================

    function deleteChat(id) {
        if (id === currentChatId)
            createNewChat();

        let filename = chatDir + "/" + id + ".json";
        deleteChatProcess.command = ["rm", filename];
        deleteChatProcess.running = true;
    }

    // ============================================
    // LOGIC
    // ============================================

    function setModel(modelName) {
        for (let i = 0; i < models.length; i++) {
            if (models[i].name === modelName) {
                currentModel = models[i];
                return;
            }
        }
    }

    function getApiKey(model) {
        if (!model || !model.requires_key)
            return "";

        // Try KeyStore first
        let ksKey = KeyStore.getKey(model.provider);
        if (ksKey)
            return ksKey;

        return "";
    }

    function processCommand(text) {
        let cmd = text.trim();
        if (!cmd.startsWith("/"))
            return false;

        let parts = cmd.split(" ");
        let command = parts[0].toLowerCase();
        let args = parts.slice(1).join(" ");

        switch (command) {
        case "/new":
            createNewChat();
            return true;
        case "/model":
            if (args) {
                let found = false;
                for (let i = 0; i < models.length; i++) {
                    if (models[i].name.toLowerCase().includes(args.toLowerCase()) || models[i].model.toLowerCase() === args.toLowerCase()) {
                        setModel(models[i].name);
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    pushSystemMessage("Model '" + args + "' not found.");
                } else {
                    pushSystemMessage("Switched to model: " + currentModel.name);
                }
            } else {
                modelSelectionRequested();
            }
            return true;
        case "/help":
            pushSystemMessage("🤖 **Assistant Commands**\n\n" + "**`/new`**\n" + "Starts a fresh conversation context.\n\n" + "**`/model [name]`**\n" + "Switches the active AI model.\n" + "• **List models:** Type `/model` without arguments.\n" + "• **Switch:** Type `/model gemini` or `/model mistral`.\n\n" + "**`/help`**\n" + "Shows this help message.\n\n" + "💡 **Tips:**\n" + "• **Edit:** Click the pen icon on any message to modify it.\n" + "• **Regenerate:** Click the refresh icon to get a new response.\n" + "• **Copy:** Use the copy button to grab code or text.");
            return true;
        }

        return false;
    }

    function pushSystemMessage(text) {
        appendMessage({
            role: "system",
            content: text
        });
    }

    // Function Call Handling
    function approveCommand(index) {
        let message = messageAt(index);
        if (!message || !message.functionCall)
            return;
        message.functionPending = false;
        message.functionApproved = true;
        saveCurrentChat();

        let args = message.functionCall.args;
        if (message.functionCall.name === "run_shell_command") {
            commandExecutionProc.command = ["bash", "-c", args.command];
            commandExecutionProc.targetMessageId = message.messageId;
            commandExecutionProc.targetChatId = currentChatId;
            commandExecutionProc.running = true;
        }
    }

    function rejectCommand(index) {
        let message = messageAt(index);
        if (!message || !message.functionCall)
            return;
        message.functionPending = false;
        message.functionApproved = false;
        appendMessage({
            role: "function",
            name: message.functionCall.name,
            content: "User rejected the command execution."
        });
        saveCurrentChat();
        makeRequest();
    }

    function sendMessage(text, attachments) {
        if (text.trim() === "" && (!attachments || attachments.length === 0))
            return;
        if (processCommand(text))
            return;
        cancelActiveRequest(true);
        lastError = "";
        let userMsg = {
            role: "user",
            content: text
        };
        if (attachments && attachments.length > 0)
            userMsg.attachments = attachments;
        appendMessage(userMsg);
        saveCurrentChat();
        makeRequest();
    }

    function makeRequest() {
        if (!currentModel) {
            lastError = "No AI model is available. Configure a provider in Settings.";
            isLoading = false;
            appendMessage({ role: "assistant", content: "Error: " + lastError });
            return;
        }

        cancelActiveRequest(true);
        let requestModel = currentModel;
        let requestStrategy = getStrategyForProvider(requestModel.provider);
        let apiKey = getApiKey(requestModel);
        if (!apiKey && requestModel.requires_key) {
            lastError = "API Key missing for " + requestModel.name + ". Add it in Settings or set " + (requestModel.key_id || "the environment variable") + ".";
            isLoading = false;
            appendMessage({ role: "assistant", content: "Error: " + lastError });
            return;
        }

        let endpoint;
        let isGemini = requestModel.provider === "gemini";
        if (isGemini && geminiStrategy._getStreamEndpoint) {
            endpoint = geminiStrategy._getStreamEndpoint(requestModel, apiKey);
        } else {
            endpoint = requestStrategy.getEndpoint(requestModel, apiKey);
        }

        let messages = [];
        if (Config.ai.systemPrompt) {
            messages.push({
                role: "system",
                content: Config.ai.systemPrompt
            });
        }
        messages = messages.concat(messagesForApi());

        let assistantMessage = appendMessage({
            role: "assistant",
            content: "",
            model: requestModel.name
        }, { done: false, thinking: true });
        if (!assistantMessage)
            return;

        requestGeneration++;
        let request = {
            generation: requestGeneration,
            chatId: currentChatId,
            messageId: assistantMessage.messageId,
            modelId: requestModel.model,
            provider: requestModel.provider,
            strategy: requestStrategy,
            toolCalls: ({}),
            finished: false
        };
        activeRequest = request;
        isLoading = true;
        responseBuffer = "";
        pendingDisplayBuffer = "";
        if (requestStrategy.resetStream)
            requestStrategy.resetStream();

        let headers = requestModel.provider === "hermes"
            ? hermesStrategy.getHeadersForSession(apiKey, currentChatId)
            : requestStrategy.getHeaders(apiKey);
        let body = requestStrategy.getStreamBody(messages, requestModel, systemTools);
        let customCurl = requestModel.customCurlTemplate || KeyStore.getCustomCurl(requestModel.provider) || "";
        writeTempBody(JSON.stringify(body), headers, endpoint, request, apiKey, customCurl);
    }

    function isRequestCurrent(request) {
        return request !== null && activeRequest !== null
            && request.generation === requestGeneration
            && activeRequest.generation === request.generation
            && request.chatId === currentChatId
            && activeRequest.modelId === request.modelId
            && activeRequest.provider === request.provider
            && activeRequest.strategy === request.strategy
            && messageForId(request.messageId) !== null;
    }

    function flushStream(request) {
        if (!isRequestCurrent(request) || pendingDisplayBuffer === "")
            return;
        let message = messageForId(request.messageId);
        if (!message)
            return;
        message.rawContent = responseBuffer;
        message.content = Markdown.displayContent(responseBuffer);
        pendingDisplayBuffer = "";
        streamFlushCount++;
    }

    function accumulateToolCalls(request, deltas) {
        if (!deltas)
            return;
        for (let i = 0; i < deltas.length; i++) {
            let delta = deltas[i];
            let index = delta.index === undefined ? i : delta.index;
            let key = index.toString();
            let current = request.toolCalls[key] || { name: "", arguments: "" };
            if (delta.function) {
                if (delta.function.name)
                    current.name += delta.function.name;
                if (delta.function.arguments)
                    current.arguments += delta.function.arguments;
            }
            request.toolCalls[key] = current;
        }
    }

    function applyToolCall(request) {
        let keys = Object.keys(request.toolCalls || {}).sort();
        if (keys.length === 0)
            return;
        let buffered = request.toolCalls[keys[0]];
        if (!buffered || !buffered.name)
            return;
        let args = ({});
        try {
            args = buffered.arguments ? JSON.parse(buffered.arguments) : ({});
        } catch (e) {
            args = { raw: buffered.arguments };
        }
        let message = messageForId(request.messageId);
        if (message) {
            message.functionCall = { name: buffered.name, args: args };
            message.functionPending = true;
            message.functionApproved = false;
        }
    }

    function finishRequest(request, exitCode, stderrText, explicitError) {
        if (!isRequestCurrent(request) || request.finished)
            return false;
        request.finished = true;
        streamFlushTimer.stop();
        flushStream(request);
        applyToolCall(request);

        let message = messageForId(request.messageId);
        let errorText = explicitError || (exitCode !== 0 ? stderrText : "");
        if (errorText) {
            lastError = exitCode !== 0 ? "Network Request Failed: " + errorText : errorText;
            if (message && message.content === "") {
                message.content = "Error: " + lastError;
                message.rawContent = message.content;
            }
        } else if (message && message.content === "" && !message.functionCall) {
            message.content = "No response received from the API.";
            message.rawContent = message.content;
        }
        if (message) {
            message.done = true;
            message.thinking = false;
            message.toolStatus = "";
        }
        isLoading = false;
        activeRequest = null;
        responseBuffer = "";
        pendingDisplayBuffer = "";
        requestFinishCount++;
        saveCurrentChat(request.chatId);
        return true;
    }

    function cancelActiveRequest(preservePartial) {
        let request = activeRequest;
        if (request && isRequestCurrent(request)) {
            streamFlushTimer.stop();
            if (preservePartial) {
                flushStream(request);
                let message = messageForId(request.messageId);
                if (message) {
                    message.done = true;
                    message.thinking = false;
                    message.toolStatus = "";
                }
                saveCurrentChat(request.chatId);
            }
        }
        requestGeneration++;
        activeRequest = null;
        pendingRequestPayload = null;
        responseBuffer = "";
        pendingDisplayBuffer = "";
        streamFlushTimer.stop();
        isLoading = false;
        if (requestProcess.running)
            requestProcess.running = false;
        if (curlProcess.running)
            curlProcess.running = false;
    }

    function writeTempBody(jsonBody, headers, endpoint, request, apiKey, customCurl) {
        pendingRequestPayload = {
            body: jsonBody,
            headers: headers,
            endpoint: endpoint,
            request: request,
            apiKey: apiKey,
            customCurl: customCurl,
            bodyPath: tmpDir + "/body-" + request.generation + ".json"
        };
        tryStartPendingRequest();
    }

    function executeRequest(payload) {
        if (!isRequestCurrent(payload.request))
            return;
        let writer = requestBodyFileFactory.createObject(root, {
            path: payload.bodyPath,
            payload: payload
        });
        if (!writer) {
            let errorText = "Failed to create request body writer";
            finishRequest(payload.request, 1, errorText, errorText);
            return;
        }
        writer.setText(payload.body);
    }

    function completeBodyWrite(writer, errorText) {
        if (!writer || writer.completed)
            return;
        writer.completed = true;
        let payload = writer.payload;
        if (errorText !== "") {
            if (payload)
                finishRequest(payload.request, 1, errorText, errorText);
        } else if (payload && isRequestCurrent(payload.request)) {
            runCurl(payload);
        }
        Qt.callLater(() => {
            writer.destroy();
            tryStartPendingRequest();
        });
    }

    function tryStartPendingRequest() {
        if (!pendingRequestPayload || requestProcessBusy || curlProcessBusy)
            return;
        let payload = pendingRequestPayload;
        if (!isRequestCurrent(payload.request)) {
            pendingRequestPayload = null;
            return;
        }
        pendingRequestPayload = null;
        requestProcess.payload = payload;
        requestProcess.command = ["/usr/bin/mkdir", "-p", tmpDir];
        requestProcessBusy = true;
        requestProcess.running = true;
    }

    function runCurl(payload) {
        if (!isRequestCurrent(payload.request))
            return;
        let command = [];
        if (payload.customCurl) {
            let curlCmd = payload.customCurl
                .split("{{BODY_PATH}}").join(payload.bodyPath)
                .replace("{{ENDPOINT}}", payload.endpoint)
                .replace("{{API_KEY}}", payload.apiKey);
            command = ["/usr/bin/bash", "-c", curlCmd];
        } else {
            command = ["curl", "-sS", "--no-buffer", "-N", "-X", "POST", payload.endpoint];
            for (let i = 0; i < payload.headers.length; i++)
                command.push("-H", payload.headers[i]);
            command.push("--data-binary", "@" + payload.bodyPath);
        }
        curlProcess.generation = payload.request.generation;
        curlProcess.request = payload.request;
        curlProcess.strategy = payload.request.strategy;
        curlProcess.command = command;
        curlProcessBusy = true;
        curlProcess.running = true;
    }

    // ============================================
    // PROCESSES
    // ============================================

    Process {
        id: requestProcess
        property var payload: ({})

        onExited: exitCode => {
            let completedPayload = payload;
            root.requestProcessBusy = false;
            if (root.isRequestCurrent(completedPayload.request)) {
                if (exitCode === 0)
                    root.executeRequest(completedPayload);
                else
                    root.finishRequest(completedPayload.request, exitCode, "Failed to create temp directory", "Failed to create temp directory");
            }
            Qt.callLater(() => root.tryStartPendingRequest());
        }
    }

    Process {
        id: curlProcess
        property int generation: -1
        property var request: null
        property var strategy: null

        stdout: SplitParser {
            onRead: data => {
                let request = curlProcess.request;
                if (!root.isRequestCurrent(request) || curlProcess.generation !== request.generation)
                    return;
                let result = curlProcess.strategy.parseStreamChunk(data);
                if (result.error) {
                    root.finishRequest(request, 0, "", result.error);
                    return;
                }
                if (result.content) {
                    root.responseBuffer += result.content;
                    root.pendingDisplayBuffer += result.content;
                    root.streamChunkCount++;
                    let message = root.messageForId(request.messageId);
                    if (message)
                        message.thinking = false;
                    if (!streamFlushTimer.running)
                        streamFlushTimer.start();
                }
                if (result.toolStatus) {
                    let message = root.messageForId(request.messageId);
                    if (message) {
                        message.toolStatus = result.toolStatus;
                        message.thinking = true;
                    }
                }
                if (result.toolCallDelta)
                    root.accumulateToolCalls(request, result.toolCallDelta);
                if (result.functionCall) {
                    let message = root.messageForId(request.messageId);
                    if (message) {
                        message.functionCall = result.functionCall;
                        message.functionPending = true;
                        if (result.geminiParts)
                            message.geminiParts = result.geminiParts;
                    }
                }
                if (result.done)
                    root.finishRequest(request, 0, "", result.error || "");
            }
        }

        stderr: StdioCollector {
            id: curlStderr
        }

        onExited: exitCode => {
            let completedRequest = request;
            root.curlProcessBusy = false;
            root.finishRequest(completedRequest, exitCode, curlStderr.text.trim(), "");
            Qt.callLater(() => root.tryStartPendingRequest());
        }
    }

    Process {
        id: commandExecutionProc
        property string targetMessageId: ""
        property string targetChatId: ""

        stdout: StdioCollector {
            id: cmdStdout
        }
        stderr: StdioCollector {
            id: cmdStderr
        }

        onExited: exitCode => {
            let completedChatId = targetChatId;
            let completedMessageId = targetMessageId;
            let output = cmdStdout.text + "\n" + cmdStderr.text;
            if (output.trim() === "")
                output = "Command executed successfully (no output).";
            Qt.callLater(() => {
                if (completedChatId !== root.currentChatId)
                    return;
                let message = root.messageForId(completedMessageId);
                if (!message || !message.functionCall)
                    return;
                root.appendMessage({
                    role: "function",
                    name: message.functionCall.name,
                    content: output
                });
                root.saveCurrentChat();
                root.makeRequest();
            });
        }
    }

    // ============================================
    // CHAT STORAGE
    // ============================================

    function createNewChat() {
        cancelActiveRequest(false);
        cancelPendingLoad();
        clearChat();
        currentChatId = Date.now().toString();
    }

    function saveCurrentChat(capturedChatId) {
        let chatId = capturedChatId || currentChatId;
        if (chatId !== currentChatId || messageIDs.length === 0)
            return;
        saveQueue = saveQueue.concat([{
            chatId: chatId,
            filePath: chatDir + "/" + chatId + ".json",
            data: JSON.stringify(serializeCurrentChat(), null, 2)
        }]);
        startNextSave();
    }

    function startNextSave() {
        if (activeSave || saveChatProcess.running || saveQueue.length === 0)
            return;
        activeSave = saveQueue[0];
        saveQueue = saveQueue.slice(1);
        saveChatProcess.command = ["/usr/bin/mkdir", "-p", chatDir];
        saveChatProcess.running = true;
    }

    function reloadHistory() {
        let pyScript = `import os, json, glob
chat_dir = "${chatDir}"
os.makedirs(chat_dir, exist_ok=True)
files = sorted(glob.glob(chat_dir + "/*.json"), key=os.path.getmtime, reverse=True)
for f in files:
    id = os.path.basename(f)[:-5]
    title = "New Chat"
    try:
        with open(f, 'r') as fp:
            data = json.load(fp)
            for msg in data:
                if msg.get("role") == "user":
                    title = msg.get("content", "")[:40].replace("\\n", " ").strip()
                    if len(msg.get("content", "")) > 40: title += "..."
                    break
    except: pass
    print(f"{id}|{title}")
`;
        listHistoryProcess.command = ["python3", "-c", pyScript];
        listHistoryProcess.running = true;
    }

    function loadChat(id) {
        cancelActiveRequest(false);
        let wasBusy = loadProcessBusy;
        cancelPendingLoad();
        pendingLoadId = id;
        if (!wasBusy)
            tryStartPendingLoad();
    }

    function cancelPendingLoad() {
        loadGeneration++;
        pendingLoadId = "";
        if (loadChatProcess.running)
            loadChatProcess.running = false;
    }

    function tryStartPendingLoad() {
        if (loadProcessBusy || pendingLoadId === "")
            return;
        let id = pendingLoadId;
        pendingLoadId = "";
        loadChatProcess.targetId = id;
        loadChatProcess.generation = loadGeneration;
        loadChatProcess.command = ["cat", chatDir + "/" + id + ".json"];
        loadProcessBusy = true;
        loadChatProcess.running = true;
    }

    Process {
        id: saveChatProcess
        onExited: exitCode => {
            let completedSave = root.activeSave;
            root.activeSave = null;
            if (exitCode === 0) {
                if (completedSave && completedSave.filePath.length > 0) {
                    chatFileView.path = completedSave.filePath;
                    chatFileView.setText(completedSave.data);
                    reloadHistory();
                }
            } else {
                console.warn("Failed to create chat directory");
            }
            Qt.callLater(() => root.startNextSave());
        }
    }

    Process {
        id: deleteChatProcess
        onExited: reloadHistory()
    }

    Process {
        id: listHistoryProcess
        stdout: StdioCollector {
            id: listHistoryStdout
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                let lines = listHistoryStdout.text.trim().split("\n");
                let history = [];
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i];
                    if (line === "")
                        continue;
                    let parts = line.split("|");
                    if (parts.length >= 2) {
                        history.push({
                            id: parts[0],
                            title: parts.slice(1).join("|"),
                            path: chatDir + "/" + parts[0] + ".json"
                        });
                    }
                }
                root.chatHistory = history;
                root.historyModelChanged();
            }
        }
    }

    Process {
        id: loadChatProcess
        property string targetId: ""
        property int generation: -1
        stdout: StdioCollector {
            id: loadChatStdout
        }
        onExited: exitCode => {
            let completedGeneration = generation;
            let completedTargetId = targetId;
            root.loadProcessBusy = false;
            if (exitCode === 0 && completedGeneration === root.loadGeneration) {
                try {
                    let messages = JSON.parse(loadChatStdout.text);
                    Qt.callLater(() => {
                        if (completedGeneration !== root.loadGeneration)
                            return;
                        root.currentChatId = completedTargetId;
                        root.replaceChat(messages);
                    });
                } catch (e) {
                    console.log("Error loading chat: " + e);
                }
            }
            Qt.callLater(() => root.tryStartPendingLoad());
        }
    }

    // ============================================
    // DYNAMIC MODEL FETCHING
    // ============================================

    property bool fetchingModels: false
    property int pendingFetches: 0
    property bool modelRefreshPending: false
    property string hermesConnectionState: "unconfigured"
    property string hermesConnectionMessage: "Enter the gateway API key to connect"
    property bool hermesFetchCountsTowardRefresh: false
    property int hermesFetchGeneration: 0
    property int hermesRunningGeneration: 0

    function normalizeHermesEndpoint(endpoint) {
        return HermesConfig.normalizeEndpoint(endpoint);
    }

    function prepareHermesKeySave() {
        hermesConnectionState = "checking";
        hermesConnectionMessage = "Saving key and checking Hermes…";
    }

    function testHermesConnection() {
        if (!KeyStore.getKey("hermes")) {
            hermesConnectionState = "unconfigured";
            hermesConnectionMessage = "Enter the gateway API key to connect";
            return;
        }
        hermesConnectionState = "checking";
        hermesConnectionMessage = "Checking Hermes gateway…";
        startHermesModelFetch(false);
    }

    function startHermesModelFetch(countsTowardRefresh) {
        let hermesKey = KeyStore.getKey("hermes");
        if (!hermesKey || fetchProcessHermes.running)
            return false;

        // Keep Hermes selectable while discovery is slow or unavailable.
        publishHermesModels(["hermes-agent"]);
        hermesConnectionState = "checking";
        hermesConnectionMessage = "Checking Hermes gateway…";
        hermesFetchCountsTowardRefresh = countsTowardRefresh;
        hermesFetchGeneration++;
        hermesRunningGeneration = hermesFetchGeneration;

        let hermesEndpoint = normalizeHermesEndpoint(Config.ai.hermesEndpoint);
        fetchProcessHermes.command = [
            "curl", "-sS", "--fail-with-body", "--connect-timeout", "3", "--max-time", "8",
            hermesEndpoint + "/models",
            "-H", "Authorization: Bearer " + hermesKey
        ];
        fetchProcessHermes.running = true;
        return true;
    }

    function fetchAvailableModels() {
        if (fetchingModels) {
            modelRefreshPending = true;
            return;
        }

        fetchingModels = true;
        pendingFetches = 0;

        // Gemini
        let geminiKey = KeyStore.getKey("gemini");
        if (geminiKey) {
            pendingFetches++;
            fetchProcessGemini.command = ["bash", "-c", "curl -s 'https://generativelanguage.googleapis.com/v1beta/models?key=" + geminiKey + "'"];
            fetchProcessGemini.running = true;
        }

        // OpenAI
        let openaiKey = KeyStore.getKey("openai");
        if (openaiKey) {
            pendingFetches++;
            fetchProcessOpenAI.command = ["bash", "-c", "curl -s https://api.openai.com/v1/models -H 'Authorization: Bearer " + openaiKey + "'"];
            fetchProcessOpenAI.running = true;
        }

        // Anthropic
        let anthropicKey = KeyStore.getKey("anthropic");
        if (anthropicKey) {
            pendingFetches++;
            fetchProcessAnthropic.command = ["bash", "-c", "curl -s https://api.anthropic.com/v1/models -H 'x-api-key: " + anthropicKey + "' -H 'anthropic-version: 2023-06-01'"];
            fetchProcessAnthropic.running = true;
        }

        // Mistral
        let mistralKey = KeyStore.getKey("mistral");
        if (mistralKey) {
            pendingFetches++;
            fetchProcessMistral.command = ["bash", "-c", "curl -s https://api.mistral.ai/v1/models -H 'Authorization: Bearer " + mistralKey + "'"];
            fetchProcessMistral.running = true;
        }

        // Groq
        let groqKey = KeyStore.getKey("groq");
        if (groqKey) {
            pendingFetches++;
            fetchProcessGroq.command = ["bash", "-c", "curl -s https://api.groq.com/openai/v1/models -H 'Authorization: Bearer " + groqKey + "'"];
            fetchProcessGroq.running = true;
        }

        // Ollama (local)
        let ollamaEnabled = KeyStore.hasKey("ollama");
        if (ollamaEnabled) {
            pendingFetches++;
            fetchProcessOllama.command = ["bash", "-c", "curl -s http://127.0.0.1:11434/api/tags"];
            fetchProcessOllama.running = true;
        }

        // MiniMax
        let minimaxKey = KeyStore.getKey("minimax");
        if (minimaxKey) {
            pendingFetches++;
            fetchProcessMiniMax.command = ["bash", "-c", "echo 'done'"];
            fetchProcessMiniMax.running = true;
        }

        // Hermes Agent (OpenAI-compatible local/remote gateway)
        let hermesKey = KeyStore.getKey("hermes");
        if (hermesKey) {
            if (startHermesModelFetch(true))
                pendingFetches++;
        } else {
            hermesFetchGeneration++;
            hermesConnectionState = "unconfigured";
            hermesConnectionMessage = "Enter the gateway API key to connect";
            replaceProviderModels([], "hermes");
        }

        if (pendingFetches === 0) {
            fetchingModels = false;
            runPendingModelRefresh();
        }
    }

    function createHermesModel(modelId) {
        return aiModelFactory.createObject(root, {
            name: modelId,
            icon: Qt.resolvedUrl("../../../assets/aiproviders/openai.svg"),
            description: "Hermes Agent",
            endpoint: normalizeHermesEndpoint(Config.ai.hermesEndpoint),
            model: modelId,
            provider: "hermes",
            requires_key: true,
            key_id: "API_SERVER_KEY"
        });
    }

    function publishHermesModels(modelIds) {
        let newModels = [];
        for (let i = 0; i < modelIds.length; i++) {
            let model = createHermesModel(modelIds[i]);
            if (model)
                newModels.push(model);
        }
        replaceProviderModels(newModels, "hermes");
    }

    function runPendingModelRefresh() {
        if (!modelRefreshPending)
            return;
        modelRefreshPending = false;
        Qt.callLater(() => fetchAvailableModels());
    }

    Process {
        id: fetchProcessGemini
        stdout: StdioCollector {
            id: fetchGeminiOut
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    let data = JSON.parse(fetchGeminiOut.text);
                    if (data.models) {
                        let newModels = [];
                        for (let i = 0; i < data.models.length; i++) {
                            let item = data.models[i];
                            let id = item.name.replace("models/", "");
                            if (id.includes("gemini") || id.includes("flash") || id.includes("pro")) {
                                let m = aiModelFactory.createObject(root, {
                                    name: item.displayName || id,
                                    icon: Qt.resolvedUrl("../../../assets/aiproviders/google.svg"),
                                    description: item.description || "Google Gemini Model",
                                    endpoint: "https://generativelanguage.googleapis.com/v1beta",
                                    model: id,
                                    provider: "gemini",
                                    requires_key: true,
                                    key_id: "GEMINI_API_KEY"
                                });
                                if (m) newModels.push(m);
                            }
                        }
                        mergeModels(newModels);
                    }
                } catch (e) {
                    console.log("Gemini fetch error: " + e);
                }
            }
            checkFetchCompletion();
        }
    }

    Process {
        id: fetchProcessOpenAI
        stdout: StdioCollector {
            id: fetchOpenAIOut
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    let data = JSON.parse(fetchOpenAIOut.text);
                    if (data.data) {
                        let newModels = [];
                        let allowed = ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-4", "o1", "o1-mini", "o1-preview", "o3-mini"];
                        for (let i = 0; i < data.data.length; i++) {
                            let item = data.data[i];
                            let id = item.id;
                            let isAllowed = false;
                            for (let j = 0; j < allowed.length; j++) {
                                if (id === allowed[j] || id.startsWith(allowed[j] + "-")) {
                                    isAllowed = true;
                                    break;
                                }
                            }
                            if (isAllowed) {
                                let m = aiModelFactory.createObject(root, {
                                    name: id,
                                    icon: Qt.resolvedUrl("../../../assets/aiproviders/openai.svg"),
                                    description: "OpenAI Model",
                                    endpoint: "https://api.openai.com",
                                    model: id,
                                    provider: "openai",
                                    requires_key: true,
                                    key_id: "OPENAI_API_KEY"
                                });
                                if (m) newModels.push(m);
                            }
                        }
                        mergeModels(newModels);
                    }
                } catch (e) {
                    console.log("OpenAI fetch error: " + e);
                }
            }
            checkFetchCompletion();
        }
    }

    Process {
        id: fetchProcessMistral
        stdout: StdioCollector {
            id: fetchMistralOut
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    let data = JSON.parse(fetchMistralOut.text);
                    if (data.data) {
                        let newModels = [];
                        for (let i = 0; i < data.data.length; i++) {
                            let item = data.data[i];
                            let id = item.id;
                            let m = aiModelFactory.createObject(root, {
                                name: id,
                                icon: Qt.resolvedUrl("../../../assets/aiproviders/mistral.svg"),
                                description: "Mistral Model",
                                endpoint: "https://api.mistral.ai/v1",
                                model: id,
                                provider: "mistral",
                                requires_key: true,
                                key_id: "MISTRAL_API_KEY"
                            });
                            if (m) newModels.push(m);
                        }
                        mergeModels(newModels);
                    }
                } catch (e) {
                    console.log("Mistral fetch error: " + e);
                }
            }
            checkFetchCompletion();
        }
    }

    Process {
        id: fetchProcessGroq
        stdout: StdioCollector {
            id: fetchGroqOut
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    let data = JSON.parse(fetchGroqOut.text);
                    if (data.data) {
                        let newModels = [];
                        for (let i = 0; i < data.data.length; i++) {
                            let item = data.data[i];
                            let id = item.id;
                            let m = aiModelFactory.createObject(root, {
                                name: id,
                                icon: Qt.resolvedUrl("../../../assets/aiproviders/groq.svg"),
                                description: "Groq Model",
                                endpoint: "https://api.groq.com/openai/v1",
                                model: id,
                                provider: "groq",
                                requires_key: true,
                                key_id: "GROQ_API_KEY"
                            });
                            if (m) newModels.push(m);
                        }
                        mergeModels(newModels);
                    }
                } catch (e) {
                    console.log("Groq fetch error: " + e);
                }
            }
            checkFetchCompletion();
        }
    }

    Process {
        id: fetchProcessAnthropic
        stdout: StdioCollector {
            id: fetchAnthropicOut
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    let data = JSON.parse(fetchAnthropicOut.text);
                    if (data.data) {
                        let newModels = [];
                        for (let i = 0; i < data.data.length; i++) {
                            let item = data.data[i];
                            let id = item.id;
                            let m = aiModelFactory.createObject(root, {
                                name: item.display_name || id,
                                icon: Qt.resolvedUrl("../../../assets/aiproviders/anthropic.svg"),
                                description: item.description || "Anthropic Model",
                                endpoint: "https://api.anthropic.com/v1/messages",
                                model: id,
                                provider: "anthropic",
                                requires_key: true,
                                key_id: "ANTHROPIC_API_KEY"
                            });
                            if (m) newModels.push(m);
                        }
                        mergeModels(newModels);
                    }
                } catch (e) {
                    console.log("Anthropic fetch error: " + e);
                }
            }
            checkFetchCompletion();
        }
    }

    Process {
        id: fetchProcessOllama
        stdout: StdioCollector {
            id: fetchOllamaOut
        }
        onExited: exitCode => {
            if (exitCode === 0) {
                try {
                    let data = JSON.parse(fetchOllamaOut.text);
                    if (data.models) {
                        let newModels = [];
                        for (let i = 0; i < data.models.length; i++) {
                            let item = data.models[i];
                            let m = aiModelFactory.createObject(root, {
                                name: item.name,
                                icon: Qt.resolvedUrl("../../../assets/aiproviders/ollama.svg"),
                                description: "Local Ollama Model",
                                endpoint: "http://127.0.0.1:11434",
                                model: item.name,
                                provider: "ollama",
                                requires_key: false
                            });
                            if (m) newModels.push(m);
                        }
                        mergeModels(newModels);
                    }
                } catch (e) {
                    console.log("Ollama fetch error: " + e);
                }
            }
            checkFetchCompletion();
        }
    }

    Process {
        id: fetchProcessMiniMax
        onExited: exitCode => {
            if (exitCode === 0) {
                let newModels = [];
                
                let models = [
                    { name: "MiniMax-M2.7", model: "MiniMax-M2.7", description: "Latest model with recursive self-improvement, SOTA coding capabilities", endpoint: "https://api.minimax.io" },
                    { name: "MiniMax-M2.7-highspeed", model: "MiniMax-M2.7-highspeed", description: "Same performance as M2.7, faster inference (~100 tps)", endpoint: "https://api.minimax.io" },
                    { name: "MiniMax-M2.5", model: "MiniMax-M2.5", description: "Peak performance, ultimate value, master the complex", endpoint: "https://api.minimax.io" },
                    { name: "MiniMax-M2.5-highspeed", model: "MiniMax-M2.5-highspeed", description: "Same performance as M2.5, faster inference (~100 tps)", endpoint: "https://api.minimax.io" },
                    { name: "MiniMax-M2.1", model: "MiniMax-M2.1", description: "Powerful multi-language programming, enhanced reasoning", endpoint: "https://api.minimax.io" },
                    { name: "MiniMax-M2.1-highspeed", model: "MiniMax-M2.1-highspeed", description: "Same performance as M2.1, faster inference (~100 tps)", endpoint: "https://api.minimax.io" },
                    { name: "MiniMax-M2", model: "MiniMax-M2", description: "Agentic capabilities, advanced reasoning, 200k context", endpoint: "https://api.minimax.io" },
                    { name: "M2-her", model: "M2-her", description: "Role-playing, multi-turn conversations, emotional expression", endpoint: "https://api.minimax.io" }
                ];
                
                for (let i = 0; i < models.length; i++) {
                    let item = models[i];
                    let m = aiModelFactory.createObject(root, {
                        name: item.name,
                        icon: Qt.resolvedUrl("../../../assets/aiproviders/minimax.svg"),
                        description: item.description,
                        endpoint: item.endpoint,
                        model: item.model,
                        provider: "minimax",
                        requires_key: true,
                        key_id: "MINIMAX_API_KEY"
                    });
                    if (m) newModels.push(m);
                }
                
                mergeModels(newModels);
            }
            checkFetchCompletion();
        }
    }

    Process {
        id: fetchProcessHermes
        stdout: StdioCollector {
            id: fetchHermesOut
        }
        stderr: StdioCollector {
            id: fetchHermesErr
        }
        onExited: exitCode => {
            let completedGeneration = hermesRunningGeneration;
            let countsTowardRefresh = hermesFetchCountsTowardRefresh;
            hermesFetchCountsTowardRefresh = false;
            let parsed = HermesConfig.parseModelsResponse(fetchHermesOut.text);
            let discovered = parsed.modelIds;
            let connectionState = "error";
            let connectionMessage = "";
            if (exitCode === 0) {
                if (discovered.length > 0) {
                    connectionState = "connected";
                    connectionMessage = "Connected · " + discovered.length
                        + (discovered.length === 1 ? " model" : " models");
                } else {
                    connectionMessage = parsed.error;
                }
            } else {
                connectionMessage = HermesConfig.connectionError(
                    exitCode, fetchHermesErr.text, fetchHermesOut.text);
            }
            if (discovered.length === 0)
                discovered.push("hermes-agent");
            Qt.callLater(() => {
                if (completedGeneration === hermesFetchGeneration) {
                    hermesConnectionState = connectionState;
                    hermesConnectionMessage = connectionMessage;
                    publishHermesModels(discovered);
                }
                if (countsTowardRefresh)
                    checkFetchCompletion();
            });
        }
    }


    function checkFetchCompletion() {
        pendingFetches--;
        if (pendingFetches <= 0) {
            fetchingModels = false;
            pendingFetches = 0;

            tryRestore();

            if (!currentModel && models.length > 0) {
                currentModel = models[0];
                isRestored = true;
            } else if (!isRestored && currentModel) {
                isRestored = true;
            }
            runPendingModelRefresh();
        }
    }

    function mergeModels(newModels) {
        let updatedList = [];
        for (let i = 0; i < models.length; i++)
            updatedList.push(models[i]);

        for (let i = 0; i < newModels.length; i++) {
            let m = newModels[i];
            let isDuplicate = false;
            for (let j = 0; j < updatedList.length; j++) {
                if (updatedList[j].model === m.model) {
                    isDuplicate = true;
                    break;
                }
            }
            if (!isDuplicate)
                updatedList.push(m);
        }

        models = updatedList;

        if (!isRestored)
            tryRestore();
    }

    function replaceProviderModels(newModels, provider) {
        let updatedList = [];
        let existingProviderModels = [];
        for (let i = 0; i < models.length; i++) {
            if (models[i].provider === provider)
                existingProviderModels.push(models[i]);
            else
                updatedList.push(models[i]);
        }

        // Reuse matching objects so a catalog refresh does not fire
        // onCurrentModelChanged and cancel an in-flight response.
        let providerModels = [];
        let supersededModels = [];
        for (let i = 0; i < newModels.length; i++) {
            let incoming = newModels[i];
            let existing = null;
            for (let j = 0; j < existingProviderModels.length; j++) {
                if (incoming.model === existingProviderModels[j].model) {
                    existing = existingProviderModels[j];
                    break;
                }
            }
            if (existing) {
                existing.name = incoming.name;
                existing.icon = incoming.icon;
                existing.description = incoming.description;
                existing.endpoint = incoming.endpoint;
                existing.requires_key = incoming.requires_key;
                existing.key_id = incoming.key_id;
                providerModels.push(existing);
                supersededModels.push(incoming);
            } else {
                providerModels.push(incoming);
            }
        }
        for (let i = 0; i < providerModels.length; i++)
            updatedList.push(providerModels[i]);

        let currentBelongsToProvider = currentModel && currentModel.provider === provider;
        let currentStillPresent = currentBelongsToProvider
            && providerModels.indexOf(currentModel) !== -1;
        let previousModelId = currentBelongsToProvider ? currentModel.model : "";
        models = updatedList;
        if (currentBelongsToProvider && !currentStillPresent) {
            let replacement = null;
            for (let i = 0; i < providerModels.length; i++) {
                if (providerModels[i].model === previousModelId) {
                    replacement = providerModels[i];
                    break;
                }
            }
            currentModel = replacement || (providerModels.length > 0 ? providerModels[0]
                : (updatedList.length > 0 ? updatedList[0] : null));
        }
        for (let i = 0; i < existingProviderModels.length; i++) {
            if (providerModels.indexOf(existingProviderModels[i]) === -1)
                existingProviderModels[i].destroy();
        }
        for (let i = 0; i < supersededModels.length; i++)
            supersededModels[i].destroy();
        if (!isRestored)
            tryRestore();
    }

    // Signals
    signal chatModelChanged
    signal historyModelChanged
    signal modelSelectionRequested

    Component {
        id: aiModelFactory
        AiModel {}
    }

    Component {
        id: aiMessageFactory
        AiMessageData {}
    }

    Component {
        id: requestBodyFileFactory
        FileView {
            id: requestBodyFile
            required property var payload
            property bool completed: false
            printErrors: false
            onSaved: root.completeBodyWrite(requestBodyFile, "")
            onSaveFailed: error => root.completeBodyWrite(requestBodyFile, "Failed to write request body: " + error)
        }
    }
}
