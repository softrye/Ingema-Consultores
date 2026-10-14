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
#include <QTemporaryDir>
#include <QTimer>
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
        emitEvent({{"type", "state"}, {"connectionState", "ONLINE"}, {"syncPhase", "IDLE"}, {"busy", false},
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
                   {"attachments", QVariantList{}}, {"remoteCurrent", QVariantMap{}}});
    }
    void handle(const QVariantMap &c)
    {
        const QString op = c.value("operation").toString();
        const QVariantMap a = c.value("arguments").toMap();
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
        if (op == "select") { selected = a.value("localId").toString(); publish(); ok(c, {{"current", rendition(selected)}}); return; }
        if (op == "closeDetail") { selected.clear(); publish(); ok(c); return; }
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
                         {"dockArea", 96}, {"glassFill", "#334"}, {"glassBorder", "#556"}, {"reducedMotion", true}};
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

    // REN-02/03/04: la subapp se crea y recupera el estado de la sesión vía bootstrap.
    check(waitFor([&]() { return controller.ready(); }), "REN-04 bootstrap publishes state");
    check(bridge.count("bootstrap") == 1, "bootstrap sent once");
    check(js("stack.currentItem.objectName").toString() == "renditionsHome", "REN-03 home screen created");

    // REN-06/07: nueva rendición con proyecto y carpeta de InGe Drive.
    js("openCreate()");
    check(waitFor([&]() { return depth() == 2; }), "editor opened");
    js("var e = stack.currentItem; e.start = '2026-10-01'; e.end = '2026-10-31'; e.toggleProject('p1'); e.toggleProject('p2'); e.setPrimary('p1'); e.changed()");
    check(waitFor([&]() { return bridge.count("saveEditorDraft") >= 1; }, 2000), "REN-21 header autosave persisted");
    check(waitFor([&]() { return bridge.drafts.contains("header:new"); }), "draft stored under header:new");
    js("stack.currentItem.openFolders()");
    check(waitFor([&]() { return js("stack.currentItem.browsing").toBool(); }), "InGe Drive folder browser opened");
    check(bridge.lastCommand("projectWorkspace").value("arguments").toMap().value("projectId") == "p1", "workspace of primary project");
    js("var e = stack.currentItem; e.loadFolders('f1', e.folders[0])");
    check(waitFor([&]() { return js("stack.currentItem.path.length").toInt() == 1; }), "entered folder");
    js("var e = stack.currentItem; var c = e.path[0]; e.path = []; e.chooseFolder(c)");
    check(waitFor([&]() { return js("stack.currentItem.folder").toString() == "f1"; }), "folder validated by folderCapabilities");
    js("stack.currentItem.save(); stack.currentItem.save()");
    check(waitFor([&]() { return js("stack.currentItem.localId === 'local-1'").toBool(); }), "REN-06 created rendition opens detail");
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
    js("stack.currentItem.save()");
    check(waitFor([&]() { return depth() == 2; }), "REN-10 expense saved and editor closed");
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

    // REN-05: atrás vuelve a la lista y libera la selección.
    check(back() && waitFor([&]() { return depth() == 1; }), "back to renditions home");
    check(waitFor([&]() { return bridge.count("closeDetail") >= 1; }), "detail closed in bridge");
    check(!back(), "REN-05 at root back returns to InGe+ Home");

    // REN-20: rendiciones recibidas.
    js("stack.currentItem.tab = 'received'; stack.currentItem.loadReceived()");
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
    check(waitFor([&]() { return depth() == 2; }), "second editor opened");
    js("var e = stack.currentItem; e.start = '2026-11-02'; e.changed()");
    check(waitFor([&]() { return bridge.drafts.value("header:new").toMap().value("periodStart") == "2026-11-02"; }, 2000), "draft persisted");
    back();
    check(waitFor([&]() { return depth() == 1; }), "left editor");
    js("openCreate()");
    check(waitFor([&]() { return depth() == 2; }), "editor reopened");
    check(js("stack.currentItem.restored && stack.currentItem.start === '2026-11-02'").toBool(), "REN-21 unsaved header restored");

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
