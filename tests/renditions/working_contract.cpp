// Contrato Working Document (rendition_cloud_working_rows_v01): las reglas locales deben
// coincidir con las del SQL para que Android no envíe nada que el servidor rechazaría
// y nunca acepte una respuesta fuera de contrato. Sin red ni Supabase.
#include "src/cpp/renditionworkingcontract.h"
#include <cassert>
#include <iostream>

namespace W = RenditionWorkingContract;

int main()
{
    const QString rid = "22222222-2222-4222-8222-222222222222";
    const QString wid = "33333333-3333-4333-8333-333333333333";
    const QString fid = "44444444-4444-4444-8444-444444444444";
    const QString expenseRequest = "55555555-5555-4555-8555-555555555555";
    const QVariantMap form{{"projectId", "66666666-6666-4666-8666-666666666666"}, {"amount", "12.50"},
                           {"concept", "Movilidad"}, {"currencyCode", "PEN"}};
    const QVariantMap source{{"id", "local-1"}, {"name", "boleta.pdf"}, {"size", 1024},
                             {"lastModified", qint64(1760000000000)}, {"type", "application/pdf"},
                             {"uploadRequestId", fid}};

    // Fila incompleta válida: los 13 campos existen como texto, vacíos incluidos.
    QVariantMap payload = W::payload(form, {}, {source}, expenseRequest);
    assert(W::validatePayload(payload).isEmpty());
    assert(payload.value("form").toMap().size() == W::formFields().size());
    assert(payload.value("baseline").toMap().value("amount").toString().isEmpty());
    assert(payload.value("proposalId").isNull());

    // Rechazos idénticos al SQL.
    auto bad = payload; bad.insert("url", "https://x");
    assert(W::validatePayload(bad) == "payload.url");                 // claves extra
    bad = payload; bad.insert("requestId", "AAAAAAAA-5555-4555-8555-555555555555");
    assert(W::validatePayload(bad) == "payload.requestId");           // UUID no canónico (mayúsculas)
    bad = payload; bad.insert("requestId", "no-es-uuid");
    assert(W::validatePayload(bad) == "payload.requestId");
    bad = payload; auto withUrl = W::formFrom(form); withUrl.insert("signedUrl", "https://x");
    bad.insert("form", withUrl);
    assert(W::validatePayload(bad) == "form.signedUrl");              // nada de URLs/tokens
    bad = payload; auto broken = payload.value("baseline").toMap(); broken.remove("amount"); bad.insert("baseline", broken);
    assert(W::validatePayload(bad) == "baseline.amount");
    bad = payload; broken = payload.value("form").toMap(); broken.insert("concept", QString(8001, QChar(u'a'))); bad.insert("form", broken);
    assert(W::validatePayload(bad) == "form.concept");
    bad = payload; auto s2 = source; s2.insert("path", "renditions/x"); bad.insert("sources", QVariantList{s2});
    assert(W::validatePayload(bad) == "source.path");                 // sin rutas de archivo
    bad = payload; s2 = source; s2.insert("size", "1024"); bad.insert("sources", QVariantList{s2});
    assert(W::validatePayload(bad) == "source.size");                 // size numérico
    bad = payload; s2 = source; s2.insert("contentHash", "abc"); bad.insert("sources", QVariantList{s2});
    assert(W::validatePayload(bad) == "source.contentHash");
    QVariantList many; for (int i = 0; i < 101; ++i) many.append(source);
    bad = payload; bad.insert("sources", many);
    assert(W::validatePayload(bad) == "payload.sources");

    // CAS: 0 crea, >0 exige la versión vigente; EDIT exige versión del gasto base.
    W::IntentLedger ledger;
    auto save = W::saveArguments(rid, wid, 0, {}, payload);
    save.insert("p_request_id", ledger.requestIdFor(save));
    assert(W::validateSave(save).isEmpty());
    assert(save.value("p_expense_id").isNull() && save.value("p_expense_row_version").isNull());
    auto edit = W::saveArguments(rid, wid, 3, ledger.requestIdFor(save), payload, fid, 0);
    assert(W::validateSave(edit) == "p_expense_id");
    assert(W::validateSave(W::saveArguments(rid, wid, -1, expenseRequest, payload)) == "p_expected_version");

    // Idempotencia: mismo intento => mismo request_id; cualquier cambio => intento nuevo.
    const QString first = ledger.requestIdFor(save);
    assert(W::canonicalUuid(first) && ledger.requestIdFor(save) == first);
    auto changed = W::saveArguments(rid, wid, 1, {}, payload);
    const QString second = ledger.requestIdFor(changed);
    assert(second != first && ledger.requestIdFor(changed) == second);
    ledger.acknowledge(wid);
    assert(ledger.requestIdFor(changed) != second);
    ledger.clear();

    // Reserva: coincide con el sustento del payload y con los límites del servidor.
    auto reserve = W::reserveArguments(wid, source);
    assert(W::validateReserve(reserve).isEmpty());
    assert(reserve.value("p_file_id") == fid && reserve.value("p_size_bytes").toLongLong() == 1024);
    auto r2 = reserve; r2.insert("p_file_name", "../boleta.pdf");
    assert(W::validateReserve(r2) == "p_file_name");
    r2 = reserve; r2.insert("p_size_bytes", W::MaxFileBytes + 1);
    assert(W::validateReserve(r2) == "p_size_bytes");
    r2 = reserve; r2.insert("p_mime_type", "PDF");
    assert(W::validateReserve(r2) == "p_mime_type");
    auto untyped = source; untyped.insert("type", "");
    assert(W::reserveArguments(wid, untyped).value("p_mime_type") == "application/octet-stream");
    const QVariantMap reserved{{"id", fid}, {"storage_path", "renditions/" + rid + "/expenses/" + wid + "/attachments/" + fid}};
    assert(W::reservedPathValid(reserved, rid, wid));
    assert(!W::reservedPathValid(reserved, rid, fid));

    // Respuestas: sólo READY con el mismo uploadRequestId cuenta como sustento en nube.
    const QVariantMap row{{"id", wid}, {"rendition_id", rid}, {"kind", "NEW"}, {"state", "ACTIVE"},
        {"row_version", 2}, {"expense_id", QVariant()}, {"expense_row_version", QVariant()},
        {"payload", payload}, {"files", QVariantList{QVariantMap{{"id", fid}, {"source_id", "local-1"}, {"status", "READY"}}}}};
    auto record = W::normalize(row, rid);
    assert(record.error.isEmpty() && record.active() && record.rowVersion == 2);
    assert(record.readySourceIds == QStringList{"local-1"} && W::missingSources(record).isEmpty());
    auto reservedOnly = row; reservedOnly.insert("files", QVariantList{QVariantMap{{"id", fid}, {"source_id", "local-1"}, {"status", "RESERVED"}}});
    assert(W::missingSources(W::normalize(reservedOnly, rid)) == QStringList{"local-1"});
    auto foreign = row; foreign.insert("rendition_id", wid);
    assert(!W::normalize(foreign, rid).error.isEmpty());          // otra rendición: se rechaza
    auto noVersion = row; noVersion.insert("row_version", 0);
    assert(!W::normalize(noVersion, rid).error.isEmpty());
    auto promoted = row; promoted.insert("state", "PROMOTED");
    assert(W::normalize(promoted, rid).error.isEmpty() && !W::normalize(promoted, rid).active());

    // Errores: entorno sin contrato y conflictos nunca se reintentan en silencio.
    assert(W::classify("PGRST202") == "CONTRACT_REQUIRED" && W::permanent("PGRST202"));
    assert(W::conflict("RENDITION_WORKING_CONFLICT") && W::permanent("RENDITION_WORKING_CONFLICT"));
    assert(!W::permanent("NETWORK_AMBIGUOUS") && !W::permanent("RENDITION_ATTACHMENT_OBJECT_MISSING"));
    assert(!W::message("RENDITION_WORKING_ROWS_PENDING").isEmpty());
    assert(!W::message(W::classify("PGRST202")).isEmpty());
    assert(W::message("PGRST202").isEmpty() && W::message("OTHER").isEmpty());   // errorText genérico intacto

    const auto promote = W::promoteArguments(wid, 2, 7);
    assert(promote.value("p_expected_version") == 2 && promote.value("p_expected_rendition_version") == 7);
    assert(W::archiveArguments(wid, 2).size() == 2);

    std::cout << "working-contract: OK\n";
    return 0;
}
