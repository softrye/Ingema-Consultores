#pragma once
#include <QVariantMap>
#include <QUuid>

namespace RenditionAttachmentContract {
inline QString objectPath(const QVariantMap &row) {
    for (const auto *key : {"storage_path", "objectPath", "object_path"}) {
        const auto path = row.value(QLatin1String(key)).toString();
        if (!path.isEmpty()) return path;
    }
    return {};
}
// reserve_rendition_attachment_v01 owns the key. Never fabricate one locally.
inline bool valid(const QString &bucket, const QString &path, const QString &id) {
    const auto parts = path.split('/');
    return bucket == QLatin1String("project-files") && parts.size() == 6
        && parts[0] == QLatin1String("renditions")
        && parts[2] == QLatin1String("expenses")
        && parts[4] == QLatin1String("attachments")
        && !QUuid(parts[1]).isNull() && !QUuid(parts[3]).isNull()
        && !QUuid(id).isNull() && parts[5] == id;
}
}
