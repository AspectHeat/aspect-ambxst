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
    property var blocks: Markdown.splitMarkdownBlocks(rawContent !== "" ? rawContent : content)
}
