#pragma once
#include <QVariantMap>
#include <QVariantList>

namespace RenditionContract {
inline bool canEditWorkingCopy(const QVariantMap &row) {
    const auto version = row.value("row_version", row.value("rowVersion"));
    if (version.isValid() && (version.toLongLong() < 0 || version.toLongLong() > 9007199254740991LL)) return false;
    const auto status = row.value("status", "BORRADOR").toString().toUpper();
    if (row.value("archived").toBool() || row.value("is_blocked", row.value("isBlocked")).toBool()
        || row.value("isSnapshot").toBool() || (status != "BORRADOR" && status != "OBSERVADO")) return false;
    if (row.contains("can_edit_content") || row.contains("canEditContent")) {
        const auto permission = row.value("can_edit_content", row.value("canEditContent"));
        return permission.metaType().id() == QMetaType::Bool && permission.toBool();
    }
    return status == "BORRADOR" && row.value("remoteId").toString().isEmpty()
        && row.value("currentVersionId").toString().isEmpty() && !row.contains("id");
}
// List and detail RPCs have different shapes. Missing detail fields are not
// deletions: preserve local values, while explicit projects=[] remains empty.
inline QVariantMap normalize(const QVariantMap &row, const QVariantMap &saved = {}) {
    QVariantMap result = row;
    const QMap<QString, QString> aliases{
        {"displayName", "display_name"},
        {"projectIds", "project_ids"}, {"primaryProjectId", "primary_project_id"},
        {"primaryProjectName", "primary_project_name"}, {"totalPen", "total_pen"},
        {"totalUsd", "total_usd"}, {"expenseCount", "expense_count"},
        {"versionNumber", "version_number"}, {"currentVersionId", "current_version_id"},
        {"baseCurrency", "base_currency_code"}, {"canEditContent", "can_edit_content"}, {"periodStart", "period_start"},
        {"periodEnd", "period_end"}, {"createdAt", "created_at"}, {"updatedAt", "updated_at"}
    };
    for (auto it = aliases.cbegin(); it != aliases.cend(); ++it) {
        if (row.contains(it.key())) result.insert(it.key(), row.value(it.key()));
        else if (row.contains(it.value())) result.insert(it.key(), row.value(it.value()));
        else if (saved.contains(it.key())) result.insert(it.key(), saved.value(it.key()));
    }
    if (row.contains("associatedProjectIds")) result.insert("projectIds", row.value("associatedProjectIds"));
    if (row.contains("projects")) {
        QVariantList ids; QString primary, name;
        for (const auto &entry : row.value("projects").toList()) {
            const auto project = entry.toMap();
            const auto id = project.value("id", project.value("project_id")).toString();
            if (id.isEmpty()) continue;
            if (!ids.contains(id)) ids.append(id);
            if (project.value("is_primary").toBool()) { primary = id; name = project.value("name").toString(); }
        }
        result.insert("projectIds", ids);
        result.insert("primaryProjectId", primary);
        result.insert("primaryProjectName", name);
    }
    if (row.contains("current_version_number")) result.insert("versionNumber", row.value("current_version_number"));
    result.insert("currentVersionNumber", result.value("versionNumber"));
    // An incomplete list response cannot preserve a stale positive authorization.
    if (!row.contains("canEditContent") && !row.contains("can_edit_content")) result.insert("canEditContent", false);
    return result;
}
}
