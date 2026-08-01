.pragma library

function _pushBlock(blocks, type, content, language, unfinished) {
    if (type === "text" && content === "")
        return;

    if (type === "text" && blocks.length > 0 && blocks[blocks.length - 1].type === "text") {
        blocks[blocks.length - 1].content += content;
        return;
    }

    blocks.push({
        type: type,
        content: content,
        language: language || "",
        unfinished: unfinished === true
    });
}

function _lineEnd(text, start) {
    let newline = text.indexOf("\n", start);
    return newline === -1 ? text.length : newline;
}

function _parseFenceOpening(line) {
    let match = line.match(/^ {0,3}(`{3,}|~{3,})(.*)$/);
    if (!match)
        return null;

    let tail = match[2].trim();
    let language = "text";
    let inlineContent = "";
    if (tail !== "") {
        let split = tail.search(/\s/);
        if (split === -1) {
            language = tail;
        } else {
            language = tail.substring(0, split);
            inlineContent = tail.substring(split).trimStart();
        }
    }

    return {
        marker: match[1][0],
        length: match[1].length,
        language: language,
        inlineContent: inlineContent
    };
}

function splitMarkdownBlocks(value) {
    let text = value === undefined || value === null ? "" : String(value);
    let blocks = [];
    let textStart = 0;
    let position = 0;

    while (position < text.length) {
        let atLineStart = position === 0 || text[position - 1] === "\n";
        if (atLineStart) {
            let openingEnd = _lineEnd(text, position);
            let opening = _parseFenceOpening(text.substring(position, openingEnd));
            if (opening) {
                _pushBlock(blocks, "text", text.substring(textStart, position), "", false);

                let codeStart = openingEnd < text.length ? openingEnd + 1 : openingEnd;
                let codePrefix = opening.inlineContent;
                let cursor = codeStart;
                let closingStart = -1;
                let closingEnd = -1;

                while (cursor <= text.length) {
                    let end = _lineEnd(text, cursor);
                    let line = text.substring(cursor, end);
                    let closeMatch = line.match(/^ {0,3}(`{3,}|~{3,})\s*$/);
                    if (closeMatch && closeMatch[1][0] === opening.marker && closeMatch[1].length >= opening.length) {
                        closingStart = cursor;
                        closingEnd = end < text.length ? end + 1 : end;
                        break;
                    }
                    if (end === text.length)
                        break;
                    cursor = end + 1;
                }

                let bodyEnd = closingStart === -1 ? text.length : closingStart;
                let body = text.substring(codeStart, bodyEnd);
                if (codePrefix !== "")
                    body = codePrefix + (body !== "" ? "\n" + body : "");
                if (body.endsWith("\n"))
                    body = body.substring(0, body.length - 1);

                _pushBlock(blocks, "code", body, opening.language, closingStart === -1);
                if (closingStart === -1) {
                    position = text.length;
                    textStart = text.length;
                } else {
                    position = closingEnd;
                    textStart = closingEnd;
                }
                continue;
            }
        }

        if (text.startsWith("<think>", position)) {
            _pushBlock(blocks, "text", text.substring(textStart, position), "", false);
            let thinkStart = position + 7;
            let thinkEnd = text.indexOf("</think>", thinkStart);
            if (thinkEnd === -1) {
                _pushBlock(blocks, "think", text.substring(thinkStart), "", true);
                position = text.length;
                textStart = text.length;
            } else {
                _pushBlock(blocks, "think", text.substring(thinkStart, thinkEnd), "", false);
                position = thinkEnd + 8;
                textStart = position;
            }
            continue;
        }

        position++;
    }

    _pushBlock(blocks, "text", text.substring(textStart), "", false);
    if (blocks.length === 0)
        _pushBlock(blocks, "text", "", "", false);
    return blocks;
}

function displayContent(value) {
    let text = value === undefined || value === null ? "" : String(value);
    let parsed = splitMarkdownBlocks(text);
    let hasThinking = parsed.some(block => block.type === "think");
    if (!hasThinking)
        return text;

    let output = "";
    for (let i = 0; i < parsed.length; i++) {
        let block = parsed[i];
        if (block.type === "text") {
            output += block.content;
        } else if (block.type === "code") {
            let fence = "```" + (block.language && block.language !== "text" ? block.language : "");
            output += fence + "\n" + block.content;
            if (!block.unfinished)
                output += "\n```";
        }
    }
    return output;
}
