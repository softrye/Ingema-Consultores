#include "syncengine.h"
#include <QDir>
#include <QFileInfo>
#include <QDateTime>




QString SyncEngine::relFromAbs(const QString& projectRootAbs, const QString& absPath)
{
    QDir root(projectRootAbs);
    QString rel = root.relativeFilePath(absPath);
    rel.replace('\\', '/');
    rel = QDir::cleanPath(rel);
    if (rel.startsWith("./")) rel = rel.mid(2);
    return SyncManifest::normalizeRel(rel);
}

qint64 SyncEngine::isoToMsUtc(const QString& iso)
{
    if (iso.isEmpty()) return 0;
    QDateTime dt = QDateTime::fromString(iso, Qt::ISODateWithMs);
    if (!dt.isValid()) dt = QDateTime::fromString(iso, Qt::ISODate);
    if (!dt.isValid()) return 0;
    dt = dt.toUTC();
    return dt.toMSecsSinceEpoch();
}

SyncEngine::Plan SyncEngine::buildMirrorPlan(const QString& projectRootAbs,
                                             const QVector<QString>& localFilesAbs,
                                             const QVector<CloudDocItem>& remoteItems,
                                             const SyncManifest& manifest,
                                             bool allowDeleteRemote,
                                             bool allowDownload)
{
    Plan plan;

    // ---- Local map: rel -> abs + sha1
    struct LocalMeta { QString abs; qint64 size=0; qint64 mtimeMs=0; QString sha1; };
    QHash<QString, LocalMeta> localByRel;
    QHash<QString, QString>   localRelBySha; // sha -> rel (para detectar renombres)

    for (const QString& abs : localFilesAbs) {
        QFileInfo fi(abs);
        if (!fi.exists() || fi.isDir()) continue;

        const QString rel = SyncManifest::normalizeRel(relFromAbs(projectRootAbs, abs));
        if (rel.isEmpty()) continue;

        // no sincronizar el manifest
        if (fi.fileName().compare(".inge_sync_manifest.json", Qt::CaseInsensitive) == 0)
            continue;

        LocalMeta m;
        m.abs = abs;
        m.size = fi.size();
        m.mtimeMs = fi.lastModified().toUTC().toMSecsSinceEpoch();

        // hash (útil para detectar renombre/cambio)
        QString err;
        m.sha1 = SyncManifest::sha1File(abs, &err);

        localByRel.insert(rel, m);
        if (!m.sha1.isEmpty())
            localRelBySha.insert(m.sha1, rel);
    }

    // ---- Remote map: rel -> item
    QHash<QString, CloudDocItem> remoteByRel;
    for (const auto& it : remoteItems) {
        if (it.isFolder) continue;
        QString rel = SyncManifest::normalizeRel(it.relativePath);
        if (rel.isEmpty()) continue;
        // no tocar el manifest si lo subiste por error
        if (QFileInfo(rel).fileName().compare(".inge_sync_manifest.json", Qt::CaseInsensitive) == 0)
            continue;
        remoteByRel.insert(rel, it);
    }

    // Sets
    QSet<QString> localSet  = QSet<QString>(localByRel.keyBegin(),  localByRel.keyEnd());
    QSet<QString> remoteSet = QSet<QString>(remoteByRel.keyBegin(), remoteByRel.keyEnd());

    const QSet<QString> localOnly  = localSet - remoteSet;
    const QSet<QString> remoteOnly = remoteSet - localSet;
    const QSet<QString> both       = localSet & remoteSet;




    // “Remaining” (OJO: declarar UNA sola vez)
    QSet<QString> localOnlyRemaining  = localOnly;
    QSet<QString> remoteOnlyRemaining = remoteOnly;

    // firstSync real
    const bool firstSync = manifest.isFirstSync(); // entries empty AND lastSyncAt empty
    // (si prefieres) const bool firstSync = (manifest.count() == 0);

    // 3.a) Renombre (MoveRemote) basado en sha1 guardado en manifest
    const QSet<QString> remoteOnlySnapshot = remoteOnlyRemaining; // snapshot para iterar seguro

    for (const QString& oldRel : remoteOnlySnapshot) {
        if (!remoteOnlyRemaining.contains(oldRel)) continue;
        if (!manifest.has(oldRel)) continue;

        const auto oldMe = manifest.get(oldRel);
        if (oldMe.sha1.isEmpty()) continue;

        const QString newRel = localRelBySha.value(oldMe.sha1);
        if (newRel.isEmpty()) continue;

        // debe ser “nuevo nombre” local (localOnly)
        if (!localOnlyRemaining.contains(newRel)) continue;

        // si en remoto ya existe newRel, no intentamos move (sería conflicto)
        if (remoteByRel.contains(newRel)) continue;

        Op op;
        op.type = OpType::MoveRemote;
        op.fromRel = oldRel;
        op.toRel = newRel;
        op.reason = "Detectado renombre por SHA1 (manifest).";
        plan.ops.push_back(op);
        plan.movesRemote++;

        // IMPORTANTÍSIMO: evita subir el newRel, porque el move lo creará
        localOnlyRemaining.remove(newRel);
        remoteOnlyRemaining.remove(oldRel);
    }


    // ---- 1) Upload localOnly que NO fueron renombres
    for (const QString& rel : localOnlyRemaining) {
        const auto lm = localByRel.value(rel);
        Op op;
        op.type = OpType::Upload;
        op.relPath = rel;
        op.absLocal = lm.abs;
        op.size = lm.size;
        op.mtimeMs = lm.mtimeMs;
        op.sha1 = lm.sha1;
        op.reason = "No existe en remoto.";

    }

    // ---- 2) Comparar ambos
    for (const QString& rel : both) {
        const auto lm = localByRel.value(rel);
        const auto rm = remoteByRel.value(rel);

        // manifest info
        const bool hasM = manifest.has(rel);
        const auto me = hasM ? manifest.get(rel) : ManifestEntry{};

        const qint64 remoteMs = isoToMsUtc(rm.updatedAt);
        const bool remoteLooksNewer = (remoteMs > 0 && remoteMs > lm.mtimeMs + 1500);

        // si el local cambió vs lo que el manifest recuerda => upload
        const bool localChanged =
            (!hasM) ||
            (me.size != lm.size) ||
            (me.sha1.isEmpty()) ||          // ✅ cura
            (me.sha1 != lm.sha1);


        if (localChanged) {
            Op op;
            op.type = OpType::Upload;
            op.relPath = rel;
            op.absLocal = lm.abs;
            op.size = lm.size;
            op.mtimeMs = lm.mtimeMs;
            op.sha1 = lm.sha1;
            op.reason = "Local cambió (sha/size) vs manifest.";

        } else if (remoteLooksNewer && allowDownload) {
            // remoto cambió “por fuera” (otro dispositivo)
            Op op;
            op.type = OpType::Download;
            op.relPath = rel;
            op.absLocal = lm.abs; // destino
            op.reason = "Remoto parece más nuevo (updated_at).";
            plan.ops.push_back(op);
            plan.downloads++;
        } else if (remoteLooksNewer && !allowDownload) {
            Op op;
            op.type = OpType::Conflict;
            op.relPath = rel;
            op.absLocal = lm.abs;
            op.reason = "Remoto más nuevo, downloads desactivados.";
            plan.ops.push_back(op);
            plan.conflicts++;
        } else {
            // OK
            Op op;
            op.type = OpType::Skip;
            op.relPath = rel;
            op.absLocal = lm.abs;
            op.reason = "Sin cambios.";
            plan.ops.push_back(op);
        }
    }

    // ---- 3.b) RemoteOnly restante: delete remoto SOLO si era conocido por manifest
    for (const QString& rel : remoteOnlyRemaining) {
        if (allowDeleteRemote && !firstSync && manifest.has(rel)) {
            Op op;
            op.type = OpType::DeleteRemote;
            op.relPath = rel;
            op.reason = "No existe local y está en manifest => borrar remoto (espejo).";
            plan.ops.push_back(op);
            plan.deletesRemote++;
        } else if (allowDownload) {
            Op op;
            op.type = OpType::Download;
            op.relPath = rel;
            op.absLocal = QDir(projectRootAbs).filePath(rel);
            op.reason = firstSync
                            ? "First sync: descargar remoto."
                            : "Remoto extra (no manifest) => descargar.";
            plan.ops.push_back(op);
            plan.downloads++;
        } else {
            Op op;
            op.type = OpType::Skip;
            op.relPath = rel;
            op.reason = "Remoto extra y no se permite borrar/descargar.";
            plan.ops.push_back(op);
        }
    }




    return plan;
}
