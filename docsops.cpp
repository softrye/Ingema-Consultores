#include "docsops.h"
#include <QLoggingCategory>   // ✅
Q_LOGGING_CATEGORY(lcDocsOps, "inge.docs.ops")  // ✅

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QDirIterator>
#include <QUrl>
#include <QElapsedTimer>
#include <QDebug>
#include <QPointer>
#include <QMetaObject>
#include <QtConcurrent/QtConcurrent>

static bool isDirEmpty(const QString& p)
{
    QDir d(p);
    return d.entryList(QDir::AllEntries | QDir::NoDotAndDotDot).isEmpty();
}

static void tryRemoveIfEmpty(const QString& p)
{
    if (p.isEmpty()) return;
    QFileInfo fi(p);
    if (fi.isDir() && isDirEmpty(p)) {
        QDir(p).removeRecursively();
    }
}

static QString normAbs(const QString& p)
{
    if (p.trimmed().isEmpty()) return {};
    return QDir::cleanPath(QDir::fromNativeSeparators(QFileInfo(p).absoluteFilePath()));
}

static bool copyIfMissing(const QString& srcRes, const QString& dstAbs)
{
    if (dstAbs.isEmpty()) return false;
    if (QFile::exists(dstAbs)) return true;

    if (!QFile::exists(srcRes)) {
        qCWarning(lcDocsOps) << "Missing resource:" << srcRes;   // ✅
        return false;
    }
    QDir().mkpath(QFileInfo(dstAbs).absolutePath());
    return QFile::copy(srcRes, dstAbs);
}

static bool samePath(const QString& a, const QString& b)
{
    const QString aa = normAbs(a);
    const QString bb = normAbs(b);
#if defined(Q_OS_WIN)
    return aa.compare(bb, Qt::CaseInsensitive) == 0;
#else
    return aa == bb;
#endif
}

static QString uniqueCopyName(const QDir& dstDir, const QString& originalName)
{
    QFileInfo fi(originalName);
    const QString base = fi.completeBaseName();
    const QString ext  = fi.suffix();

    for (int n = 1; n < 10000; ++n) {
        const QString suf = (n == 1) ? "" : QString::number(n);
        QString cand;
        if (ext.isEmpty())
            cand = QString("%1_copy%2").arg(base, suf);
        else
            cand = QString("%1_copy%2.%3").arg(base, suf, ext);

        const QString full = dstDir.filePath(cand);
        if (!QFileInfo::exists(full))
            return full;
    }
    return dstDir.filePath(base + "_copy9999" + (ext.isEmpty() ? "" : "." + ext));
}

static QString toLocalPathMaybe(const QString& p)
{
    const QString s = p.trimmed();
    if (s.startsWith("file:", Qt::CaseInsensitive)) {
        const QString lf = QUrl(s).toLocalFile();
        if (!lf.isEmpty()) return lf;
    }
    return p;
}

static void makeWritableOne(const QString& p)
{
    if (p.isEmpty()) return;
    QFile::setPermissions(p,
                          QFileDevice::ReadOwner  | QFileDevice::WriteOwner  | QFileDevice::ExeOwner |
                              QFileDevice::ReadUser   | QFileDevice::WriteUser   | QFileDevice::ExeUser  |
                              QFileDevice::ReadGroup  | QFileDevice::WriteGroup  | QFileDevice::ExeGroup |
                              QFileDevice::ReadOther  | QFileDevice::WriteOther  | QFileDevice::ExeOther
                          );
}

static void makeTreeWritable(const QString& dirPath)
{
    if (dirPath.isEmpty()) return;
    QDirIterator it(dirPath,
                    QDir::AllEntries | QDir::NoDotAndDotDot,
                    QDirIterator::Subdirectories);
    while (it.hasNext()) {
        it.next();
        makeWritableOne(it.filePath());
    }
    makeWritableOne(dirPath);
}


static const QString kResourcesFolderNameOps = "Recursos";
static const QString kResourcesLockFileOps   = ".ingep_resources.lock";

static bool isLockedResourcesRootOps(const QString& absPath)
{
    const QString p = normAbs(toLocalPathMaybe(absPath));
    if (p.isEmpty()) return false;

    QFileInfo fi(p);
    if (!fi.exists() || !fi.isDir()) return false;

    if (fi.fileName().compare(kResourcesFolderNameOps, Qt::CaseInsensitive) != 0)
        return false;

    const QString lockAbs = QDir(fi.absoluteFilePath()).absoluteFilePath(kResourcesLockFileOps);
    return QFileInfo::exists(lockAbs);
}


// ------------------------------------------------------------

DocsOps::DocsOps(QObject* parent) : QObject(parent)
{
    connect(&m_scopedWatcher, &QFutureWatcher<ScopedResult>::finished, this, [this]() {
        const ScopedResult res = m_scopedWatcher.result();
        const int finishedToken = res.token;

        // ignora resultados viejos
        if (finishedToken == m_scopedReqToken) {
            if (!res.ok) setErr(res.err);
            emit scopedRootReady(res.ok, res.rootAbs, res.err);
        }

        m_scopedRunningToken = 0;

        // si hay uno más nuevo pendiente, lánzalo
        if (m_scopedReqToken > finishedToken) {
            startScopedRootAsync(m_scopedReqToken, m_scopedPendingUid);
        }
    });
}

DocsOps::~DocsOps()
{
    if (m_scopedWatcher.isRunning()) {
        m_scopedWatcher.cancel();
        // no wait en UI
    }
}

void DocsOps::setErr(const QString& e)
{
    m_lastError = e;
    emit lastErrorChanged();
}

QString DocsOps::ingeBasePath()
{
    static QString cached;
    if (!cached.isEmpty())
        return cached;

    QString base;

#if defined(Q_OS_ANDROID)
    // InGe+ Mobile: almacenamiento visible para el usuario final.
    // Evita Android/data/<package>/files y usa Almacenamiento interno/Documents.
    base = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (base.isEmpty())
        base = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if (base.isEmpty())
        base = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
#elif defined(Q_OS_IOS)
    base = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (base.isEmpty())
        base = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
#else
    base = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (base.isEmpty())
        base = QDir::homePath();
#endif

    if (base.isEmpty())
        base = QDir::currentPath();

    cached = normAbs(QDir(base).filePath("InGePlusProyectos"));
    QDir().mkpath(cached);
    return cached;
}

QString DocsOps::localUserRoot() const
{
    return normAbs(QDir(ingeBasePath()).filePath("Usuario_nouid"));
}

QString DocsOps::userRoot(const QString& uid) const
{
    return normAbs(QDir(QDir(ingeBasePath()).filePath("Usuarios")).filePath(uid));
}

void DocsOps::ensureDefaultRecursos(const QString& userRoot)
{
    if (userRoot.isEmpty()) return;

    const QString recursosDir = normAbs(QDir(userRoot).filePath("Recursos"));
    QDir().mkpath(recursosDir);

    const QString marker = normAbs(QDir(recursosDir).filePath(".initialized"));

    const QString logoMtc = normAbs(QDir(recursosDir).filePath("Logo_MTC.jpeg"));
    const QString logoAld = normAbs(QDir(recursosDir).filePath("Logo_Aldesa.png"));

    const bool needSeed = !QFile::exists(marker)
                          || !QFile::exists(logoMtc)
                          || !QFile::exists(logoAld);

    if (!needSeed) return;

    copyIfMissing(":/Logos/images/ICONO_LOGO_MTC.jpeg", logoMtc);
    copyIfMissing(":/Logos/images/aldesa_logo.png",      logoAld);

    QFile f(marker);
    if (f.open(QIODevice::WriteOnly)) {
        f.write("ok");
        f.close();
    }

    const QString lockAbs = normAbs(QDir(recursosDir).filePath(kResourcesLockFileOps));
    if (!QFile::exists(lockAbs)) {
        QFile lf(lockAbs);
        if (lf.open(QIODevice::WriteOnly)) {
            lf.write("LOCK: Recursos root\n");
            lf.close();
        }
    }


}

QString DocsOps::scopedRoot(const QString& uid)
{
    QElapsedTimer t; t.start();

    const QString base = ingeBasePath();
    if (base.isEmpty()) return {};

    const QString uidTrim = uid.trimmed();

    // 1) Sin uid => Usuario_nouid
    if (uidTrim.isEmpty()) {
        const QString out = normAbs(QDir(base).filePath("Usuario_nouid"));
        QDir().mkpath(out);
        ensureDefaultRecursos(out);
        return out;
    }

    const QString uid8 = uidTrim.left(8);
    QDir baseDir(base);

    // 2) Busca matches *_<uid8>
    QStringList matches;
    {
        QDirIterator it(base, QStringList() << ("*_" + uid8),
                        QDir::Dirs | QDir::NoDotAndDotDot);
        while (it.hasNext()) {
            it.next();
            matches << normAbs(it.filePath());
        }
    }

    // 3) Elige el mejor (preferir NO Usuario_)
    QString chosen;
    for (const QString& p : matches) {
        const QString name = QFileInfo(p).fileName();
        if (!name.startsWith("Usuario_", Qt::CaseInsensitive)) {
            chosen = p;
            break;
        }
    }
    if (chosen.isEmpty() && !matches.isEmpty())
        chosen = matches.first();

    // 4) fallback Usuario_<uid8>
    if (chosen.isEmpty()) {
        chosen = normAbs(baseDir.filePath("Usuario_" + uid8));
        QDir().mkpath(chosen);
    }

    // 5) Limpieza de fallback vacío
    const QString fallback = normAbs(baseDir.filePath("Usuario_" + uid8));
    if (!samePath(chosen, fallback))
        tryRemoveIfEmpty(fallback);

    ensureDefaultRecursos(chosen);

    qCDebug(lcDocsOps) << "[DocsOps] scopedRoot ms =" << t.elapsed();  // ✅
    return chosen;
}

void DocsOps::applyScopedRoot(const QString& uid)
{
    const QString u = uid.trimmed();
    QPointer<DocsOps> self(this);

    QtConcurrent::run([self, u]() {
        if (!self) return;

        QString root, err;
        bool ok = true;

        root = DocsOps::scopedRoot(u);
        if (root.isEmpty()) { ok = false; err = "scopedRoot vacío"; }

        QMetaObject::invokeMethod(self, [self, ok, root, err]() {
            if (!self) return;
            emit self->scopedRootReady(ok, root, err);
        }, Qt::QueuedConnection);
    });
}

void DocsOps::startScopedRootAsync(int token, const QString& uid)
{
    m_scopedRunningToken = token;

    const QString uidCopy = uid;

    auto future = QtConcurrent::run([token, uidCopy]() -> ScopedResult {
        ScopedResult out;
        out.token = token;

        const QString rootAbs = DocsOps::scopedRoot(uidCopy);
        if (rootAbs.trimmed().isEmpty()) {
            out.ok = false;
            out.err = "No se pudo resolver scopedRoot (vacío).";
            return out;
        }

        // valida existencia (opcional)
        if (!QFileInfo(rootAbs).exists()) {
            QDir().mkpath(rootAbs);
        }

        out.ok = true;
        out.rootAbs = rootAbs;
        return out;
    });

    m_scopedWatcher.setFuture(future);
}

QString DocsOps::parentDir(const QString& path) const
{
    const QString p = normAbs(path);
    if (p.isEmpty()) return {};

    QFileInfo fi(p);
    if (!fi.exists()) return {};

    QDir d = fi.isDir() ? QDir(fi.absoluteFilePath()) : fi.dir();
    if (!d.cdUp()) return {};
    return normAbs(d.absolutePath());
}

bool DocsOps::makeDir(const QString& parentDir, const QString& name)
{
    setErr({});
    const QString nn = name.trimmed();
    if (nn.isEmpty()) { setErr("Nombre vacío"); return false; }

    const QString parent = normAbs(parentDir);
    if (parent.isEmpty()) { setErr("parentDir vacío"); return false; }

    QDir d(parent);
    if (!d.exists() && !QDir().mkpath(parent)) { setErr("No se pudo crear parentDir"); return false; }
    if (d.exists(nn)) { setErr("Ya existe"); return false; }
    if (!d.mkdir(nn)) { setErr("mkdir falló"); return false; }
    return true;
}

bool DocsOps::removePath(const QString& path)
{
    setErr({});

    const QString p = normAbs(toLocalPathMaybe(path));
    if (p.isEmpty()) return true;

    if (isLockedResourcesRootOps(p)) {
        setErr("No se puede eliminar la carpeta 'Recursos' (candado).");
        return false;
    }

    QFileInfo fi(p);
    if (!fi.exists()) return true;

    const QString base = normAbs(ingeBasePath());
    if (!base.isEmpty() && samePath(p, base)) {
        setErr("No se puede eliminar la carpeta base InGePlusProyectos");
        return false;
    }

    if (fi.isDir()) {
        makeTreeWritable(fi.absoluteFilePath());
        QDir d(fi.absoluteFilePath());
        if (d.removeRecursively()) return true;
        if (d.removeRecursively()) return true; // reintento
        setErr("No se pudo eliminar carpeta");
        return false;
    }

    makeWritableOne(fi.absoluteFilePath());
    if (!QFile::remove(fi.absoluteFilePath())) {
        if (QFile::remove(fi.absoluteFilePath())) return true; // reintento
        setErr("No se pudo eliminar archivo");
        return false;
    }
    return true;
}

bool DocsOps::renameInPlace(const QString& oldPath, const QString& newName)
{
    setErr({});

    const QString oldP = normAbs(toLocalPathMaybe(oldPath));
    if (oldP.isEmpty()) { setErr("Ruta inválida"); return false; }

    if (isLockedResourcesRootOps(oldP)) {
        setErr("No se puede renombrar la carpeta 'Recursos' (candado).");
        return false;
    }

    QFileInfo fi(oldP);
    if (!fi.exists()) { setErr("No existe"); return false; }

    const QString nn = newName.trimmed();
    if (nn.isEmpty()) { setErr("Nombre vacío"); return false; }
    if (nn.contains('/') || nn.contains('\\')) { setErr("Nombre inválido"); return false; }

    const QString dst = normAbs(fi.dir().filePath(nn));
    if (dst.isEmpty()) { setErr("Destino inválido"); return false; }
    if (QFileInfo::exists(dst)) { setErr("Destino ya existe"); return false; }

    bool ok = false;
    if (fi.isDir()) {
        QDir parent(fi.dir().absolutePath());
        ok = parent.rename(fi.fileName(), nn);
    } else {
        ok = QFile::rename(oldP, dst);
    }

    if (!ok) { setErr("rename falló"); return false; }
    return true;
}


bool DocsOps::copyDirRec(const QString& srcDir, const QString& dstDir)
{
    QDir src(srcDir);
    if (!src.exists()) return false;

    QDir().mkpath(dstDir);

    const auto entries = src.entryInfoList(QDir::NoDotAndDotDot | QDir::AllEntries);
    for (const QFileInfo& e : entries) {
        const QString srcPath = e.absoluteFilePath();
        const QString dstPath = QDir(dstDir).filePath(e.fileName());

        if (e.isDir()) {
            if (!copyDirRec(srcPath, dstPath)) return false;
        } else {
            QFile::remove(dstPath);
            if (!QFile::copy(srcPath, dstPath)) return false;
        }
    }
    return true;
}

QString DocsOps::copyToDir(const QString& srcPath, const QString& dstDir)
{
    setErr({});
    const QString srcP = normAbs(srcPath);
    if (srcP.isEmpty()) { setErr("Origen vacío"); return {}; }

    QFileInfo fi(srcP);
    if (!fi.exists()) { setErr("Origen no existe"); return {}; }

    const QString dstD = normAbs(dstDir);
    if (dstD.isEmpty()) { setErr("Destino vacío"); return {}; }

    QDir d(dstD);
    if (!d.exists() && !QDir().mkpath(dstD)) { setErr("No se pudo crear destino"); return {}; }

    QString dst = d.filePath(fi.fileName());
    if (QFileInfo::exists(dst)) {
        dst = uniqueCopyName(d, fi.fileName());
    }

    if (fi.isDir()) {
        if (!copyDirRec(fi.absoluteFilePath(), dst)) { setErr("copy dir falló"); return {}; }
        return normAbs(dst);
    }

    if (!QFile::copy(fi.absoluteFilePath(), dst)) { setErr("copy file falló"); return {}; }
    return normAbs(dst);
}

QString DocsOps::moveToDir(const QString& srcPath, const QString& dstDir)
{
    setErr({});

    const QString srcP = normAbs(toLocalPathMaybe(srcPath));
    if (srcP.isEmpty()) { setErr("Origen vacío"); return {}; }

    if (isLockedResourcesRootOps(srcP)) {
        setErr("No se puede mover la carpeta 'Recursos' (candado).");
        return {};
    }

    const QString out = copyToDir(srcP, dstDir);
    if (out.isEmpty()) return {};
    if (!removePath(srcP)) return {};
    return out;
}


bool DocsOps::exportLocalDataToUser(const QString& userDir, bool overwrite)
{
    setErr({});

    const QString srcDir = normAbs(localUserRoot());
    const QString dstDir = normAbs(userDir);

    if (srcDir.isEmpty() || dstDir.isEmpty()) { setErr("Origen o destino vacío"); return false; }
    if (srcDir == dstDir) { setErr("Origen y destino son iguales"); return false; }

    QDir src(srcDir);
    if (!src.exists()) { setErr("No existe Usuario_nouid"); return false; }

    QDir dst(dstDir);
    if (!dst.exists() && !QDir().mkpath(dstDir)) { setErr("No se pudo crear carpeta usuario"); return false; }

    const auto entries = src.entryInfoList(QDir::NoDotAndDotDot | QDir::AllEntries);
    if (entries.isEmpty()) { setErr("No hay datos locales para exportar"); return false; }

    bool okAny = false;

    for (const QFileInfo& e : entries) {
        const QString srcPath = e.absoluteFilePath();
        QString dstPath = dst.filePath(e.fileName());

        if (QFileInfo::exists(dstPath)) {
            if (overwrite) {
                if (!removePath(dstPath)) return false;
            } else {
                dstPath = uniqueCopyName(dst, e.fileName());
            }
        }

        if (e.isDir()) {
            if (!copyDirRec(srcPath, dstPath)) { setErr("No se pudo copiar carpeta: " + e.fileName()); return false; }
        } else {
            QFile::remove(dstPath);
            if (!QFile::copy(srcPath, dstPath)) { setErr("No se pudo copiar archivo: " + e.fileName()); return false; }
        }

        okAny = true;
    }

    return okAny;
}
