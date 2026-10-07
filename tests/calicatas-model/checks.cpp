#include "calicatadocument.h"
#include <QGuiApplication>
#include <QStandardPaths>
#include <QDebug>
int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    app.setApplicationName("CalicataModelClosureChecks");
    QStandardPaths::setTestModeEnabled(true);
    CalicataDocument d;
    if (d.header().value("status") != "BORRADOR" || d.header().value("water_table_status") != "NO_EVALUADO") return 1;
    if (d.selectProject({{"projectId", "C-01"}})) return 2;
    if (!d.selectProject({{"projectId", "a42abcde-1234-4321-8765-123456789012"}, {"projectName", "Test"}})) return 3;
    auto h = d.header(); h["calicataId"] = "C-01"; h["utm_x"] = "1,50";
    h["water_table_status"] = "ENCONTRADO"; h["water_table_depth"] = "0"; d.setHeader(h);
    if (d.header().value("calicataId") != d.instanceId() || d.header().value("utm_x") != "1.50") return 4;
    if (!d.header().value("water_table_present").toBool() || d.header().value("water_table_depth") != "0") return 5;
    if (d.transitionStatus("APROBADO")) return 6;
    if (!d.transitionStatus("EN_REVISION") || !d.transitionStatus("REVISADO") || !d.transitionStatus("APROBADO") || !d.transitionStatus("EXPORTADO") || !d.transitionStatus("ARCHIVADO")) return 7;
    CalicataDocument restored;
    if (!restored.loadDraftById(d.instanceId()) || restored.header().value("status") != "ARCHIVADO" || restored.instanceId() != d.instanceId()) return 8;
    d.clearDraft();
    qInfo() << "PASS: identity, project UUID, decimal, groundwater zero, transitions, archive persistence";
}
