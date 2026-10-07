#pragma once
#include <QVariantMap>
#include <QVariantList>

namespace RenditionContract {
// List and detail RPCs have different shapes. Missing detail fields are not
// deletions: preserve local values, while explicit projects=[] remains empty.
inline QVariantMap normalize(const QVariantMap &row, const QVariantMap &saved = {}) {
    QVariantMap result = row;
    const QMap<QString, QString> aliases{
        {"projectIds", "project_ids"}, {"primaryProjectId", "primary_project_id"},
        {"primaryProjectName", "primary_project_name"}, {"totalPen", "total_pen"},
        {"totalUsd", "total_usd"}, {"expenseCount", "expense_count"},
        {"versionNumber", "version_number"}, {"currentVersionId", "current_version_id"},
        {"baseCurrency", "base_currency_code"}, {"periodStart", "period_start"},
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
    return result;
}
}
