pragma Singleton
import QtQuick 2.15
import "../lib/IconCatalog.js" as IconCatalog

QtObject {
    readonly property var categories: [
        "navigation",
        "actions",
        "status",
        "files",
        "map",
        "geotechnical",
        "system"
    ]

    function source(name) {
        return IconCatalog.source(name)
    }

    function has(name) {
        return IconCatalog.has(name)
    }

    function category(name) {
        return IconCatalog.category(name)
    }

    function sourceForState(name, state) {
        return IconCatalog.sourceForState(name, state)
    }
}
