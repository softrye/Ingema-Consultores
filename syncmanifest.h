#pragma once
#include <QString>
#include <QHash>
#include <QVector>

struct ManifestEntry
{
    QString relativePath;     // "Calicatas/SUCS/CT-0+000.calicata.json"
    bool    isFolder = false;

    qint64  size = 0;
    qint64  mtimeMs = 0;      // local
    QString sha1;             // hash local (para detectar cambios/renombres)

    QString remoteUpdatedAt;  // ISO (si lo tienes)
    QString remoteEtag;       // opcional
    QString remoteMtimeType;  // opcional

    bool    deleted = false;  // tombstone (para reflejar deletes)
    qint64  deletedAtMs = 0;
};

class SyncManifest
{
public:
    SyncManifest() = default;
    explicit SyncManifest(const QString& manifestPath);

    void setManifestPath(const QString& path);
    QString manifestPath() const;

    bool load(QString* err = nullptr);
    bool save(QString* err = nullptr) const;

    QString lastSyncAt() const;
    void setLastSyncAt(const QString& isoUtc);

    bool has(const QString& rel) const;
    ManifestEntry get(const QString& rel) const;
    void upsert(const ManifestEntry& e);
    void remove(const QString& rel);

    QVector<ManifestEntry> all() const;

    void markDeleted(const QString& rel, qint64 nowMsUtc);
    void clearDeleted(const QString& rel);

    static QString normalizeRel(QString rel);
    static QString sha1File(const QString& absPath, QString* err = nullptr);

    bool isEmpty() const { return m_entries.isEmpty(); }
    qsizetype count() const { return m_entries.size(); }

    // "primer sync" real: nunca se ha sincronizado este proyecto en este dispositivo
    bool isFirstSync() const { return m_entries.isEmpty() && m_lastSyncAt.isEmpty(); }

private:
    QString m_path;
    QString m_lastSyncAt;
    QHash<QString, ManifestEntry> m_entries; // key=normalized rel
};
