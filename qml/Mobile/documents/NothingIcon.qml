// SPDX-License-Identifier: GPL-3.0-only
import QtQuick
import InGe.CoreFlow 3.0 as Mobile

Text {
    property string name: "folder"
    property color ink: Mobile.InGeCoreFlow.theme.accent
    property int size: 24
    readonly property var glyphs: ({
            "settings": "\ue8b8",
            "save": "\ue161",
            "search": "\ue8b6",
            "image": "\ue3f4",
            "video_file": "\ueb87",
            "audio_file": "\ueb82",
            "description": "\ue873",
            "android": "\ue859",
            "analytics": "\uef3e",
            "cloud": "\ue2bd",
            "delete": "\ue872",
            "close": "\ue5cd",
            "select_all": "\ue162",
            "arrow_back": "\ue5c4",
            "delete_sweep": "\ue16c",
            "content_paste": "\ue14f",
            "grid_view": "\ue9b0",
            "list": "\ue896",
            "sort": "\ue164",
            "add": "\ue145",
            "folder_open": "\ue2c8",
            "more_vert": "\ue5d4",
            "check": "\ue5ca",
            "restore": "\ue8b3",
            "delete_forever": "\ue92b",
            "open_in_new": "\ue89e",
            "content_cut": "\ue14e",
            "content_copy": "\ue14d",
            "edit": "\ue3c9",
            "share": "\ue80d",
            "unarchive": "\ue169",
            "archive": "\ue149",
            "menu_book": "\uea19",
            "info": "\ue88e",
            "folder": "\ue2c7",
            "picture_as_pdf": "\ue415",
            "insert_drive_file": "\ue24d",
            "download": "\uf090",
            "upload": "\uf09b",
            "refresh": "\ue5d5"
        })
    FontLoader {
        id: material
        source: "assets/MaterialIcons-Regular.ttf"
    }
    text: glyphs[name] || glyphs.insert_drive_file
    color: ink
    font.family: material.name
    font.pixelSize: size
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    width: size
    height: size
    Accessible.ignored: true
}
