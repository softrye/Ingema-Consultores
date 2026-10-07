import QtQuick 2.15
import QtQuick.Controls 2.15
import InGe.CoreFlow 3.0 as Mobile

Control {
    id: root

    readonly property var flow: Mobile.InGeCoreFlow
    property bool scrollable: true
    property int safeTopMargin: 0
    property int safeBottomMargin: 0
    property int safeLeftMargin: 0
    property int safeRightMargin: 0
    property int pagePadding: flow.spacing.lg
    default property alias contentData: pageContent.data

    padding: 0
    background: Rectangle {
        color: flow.theme.background
    }

    contentItem: Flickable {
        id: pageFlick
        clip: true
        interactive: root.scrollable
        boundsBehavior: Flickable.StopAtBounds
        flickDeceleration: flow.flickDeceleration
        maximumFlickVelocity: flow.maximumFlickVelocity
        contentWidth: width
        contentHeight: Math.max(height, pageContent.childrenRect.height
                                + root.pagePadding * 2
                                + root.safeTopMargin
                                + root.safeBottomMargin)

        Item {
            id: pageContent
            x: root.pagePadding + root.safeLeftMargin
            y: root.pagePadding + root.safeTopMargin
            width: pageFlick.width - root.pagePadding * 2
                   - root.safeLeftMargin - root.safeRightMargin
            height: Math.max(childrenRect.height,
                             pageFlick.height - root.pagePadding * 2
                             - root.safeTopMargin - root.safeBottomMargin)
        }

        ScrollIndicator.vertical: ScrollIndicator {
            opacity: flow.scrollIndicatorOpacity
        }
    }
}
