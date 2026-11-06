import QtQuick
Image {
    id: mascot
    property int frame: 0
    property int tilePixels: 128
    property bool active: true
    enabled: false
    // Separate source images prevent Qt from downscaling the entire atlas before cropping.
    readonly property var spriteSources: [
        "qrc:/images/kawaii/pompompurin-engineer.png",
        "qrc:/images/kawaii/cinnamoroll-engineer.png",
        "qrc:/images/kawaii/pompompurin-dock-sit.png",
        "qrc:/images/kawaii/pompompurin-dock-play.png"
    ]
    source: active && frame >= 0 && frame < spriteSources.length ? spriteSources[frame] : ""
    sourceSize: Qt.size(tilePixels, tilePixels)
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    retainWhileLoading: true
    cache: true
    smooth: true
}
