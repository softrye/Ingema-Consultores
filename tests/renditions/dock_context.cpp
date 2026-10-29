// Dock Contextual global: el contrato de Nuevo gasto (4 posiciones, Deep Press /
// 3D Touch) pasa por el DockContextController REAL sin perder la marca opt-in
// `tapCommand` (toque = comando; Deep Press = submenú) y sin alterar otras subapps.
#include "src/dock/DockContextController.h"

#include <QCoreApplication>
#include <QTimer>
#include <iostream>

static int checks = 0;
static void check(bool value, const char *label)
{
    ++checks;
    if (!value) { std::cerr << "FAIL " << label << '\n'; std::exit(1); }
}

static QVariantMap find(const QVariantList &list, const QString &id)
{
    for (const auto &v : list) if (v.toMap().value("id") == id) return v.toMap();
    return {};
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    DockContextController dock;
    dock.setForegroundOwner(QStringLiteral("rendiciones"));
    const QVariantList actions{
        QVariantMap{{"id", "previous"}, {"label", "Volver"}, {"icon", "system.back"}, {"command", "renditions.page.back"},
                    {"tapCommand", true}, {"priority", 1},
                    {"children", QVariantList{QVariantMap{{"id", "renditions.page.toList"}, {"label", "Volver a la lista de gastos"}, {"command", "renditions.page.toList"}},
                                              QVariantMap{{"id", "renditions.page.exitNoSave"}, {"label", "Salir sin guardar"}, {"command", "renditions.page.exitNoSave"}}}}},
        QVariantMap{{"id", "renditions.page.draft"}, {"label", "Borrador"}, {"icon", "documents.file"}, {"command", "renditions.page.draft"},
                    {"tapCommand", true}, {"priority", 2},
                    {"children", QVariantList{QVariantMap{{"id", "renditions.page.saveDraft"}, {"label", "Guardar como borrador"}, {"command", "renditions.page.draft"}}}}},
        QVariantMap{{"id", "next"}, {"label", "Siguiente"}, {"icon", "system.forward"}, {"command", "renditions.page.next"},
                    {"tapCommand", true}, {"priority", 3},
                    {"children", QVariantList{QVariantMap{{"id", "renditions.page.aiValidate"}, {"label", "Validar datos con IA"},
                                                          {"command", "renditions.page.aiValidate"}, {"enabled", false}}}}},
        QVariantMap{{"id", "renditions.tool.today"}, {"label", "Usar fecha de hoy"}, {"icon", "renditions.today"}, {"command", "renditions.tool.today"}, {"priority", 4}},
        QVariantMap{{"id", "renditions.tool.period"}, {"label", "Revisar período permitido"}, {"icon", "renditions.period"}, {"command", "renditions.tool.period"}, {"priority", 5}}};
    check(dock.publishContext(QStringLiteral("rendiciones"), QStringLiteral("rendiciones/expense"), actions), "D1 expense context accepted");
    QTimer::singleShot(0, &app, &QCoreApplication::quit);
    app.exec();                                              // commit en el bucle de eventos (como en la app)
    const auto published = dock.actions();
    check(dock.contextId() == "rendiciones/expense" && published.size() == 5, "D2 four-slot contract published (previous, draft, next + tools)");
    check(find(published, "previous").value("tapCommand").toBool() && find(published, "next").value("tapCommand").toBool()
          && find(published, "renditions.page.draft").value("tapCommand").toBool(), "D3 tapCommand preserved (tap = command, Deep Press = 3D Touch menu)");
    check(!find(published, "renditions.tool.today").value("tapCommand").toBool(), "D4 tools without opt-in keep default behaviour");
    check(find(published, "previous").value("children").toList().size() == 2, "D5 3D Touch children kept");
    const auto ai = dock.actionById(QStringLiteral("renditions.page.aiValidate"));
    check(ai.isEmpty() || ai.value("enabled").toBool() == false, "D6 AI entry is never executable");

    // Otra subapp (sin tapCommand): su contrato no cambia.
    dock.setForegroundOwner(QStringLiteral("calicatas"));
    check(dock.publishContext(QStringLiteral("calicatas"), QStringLiteral("calicatas/form"),
                              {QVariantMap{{"id", "tools"}, {"label", "Herramientas"}, {"icon", "action.menu"}, {"priority", 1},
                                           {"children", QVariantList{QVariantMap{{"id", "x"}, {"label", "X"}, {"command", "x"}}}}}}),
          "D7 other owner publishes");
    QTimer::singleShot(0, &app, &QCoreApplication::quit);
    app.exec();
    check(dock.ownerId() == "calicatas" && !find(dock.actions(), "tools").value("tapCommand").toBool(), "D8 other subapps keep branch-tap behaviour");

    std::cout << "PASS dock context: " << checks << " checks\n";
    return 0;
}
