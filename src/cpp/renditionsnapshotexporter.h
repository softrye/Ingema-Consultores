#pragma once

#include <QVariantMap>
#include <QVariantList>
#include <QString>

// Constructed exclusively from get_received_rendition_v02, never local drafts.
struct SnapshotExportModel {
    QString code, owner, project, projects, period, status, submittedAt, versionId, hash;
    int version = 0;
    double totalPen = 0, totalUsd = 0;
    QVariantList expenses, attachments;
    static bool fromReceived(const QVariantMap &received, SnapshotExportModel *model, QString *error);
    QString fileBaseName() const;
};

class RenditionSnapshotExporter {
public:
    static bool write(const SnapshotExportModel &model, const QString &format,
                      const QString &path, QString *error);
};
