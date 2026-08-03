import QtQuick
import "markdown.js" as Markdown

QtObject {
    property string messageId: ""
    property string role: "assistant"
    property string content: ""
    property string rawContent: ""
    property bool done: true
    property bool thinking: false
    property string model: ""
    property var functionCall
    property bool functionPending: false
    property bool functionApproved: false
    property string name: ""
    property var attachments
    property var geminiParts
    property string fileMimeType: ""
    property string fileUri: ""
    property string localFilePath: ""
    property string functionName: ""
    property string functionResponse: ""
    property var annotations
    property var annotationSources
    property var searchQueries
    property bool visibleToUser: true
    property string toolStatus: ""
    property var sourceData: ({})
    // Streaming text changes at up to 20 Hz. Replacing the block array on every
    // flush tears down and recreates the entire Loader tree in the sidebar.
    // Build rich blocks once the response is complete (and again only for later
    // edits to a completed message).
    property var blocks: done
        ? Markdown.splitMarkdownBlocks(rawContent !== "" ? rawContent : content)
        : []
}
