#include "editablemeta.h"

#include <QFile>
#include <QDir>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>

static QString ctxDir(const QString& ctx)
{
    const QString c = ctx.trimmed();
    if (c.isEmpty()) return {};
    QFileInfo fi(c);
    return fi.isDir() ? fi.absoluteFilePath() : fi.dir().absolutePath();
}

static QString metaPathForCtxRead(const QString& ctx)
{
    const QString dir = ctxDir(ctx);
    if (dir.isEmpty()) return {};

    const QString p1 = QDir(dir).filePath(".ingep_editable.json");
    if (QFileInfo::exists(p1)) return p1;

    const QString p2 = QDir(dir).filePath("ingep_editable.json"); // legacy por si existe
    if (QFileInfo::exists(p2)) return p2;

    // si no existe, igual devolvemos el canonical para crear
    return QDir(dir).filePath(".ingep_editable.json");
}

static QJsonObject readObj(const QString& ctx)
{
    QJsonObject obj;
    const QString path = metaPathForCtxRead(ctx);
    QFile f(path);
    if (f.open(QIODevice::ReadOnly)) {
        const auto jd = QJsonDocument::fromJson(f.readAll());
        if (jd.isObject()) obj = jd.object();
    }
    return obj;
}

static bool writeObj(const QString& ctx, QJsonObject obj)
{
    const QString dir = ctxDir(ctx);
    if (dir.isEmpty()) return false;

    // canonical: SIEMPRE con punto
    const QString path = QDir(dir).filePath(".ingep_editable.json");

    // mínimos
    if (!obj.contains("version"))    obj["version"] = 1;
    if (!obj.contains("type"))       obj["type"] = "editable";
    if (!obj.contains("photos_dir")) obj["photos_dir"] = "fotos";

    QFile out(path);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) return false;
    out.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    return true;
}

// ---------------- TITULO ----------------

QString loadExcelTitleFromEditableMeta(const QString& ctx)
{
    if (ctx.trimmed().isEmpty()) return {};
    return readObj(ctx).value("excel_title").toString();
}

bool saveExcelTitleToEditableMeta(const QString& ctx, const QString& title)
{
    if (ctx.trimmed().isEmpty()) return false;
    auto obj = readObj(ctx);
    obj["excel_title"] = title.trimmed();
    return writeObj(ctx, obj);
}

// ---------------- LOGO MTC ----------------

QString loadLogoMtcPathFromEditableMeta(const QString& ctx)
{
    if (ctx.trimmed().isEmpty()) return {};
    return readObj(ctx).value("logo_mtc_path").toString();
}

bool saveLogoMtcPathToEditableMeta(const QString& ctx, const QString& relPath)
{
    if (ctx.trimmed().isEmpty()) return false;

    auto obj = readObj(ctx);
    const QString p = QDir::cleanPath(QDir::fromNativeSeparators(relPath.trimmed()));

    obj["logo_mtc_custom"] = !p.isEmpty();
    obj["logo_mtc_path"]   = p;

    return writeObj(ctx, obj);
}

// ---------------- LOGO PROYECTO ----------------

QString loadLogoProyectoPathFromEditableMeta(const QString& ctx)
{
    if (ctx.trimmed().isEmpty()) return {};
    return readObj(ctx).value("logo_proyecto_path").toString();
}

bool saveLogoProyectoPathToEditableMeta(const QString& ctx, const QString& relPath)
{
    if (ctx.trimmed().isEmpty()) return false;

    auto obj = readObj(ctx);
    const QString p = QDir::cleanPath(QDir::fromNativeSeparators(relPath.trimmed()));

    obj["logo_proyecto_custom"] = !p.isEmpty();
    obj["logo_proyecto_path"]   = p;

    return writeObj(ctx, obj);
}
