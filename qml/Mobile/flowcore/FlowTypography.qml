import QtQuick 2.15

QtObject {
    // Tipografia corporativa INGEMA (Manual 2025): Rubik.
    // Semibold -> titulos/encabezados/botones principales; Regular -> cuerpo,
    // inputs, menus, tablas y labels; Light -> captions/secundario solo en
    // tamanos >= subtitleSize con contraste suficiente. main_mobile.cpp
    // registra los tres pesos y fija Rubik como fuente de la aplicacion.
    readonly property string family: "Rubik"

    readonly property int displaySize: 32
    readonly property int titleLargeSize: 24
    readonly property int titleSize: 20
    readonly property int subtitleSize: 16
    readonly property int bodySize: 15
    readonly property int labelSize: 13
    readonly property int captionSize: 11

    readonly property int lightWeight: Font.Light
    readonly property int regularWeight: Font.Normal
    readonly property int mediumWeight: Font.Medium
    readonly property int semiboldWeight: Font.DemiBold
    readonly property int boldWeight: Font.Bold

    readonly property real compactLineHeight: 1.15
    readonly property real bodyLineHeight: 1.35
    readonly property real relaxedLineHeight: 1.55
}
