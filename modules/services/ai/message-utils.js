.pragma library

function cloneValue(value) {
    if (value === undefined)
        return undefined;
    return JSON.parse(JSON.stringify(value));
}

function hasOwn(object, key) {
    return object !== null && object !== undefined && Object.prototype.hasOwnProperty.call(object, key);
}

function _copyOptional(output, source, key, value, meaningful) {
    if (hasOwn(source, key) || meaningful) {
        if (value !== undefined && value !== null)
            output[key] = cloneValue(value);
        else
            delete output[key];
    }
}

function serializeMessage(message) {
    let source = cloneValue(message.sourceData || {}) || {};
    let output = source;

    output.role = message.role || "assistant";
    output.content = message.content || "";

    _copyOptional(output, source, "rawContent", message.rawContent,
        message.rawContent !== "" && message.rawContent !== message.content);
    _copyOptional(output, source, "model", message.model, message.model !== "");
    _copyOptional(output, source, "name", message.name, message.name !== "");
    _copyOptional(output, source, "attachments", message.attachments,
        Array.isArray(message.attachments) && message.attachments.length > 0);
    _copyOptional(output, source, "geminiParts", message.geminiParts,
        Array.isArray(message.geminiParts) && message.geminiParts.length > 0);
    _copyOptional(output, source, "functionCall", message.functionCall,
        message.functionCall !== undefined && message.functionCall !== null);
    _copyOptional(output, source, "functionPending", message.functionPending,
        message.functionCall !== undefined && message.functionCall !== null);
    _copyOptional(output, source, "functionApproved", message.functionApproved,
        message.functionCall !== undefined && message.functionCall !== null);
    _copyOptional(output, source, "fileMimeType", message.fileMimeType, message.fileMimeType !== "");
    _copyOptional(output, source, "fileUri", message.fileUri, message.fileUri !== "");
    _copyOptional(output, source, "localFilePath", message.localFilePath, message.localFilePath !== "");
    _copyOptional(output, source, "functionName", message.functionName, message.functionName !== "");
    _copyOptional(output, source, "functionResponse", message.functionResponse, message.functionResponse !== "");
    _copyOptional(output, source, "annotations", message.annotations,
        message.annotations !== undefined && message.annotations !== null);
    _copyOptional(output, source, "annotationSources", message.annotationSources,
        message.annotationSources !== undefined && message.annotationSources !== null);
    _copyOptional(output, source, "searchQueries", message.searchQueries,
        message.searchQueries !== undefined && message.searchQueries !== null);
    _copyOptional(output, source, "visibleToUser", message.visibleToUser,
        message.visibleToUser === false);

    delete output.done;
    delete output.thinking;
    delete output.toolStatus;
    delete output.blocks;
    delete output.sourceData;
    return output;
}

function messageForApi(message) {
    let serialized = serializeMessage(message);
    let output = {
        role: serialized.role,
        content: message.rawContent || serialized.content
    };
    let keys = [
        "attachments", "geminiParts", "functionCall", "name",
        "functionName", "functionResponse", "fileMimeType", "fileUri",
        "localFilePath", "annotations", "annotationSources", "searchQueries"
    ];
    for (let i = 0; i < keys.length; i++) {
        let key = keys[i];
        if (hasOwn(serialized, key))
            output[key] = cloneValue(serialized[key]);
    }
    return output;
}
