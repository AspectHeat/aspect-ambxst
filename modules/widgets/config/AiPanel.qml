import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

Item {
    id: root

    property int maxContentWidth: 480
    readonly property int contentWidth: Math.min(width, maxContentWidth)
    readonly property real sideMargin: Math.max(0, (width - contentWidth) / 2)

    function providerStatusText(provider) {
        if (provider !== "hermes")
            return KeyStore.hasKey(provider) ? "Key Configured" : "Not Configured";
        if (Ai.hermesConnectionState === "connected")
            return "Connected";
        if (Ai.hermesConnectionState === "checking")
            return "Checking…";
        if (Ai.hermesConnectionState === "error")
            return "Connection Failed";
        return "Not Configured";
    }

    function providerStatusColor(provider) {
        if (provider === "hermes" && Ai.hermesConnectionState === "error")
            return Colors.error;
        if (provider === "hermes" && Ai.hermesConnectionState === "checking")
            return Colors.primary;
        return KeyStore.hasKey(provider) ? Colors.success : Colors.overSurfaceVariant;
    }

    component LegibleTextField: TextField {
        id: field

        property string hintText: ""
        property string accessibleName: hintText

        placeholderText: ""
        color: Colors.overSurface
        selectionColor: Colors.primary
        selectedTextColor: Colors.overPrimary
        palette.text: Colors.overSurface
        palette.placeholderText: Colors.overSurfaceVariant
        palette.highlight: Colors.primary
        palette.highlightedText: Colors.overPrimary
        Accessible.name: accessibleName
        Accessible.description: hintText

        Text {
            anchors.fill: parent
            anchors.leftMargin: field.leftPadding
            anchors.rightMargin: field.rightPadding
            z: 10

            visible: field.length === 0 && field.preeditText.length === 0
            text: field.hintText
            color: Colors.overSurfaceVariant
            font: field.font
            horizontalAlignment: field.effectiveHorizontalAlignment
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: contentColumn.implicitHeight + 40
        clip: true
        bottomMargin: 40

        ColumnLayout {
            id: contentColumn
            width: root.contentWidth
            x: root.sideMargin
            y: 20
            spacing: 24

            Text {
                text: "AI & API Keys"
                font.family: Config.theme.font
                font.pixelSize: 24
                font.weight: Font.Bold
                color: Colors.overSurface
                Layout.fillWidth: true
                Layout.bottomMargin: 8
            }

            // Providers
            Repeater {
                model: ["gemini", "openai", "anthropic", "mistral", "groq", "ollama", "minimax", "hermes"]
                delegate: StyledRect {
                    required property string modelData
                    Layout.fillWidth: true
                    variant: "surface"
                    radius: Styling.radius(8)
                    
                    // We need a wrapper to give it a height based on content
                    implicitHeight: providerCol.implicitHeight + 32

                    ColumnLayout {
                        id: providerCol
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        RowLayout {
                            Layout.fillWidth: true
                            Text {
                                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                font.family: Config.theme.font
                                font.pixelSize: 16
                                font.weight: Font.Bold
                                color: Colors.overSurface
                                Layout.fillWidth: true
                            }
                            Text {
                                text: root.providerStatusText(modelData)
                                font.family: Config.theme.font
                                font.pixelSize: 12
                                color: root.providerStatusColor(modelData)
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            LegibleTextField {
                                visible: modelData !== "ollama"
                                id: keyInput
                                Layout.fillWidth: true
                                hintText: "Enter API Key..."
                                accessibleName: modelData.charAt(0).toUpperCase() + modelData.slice(1) + " API key"
                                echoMode: TextInput.Password
                                font.family: Config.theme.font
                                padding: 6
                                
                                background: StyledRect {
                                    variant: "internalbg"
                                    radius: Styling.radius(4)
                                    border.width: keyInput.activeFocus ? 2 : 0
                                    border.color: Styling.srItem("primary")
                                    anchors.fill: parent
                                    anchors.leftMargin: -parent.padding
                                    anchors.rightMargin: -parent.padding
                                    anchors.topMargin: -parent.padding
                                    anchors.bottomMargin: -parent.padding
                                }
                            }
                            Button {
                                id: saveButton
                                text: modelData === "ollama"
                                    ? (KeyStore.hasKey("ollama") ? "Configured" : "Enable")
                                    : (modelData === "hermes" ? "Save & Test" : "Save")
                                visible: modelData === "ollama" ? !KeyStore.hasKey("ollama") : true
                                hoverEnabled: true
                                leftPadding: 6
                                rightPadding: 6
                                topPadding: 4
                                bottomPadding: 4
                                onClicked: {
                                    if (modelData === "ollama") {
                                        KeyStore.setKey("ollama", "enabled")
                                    } else if (keyInput.text !== "") {
                                        if (modelData === "hermes")
                                            Ai.prepareHermesKeySave();
                                        KeyStore.setKey(modelData, keyInput.text)
                                        keyInput.text = ""
                                    }
                                }
                                background: StyledRect {
                                    variant: saveButton.down ? "overprimary" : (saveButton.hovered ? "primaryfocus" : "primary")
                                    radius: Styling.radius(4)
                                }
                                contentItem: Item {
                                    implicitWidth: saveButtonLabel.implicitWidth + saveButton.leftPadding + saveButton.rightPadding
                                    implicitHeight: saveButtonLabel.implicitHeight + saveButton.topPadding + saveButton.bottomPadding

                                    Text {
                                        id: saveButtonLabel
                                        text: saveButton.text
                                        color: Colors.overPrimary
                                        font.family: Config.theme.font
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        anchors.fill: parent
                                        anchors.leftMargin: saveButton.leftPadding
                                        anchors.rightMargin: saveButton.rightPadding
                                        anchors.topMargin: saveButton.topPadding
                                        anchors.bottomMargin: saveButton.bottomPadding
                                    }
                                }
                            }
                            Button {
                                id: clearButton
                                visible: KeyStore.hasKey(modelData)
                                text: modelData === "ollama" ? "Disable" : "Clear"
                                leftPadding: 6
                                rightPadding: 6
                                topPadding: 4
                                bottomPadding: 4
                                onClicked: KeyStore.deleteKey(modelData)
                                background: StyledRect {
                                    variant: "error"
                                    radius: Styling.radius(4)
                                }
                                contentItem: Item {
                                    implicitWidth: clearButtonLabel.implicitWidth + clearButton.leftPadding + clearButton.rightPadding
                                    implicitHeight: clearButtonLabel.implicitHeight + clearButton.topPadding + clearButton.bottomPadding

                                    Text {
                                        id: clearButtonLabel
                                        text: clearButton.text
                                        color: Colors.overError
                                        font.family: Config.theme.font
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        anchors.fill: parent
                                        anchors.leftMargin: clearButton.leftPadding
                                        anchors.rightMargin: clearButton.rightPadding
                                        anchors.topMargin: clearButton.topPadding
                                        anchors.bottomMargin: clearButton.bottomPadding
                                    }
                                }
                            }
                        }

                        Text {
                            visible: modelData === "hermes"
                            text: "Hermes API Endpoint"
                            font.family: Config.theme.font
                            font.pixelSize: 12
                            color: Colors.overSurfaceVariant
                        }

                        LegibleTextField {
                            id: hermesEndpointInput
                            visible: modelData === "hermes"
                            Layout.fillWidth: true
                            text: modelData === "hermes" ? Config.ai.hermesEndpoint : ""
                            hintText: "http://127.0.0.1:8642/v1"
                            accessibleName: "Hermes API endpoint"
                            font.family: Config.theme.font
                            padding: 6

                            onEditingFinished: {
                                let normalized = Ai.normalizeHermesEndpoint(text);
                                text = normalized;
                                Config.ai.hermesEndpoint = normalized;
                                Ai.testHermesConnection();
                            }

                            background: StyledRect {
                                variant: "internalbg"
                                radius: Styling.radius(4)
                                border.width: hermesEndpointInput.activeFocus ? 2 : 0
                                border.color: Styling.srItem("primary")
                                anchors.fill: parent
                                anchors.leftMargin: -parent.padding
                                anchors.rightMargin: -parent.padding
                                anchors.topMargin: -parent.padding
                                anchors.bottomMargin: -parent.padding
                            }
                        }

                        Text {
                            visible: modelData === "hermes"
                            Layout.fillWidth: true
                            text: "Start the Hermes gateway, then enter its API_SERVER_KEY above. "
                                + "Local default: http://127.0.0.1:8642/v1"
                            wrapMode: Text.WordWrap
                            font.family: Config.theme.font
                            font.pixelSize: 11
                            color: Colors.overSurfaceVariant
                        }

                        RowLayout {
                            visible: modelData === "hermes"
                            Layout.fillWidth: true
                            spacing: 12

                            Button {
                                id: hermesTestButton
                                text: Ai.hermesConnectionState === "checking" ? "Checking…" : "Test Connection"
                                enabled: KeyStore.hasKey("hermes") && Ai.hermesConnectionState !== "checking"
                                hoverEnabled: enabled
                                leftPadding: 8
                                rightPadding: 8
                                topPadding: 4
                                bottomPadding: 4
                                onClicked: {
                                    let normalized = Ai.normalizeHermesEndpoint(hermesEndpointInput.text);
                                    hermesEndpointInput.text = normalized;
                                    Config.ai.hermesEndpoint = normalized;
                                    Ai.testHermesConnection();
                                }
                                background: StyledRect {
                                    variant: hermesTestButton.enabled
                                        ? (hermesTestButton.down ? "overprimary"
                                            : (hermesTestButton.hovered ? "primaryfocus" : "primary"))
                                        : "internalbg"
                                    radius: Styling.radius(4)
                                }
                                contentItem: Text {
                                    text: hermesTestButton.text
                                    color: hermesTestButton.enabled ? Colors.overPrimary : Colors.overSurfaceVariant
                                    font.family: Config.theme.font
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            Text {
                                Layout.fillWidth: true
                                text: Ai.hermesConnectionMessage
                                wrapMode: Text.WordWrap
                                font.family: Config.theme.font
                                font.pixelSize: 12
                                color: Ai.hermesConnectionState === "connected"
                                    ? Colors.success
                                    : (Ai.hermesConnectionState === "error"
                                        ? Colors.error : Colors.overSurfaceVariant)
                            }
                        }
                    }
                }
            }
            
            // Custom Provider
            Text {
                text: "Custom Provider"
                font.family: Config.theme.font
                font.pixelSize: 20
                font.weight: Font.Bold
                color: Colors.overSurface
                Layout.fillWidth: true
                Layout.topMargin: 16
                Layout.bottomMargin: 8
            }
            
            StyledRect {
                Layout.fillWidth: true
                variant: "surface"
                radius: Styling.radius(8)
                implicitHeight: customCol.implicitHeight + 32

                ColumnLayout {
                    id: customCol
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Custom Provider API Key"
                            font.family: Config.theme.font
                            font.pixelSize: 14
                            font.weight: Font.Bold
                            color: Colors.overSurface
                            Layout.fillWidth: true
                        }
                        Text {
                            text: KeyStore.hasKey("custom") ? "Key Configured" : "Not Configured"
                            font.family: Config.theme.font
                            font.pixelSize: 12
                            color: KeyStore.hasKey("custom") ? Colors.success : Colors.overSurfaceVariant
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        LegibleTextField {
                            id: customKeyInput
                            Layout.fillWidth: true
                            hintText: "Enter API Key..."
                            accessibleName: "Custom provider API key"
                            echoMode: TextInput.Password
                            font.family: Config.theme.font
                            padding: 6
                            
                            background: StyledRect {
                                variant: "internalbg"
                                radius: Styling.radius(4)
                                border.width: customKeyInput.activeFocus ? 2 : 0
                                border.color: Styling.srItem("primary")
                                anchors.fill: parent
                                anchors.leftMargin: -parent.padding
                                anchors.rightMargin: -parent.padding
                                anchors.topMargin: -parent.padding
                                anchors.bottomMargin: -parent.padding
                            }
                        }
                        Button {
                            id: customSaveButton
                            text: "Save"
                            hoverEnabled: true
                            leftPadding: 6
                            rightPadding: 6
                            topPadding: 4
                            bottomPadding: 4
                            onClicked: {
                                if (customKeyInput.text !== "") {
                                    KeyStore.setKey("custom", customKeyInput.text)
                                    customKeyInput.text = ""
                                }
                            }
                            background: StyledRect {
                                variant: customSaveButton.down ? "overprimary" : (customSaveButton.hovered ? "primaryfocus" : "primary")
                                radius: Styling.radius(4)
                            }
                            contentItem: Item {
                                implicitWidth: customSaveButtonLabel.implicitWidth + customSaveButton.leftPadding + customSaveButton.rightPadding
                                implicitHeight: customSaveButtonLabel.implicitHeight + customSaveButton.topPadding + customSaveButton.bottomPadding

                                Text {
                                    id: customSaveButtonLabel
                                    text: customSaveButton.text
                                    color: Colors.overPrimary
                                    font.family: Config.theme.font
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    anchors.fill: parent
                                    anchors.leftMargin: customSaveButton.leftPadding
                                    anchors.rightMargin: customSaveButton.rightPadding
                                    anchors.topMargin: customSaveButton.topPadding
                                    anchors.bottomMargin: customSaveButton.bottomPadding
                                }
                            }
                        }
                        Button {
                            id: customClearButton
                            visible: KeyStore.hasKey("custom")
                            text: "Clear"
                            leftPadding: 6
                            rightPadding: 6
                            topPadding: 4
                            bottomPadding: 4
                            onClicked: KeyStore.deleteKey("custom")
                            background: StyledRect {
                                variant: "error"
                                radius: Styling.radius(4)
                            }
                            contentItem: Item {
                                implicitWidth: customClearButtonLabel.implicitWidth + customClearButton.leftPadding + customClearButton.rightPadding
                                implicitHeight: customClearButtonLabel.implicitHeight + customClearButton.topPadding + customClearButton.bottomPadding

                                Text {
                                    id: customClearButtonLabel
                                    text: customClearButton.text
                                    color: Colors.overError
                                    font.family: Config.theme.font
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    anchors.fill: parent
                                    anchors.leftMargin: customClearButton.leftPadding
                                    anchors.rightMargin: customClearButton.rightPadding
                                    anchors.topMargin: customClearButton.topPadding
                                    anchors.bottomMargin: customClearButton.bottomPadding
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Colors.outline
                        opacity: 0.2
                        Layout.topMargin: 8
                        Layout.bottomMargin: 8
                    }

                    Text {
                        text: "Custom Endpoint"
                        font.family: Config.theme.font
                        font.pixelSize: 14
                        color: Colors.overSurface
                    }
                    
                    LegibleTextField {
                        id: endpointInput
                        Layout.fillWidth: true
                        text: Config.ai.customEndpoint
                        hintText: "e.g. https://api.example.com/v1/chat/completions"
                        accessibleName: "Custom provider endpoint"
                        font.family: Config.theme.font
                        padding: 6
                        
                        onEditingFinished: Config.ai.customEndpoint = text.trim()
                        
                        background: StyledRect {
                            variant: "internalbg"
                            radius: Styling.radius(4)
                            border.width: endpointInput.activeFocus ? 2 : 0
                            border.color: Styling.srItem("primary")
                            anchors.fill: parent
                            anchors.leftMargin: -parent.padding
                            anchors.rightMargin: -parent.padding
                            anchors.topMargin: -parent.padding
                            anchors.bottomMargin: -parent.padding
                        }
                    }

                    Text {
                        text: "Custom cURL Template"
                        font.family: Config.theme.font
                        font.pixelSize: 14
                        color: Colors.overSurface
                        Layout.topMargin: 8
                    }
                    
                    Text {
                        text: "Placeholders: {{ENDPOINT}}, {{API_KEY}}, {{BODY_PATH}}"
                        font.family: Config.theme.font
                        font.pixelSize: 12
                        color: Colors.overSurfaceVariant
                    }
                    
                    LegibleTextField {
                        id: curlInput
                        Layout.fillWidth: true
                        text: Config.ai.customCurlTemplate
                        hintText: "curl -X POST {{ENDPOINT}} -H 'Authorization: Bearer {{API_KEY}}' -d @{{BODY_PATH}}"
                        accessibleName: "Custom provider cURL template"
                        font.family: "Monospace"
                        padding: 6
                        
                        onEditingFinished: Config.ai.customCurlTemplate = text
                        
                        background: StyledRect {
                            variant: "internalbg"
                            radius: Styling.radius(4)
                            border.width: curlInput.activeFocus ? 2 : 0
                            border.color: Styling.srItem("primary")
                            anchors.fill: parent
                            anchors.leftMargin: -parent.padding
                            anchors.rightMargin: -parent.padding
                            anchors.topMargin: -parent.padding
                            anchors.bottomMargin: -parent.padding
                        }
                    }
                }
            }
        }
    }
}
