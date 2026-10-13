#include "docscontroller.h"

#include <QLoggingCategory>   // ✅
Q_LOGGING_CATEGORY(lcDocsCtl, "inge.docs.controller") // ✅

#include <QFileInfo>
#include <QDirIterator>
#include <QSaveFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QDateTime>
#include <QStandardPaths>
#include <QFile>
#include <QFileDevice>
#include <QTimer>
#include <QtConcurrent/QtConcurrent>
#include <QPointer>
#include <QDir>


// ---------------- helpers (paths / permisos / recursos) ----------------
static inline QString ensureSlash(QString p)
{
    p = QDir::cleanPath(QDir::fromNativeSeparators(p));
    if (!p.endsWith('/')) p += '/';
    return p;
}

static inline QString normPathLower(const QString& p)
{
    return QDir::cleanPath(QDir::fromNativeSeparators(p)).toLower();
}

static bool isUnderPath(const QString& child, const QString& parent)
{
    const QString c = normPathLower(child);
    QString pr = normPathLower(parent);
    if (pr.isEmpty()) return false;
    if (c == pr) return true;
    pr = ensureSlash(pr);
    return c.startsWith(pr);
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

static void makeTreeWritable(const QString& dirAbs)
{
    if (dirAbs.isEmpty()) return;
    QDirIterator it(dirAbs,
                    QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden,
                    QDirIterator::Subdirectories);
    while (it.hasNext()) {
        it.next();
        makeWritableOne(it.filePath());
    }
    makeWritableOne(dirAbs);
}

static QString fixRes(QString src)
{
    if (src.startsWith("qrc:/"))
        src = ":" + src.mid(4);
    return src;
}

static bool copyIfMissingRes(const QString& srcRes, const QString& dstAbs)
{
    if (dstAbs.isEmpty()) return false;
    if (QFileInfo::exists(dstAbs)) return true;

    const QString src = fixRes(srcRes);
    if (!QFileInfo::exists(src)) {
        qWarning() << "Missing resource:" << srcRes << "->" << src;
        return false;
    }

    QDir().mkpath(QFileInfo(dstAbs).absolutePath());
    return QFile::copy(src, dstAbs);
}

static const QString kResourcesFolderName = "Recursos";
static const QString kResourcesLockFile   = ".ingep_resources.lock";

static bool ensureFile(const QString& absFilePath, const QByteArray& content)
{
    QFile f(absFilePath);
    if (QFileInfo::exists(absFilePath)) return true;
    if (!f.open(QIODevice::WriteOnly)) return false;
    f.write(content);
    f.close();
    return true;
}

static bool isLockedResourcesRoot(const QString& absPath)
{
    QFileInfo fi(absPath);
    if (!fi.exists() || !fi.isDir()) return false;
    if (fi.fileName().compare(kResourcesFolderName, Qt::CaseInsensitive) != 0) return false;

    const QString lockAbs = QDir(fi.absoluteFilePath()).absoluteFilePath(kResourcesLockFile);
    return QFileInfo::exists(lockAbs);
}


static QString norm(const QString& p)
{
    QString s = p;
    s.replace('\\', '/');
    while (s.endsWith('/')) s.chop(1);
    return s;
}

static bool isUnderCI(const QString& child, const QString& root)
{
    QString c = norm(child).toLower();
    QString r = norm(root).toLower();
    if (r.isEmpty()) return false;
    if (c == r) return true;
    if (!r.endsWith('/')) r += '/';
    return c.startsWith(r);
}

static bool fileExistsInDir(const QString& dirAbs, const QString& fileName)
{
    return QFileInfo(QDir(dirAbs).absoluteFilePath(fileName)).exists();
}

static QString sanitizeFileName(QString s) {
    s = s.trimmed();
    // quitar caracteres inválidos típicos
    const QString bad = "\\/:*?\"<>|";
    for (QChar c : bad) s.replace(c, '_');
    while (s.contains("  ")) s.replace("  ", " ");
    if (s.isEmpty()) s = "calicata";
    return s;
}

static QString ensureCalicataExt(QString name) {
    name = name.trimmed();
    if (name.isEmpty()) return {};
    const QString low = name.toLower();
    if (low.endsWith(".calicata.json")) return name;
    if (low.endsWith(".json")) name.chop(5);
    if (name.toLower().endsWith(".calicata")) name.chop(8);
    return name + ".calicata.json";
}

bool DocsController::isCalicataFile(const QString& absPath) const {
    const QString p = clean(absPath);
    return p.endsWith(".calicata.json", Qt::CaseInsensitive);
}


// ----------------------------------------------------------------------

DocsController::DocsController(QObject *parent) : QObject(parent)
{
    QElapsedTimer t; t.start();
    qCDebug(lcDocsCtl) << "[DocsController] ctor begin";   // ✅

    // ✅ Default seguro para que QML nunca trabaje con basePath vacío
    QString docs = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (docs.isEmpty())
        docs = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (docs.isEmpty())
        docs = QDir::homePath();

    const QString global = clean(QDir(docs).absoluteFilePath("InGePlusProyectos"));

    m_basePath = clean(QDir(global).absoluteFilePath("Usuario_nouid"));
    // Constructor resolves paths only. applyUserRoot/explicit document operations
    // create account directories and resources when the module is actually used.

    qCDebug(lcDocsCtl) << "[DocsController] ctor ms=" << t.elapsed();  // ✅
}

QString DocsController::findSingleMetaFolderUnderDirectChildren(const QString& root,
                                                                const char* metaFile) const
{
    QDir d(root);
    const QFileInfoList dirs = d.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::Hidden);
    for (const QFileInfo& di : dirs) {
        const QString meta = QDir(di.absoluteFilePath()).absoluteFilePath(metaFile);
        if (QFileInfo::exists(meta))
            return clean(di.absoluteFilePath());
    }
    return {};
}

QString DocsController::sanitizeFolderName(QString s)
{
    s = s.trimmed();
    s.replace("/", "_");
    s.replace("\\", "_");
    s.replace(":", "_");
    s.replace("*", "_");
    s.replace("?", "_");
    s.replace("\"", "_");
    s.replace("<", "_");
    s.replace(">", "_");
    s.replace("|", "_");
    while (s.contains("  ")) s.replace("  ", " ");
    if (s.isEmpty()) s = "user";
    return s;
}

bool DocsController::ensureResourcesFolder() const
{
    if (m_basePath.trimmed().isEmpty()) return false;

    const QString res = QDir(m_basePath).absoluteFilePath(kResourcesFolderName);
    if (!QDir().mkpath(res))
        return false;

    const QString meta = QDir(res).absoluteFilePath(kResourcesMetaFile);
    if (!QFileInfo::exists(meta)) {
        QVariantMap o;
        o["type"] = "resources";
        o["version"] = 1;
        writeJsonMeta(res, kResourcesMetaFile, o);
    }

    // ✅ Copiar logos por defecto si faltan
    copyIfMissingRes(":/Logos/images/ICONO_LOGO_MTC.jpeg", QDir(res).absoluteFilePath("Logo_MTC.jpeg"));
    copyIfMissingRes(":/Logos/images/aldesa_logo.png",     QDir(res).absoluteFilePath("Logo_Aldesa.png"));

    const QString lockAbs = QDir(res).absoluteFilePath(kResourcesLockFile);
    ensureFile(lockAbs, QByteArray("LOCK: Recursos root\n"));


    return true;
}

bool DocsController::isUnderResourcesPath(const QString& absPath) const
{
    const QString res = clean(QDir(m_basePath).absoluteFilePath(kResourcesFolderName));
    const QString p   = clean(absPath);
    if (res.isEmpty() || p.isEmpty()) return false;
    return isUnderPath(p, res);
}

bool DocsController::isProtectedResourcesFile(const QString& absPath) const
{
    const QString fn = QFileInfo(absPath).fileName();
    if (fn.compare(QString::fromUtf8(kResourcesMetaFile), Qt::CaseInsensitive) == 0) return true;
    if (fn.compare(kResourcesLockFile, Qt::CaseInsensitive) == 0) return true; // ✅ LOCK protegido
    return false;
}


bool DocsController::isImageFile(const QString& absPath) const
{
    const QString ext = QFileInfo(absPath).suffix().toLower();
    return ext == "png" || ext == "jpg" || ext == "jpeg";
}

bool DocsController::isExcelFile(const QString& absPath) const
{
    const QString ext = QFileInfo(absPath).suffix().toLower();
    return ext == "xlsx" || ext == "xlsm" || ext == "xls";
}

bool DocsController::isPdfFile(const QString& absPath) const
{
    return QFileInfo(absPath).suffix().toLower() == "pdf";
}

// ---------------- Meta checks ----------------
bool DocsController::isProjectFolder(const QString& folderAbs) const
{
    return QFileInfo(QDir(folderAbs).absoluteFilePath(kProjectMetaFile)).exists();
}
bool DocsController::isEditableFolder(const QString& folderAbs) const
{
    return QFileInfo(QDir(folderAbs).absoluteFilePath(kEditableMetaFile)).exists();
}
bool DocsController::isCalicatasFolder(const QString& folderAbs) const
{
    return QFileInfo(QDir(folderAbs).absoluteFilePath(kCalicatasMetaFile)).exists();
}
bool DocsController::isExcelFolder(const QString& folderAbs) const
{
    return QFileInfo(QDir(folderAbs).absoluteFilePath(kExcelMetaFile)).exists();
}
bool DocsController::isPdfFolder(const QString& folderAbs) const
{
    return QFileInfo(QDir(folderAbs).absoluteFilePath(kPdfMetaFile)).exists();
}

QString DocsController::findMetaUp(const QString& startAbs, const char* metaFile) const
{
    QString p = clean(startAbs);
    QFileInfo fi(p);
    QDir d(fi.isDir() ? p : fi.dir().absolutePath());

    const QString base = clean(m_basePath);
    while (true) {
        const QString meta = d.absoluteFilePath(metaFile);
        if (QFileInfo::exists(meta))
            return clean(meta);

        const QString cur = clean(d.absolutePath());
        if (!base.isEmpty() && cur == base) break;
        if (!d.cdUp()) break;
    }
    return {};
}

bool DocsController::isInsideProject(const QString& anyAbs, QString* outProjectRoot) const
{
    const QString meta = findMetaUp(anyAbs, kProjectMetaFile);
    if (meta.isEmpty()) return false;
    const QString root = QFileInfo(meta).dir().absolutePath();
    if (outProjectRoot) *outProjectRoot = clean(root);
    return true;
}

bool DocsController::canDefineProjectHere(const QString& folderAbs) const
{
    const QString f = clean(folderAbs);
    if (!QFileInfo(f).isDir())
        return false;

    const QString base = clean(m_basePath);
    if (base.isEmpty())
        return false;

    // Debe estar dentro del root del usuario
    if (!isUnderPath(f, base))
        return false;

    // La raíz base NO se convierte en proyecto
    if (f == base)
        return false;

    // Recursos nunca puede ser proyecto, ni nada dentro de Recursos
    if (isResourcesRootFolder(f) || isUnderResourcesPath(f))
        return false;

    // No permitir proyecto dentro de otro proyecto
    QString projRoot;
    if (isInsideProject(f, &projRoot)) {
        // Solo se permite si la misma carpeta ya es el root del proyecto
        // (esto deja funcionar la edición del meta del proyecto existente)
        if (clean(projRoot) != f)
            return false;
    }

    return true;
}

QString DocsController::findSingleMetaFolderUnder(const QString& root, const char* metaFile) const
{
    QDirIterator it(root, QStringList() << metaFile,
                    QDir::Files | QDir::Hidden,
                    QDirIterator::Subdirectories);
    if (!it.hasNext()) return {};
    it.next();
    return clean(QFileInfo(it.filePath()).dir().absolutePath());
}

QString DocsController::findCalicatasFolderInProject(const QString& projRoot) const
{
    return findSingleMetaFolderUnderDirectChildren(projRoot, kCalicatasMetaFile);
}

QString DocsController::findEditableFolderInProject(const QString& projRoot) const
{
    return findSingleMetaFolderUnder(projRoot, kEditableMetaFile);
}

bool DocsController::canDefineCalicatasHere(const QString& folderAbs) const
{
    QString projRoot;
    if (!isInsideProject(folderAbs, &projRoot))
        return false;

    const QString f = clean(folderAbs);
    if (!QFileInfo(f).isDir())
        return false;

    // No permitir convertir el root del proyecto en Calicatas
    if (f == clean(projRoot))
        return false;

    // Regla principal: NO puede estar dentro de otra Calicatas
    QString calRoot;
    if (isInsideCalicatas(f, &calRoot)) {
        // si ya está dentro de Calicatas (y no es esa misma carpeta), bloquea
        if (clean(calRoot) != f)
            return false;

        // si fuera la misma carpeta, significa que ya es Calicatas -> no "definir"
        return false;
    }

    // OK: está dentro de un proyecto y fuera de Calicatas
    return true;
}


bool DocsController::canDefineExcelHere(const QString& folderAbs) const
{
    const QString calMeta = findMetaUp(folderAbs, kCalicatasMetaFile);
    if (calMeta.isEmpty()) return false;
    const QString calRoot = clean(QFileInfo(calMeta).dir().absolutePath());

    if (clean(QFileInfo(folderAbs).dir().absolutePath()) != calRoot)
        return false;

    const QString existing = findSingleMetaFolderUnderDirectChildren(calRoot, kExcelMetaFile);
    if (!existing.isEmpty() && clean(existing) != clean(folderAbs))
        return false;

    return true;
}

bool DocsController::canDefinePdfHere(const QString& folderAbs) const
{
    const QString calMeta = findMetaUp(folderAbs, kCalicatasMetaFile);
    if (calMeta.isEmpty()) return false;
    const QString calRoot = clean(QFileInfo(calMeta).dir().absolutePath());

    if (clean(QFileInfo(folderAbs).dir().absolutePath()) != calRoot)
        return false;

    const QString existing = findSingleMetaFolderUnderDirectChildren(calRoot, kPdfMetaFile);
    if (!existing.isEmpty() && clean(existing) != clean(folderAbs))
        return false;

    return true;
}

// ---------------- Meta write/remove ----------------
bool DocsController::writeJsonMeta(const QString& folderAbs, const char* metaFile, const QVariantMap& fields) const
{
    const QString metaPath = QDir(folderAbs).absoluteFilePath(metaFile);

    QJsonObject o;
    for (auto it = fields.begin(); it != fields.end(); ++it)
        o.insert(it.key(), QJsonValue::fromVariant(it.value()));

    QSaveFile sf(metaPath);
    if (!sf.open(QIODevice::WriteOnly | QIODevice::Truncate)) return false;
    sf.write(QJsonDocument(o).toJson(QJsonDocument::Indented));
    return sf.commit();
}

bool DocsController::removeMeta(const QString& folderAbs, const char* metaFile) const
{
    const QString metaPath = QDir(folderAbs).absoluteFilePath(metaFile);
    if (!QFileInfo::exists(metaPath)) return true;
    makeWritableOne(metaPath);
    return QFile::remove(metaPath);
}

bool DocsController::ensureEditablePhotosDir(const QString& editableFolderAbs) const
{
    return QDir(editableFolderAbs).mkpath(QString::fromUtf8(kEditablePhotosFolder));
}

bool DocsController::ensureCalicatasStructure(const QString& calicatasFolderAbs) const
{
    QDir d(calicatasFolderAbs);

    if (!d.mkpath(kCalicatasEditFolder))  return false;
    if (!d.mkpath(kCalicatasExcelFolder)) return false;
    if (!d.mkpath(kCalicatasPdfFolder))   return false;

    const QString editAbs  = d.absoluteFilePath(kCalicatasEditFolder);
    const QString excelAbs = d.absoluteFilePath(kCalicatasExcelFolder);
    const QString pdfAbs   = d.absoluteFilePath(kCalicatasPdfFolder);

    {
        QVariantMap m;
        m["type"] = "editable";
        m["version"] = 1;
        m["photos_dir"] = QString::fromUtf8(kEditablePhotosFolder);
        if (!writeJsonMeta(editAbs, kEditableMetaFile, m)) return false;
        if (!ensureEditablePhotosDir(editAbs)) return false;
    }
    {
        QVariantMap m;
        m["type"] = "excel";
        m["version"] = 1;
        if (!writeJsonMeta(excelAbs, kExcelMetaFile, m)) return false;
    }
    {
        QVariantMap m;
        m["type"] = "pdf";
        m["version"] = 1;
        if (!writeJsonMeta(pdfAbs, kPdfMetaFile, m)) return false;
    }

    return true;
}

// ---------------- FS ops ----------------
bool DocsController::copyDirRecursively(const QString& srcPath, const QString& dstPath) const
{
    QDir srcDir(srcPath);
    if (!srcDir.exists()) return false;

    QDir dstDir(dstPath);
    if (!dstDir.exists() && !dstDir.mkpath(".")) return false;

    QFileInfoList entries = srcDir.entryInfoList(QDir::Files | QDir::Hidden);
    for (const QFileInfo &fi : entries) {
        const QString srcFile = fi.absoluteFilePath();
        const QString dstFile = dstDir.absoluteFilePath(fi.fileName());
        QFile::remove(dstFile);
        if (!QFile::copy(srcFile, dstFile))
            return false;
    }

    entries = srcDir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::Hidden);
    for (const QFileInfo &di : entries) {
        const QString srcSub = di.absoluteFilePath();
        const QString dstSub = dstDir.absoluteFilePath(di.fileName());
        if (!copyDirRecursively(srcSub, dstSub))
            return false;
    }

    return true;
}

bool DocsController::dirContainsMetaRecursively(const QString& dirAbs, const char* metaFile) const
{
    QDirIterator it(dirAbs, QStringList() << metaFile,
                    QDir::Files | QDir::Hidden,
                    QDirIterator::Subdirectories);
    return it.hasNext();
}

bool DocsController::dirContainsProjectMetaRecursively(const QString& dirAbs) const
{
    return dirContainsMetaRecursively(dirAbs, kProjectMetaFile);
}

QString DocsController::uniqueNameForPaste(const QString& targetDirAbs, const QString& baseName) const
{
    QDir target(targetDirAbs);
    QString destName = baseName;
    int count = 1;
    while (target.exists(destName)) {
        destName = QString("%1 - copia (%2)").arg(baseName).arg(count++);
    }
    return destName;
}

// ---------------- Root por usuario ----------------
QVariantMap DocsController::applyUserRoot(bool logged,
                                          const QString& userId,
                                          const QString& displayName,
                                          const QString& globalBasePath)
{
    QElapsedTimer t; t.start();

    QVariantMap r;

    const QString gb = clean(globalBasePath);
    if (gb.isEmpty()) {
        r["ok"] = false;
        r["err"] = "globalBasePath vacío";
        return r;
    }

    const QString dn = sanitizeFolderName(displayName);
    const QString uid = userId.trimmed();

    const QString folder = (logged && !uid.isEmpty())
                               ? (dn + "_" + uid.left(8))
                               : QStringLiteral("Usuario_nouid");

    const QString newRoot = clean(QDir(gb).absoluteFilePath(folder));
    if (newRoot.isEmpty()) {
        r["ok"] = false;
        r["err"] = "No se pudo construir newRoot";
        return r;
    }

    // ✅ evita trabajo repetido si ya está igual
    if (clean(m_basePath) == newRoot) {
        ensureResourcesFolder();
        emit basePathChanged();
        r["ok"] = true;
        r["basePath"] = m_basePath;
        return r;
    }

    QDir().mkpath(newRoot);
    m_basePath = newRoot;

    if (!ensureResourcesFolder()) {
        r["ok"] = false;
        r["err"] = "No se pudo crear Recursos";
        return r;
    }

    emit basePathChanged();
    r["ok"] = true;
    r["basePath"] = m_basePath;

    qCDebug(lcDocsCtl) << "[DocsController] applyUserRoot ms=" << t.elapsed()
                       << "logged=" << logged << "uid8=" << userId.left(8)
                       << "basePath=" << m_basePath;      // ✅

    return r;
}

// ---------------- Capabilities ----------------
QVariantMap DocsController::capabilities(const QString& selectedAbsPath) const
{
    QVariantMap c;

    const QString p = clean(selectedAbsPath);
    QFileInfo fi(p);

    const bool hasSelection = !p.isEmpty() && fi.exists();
    const bool isDir = hasSelection && fi.isDir();

    c["hasSelection"] = hasSelection;
    c["isDir"] = isDir;

    const QString folderPath = hasSelection
                                   ? (isDir ? p : fi.dir().absolutePath())
                                   : QString();

    // ---------------- Paths/Áreas ----------------
    const bool underRes = hasSelection && isUnderResourcesPath(p);
    c["underResources"] = underRes;

    const bool isResRoot = isDir && isResourcesRootFolder(folderPath);
    c["isResourcesRoot"] = isResRoot;

    const bool isLevel1 = isDir && isLevel1Folder(folderPath);
    c["isLevel1"] = isLevel1;

    QString projRoot;
    const bool insideProj = hasSelection && isInsideProject(folderPath, &projRoot);
    projRoot = clean(projRoot);
    c["insideProject"] = insideProj;
    c["projectRoot"] = projRoot;

    QString calRoot;
    const bool insideCal = hasSelection && isInsideCalicatas(folderPath, &calRoot);
    calRoot = clean(calRoot);
    c["insideCalicatas"] = insideCal;
    c["calicatasRoot"] = calRoot;

    // ---------------- Tipos de carpeta (UNA sola vez) ----------------
    const bool isProj = isDir && isProjectFolder(folderPath);
    const bool isCal  = isDir && isCalicatasFolder(folderPath);
    const bool isEdit = isDir && isEditableFolder(folderPath);
    const bool isXlsF = isDir && isExcelFolder(folderPath);
    const bool isPdfF = isDir && isPdfFolder(folderPath);

    // ---------------- Básicos (tu lógica actual) ----------------
    const bool selUnderRes = hasSelection && isUnderResourcesPath(p);
    const bool selIsResRoot = hasSelection && fi.isDir() && isResourcesRootFolder(p);
    const bool selProtected = selUnderRes && isProtectedResourcesFile(p);

    c["canNewFolder"] = hasSelection;
    c["canPaste"]     = hasSelection;

    const bool allowResRenameDelete = selUnderRes && !selIsResRoot && !selProtected;
    c["canRename"] = selUnderRes ? allowResRenameDelete : (hasSelection && !isResRoot);
    c["canDelete"] = selUnderRes ? allowResRenameDelete : (hasSelection && !isResRoot);

    c["canCut"]  = hasSelection && !selUnderRes && !isResRoot;
    c["canCopy"] = hasSelection && !isResRoot;

    // ---------------- Defaults especiales ----------------
    c["canDefineProject"] = false;
    c["canEditProject"]   = false;
    c["canRemoveProject"] = false;

    c["canDefineCalicatas"] = false;
    c["canRemoveCalicatas"] = false;

    c["canDefineEditable"] = false;
    c["canRemoveEditable"] = false;
    c["canEditEditableLogos"] = false;
    c["canEditEditableTitle"] = false; // 👈 para tu opción “editar título compartido”

    c["canDefineExcel"] = false;
    c["canRemoveExcel"] = false;

    c["canDefinePdf"] = false;
    c["canRemovePdf"] = false;

    // Debug opcional para QML
    c["isLevel2InProject"] = false;
    c["isLevel3InCalicatas"] = false;
    c["hasEditableInCalicatas"] = false;
    c["hasExcelInCalicatas"] = false;
    c["hasPdfInCalicatas"] = false;

    // ---------------- Nivel 1: Proyecto ----------------
    if (isDir) {
        c["canDefineProject"] = !isProj && canDefineProjectHere(folderPath);
        c["canEditProject"]   = isProj;
        c["canRemoveProject"] = isProj;
    }

    // ---------------- Nivel 2: Calicatas dentro del Proyecto ----------------
    bool isLevel2InProject = false;
    if (insideProj && isDir && !projRoot.isEmpty()) {
        const QString parentAbs = clean(QFileInfo(folderPath).dir().absolutePath());
        isLevel2InProject = (parentAbs == projRoot) && (clean(folderPath) != projRoot);
    }
    c["isLevel2InProject"] = isLevel2InProject;

    if (!underRes && insideProj && isDir) {
        // Definir Calicatas SOLO en nivel2 y si NO estás dentro de otra Calicatas
        c["canDefineCalicatas"] =
            isLevel2InProject && !insideCal && !isCal && canDefineCalicatasHere(folderPath);

        c["canRemoveCalicatas"] = isCal;
    }

    // ---------------- Nivel 3: Edit / EXCEL / PDF (únicos) dentro de Calicatas ----------------
    if (!underRes && insideCal && isDir && !calRoot.isEmpty()) {

        bool isLevel3InCal = false;
        {
            const QString parentAbs = clean(QFileInfo(folderPath).dir().absolutePath());
            isLevel3InCal = (parentAbs == calRoot) && (clean(folderPath) != calRoot);
        }
        c["isLevel3InCalicatas"] = isLevel3InCal;

        // Detectar si ya existen Edit/Excel/PDF en el root de Calicatas (hijos directos)
        bool hasEditable = false, hasExcel = false, hasPdf = false;
        const QFileInfoList kids = QDir(calRoot).entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot);
        for (const QFileInfo& kid : kids) {
            const QString k = clean(kid.absoluteFilePath());
            if (!hasEditable && isEditableFolder(k)) hasEditable = true;
            if (!hasExcel    && isExcelFolder(k))    hasExcel = true;
            if (!hasPdf      && isPdfFolder(k))      hasPdf = true;
        }
        c["hasEditableInCalicatas"] = hasEditable;
        c["hasExcelInCalicatas"] = hasExcel;
        c["hasPdfInCalicatas"] = hasPdf;

        // Si la carpeta seleccionada YA ES especial:
        if (isEdit) {
            c["canRemoveEditable"] = true;
            c["canEditEditableLogos"] = true;
            c["canEditEditableTitle"] = true;
        } else if (isXlsF) {
            c["canRemoveExcel"] = true;
        } else if (isPdfF) {
            c["canRemovePdf"] = true;
        }
        // Si es carpeta normal (en nivel3), permitir definir SOLO las que falten
        else if (isLevel3InCal) {
            c["canDefineEditable"] = !hasEditable;
            c["canDefineExcel"]    = !hasExcel;
            c["canDefinePdf"]      = !hasPdf;
        }
    }

    // Importar imágenes: solo en Recursos y carpeta
    c["canImportImagesToResources"] = (hasSelection && isDir && underRes);

    // Archivos
    c["isExcelFile"] = hasSelection && fi.isFile() && isExcelFile(p);
    c["isPdfFile"]   = hasSelection && fi.isFile() && isPdfFile(p);

    c["isCalicataFile"] = hasSelection && fi.isFile() && p.endsWith(".calicata.json", Qt::CaseInsensitive);
    c["canOpenCalicata"] = c["isCalicataFile"];

    return c;
}




// ---------------- Clipboard ops ----------------
void DocsController::copyToClipboard(const QString& absPath)
{
    m_clipboardPath = clean(absPath);
    m_cutOperation = false;
    emit clipboardChanged();
}

QVariantMap DocsController::cutToClipboard(const QString& absPath)
{
    QVariantMap r;
    const QString p = clean(absPath);
    if (p.isEmpty() || !QFileInfo::exists(p)) {
        r["ok"] = false; r["err"] = "Ruta inválida";
        return r;
    }
    if (isUnderResourcesPath(p)) {
        r["ok"] = false;
        r["err"] = "No se puede mover contenido dentro de Recursos.";
        return r;
    }
    m_clipboardPath = p;
    m_cutOperation = true;
    emit clipboardChanged();
    r["ok"] = true;
    return r;
}

QVariantMap DocsController::pasteInto(const QString& targetDirAbs)
{
    QVariantMap r;

    if (m_clipboardPath.isEmpty()) { r["ok"]=false; r["err"]="Clipboard vacío"; return r; }

    const QString targetDir = clean(targetDirAbs);
    if (targetDir.isEmpty() || !QFileInfo(targetDir).isDir()) {
        r["ok"]=false; r["err"]="targetDir no es carpeta"; return r;
    }

    const bool targetUnderRes = isUnderResourcesPath(targetDir);

    QFileInfo srcInfo(m_clipboardPath);
    if (!srcInfo.exists()) { r["ok"]=false; r["err"]="Origen no existe"; return r; }

    if (targetUnderRes) {
        if (m_cutOperation || srcInfo.isDir() || !isImageFile(m_clipboardPath)) {
            r["ok"]=false;
            r["err"]="En Recursos solo se permite pegar imágenes (copiar, no cortar).";
            return r;
        }
        if (srcInfo.fileName().compare(QString::fromUtf8(kResourcesMetaFile), Qt::CaseInsensitive) == 0) {
            r["ok"]=false; r["err"]="No se puede pegar el meta de Recursos."; return r;
        }
    }

    if (srcInfo.isDir()) {
        if (dirContainsMetaRecursively(srcInfo.absoluteFilePath(), kResourcesMetaFile)) {
            r["ok"]=false;
            r["err"]="No puedes copiar/pegar una carpeta que contiene Recursos.";
            return r;
        }
    } else {
        if (srcInfo.fileName().compare(QString::fromUtf8(kResourcesMetaFile), Qt::CaseInsensitive) == 0) {
            r["ok"]=false;
            r["err"]="No puedes copiar/pegar el meta de Recursos.";
            return r;
        }
    }

    QString destProjRoot;
    const bool destInsideProject = isInsideProject(targetDir, &destProjRoot);
    if (destInsideProject && srcInfo.isDir()) {
        if (dirContainsProjectMetaRecursively(srcInfo.absoluteFilePath())) {
            r["ok"]=false;
            r["err"]="No puedes pegar un proyecto dentro de otro proyecto.";
            return r;
        }
    }

    if (srcInfo.isDir()) {
        const QString td = clean(targetDir);
        const QString sd = clean(srcInfo.absoluteFilePath());
        if (td == sd || isUnderPath(td, sd)) {
            r["ok"]=false;
            r["err"]="No puedes copiar una carpeta dentro de sí misma.";
            return r;
        }
    }

    const QString baseName = srcInfo.fileName();
    const QString destName = uniqueNameForPaste(targetDir, baseName);
    const QString destPath = QDir(targetDir).absoluteFilePath(destName);

    bool ok = false;
    if (srcInfo.isDir()) ok = copyDirRecursively(srcInfo.absoluteFilePath(), destPath);
    else ok = QFile::copy(srcInfo.absoluteFilePath(), destPath);

    if (!ok) { r["ok"]=false; r["err"]="No se pudo copiar el elemento."; return r; }

    if (m_cutOperation) {
        bool rmOk = false;
        if (srcInfo.isDir()) {
            makeTreeWritable(srcInfo.absoluteFilePath());
            rmOk = QDir(srcInfo.absoluteFilePath()).removeRecursively();
        } else {
            makeWritableOne(srcInfo.absoluteFilePath());
            rmOk = QFile::remove(srcInfo.absoluteFilePath());
        }
        if (!rmOk) {
            // no abortamos el paste, pero avisamos
            r["warn"] = "Pegado OK pero no pude borrar el origen (cut).";
        }
        m_cutOperation = false;
        m_clipboardPath.clear();
        emit clipboardChanged();
    }

    r["ok"]=true;
    r["destPath"]=clean(destPath);
    return r;
}

// ---------------- File ops ----------------
QVariantMap DocsController::newFolder(const QString& parentDirAbs, const QString& baseName)
{
    QVariantMap r;
    const QString parent = clean(parentDirAbs);
    if (!QFileInfo(parent).isDir()) { r["ok"]=false; r["err"]="parent no es dir"; return r; }

    if (isUnderResourcesPath(parent)) { r["ok"]=false; r["err"]="No se pueden crear carpetas dentro de Recursos."; return r; }

    QDir dir(parent);
    QString finalName = baseName.trimmed().isEmpty() ? "Nueva carpeta" : baseName.trimmed();
    int num = 1;
    while (dir.exists(finalName)) finalName = QString("%1 (%2)").arg(baseName).arg(num++);

    if (!dir.mkdir(finalName)) { r["ok"]=false; r["err"]="mkdir falló"; return r; }

    r["ok"]=true;
    r["path"]=clean(dir.absoluteFilePath(finalName));
    return r;
}

QVariantMap DocsController::removePaths(const QStringList& absPaths)
{
    QVariantMap r;
    if (absPaths.isEmpty()) { r["ok"]=false; r["err"]="Lista vacía"; return r; }

    bool someError = false;
    QString firstErr;

    for (const QString& p0 : absPaths) {
        const QString p = clean(p0);
        QFileInfo fi(p);
        if (!fi.exists()) continue;

        const bool underRes = isUnderResourcesPath(p);
        if (underRes) {
            if (!(fi.isFile() && isImageFile(p) && !isProtectedResourcesFile(p))) {
                r["ok"]=false;
                r["err"]="No se puede eliminar carpetas o archivos protegidos dentro de Recursos.";
                return r;
            }
        }

        bool ok = false;
        if (fi.isDir()) {
            makeTreeWritable(p);
            ok = QDir(p).removeRecursively();
            if (!ok) ok = QDir(p).removeRecursively(); // reintento
        } else {
            makeWritableOne(p);
            ok = QFile::remove(p);
            if (!ok) ok = QFile::remove(p); // reintento
        }

        if (!ok) {
            someError = true;
            if (firstErr.isEmpty())
                firstErr = QString("No se pudo eliminar: %1").arg(p);
        }
    }

    r["ok"]=!someError;
    r["err"]= someError ? (firstErr.isEmpty() ? "No se pudo eliminar algún elemento." : firstErr) : "";
    return r;
}

QVariantMap DocsController::renamePath(const QString& absPath, const QString& newName)
{
    QVariantMap r;
    const QString oldPath = clean(absPath);
    QFileInfo oldInfo(oldPath);
    if (!oldInfo.exists()) { r["ok"]=false; r["err"]="No existe"; return r; }

    const bool underRes = isUnderResourcesPath(oldPath);
    if (underRes) {
        if (!(oldInfo.isFile() && isImageFile(oldPath) && !isProtectedResourcesFile(oldPath))) {
            r["ok"]=false;
            r["err"]="En Recursos solo puedes renombrar imágenes no protegidas.";
            return r;
        }
    }

    QString nn = newName.trimmed();
    if (nn.isEmpty()) { r["ok"]=false; r["err"]="Nombre vacío"; return r; }
    if (nn.contains('/') || nn.contains('\\')) { r["ok"]=false; r["err"]="Nombre inválido"; return r; }

    const QString newPath = oldInfo.dir().absoluteFilePath(nn);
    if (QFileInfo::exists(newPath)) { r["ok"]=false; r["err"]="Ya existe"; return r; }

    bool ok = false;
    if (oldInfo.isDir()) {
        QDir parent(oldInfo.dir().absolutePath());
        ok = parent.rename(oldInfo.fileName(), nn);
    } else {
        makeWritableOne(oldPath);
        ok = QFile::rename(oldPath, newPath);
    }

    r["ok"]=ok;
    r["path"]= clean(newPath);
    r["err"]= ok ? "" : "No se pudo renombrar.";
    return r;
}

// ---------------- Define / Remove metas ----------------
QVariantMap DocsController::defineProject(const QString& folderAbs,
                                          const QString& projectName,
                                          const QString& clientName)
{
    QVariantMap r;
    const QString f = clean(folderAbs);
    if (!QFileInfo(f).isDir()) { r["ok"]=false; r["err"]="No es carpeta"; return r; }
    if (!canDefineProjectHere(f)) { r["ok"]=false; r["err"]="No puedes definir un proyecto dentro de otro proyecto."; return r; }

    QVariantMap m;
    m["type"]="project";
    m["version"]=1;
    m["project"]=projectName.trimmed().isEmpty() ? QFileInfo(f).fileName() : projectName.trimmed();
    m["client"]=clientName.trimmed();

    r["ok"] = writeJsonMeta(f, kProjectMetaFile, m);
    r["err"] = r["ok"].toBool() ? "" : "No se pudo guardar meta de proyecto.";
    return r;
}

QVariantMap DocsController::removeProject(const QString& folderAbs)
{
    QVariantMap r;
    const QString f = clean(folderAbs);
    if (!isProjectFolder(f)) { r["ok"]=true; return r; }
    r["ok"]=removeMeta(f, kProjectMetaFile);
    r["err"]=r["ok"].toBool() ? "" : "No se pudo quitar meta de proyecto.";
    return r;
}

QVariantMap DocsController::defineEditable(const QString& folderAbs, bool allowReplaceExisting)
{
    QVariantMap r;
    const QString f = clean(folderAbs);
    if (!QFileInfo(f).isDir()) { r["ok"]=false; r["err"]="No es carpeta"; return r; }

    QString projectRoot;
    if (!isInsideProject(f, &projectRoot) || clean(f) == clean(projectRoot)) {
        r["ok"]=false;
        r["err"]="Editable debe estar dentro de un proyecto y no puede ser el root del proyecto.";
        return r;
    }

    if (allowReplaceExisting) {
        const QString existing = findEditableFolderInProject(projectRoot);
        if (!existing.isEmpty() && clean(existing) != clean(f)) {
            removeMeta(existing, kEditableMetaFile);
        }
    }

    QVariantMap m;
    m["type"]="editable";
    m["version"]=1;
    m["photos_dir"]=QString::fromUtf8(kEditablePhotosFolder);
    m["shared_logo_mtc_path"]="";
    m["shared_logo_proyecto_path"]="";

    if (!writeJsonMeta(f, kEditableMetaFile, m) || !ensureEditablePhotosDir(f)) {
        r["ok"]=false; r["err"]="No se pudo configurar editable o crear 'fotos'.";
        return r;
    }

    r["ok"]=true;
    return r;
}

QVariantMap DocsController::removeEditable(const QString& folderAbs)
{
    QVariantMap r;
    const QString f = clean(folderAbs);
    if (!isEditableFolder(f)) { r["ok"]=true; return r; }
    r["ok"]=removeMeta(f, kEditableMetaFile);
    r["err"]=r["ok"].toBool() ? "" : "No se pudo quitar meta editable.";
    return r;
}

QVariantMap DocsController::defineCalicatas(const QString& folderAbs)
{
    QVariantMap r;
    const QString f = clean(folderAbs);
    if (!QFileInfo(f).isDir()) { r["ok"]=false; r["err"]="No es carpeta"; return r; }
    if (!canDefineCalicatasHere(f)) {
        r["ok"]=false;
        r["err"]="Calicatas debe estar dentro de un proyecto, ser hija directa y ser única por proyecto.";
        return r;
    }

    QVariantMap m;
    m["type"]="calicatas";
    m["version"]=1;

    if (!writeJsonMeta(f, kCalicatasMetaFile, m) || !ensureCalicatasStructure(f)) {
        r["ok"]=false; r["err"]="No se pudo definir Calicatas o crear estructura (Edit/EXCEL/PDF).";
        return r;
    }
    r["ok"]=true;
    return r;
}

QVariantMap DocsController::removeCalicatas(const QString& folderAbs)
{
    QVariantMap r;
    const QString f = clean(folderAbs);
    if (!isCalicatasFolder(f)) { r["ok"]=true; return r; }
    r["ok"]=removeMeta(f, kCalicatasMetaFile);
    r["err"]=r["ok"].toBool() ? "" : "No se pudo quitar meta Calicatas.";
    return r;
}

QVariantMap DocsController::defineExcel(const QString& folderAbs)
{
    QVariantMap r;
    const QString f = clean(folderAbs);
    if (!QFileInfo(f).isDir()) { r["ok"]=false; r["err"]="No es carpeta"; return r; }
    if (!canDefineExcelHere(f)) { r["ok"]=false; r["err"]="EXCEL debe ser hijo directo de Calicatas y único."; return r; }

    QVariantMap m;
    m["type"]="excel";
    m["version"]=1;
    r["ok"]=writeJsonMeta(f, kExcelMetaFile, m);
    r["err"]=r["ok"].toBool() ? "" : "No se pudo definir meta EXCEL.";
    return r;
}

QVariantMap DocsController::removeExcel(const QString& folderAbs)
{
    QVariantMap r;
    const QString f = clean(folderAbs);
    if (!isExcelFolder(f)) { r["ok"]=true; return r; }
    r["ok"]=removeMeta(f, kExcelMetaFile);
    r["err"]=r["ok"].toBool() ? "" : "No se pudo quitar meta EXCEL.";
    return r;
}

QVariantMap DocsController::definePdf(const QString& folderAbs)
{
    QVariantMap r;
    const QString f = clean(folderAbs);
    if (!QFileInfo(f).isDir()) { r["ok"]=false; r["err"]="No es carpeta"; return r; }
    if (!canDefinePdfHere(f)) { r["ok"]=false; r["err"]="PDF debe ser hijo directo de Calicatas y único."; return r; }

    QVariantMap m;
    m["type"]="pdf";
    m["version"]=1;
    r["ok"]=writeJsonMeta(f, kPdfMetaFile, m);
    r["err"]=r["ok"].toBool() ? "" : "No se pudo definir meta PDF.";
    return r;
}

QVariantMap DocsController::removePdf(const QString& folderAbs)
{
    QVariantMap r;
    const QString f = clean(folderAbs);
    if (!isPdfFolder(f)) { r["ok"]=true; return r; }
    r["ok"]=removeMeta(f, kPdfMetaFile);
    r["err"]=r["ok"].toBool() ? "" : "No se pudo quitar meta PDF.";
    return r;
}

// ---------------- Recursos: import ----------------
QVariantMap DocsController::importImagesToResources(const QStringList& absFiles)
{
    QVariantMap r;

    ensureResourcesFolder();
    const QString res = QDir(m_basePath).absoluteFilePath(kResourcesFolderName);
    if (!QFileInfo(res).isDir()) { r["ok"]=false; r["err"]="No existe Recursos"; return r; }

    int copied=0, skipped=0;
    QDir dst(res);

    for (const QString& src0 : absFiles) {
        const QString src = clean(src0);
        QFileInfo sfi(src);
        if (!sfi.exists() || !sfi.isFile()) { skipped++; continue; }
        const QString ext = sfi.suffix().toLower();
        if (ext!="png" && ext!="jpg" && ext!="jpeg") { skipped++; continue; }

        QString baseName = sfi.completeBaseName();
        QString dstName = sfi.fileName();
        QString dstAbs = dst.absoluteFilePath(dstName);

        int n=1;
        while (QFileInfo::exists(dstAbs)) {
            dstName = QString("%1_%2.%3").arg(baseName).arg(n++).arg(ext);
            dstAbs = dst.absoluteFilePath(dstName);
        }

        if (QFile::copy(src, dstAbs)) copied++;
        else skipped++;
    }

    r["ok"]=true;
    r["copied"]=copied;
    r["skipped"]=skipped;
    return r;
}

// ---------------- Editable: resolve folder ----------------
QString DocsController::resolveEditableFolderFromAnyPath(const QString& anyAbsPath) const
{
    QString p = clean(anyAbsPath);
    if (p.isEmpty()) return {};

    QFileInfo fi(p);
    QString dirPath = fi.isDir() ? fi.absoluteFilePath() : fi.dir().absolutePath();
    QDir d(dirPath);

    const QString base = clean(m_basePath);
    while (true) {
        const QString meta = d.absoluteFilePath(kEditableMetaFile);
        if (QFileInfo::exists(meta)) return clean(d.absolutePath());

        const QString cur = clean(d.absolutePath());
        if (!base.isEmpty() && cur == base) break;
        if (!d.cdUp()) break;
    }
    return {};
}

int DocsController::countCalicataFilesToPatch(const QString& editableFolderAbs) const
{
    const QString edit = clean(editableFolderAbs);
    const QString fotosAbs = clean(QDir(edit).absoluteFilePath(kEditablePhotosFolder));
    const QString fotosPrefix = ensureSlash(fotosAbs);

    int total = 0;
    QDirIterator it(edit,
                    QStringList() << "*.calicata.json" << "*.cal",
                    QDir::Files,
                    QDirIterator::Subdirectories);

    while (it.hasNext()) {
        const QString fp = clean(it.next());
        if (normPathLower(fp).startsWith(normPathLower(fotosPrefix)))
            continue;
        total++;
    }
    return total;
}

// ---------------- Editable: logos ----------------
bool DocsController::readEditableSharedLogos(const QString& editableFolderAbs,
                                             QString& outMtcRel,
                                             QString& outProyectoRel) const
{
    outMtcRel.clear();
    outProyectoRel.clear();

    const QString metaPath = QDir(editableFolderAbs).absoluteFilePath(kEditableMetaFile);
    QFile f(metaPath);
    if (!f.open(QIODevice::ReadOnly)) return false;

    QJsonParseError pe{};
    const QJsonDocument jd = QJsonDocument::fromJson(f.readAll(), &pe);
    if (pe.error != QJsonParseError::NoError || !jd.isObject()) return false;

    const QJsonObject o = jd.object();
    outMtcRel      = o.value("shared_logo_mtc_path").toString().trimmed();
    outProyectoRel = o.value("shared_logo_proyecto_path").toString().trimmed();
    return true;
}

bool DocsController::writeEditableSharedLogos(const QString& editableFolderAbs,
                                              const QString& mtcRel,
                                              const QString& proyectoRel) const
{
    const QString metaPath = QDir(editableFolderAbs).absoluteFilePath(kEditableMetaFile);

    QJsonObject o;
    {
        QFile rf(metaPath);
        if (rf.open(QIODevice::ReadOnly)) {
            QJsonParseError pe{};
            const QJsonDocument jd = QJsonDocument::fromJson(rf.readAll(), &pe);
            if (pe.error == QJsonParseError::NoError && jd.isObject())
                o = jd.object();
        }
    }

    if (!o.contains("version"))    o["version"] = 1;
    if (!o.contains("type"))       o["type"] = "editable";
    if (!o.contains("photos_dir")) o["photos_dir"] = QString::fromUtf8(kEditablePhotosFolder);

    auto norm = [](QString s){
        s = s.trimmed();
        return s.isEmpty() ? QString() : QDir::cleanPath(QDir::fromNativeSeparators(s));
    };

    o["shared_logo_mtc_path"]      = norm(mtcRel);
    o["shared_logo_proyecto_path"] = norm(proyectoRel);

    QSaveFile sf(metaPath);
    if (!sf.open(QIODevice::WriteOnly | QIODevice::Truncate)) return false;
    sf.write(QJsonDocument(o).toJson(QJsonDocument::Indented));
    return sf.commit();
}

bool DocsController::patchCalicataFileLogosOnDisk(const QString& filePath,
                                                  const QString& mtcRel,
                                                  const QString& proyectoRel,
                                                  QString* err)
{
    QFile f(filePath);
    if (!f.open(QIODevice::ReadOnly)) {
        if (err) *err = "No pude abrir para lectura: " + f.errorString();
        return false;
    }

    QJsonParseError pe{};
    QJsonDocument jd = QJsonDocument::fromJson(f.readAll(), &pe);
    f.close();

    if (pe.error != QJsonParseError::NoError || !jd.isObject()) {
        if (err) *err = "JSON inválido: " + pe.errorString();
        return false;
    }

    QJsonObject root = jd.object();
    QJsonObject imgs = root.value("images").toObject();

    auto cleanRel = [](QString s){
        s = s.trimmed();
        return s.isEmpty() ? QString() : QDir::cleanPath(QDir::fromNativeSeparators(s));
    };

    const QString mtc = cleanRel(mtcRel);
    const QString pro = cleanRel(proyectoRel);

    if (!mtc.isEmpty()) {
        imgs["logo_mtc_custom"] = true;
        imgs["logo_mtc_path"]   = mtc;
        imgs["logo_mtc"]        = QString();
    } else {
        imgs["logo_mtc_custom"] = false;
        imgs["logo_mtc_path"]   = QString();
        imgs["logo_mtc"]        = QString();
    }

    if (!pro.isEmpty()) {
        imgs["logo_proyecto_custom"] = true;
        imgs["logo_proyecto_path"]   = pro;
        imgs["logo_proyecto"]        = QString();
    } else {
        imgs["logo_proyecto_custom"] = false;
        imgs["logo_proyecto_path"]   = QString();
        imgs["logo_proyecto"]        = QString();
    }

    root["images"] = imgs;

    QSaveFile sf(filePath);
    if (!sf.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        if (err) *err = "No pude abrir para escritura: " + sf.errorString();
        return false;
    }
    sf.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    if (!sf.commit()) {
        if (err) *err = "No pude guardar cambios (commit falló).";
        return false;
    }
    return true;
}

void DocsController::applyEditableLogosToAllCalicataFiles(const QString& editableFolderAbs,
                                                          const QString& mtcRel,
                                                          const QString& proyectoRel,
                                                          int* outUpdated,
                                                          int* outFailed,
                                                          QStringList* outErrors) const
{
    if (outUpdated) *outUpdated = 0;
    if (outFailed)  *outFailed  = 0;
    if (outErrors)  outErrors->clear();

    const QString fotosAbs = clean(QDir(editableFolderAbs).absoluteFilePath(kEditablePhotosFolder));
    const QString fotosPrefix = ensureSlash(fotosAbs);
    const QString fotosPrefixLower = normPathLower(fotosPrefix);

    QDirIterator it(editableFolderAbs,
                    QStringList() << "*.calicata.json" << "*.cal",
                    QDir::Files,
                    QDirIterator::Subdirectories);

    while (it.hasNext()) {
        const QString fp = clean(it.next());
        if (normPathLower(fp).startsWith(fotosPrefixLower))
            continue;

        QString e;
        if (!patchCalicataFileLogosOnDisk(fp, mtcRel, proyectoRel, &e)) {
            if (outFailed) (*outFailed)++;
            if (outErrors) outErrors->push_back(fp + "\n" + e);
        } else {
            if (outUpdated) (*outUpdated)++;
        }
    }
}

QVariantMap DocsController::getEditableSharedLogos(const QString& editableFolderAbs) const
{
    QVariantMap r;
    const QString f = clean(editableFolderAbs);
    if (!isEditableFolder(f)) { r["ok"]=false; r["err"]="No es editable"; return r; }

    QString mtc, pro;
    readEditableSharedLogos(f, mtc, pro);
    r["ok"]=true;
    r["mtcRel"]=mtc;
    r["proRel"]=pro;
    return r;
}

QVariantMap DocsController::setEditableSharedLogos(const QString& editableFolderAbs,
                                                   const QString& mtcRel,
                                                   const QString& proyectoRel,
                                                   bool applyToAllFiles)
{
    QVariantMap r;
    const QString f = clean(editableFolderAbs);
    if (!isEditableFolder(f)) { r["ok"]=false; r["err"]="No es editable"; return r; }

    if (!writeEditableSharedLogos(f, mtcRel, proyectoRel)) {
        r["ok"]=false; r["err"]="No pude guardar logos en meta editable.";
        return r;
    }

    int updated=0, failed=0;
    QStringList errs;
    if (applyToAllFiles) {
        applyEditableLogosToAllCalicataFiles(f, mtcRel, proyectoRel, &updated, &failed, &errs);
    }

    r["ok"]=true;
    r["updated"]=updated;
    r["failed"]=failed;
    r["firstError"]=errs.isEmpty() ? "" : errs.first();

    emit editableSharedLogosChanged(f, mtcRel, proyectoRel);
    return r;
}

// ---------------- fileKind ----------------
QString DocsController::fileKind(const QString& absPath) const
{
    const QString p = clean(absPath);
    QFileInfo fi(p);
    if (!fi.exists()) return "missing";
    if (fi.isDir()) return "dir";
    const QString ext = fi.suffix().toLower();
    if (ext=="png" || ext=="jpg" || ext=="jpeg") return "image";
    if (ext=="pdf") return "pdf";
    if (ext=="xlsx" || ext=="xlsm" || ext=="xls") return "excel";
    if (p.endsWith(".calicata.json", Qt::CaseInsensitive) || ext=="cal") return "calicata";
    return "other";
}

QStringList DocsController::listFilesRecursively(const QString& rootAbs) const
{
    QStringList out;
    const QString root = clean(rootAbs);
    if (root.isEmpty() || !QFileInfo(root).exists())
        return out;

    QFileInfo fi(root);
    if (fi.isFile()) {
        out << clean(fi.absoluteFilePath());
        return out;
    }

    QDirIterator it(root,
                    QDir::Files | QDir::Hidden | QDir::NoDotAndDotDot,
                    QDirIterator::Subdirectories);

    while (it.hasNext()) {
        const QString fp = clean(it.next());
        const QString name = QFileInfo(fp).fileName();
        if (name == ".DS_Store" || name.toLower() == ".thumbs")
            continue;
        out << fp;
    }

    return out;
}

QString DocsController::relativePath(const QString& absPath, const QString& baseAbs) const
{
    const QString abs = clean(absPath);
    const QString base = clean(baseAbs);
    if (abs.isEmpty() || base.isEmpty())
        return QFileInfo(abs).fileName();

    return QDir(base).relativeFilePath(abs);
}


void DocsController::requestEditableLogosDialogData(const QString& anyAbsPath, int token)
{
    const QString any = clean(anyAbsPath);
    QPointer<DocsController> self(this);

    QtConcurrent::run([self, any, token]() {
        if (!self) return;

        const QString editable = self->resolveEditableFolderFromAnyPath(any);
        if (editable.isEmpty() || !self->isEditableFolder(editable)) {
            QMetaObject::invokeMethod(self, [self, token, editable]() {
                if (!self) return;
                emit self->editableLogosDialogDataReady(token, false, editable, "", "", 0,
                                                        "No se pudo resolver la carpeta Editable.");
            }, Qt::QueuedConnection);
            return;
        }

        QString mtc, pro;
        const bool okRead = self->readEditableSharedLogos(editable, mtc, pro);
        const int n = self->countCalicataFilesToPatch(editable);

        QMetaObject::invokeMethod(self, [self, token, editable, okRead, mtc, pro, n]() {
            if (!self) return;
            emit self->editableLogosDialogDataReady(
                token, true, editable,
                okRead ? mtc : QString(),
                okRead ? pro : QString(),
                n,
                okRead ? "" : "Meta editable leída con advertencia."
                );
        }, Qt::QueuedConnection);
    });
}

void DocsController::setEditableSharedLogosAsync(const QString& editableFolderAbs,
                                                 const QString& mtcRel,
                                                 const QString& proyectoRel,
                                                 bool applyToAllFiles,
                                                 int token)
{
    const QString f = clean(editableFolderAbs);
    QPointer<DocsController> self(this);

    QtConcurrent::run([self, f, mtcRel, proyectoRel, applyToAllFiles, token]() {
        if (!self) return;

        if (!self->isEditableFolder(f)) {
            QMetaObject::invokeMethod(self, [self, token]() {
                if (!self) return;
                emit self->editableSharedLogosApplied(token, false, 0, 0, "",
                                                      "No es carpeta editable.");
            }, Qt::QueuedConnection);
            return;
        }

        if (!self->writeEditableSharedLogos(f, mtcRel, proyectoRel)) {
            QMetaObject::invokeMethod(self, [self, token]() {
                if (!self) return;
                emit self->editableSharedLogosApplied(token, false, 0, 0, "",
                                                      "No pude guardar logos en meta editable.");
            }, Qt::QueuedConnection);
            return;
        }

        int updated = 0, failed = 0;
        QStringList errs;

        if (applyToAllFiles) {
            self->applyEditableLogosToAllCalicataFiles(f, mtcRel, proyectoRel,
                                                       &updated, &failed, &errs);
        }

        const QString firstErr = errs.isEmpty() ? "" : errs.first();

        QMetaObject::invokeMethod(self, [self, f, mtcRel, proyectoRel, token, updated, failed, firstErr]() {
            if (!self) return;
            emit self->editableSharedLogosChanged(f, mtcRel, proyectoRel); // tu señal existente
            emit self->editableSharedLogosApplied(token, true, updated, failed, firstErr, "");
        }, Qt::QueuedConnection);
    });
}

bool DocsController::readEditableTitle(const QString& editableFolderAbs,
                                       QString& outTitle) const
{
    outTitle.clear();

    const QString folder = clean(editableFolderAbs);
    const QString metaPath = QDir(folder).absoluteFilePath(kEditableMetaFile);

    QFile f(metaPath);
    if (!f.open(QIODevice::ReadOnly))
        return false;

    QJsonParseError pe{};
    const QJsonDocument jd = QJsonDocument::fromJson(f.readAll(), &pe);
    if (pe.error != QJsonParseError::NoError || !jd.isObject())
        return false;

    const QJsonObject o = jd.object();

    // ✅ Key elegida (ajusta si en PC usaste otra)
    outTitle = o.value("excel_title").toString().trimmed();
    return true;
}

bool DocsController::writeEditableTitle(const QString& editableFolderAbs,
                                        const QString& title) const
{
    const QString folder = clean(editableFolderAbs);
    const QString metaPath = QDir(folder).absoluteFilePath(kEditableMetaFile);

    // leer meta existente si se puede
    QJsonObject o;
    {
        QFile rf(metaPath);
        if (rf.open(QIODevice::ReadOnly)) {
            QJsonParseError pe{};
            const QJsonDocument jd = QJsonDocument::fromJson(rf.readAll(), &pe);
            if (pe.error == QJsonParseError::NoError && jd.isObject())
                o = jd.object();
        }
    }

    // asegurar campos mínimos
    if (!o.contains("version"))    o["version"] = 1;
    if (!o.contains("type"))       o["type"] = "editable";
    if (!o.contains("photos_dir")) o["photos_dir"] = QString::fromUtf8(kEditablePhotosFolder);

    // ✅ Key elegida (ajusta si en PC usaste otra)
    o["excel_title"] = title.trimmed();

    QSaveFile sf(metaPath);
    if (!sf.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;

    sf.write(QJsonDocument(o).toJson(QJsonDocument::Indented));
    return sf.commit();
}

QString DocsController::getEditableTitle(const QString& editableFolder)
{
    // Acepta carpeta o archivo dentro del editable
    QString folder = resolveEditableFolderFromAnyPath(editableFolder);

    // fallback: si ya te pasan directo la carpeta editable
    if (folder.isEmpty()) {
        const QString f = clean(editableFolder);
        if (QFileInfo(f).isDir() && isEditableFolder(f))
            folder = f;
    }

    if (folder.isEmpty() || !isEditableFolder(folder))
        return QString();

    QString t;
    if (!readEditableTitle(folder, t))
        return QString();

    return t;
}

bool DocsController::setEditableTitle(const QString& editableFolder,
                                      const QString& title)
{
    QString folder = resolveEditableFolderFromAnyPath(editableFolder);

    if (folder.isEmpty()) {
        const QString f = clean(editableFolder);
        if (QFileInfo(f).isDir() && isEditableFolder(f))
            folder = f;
    }

    if (folder.isEmpty() || !isEditableFolder(folder))
        return false;

    return writeEditableTitle(folder, title.trimmed());
}

bool DocsController::isLevel1Folder(const QString& folderAbs) const
{
    const QString f = clean(folderAbs);
    const QString base = clean(m_basePath);
    if (f.isEmpty() || base.isEmpty()) return false;

    const QString parent = clean(QFileInfo(f).dir().absolutePath());
    return parent == base;
}

bool DocsController::isResourcesRootFolder(const QString& folderAbs) const
{
    const QString f = clean(folderAbs);
    if (f.isEmpty()) return false;

    // 1) usa el LOCK si existe (tu diseño actual)
    if (isLockedResourcesRoot(f)) return true;

    // 2) fallback: base/Recursos
    const QString base = clean(m_basePath);
    if (base.isEmpty()) return false;

    const QString expect = clean(QDir(base).absoluteFilePath(kResourcesFolderName));
    return !expect.isEmpty() && (clean(expect) == f);
}


QVariantMap DocsController::getProjectInfo(const QString& projectFolderAbs) const
{
    QVariantMap r;
    const QString f = clean(projectFolderAbs);

    if (!QFileInfo(f).isDir()) { r["ok"]=false; r["err"]="No es carpeta"; return r; }

    const QString metaPath = QDir(f).absoluteFilePath(kProjectMetaFile);
    QFile file(metaPath);
    if (!file.open(QIODevice::ReadOnly)) {
        r["ok"]=false; r["err"]="No pude leer meta de proyecto";
        return r;
    }

    QJsonParseError pe{};
    const QJsonDocument jd = QJsonDocument::fromJson(file.readAll(), &pe);
    if (pe.error != QJsonParseError::NoError || !jd.isObject()) {
        r["ok"]=false; r["err"]="JSON inválido";
        return r;
    }

    const QJsonObject o = jd.object();
    r["ok"]=true;
    r["projectName"]=o.value("project").toString();
    r["clientName"]=o.value("client").toString();
    return r;
}

QVariantMap DocsController::scanSpecialMetasInTree(const QString& projRootAbs) const
{
    QVariantMap out;

    struct M { const char* meta; const char* key; };
    const M metas[] = {
                       { kEditableMetaFile,  "editable"  },
                       { kCalicatasMetaFile, "calicatas" },
                       { kExcelMetaFile,     "excel"     },
                       { kPdfMetaFile,       "pdf"       },
                       };

    for (const auto& m : metas) {
        int count = 0;
        QVariantList samples;

        QDirIterator it(projRootAbs, QStringList() << m.meta,
                        QDir::Files | QDir::Hidden,
                        QDirIterator::Subdirectories);

        while (it.hasNext()) {
            const QString fp = clean(it.next());
            count++;
            if (samples.size() < 5)
                samples.push_back(fp);
        }

        QVariantMap one;
        one["count"] = count;
        one["samples"] = samples;
        out[QString::fromUtf8(m.key)] = one;
    }

    return out;
}

QString DocsController::projectRemovalReport(const QString& folderAbs) const
{
    const QString f = clean(folderAbs);
    if (!isProjectFolder(f))
        return "La carpeta seleccionada no tiene propiedades de proyecto.";

    QStringList lines;
    lines << "Se quitará: .ingep_project.json";
    lines << "No se eliminarán archivos ni carpetas.";

    // aviso si hay metas dentro
    const bool hasCal = dirContainsMetaRecursively(f, kCalicatasMetaFile);
    const bool hasEd  = dirContainsMetaRecursively(f, kEditableMetaFile);
    if (hasCal || hasEd) {
        lines << "";
        lines << "Advertencia:";
        if (hasCal) lines << "• Hay carpetas Calicatas dentro (metas quedarán intactas).";
        if (hasEd)  lines << "• Hay carpetas Editable dentro (metas quedarán intactas).";
    }

    return lines.join("\n");
}


QVariantMap DocsController::clearSpecialMetasInTree(const QString& projRootAbs) const
{
    QVariantMap r;
    int removed = 0;
    QStringList errors;

    const char* metas[] = { kEditableMetaFile, kCalicatasMetaFile, kExcelMetaFile, kPdfMetaFile };

    for (const char* meta : metas) {
        QDirIterator it(projRootAbs, QStringList() << meta,
                        QDir::Files | QDir::Hidden,
                        QDirIterator::Subdirectories);

        while (it.hasNext()) {
            const QString fp = clean(it.next());
            makeWritableOne(fp);
            if (QFile::remove(fp)) removed++;
            else errors << ("No pude borrar: " + fp);
        }
    }

    r["removed"] = removed;
    r["errors"] = errors;
    r["ok"] = errors.isEmpty();
    return r;
}

QVariantMap DocsController::removeProjectWithCleanup(const QString& projectFolderAbs,
                                                     bool cleanupNestedSpecial)
{
    QVariantMap r;
    const QString f = clean(projectFolderAbs);
    if (!isProjectFolder(f)) { r["ok"]=true; return r; }

    if (cleanupNestedSpecial) {
        r["cleanup"] = clearSpecialMetasInTree(f);
    }

    r["ok"] = removeMeta(f, kProjectMetaFile);
    r["err"] = r["ok"].toBool() ? "" : "No se pudo quitar meta de proyecto.";
    return r;
}

QString DocsController::folderSpecialKind(const QString& absPath) const
{
    const QString p = clean(absPath);
    QFileInfo fi(p);
    if (!fi.exists()) return "missing";

    if (!fi.isDir())
        return fileKind(p); // image/pdf/excel/calicata/other

    if (isResourcesRootFolder(p)) return "resources_root";
    if (isUnderResourcesPath(p))  return "resources_dir";

    if (isProjectFolder(p))   return "project";
    if (isCalicatasFolder(p)) return "calicatas";
    if (isEditableFolder(p))  return "editable";
    if (isExcelFolder(p))     return "excel";
    if (isPdfFolder(p))       return "pdf";

    return "dir";
}

bool DocsController::isInsideCalicatas(const QString& anyAbs, QString* outCalRoot) const
{
    const QString meta = findMetaUp(anyAbs, kCalicatasMetaFile);
    if (meta.isEmpty()) return false;

    const QString root = clean(QFileInfo(meta).dir().absolutePath());
    if (outCalRoot) *outCalRoot = root;
    return true;
}

QVariantMap DocsController::removeCalicatasWithCleanup(const QString& folderAbs, bool cleanupNestedSpecial)
{
    QVariantMap r;
    const QString f = clean(folderAbs);
    if (!isCalicatasFolder(f)) { r["ok"] = true; return r; }

    QVariantMap cleanup;
    if (cleanupNestedSpecial) {
        // reutiliza tu helper existente (borra metas editable/calicatas/excel/pdf dentro del árbol)
        cleanup = clearSpecialMetasInTree(f);
    }

    // Por si cleanup=false o por si quedó algo:
    const bool ok = removeMeta(f, kCalicatasMetaFile);

    r["ok"] = ok;
    r["cleanup"] = cleanup;
    r["err"] = ok ? "" : "No se pudo quitar meta Calicatas.";
    return r;
}

QString DocsController::calicatasRemovalReport(const QString& folderAbs) const
{
    const QString f = clean(folderAbs);
    if (!isCalicatasFolder(f))
        return "La carpeta seleccionada no tiene propiedades de Calicatas.";

    QStringList lines;
    lines << "Se quitará la propiedad de Calicatas:";
    lines << "• .ingep_calicatas.json";
    lines << "";
    lines << "Además, para que todo quede como carpeta NORMAL, se quitarán metas internas (sin borrar contenido):";
    lines << "• .ingep_editable.json / .ingep_excel.json / .ingep_pdf.json (si existen)";
    lines << "";
    lines << "No se eliminarán carpetas ni archivos. Solo se quitan propiedades.";
    return lines.join("\n");
}

bool DocsController::containsCalicatasMeta(const QString& dirAbs) const
{
    const QString d = clean(dirAbs);
    if (!QFileInfo(d).isDir()) return false;
    return dirContainsMetaRecursively(d, kCalicatasMetaFile);
}

bool DocsController::containsProjectMeta(const QString& dirAbs) const
{
    const QString d = clean(dirAbs);
    if (!QFileInfo(d).isDir()) return false;
    return dirContainsProjectMetaRecursively(d);
}

QVariantMap DocsController::createCalicataFile(const QString& targetDirAbs,
                                               const QString& baseName,
                                               bool overwrite) const
{
    QVariantMap r;

    const QString dirAbs = clean(targetDirAbs);
    if (dirAbs.isEmpty() || !QFileInfo(dirAbs).isDir()) {
        r["ok"] = false;
        r["err"] = "targetDir no es carpeta";
        return r;
    }

    // Debe estar bajo el root del usuario
    const QString base = clean(m_basePath);
    if (base.isEmpty() || !isUnderPath(dirAbs, base)) {
        r["ok"] = false;
        r["err"] = "Destino fuera del root del usuario";
        return r;
    }

    // Nunca dentro de Recursos
    if (isUnderResourcesPath(dirAbs)) {
        r["ok"] = false;
        r["err"] = "No se pueden crear fichas dentro de Recursos";
        return r;
    }

    // Debe pertenecer a una carpeta Editable
    const QString editableRoot = resolveEditableFolderFromAnyPath(dirAbs);
    if (editableRoot.isEmpty() || !isEditableFolder(editableRoot)) {
        r["ok"] = false;
        r["err"] = "Las fichas solo se pueden crear dentro de una carpeta Editable";
        return r;
    }

    // Regla estricta: solo en la raíz de Editable, no en subcarpetas
    if (clean(dirAbs) != clean(editableRoot)) {
        r["ok"] = false;
        r["err"] = "Las fichas solo se pueden crear en la raíz de la carpeta Editable";
        return r;
    }

    // Nunca dentro de la carpeta fotos
    const QString fotosAbs = clean(QDir(editableRoot).absoluteFilePath(kEditablePhotosFolder));
    if (clean(dirAbs) == fotosAbs) {
        r["ok"] = false;
        r["err"] = "No se pueden crear fichas dentro de 'fotos'";
        return r;
    }

    QString fn = ensureCalicataExt(sanitizeFileName(baseName));
    if (fn.isEmpty()) {
        r["ok"] = false;
        r["err"] = "Nombre inválido";
        return r;
    }

    const QString abs = clean(QDir(dirAbs).absoluteFilePath(fn));

    if (QFileInfo::exists(abs) && !overwrite) {
        r["ok"] = false;
        r["err"] = "El archivo ya existe";
        r["path"] = abs;
        return r;
    }

    QJsonObject root;
    root["type"] = "calicata";
    root["version"] = 1;
    root["saved_at"] = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);

    QJsonObject images;
    images["logo_mtc_custom"] = false;
    images["logo_mtc_path"] = "";
    images["logo_proyecto_custom"] = false;
    images["logo_proyecto_path"] = "";
    root["images"] = images;

    root["data"] = QJsonObject();

    QSaveFile sf(abs);
    if (!sf.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        r["ok"] = false;
        r["err"] = "No pude crear archivo: " + sf.errorString();
        return r;
    }

    sf.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    if (!sf.commit()) {
        r["ok"] = false;
        r["err"] = "Commit falló al crear ficha";
        return r;
    }

    r["ok"] = true;
    r["path"] = abs;
    return r;
}

QVariantMap DocsController::validatePlacement(const QString& sourceAbsPath,
                                              const QString& targetDirAbs) const
{
    QVariantMap r;

    const QString src = clean(sourceAbsPath);
    const QString dst = clean(targetDirAbs);

    if (src.isEmpty() || !QFileInfo::exists(src)) {
        r["ok"] = false;
        r["err"] = "Origen inválido.";
        return r;
    }

    if (dst.isEmpty() || !QFileInfo(dst).isDir()) {
        r["ok"] = false;
        r["err"] = "Destino inválido.";
        return r;
    }

    auto isMetaOrInternal = [&](const QString& fp) -> bool {
        const QString fn = QFileInfo(fp).fileName();
        return fn.compare(QString::fromUtf8(kProjectMetaFile),   Qt::CaseInsensitive) == 0 ||
               fn.compare(QString::fromUtf8(kEditableMetaFile),  Qt::CaseInsensitive) == 0 ||
               fn.compare(QString::fromUtf8(kCalicatasMetaFile), Qt::CaseInsensitive) == 0 ||
               fn.compare(QString::fromUtf8(kExcelMetaFile),     Qt::CaseInsensitive) == 0 ||
               fn.compare(QString::fromUtf8(kPdfMetaFile),       Qt::CaseInsensitive) == 0 ||
               fn.compare(QString::fromUtf8(kResourcesMetaFile), Qt::CaseInsensitive) == 0 ||
               fn.compare(kResourcesLockFile, Qt::CaseInsensitive) == 0;
    };

    auto validateSingleFile = [&](const QString& fileAbs, const QString& destDir) -> QVariantMap {
        QVariantMap out;
        out["ok"] = true;
        out["err"] = "";

        if (isMetaOrInternal(fileAbs))
            return out;

        // PDF -> solo carpeta PDF
        if (isPdfFile(fileAbs)) {
            if (!isPdfFolder(destDir)) {
                out["ok"] = false;
                out["err"] = "Los archivos PDF solo pueden guardarse dentro de una carpeta con propiedad PDF.";
                return out;
            }
            return out;
        }

        // EXCEL -> solo carpeta EXCEL
        if (isExcelFile(fileAbs)) {
            if (!isExcelFolder(destDir)) {
                out["ok"] = false;
                out["err"] = "Los archivos Excel solo pueden guardarse dentro de una carpeta con propiedad EXCEL.";
                return out;
            }
            return out;
        }

        // OPCIONAL pero recomendado:
        // Calicata editable -> solo raíz de carpeta Editable
        if (isCalicataFile(fileAbs)) {
            if (!isEditableFolder(destDir)) {
                out["ok"] = false;
                out["err"] = "Los archivos .calicata.json solo pueden guardarse dentro de una carpeta Editable.";
                return out;
            }
            return out;
        }

        return out;
    };

    QFileInfo sfi(src);

    // ---------- Caso archivo ----------
    if (sfi.isFile()) {
        return validateSingleFile(src, dst);
    }

    // ---------- Caso carpeta ----------
    // Si copias una carpeta completa, validamos que NO contenga PDF/Excel regados
    // fuera de carpetas especiales correctas.
    QDirIterator it(src,
                    QDir::Files | QDir::Hidden,
                    QDirIterator::Subdirectories);

    while (it.hasNext()) {
        const QString fp = clean(it.next());
        if (isMetaOrInternal(fp))
            continue;

        QFileInfo ffi(fp);
        const QString parentDir = clean(ffi.dir().absolutePath());

        if (isPdfFile(fp) && !isPdfFolder(parentDir)) {
            r["ok"] = false;
            r["err"] = "La carpeta contiene un PDF fuera de una carpeta PDF: " + fp;
            return r;
        }

        if (isExcelFile(fp) && !isExcelFolder(parentDir)) {
            r["ok"] = false;
            r["err"] = "La carpeta contiene un archivo Excel fuera de una carpeta EXCEL: " + fp;
            return r;
        }

        // OPCIONAL pero recomendado:
        if (isCalicataFile(fp) && !isEditableFolder(parentDir)) {
            r["ok"] = false;
            r["err"] = "La carpeta contiene un .calicata.json fuera de una carpeta Editable: " + fp;
            return r;
        }
    }

    r["ok"] = true;
    r["err"] = "";
    return r;
}
