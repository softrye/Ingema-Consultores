import QtQuick 2.15
import InGe.CoreFlow 3.0 as Mobile

Text {
    id: root

    readonly property var flow: Mobile.InGeCoreFlow
    property string role: "body"
    property bool muted: false

    color: muted ? flow.theme.textMuted
                 : (role === "secondary"
                    ? flow.theme.textSecondary
                    : flow.theme.textPrimary)
    font.family: flow.typography.family
    font.pixelSize: flow.accessibility.scaledTextSize(
        role === "display" ? flow.typography.displaySize
        : (role === "titleLarge" ? flow.typography.titleLargeSize
           : (role === "title" ? flow.typography.titleSize
              : (role === "subtitle" ? flow.typography.subtitleSize
                 : (role === "label" ? flow.typography.labelSize
                    : (role === "caption" ? flow.typography.captionSize
                       : flow.typography.bodySize))))))
    font.weight: role === "display" || role === "titleLarge"
                 || role === "title" ? flow.typography.semiboldWeight
                                    : flow.typography.regularWeight
    wrapMode: Text.WordWrap
    renderType: Text.QtRendering
}
