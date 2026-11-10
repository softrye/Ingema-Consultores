// P0 conectividad de Rendiciones: fuente única de estado (RenditionConnectivity) y
// su efecto en el almacén local real (RenditionLocalStore). Sin red ni Supabase.
// Pruebas A (desconexión), B (reconexión), C (conflicto real), D (timeout/5xx)
// y F (interrupción y reanudación sin duplicados) a nivel de dominio.
#include "src/cpp/renditionconnectivity.h"
#include "src/cpp/renditionlocalstore.h"

#include <QGuiApplication>
#include <QStandardPaths>
#include <QUuid>
#include <iostream>

namespace C = RenditionConnectivity;
static int checks = 0;
static void check(bool value, const char *label)
{
    ++checks;
    if (!value) { std::cerr << "FAIL " << label << '\n'; std::exit(1); }
}

int main(int argc, char **argv)
{
    QGuiApplication app(argc, argv);
    QStandardPaths::setTestModeEnabled(true);
    QCoreApplication::setApplicationName("RenditionConnectivityChecks");

    // ---------------------------------------------------------- Máquina de estados
    {
        C::State s;
        check(s.connectionState() == "UNKNOWN" && !s.offline(), "starts unknown (no false red)");
        // A: con red pero sin respuesta (timeout/5xx) => servidor inaccesible (rojo).
        check(s.onTransport(C::classify("NETWORK_AMBIGUOUS")), "A transport failure changes state");
        check(s.offline() && s.connectionState() == "OFFLINE" && s.connectivity() == "SERVER_UNREACHABLE",
              "A server unreachable published as OFFLINE");
        // Sin red (evento del sistema) => desconexión inmediata, sin reintentos activos.
        check(s.onNetwork(false) && s.connectivity() == "NO_NETWORK", "A no network");
        check(s.retryDelayMs() < 0, "A no polling without network (waits for event)");
        // Red recuperada: NO se declara online sin evidencia del servidor.
        s.onNetwork(true);
        check(s.offline() && s.connectivity() == "SERVER_UNREACHABLE", "B network back is not ONLINE yet");
        check(s.retryDelayMs() == 15000, "B controlled first retry");
        // B: primera respuesta real => online.
        check(s.onTransport(C::Outcome::Reachable) && s.online() && s.connectionState() == "ONLINE", "B real response => ONLINE");
        check(s.retryDelayMs() < 0 && s.failures() == 0, "B retries stop once online");
        // C: un conflicto CAS es una RESPUESTA del servidor: conexión efectiva.
        check(C::classify("RENDITION_WORKING_CONFLICT") == C::Outcome::Reachable
              && C::classify("RENDITION_VERSION_CONFLICT") == C::Outcome::Reachable, "C CAS conflict proves reachability");
        check(!C::isTransportFailure("RENDITION_WORKING_CONFLICT"), "C conflict is never a transport failure");
        // D: timeout, 5xx y sin respuesta HTTP son transporte (nunca conflicto).
        for (const char *code : {"NETWORK_AMBIGUOUS", "TIMEOUT", "HTTP_500", "HTTP_503", "HTTP_0",
                                 "ATTACHMENT_UPLOAD_NEEDS_RECONCILIATION"})
            check(C::isTransportFailure(code) && C::classify(code) == C::Outcome::Unreachable, code);
        check(C::classifyHttp(0, true) == C::Outcome::Unreachable && C::classifyHttp(503, false) == C::Outcome::Unreachable,
              "D no HTTP response / 5xx unreachable");
        check(C::classifyHttp(409, false) == C::Outcome::Reachable && C::classifyHttp(400, false) == C::Outcome::Reachable
              && C::classifyHttp(200, false) == C::Outcome::Reachable, "D 2xx/4xx prove the server answered");
        check(C::classifyHttp(401, false) == C::Outcome::Auth, "401 is authentication, not offline");
        // Wi-Fi apagado con datos móviles: el sistema sigue informando red y las
        // respuestas llegan => nunca rojo sólo por el interruptor Wi-Fi.
        C::State mobile;
        mobile.onTransport(C::Outcome::Reachable);
        mobile.onNetwork(true);
        check(mobile.online(), "wifi off but mobile data reachable stays ONLINE");
        check(!mobile.onTransport(C::Outcome::Unreachable) && mobile.online(),
              "one RPC failure is not proof the server is down");
        check(mobile.onTransport(C::Outcome::Unreachable) && mobile.offline(),
              "two consecutive RPC failures confirm connectivity loss");
        check(mobile.onTransport(C::Outcome::Reachable) && mobile.online(),
              "server response restores connectivity");
        // Espera creciente por INTENTO (un pull de ~8 RPC cuenta una vez).
        C::State backoff;
        backoff.onNetwork(true);
        for (int i = 0; i < 8; ++i) backoff.onTransport(C::Outcome::Unreachable);
        check(backoff.failures() == 1 && backoff.retryDelayMs() == 15000, "one pull counts as one failed attempt");
        backoff.beginAttempt();
        for (int i = 0; i < 8; ++i) backoff.onTransport(C::Outcome::Unreachable);
        check(backoff.failures() == 2 && backoff.retryDelayMs() == 30000, "second attempt doubles wait");
        for (int i = 0; i < 10; ++i) { backoff.beginAttempt(); backoff.onTransport(C::Outcome::Unreachable); }
        check(backoff.retryDelayMs() == 300000, "wait capped at 5 minutes");
        // Errores silenciosos (aura) vs. accionables (visibles).
        check(C::isSilent("OFFLINE") && C::isSilent("SYNC_BUSY") && C::isSilent("AUTH_REQUIRED")
              && !C::isSilent("RENDITION_NOT_FOUND_OR_FORBIDDEN"), "silent vs actionable codes");
    }

    // ------------------------------------------------- Almacén real (offline-first)
    const auto scope = QUuid::createUuid().toString();
    const QString rid = "22222222-2222-4222-8222-222222222222";
    QString local, child, request;
    {
        RenditionLocalStore store(scope);
        local = store.createDraft("2026-10-01", "2026-10-31", {"p1"}, "p1", "folder", "space", true);
        check(!local.isEmpty(), "draft persisted");
        check(store.markRenditionSynced(local, {{"rendition_id", rid}, {"visible_code", "RDC-2026-000024"},
                                                {"row_version", 3}, {"can_edit_content", true}}), "remote identity");
        // Detalle nunca descargado (p. ej. abierto sin red): NO es conflicto.
        auto status = store.syncStatus(local);
        check(status.value("syncState") == "NEEDS_RECONCILIATION" && status.value("reconcileReason") == "DETAIL_NOT_LOADED",
              "detail not loaded is reconciliation by DETAIL_NOT_LOADED");
        check(status.value("syncError").toString().isEmpty(), "no error text for detail not loaded");

        // A/D: gasto creado sin conexión y fallo de transporte en su envío.
        const QVariantMap expense{{"projectId", "p1"}, {"expenseDate", "2026-10-08"}, {"categoryCode", "FOOD"},
                                  {"currencyCode", "PEN"}, {"amount", "12.50"}, {"concept", "Movilidad de campo"},
                                  {"beneficiary", "Taxi"}, {"paymentMethodCode", "CASH"}, {"supportTypeCode", "RECEIPT"}};
        child = store.addLocalExpense(local, expense, true);
        check(!child.isEmpty(), "offline expense persisted locally");
        request = store.expensesFor(local).last().toMap().value("requestId").toString();
        check(store.markExpenseSyncing(local, child), "send starts durably");
        // Exactamente lo que hace RenditionSyncController::failCurrent ante NETWORK/TIMEOUT/5xx.
        check(store.markExpenseState(local, child, "ERROR", C::transportMarker()), "transport failure recorded");
        status = store.syncStatus(local);
        check(status.value("syncState") == "PENDING_UPDATE", "D waiting op published as pending, not ERROR");
        check(status.value("syncError").toString().isEmpty(), "D no error text published for transport");
        check(status.value("pendingCount").toInt() >= 1, "D op still counted pending");
        const auto ops = store.pendingOperations();
        check(ops.size() == 1 && ops.first().toMap().value("requestId") == request, "D retry keeps same request_id");
    }
    // F: el proceso muere con la operación en vuelo; al reabrir se reanuda sin duplicar.
    {
        RenditionLocalStore store(scope);
        check(store.markExpenseSyncing(local, child), "F operation in flight before process death");
    }
    {
        RenditionLocalStore restarted(scope);
        const auto expense = restarted.expensesFor(local).last().toMap();
        check(expense.value("syncError") == C::transportMarker(), "F interrupted op silently waits for server");
        check(restarted.syncStatus(local).value("syncState") != "ERROR", "F interruption is not shown as error");
        const auto ops = restarted.pendingOperations();
        check(ops.size() == 1 && ops.first().toMap().value("requestId") == request, "F resumes same intention (no duplicate)");
        check(restarted.markExpenseSynced(local, child, {{"expense_id", "55555555-5555-4555-8555-555555555555"},
                                                         {"expense_row_version", 1}, {"rendition_row_version", 4}}),
              "B reconnection confirms the original create");
        check(restarted.expensesFor(local).size() == 1, "B no duplicate expense after resume");
        check(restarted.pendingOperations().isEmpty(), "B queue drained");

        // C: conflicto CAS REAL (rechazo del servidor) sí es visible y bloquea.
        auto values = restarted.expensesFor(local).last().toMap();
        values.insert("amount", "13.00");
        check(restarted.saveLocalExpense(local, child, values, true), "local edit queued");
        check(restarted.markExpenseState(local, child, "CONFLICT", "Este gasto cambió en Web mientras había cambios locales pendientes."),
              "CAS conflict recorded");
        const auto status = restarted.syncStatus(local);
        check(status.value("syncState") == "CONFLICT", "C conflict published");
        check(status.value("syncError").toString().contains("cambió en Web"), "C conflict keeps actionable message");
        check(restarted.expensesFor(local).last().toMap().value("amount") == "13.00", "C local change preserved");
        check(restarted.pendingOperations().isEmpty(), "C conflict never retried automatically (no silent overwrite)");
    }
    std::cout << "PASS renditions connectivity: " << checks << " checks\n";
    return 0;
}
