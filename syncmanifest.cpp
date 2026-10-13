#include "syncmanifest.h"

#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QSaveFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QCryptographicHash>

SyncManifest::SyncManifest(const QString& manifestPath)
    : m_path(manifestPath)
{}

void SyncManifest::setManifestPath(const QString& path) { m_path = path; }
QString SyncManifest::manifestPath() const { return m_path; }

QString SyncManifest::lastSyncAt() const { return m_lastSyncAt; }
void SyncManifest::setLastSyncAt(const QString& isoUtc) { m_lastSyncAt = isoUtc; }

QString SyncManifest::normalizeRel(QString rel)
{
    rel = rel.trimmed();
    rel.replace('\\', '/');
    rel = QDir::cleanPath(rel);
    if (rel.startsWith("./")) rel = rel.mid(2);
    if (rel == ".") rel.clear();
    while (rel.startsWith('/')) rel.remove(0, 1);
    return rel;
}

bool SyncManifest::has(const QString& rel) const
{
    return m_entries.contains(normalizeRel(rel));
}

ManifestEntry SyncManifest::get(const QString& rel) const
{
    return m_entries.value(normalizeRel(rel));
}

void SyncManifest::upsert(const ManifestEntry& e)
{
    ManifestEntry copy = e;
    copy.relativePath = normalizeRel(copy.relativePath);
    if (copy.relativePath.isEmpty())
        return;
    m_entries.insert(copy.relativePath, copy);
}

void SyncManifest::remove(const QString& rel)
{
    m_entries.remove(normalizeRel(rel));
}

QVector<ManifestEntry> SyncManifest::all() const
{
    QVector<ManifestEntry> out;
    out.reserve(m_entries.size());
    for (auto it = m_entries.constBegin(); it != m_entries.constEnd(); ++it)
        out.push_back(it.value());
    return out;
}

void SyncManifest::markDeleted(const QString& rel, qint64 nowMsUtc)
{
    const QString k = normalizeRel(rel);
    if (k.isEmpty()) return;

    ManifestEntry e = m_entries.value(k);
    e.relativePath = k;
    e.deleted = true;
    e.deletedAtMs = nowMsUtc;
    m_entries.insert(k, e);
}

void SyncManifest::clearDeleted(const QString& rel)
{
    const QString k = normalizeRel(rel);
    if (!m_entries.contains(k)) return;
    auto e = m_entries.value(k);
    e.deleted = false;
    e.deletedAtMs = 0;
    m_entries.insert(k, e);
}

QString SyncManifest::sha1File(const QString& absPath, QString* err)
{
    QFile f(absPath);
    if (!f.open(QIODevice::ReadOnly)) {
        if (err) *err = "No se pudo abrir para SHA1: " + absPath;
        return {};
    }
    QCryptographicHash h(QCryptographicHash::Sha1);
    while (!f.atEnd()) {
        h.addData(f.read(1024 * 256));
    }
    return QString::fromLatin1(h.result().toHex());
}

bool SyncManifest::load(QString* err)
{
    m_entries.clear();
    m_lastSyncAt.clear();

    if (m_path.isEmpty()) {
        if (err) *err = "SyncManifest: manifestPath vacío.";
        return false;
    }

    QFile f(m_path);
    if (!f.exists()) return true; // no existe aún => OK

    if (!f.open(QIODevice::ReadOnly)) {
        if (err) *err = "No se pudo abrir manifest: " + m_path;
        return false;
    }

    QJsonParseError pe{};
    const auto doc = QJsonDocument::fromJson(f.readAll(), &pe);
    if (pe.error != QJsonParseError::NoError || !doc.isObject()) {
        if (err) *err = "Manifest inválido JSON.";
        return false;
    }

    const QJsonObject root = doc.object();
    m_lastSyncAt = root.value("lastSyncAt").toString();

    const QJsonArray arr = root.value("entries").toArray();
    for (const auto& v : arr) {
        const QJsonObject o = v.toObject();
        ManifestEntry e;
        e.relativePath     = normalizeRel(o.value("path").toString());
        e.isFolder         = o.value("isFolder").toBool(false);
        e.size             = (qint64)o.value("size").toDouble(0);
        e.mtimeMs          = (qint64)o.value("mtimeMs").toDouble(0);
        e.sha1             = o.value("sha1").toString();
        e.remoteUpdatedAt  = o.value("remoteUpdatedAt").toString();
        e.remoteEtag       = o.value("remoteEtag").toString();
        e.remoteMtimeType  = o.value("remoteMtimeType").toString();
        e.deleted          = o.value("deleted").toBool(false);
        e.deletedAtMs      = (qint64)o.value("deletedAtMs").toDouble(0);

        if (!e.relativePath.isEmpty())
            m_entries.insert(e.relativePath, e);
    }

    return true;
}

bool SyncManifest::save(QString* err) const
{
    if (m_path.isEmpty()) {
        if (err) *err = "SyncManifest: manifestPath vacío.";
        return false;
    }

    QDir().mkpath(QFileInfo(m_path).absolutePath());

    QJsonObject root;
    root["version"] = 1;
    root["lastSyncAt"] = m_lastSyncAt;

    QJsonArray arr;
    for (auto it = m_entries.constBegin(); it != m_entries.constEnd(); ++it) {
        const ManifestEntry& e = it.value();
        QJsonObject o;
        o["path"]            = e.relativePath;
        o["isFolder"]        = e.isFolder;
        o["size"]            = (double)e.size;
        o["mtimeMs"]         = (double)e.mtimeMs;
        o["sha1"]            = e.sha1;
        o["remoteUpdatedAt"] = e.remoteUpdatedAt;
        o["remoteEtag"]      = e.remoteEtag;
        o["remoteMtimeType"] = e.remoteMtimeType;
        o["deleted"]         = e.deleted;
        o["deletedAtMs"]     = (double)e.deletedAtMs;
        arr.append(o);
    }
    root["entries"] = arr;

    QSaveFile sf(m_path);
    if (!sf.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        if (err) *err = "No se pudo escribir manifest: " + m_path;
        return false;
    }
    sf.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    if (!sf.commit()) {
        if (err) *err = "No se pudo commit manifest: " + m_path;
        return false;
    }
    return true;
}

