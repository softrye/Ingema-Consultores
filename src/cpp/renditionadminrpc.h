#pragma once

#include <QString>
#include <QVariantMap>

// Contrato puro comando del bridge -> RPC administrativa/documental de
// Supabase (sin red). Mismos nombres y argumentos que la Web
// (RenditionReviewPanel, renditionDossierService). false = comando desconocido.
namespace RenditionAdminRpc {

inline QVariant nullable(const QString &value)
{
    return value.trimmed().isEmpty() ? QVariant() : QVariant(value.trimmed());
}

inline bool call(const QString &operation, const QVariantMap &arguments,
                 QString *rpc, QVariantMap *params)
{
    rpc->clear();
    params->clear();
    const auto arg = [&arguments](const char *key) { return arguments.value(QLatin1String(key)); };
    if (operation == QLatin1String("folderCapabilities")) {
        *rpc = QStringLiteral("get_document_structural_capabilities_v02");
        *params = {{QStringLiteral("p_space_id"), arg("spaceId")},
                   {QStringLiteral("p_node_id"), arg("nodeId")}};
    } else if (operation == QLatin1String("reviewContext")) {
        // Revisión y permisos efectivos de la Web (RenditionReviewPanel).
        *rpc = QStringLiteral("get_rendition_review_context_v03");
        *params = {{QStringLiteral("p_rendition_id"), arg("renditionId")}};
    } else if (operation == QLatin1String("reviewTransition")) {
        *rpc = QStringLiteral("transition_rendition_review_v03");
        *params = {{QStringLiteral("p_rendition_id"), arg("renditionId")},
                   {QStringLiteral("p_expected_row_version"), arg("expectedRowVersion").toLongLong()},
                   {QStringLiteral("p_next_state"), arg("nextState")},
                   {QStringLiteral("p_reason"), arg("reason").toString().trimmed()}};
    } else if (operation == QLatin1String("reviewRequest")) {
        *rpc = QStringLiteral("request_rendition_state_v04");
        *params = {{QStringLiteral("p_rendition_id"), arg("renditionId")},
                   {QStringLiteral("p_expected_row_version"), arg("expectedRowVersion").toLongLong()},
                   {QStringLiteral("p_request_id"), arg("requestId")},
                   {QStringLiteral("p_requested_state"), arg("requestedState").toString().isEmpty()
                        ? QVariant(QStringLiteral("OBSERVADO")) : arg("requestedState")},
                   {QStringLiteral("p_reason"), arg("reason").toString().trimmed()}};
    } else if (operation == QLatin1String("reviewDecide")) {
        *rpc = QStringLiteral("decide_rendition_edit_v03");
        *params = {{QStringLiteral("p_rendition_id"), arg("renditionId")},
                   {QStringLiteral("p_edit_request_id"), arg("editRequestId")},
                   {QStringLiteral("p_expected_row_version"), arg("expectedRowVersion").toLongLong()},
                   {QStringLiteral("p_expected_request_row_version"), arg("expectedRequestRowVersion").toLongLong()},
                   {QStringLiteral("p_approve"), arg("approve").toBool()},
                   {QStringLiteral("p_reason"), arg("reason").toString().trimmed()}};
    } else if (operation == QLatin1String("receive")) {
        // Recepción administrativa idempotente por request_id (Web: renditionDossierService).
        *rpc = QStringLiteral("receive_rendition_v01");
        *params = {{QStringLiteral("p_rendition_id"), arg("renditionId")},
                   {QStringLiteral("p_request_id"), arg("requestId")}};
    } else if (operation == QLatin1String("receivedList")) {
        *rpc = QStringLiteral("list_received_renditions_v02");
        *params = {{QStringLiteral("p_limit"), 200},
                  {QStringLiteral("p_after_submitted_at"), nullable(arguments.value(QStringLiteral("afterSubmittedAt")).toString())},
                  {QStringLiteral("p_after_id"), nullable(arguments.value(QStringLiteral("afterId")).toString())}};
    } else {
        params->insert(QStringLiteral("p_rendition_id"), arg("renditionId"));
        if (operation == QLatin1String("receivedQuery"))
            *rpc = QStringLiteral("get_received_rendition_v02");
        else if (operation == QLatin1String("receivedNotes"))
            *rpc = QStringLiteral("list_rendition_admin_notes_v01");
        else if (operation == QLatin1String("receivedActivity"))
            *rpc = QStringLiteral("list_rendition_activity_v01");
        else if (operation == QLatin1String("receivedAddNote")) {
            *rpc = QStringLiteral("create_rendition_admin_note_v01");
            params->insert(QStringLiteral("p_rendition_version_id"), arg("versionId"));
            params->insert(QStringLiteral("p_request_id"), arg("noteRequestId"));
            params->insert(QStringLiteral("p_body"), arg("body"));
        }
    }
    if (rpc->isEmpty())
        params->clear();
    return !rpc->isEmpty();
}

} // namespace RenditionAdminRpc
