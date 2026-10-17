#pragma once

#include <QString>
#include <QStringList>
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
    } else if (operation == QLatin1String("filesContract")) {
        // Files v07 (PR #5/#6): disponibilidad del contrato por entorno (PGRST202 = no desplegado).
        *rpc = QStringLiteral("get_files_recovery_contract_v07");
    } else if (operation == QLatin1String("filesArchive") || operation == QLatin1String("filesTrash")) {
        // Archivero (sólo lectura) y Papelera global jerárquicos; ACL exclusivamente del servidor.
        *rpc = operation == QLatin1String("filesArchive") ? QStringLiteral("list_files_archive_children_v07")
                                                          : QStringLiteral("list_files_trash_children_v07");
        *params = {{QStringLiteral("p_parent_id"), nullable(arguments.value(QStringLiteral("parentId")).toString())},
                   {QStringLiteral("p_after_id"), nullable(arguments.value(QStringLiteral("afterId")).toString())},
                   {QStringLiteral("p_limit"), 200}};
    } else if (operation == QLatin1String("filesCanChoose")) {
        *rpc = QStringLiteral("can_select_files_recovery_destination_v07");
        *params = {{QStringLiteral("p_entity_id"), arg("entityId")},
                   {QStringLiteral("p_space_id"), arg("spaceId")},
                   {QStringLiteral("p_node_id"), nullable(arguments.value(QStringLiteral("nodeId")).toString())}};
    } else if (operation == QLatin1String("filesPreviewRecovery") || operation == QLatin1String("filesRecover")) {
        // Recuperación reversible: vista previa (token) -> mutación con el MISMO token,
        // versión esperada y request_id idempotente. Nunca purga ni borra.
        *rpc = operation == QLatin1String("filesPreviewRecovery") ? QStringLiteral("preview_files_recovery_v07")
                                                                  : QStringLiteral("mutate_files_recovery_v07");
        *params = {{QStringLiteral("p_entity_id"), arg("entityId")},
                   {QStringLiteral("p_expected_version"), arg("expectedVersion").toLongLong()},
                   {QStringLiteral("p_destination_space_id"), nullable(arguments.value(QStringLiteral("destinationSpaceId")).toString())},
                   {QStringLiteral("p_destination_node_id"), nullable(arguments.value(QStringLiteral("destinationNodeId")).toString())}};
        if (operation == QLatin1String("filesRecover")) {
            params->insert(QStringLiteral("p_request_id"), arg("requestId"));
            params->insert(QStringLiteral("p_preview_token"), arg("previewToken"));
        }
    } else if (operation == QLatin1String("filesArchivedContext")) {
        *rpc = QStringLiteral("get_my_archived_document_context_v07");
        *params = {{QStringLiteral("p_node_id"), arg("nodeId")}};
    } else if (operation == QLatin1String("workingInspect")) {
        // Lectura de la versión vigente del servidor (resolución de conflictos Working).
        *rpc = QStringLiteral("list_rendition_working_rows_v01");
        *params = {{QStringLiteral("p_rendition_id"), arg("renditionId")}};
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

// Comandos Files/Working de sólo lectura o recuperación reversible enrutados por
// el canal solicitud/respuesta del bridge (ninguno purga, borra ni mueve bytes).
inline bool isFilesOperation(const QString &operation)
{
    static const QStringList names{QStringLiteral("filesContract"), QStringLiteral("filesArchive"),
        QStringLiteral("filesTrash"), QStringLiteral("filesCanChoose"), QStringLiteral("filesPreviewRecovery"),
        QStringLiteral("filesRecover"), QStringLiteral("filesArchivedContext"), QStringLiteral("workingInspect")};
    return names.contains(operation);
}

} // namespace RenditionAdminRpc
