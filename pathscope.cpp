#include "pathscope.h"
#include "authsession.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QDirIterator>

static const QString kNoUidFolder = "Usuario_nouid";

static QString cleanAnyPath(QString p)
{
    return QDir::cleanPath(QDir::fromNativeSeparators(p.trimmed()));
}

void ensureDefaultResourcesIn(const QString& userRoot,
                              const QString& resourcesFolderName,
                              const QString& qrcDefaultsDir)
{
    const QString uroot = cleanAnyPath(userRoot);
    if (uroot.isEmpty()) return;

    const QString dstRes = QDir(uroot).filePath(resourcesFolderName);
    QDir().mkpath(dstRes);

    // Evita copiar cada vez que abres la app
    const QString marker = QDir(dstRes).filePath(".initialized");
    if (QFileInfo::exists(marker)) return;

    // Copia recursiva desde QRC (si existe).
    QDir src(qrcDefaultsDir);
    if (src.exists()) {
        QDirIterator it(qrcDefaultsDir,
                        QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot,
                        QDirIterator::Subdirectories);

        while (it.hasNext()) {
            it.next();
            const QFileInfo fi = it.fileInfo();

            const QString rel = QDir(qrcDefaultsDir).relativeFilePath(fi.filePath());
            const QString dstPath = QDir(dstRes).filePath(rel);

            if (fi.isDir()) {
                QDir().mkpath(dstPath);
            } else {
                QDir().mkpath(QFileInfo(dstPath).absolutePath());
                if (!QFileInfo::exists(dstPath)) {
                    QFile::copy(fi.filePath(), dstPath);
                }
            }
        }
    }

    QFile f(marker);
    if (f.open(QIODevice::WriteOnly)) {
        f.write("ok");
        f.close();
    }
}

QString ensureUserScopedRoot(const QString& rootMaybeGlobal,
                             bool allowGlobalWhenNoSession,
                             bool ensureResourcesFolder)
{
    QString root = cleanAnyPath(rootMaybeGlobal);
    if (root.isEmpty()) return root;

    AuthSession* auth = AuthSession::instance();

    QString folder;
    if (auth && auth->isLogged()) {
        folder = auth->localUserFolderName().trimmed();
        if (folder.isEmpty()) {
            const QString uid = auth->userId().trimmed();
            if (!uid.isEmpty())
                folder = "Usuario_" + uid;
        }
    } else {
        if (allowGlobalWhenNoSession) return root;
        folder = kNoUidFolder;
    }

    if (folder.isEmpty()) return root;

#ifdef Q_OS_WIN
    const Qt::CaseSensitivity cs = Qt::CaseInsensitive; // ✅ CORRECTO en Windows
#else
    const Qt::CaseSensitivity cs = Qt::CaseSensitive;
#endif

    // ✅ IDEMPOTENTE: si ya termina en /folder, no lo vuelvas a anexar
    const QString last = QFileInfo(root).fileName();
    if (last.compare(folder, cs) == 0) {
        if (ensureResourcesFolder)
            ensureDefaultResourcesIn(root, "Recursos", ":/default_resources");
        return root;
    }

    const QString scoped = cleanAnyPath(QDir(root).filePath(folder));
    QDir().mkpath(scoped);

    if (ensureResourcesFolder)
        ensureDefaultResourcesIn(scoped, "Recursos", ":/default_resources");

    return scoped;
}
