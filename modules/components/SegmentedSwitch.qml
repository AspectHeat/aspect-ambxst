pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.modules.theme
import qs.config

// A segmented switch with sliding highlight, similar to iOS segmented control
StyledRect {
    id: root
    variant: "common"
    radius: Styling.radius(-4)

    // Model: array of { icon: "...", tooltip: "..." } or just strings for text labels
    property var options: []
    property int currentIndex: 0
    property int buttonSize: 28
    property int spacing: 2
    property int padding: 2

    signal indexChanged(int index)

    // Every segment is this wide - the widest segment's content sets it for all of them.
    // This file describes itself as an iOS-style segmented control, and equal segments are
    // most of what that means; sizing each one to its own label made "Standard" half again
    // as wide as "P2P" and the sliding highlight lopsided with it. Uniform is also what
    // makes `fillWidth` split surplus evenly: QQuickLinearLayout distributes extra space in
    // proportion to each item's preferred width, so unequal preferences stay unequal no
    // matter how wide the control gets.
    property int segmentWidth: buttonSize

    // Recomputed from the live items rather than from `options`, because the width that
    // matters is the rendered text's, which depends on the font. Driven by the segments'
    // own naturalWidth changes and by the Repeater's count, so it settles for both a
    // changed option set and a font or icon that resolves late.
    function updateSegmentWidth(): void {
        let widest = root.buttonSize;
        for (let i = 0; i < repeater.count; i++) {
            const segment = repeater.itemAt(i);
            if (segment)
                widest = Math.max(widest, segment.naturalWidth);
        }
        root.segmentWidth = Math.ceil(widest);
    }

    implicitWidth: repeater.count * segmentWidth
        + Math.max(0, repeater.count - 1) * spacing
        + padding * 2
    implicitHeight: buttonSize + padding * 2

    Item {
        anchors.fill: parent
        anchors.margins: root.padding

        // Sliding highlight
        StyledRect {
            id: highlight
            variant: "focus"
            z: 0
            radius: Styling.radius(-6)

            // Segment geometry is uniform and already derived from the control's available
            // width, so derive the highlight from that same geometry. Looking up a Repeater
            // item here leaves a startup race: count can change before itemAt() returns a
            // fully laid-out button, and no reactive dependency makes the lookup run again.
            // The result was a buttonSize-wide stub until currentIndex changed on first click.
            readonly property real segmentSpan: repeater.count > 0
                ? (parent.width - (repeater.count - 1) * root.spacing) / repeater.count
                : 0
            readonly property int boundedIndex: repeater.count > 0
                ? Math.max(0, Math.min(root.currentIndex, repeater.count - 1))
                : 0

            width: segmentSpan
            height: parent.height
            x: boundedIndex * (segmentSpan + root.spacing)

            Behavior on x {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration / 2
                    easing.type: Easing.OutCubic
                }
            }

            Behavior on width {
                enabled: Config.animDuration > 0
                NumberAnimation {
                    duration: Config.animDuration / 2
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Buttons
        // Use the same explicit equal-width pattern as the gradient type selector in
        // VariantEditor. RowLayout distributes surplus from layout hints, which made this
        // control depend on implicit/preferred-width negotiation and proved visually
        // inconsistent for differently sized labels. A plain Row plus an exact width from
        // the available space makes every segment share the same boundaries by construction.
        Row {
            id: buttonsRow
            anchors.fill: parent
            spacing: root.spacing
            z: 1

            Repeater {
                id: repeater
                model: root.options

                // itemAt() is not reactive, so a shrinking option set would otherwise leave
                // segmentWidth stale at the old maximum.
                onCountChanged: root.updateSegmentWidth()

                Button {
                    id: optionButton
                    required property var modelData
                    required property int index

                    // What this segment would need for its own content. Reported up so root
                    // can take the max; never used as this segment's width directly.
                    readonly property real naturalWidth: contentRow.implicitWidth + 16

                    onNaturalWidthChanged: root.updateSegmentWidth()
                    Component.onCompleted: root.updateSegmentWidth()

                    width: repeater.count > 0
                        ? (buttonsRow.width - (repeater.count - 1) * buttonsRow.spacing)
                            / repeater.count
                        : 0
                    height: buttonsRow.height

                    focusPolicy: Qt.NoFocus
                    hoverEnabled: true
                    flat: true

                    background: Rectangle {
                        color: "transparent"
                    }

                    // A plain Item that Control is free to stretch, with the real content
                    // centered inside it. `anchors.centerIn` on the RowLayout itself did
                    // nothing: Control assigns its contentItem's width and height directly, so
                    // the layout was stretched to the full content rect and its children packed
                    // to the LEFT of it. At a segment's natural width that is invisible - the
                    // row fills the button - but once segments grow to fill the control, the
                    // icon and label sat hard against the left edge of a wide highlight. Nesting
                    // is what lets the outer item stretch while the row keeps its implicit size.
                    contentItem: Item {
                        implicitWidth: contentRow.implicitWidth
                        implicitHeight: contentRow.implicitHeight

                        // This is content, not a space-distributing layout. RowLayout can
                        // stretch its children across the button's content rect, leaving the
                        // icon near one edge and the label near the other. A plain Row keeps
                        // the icon and label as one compact group for centerIn to centre.
                        Row {
                            id: contentRow
                            anchors.centerIn: parent
                            spacing: 8

                            // Image Icon
                            Image {
                                mipmap: true
                                visible: typeof optionButton.modelData === "object" && !!optionButton.modelData.image
                                source: visible ? optionButton.modelData.image : ""
                                sourceSize.width: 16
                                sourceSize.height: 16
                                width: 16
                                height: 16
                                anchors.verticalCenter: parent.verticalCenter
                                fillMode: Image.PreserveAspectFit
                                opacity: root.currentIndex === optionButton.index ? 1.0 : 0.7
                            }

                            // Font Icon
                            Text {
                                visible: typeof optionButton.modelData === "object" && !!optionButton.modelData.icon && !optionButton.modelData.image
                                text: visible ? optionButton.modelData.icon : ""
                                color: root.currentIndex === optionButton.index ? Styling.srItem("overprimary") : Colors.overBackground
                                font.family: Icons.font
                                font.pixelSize: 14
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter

                                Behavior on color {
                                    enabled: Config.animDuration > 0
                                    ColorAnimation {
                                        duration: Config.animDuration / 2
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }

                            // Label
                            Text {
                                visible: typeof optionButton.modelData !== "object" || !!optionButton.modelData.label
                                text: typeof optionButton.modelData === "object" ? (optionButton.modelData.label || "") : optionButton.modelData
                                color: root.currentIndex === optionButton.index ? Styling.srItem("overprimary") : Colors.overBackground
                                font.family: Config.theme.font
                                font.pixelSize: 14
                                font.weight: root.currentIndex === optionButton.index ? Font.DemiBold : Font.Normal
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter

                                Behavior on color {
                                    enabled: Config.animDuration > 0
                                    ColorAnimation {
                                        duration: Config.animDuration / 2
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }
                    }

                    onClicked: {
                        root.currentIndex = optionButton.index;
                        root.indexChanged(optionButton.index);
                    }

                    StyledToolTip {
                        visible: optionButton.hovered && typeof optionButton.modelData === "object" && !!optionButton.modelData.tooltip
                        tooltipText: typeof optionButton.modelData === "object" ? (optionButton.modelData.tooltip || "") : ""
                    }
                }
            }
        }
    }
}
