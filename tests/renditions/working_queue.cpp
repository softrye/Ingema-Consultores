// Cola REAL (RenditionSyncController + RenditionLocalStore) con un repositorio de
// prueba (fake_repository.cpp, misma clase/señales). El "servidor" responde
// emitiendo las señales reales del repositorio. Sin red ni Supabase.
//
// Cubre: Working (guardar, reintento idéntico tras pérdida de respuesta, sustentos
// reservar/confirmar/subir/confirmar, promoción atómica, conflicto CAS real y su
// resolución, descarte, recuperación entre dispositivos, contrato ausente,
// reinicio del proceso) y P0 (fallo de transporte ≠ conflicto, sin consultas extra).
#include "src/cpp/renditionconnectivity.h"
#include "src/cpp/renditionlocalstore.h"
#include "src/cpp/renditionrepository.h"
#include "src/cpp/renditionsynccontroller.h"
#include "src/cpp/renditionworkingcontract.h"
#include "fake_repository.h"

#include <QFile>
#include <QJsonDocument>
#include <QGuiApplication>
#include <QSignalSpy>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QUuid>
#include <cstdlib>
#include <iostream>

namespace W = RenditionWorkingContract;
static int checks = 0;
static void check(bool value, const char *label)
{
    ++checks;
    if (qEnvironmentVariableIsSet("INGE_TEST_TRACE")) std::cerr << "  ok? " << label << std::endl;
    if (!value) { std::cerr << "FAIL " << label << std::endl; std::_Exit(1); }   // sin destructores Qt
}
static void settle() { for (int i = 0; i < 5; ++i) QCoreApplication::processEvents(); }

static QVariantMap serverRow(const QVariantMap &saveArgs, qint64 version, const QString &state = QStringLiteral("ACTIVE"),
                             const QVariantList &files = {})
{
    return {{"id", saveArgs.value("p_working_id")}, {"rendition_id", saveArgs.value("p_rendition_id")},
            {"payload", saveArgs.value("p_payload")}, {"row_version", version},
            {"expense_id", saveArgs.value("p_expense_id")}, {"expense_row_version", saveArgs.value("p_expense_row_version")},
            {"kind", saveArgs.value("p_expense_id").isNull() ? "NEW" : "EDIT"}, {"state", state},
            {"updated_at", "2026-10-16T12:00:00Z"}, {"files", files}};
}

int main(int argc, char **argv)
{
    qputenv("QT_QPA_PLATFORM", "offscreen");
    QGuiApplication app(argc, argv);
    QStandardPaths::setTestModeEnabled(true);
    QCoreApplication::setApplicationName("RenditionWorkingQueueChecks");
    QTemporaryDir files;
    check(files.isValid(), "fixture dir");
    const QString receipt = files.filePath("boleta.jpg");
    { QFile f(receipt); check(f.open(QIODevice::WriteOnly) && f.write(QByteArray(2048, 'r')) == 2048, "receipt fixture"); }

    const auto scope = QUuid::createUuid().toString();
    const QString rid = "22222222-2222-4222-8222-222222222222";
    auto *store = new RenditionLocalStore(scope);
    RenditionRepository repo;
    const QString local = store->createDraft("2026-10-01", "2026-10-31", {"p1"}, "p1", "folder", "space", true);
    check(store->markRenditionSynced(local, {{"rendition_id", rid}, {"visible_code", "RDC-2026-000031"},
                                             {"row_version", 4}, {"can_edit_content", true}}), "rendition confirmed");
    auto *syncPtr = new RenditionSyncController(store, &repo);
    RenditionSyncController &sync = *syncPtr;
    QSignalSpy stopped(&sync, &RenditionSyncController::syncStopped);
    QSignalSpy finished(&sync, &RenditionSyncController::syncFinished);
    QSignalSpy contractMissing(&sync, &RenditionSyncController::workingContractMissing);
    settle();                                    // sincronización inicial (cola vacía)

    const QVariantMap form{{"projectId", "p1"}, {"expenseDate", "2026-10-08"}, {"categoryCode", "FOOD"},
                           {"currencyCode", "PEN"}, {"amount", "12.50"}, {"concept", "Movilidad de campo"},
                           {"beneficiary", "Taxi Lima"}, {"paymentMethodCode", "CASH"}, {"supportTypeCode", "RECEIPT"}};

    // ================= W1: borrador con sustento; respuesta perdida; reintento idéntico.
    const QString wid = store->saveWorkingDraft(local, {}, form, {QVariantMap{{"localUri", receipt}, {"fileName", "boleta.jpg"},
                                                                            {"mimeType", "image/jpeg"}, {"sizeBytes", 2048}}});
    check(W::canonicalUuid(wid), "W1 working row created locally (offline-first)");
    check(store->activeWorkingCount(local) == 1, "W1 one active draft");
    check(!store->presentationBlocker(local).isEmpty() && store->presentationBlocker(local).contains("borrador"),
          "W1 presentation blocked by unfinished draft (server guard parity)");
    FakeServer::calls.clear();
    sync.synchronize(); settle();
    const QVariantMap first = FakeServer::last("saveWorkingRow");
    check(!first.isEmpty() && W::validateSave(first).isEmpty(), "W1 save sent with contract-valid arguments");
    check(first.value("p_expected_version").toLongLong() == 0 && first.value("p_rendition_id") == rid, "W1 create CAS expected 0");
    const QString sourceId = first.value("p_payload").toMap().value("sources").toList().first().toMap().value("id").toString();
    const QString fileId = first.value("p_payload").toMap().value("sources").toList().first().toMap().value("uploadRequestId").toString();
    check(!first.value("p_payload").toMap().value("sources").toList().first().toMap().contains("localUri"), "W1 no local path sent");
    // Respuesta perdida (timeout): silencioso, sin conflicto, intento en vuelo conservado.
    emit repo.operationFailed("working_save", "NETWORK_AMBIGUOUS", "timeout");
    settle();
    check(!sync.busy() && stopped.count() >= 1 && stopped.last().at(1).toString() == "NETWORK_AMBIGUOUS", "W1 transport stops queue with real code");
    check(stopped.last().at(2).toString().isEmpty(), "W1 no user-facing message for transport");
    check(store->workingRowsFor(local).first().toMap().value("syncState") != "CONFLICT", "W1 transport is not a conflict");
    check(store->syncStatus(local).value("syncState") != "CONFLICT" && store->syncStatus(local).value("syncState") != "ERROR",
          "W1 rendition not error/conflict after transport failure");
    // El usuario sigue editando sin conexión.
    QVariantMap edited = form; edited.insert("amount", "13.00");
    check(store->saveWorkingDraft(local, wid, edited, {QVariantMap{{"id", sourceId}}}) == wid, "W1 offline edit kept locally");
    FakeServer::calls.clear();
    sync.synchronize(); settle();
    const QVariantMap replay = FakeServer::last("saveWorkingRow");
    check(replay == first, "W1 reconnection REPLAYS the lost attempt byte-for-byte (same request_id, CAS, payload)");
    // El servidor sí lo había aplicado: devuelve el recibo (versión 1).
    emit repo.workingSaved(serverRow(first, 1));
    settle();
    const QVariantMap reserve = FakeServer::last("reserveWorkingFile");
    check(reserve.value("p_working_id") == wid && reserve.value("p_file_id") == fileId && reserve.value("p_size_bytes").toLongLong() == 2048,
          "W1 source reserved with exact payload metadata");
    const QString path = "renditions/" + rid + "/expenses/" + wid + "/attachments/" + fileId;
    emit repo.workingFileReserved({{"id", fileId}, {"status", "RESERVED"}, {"storage_path", path}, {"mime_type", "image/jpeg"}});
    settle();
    check(FakeServer::last("confirmWorkingFile").value("p_file_id") == fileId, "W1 confirm attempted before upload (lost-response safe)");
    emit repo.operationFailed("working_confirm", "RENDITION_ATTACHMENT_OBJECT_MISSING", "missing");
    settle();
    const QVariantMap upload = FakeServer::last("upload");
    check(upload.value("bucket") == "project-files" && upload.value("objectPath") == path && upload.value("id") == fileId
          && upload.value("mimeType") == "image/jpeg" && QFile::exists(upload.value("localFilePath").toString()),
          "W1 bytes uploaded from persistent mirror to server-assigned path");
    emit repo.attachmentUploaded(fileId);
    settle();
    check(FakeServer::count("confirmWorkingFile") == 2, "W1 confirm after upload");
    emit repo.workingFileConfirmed({{"id", fileId}, {"status", "READY"}, {"storage_path", path}});
    settle();
    // Tras el recibo, la intención nueva (13.00) se envía sobre la versión confirmada.
    const QVariantMap second = FakeServer::last("saveWorkingRow");
    check(second.value("p_expected_version").toLongLong() == 1 && second.value("p_request_id") != first.value("p_request_id")
          && second.value("p_payload").toMap().value("form").toMap().value("amount") == "13.00",
          "W1 newer intent sent on confirmed version with a NEW request_id (no false CAS conflict)");
    emit repo.workingSaved(serverRow(second, 2, "ACTIVE", {QVariantMap{{"id", fileId}, {"source_id", sourceId}, {"status", "READY"}}}));
    settle();
    check(!sync.busy() && finished.count() >= 1, "W1 queue drained");
    check(FakeServer::count("upload") == 1 && FakeServer::count("reserveWorkingFile") == 1, "W1 no duplicate upload/reservation");
    auto view = store->workingRowsFor(local).first().toMap();
    check(view.value("syncState") == "SYNCED" && view.value("cloudVersion").toLongLong() == 2 && view.value("missingSources").toInt() == 0,
          "W1 draft synced in cloud with its receipt");

    // ================= W2: promoción atómica explícita.
    check(store->requestWorkingPromotion(local, wid), "W2 promotion requested (validated like a normal expense)");
    FakeServer::calls.clear();
    sync.synchronize(); settle();
    const QVariantMap promote = FakeServer::last("promoteWorkingRow");
    check(promote.value("p_working_id") == wid && promote.value("p_expected_version").toLongLong() == 2
          && promote.value("p_expected_rendition_version").toLongLong() == 4, "W2 promote with working + rendition CAS");
    emit repo.operationFailed("working_promote", "TIMEOUT", "lost");     // respuesta perdida
    settle();
    FakeServer::calls.clear();
    sync.synchronize(); settle();
    check(FakeServer::last("promoteWorkingRow") == promote, "W2 promote replay identical (server returns same result, no double expense)");
    const QString expenseId = "55555555-5555-4555-8555-555555555555";
    emit repo.workingPromoted({{"expense_id", expenseId}, {"expense_row_version", 1}, {"rendition_row_version", 5},
                               {"line_number", 1}, {"result_code", "CREATED"}, {"updated_at", "2026-10-16T12:01:00Z"}});
    settle();
    check(store->activeWorkingCount(local) == 0 && store->workingRowsFor(local).isEmpty(), "W2 promoted draft leaves the active list");
    check(store->rendition(local).value("rowVersion").toLongLong() == 5, "W2 own rendition version adopted");
    check(store->pendingCount() == 0, "W2 nothing pending after promotion");

    // ================= W3: conflicto CAS real por fila; la cola sigue; resolución explícita.
    const QString w3 = store->saveWorkingDraft(local, {}, form, {});
    FakeServer::calls.clear();
    sync.synchronize(); settle();
    const QVariantMap w3Save = FakeServer::last("saveWorkingRow");
    emit repo.workingSaved(serverRow(w3Save, 1));
    settle();
    QVariantMap mine = form; mine.insert("concept", "Mi versión");
    store->saveWorkingDraft(local, w3, mine, {});
    FakeServer::calls.clear();
    sync.synchronize(); settle();
    emit repo.operationFailed("working_save", "RENDITION_WORKING_CONFLICT", "RENDITION_WORKING_CONFLICT");
    settle();
    view = store->workingRowsFor(local).first().toMap();
    check(view.value("syncState") == "CONFLICT" && view.value("form").toMap().value("concept") == "Mi versión",
          "W3 real conflict kept per row with local intent intact");
    check(store->syncStatus(local).value("workingConflictCount").toInt() == 1
          && store->syncStatus(local).value("syncState") != "CONFLICT", "W3 row conflict does not lock the whole rendition");
    check(!sync.busy(), "W3 queue not stuck by a row conflict");
    FakeServer::calls.clear();
    sync.synchronize(); settle();
    check(FakeServer::count("saveWorkingRow") == 0, "W3 conflict never retried automatically (no silent overwrite)");
    QVariantMap theirs = w3Save; QVariantMap theirPayload = theirs.value("p_payload").toMap();
    QVariantMap theirForm = theirPayload.value("form").toMap(); theirForm.insert("concept", "Versión Web");
    theirPayload.insert("form", theirForm); theirs.insert("p_payload", theirPayload);
    check(store->resolveWorkingConflict(local, w3, true, serverRow(theirs, 3)), "W3 keep mine over server version");
    FakeServer::calls.clear();
    sync.synchronize(); settle();
    const QVariantMap rebased = FakeServer::last("saveWorkingRow");
    check(rebased.value("p_expected_version").toLongLong() == 3
          && rebased.value("p_payload").toMap().value("form").toMap().value("concept") == "Mi versión", "W3 rebased on server version 3");
    emit repo.workingSaved(serverRow(rebased, 4));
    settle();

    // ================= W4: descarte (archivo) autorizado; local-only se descarta sin red.
    const QString localOnly = store->saveWorkingDraft(local, {}, form, {});
    check(store->requestWorkingArchive(local, localOnly) && store->workingRow(localOnly).isEmpty(), "W4 never-sent draft discarded locally");
    check(store->requestWorkingArchive(local, w3), "W4 archive requested for cloud draft");
    FakeServer::calls.clear();
    sync.synchronize(); settle();
    const QVariantMap archive = FakeServer::last("archiveWorkingRow");
    check(archive.value("p_working_id") == w3 && archive.value("p_expected_version").toLongLong() == 4, "W4 archive with CAS");
    emit repo.workingArchived({{"id", w3}, {"state", "ARCHIVED"}, {"row_version", 5}});
    settle();
    check(store->activeWorkingCount(local) == 0 && store->presentationBlocker(local).indexOf("borrador") < 0, "W4 archived draft no longer blocks");

    // ================= W5: recuperación en otro dispositivo (metadatos + bytes del servidor).
    const QString remoteWid = "77777777-7777-4777-8777-777777777777";
    const QVariantMap remotePayload = W::payload(form, {}, {
        QVariantMap{{"id", "src-ready"}, {"name", "factura.pdf"}, {"size", 10}, {"lastModified", 1}, {"type", "application/pdf"},
                    {"uploadRequestId", "88888888-8888-4888-8888-888888888888"}},
        QVariantMap{{"id", "src-lost"}, {"name", "foto.jpg"}, {"size", 20}, {"lastModified", 2}, {"type", "image/jpeg"},
                    {"uploadRequestId", "99999999-9999-4999-8999-999999999999"}}}, W::newUuid());
    store->mergeRemoteWorkingRows(local, {QVariantMap{{"id", remoteWid}, {"rendition_id", rid}, {"payload", remotePayload},
        {"row_version", 2}, {"expense_id", QVariant()}, {"expense_row_version", QVariant()}, {"kind", "NEW"}, {"state", "ACTIVE"},
        {"updated_at", "2026-10-16T10:00:00Z"},
        {"files", QVariantList{QVariantMap{{"id", "88888888-8888-4888-8888-888888888888"}, {"source_id", "src-ready"}, {"status", "READY"}}}}}});
    view = store->workingRowsFor(local).first().toMap();
    check(view.value("id") == remoteWid && view.value("cloudVersion").toLongLong() == 2, "W5 draft from another device recovered");
    check(view.value("missingSources").toInt() == 1, "W5 bytes never uploaded are reported missing (not recreated)");
    check(!store->requestWorkingPromotion(local, remoteWid) && store->lastError().contains("Faltan 1"), "W5 promotion blocked until re-attached");

    // ================= W6: entorno sin contrato (PGRST202): sin escrituras, borrador local.
    QVariantMap remoteEdit = form; remoteEdit.insert("concept", "Editado aquí");
    store->saveWorkingDraft(local, remoteWid, remoteEdit, {QVariantMap{{"id", "src-ready"}}, QVariantMap{{"id", "src-lost"}}});
    FakeServer::calls.clear();
    sync.synchronize(); settle();
    emit repo.operationFailed("working_save", "PGRST202", "Could not find the function");
    settle();
    check(contractMissing.count() == 1, "W6 contract missing reported to bridge");
    check(store->workingRowsFor(local).first().toMap().value("syncState") == "LOCAL_ONLY", "W6 draft kept local only");
    FakeServer::calls.clear();
    sync.synchronize(); settle();
    check(FakeServer::count("saveWorkingRow") == 0, "W6 no further writes against missing contract");

    // ================= W7: reinicio con un guardado en vuelo -> reanuda el MISMO intento.
    const QString w7 = store->saveWorkingDraft(local, {}, form, {});
    FakeServer::calls.clear();
    sync.synchronize(); settle();
    const QVariantMap inflight = FakeServer::last("saveWorkingRow");
    check(!inflight.isEmpty(), "W7 save in flight");
    delete syncPtr;                                            // el proceso muere sin respuesta
    delete store;
    RenditionLocalStore restarted(scope);
    bool resumed = false;
    for (const auto &op : restarted.pendingOperations())
        if (op.toMap().value("kind") == "working_save" && op.toMap().value("workingId") == w7)
            resumed = QJsonDocument::fromVariant(op.toMap().value("saveArguments")).toJson()
                == QJsonDocument::fromVariant(inflight).toJson();          // lo que viaja: JSON idéntico
    check(resumed, "W7 restart resumes identical attempt (no duplicate, no false conflict)");
    check(restarted.workingRowsFor(local).size() == 2, "W7 drafts survive restart");

    // ================= P0 en la cola real: transporte ≠ conflicto; sin consultas extra.
    RenditionLocalStore p0(QUuid::createUuid().toString());
    const QString pl = p0.createDraft("2026-10-01", "2026-10-31", {"p1"}, "p1", "folder", "space", true);
    p0.markRenditionSynced(pl, {{"rendition_id", rid}, {"row_version", 1}, {"can_edit_content", true}});
    RenditionRepository repo2;
    RenditionSyncController sync2(&p0, &repo2);
    QSignalSpy stopped2(&sync2, &RenditionSyncController::syncStopped);
    settle();
    const QString child = p0.addLocalExpense(pl, form, true);
    FakeServer::calls.clear();
    sync2.synchronize(); settle();
    check(FakeServer::count("addExpense") == 1, "P0 expense create sent");
    const QString request = FakeServer::last("addExpense").value("requestId").toString();
    emit repo2.operationFailed("expense_create", "NETWORK_AMBIGUOUS", "Host unreachable");   // nombre real de la operación
    settle();
    check(!stopped2.isEmpty() && stopped2.last().at(1).toString() == "NETWORK_AMBIGUOUS" && stopped2.last().at(2).toString().isEmpty(), "P0 transport code, no message");
    check(p0.syncStatus(pl).value("syncState") == "PENDING_UPDATE" && p0.syncStatus(pl).value("syncError").toString().isEmpty(),
          "P0 waiting expense shown as pending, never conflict/error");
    check(FakeServer::count("listRenditions") == 0 && FakeServer::count("listExpenses") == 0, "P0 no refetch storm while offline");
    FakeServer::calls.clear();
    sync2.synchronize(); settle();
    check(FakeServer::last("addExpense").value("requestId") == request, "P0 reconnection retries same request_id (idempotent)");
    check(p0.expensesFor(pl).size() == 1 && !child.isEmpty(), "P0 no duplicate local expense");

    // Sesión expirada (401): la operación espera intacta; NO es un rechazo en la ficha
    // (causa del recuadro "La sesión expiró" sobre la tarjeta).
    emit repo2.operationFailed("expense_create", "AUTH_REQUIRED", "La sesión expiró. Vuelve a iniciar sesión para sincronizar.");
    settle();
    check(!stopped2.isEmpty() && stopped2.last().at(1).toString() == "AUTH_REQUIRED" && stopped2.last().at(2).toString().isEmpty(),
          "AUTH1 session expiry stops the queue without a user-facing message");
    check(p0.syncStatus(pl).value("syncState") == "PENDING_UPDATE" && p0.syncStatus(pl).value("syncError").toString().isEmpty()
          && !p0.expensesFor(pl).first().toMap().value("syncError").toString().contains("sesión"),
          "AUTH2 no session-expired text stored on the rendition/expense");
    check(FakeServer::count("listRenditions") == 0, "AUTH3 no refetch with an expired session");
    FakeServer::calls.clear();
    sync2.synchronize(); settle();
    check(FakeServer::last("addExpense").value("requestId") == request, "AUTH4 renewed session replays the same request_id");

    std::cout << "PASS renditions working queue: " << checks << " checks" << std::endl;
    return 0;
}
