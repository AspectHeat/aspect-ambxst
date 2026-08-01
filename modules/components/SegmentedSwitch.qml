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

    implicitWidth: buttonsRow.implicitWidth + padding * 2
    implicitHeight: Math.max(buttonSize, buttonsRow.implicitHeight) + padding * 2

    Item {
        anchors.fill: parent
        anchors.margins: root.padding

        // Sliding highlight
        StyledRect {
            id: highlight
            variant: "focus"
            z: 0
            radius: Styling.radius(-6)

            // itemAt() is a function call, NOT a reactive binding: it is evaluated once when
            // this rect is created, and at that moment the Repeater has not instantiated its
            // buttons yet, so it returned null and the highlight fell back to `buttonSize` -
            // a stub covering the first icon and part of the first label. It then only
            // re-evaluated when currentIndex changed, which is why clicking a segment
            // "fixed" it. Depending on repeater.count (a real property) makes the expression
            // re-run as soon as the items exist; width/x below are genuine bindings on the
            // item, so they track layout from then on.
            property Item activeItem: repeater.count > root.currentIndex
                ? repeater.itemAt(root.currentIndex)
                : null
            width: activeItem ? activeItem.width : root.buttonSize
            height: parent.height
            x: activeItem ? activeItem.x : 0

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
        RowLayout {
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

                    Layout.fillHeight: true
                    // Segments must TILE the control, so they have to grow with it. Without
                    // fillWidth, a host setting `Layout.fillWidth: true` on the SegmentedSwitch
                    // stretched only the layout's cells: RowLayout clamps a non-filling item
                    // to its preferred width and pins it to the cell origin, so the segments
                    // ended up scattered with dead space between and after them. Measured on
                    // Bostrom in a 581px control: segment 0 at x=0 w=88, segment 1 at x=344
                    // w=61, 176px of empty bar to the right. The sliding highlight tracks its
                    // segment faithfully, so it inherited the gap and read as a stub pinned to
                    // the left of a wide bar.
                    //
                    // preferred AND minimum are both the shared segmentWidth, which is what
                    // actually makes the segments equal: surplus is split in proportion to
                    // preferred width, and a per-segment minimum would drag the effective
                    // preference back to per-segment content and reintroduce the imbalance.
                    Layout.fillWidth: true
                    Layout.minimumWidth: root.segmentWidth
                    Layout.preferredWidth: root.segmentWidth

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

                        RowLayout {
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
