// Prueba QML host de la subapp Rendiciones: carga las pantallas reales
// (qml/Mobile/renditions) con el RenditionUiController real y un bridge
// SINTÉTICO que imita el contrato JSON de RenditionFlutterBridge (comandos,
// commandResult por requestId y eventos "state"). Recorre el flujo
// Nueva rendición -> proyecto -> carpeta -> gasto -> sustento -> fondo ->
// tipo de cambio -> sincronizar -> presentar -> revisión -> recibidas.
// No prueba Android ni Supabase real.
#include "src/cpp/renditionuicontroller.h"

#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QGuiApplication>
#include <QJsonDocument>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQmlExpression>
#include <QQuickItem>
#include <QQuickWindow>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QTimer>
#include <QUuid>
#include <QUrl>
#include <functional>
#include <iostream>

static int checks = 0;
static QStringList qmlWarnings;
static void check(bool value, const std::string &label)
{
    ++checks;
    if (!value) { std::cerr << "FAIL " << label << '\n'; std::exit(1); }
}
static void messageHandler(QtMsgType type, const QMessageLogContext &, const QString &message)
{
    // Solo diagnósticos QML/JS; la plataforma offscreen avisa de fuentes ausentes.
    if ((type == QtWarningMsg || type == QtCriticalMsg || type == QtFatalMsg)
        && (message.contains(QLatin1String(".qml")) || message.contains(QLatin1String(".js"))
            || message.contains(QLatin1String("Error")) || message.contains(QLatin1String("QML"))))
        qmlWarnings.append(message);
    std::cerr << message.toStdString() << '\n';
}
static bool waitFor(const std::function<bool()> &condition, int ms = 3000)
{
    QElapsedTimer timer; timer.start();
    while (!condition() && timer.elapsed() < ms)
        QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
    return condition();
}

// Bridge sintético con el contrato del bridge real (subconjunto del dominio).
class SyntheticBridge : public QObject
{
    Q_OBJECT
public:
    QVariantList commands;
    QVariantList renditions;
    QVariantMap drafts;
    QString selected;
    QVariantMap expenses;            // localId rendición -> lista
    // Conectividad simulada (fuente única publicada por el bridge real).
    QString connection = "ONLINE";
    QString phase = "IDLE";
    QStringList failOps;             // operaciones que fallan por transporte
    QString failCode = "NETWORK_AMBIGUOUS";
    void push() { publish(); }
    int selectSerial = 0;
    // Working Document y Files v07 simulados (contratos del bridge real).
    QVariantList workingRows;
    QVariantMap inspectRow;
    bool requireDestination = false;
    QVariantList filesItems{QVariantMap{{"id", "n-archived-1"}, {"name", "Informe topográfico.pdf"}, {"space_id", "space-1"},
        {"space_name", "Presa Norte"}, {"origin", "Presa Norte / Informes"}, {"updated_at", "2026-10-10T10:00:00Z"},
        {"node_version", 3}, {"kind", "BINARY_DOCUMENT"}, {"parent_node_id", QVariant()}, {"project_id", "p1"},
        {"started", false}, {"request_id", QVariant()}, {"can_restore", true}, {"lifecycle", "ARCHIVED"},
        {"can_reactivate", true}, {"requires_destination", false}, {"origin_state", "AVAILABLE"}}};

    QVariantMap lastCommand(const QString &operation) const
    {
        for (int i = commands.size() - 1; i >= 0; --i)
            if (commands.at(i).toMap().value("operation") == operation) return commands.at(i).toMap();
        return {};
    }
    int count(const QString &operation) const
    {
        int n = 0;
        for (const auto &c : commands) n += c.toMap().value("operation") == operation;
        return n;
    }
    Q_INVOKABLE void submit(const QString &json)
    {
        const auto command = QJsonDocument::fromJson(json.toUtf8()).toVariant().toMap();
        commands.append(command);
        QTimer::singleShot(5, this, [this, command]() { handle(command); });
    }
signals:
    void eventReady(const QString &eventJson);

private:
    void emitEvent(const QVariantMap &e) { emit eventReady(QString::fromUtf8(QJsonDocument::fromVariant(e).toJson(QJsonDocument::Compact))); }
    void ok(const QVariantMap &c, const QVariantMap &result = {}) { emitEvent({{"type", "commandResult"}, {"requestId", c.value("requestId")}, {"ok", true}, {"result", result}}); }
    void fail(const QVariantMap &c, const QString &code, const QString &message) { emitEvent({{"type", "commandResult"}, {"requestId", c.value("requestId")}, {"ok", false}, {"code", code}, {"message", message}}); }
    int indexOf(const QString &localId) const
    {
        for (int i = 0; i < renditions.size(); ++i) if (renditions.at(i).toMap().value("localId") == localId) return i;
        return -1;
    }
    QVariantMap rendition(const QString &localId) const { const int i = indexOf(localId); return i < 0 ? QVariantMap{} : renditions.at(i).toMap(); }
    void put(const QVariantMap &r) { const int i = indexOf(r.value("localId").toString()); if (i < 0) renditions.append(r); else renditions[i] = r; }
    void publish()
    {
        QVariantMap current = rendition(selected);
        emitEvent({{"type", "state"}, {"connectionState", connection}, {"syncPhase", phase}, {"busy", false},
                   {"lastPullAt", "2026-10-16T12:00:00.000Z"},
                   {"pendingCount", current.value("pendingCount", 0)}, {"editorDrafts", drafts}, {"renditions", renditions},
                   {"projects", QVariantList{QVariantMap{{"id", "p1"}, {"code", "P-01"}, {"name", "Presa Norte"}},
                                             QVariantMap{{"id", "p2"}, {"code", "P-02"}, {"name", "Canal Sur"}}}},
                   {"catalogs", QVariantList{QVariantMap{{"catalog_type", "CATEGORY"}, {"code", "FOOD"}, {"name", "Alimentación"}},
                                             QVariantMap{{"catalog_type", "PAYMENT_METHOD"}, {"code", "CASH"}, {"name", "Efectivo"}},
                                             QVariantMap{{"catalog_type", "SUPPORT_TYPE"}, {"code", "RECEIPT"}, {"name", "Boleta"}}}},
                   {"selectedLocalId", selected}, {"current", current},
                   {"expenses", expenses.value(selected).toList()},
                   {"versions", current.value("currentVersionId").toString().isEmpty() ? QVariantList{}
                        : QVariantList{QVariantMap{{"id", "v1"}, {"version_number", 1}, {"rendition_id", "remote-1"}, {"snapshot_hash", QString(64, 'a')}}}},
                   {"attachments", QVariantList{}}, {"remoteCurrent", QVariantMap{}},
                   {"workingRows", workingRows}, {"workingContract", "AVAILABLE"}});
    }
    void handle(const QVariantMap &c)
    {
        const QString op = c.value("operation").toString();
        const QVariantMap a = c.value("arguments").toMap();
        if (failOps.contains(op)) { publish(); fail(c, failCode, "Host unreachable"); return; }
        if (op == "bootstrap" || op == "refresh") { publish(); ok(c, {{"pulled", true}}); return; }
        if (op == "saveEditorDraft") {
            if (a.value("draft").toMap().isEmpty()) drafts.remove(a.value("key").toString());
            else drafts.insert(a.value("key").toString(), a.value("draft"));
            ok(c); publish(); return;
        }
        if (op == "create") {
            QVariantMap r{{"localId", "local-1"}, {"status", "BORRADOR"}, {"periodStart", a.value("periodStart")}, {"periodEnd", a.value("periodEnd")},
                          {"projectIds", a.value("projectIds")}, {"primaryProjectId", a.value("primaryProjectId")},
                          {"documentParentNodeId", a.value("documentParentNodeId")}, {"spaceId", a.value("spaceId")},
                          {"rowVersion", 0}, {"syncState", "PENDING_CREATE"}, {"pendingCount", 1}, {"totalPen", 0}, {"totalUsd", 0}, {"expenseCount", 0}};
            put(r); selected = "local-1";
            publish(); ok(c, {{"current", r}, {"localId", "local-1"}, {"pendingSync", true}}); return;
        }
        if (op == "select") { selected = a.value("localId").toString(); ++selectSerial; publish(); ok(c, {{"current", rendition(selected)}, {"selectionToken", selectSerial}}); return; }
        if (op == "closeDetail") {                     // mismo contrato del bridge real
            const int token = a.value("selectionToken").toInt();
            if (token > 0 ? token == selectSerial : (a.value("localId").toString().isEmpty() || a.value("localId") == selected)) selected.clear();
            publish(); ok(c); return;
        }
        if (op == "projectWorkspace") { ok(c, {{"spaceId", "space-1"}}); return; }
        if (op == "listFolders") { ok(c, {{"folders", QVariantList{QVariantMap{{"id", "f1"}, {"name", "Rendiciones"}}}}, {"count", 1}}); return; }
        if (op == "folderCapabilities") {
            ok(c, {{"node_kind", "FOLDER"}, {"lifecycle", "ACTIVE"}, {"can_accept_child", true}, {"space_id", a.value("spaceId")}, {"node_id", a.value("nodeId")}});
            return;
        }
        if (op == "saveExpense") {
            auto list = expenses.value(a.value("localId").toString()).toList();
            QVariantMap e = a.value("expense").toMap();
            e.insert("localId", "exp-1"); e.insert("syncState", "PENDING_CREATE"); e.insert("rowVersion", 0); e.insert("attachments", QVariantList{});
            list.append(e); expenses.insert(a.value("localId").toString(), list);
            auto r = rendition(a.value("localId").toString()); r.insert("totalPen", e.value("amount")); r.insert("expenseCount", 1); r.insert("pendingCount", 2); put(r);
            publish(); ok(c, {{"localId", "exp-1"}, {"pendingSync", true}}); return;
        }
        if (op == "attachSupport") {
            auto list = expenses.value(a.value("localId").toString()).toList();
            auto e = list.first().toMap(); auto files = e.value("attachments").toList();
            auto file = a.value("attachment").toMap(); file.insert("phase", "RESERVE"); file.insert("syncState", "PENDING_CREATE");
            files.append(file); e.insert("attachments", files); list[0] = e; expenses.insert(a.value("localId").toString(), list);
            publish(); ok(c, {{"pendingSync", true}}); return;
        }
        if (op == "saveFinancial") {
            auto r = rendition(a.value("localId").toString());
            r.insert(a.value("kind") == "funding_set" ? "funding" : "exchangeRate", a.value("values")); put(r);
            publish(); ok(c, {{"pendingSync", true}, {"current", r}}); return;
        }
        if (op == "exchangeQuote") { fail(c, "QUOTE_ORIGIN_NOT_CONFIGURED", "Configure the authenticated DEV Web API origin; saved rate is retained"); return; }
        if (op == "sync") {
            auto r = rendition("local-1"); r.insert("remoteId", "remote-1"); r.insert("visibleCode", "RDC-2026-000042");
            r.insert("syncState", "SYNCED"); r.insert("pendingCount", 0); r.insert("rowVersion", 1); r.insert("can_edit_content", true); put(r);
            publish(); ok(c, {{"pulled", true}}); return;
        }
        if (op == "present") {
            auto r = rendition(selected); r.insert("status", "EN_REVISION"); r.insert("currentVersionId", "v1"); r.insert("versionNumber", 1); r.insert("rowVersion", 2); put(r);
            publish(); ok(c, {{"pulled", true}, {"reason", "present"}}); return;
        }
        if (op == "reviewContext") {
            ok(c, {{"rows", QVariantList{QVariantMap{{"rendition_id", a.value("renditionId")}, {"status", "EN_REVISION"}, {"row_version", 2},
                    {"can_edit", false}, {"can_request_edit", true}, {"can_decide_edit", false}, {"next_states", QVariantList{}}, {"requests", QVariantList{}}}}}});
            return;
        }
        if (op == "receivedList") {
            ok(c, {{"rows", QVariantList{QVariantMap{{"rendition_id", "remote-9"}, {"rendition_version_id", "v9"}, {"version_number", 2},
                    {"snapshot_hash", QString(64, 'b')}, {"visible_code", "RDC-2026-000009"}, {"owner_name", "Equipo de campo"},
                    {"period_start", "2026-09-01"}, {"period_end", "2026-09-30"}, {"status", "EN_REVISION"}, {"total_declared_pen", 80.5},
                    {"total_declared_usd", 0}, {"submitted_at", "2026-10-01T10:00:00Z"}}}}});
            return;
        }
        if (op == "receivedQuery") {
            ok(c, {{"rows", QVariantList{QVariantMap{{"rendition_id", a.value("renditionId")}, {"rendition_version_id", a.value("versionId")},
                    {"version_number", a.value("versionNumber")}, {"snapshot_hash", a.value("hash")},
                    {"snapshot_payload", QVariantMap{{"expenses", QVariantList{QVariantMap{{"id", "e9"}, {"concept", "Combustible"}, {"amount", 80.5}, {"currency_code", "PEN"}}}},
                                                    {"attachments", QVariantList{QVariantMap{{"id", "a9"}, {"expense_id", "e9"}, {"file_name", "boleta.pdf"}}}}}},
                    {"funding", QVariantMap{{"enabled", true}, {"pen", "100.00"}, {"usd", "0"}}}, {"exchangeRate", QVariantMap{{"rate", "3.75"}}}}}}});
            return;
        }
        if (op == "receive") { ok(c, {{"rows", QVariantList{QVariantMap{{"result_code", "RECEIVED"}, {"received_at", "2026-10-14T12:00:00Z"}}}}}); return; }
        // ---- Working Document
        if (op == "saveWorking" || op == "promoteWorking") {
            QString id = a.value("workingId").toString();
            int index = -1;
            for (int i = 0; i < workingRows.size(); ++i) if (workingRows.at(i).toMap().value("id") == id) index = i;
            QVariantMap row = index >= 0 ? workingRows.at(index).toMap()
                : QVariantMap{{"id", "w-1"}, {"kind", "NEW"}, {"sources", QVariantList{}}, {"missingSources", 0},
                              {"waitingSources", 0}, {"cloudVersion", 0}, {"inCloud", false}, {"syncState", "PENDING_UPDATE"}};
            if (a.contains("form")) row.insert("form", a.value("form"));
            if (op == "promoteWorking") row.insert("promoteRequested", true);
            if (index >= 0) workingRows[index] = row; else workingRows.append(row);
            publish(); ok(c, {{"workingId", row.value("id")}, {"pendingSync", true}}); return;
        }
        if (op == "archiveWorking") {
            for (int i = workingRows.size() - 1; i >= 0; --i) if (workingRows.at(i).toMap().value("id") == a.value("workingId")) workingRows.removeAt(i);
            publish(); ok(c, {{"workingId", a.value("workingId")}}); return;
        }
        if (op == "resolveWorking") {
            for (int i = 0; i < workingRows.size(); ++i) {
                auto row = workingRows.at(i).toMap();
                if (row.value("id") != a.value("workingId")) continue;
                row.insert("syncState", "PENDING_UPDATE"); row.remove("syncError"); workingRows[i] = row;
            }
            publish(); ok(c, {{"workingId", a.value("workingId")}}); return;
        }
        if (op == "workingInspect") { ok(c, {{"rows", QVariantList{inspectRow}}}); return; }
        // ---- Files v07 (sin purga)
        if (op == "filesContract") {
            ok(c, {{"rows", QVariantList{QVariantMap{{"version", 7}, {"archive", true}, {"readonly", true}, {"restore", true},
                                                     {"lifecycle", true}, {"domain_recovery", true}, {"purge_protection", true}}}}});
            return;
        }
        if (op == "filesArchive" || op == "filesTrash") {
            ok(c, {{"rows", QVariantList{QVariantMap{{"items", filesItems}, {"has_more", false}, {"next_id", QVariant()}}}}});
            return;
        }
        if (op == "filesPreviewRecovery") {
            const bool needs = requireDestination && a.value("destinationSpaceId").toString().isEmpty();
            ok(c, {{"rows", QVariantList{QVariantMap{
                {"entity", QVariantMap{{"id", a.value("entityId")}, {"kind", "BINARY_DOCUMENT"}, {"version", a.value("expectedVersion")}}},
                {"origin", QVariantMap{{"state", needs ? "MOVED" : "AVAILABLE"}, {"label", "Presa Norte / Informes"}}},
                {"requires_destination", needs}, {"token", needs ? QVariant() : QVariant("preview-token-1")},
                {"destination", needs ? QVariant() : QVariant(QVariantMap{{"space_id", "space-1"}, {"node_id", QVariant()}, {"label", "Presa Norte"}, {"space_version", 1}})},
                {"nodes", needs ? QVariantList{} : QVariantList{QVariantMap{{"id", a.value("entityId")}, {"name", "Informe"}, {"kind", "BINARY_DOCUMENT"}, {"version", 3}}}},
                {"domains", QVariantList{}}}}}});
            return;
        }
        if (op == "filesCanChoose") { ok(c, {{"rows", QVariantList{true}}}); return; }
        if (op == "filesRecover") {
            filesItems.clear();
            ok(c, {{"rows", QVariantList{QVariantMap{{"success", true}, {"id", a.value("entityId")}, {"version", 4}}}}});
            return;
        }
        ok(c, {{"rows", QVariantList{}}});
    }
};

int main(int argc, char **argv)
{
    qputenv("QT_QPA_PLATFORM", "offscreen");
    qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");
    qInstallMessageHandler(messageHandler);
    QGuiApplication app(argc, argv);
    const QString qmlDir = QString::fromLocal8Bit(argc > 1 ? argv[1] : "qml/Mobile/renditions");

    SyntheticBridge bridge;
    RenditionUiController controller(&bridge);
    QQmlEngine engine;
    QQmlComponent component(&engine, QUrl::fromLocalFile(QDir(qmlDir).filePath("RenditionsApp.qml")));
    check(component.isReady(), ("RenditionsApp.qml compiles: " + component.errorString()).toStdString());
    const QVariantMap ui{{"u", 1.0}, {"fontFamily", ""}, {"iconFamily", ""}, {"topInset", 24}, {"gutter", 18},
                         {"dockArea", 96}, {"glassFill", "#334"}, {"glassBorder", "#556"}, {"reducedMotion", true},
                         {"firstName", "Paola"}};
    QObject *root = component.createWithInitialProperties({{"ui", ui}, {"ctl", QVariant::fromValue<QObject *>(&controller)},
                                                           {"width", 412}, {"height", 915}});
    check(root != nullptr, ("RenditionsApp created: " + component.errorString()).toStdString());
    // Ventana offscreen: StackView y Popup necesitan su bucle de render (como en la app).
    QQuickWindow window;
    window.resize(412, 915);
    qobject_cast<QQuickItem *>(root)->setParentItem(window.contentItem());
    window.show();
    QQmlContext *context = qmlContext(root);
    const auto js = [&](const QString &code) {
        QQmlExpression expression(context, root, code);
        const QVariant value = expression.evaluate();
        if (expression.hasError()) {   // fallo de script: no cuenta como verificación
            std::cerr << "FAIL JS error in `" << code.toStdString() << "`: " << expression.error().toString().toStdString() << std::endl;
            std::exit(1);
        }
        return value;
    };
    const auto depth = [&]() { return js("stack.depth").toInt(); };
    // Atrás se ignora a propósito durante una transición de la pila: esperar a que termine.
    const auto back = [&]() {
        if (!waitFor([&]() { return !js("stack.busy").toBool(); }, 8000)) { std::cerr << "FAIL stack idle before back" << std::endl; std::exit(1); }
        return js("handleBack()").toBool();
    };

    // Texto VISIBLE en pantalla (efectivamente visible, con opacidad): banners/toasts/recuadros.
    // Recorre el ÁRBOL VISUAL real (childItems), no el árbol de QObject: así se
    // incluyen delegados, Loaders y popups. Sólo cuenta lo efectivamente visible.
    std::function<void(QQuickItem *, QList<QQuickItem *> &)> collect = [&](QQuickItem *item, QList<QQuickItem *> &out) {
        if (!item || !item->isVisible() || item->opacity() <= 0.01) return;
        out.append(item);
        for (QQuickItem *child : item->childItems()) collect(child, out);
    };
    const auto visibleItems = [&]() {
        QCoreApplication::processEvents();
        QList<QQuickItem *> out;
        collect(window.contentItem(), out);
        return out;
    };
    const auto visibleText = [&](const QString &needle) {
        for (QQuickItem *item : visibleItems()) {
            const QVariant text = item->property("text");
            if (text.isValid() && text.toString().contains(needle)) return true;
        }
        return false;
    };
    // REN-02/03/04: la subapp se crea y recupera el estado de la sesión vía bootstrap.
    check(waitFor([&]() { return controller.ready(); }), "REN-04 bootstrap publishes state");
    check(bridge.count("bootstrap") == 1, "bootstrap sent once");
    check(js("stack.currentItem.objectName").toString() == "renditionsHome", "REN-03 home screen created");

    // REN-06/07: nueva rendición con proyecto y carpeta de InGe Drive.
    js("openCreate()");
    check(waitFor([&]() { return js("createSheet.editor !== null").toBool(); }), "new rendition sheet opened");
    check(js("modalOpen").toBool() && !js("stack.currentItem.listInteractive").toBool(), "SCROLL background list frozen while 'Nueva rendición' is open");
    check(root->findChild<QObject *>("renditionNameInput") != nullptr, "IMG1 name editable inside the compact period block");
    js("var e = createSheet.editor; e.displayName = 'Visita de campo Huarmey'; e.start = '2026-10-01'; e.end = '2026-10-31'; e.toggleProject('p1'); e.toggleProject('p2'); e.setPrimary('p1'); e.changed()");
    check(waitFor([&]() { return bridge.count("saveEditorDraft") >= 1; }, 2000), "REN-21 header autosave persisted");
    check(waitFor([&]() { return bridge.drafts.contains("header:new"); }), "draft stored under header:new");
    js("createSheet.editor.openFolders()");
    check(waitFor([&]() { return js("createSheet.editor.browsing").toBool(); }), "InGe Drive folder browser opened");
    check(bridge.lastCommand("projectWorkspace").value("arguments").toMap().value("projectId") == "p1", "workspace of primary project");
    js("var e = createSheet.editor; e.loadFolders('f1', e.folders[0])");
    check(waitFor([&]() { return js("createSheet.editor.path.length").toInt() == 1; }), "entered folder");
    js("var e = createSheet.editor; var c = e.path[0]; e.path = []; e.chooseFolder(c)");
    check(waitFor([&]() { return js("createSheet.editor.folder").toString() == "f1"; }), "folder validated by folderCapabilities");
    js("createSheet.editor.save(); createSheet.editor.save()");
    check(waitFor([&]() { return js("stack.currentItem.localId === 'local-1'").toBool(); }), "REN-06 created rendition opens detail");
    check(js("stack.currentItem.tab === 'expenses' && stack.currentItem.expensesTab.visible").toBool(), "UI03 expense overview is the initial visible route");
    check(!js("modalOpen").toBool(), "SCROLL sheet closed releases the background");
    check(waitFor([&]() { return js("dockActions.map(function(a) { return a.id }).join(',')").toString()
                                 == "renditions.search,renditions.info,renditions.new,renditions.review"; }),
          "IMG2 rendition dock: Buscar, Información, +, Estado (3D Touch con Actividad; no Atrás)");
    check(js("dockActions[2].tapCommand === true && dockActions[2].children.length === 4").toBool(), "IMG2 + taps quick expense; Deep Press shows creation options");
    js("dockCommand('renditions.quickExpense')");
    check(waitFor([&]() { auto *p = root->findChild<QObject *>("expenseEditorPopup"); return p && p->property("visible").toBool(); }),
          "IMG2 + opens the approved expense editor (new expense)");
    QMetaObject::invokeMethod(root->findChild<QObject *>("expandedExpenseForm"), "requestClose");
    js("dockCommand('renditions.info')");
    check(waitFor([&]() { return js("infoPanel.open && infoPanel.financialRows.length === 6 && infoPanel.generalRows.length === 4").toBool(); }), "IMG2 Información selector with real values");
    js("dockCommand('renditions.activity')");
    check(js("activityPanel.open && !infoPanel.open").toBool(), "IMG2 Actividad selector replaces Información");
    js("dockCommand('renditions.search')");
    check(js("searchPanel.open && searchPanel.tab !== null").toBool(), "IMG2 Buscar selector bound to the real expenses list");
    js("searchPanel.close()");
    check(bridge.count("create") == 1, "REN-26 double tap sends one create");
    const auto create = bridge.lastCommand("create").value("arguments").toMap();
    check(create.value("periodStart") == "2026-10-01" && create.value("periodEnd") == "2026-10-31"
          && create.value("projectIds").toList().size() == 2 && create.value("primaryProjectId") == "p1"
          && create.value("documentParentNodeId") == "f1" && create.value("spaceId") == "space-1" && create.value("synchronize") == true,
          "create arguments follow bridge contract");
    check(waitFor([&]() { return !bridge.drafts.contains("header:new"); }), "draft cleared after save");

    // REN-10/16: gasto con sustento PDF.
    QTemporaryDir dir;
    QFile pdf(dir.filePath("boleta.pdf"));
    check(pdf.open(QIODevice::WriteOnly) && pdf.write("%PDF-1.4\n1 0 obj\n%%EOF\n") > 0, "pdf fixture"); pdf.close();
    js("openExpense('local-1', '')");
    check(waitFor([&]() { return depth() == 3; }), "expense editor opened");
    js(QStringLiteral("var e = stack.currentItem; e.projectId = 'p1'; e.expenseDate = '2026-10-09'; e.categoryCode = 'FOOD';"
                      "e.paymentMethodCode = 'CASH'; e.supportTypeCode = 'RECEIPT'; e.currencyCode = 'PEN';"
                      "e.fieldItem('amount').text = '125,50'; e.fieldItem('concept').text = 'Almuerzo de campo para cuadrilla';"
                      "e.fieldItem('beneficiary').text = 'Restaurante El Puente'; e.fieldItem('supportNumber').text = 'B001-884';"
                      "e.addFile('%1', 'file')").arg(QUrl::fromLocalFile(pdf.fileName()).toString()));
    check(js("stack.currentItem.pending.length").toInt() == 1, "receipt staged before save");
    js("stack.currentItem.confirmWaitMs = 300; stack.currentItem.save()");
    // Guardado sin acuse del servidor: cuadro "Gasto guardado" SIN confeti (no es "registrado").
    check(waitFor([&]() { return js("stack.currentItem.resultKind").toString() == "pending"; }), "REN-10 expense saved: pending result (no server confirmation)");
    check(js("stack.currentItem.celebrations").toInt() == 0 && visibleText("Gasto guardado") && !visibleText("Gasto registrado"),
          "CONF1 no confetti/registered dialog without server confirmation");
    check(visibleText("Ver en mis gastos") && visibleText("Registrar otro gasto"), "CONF2 result dialog actions");
    js("stack.currentItem.viewInExpenses()");
    check(waitFor([&]() { return depth() == 2; }), "REN-10 'Ver en mis gastos' returns to the rendition");
    const auto saved = bridge.lastCommand("saveExpense").value("arguments").toMap();
    const auto expense = saved.value("expense").toMap();
    check(saved.value("localId") == "local-1" && saved.value("expenseLocalId").toString().isEmpty() && saved.value("synchronize") == true,
          "saveExpense targets rendition");
    check(expense.value("amount") == "125.50" && expense.value("concept") == "Almuerzo de campo para cuadrilla"
          && expense.value("projectId") == "p1" && expense.value("expenseDate") == "2026-10-09" && expense.value("categoryCode") == "FOOD"
          && !expense.value("clientIntentId").toString().isEmpty(), "expense values normalized");
    const auto attachment = bridge.lastCommand("attachSupport").value("arguments").toMap().value("attachment").toMap();
    check(bridge.lastCommand("attachSupport").value("arguments").toMap().value("expenseLocalId") == "exp-1"
          && attachment.value("mimeType") == "application/pdf" && attachment.value("sizeBytes").toLongLong() == pdf.size()
          && attachment.value("fileName") == "boleta.pdf" && attachment.value("supportTypeCode") == "RECEIPT"
          && attachment.value("clientIntentId").toString().endsWith(attachment.value("localUri").toString()), "REN-16 attachSupport contract");
    check(js("stack.currentItem.objectName === '' && stack.currentItem.localId === 'local-1'").toBool(), "back on detail");
    check(waitFor([&]() { return root->findChild<QObject *>("expensesTab")->property("expenses").toList().size() == 1; }), "REN-13 expense listed in detail");
    {   // IMG2-B/C: gasto expandido en la misma ficha (formulario compacto + comprobantes), guarda con CAS.
        QObject *tabObj = root->findChild<QObject *>("expensesTab");
        QMetaObject::invokeMethod(tabObj, "expand", Q_ARG(QVariant, tabObj->property("expenses").toList().first()));
        check(waitFor([&]() { return root->findChild<QObject *>("expandedExpenseForm") != nullptr
                                     && root->findChild<QObject *>("expenseEditorPopup") != nullptr && root->findChild<QObject *>("expenseEditorPopup")->property("visible").toBool(); }), "IMG2 expense opens its editor in the same rendition");
        QObject *quick = root->findChild<QObject *>("expandedExpenseForm");
        check(quick->property("files").toList().size() >= 1, "IMG2 attachments listed inside the expanded expense");
        const int saves = bridge.count("saveExpense");
        QMetaObject::invokeMethod(quick, "save");
        check(waitFor([&]() { return bridge.count("saveExpense") == saves + 1; }), "IMG2 inline save uses saveExpense");
        const auto inlineArgs = bridge.lastCommand("saveExpense").value("arguments").toMap();
        check(inlineArgs.value("expenseLocalId") == "exp-1" && inlineArgs.contains("expectedExpenseRowVersion")
              && inlineArgs.value("expense").toMap().value("concept") == "Almuerzo de campo para cuadrilla", "IMG2 inline edit keeps identity, CAS and data");
        check(waitFor([&]() { return tabObj->property("expandedId").toString().isEmpty(); }), "IMG2 expanded form closes after saving");
    }

    // REN-14/15: fondo PEN/USD y tipo de cambio manual.
    QObject *financial = root->findChild<QObject *>("financialTab");
    check(financial != nullptr, "financial tab exists");
    financial->setProperty("fundEnabled", true);
    root->findChild<QObject *>("fundPen")->setProperty("text", "500");
    root->findChild<QObject *>("fundUsd")->setProperty("text", "100");
    financial->setProperty("dirtyFund", true);
    QMetaObject::invokeMethod(financial, "saveFunding");
    check(waitFor([&]() { return bridge.count("saveFinancial") == 1; }), "REN-14 fund submitted");
    auto fund = bridge.lastCommand("saveFinancial").value("arguments").toMap();
    check(fund.value("kind") == "funding_set" && fund.value("localId") == "local-1" && fund.value("expectedRowVersion").toInt() == 0
          && fund.value("values").toMap().value("pen") == "500" && fund.value("values").toMap().value("usd") == "100"
          && fund.value("values").toMap().value("enabled") == true, "funding_set with CAS");
    root->findChild<QObject *>("exchangeRate")->setProperty("text", "3,75");
    QMetaObject::invokeMethod(financial, "saveManualRate");
    check(waitFor([&]() { return bridge.count("saveFinancial") == 2; }), "REN-15 manual rate submitted");
    const auto manual = bridge.lastCommand("saveFinancial").value("arguments").toMap().value("values").toMap();
    check(manual.value("mode") == "MANUAL" && manual.value("rate") == "3.75" && manual.value("quoted_on").isNull(), "exchange_set manual");
    check(waitFor([&]() { return financial->property("balance").toMap().value("penCents").isValid(); }), "fund balance computed in C++");

    // Sincronizar y cotización automática sin origen configurado.
    js("synchronize()");
    check(waitFor([&]() { return js("stack.currentItem.current.syncState").toString() == "SYNCED"; }), "REN-23 synced keeps same local identity");
    check(js("stack.currentItem.current.remoteId").toString() == "remote-1" && js("stack.currentItem.localId").toString() == "local-1",
          "remote UUID adopted for the same rendition");
    financial->setProperty("automatic", true);
    QMetaObject::invokeMethod(financial, "quote");
    check(waitFor([&]() { return financial->property("rateError").toString().contains("no está configurada"); }), "QUOTE_ORIGIN_NOT_CONFIGURED explained");
    check(bridge.lastCommand("exchangeQuote").value("arguments").toMap().value("renditionId") == "remote-1", "quote uses remote id");
    check(bridge.count("saveFinancial") == 2, "no invented quote saved");

    // REN-18/19: presentar y revisión.
    js("stack.currentItem.tab = 'review'");
    QObject *review = root->findChild<QObject *>("reviewTab");
    check(review->property("presentBlocker").toString().isEmpty(), "presentation allowed when synced");
    QMetaObject::invokeMethod(review, "present");
    js("var cb = confirmDialog.acceptCallback; confirmDialog.close(); cb()");
    check(waitFor([&]() { return js("stack.currentItem.current.status").toString() == "EN_REVISION"; }), "REN-18 presented");
    check(waitFor([&]() { return bridge.count("reviewContext") >= 1; }), "REN-19 review context requested");
    check(bridge.lastCommand("reviewContext").value("arguments").toMap().value("renditionId") == "remote-1", "review context by remote id");
    check(waitFor([&]() { return review->property("versions").toList().size() == 1; }), "REN-19 versions listed");
    check(!js("stack.currentItem.writable").toBool(), "REN-25 presented rendition read only");

    // REN-05: desde otra pestaña, atrás vuelve primero a la vista general de gastos;
    // desde la vista general, vuelve a la lista y libera la selección.
    check(back() && js("stack.currentItem.tab").toString() == "expenses" && depth() == 2, "back from review returns to expense overview");
    check(back() && waitFor([&]() { return depth() == 1; }), "back to renditions home");
    check(waitFor([&]() { return bridge.count("closeDetail") >= 1; }), "detail closed in bridge");
    check(!back(), "REN-05 at root back returns to InGe+ Home");

    // REN-20: rendiciones recibidas.
    js("stack.currentItem.selectStatus('RECEIVED')");
    check(waitFor([&]() { return js("stack.currentItem.received.length").toInt() == 1; }), "REN-20 received list loaded");
    js("openReceived(stack.currentItem.received[0])");
    check(waitFor([&]() { return depth() == 2 && js("stack.currentItem.snapshot !== null").toBool(); }), "received snapshot loaded");
    const auto query = bridge.lastCommand("receivedQuery").value("arguments").toMap();
    check(query.value("renditionId") == "remote-9" && query.value("versionId") == "v9" && query.value("versionNumber").toInt() == 2
          && query.value("hash").toString().size() == 64, "receivedQuery identity");
    check(waitFor([&]() { return bridge.count("receivedNotes") == 1 && bridge.count("receivedActivity") == 1; }), "notes and activity requested");
    js("stack.currentItem.receive()");
    check(waitFor([&]() { return js("stack.currentItem.receivedAt.length > 0").toBool(); }), "reception registered");
    const auto receive = bridge.lastCommand("receive").value("arguments").toMap();
    check(receive.value("renditionId") == "remote-9" && !receive.value("requestId").toString().isEmpty(), "receive idempotency id");
    back();
    check(waitFor([&]() { return bridge.count("receivedClose") == 1; }), "received query closed");

    // REN-21: un formulario sin guardar se recupera al volver.
    js("openCreate()");
    check(waitFor([&]() { return js("createSheet.editor !== null").toBool(); }), "second sheet opened");
    js("var e = createSheet.editor; e.start = '2026-11-02'; e.changed()");
    check(waitFor([&]() { return bridge.drafts.value("header:new").toMap().value("periodStart") == "2026-11-02"; }, 2000), "draft persisted");
    back();
    check(waitFor([&]() { return !js("createSheet.visible").toBool(); }), "sheet closed by Back");
    js("openCreate()");
    check(waitFor([&]() { return js("createSheet.editor !== null").toBool(); }), "sheet reopened");
    check(js("createSheet.editor.restored && createSheet.editor.start === '2026-11-02'").toBool(), "REN-21 unsaved header restored");
    back();
    check(waitFor([&]() { return !js("createSheet.visible").toBool() && depth() == 1; }), "sheet closed before connectivity checks");

    // ================= P0 conectividad y auras (pantallas reales, bridge sintético)
    QObject *aura = root->findChild<QObject *>("syncAura");
    check(aura != nullptr, "single shell aura exists");
    check(visibleText("Rendiciones") || visibleText("RDC-"), "visible text probe sees the real screen");
    const auto settle = [&](int ms) { waitFor([]() { return false; }, ms); };
    // Ficha remota cuyo detalle nunca se descargó (caso de la captura del A12).
    {
        QVariantMap r{{"localId", "local-2"}, {"remoteId", "remote-2"}, {"visibleCode", "RDC-2026-000024"},
                      {"status", "BORRADOR"}, {"can_edit_content", true}, {"rowVersion", 3},
                      {"syncState", "NEEDS_RECONCILIATION"}, {"reconcileReason", "DETAIL_NOT_LOADED"},
                      {"pendingCount", 0}, {"periodStart", "2026-10-01"}, {"periodEnd", "2026-10-31"},
                      {"projectIds", QVariantList{"p1"}}, {"primaryProjectId", "p1"}, {"documentParentNodeId", "f1"},
                      {"totalPen", 0}, {"totalUsd", 0}, {"expenseCount", 0}};
        bridge.renditions.append(r);
        bridge.push();
    }

    // PRUEBA A — Desconexión: el estado llega a QML, aura roja, sin avisos.
    check(waitFor([&]() { return js("syncMode").toString() == "synced"; }), "A0 online synced before outage");
    check(!aura->property("error").toBool(), "A0 aura not red while synced");
    js("toastText = ''");                                     // avisos de pasos anteriores (p. ej. recepción)
    bridge.connection = "OFFLINE";
    bridge.failOps = QStringList{"refresh", "sync", "bootstrap"};
    bridge.push();
    check(waitFor([&]() { return js("syncMode").toString() == "offline"; }), "A1 OFFLINE propagated to shell.syncMode");
    check(aura->property("mode").toString() == "offline" && aura->property("error").toBool(), "A2 aura enters red state");
    js("refresh()");
    js("synchronize()");                                      // botón manual (no silencioso)
    check(waitFor([&]() { return bridge.count("sync") >= 2 && !js("busy('sync')").toBool(); }), "A3 failed commands answered");
    settle(150);
    if (!js("toastText").toString().isEmpty()) std::cerr << "toast: " << js("toastText").toString().toStdString() << std::endl;
    check(js("toastText").toString().isEmpty(), "A4 no toast for connectivity failure");
    check(!visibleText("Sin conexión") && !visibleText("conexión con el servidor"), "A5 no offline banner/box on list");
    js("openDetail('local-2')");
    check(waitFor([&]() { return depth() == 2 && js("stack.currentItem.isRenditionDetail === true").toBool(); }), "A6 detail opens offline (local first)");
    settle(400);
    check(!js("stack.currentItem.conflict").toBool(), "A7 detail not loaded offline is NOT a conflict");
    check(js("stack.currentItem.editable").toBool(), "A8 offline detail stays editable (local work)");
    check(!visibleText("Conflicto con el servidor") && !visibleText("Sin conexión"), "A9 no conflict/offline box on detail");
    check(js("syncMode").toString() == "offline", "A10 aura stays red on detail");

    // PRUEBA D — Timeout/5xx: operación en espera (marca técnica) ≠ conflicto/error.
    {
        auto list = QVariantList{QVariantMap{{"localId", "exp-9"}, {"remoteId", ""}, {"concept", "Movilidad"}, {"amount", "12.50"},
                                             {"currencyCode", "PEN"}, {"syncState", "ERROR"}, {"syncError", "TRANSPORT_RETRY"},
                                             {"attachments", QVariantList{}}}};
        bridge.expenses.insert("local-2", list);
        for (int i = 0; i < bridge.renditions.size(); ++i) {
            auto r = bridge.renditions.at(i).toMap();
            if (r.value("localId") != "local-2") continue;
            r.insert("syncState", "PENDING_UPDATE"); r.insert("pendingCount", 1); r.insert("syncError", "");
            bridge.renditions[i] = r;
        }
        bridge.failCode = "TIMEOUT";
        bridge.push();
    }
    check(waitFor([&]() { return js("stack.currentItem.expenses.length").toInt() == 1; }), "D1 offline expense kept");
    check(js("syncState(stack.currentItem.expenses[0])").toString() == "PENDING_UPDATE", "D2 transport ERROR shown as pending");
    js("stack.currentItem.showSection('expenses')");
    settle(400);
    check(!visibleText("Error de sincronización") && !visibleText("TRANSPORT_RETRY"), "D3 no error badge/marker for waiting op");
    if (!visibleText("Pendiente de sincronizar")) {
        std::cerr << "tab=" << js("stack.currentItem.tab").toString().toStdString() << '\n';
        for (QQuickItem *item : visibleItems())
            if (item->property("text").isValid() && !item->property("text").toString().isEmpty())
                std::cerr << "  visible: " << item->property("text").toString().toStdString() << '\n';
    }
    check(visibleText("Pendiente de sincronizar"), "D4 pending badge shown");
    check(js("syncMode").toString() == "offline" && !js("stack.currentItem.conflict").toBool(), "D5 timeout is not a conflict");
    js("synchronize(true)");
    check(waitFor([&]() { return !js("busy('sync')").toBool(); }), "D6 timeout answered");
    settle(150);
    check(js("toastText").toString().isEmpty(), "D7 no toast for TIMEOUT");

    // PRUEBA E — Navegación: misma aura (única) en lista, detalle y editor de gastos.
    js("openExpense('local-2', '')");
    check(waitFor([&]() { return depth() == 3; }), "E1 expense editor opened offline");
    check(root->findChildren<QObject *>("syncAura").size() == 1 && aura->property("error").toBool(), "E2 single red aura behind editor");
    check(!visibleText("Sin conexión"), "E3 no offline text in editor");
    back();
    check(waitFor([&]() { return depth() == 2; }), "E4 back to detail");

    // PRUEBA B — Reconexión: sólo evidencia real (ONLINE) saca del rojo; luego pendientes.
    bridge.connection = "ONLINE";
    bridge.failOps.clear();
    bridge.phase = "PUSHING";
    bridge.push();
    check(waitFor([&]() { return js("syncMode").toString() == "syncing"; }), "B1 reconnection leaves red -> syncing");
    bridge.phase = "IDLE";
    bridge.push();
    check(waitFor([&]() { return js("syncMode").toString() == "pending"; }), "B2 pending operations reflected after reconnect");
    check(!aura->property("error").toBool(), "B3 aura no longer red");
    for (int i = 0; i < bridge.renditions.size(); ++i) {
        auto r = bridge.renditions.at(i).toMap();
        if (r.value("localId") != "local-2") continue;
        r.insert("syncState", "SYNCED"); r.insert("pendingCount", 0); bridge.renditions[i] = r;
    }
    bridge.expenses.insert("local-2", QVariantList{});
    bridge.push();
    check(waitFor([&]() { return js("syncMode").toString() == "synced"; }), "B4 synced after queue drained");
    settle(150);
    check(js("toastText").toString().isEmpty() && !visibleText("Sin conexión"), "B5 no reconnection notices");

    // PRUEBA C — Conflicto CAS real: distinto de desconexión, visible y con resolución.
    for (int i = 0; i < bridge.renditions.size(); ++i) {
        auto r = bridge.renditions.at(i).toMap();
        if (r.value("localId") != "local-2") continue;
        r.insert("syncState", "CONFLICT"); r.insert("syncError", "La cabecera cambió en Web mientras había cambios locales pendientes.");
        bridge.renditions[i] = r;
    }
    bridge.push();
    js("stack.currentItem.tab = 'expenses'");
    check(waitFor([&]() { return js("stack.currentItem.conflict").toBool(); }), "C1 real CAS conflict detected");
    check(js("syncMode").toString() == "error" && bridge.connection == "ONLINE", "C2 conflict is error, not offline");
    check(!js("stack.currentItem.editable").toBool(), "C3 local changes protected (no edit over conflict)");
    check(js("stack.currentItem.suggestions[0].key").toString() == "sync", "C4 safe resolution offered (bring server version)");
    check(!root->findChild<QObject *>("addQuickExpense")->property("enabledButton").toBool(), "C5 quick creation blocked during a real conflict");
    back();
    check(waitFor([&]() { return depth() == 1; }), "C6 back to list");

    // ================= Working Document en las pantallas reales (mismo editor, lista de Gastos)
    const auto setLocal2 = [&](const QVariantMap &values) {
        for (int i = 0; i < bridge.renditions.size(); ++i) {
            auto r = bridge.renditions.at(i).toMap();
            if (r.value("localId") != "local-2") continue;
            for (auto it = values.cbegin(); it != values.cend(); ++it) r.insert(it.key(), it.value());
            bridge.renditions[i] = r;
        }
        bridge.push();
    };
    setLocal2({{"syncState", "SYNCED"}, {"syncError", ""}, {"pendingCount", 0}, {"workingCount", 0}, {"workingConflictCount", 0}});
    js("openDetail('local-2')");
    check(waitFor([&]() { return depth() == 2 && js("stack.currentItem.isRenditionDetail === true").toBool() && !js("stack.busy").toBool(); }), "W-UI detail reopened");
    js("openExpense('local-2', '')");
    check(waitFor([&]() { return depth() == 3 && !js("stack.busy").toBool(); }), "W-UI expense editor opened");
    check(js("stack.currentItem.cloudDrafts").toBool() && js("JSON.stringify(dockActions)").toString().contains("Guardar como borrador"),
          "G1 cloud draft available for a confirmed rendition (Dock: Borrador)");
    js("stack.currentItem.fieldItem('concept').text = 'Peaje Panamericana'");
    js("stack.currentItem.dockCommand('renditions.page.draft')");
    check(waitFor([&]() { return bridge.count("saveWorking") >= 1 && js("stack.currentItem.workingId").toString() == "w-1"; }), "G1 draft saved from the Dock (keeps editing)");
    check(waitFor([&]() { return !bridge.drafts.contains("expense:local-2:new"); }), "G1 local 'new' copy handed over to the cloud draft (no duplicate)");
    back();
    check(waitFor([&]() { return depth() == 2; }), "G1 back to detail from General");
    const auto draftForm = bridge.lastCommand("saveWorking").value("arguments").toMap().value("form").toMap();
    check(draftForm.size() == 13 && draftForm.value("concept") == "Peaje Panamericana" && draftForm.value("supportDetail") == "",
          "G1 draft sends exactly the 13 contract fields");
    setLocal2({{"workingCount", 1}});
    js("stack.currentItem.showSection('expenses')");
    check(waitFor([&]() { return visibleText("1 borrador sin registrar") && visibleText("Peaje Panamericana"); }), "G2 draft listed in Expenses");
    check(visibleText("Pendiente de subir"), "G2 draft state shown (not yet confirmed by server)");
    js("openExpense('local-2', '', 'w-1')");
    check(waitFor([&]() { return depth() == 3 && !js("stack.busy").toBool(); }), "G3 continue draft in the same editor");
    check(js("stack.currentItem.draftMode").toBool() && js("stack.currentItem.title").toString() == "General"
          && js("stack.currentItem.headerChip.label").toString() == "Sin sincronizar", "G3 draft mode: section title + real draft chip");
    check(js("stack.currentItem.fieldItem('concept').text").toString() == "Peaje Panamericana", "G3 draft content restored");
    js("stack.currentItem.goToSection(3)");
    check(js("dockActions.filter(function(a) { return a.id === 'next' })[0].label").toString() == "Registrar gasto"
          && js("dockActions.filter(function(a) { return a.id === 'renditions.page.draft' }).length").toInt() == 1,
          "G3 explicit register / save draft actions in the Dock");
    js("stack.currentItem.dockCommand('renditions.page.next')");
    settle(150);
    check(bridge.count("promoteWorking") == 0 && !js("stack.currentItem.error").toString().isEmpty(), "G3 incomplete draft not promoted (same validation as expenses)");
    check(js("stack.currentItem.section").toInt() < 3, "G3 validation moves to the section to correct");
    for (int i = 0; i < 6 && depth() == 3; ++i) { back(); settle(50); }
    check(waitFor([&]() { return depth() == 2; }), "G3 back to detail");
    QObject *expensesTab = root->findChild<QObject *>("expensesTab");
    check(expensesTab != nullptr, "G4 expenses tab");
    QMetaObject::invokeMethod(expensesTab, "promote", Q_ARG(QVariant, bridge.workingRows.first()));
    check(waitFor([&]() { return bridge.count("promoteWorking") == 1; }), "G4 register from list");
    check(bridge.lastCommand("promoteWorking").value("arguments").toMap().value("workingId") == "w-1", "G4 promote targets the draft id");
    check(waitFor([&]() { return visibleText("Registro pendiente"); }), "G4 pending registration shown");
    // Conflicto real del borrador: identidad visual de conflicto + resolución explícita.
    {
        auto row = bridge.workingRows.first().toMap();
        row.insert("syncState", "CONFLICT"); row.insert("promoteRequested", false);
        row.insert("syncError", "Esta fila cambió en otra sesión. Tus cambios se conservaron; revisa la versión del servidor antes de continuar.");
        bridge.workingRows[0] = row;
        QVariantMap serverForm = row.value("form").toMap(); serverForm.insert("concept", "Peaje (Web)");
        bridge.inspectRow = {{"id", "w-1"}, {"state", "ACTIVE"}, {"row_version", 3}, {"payload", QVariantMap{{"form", serverForm}}}};
        setLocal2({{"workingConflictCount", 1}});
    }
    check(waitFor([&]() { return visibleText("Revisar versión del servidor") && js("syncMode").toString() == "error"; }), "G5 draft conflict visible; aura uses conflict identity");
    QObject *card = nullptr;                                  // delegado de Repeater: árbol visual
    for (QQuickItem *item : visibleItems()) if (item->objectName() == "draft:w-1") card = item;
    check(card != nullptr, "G5 draft card");
    QMetaObject::invokeMethod(card, "inspect");
    check(waitFor([&]() { return visibleText("Tus cambios: Peaje Panamericana") && visibleText("Servidor: Peaje (Web)"); }), "G5 field-by-field diff");
    for (QQuickItem *item : visibleItems()) if (item->objectName() == "draft:w-1") card = item;   // delegado vigente
    QMetaObject::invokeMethod(card, "resolve", Q_ARG(QVariant, true));
    check(waitFor([&]() { return bridge.count("resolveWorking") == 1; }), "G5 resolution sent");
    const auto resolve = bridge.lastCommand("resolveWorking").value("arguments").toMap();
    check(resolve.value("keepLocal").toBool() && resolve.value("serverRow").toMap().value("id") == "w-1", "G5 keep mine over the inspected server version");
    check(waitFor([&]() { return !js("busy('working:w-1')").toBool() && js("toastText").toString().contains("versión del servidor"); }), "G5 resolution confirmed (anti double-tap key released)");
    setLocal2({{"workingConflictCount", 0}});
    // Descartar (archivo autorizado; con confirmación).
    QMetaObject::invokeMethod(expensesTab, "discard", Q_ARG(QVariant, bridge.workingRows.first()));
    check(waitFor([&]() { return js("confirmDialog.opened").toBool(); }), "G6 discard asks confirmation");
    js("var cb = confirmDialog.acceptCallback; confirmDialog.close(); cb()");
    check(waitFor([&]() { return bridge.count("archiveWorking") == 1 && !visibleText("borrador sin registrar"); }), "G6 draft discarded");
    back();                                                   // sección Gastos -> Resumen (detalle aprobado)
    check(waitFor([&]() { return js("stack.currentItem.tab").toString() == "expenses"; }), "G7 back to expense overview");
    back();
    check(waitFor([&]() { return depth() == 1; }), "G7 back to list");

    // ================= Nuevo gasto: 4 secciones, Dock 3D Touch y herramientas por sección
    setLocal2({{"syncState", "SYNCED"}, {"syncError", ""}, {"pendingCount", 0}, {"workingCount", 0}, {"workingConflictCount", 0}});
    js("openDetail('local-2')");
    check(waitFor([&]() { return depth() == 2 && js("stack.currentItem.isRenditionDetail === true").toBool() && !js("stack.busy").toBool(); }), "N0 detail opened");
    js("openExpense('local-2', '')");
    check(waitFor([&]() { return depth() == 3 && !js("stack.busy").toBool(); }), "N0 Nuevo gasto opened");
    QObject *headerTitle = root->findChild<QObject *>("headerTitle");
    check(js("stack.currentItem.sections.length").toInt() == 4 && headerTitle->property("text").toString() == "General", "N1 four sections; header shows the section name");
    check(js("stack.currentItem.headerChip.label").toString().startsWith("Borrador") && visibleText("Información general")
          && !visibleText("Paso 1") && !visibleText("1 de 4"), "N2 draft chip, no top progress timeline");
    check(!root->findChild<QObject *>("headerSyncButton")->property("visible").toBool(), "N2 header shows the draft chip instead of the sync button");
    check(js("dockContextId").toString() == "rendiciones/expense", "N3 expense dock context");
    check(js("dockActions.map(function(a) { return a.id }).join(',')").toString()
          == "previous,renditions.page.draft,next,renditions.tool.today,renditions.tool.period,renditions.tool.reuse",
          "N4 Dock: [Volver][Borrador][Siguiente][··· tools of General]");
    check(js("dockActions[0].tapCommand && dockActions[1].tapCommand && dockActions[2].tapCommand").toBool(), "N5 tap executes; Deep Press opens the 3D Touch menu");
    check(js("dockActions[0].children.map(function(c) { return c.label }).join('|')").toString()
          == "Volver a la lista de gastos|Salir sin guardar|Cancelar registro", "N6 Volver menu");
    check(js("dockActions[1].children.map(function(c) { return c.label }).join('|')").toString()
          == "Guardar como borrador|Ver mis borradores|Recuperar último borrador", "N7 Borrador menu");
    check(js("dockActions[2].children[2].label === 'Validar datos con IA' && dockActions[2].children[2].enabled === false").toBool(),
          "N8 AI entry prepared but disabled");
    js("var e = stack.currentItem; e.projectId = 'p1'; e.categoryCode = 'FOOD';"
       "e.fieldItem('concept').text = 'Movilidad a campamento minero'; e.fieldItem('beneficiary').text = 'Transportes Andinos'; e.changed()");
    js("dockCommand('renditions.tool.today')");
    check(js("stack.currentItem.expenseDate === ctl.today()").toBool(), "T1 Usar fecha de hoy");
    js("stack.currentItem.expenseDate = '2026-10-09'");
    js("dockCommand('renditions.tool.period')");
    check(js("stack.currentItem.toolMenu.open").toBool() && js("stack.currentItem.toolBody").toString().contains("dentro del período"), "T2 Revisar período permitido");
    check(back() && depth() == 3 && !js("stack.currentItem.toolMenu.open").toBool(), "T2 Back closes the tool menu first");
    js("dockCommand('renditions.page.next')");
    check(js("stack.currentItem.section").toInt() == 1 && headerTitle->property("text").toString() == "Comprobante", "N9 Siguiente -> Comprobante");
    check(js("stack.currentItem.pagerTrack.x").toDouble() == -js("stack.currentItem.width").toDouble(), "N9 reduced motion: section change without animation");
    check(js("dockActions.slice(3).map(function(a) { return a.id + ':' + a.enabled }).join(',')").toString()
          == "renditions.tool.requirements:true,renditions.tool.noReceipt:false,renditions.tool.help:true",
          "T3 Comprobante tools; 'sin comprobante' only when the catalog allows it");
    js("dockCommand('renditions.tool.requirements')");
    check(js("stack.currentItem.toolBody").toString().contains("tipo de comprobante"), "T4 Revisar requisitos");
    js("var e = stack.currentItem; e.closeTools(); e.supportTypeCode = 'RECEIPT'; e.fieldItem('supportNumber').text = 'B002-17'");
    js("dockCommand('renditions.page.next')");
    check(js("stack.currentItem.section").toInt() == 2 && headerTitle->property("text").toString() == "Pago e importe", "N10 Siguiente -> Pago e importe");
    js("var e = stack.currentItem; e.paymentMethodCode = 'CASH'; e.fieldItem('amount').text = '118.00'");
    js("dockCommand('renditions.tool.igv')");
    check(js("stack.currentItem.toolActionLabel").toString().isEmpty() && js("stack.currentItem.toolBody").toString().contains("sólo se desglosa"),
          "T5 IGV is not computed for receipts without tax credit");
    js("var e = stack.currentItem; e.closeTools(); e.supportTypeCode = 'FACTURA'");
    js("dockCommand('renditions.tool.igv')");
    check(js("stack.currentItem.toolActionLabel").toString() == "Aplicar al formulario" && js("stack.currentItem.fieldItem('subtotal').text").toString().isEmpty(),
          "T6 IGV shown with its assumption; nothing applied without confirmation");
    js("var e = stack.currentItem; var a = e.toolAction; e.closeTools(); a()");
    check(js("stack.currentItem.fieldItem('subtotal').text").toString() == "100.00" && js("stack.currentItem.fieldItem('igv').text").toString() == "18.00",
          "T7 IGV applied deterministically (118.00 = 100.00 + 18.00)");
    js("stack.currentItem.fieldItem('igv').text = '10.00'; dockCommand('renditions.tool.amounts')");
    check(js("stack.currentItem.toolBody").toString().contains("no coincide"), "T8 Validar importes detects inconsistency");
    js("var e = stack.currentItem; e.closeTools(); e.fieldItem('igv').text = '18.00'; dockCommand('renditions.tool.breakdown')");
    check(js("stack.currentItem.toolBody").toString().contains("Subtotal") && js("stack.currentItem.toolBody").toString().contains("IGV"), "T9 Revisar desglose");
    js("var e = stack.currentItem; e.closeTools(); e.supportTypeCode = 'RECEIPT'; e.fieldItem('subtotal').text = ''; e.fieldItem('igv').text = ''");
    check(back() && js("stack.currentItem.section").toInt() == 1 && depth() == 3, "N11 Back returns to the previous section");
    check(js("stack.currentItem.fieldItem('concept').text").toString() == "Movilidad a campamento minero"
          && js("stack.currentItem.fieldItem('amount').text").toString() == "118.00", "N12 no data lost between sections");
    js("dockCommand('renditions.page.toSupports')");
    check(js("stack.currentItem.section").toInt() == 3 && headerTitle->property("text").toString() == "Sustentos"
          && js("dockActions[2].label").toString() == "Registrar gasto", "N13 last section: main action is Registrar gasto");
    check(js("dockActions.slice(3).map(function(a) { return a.id + ':' + a.enabled }).join(',')").toString()
          == "renditions.tool.files:false,renditions.tool.replace:false,renditions.tool.retry:false",
          "T10 Sustentos tools enabled only when they apply");
    js(QStringLiteral("stack.currentItem.addFile('%1', 'file')").arg(QUrl::fromLocalFile(pdf.fileName()).toString()));
    check(js("dockActions.slice(3).map(function(a) { return a.enabled }).join(',')").toString() == "true,true,false", "T11 attachments can be viewed/replaced; no retry without pending uploads");
    js("stack.currentItem.confirmWaitMs = 5000; dockCommand('renditions.page.next')");
    check(waitFor([&]() { return bridge.lastCommand("saveExpense").value("arguments").toMap().value("localId") == "local-2"
                                 && bridge.lastCommand("attachSupport").value("arguments").toMap().value("localId") == "local-2"; }),
          "N14 Registrar gasto uses the existing saveExpense + attachSupport engine");
    check(js("stack.currentItem.resultKind").toString().isEmpty() && js("stack.currentItem.celebrations").toInt() == 0, "CONF3 no celebration before server confirmation");
    {
        auto list = bridge.expenses.value("local-2").toList();
        auto e = list.last().toMap(); e.insert("syncState", "SYNCED"); e.insert("remoteId", "re-1"); list[list.size() - 1] = e;
        bridge.expenses.insert("local-2", list);
        bridge.push();
    }
    check(waitFor([&]() { return js("stack.currentItem.resultKind").toString() == "confirmed"; }), "CONF4 server confirmation -> Gasto registrado");
    check(js("stack.currentItem.celebrations").toInt() == 1 && visibleText("Gasto registrado") && visibleText("El gasto se ha guardado correctamente."),
          "CONF5 confetti + approved dialog only on real confirmation");
    check(!root->findChild<QObject *>("confetti")->property("running").toBool(), "CONF6 reduced motion: no confetti animation");
    check(js("stack.currentItem.headerChip.label").toString() == "Registrado", "N15 chip reflects the registered state");
    js("stack.currentItem.registerAnother()");
    check(waitFor([&]() { return depth() == 3 && !js("stack.busy").toBool() && js("stack.currentItem.resultKind === '' && stack.currentItem.section === 0").toBool(); }),
          "N16 Registrar otro gasto opens a clean form");
    check(js("stack.currentItem.fieldItem('concept').text").toString().isEmpty(), "N16 clean form");
    check(js("dockActions[5].enabled").toBool(), "T12 Reutilizar datos anteriores enabled with a previous expense");
    js("dockCommand('renditions.tool.reuse')");
    check(js("stack.currentItem.reuseMenu.open").toBool(), "T12 reuse chooser opened");
    js("var e = stack.currentItem; e.reuse(e.previousExpenses[0])");
    check(js("stack.currentItem.categoryCode").toString() == "FOOD" && js("stack.currentItem.fieldItem('beneficiary').text").toString() == "Transportes Andinos"
          && js("stack.currentItem.fieldItem('amount').text").toString().isEmpty() && js("stack.currentItem.fieldItem('supportNumber').text").toString().isEmpty(),
          "T13 reuse copies compatible data only (never amount or receipt number)");
    js("var e = stack.currentItem; e.fieldItem('beneficiary').text = 'Otro proveedor'; e.reuse(e.previousExpenses[0])");
    check(js("confirmDialog.opened").toBool() && js("stack.currentItem.fieldItem('beneficiary').text").toString() == "Otro proveedor",
          "T14 confirmation before overwriting existing data");
    js("confirmDialog.close()");
    js("var e = stack.currentItem; e.fieldItem('concept').text = 'Gasto a descartar'; e.changed()");
    check(waitFor([&]() { return bridge.drafts.contains("expense:local-2:new"); }, 2000), "N17 local copy autosaved");
    js("dockCommand('renditions.page.exitNoSave')");
    check(waitFor([&]() { return js("confirmDialog.opened").toBool(); }), "N18 Salir sin guardar asks confirmation (no silent discard)");
    js("var cb = confirmDialog.acceptCallback; confirmDialog.close(); cb()");
    check(waitFor([&]() { return depth() == 2 && !bridge.drafts.contains("expense:local-2:new"); }), "N18 exit without saving clears only the unsaved copy");
    for (int i = 0; i < 4 && depth() > 1; ++i) { back(); settle(50); }
    check(waitFor([&]() { return depth() == 1; }), "N19 back to list");

    // ================= Auras A-F + panel "Estado de Rendiciones" en las pantallas reales
    QSignalSpy profileRequests(root, SIGNAL(requestOpenProfile()));
    const QVariantMap incompleteExpense{{"localId", "exp-bad"}, {"projectId", "p1"}, {"expenseDate", "2026-10-09"}, {"amount", "40.00"},
        {"currencyCode", "PEN"}, {"concept", "Combustible camioneta proyecto"}, {"paymentMethodCode", "CASH"}, {"supportTypeCode", "RECEIPT"},
        {"syncState", "SYNCED"}, {"attachments", QVariantList{QVariantMap{{"fileName", "vale.pdf"}, {"phase", "READY"}}}}};
    auto completeExpense = incompleteExpense; completeExpense.insert("categoryCode", "FOOD");
    setLocal2({{"pendingCount", 0}, {"syncState", "SYNCED"}, {"expenses", QVariantList{completeExpense}}});
    bridge.selected.clear(); bridge.push();
    check(waitFor([&]() { return js("syncMode").toString() == "synced"; }), "AURA-A all OK -> blue + green");
    check(js("dockActions.length").toInt() == 4 && js("dockActions[3].id").toString() == "renditions.status",
          "AURA-A 'Estado de Rendiciones' available from the first Home entry (4 slots, no 5th)");
    js("dockCommand('renditions.status')");
    check(waitFor([&]() { return js("statusPanel.open").toBool() && visibleText("Todo en orden. No hay fallos técnicos activos."); }),
          "PANEL opens with zero incidents and a clear healthy state");
    check(back() && !js("statusPanel.open").toBool(), "PANEL zero-state closes with Back");
    // Un gasto incompleto es una tarea del usuario: NO es incidencia ni cambia el aura.
    setLocal2({{"expenses", QVariantList{incompleteExpense}}});
    settle(150);
    check(js("syncMode").toString() == "synced" && js("incidentCount").toInt() == 0, "AURA-A incomplete expense is not a technical incident");
    auto rejectedExpense = incompleteExpense;
    rejectedExpense.insert("syncState", "ERROR"); rejectedExpense.insert("syncError", "El proyecto ya no admite gastos en este período.");
    setLocal2({{"expenses", QVariantList{rejectedExpense}}});
    check(waitFor([&]() { return js("syncMode").toString() == "attention"; }), "AURA-B localized technical failure -> blue + yellow");
    check(aura->property("attention").toBool() && !aura->property("error").toBool(), "AURA-B aura attention identity");
    check(!js("statusPanel.open").toBool(), "PANEL never opens by itself");
    js("dockCommand('renditions.status')");
    check(waitFor([&]() { return js("statusPanel.open").toBool() && visibleText("Estado de Rendiciones") && visibleText("Qué sucede")
                                 && visibleText("Causa:") && visibleText("Cómo solucionarlo") && visibleText("Abrir gasto"); }),
          "PANEL opened voluntarily with code/what/cause/how/action");
    js("runIncident(diagnostics.incidents.filter(function(i) { return i.code === 'EXPENSE_REJECTED' })[0])");
    check(waitFor([&]() { return depth() == 3 && !js("stack.busy").toBool() && js("stack.currentItem.expenseLocalId === 'exp-bad'").toBool(); }, 5000),
          "PANEL action navigates to the affected expense");
    check(js("stack.currentItem.section").toInt() == 0 && !js("statusPanel.open").toBool(), "PANEL action opens the section to correct");
    for (int i = 0; i < 4 && depth() > 1; ++i) { back(); settle(50); }
    check(waitFor([&]() { return depth() == 1; }), "PANEL back to list");
    bridge.connection = "AUTH_REQUIRED"; bridge.push();
    check(waitFor([&]() { return js("syncMode").toString() == "error"; }), "AURA-C session expired -> red beats yellow");
    js("toastText = ''");                                     // avisos breves de pasos anteriores
    js("synchronize(true); refresh()");
    settle(200);
    if (!js("toastText").toString().isEmpty()) std::cerr << "toast: " << js("toastText").toString().toStdString() << std::endl;
    check(js("toastText").toString().isEmpty() && !visibleText("La sesión expiró"), "AURA-C no session-expired banner/box/toast");
    check(js("diagnostics.incidents[0].code").toString() == "SESSION_EXPIRED", "AURA-C session incident listed first");
    js("runIncident(diagnostics.incidents[0])");
    check(profileRequests.count() == 1, "AURA-C renew without AuthSession -> sign-in from Profile (no fake action)");
    bridge.connection = "OFFLINE"; bridge.push();
    check(waitFor([&]() { return js("syncMode").toString() == "offline"; }), "AURA-D offline red");
    check(js("diagnostics.incidents[0].code").toString() == "NO_NETWORK"
          && js("diagnostics.incidents.filter(function(i) { return i.code === 'SESSION_EXPIRED' }).length").toInt() == 0, "AURA-D offline is distinct from session expired");
    bridge.connection = "ONLINE"; bridge.push();
    check(waitFor([&]() { return js("syncMode").toString() == "attention"; }), "AURA-E real recovery leaves red (attention remains)");
    setLocal2({{"expenses", QVariantList{completeExpense}}});
    check(waitFor([&]() { return js("syncMode").toString() == "synced" && js("dockActions.length").toInt() == 4; }),
          "AURA-F recovered -> green; status stays available");
    js("toast('No se pudo abrir el archivo del sustento.', 'error')");
    check(js("toastText").toString().isEmpty() && js("syncMode").toString() == "error", "PANEL error notices go to the panel, not a box");
    js("dockCommand('renditions.status')");
    check(waitFor([&]() { return js("statusPanel.open").toBool() && visibleText("No se pudo abrir el archivo del sustento."); }), "PANEL shows the action failure");
    js("runIncident(diagnostics.incidents[0])");
    check(waitFor([&]() { return js("syncMode").toString() == "synced"; }), "PANEL 'Entendido' resolves the incident");
    check(back() && !js("statusPanel.open").toBool() && depth() == 1, "PANEL closes with Back");

    // ================= InGe IA (global en HomeScreen): contexto y herramienta nativa de Rendiciones
    const int savesBeforeAi = bridge.count("saveExpense");
    check(js("assistantModule.id === 'rendiciones' && assistantModule.tools[0].label === 'Registrar gasto' && assistantModule.tools[0].primary === true").toBool(),
          "IA Rendiciones publishes its native 'Registrar gasto' tool");
    check(!js("assistantValidate(assistantProposal({concept: 'Almuerzo de cuadrilla', amount: 'abc'})).ready").toBool(), "IA invalid amount is not ready");
    check(js("assistantProposal({concept: 'Taxi a obra', amount: 12, category: 'NO_EXISTE'}).categoryCode === ''").toBool(), "IA never invents catalog codes");
    js("var fa = { proposals: [], setProposals: function(l) { this.proposals = l } };"
       "var p = assistantValidate(assistantProposal({concept: 'Almuerzo de cuadrilla en obra', amount: 18, currency: 'PEN', category: 'FOOD'}));"
       "fa.proposals = [p]; assistantOpen(0, p, fa)");
    check(waitFor([&]() { return depth() == 3 && !js("stack.busy").toBool() && js("stack.currentItem.renditionLocalId === 'local-2'").toBool(); }, 5000),
          "IA proposal opens the existing ExpenseEditor");
    check(js("stack.currentItem.fieldItem('concept').text").toString() == "Almuerzo de cuadrilla en obra"
          && js("stack.currentItem.fieldItem('amount').text").toString() == "18" && js("stack.currentItem.categoryCode").toString() == "FOOD"
          && js("stack.currentItem.resultKind").toString().isEmpty(), "IA prefill is reviewed in the form; nothing registered yet");
    check(bridge.count("saveExpense") == savesBeforeAi, "IA never registers an expense automatically");
    js("dockCommand('renditions.page.exitNoSave')");
    check(waitFor([&]() { return js("confirmDialog.opened").toBool(); }), "IA draft can be discarded with confirmation");
    js("var cb = confirmDialog.acceptCallback; confirmDialog.close(); cb()");
    for (int i = 0; i < 4 && depth() > 1; ++i) { waitFor([&]() { return !js("stack.busy").toBool(); }); back(); settle(50); }
    check(waitFor([&]() { return depth() == 1; }), "IA back to list");

    // ================= Archivero y Papelera (Files v07): consulta y recuperación reversible
    check(root->findChild<QObject *>("menuTrash")->property("glyph").toInt() == 0xE18E, "PAP1 Papelera menu item uses the trash icon");
    js("openFiles('archive')");
    check(waitFor([&]() { return depth() == 2 && js("stack.currentItem.objectName").toString() == "filesBrowser"; }), "F1 archive opened from folder menu");
    check(waitFor([&]() { return js("stack.currentItem.items.length").toInt() == 1; }), "F1 archive listed after contract check");
    check(root->findChild<QObject *>("headerSyncButton")->property("visible").toBool(), "PAP2 Archivero unchanged (keeps its header)");
    check(visibleText("Informe topográfico.pdf") && visibleText("puede reactivarse"), "F1 archived item and state");
    js("stack.currentItem.startRecovery(stack.currentItem.items[0])");
    check(waitFor([&]() { return js("!!stack.currentItem.plan && stack.currentItem.plan.token === 'preview-token-1'").toBool(); }), "F2 recovery preview with token");
    check(visibleText("Ubicación original: Presa Norte / Informes"), "F2 origin shown before confirming");
    js("stack.currentItem.recover()");
    check(waitFor([&]() { return js("stack.currentItem.items.length").toInt() == 0; }), "F2 reactivated item leaves the archive");
    const auto recover = bridge.lastCommand("filesRecover").value("arguments").toMap();
    check(recover.value("entityId") == "n-archived-1" && recover.value("expectedVersion").toInt() == 3
          && recover.value("previewToken") == "preview-token-1" && QUuid(recover.value("requestId").toString()).isNull() == false,
          "F2 mutation uses expected version + preview token + idempotent request");
    // Origen movido: destino alternativo validado por el servidor.
    bridge.filesItems = QVariantList{QVariantMap{{"id", "n-archived-2"}, {"name", "Plano.dwg"}, {"space_id", "space-1"},
        {"space_name", "Presa Norte"}, {"origin", "Presa Norte / Planos"}, {"updated_at", "2026-10-11T10:00:00Z"}, {"node_version", 5},
        {"kind", "BINARY_DOCUMENT"}, {"parent_node_id", QVariant()}, {"project_id", "p1"}, {"started", false}, {"request_id", QVariant()},
        {"can_restore", true}, {"lifecycle", "ARCHIVED"}, {"can_reactivate", true}, {"requires_destination", true}, {"origin_state", "MOVED"}}};
    bridge.requireDestination = true;
    js("stack.currentItem.load('', false)");
    check(waitFor([&]() { return js("stack.currentItem.items.length").toInt() == 1; }), "F3 moved-origin item listed");
    js("stack.currentItem.startRecovery(stack.currentItem.items[0])");
    check(waitFor([&]() { return js("stack.currentItem.choosingDestination").toBool(); }), "F3 destination required");
    check(!js("stack.currentItem.plan.token").isValid() || js("stack.currentItem.plan.token === null").toBool(), "F3 no token without destination");
    js("stack.currentItem.chooseProject('p1')");
    check(waitFor([&]() { return js("stack.currentItem.destFolders.length").toInt() == 1; }), "F3 project folders listed");
    js("stack.currentItem.loadDestFolders('f1', stack.currentItem.destFolders[0])");
    check(waitFor([&]() { return js("stack.currentItem.destPath.length").toInt() == 1; }), "F3 folder entered");
    js("stack.currentItem.useDestination()");
    check(waitFor([&]() { return js("!!stack.currentItem.plan && stack.currentItem.plan.token === 'preview-token-1'").toBool(); }), "F3 preview repeated with validated destination");
    const auto chosen = bridge.lastCommand("filesCanChoose").value("arguments").toMap();
    check(chosen.value("spaceId") == "space-1" && chosen.value("nodeId") == "f1", "F3 destination validated by server");
    js("stack.currentItem.recover()");
    check(waitFor([&]() { return bridge.lastCommand("filesRecover").value("arguments").toMap().value("destinationNodeId") == "f1"; }), "F3 recovered into chosen folder");
    bridge.requireDestination = false;
    back();
    check(waitFor([&]() { return depth() == 1; }), "F4 back to list");
    js("openFiles('trash')");
    check(waitFor([&]() { return bridge.count("filesTrash") >= 1 && depth() == 2; }), "F5 global trash opened");
    check(!root->findChild<QObject *>("headerSyncButton")->property("visible").toBool() && !visibleText("Sincronizado"),
          "PAP3 no 'Sincronizado' button on the Papelera screen");
    back();
    check(waitFor([&]() { return depth() == 1; }), "F5 back to list");
    for (const auto &command : bridge.commands) {
        const QString op = command.toMap().value("operation").toString();
        check(!op.contains("urge", Qt::CaseInsensitive), "F6 no purge command ever sent from mobile");
    }

    // Ninguna advertencia QML en todo el recorrido.
    QCoreApplication::processEvents();
    for (const auto &warning : qmlWarnings) std::cerr << "QML WARNING: " << warning.toStdString() << '\n';
    check(qmlWarnings.isEmpty(), "no QML warnings during the flow");
    delete root;
    window.close();
    std::cout << "PASS renditions QML flow: " << checks << " checks\n";
    return 0;
}

#include "qml_flow.moc"
