import QtQuick 2.15
import QtQuick.Layouts 1.15
import "../components" as Components
import InGe.CoreFlow 3.0 as Mobile

// InGeCoreFlow V34
// Globo contextual inspirado en la respuesta táctil de iOS. Se expande desde
// el punto de origen, atenúa suavemente el fondo y respeta Reducir movimiento.
Item {
    id: root

    property var flow: null
    property bool darkMode: false
    property bool presented: false
    property Item anchorItem: null
    property string title: "Acciones rápidas"
    property var actions: []
    property real revealProgress: 0.0
    property real anchorCenterX: width / 2
    property real anchorY: height / 2
    property point bubblePosition: Qt.point(12, 12)
    property bool bubbleBelowAnchor: false

    readonly property bool motionAllowed:
        flow && flow.motionAllowed === true

    readonly property int actionCount:
        actions && actions.length !== undefined ? actions.length : 0

    readonly property real computedBubbleWidth:
        Math.max(
            flow ? flow.quickBubbleMinimumWidth : 218,
            Math.min(
                flow ? flow.quickBubbleMaximumWidth : 258,
                width - 24
            )
        )

    readonly property real computedBubbleHeight:
        54 + actionCount
        * (flow ? flow.quickBubbleActionHeight : 50)
        + 14

    readonly property real pointerLocalX:
        flow
        ? flow.quickBubblePointerX(
              anchorCenterX,
              bubblePosition.x,
              computedBubbleWidth
          )
        : computedBubbleWidth / 2

    signal actionTriggered(string actionKey)

    visible: presented || revealProgress > 0.001
    enabled: presented
    focus: presented

    function clamp(value, minimum, maximum) {
        return Math.max(minimum, Math.min(maximum, value))
    }

    function updatePlacement(item) {
        if (!item)
            return

        var margin = 12.0
        var pointerGap = (flow ? flow.quickBubblePointerSize : 15) + 7.0
        var topPoint = item.mapToItem(root, item.width / 2, 0)
        var bottomPoint = item.mapToItem(root, item.width / 2, item.height)
        var proposedX = topPoint.x - computedBubbleWidth / 2
        var aboveY = topPoint.y - computedBubbleHeight - pointerGap
        var belowY = bottomPoint.y + pointerGap

        anchorCenterX = topPoint.x
        bubbleBelowAnchor = aboveY < margin
        anchorY = bubbleBelowAnchor ? bottomPoint.y : topPoint.y

        bubblePosition = Qt.point(
            clamp(proposedX,
                  margin,
                  Math.max(margin,
                           width - computedBubbleWidth - margin)),
            bubbleBelowAnchor
            ? clamp(belowY,
                    margin,
                    Math.max(margin,
                             height - computedBubbleHeight - margin))
            : clamp(aboveY,
                    margin,
                    Math.max(margin,
                             height - computedBubbleHeight - margin))
        )
    }

    function openFor(item, bubbleTitle, bubbleActions) {
        if (!item || !flow || !flow.quickBubbleEnabled)
            return

        anchorItem = item
        title = String(bubbleTitle || "Acciones rápidas")
        actions = bubbleActions || []
        updatePlacement(item)

        presented = true
        closeAnimation.stop()

        if (motionAllowed) {
            openAnimation.from = revealProgress
            openAnimation.to = 1.0
            openAnimation.restart()
        } else {
            revealProgress = 1.0
        }
    }

    function close() {
        if (!visible)
            return

        presented = false
        openAnimation.stop()

        if (motionAllowed) {
            closeAnimation.from = revealProgress
            closeAnimation.to = 0.0
            closeAnimation.restart()
        } else {
            revealProgress = 0.0
            anchorItem = null
        }
    }

    function activate(actionKey) {
        var key = String(actionKey || "")
        close()
        Qt.callLater(function() {
            root.actionTriggered(key)
        })
    }

    Keys.onEscapePressed: function(event) {
        root.close()
        event.accepted = true
    }

    onWidthChanged: {
        if (presented && anchorItem)
            updatePlacement(anchorItem)
    }

    onHeightChanged: {
        if (presented && anchorItem)
            updatePlacement(anchorItem)
    }

    Rectangle {
        anchors.fill: parent
        color: root.darkMode ? Mobile.InGeCoreFlow.colors.ingemaDeepShade : Mobile.InGeCoreFlow.colors.ingemaDeep
        opacity: (root.darkMode ? 0.24 : 0.12) * root.revealProgress
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.presented
        onClicked: root.close()
    }

    Rectangle {
        x: bubble.x + 2
        y: bubble.y + 7
        width: bubble.width - 4
        height: bubble.height
        radius: bubble.radius
        color: "#000000"
        opacity: 0.13 * root.revealProgress
        scale: bubble.visualScale
        transformOrigin: Item.Bottom
    }

    FlowGlassSurface {
        id: bubble

        property real visualScale:
            (root.flow ? root.flow.quickBubbleStartScale : 0.84)
            + (1.0 - (root.flow ? root.flow.quickBubbleStartScale : 0.84))
            * root.revealProgress

        x: root.bubblePosition.x
        y: root.bubblePosition.y
        width: root.computedBubbleWidth
        height: root.computedBubbleHeight
        radius: root.flow ? root.flow.quickBubbleCornerRadius : 22
        flow: root.flow
        darkMode: root.darkMode
        strength: 0.99
        fallbackLight: "#FFFFFF"
        fallbackDark: Mobile.InGeCoreFlow.colors.ingemaNavy
        opacity: root.revealProgress

        transform: [
            Translate {
                y: (1.0 - root.revealProgress)
                   * (root.flow ? root.flow.quickBubbleStartOffset : 18)
                   * (root.bubbleBelowAnchor ? -1.0 : 1.0)
            },
            Scale {
                origin.x: root.pointerLocalX
                origin.y: root.bubbleBelowAnchor ? 0 : bubble.height
                xScale: bubble.visualScale
                yScale: bubble.visualScale
            }
        ]

        Rectangle {
            width: root.flow ? root.flow.quickBubblePointerSize : 15
            height: width
            rotation: 45
            radius: 3
            color: bubble.color
            border.color: bubble.border.color
            border.width: 1
            x: root.pointerLocalX - width / 2
            y: root.bubbleBelowAnchor ? -height / 2 : bubble.height - height / 2
            z: -1
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 4

            Text {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                text: root.title
                color: root.darkMode ? "#FFFFFF" : Mobile.InGeCoreFlow.colors.ingemaDeep
                font.pixelSize: 14
                font.bold: true
                verticalAlignment: Text.AlignVCenter
                leftPadding: 8
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: root.darkMode ? Qt.rgba(1, 1, 1, 0.16) : Mobile.InGeCoreFlow.colors.blue100
            }

            Repeater {
                model: root.actions || []

                delegate: Rectangle {
                    id: actionRow
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.preferredHeight:
                        root.flow ? root.flow.quickBubbleActionHeight : 50
                    radius: 14
                    color: actionMouse.pressed
                           ? (root.darkMode ? Qt.rgba(1, 1, 1, 0.10) : Mobile.InGeCoreFlow.colors.blue100)
                           : "transparent"
                    opacity: Math.max(
                                 0.0,
                                 Math.min(
                                     1.0,
                                     (root.revealProgress - index * 0.055) / 0.72
                                 )
                             )
                    transform: Translate {
                        y: (1.0 - actionRow.opacity) * 8
                    }

                    Behavior on color {
                        ColorAnimation {
                            duration: root.flow
                                      ? root.flow.fastDuration
                                      : 110
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        spacing: 11

                        Rectangle {
                            Layout.preferredWidth: 32
                            Layout.preferredHeight: 32
                            radius: 11
                            color: root.darkMode ? Qt.rgba(0.561, 0.698, 0.835, 0.16) : Mobile.InGeCoreFlow.colors.ingemaBlueWash

                            Components.FlowIcon {
                                anchors.centerIn: parent
                                width: 20
                                height: 20
                                name: String(modelData.icon || "nav.settings")
                                flow: root.flow
                                pressed: actionMouse.pressed
                                tintColor: root.darkMode ? Mobile.InGeCoreFlow.colors.ingemaBlueTint : Mobile.InGeCoreFlow.colors.ingemaBlue
                                activeTintColor: root.darkMode ? "#FFFFFF" : Mobile.InGeCoreFlow.colors.ingemaNavy
                                inactiveOpacity: 1.0
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                Layout.fillWidth: true
                                text: String(modelData.label || "")
                                color: root.darkMode ? "#FFFFFF" : Mobile.InGeCoreFlow.colors.ingemaDeep
                                font.pixelSize: 13
                                font.bold: true
                                maximumLineCount: 1
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                visible: String(modelData.subtitle || "").length > 0
                                text: String(modelData.subtitle || "")
                                color: root.darkMode ? Mobile.InGeCoreFlow.colors.ingemaPaperSecondary : Mobile.InGeCoreFlow.colors.ingemaInkSecondary
                                font.pixelSize: 10
                                maximumLineCount: 1
                                elide: Text.ElideRight
                            }
                        }

                        Components.FlowIcon {
                            Layout.preferredWidth: 16
                            Layout.preferredHeight: 16
                            name: "system.chevronRight"
                            flow: root.flow
                            tintColor: root.darkMode ? Mobile.InGeCoreFlow.colors.ingemaBlueTint : Mobile.InGeCoreFlow.colors.ingemaInkTertiary
                            inactiveOpacity: 1.0
                        }
                    }

                    MouseArea {
                        id: actionMouse
                        anchors.fill: parent
                        onClicked: root.activate(
                            String(actionRow.modelData.key || "")
                        )
                    }
                }
            }
        }
    }

    NumberAnimation {
        id: openAnimation
        target: root
        property: "revealProgress"
        duration: root.flow ? root.flow.quickBubbleOpenDuration : 250
        easing.type: root.flow ? root.flow.easeOvershoot : Easing.OutBack
    }

    NumberAnimation {
        id: closeAnimation
        target: root
        property: "revealProgress"
        duration: root.flow ? root.flow.quickBubbleCloseDuration : 145
        easing.type: root.flow ? root.flow.easeOut : Easing.OutCubic
        onFinished: {
            if (!root.presented && root.revealProgress <= 0.001)
                root.anchorItem = null
        }
    }
}
