#pragma once
#include <QString>
#include <QVector>
#include <QHash>
#include "clouddocs.h"
#include "syncmanifest.h"

class SyncEngine
{
public:
    enum class OpType {
        Upload,
        Download,
        DeleteRemote,
        DeleteLocal,
        MoveRemote,
        Skip,
        Conflict
    };

    struct Op {
        OpType type = OpType::Skip;

        QString relPath;
        QString absLocal;

        QString fromRel;
        QString toRel;

        // ✅ meta precalculada (para manifest)
        qint64 size = 0;
        qint64 mtimeMs = 0;
        QString sha1;

        QString reason;
    };


    struct Plan {
        QVector<Op> ops;
        int uploads = 0;
        int downloads = 0;
        int deletesRemote = 0;
        int deletesLocal = 0;
        int movesRemote = 0;
        int conflicts = 0;
    };

    static QString relFromAbs(const QString& projectRootAbs, const QString& absPath);
    static qint64 isoToMsUtc(const QString& iso);

    // Modo espejo:
    // - local manda
    // - renombres => moveRemote (si se detecta por SHA1 en manifest)
    // - deletes locales => deleteRemote (si manifest lo conoce)
    // - remotos nuevos => download (si allowDownload=true)
    static Plan buildMirrorPlan(const QString& projectRootAbs,
                                const QVector<QString>& localFilesAbs,
                                const QVector<CloudDocItem>& remoteItems,
                                const SyncManifest& manifest,
                                bool allowDeleteRemote = true,
                                bool allowDownload = true);
};
