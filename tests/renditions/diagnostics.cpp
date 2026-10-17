// Modelo CENTRALIZADO de incidencias de Rendiciones (renditiondiagnostics.h) y
// su publicación en RenditionUiController (auras + panel "Estado de Rendiciones").
// Escenarios de auras A-F sobre estados publicados por un bridge sintético.
#include "src/cpp/renditiondiagnostics.h"
#include "src/cpp/renditionuicontroller.h"

#include <QCoreApplication>
#include <QJsonDocument>
#include <QSignalSpy>
#include <iostream>

static int checks = 0;
static void check(bool value, const char *label)
{
    ++checks;
    if (!value) { std::cerr << "FAIL " << label << '\n'; std::exit(1); }
}

class FakeBridge : public QObject
{
    Q_OBJECT
public:
    Q_INVOKABLE void submit(const QString &) {}
    void emitJson(const QVariantMap &event)
    {
        emit eventReady(QString::fromUtf8(QJsonDocument::fromVariant(event).toJson(QJsonDocument::Compact)));
    }
signals:
    void eventReady(const QString &eventJson);
};

static QVariantMap completeExpense(const QString &id)
{
    return {{"localId", id}, {"projectId", "p1"}, {"expenseDate", "2026-10-09"}, {"amount", "125.50"}, {"currencyCode", "PEN"},
            {"concept", "Almuerzo de campo para cuadrilla"}, {"categoryCode", "FOOD"}, {"paymentMethodCode", "CASH"},
            {"supportTypeCode", "RECEIPT"}, {"syncState", "SYNCED"},
            {"attachments", QVariantList{QVariantMap{{"fileName", "boleta.pdf"}, {"phase", "READY"}}}}};
}
static QVariantMap rendition(const QString &id, const QVariantList &expenses, const QString &status = "BORRADOR")
{
    return {{"localId", id}, {"remoteId", "remote-" + id}, {"visibleCode", "RDC-2026-0000" + id}, {"status", status},
            {"can_edit_content", true}, {"rowVersion", 2}, {"syncState", "SYNCED"}, {"periodStart", "2026-10-01"},
            {"periodEnd", "2026-10-31"}, {"projectIds", QVariantList{"p1"}}, {"expenses", expenses}};
}
static QVariantMap state(const QString &connection, const QVariantList &renditions, const QString &connectivity = {})
{
    return {{"connectionState", connection}, {"connectivity", connectivity}, {"renditions", renditions}};
}
static QStringList codes(const QVariantMap &d)
{
    QStringList out;
    for (const auto &v : d.value("incidents").toList()) out << v.toMap().value("code").toString();
    return out;
}
static QVariantMap incident(const QVariantMap &d, const QString &code)
{
    for (const auto &v : d.value("incidents").toList()) if (v.toMap().value("code") == code) return v.toMap();
    return {};
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    namespace D = RenditionDiagnostics;

    // A — Todo en orden: azul + verde (sin incidencias).
    auto ok = D::evaluate(state("ONLINE", {rendition("1", {completeExpense("e1")})}));
    check(ok.value("level") == "ok" && ok.value("incidents").toList().isEmpty(), "A OK state has no incidents (green)");

    // B0 — Tareas del usuario NO son incidencias: gasto incompleto, sin sustento u
    // observado mantienen el sistema saludable (sin contador ni cambio de aura).
    auto noCategory = completeExpense("e2"); noCategory.remove("categoryCode");
    auto noSupportType = completeExpense("e3"); noSupportType.insert("supportTypeCode", "");
    auto noFiles = completeExpense("e4"); noFiles.insert("attachments", QVariantList{});
    auto observed = completeExpense("e5"); observed.insert("reviewStatus", "OBSERVADO");
    auto tasks = D::evaluate(state("ONLINE", {rendition("1", {noCategory, noSupportType, noFiles, observed})}));
    check(tasks.value("level") == "ok" && tasks.value("incidents").toList().isEmpty(), "B0 incomplete/unsupported/observed expenses are not technical incidents");

    // B — Atención TÉCNICA localizada: azul + amarillo (rechazo real, carga fallida).
    auto rejected = completeExpense("e6"); rejected.insert("syncState", "ERROR"); rejected.insert("syncError", "El proyecto ya no admite gastos.");
    auto waiting = completeExpense("e7"); waiting.insert("syncState", "ERROR"); waiting.insert("syncError", "TRANSPORT_RETRY");
    auto failedUpload = completeExpense("e8");
    failedUpload.insert("attachments", QVariantList{QVariantMap{{"fileName", "vale.jpg"}, {"phase", "RESERVE"},
                                                               {"syncState", "ERROR"}, {"syncError", "Tipo de archivo no permitido."}}});
    auto b = D::evaluate(state("ONLINE", {rendition("1", {rejected, waiting, failedUpload})}));
    check(b.value("level") == "attention" && b.value("errors").toInt() == 0 && b.value("attention").toInt() == 2, "B localized technical attention -> yellow");
    const auto incRejected = incident(b, "EXPENSE_REJECTED");
    check(incRejected.value("expenseLocalId") == "e6" && incRejected.value("action").toMap().value("kind") == "openExpense",
          "B1 rejected expense -> open the expense");
    const auto incUpload = incident(b, "UPLOAD_FAILED");
    check(incUpload.value("section") == "supports" && incUpload.value("action").toMap().value("kind") == "retry", "B2 failed upload -> retry");
    check(!codes(b).contains("SYNC_REJECTED") && b.value("incidents").toList().size() == 2, "B3 transport wait is not an incident");
    for (const auto &v : b.value("incidents").toList()) {
        const auto m = v.toMap();
        check(!m.value("title").toString().isEmpty() && !m.value("code").toString().isEmpty() && !m.value("area").toString().isEmpty()
              && !m.value("what").toString().isEmpty() && !m.value("cause").toString().isEmpty() && !m.value("how").toString().isEmpty(),
              "B4 every incident has name, code, location, what, cause and how");
    }

    // C — Prioridad: rojo > amarillo; lo bloqueante se lista primero.
    auto conflict = rendition("2", {}); conflict.insert("syncState", "CONFLICT"); conflict.insert("syncError", "La cabecera cambió en Web.");
    auto c = D::evaluate(state("ONLINE", {rendition("1", {rejected}), conflict}));
    check(c.value("level") == "error" && c.value("errors").toInt() == 1 && c.value("attention").toInt() >= 1, "C error wins over attention (red)");
    check(c.value("incidents").toList().first().toMap().value("code") == "RENDITION_CONFLICT", "C1 blocking incidents first");
    check(incident(c, "RENDITION_CONFLICT").value("action").toMap().value("kind") == "openRendition", "C2 conflict offers the CAS review flow");

    // D — Sesión expirada ≠ pérdida de red ≠ servidor inaccesible.
    auto session = D::evaluate(state("AUTH_REQUIRED", {rendition("1", {completeExpense("e1")})}));
    check(codes(session) == QStringList{"SESSION_EXPIRED"} && session.value("level") == "error", "D1 session expired is its own error");
    check(incident(session, "SESSION_EXPIRED").value("action").toMap().value("kind") == "renewSession", "D2 renew session action (real auth)");
    auto offline = D::evaluate(state("OFFLINE", {rendition("1", {completeExpense("e1")})}, "NO_NETWORK"));
    check(codes(offline) == QStringList{"NO_NETWORK"} && !codes(offline).contains("SESSION_EXPIRED"), "D3 offline is not session expired");
    check(incident(offline, "NO_NETWORK").value("action").toMap().isEmpty(), "D4 no fake action without network");
    auto server = D::evaluate(state("OFFLINE", {}, "SERVER_UNREACHABLE"));
    check(codes(server) == QStringList{"SERVER_UNREACHABLE"} && incident(server, "SERVER_UNREACHABLE").value("action").toMap().value("kind") == "retry",
          "D5 server unreachable offers retry");

    // E — Recuperación: sólo un estado ONLINE real retira el rojo (sin incidencias obsoletas).
    auto recovered = D::evaluate(state("ONLINE", {rendition("1", {completeExpense("e1")})}));
    check(recovered.value("level") == "ok" && !codes(recovered).contains("NO_NETWORK"), "E recovery clears connection incident");

    // F — Operación en espera de transporte NO es rechazo; permiso es explicación sin acción.
    auto waiting = rendition("1", {}); waiting.insert("syncState", "ERROR"); waiting.insert("syncError", "TRANSPORT_RETRY");
    check(D::evaluate(state("ONLINE", {waiting})).value("level") == "ok", "F1 transport marker is not an error");
    auto denied = rendition("1", {}); denied.insert("syncState", "ERROR"); denied.insert("syncError", "No tiene permiso para editar esta rendición.");
    const auto permission = incident(D::evaluate(state("ONLINE", {denied})), "PERMISSION_DENIED");
    check(!permission.isEmpty() && permission.value("action").toMap().isEmpty(), "F2 permission explained without unauthorized action");

    // Borradores Working: conflicto (error) y bytes por volver a adjuntar (atención, ficha abierta).
    auto withDrafts = rendition("1", {}); withDrafts.insert("workingConflictCount", 1);
    QVariantMap ws = state("ONLINE", {withDrafts});
    ws.insert("selectedLocalId", "1");
    ws.insert("workingRows", QVariantList{QVariantMap{{"id", "w-9"}, {"missingSources", 1}, {"form", QVariantMap{{"concept", "Peaje"}}}}});
    auto w = D::evaluate(ws);
    check(incident(w, "WORKING_CONFLICT").value("action").toMap().value("kind") == "openExpenses", "W1 draft conflict -> review drafts");
    check(incident(w, "SUPPORT_REATTACH").value("workingId") == "w-9" && incident(w, "SUPPORT_REATTACH").value("section") == "supports",
          "W2 missing bytes -> open draft at Sustentos");

    // Sin duplicados ni secretos.
    auto dup = D::evaluate(state("ONLINE", {rendition("1", {rejected, rejected})}));
    check(dup.value("incidents").toList().size() == 1, "N1 no duplicated incidents");
    QVariantMap secret = state("AUTH_REQUIRED", {rendition("1", {})});
    secret.insert("accessToken", "eyJ-secret-token"); secret.insert("refreshToken", "refresh-secret");
    const QString json = QString::fromUtf8(QJsonDocument::fromVariant(D::evaluate(secret)).toJson());
    check(!json.contains("secret") && !json.contains("eyJ"), "N2 diagnostics never carry tokens");

    // ---- Publicación en el controlador (fuente de auras y panel).
    FakeBridge bridge;
    RenditionUiController ui(&bridge);
    QSignalSpy changed(&ui, &RenditionUiController::diagnosticsChanged);
    QVariantMap event = state("ONLINE", {rendition("1", {rejected})}); event.insert("type", "state");
    bridge.emitJson(event);
    check(ui.diagnostics().value("level") == "attention", "P1 controller publishes attention");
    const int afterFirst = changed.count();
    bridge.emitJson(event);
    check(changed.count() == afterFirst, "P2 identical state does not re-emit (no flicker)");
    ui.reportIssue("msg:x", {{"what", "No se pudo abrir el archivo."}, {"area", "Rendición RDC"}});
    check(ui.diagnostics().value("level") == "error" && !incident(ui.diagnostics(), "ACTION_FAILED").isEmpty()
          && incident(ui.diagnostics(), "ACTION_FAILED").value("action").toMap().value("kind") == "dismiss", "P3 action failure goes to the panel (no toast)");
    ui.reportIssue("msg:x", {{"what", "No se pudo abrir el archivo."}});
    check(ui.diagnostics().value("errors").toInt() == 1, "P4 repeated failure is one incident");
    ui.resolveIssue("msg:x");
    check(ui.diagnostics().value("level") == "attention", "P5 resolved issue leaves the panel");
    event = state("AUTH_REQUIRED", {rendition("1", {completeExpense("e1")})}); event.insert("type", "state");
    bridge.emitJson(event);
    check(ui.diagnostics().value("level") == "error" && codes(ui.diagnostics()) == QStringList{"SESSION_EXPIRED"}, "P6 session expired published");
    event = state("ONLINE", {rendition("1", {completeExpense("e1")})}); event.insert("type", "state");
    bridge.emitJson(event);
    check(ui.diagnostics().value("level") == "ok", "P7 renewed session returns to green");

    std::cout << "PASS rendition diagnostics: " << checks << " checks\n";
    return 0;
}

#include "diagnostics.moc"
