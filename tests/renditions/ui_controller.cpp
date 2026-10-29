// Adaptador de presentación de Rendiciones (RenditionUiController) y contrato
// comando -> RPC administrativa (RenditionAdminRpc). Bridge sintético: no
// prueba Supabase real.
#include "src/cpp/renditionadminrpc.h"
#include "src/cpp/renditionuicontroller.h"

#include <QCoreApplication>
#include <QFile>
#include <QJsonDocument>
#include <QSignalSpy>
#include <QTemporaryDir>
#include <QUrl>
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
    QStringList submitted;
    Q_INVOKABLE void submit(const QString &json) { submitted.append(json); }
    void emitJson(const QVariantMap &event)
    {
        emit eventReady(QString::fromUtf8(QJsonDocument::fromVariant(event).toJson(QJsonDocument::Compact)));
    }
signals:
    void eventReady(const QString &eventJson);
};

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    FakeBridge bridge;
    RenditionUiController ui(&bridge);
    QSignalSpy finished(&ui, &RenditionUiController::finished);
    QSignalSpy bridgeError(&ui, &RenditionUiController::bridgeError);

    // ---- requestId, envelope and double-tap protection
    const QString id = ui.send("create", {{"periodStart", "2026-10-01"}}, "header:new");
    check(!id.isEmpty() && bridge.submitted.size() == 1, "command submitted");
    const auto sent = QJsonDocument::fromJson(bridge.submitted.first().toUtf8()).toVariant().toMap();
    check(sent.value("requestId") == id && sent.value("operation") == "create"
          && sent.value("arguments").toMap().value("periodStart") == "2026-10-01", "bridge envelope requestId/operation/arguments");
    check(ui.send("create", {}, "header:new").isEmpty() && bridge.submitted.size() == 1, "double tap ignored while pending");
    check(ui.isPending("header:new") && ui.pendingKeys().contains("header:new"), "pending key exposed");
    const QString other = ui.send("refresh", {}, "refresh");
    check(!other.isEmpty() && other != id, "independent request ids");

    // ---- correlation: responses reach only their own request
    bridge.emitJson({{"type", "commandResult"}, {"requestId", other}, {"ok", true}, {"result", QVariantMap{{"pulled", true}}}});
    check(finished.size() == 1 && finished.at(0).at(0) == other && finished.at(0).at(1) == "refresh", "result correlated by requestId");
    check(ui.isPending("header:new") && !ui.isPending("refresh"), "other request still pending");
    bridge.emitJson({{"type", "commandResult"}, {"requestId", id}, {"ok", false}, {"code", "CREATE_LOCAL_FAILED"}, {"message", "x"}});
    check(finished.size() == 2 && finished.at(1).at(3) == false && finished.at(1).at(5) == "CREATE_LOCAL_FAILED", "error correlated");
    check(!ui.isPending("header:new"), "key released after response");
    bridge.emitJson({{"type", "commandResult"}, {"requestId", id}, {"ok", true}});
    check(finished.size() == 2, "late duplicate response ignored");
    bridge.emitJson({{"type", "commandResult"}, {"requestId", ""}, {"ok", false}, {"code", "DETAIL_BUSY"}, {"message", "m"}});
    check(finished.size() == 2 && bridgeError.size() == 1 && bridgeError.at(0).at(0) == "DETAIL_BUSY", "uncorrelated error routed globally");

    // ---- state
    QVariantMap state{{"type", "state"}, {"connectionState", "ONLINE"},
        {"projects", QVariantList{QVariantMap{{"id", "p1"}, {"code", "P-01"}, {"name", "Presa"}}}},
        {"catalogs", QVariantList{QVariantMap{{"catalog_type", "CATEGORY"}, {"code", "FOOD"}, {"name", "Alimentación"}},
                                  QVariantMap{{"catalog_type", "PAYMENT_METHOD"}, {"code", "CASH"}, {"name", "Efectivo"}}}},
        {"renditions", QVariantList{
            QVariantMap{{"localId", "l1"}, {"visibleCode", "RDC-2026-000007"}, {"status", "BORRADOR"}, {"projectIds", QVariantList{"p1"}}, {"primaryProjectId", "p1"}},
            QVariantMap{{"localId", "l2"}, {"status", "OBSERVADO"}, {"projectIds", QVariantList{"p2"}}}}}};
    bridge.emitJson(state);
    check(ui.ready() && ui.state().value("connectionState") == "ONLINE", "state published");
    QSignalSpy stateChanges(&ui, &RenditionUiController::stateChanged);
    bridge.emitJson(state);
    check(stateChanges.isEmpty(), "identical state does not invalidate QML bindings");
    auto changedState = state;
    changedState.insert("busy", true);
    bridge.emitJson(changedState);
    check(stateChanges.size() == 1, "effective state change still reaches QML");
    check(ui.catalog("category").size() == 1 && ui.catalog("PAYMENT").size() == 1, "catalog by type");
    check(ui.projectLabel("p1") == "P-01 · Presa" && ui.projectLabel("zz") == "Proyecto no disponible", "project label");
    check(ui.filterRenditions("rdc-2026", "", "").size() == 1, "search by code");
    check(ui.filterRenditions("", "OBSERVADO", "").size() == 1, "filter by status");
    check(ui.filterRenditions("", "", "p1").size() == 1, "filter by project");
    bridge.emitJson({{"type", "receivedReset"}});
    check(!ui.ready() && ui.state().isEmpty(), "account change clears state");
    stateChanges.clear();
    bridge.emitJson(state);
    check(ui.ready() && stateChanges.size() == 1, "same content publishes again after account reset");

    // ---- domain rules exposed to QML (no duplicated JavaScript)
    check(ui.canEdit({{"localId", "l"}, {"status", "BORRADOR"}}), "local draft editable");
    check(!ui.canEdit({{"remoteId", "r"}, {"status", "OBSERVADO"}, {"can_edit_content", false}}), "server permission revokes edit");
    check(ui.canEdit({{"remoteId", "r"}, {"status", "OBSERVADO"}, {"can_edit_content", true}}), "OBSERVADO with permission editable");
    check(!ui.canEdit({{"remoteId", "r"}, {"status", "EN_REVISION"}, {"can_edit_content", true}}), "EN_REVISION immutable");
    check(ui.formatMoney("1234.5", "PEN") == "S/ 1,234.50" && ui.formatMoney("1.005", "USD") == "US$ 1.01", "money formatting with server rounding");
    check(ui.formatMoney(QVariant(), "PEN") == "—" && ui.formatCents(QVariant(), "PEN") == "—", "absent value never shown as zero");
    check(ui.amountError("0").size() && ui.amountError("abc").size() && ui.amountError("12,50").isEmpty(), "amount validation");
    check(ui.rateError("3.437").isEmpty() && !ui.rateError("0").isEmpty(), "rate validation");
    check(!ui.fundingError({{"enabled", true}, {"pen", "-1"}, {"usd", "0"}}).isEmpty(), "negative fund rejected");
    const auto balance = ui.fundBalance({{"funding", QVariantMap{{"enabled", true}, {"pen", "0"}, {"usd", "100"}}},
                                        {"totalPen", "75"}, {"totalUsd", "20"}, {"exchangeRate", QVariantMap{{"rate", "3.75"}}}});
    check(balance.value("penCents").toLongLong() == 22500 && balance.value("usdCents").toLongLong() == 6000, "shared fund vector");
    const auto mixed = ui.fundBalance({{"funding", QVariantMap{{"enabled", true}, {"pen", "100"}, {"usd", "10"}}},
                                      {"totalPen", "10"}, {"totalUsd", "0"}});
    check(!mixed.value("penCents").isValid() || mixed.value("penCents").isNull(), "mixed balance without rate not determinable");
    const auto totals = ui.totals({QVariantMap{{"amount", "10.10"}, {"currencyCode", "PEN"}, {"reviewStatus", "VALIDADO"}},
                                   QVariantMap{{"amount", "5"}, {"currencyCode", "USD"}, {"reviewStatus", "OBSERVADO"}},
                                   QVariantMap{{"amount", "1"}, {"currencyCode", "PEN"}, {"archived", true}}});
    check(totals.value("penCents").toLongLong() == 1010 && totals.value("usdCents").toLongLong() == 500
          && totals.value("validatedPenCents").toLongLong() == 1010 && totals.value("observed").toInt() == 1
          && totals.value("count").toInt() == 2, "totals exclude archived");
    const QVariantMap draft{{"periodStart", "2026-10-01"}, {"periodEnd", "2026-10-31"}, {"projectIds", QVariantList{"p1"}}};
    QVariantMap expense{{"projectId", "p1"}, {"expenseDate", "2026-10-09"}, {"amount", "12,50"}, {"currencyCode", "PEN"},
                        {"concept", "Almuerzo de campo"}, {"categoryCode", "FOOD"}, {"paymentMethodCode", "CASH"}, {"supportTypeCode", "RECEIPT"}};
    check(ui.expenseError(draft, expense).isEmpty(), "valid expense");
    expense.insert("expenseDate", "2026-11-01");
    check(!ui.expenseError(draft, expense).isEmpty(), "date outside period rejected");
    check(!ui.headerError({{"periodStart", "2026-10-31"}, {"periodEnd", "2026-10-01"}}).isEmpty(), "inverted period rejected");

    // ---- completion (avance) derived only from real presentation requirements
    check(!ui.completion({{"localId", "r"}, {"periodStart", "2026-10-01"}}).value("known").toBool(), "list row without projects not evaluated");
    QVariantMap header{{"periodStart", "2026-10-01"}, {"periodEnd", "2026-10-31"}, {"projectIds", QVariantList{"p1"}},
                       {"primaryProjectId", "p1"}, {"expenses", QVariantList{}}, {"expenseCount", 0}};
    check(ui.completion(header).value("percent").toInt() == 33, "period + projects only = 2/6");
    header.insert("documentParentNodeId", "f1"); header.insert("spaceId", "s1");
    check(ui.completion(header).value("percent").toInt() == 50, "header complete without expenses = 3/6");
    QVariantMap good{{"projectId", "p1"}, {"expenseDate", "2026-10-09"}, {"amount", "10.00"}, {"currencyCode", "PEN"},
                     {"concept", "Almuerzo de campo"}, {"categoryCode", "FOOD"}, {"paymentMethodCode", "CASH"}, {"supportTypeCode", "RECEIPT"}};
    QVariantMap bad = good; bad.insert("concept", "");
    header.insert("expenses", QVariantList{good, bad}); header.insert("expenseCount", 2);
    check(ui.completion(header).value("percent").toInt() == 83, "one of two expenses valid = 5/6");
    header.insert("expenses", QVariantList{good, good});
    check(ui.completion(header).value("percent").toInt() == 100, "all requirements = 100");
    header.insert("expenseCount", 5);
    check(!ui.completion(header).value("known").toBool(), "partially loaded expenses not evaluated");
    header.insert("expenseCount", 2); header.insert("status", "APROBADO"); header.insert("syncState", "ERROR");
    check(ui.completion(header).value("percent").toInt() == 100, "status and sync do not change completion");
    check(ui.errorText("QUOTE_ORIGIN_NOT_CONFIGURED", "raw").contains("manualmente"), "quote origin message");
    check(ui.errorText("NETWORK_ERROR", "").contains("Sin conexión"), "offline message");
    check(ui.errorText("RENDITION_WORKING_ROWS_PENDING", "RENDITION_WORKING_ROWS_PENDING").contains("sin terminar"),
          "working rows pending message");
    check(ui.errorText("PGRST202", "raw").contains("raw"), "missing RPC stays generic outside Working");
    // P0 conectividad: la pérdida de conexión no produce avisos (la comunica el aura).
    for (const char *code : {"NETWORK_AMBIGUOUS", "TIMEOUT", "OFFLINE", "SERVER_UNREACHABLE", "HTTP_503",
                             "ATTACHMENT_UPLOAD_NEEDS_RECONCILIATION", "SYNC_BUSY", "PULL_BUSY", "AUTH_REQUIRED"})
        check(ui.silentError(code), (std::string("silent connectivity code ") + code).c_str());
    for (const char *code : {"RENDITION_WORKING_CONFLICT", "RENDITION_VERSION_CONFLICT",
                             "RENDITION_NOT_FOUND_OR_FORBIDDEN", "PERMISSION_DENIED", "HTTP_409"})
        check(!ui.silentError(code), (std::string("actionable error stays visible ") + code).c_str());
    check(ui.effectiveSyncState({{"syncState", "ERROR"}, {"syncError", "TRANSPORT_RETRY"}}) == "PENDING_UPDATE",
          "waiting-for-server ERROR shown as pending");
    check(ui.effectiveSyncState({{"syncState", "ERROR"}, {"syncError", "Rechazado por permisos"}}) == "ERROR",
          "real server rejection stays ERROR");
    check(ui.effectiveSyncState({{"syncState", "CONFLICT"}, {"syncError", "TRANSPORT_RETRY"}}) == "CONFLICT",
          "conflict never downgraded");
    check(ui.visibleSyncError("TRANSPORT_RETRY").isEmpty() && ui.visibleSyncError("Sin permiso") == "Sin permiso",
          "technical marker hidden, real message kept");
    check(!ui.aiEnabled(), "Renditions AI disabled");

    QTemporaryDir dir;
    QFile pdf(dir.filePath("comprobante.pdf"));
    check(pdf.open(QIODevice::WriteOnly) && pdf.write("%PDF-1.4\n%%EOF\n") > 0, "pdf fixture"); pdf.close();
    const auto described = ui.describeLocalFile(QUrl::fromLocalFile(pdf.fileName()));
    check(described.value("mimeType") == "application/pdf" && described.value("sizeBytes").toLongLong() == pdf.size()
          && described.value("fileName") == "comprobante.pdf" && described.value("error").toString().isEmpty(), "local file described");
    QFile text(dir.filePath("nota.txt"));
    check(text.open(QIODevice::WriteOnly) && text.write("hola") > 0, "txt fixture"); text.close();
    check(!ui.describeLocalFile(QUrl::fromLocalFile(text.fileName())).value("error").toString().isEmpty(), "unsupported format rejected");

    // ---- reviewer contracts (same RPCs and arguments as the Web)
    QString rpc; QVariantMap params;
    check(!RenditionAdminRpc::requiresReviewReason("reviewTransition", {{"nextState", "BORRADOR"}}), "return to draft accepts the server's empty reason contract");
    check(RenditionAdminRpc::requiresReviewReason("reviewTransition", {{"nextState", "OBSERVADO"}}), "observation still requires a reason");
    check(RenditionAdminRpc::requiresReviewReason("reviewRequest", {{"requestedState", "BORRADOR"}}), "owner request still requires a reason");
    check(RenditionAdminRpc::requiresReviewReason("reviewDecide", {}), "review decision still requires a reason");
    check(RenditionAdminRpc::call("reviewContext", {{"renditionId", "r"}}, &rpc, &params)
          && rpc == "get_rendition_review_context_v03" && params.value("p_rendition_id") == "r" && params.size() == 1, "review context contract");
    check(RenditionAdminRpc::call("reviewTransition", {{"renditionId", "r"}, {"expectedRowVersion", 7}, {"nextState", "OBSERVADO"}, {"reason", " Falta boleta "}}, &rpc, &params)
          && rpc == "transition_rendition_review_v03" && params.value("p_expected_row_version").toLongLong() == 7
          && params.value("p_next_state") == "OBSERVADO" && params.value("p_reason") == "Falta boleta" && params.size() == 4, "transition contract");
    check(RenditionAdminRpc::call("reviewRequest", {{"renditionId", "r"}, {"expectedRowVersion", 3}, {"requestId", "q"}, {"reason", "x"}}, &rpc, &params)
          && rpc == "request_rendition_state_v04" && params.value("p_requested_state") == "OBSERVADO" && params.value("p_request_id") == "q" && params.size() == 5, "edit request contract");
    check(RenditionAdminRpc::call("reviewDecide", {{"renditionId", "r"}, {"editRequestId", "e"}, {"expectedRowVersion", 3}, {"expectedRequestRowVersion", 2}, {"approve", true}, {"reason", "ok"}}, &rpc, &params)
          && rpc == "decide_rendition_edit_v03" && params.value("p_approve").toBool() && params.value("p_expected_request_row_version").toLongLong() == 2 && params.size() == 6, "decision contract");
    check(RenditionAdminRpc::call("receive", {{"renditionId", "r"}, {"requestId", "q"}}, &rpc, &params)
          && rpc == "receive_rendition_v01" && params.value("p_request_id") == "q" && params.size() == 2, "reception contract");
    check(RenditionAdminRpc::call("receivedList", {}, &rpc, &params) && rpc == "list_received_renditions_v02"
          && params.value("p_limit").toInt() == 200 && params.value("p_after_id").isNull(), "received list contract preserved");
    check(RenditionAdminRpc::call("receivedAddNote", {{"renditionId", "r"}, {"versionId", "v"}, {"noteRequestId", "n"}, {"body", "b"}}, &rpc, &params)
          && rpc == "create_rendition_admin_note_v01" && params.value("p_rendition_version_id") == "v", "admin note contract preserved");
    check(!RenditionAdminRpc::call("deleteEverything", {}, &rpc, &params) && rpc.isEmpty() && params.isEmpty(), "unknown command rejected");

    std::cout << "PASS ui controller and reviewer contracts: " << checks << " checks\n";
    return 0;
}

#include "ui_controller.moc"
