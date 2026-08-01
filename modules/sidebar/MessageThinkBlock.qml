import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.config
import qs.modules.components
import qs.modules.theme

StyledRect {
    id: root

    property string content: ""
    property bool unfinished: false
    property bool expanded: unfinished

    Layout.fillWidth: true
    implicitHeight: thinkColumn.implicitHeight + 16
    variant: "internalbg"
    radius: Styling.radius(4)

    ColumnLayout {
        id: thinkColumn
        anchors.fill: parent
        anchors.margins: 8
        spacing: 6

        Button {
            Layout.fillWidth: true
            flat: true
            padding: 0

            contentItem: RowLayout {
                spacing: 6

                Text {
                    text: root.unfinished ? "Reasoning…" : "Reasoning"
                    color: Colors.outline
                    font.family: Config.theme.font
                    font.pixelSize: 12
                    font.weight: Font.Bold
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: root.expanded ? Icons.caretUp : Icons.caretDown
                    color: Colors.outline
                    font.family: Icons.font
                    font.pixelSize: 12
                }
            }

            background: null
            onClicked: root.expanded = !root.expanded
        }

        TextEdit {
            Layout.fillWidth: true
            visible: root.expanded
            text: root.content
            textFormat: Text.MarkdownText
            color: Colors.outline
            font.family: Config.theme.font
            font.pixelSize: 13
            readOnly: true
            selectByMouse: true
            wrapMode: Text.Wrap
            onLinkActivated: link => Qt.openUrlExternally(link)
        }
    }
}
