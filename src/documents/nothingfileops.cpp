// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Nothing Files FileViewModel.kt; account containment, atomic trash
// metadata, collision checks and ZIP traversal checks are InGe+ additions.
#include "nothingfileops.h"
#include "docsops.h"
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QTemporaryFile>
#include <QStorageInfo>
#include <QUuid>
#include <QCryptographicHash>
#include <QUrl>
#include <private/qzipreader_p.h>
#include <private/qzipwriter_p.h>
#include <algorithm>

namespace NothingFiles {
static QVariantMap failure(const QString &message) { return {{"error", message}}; }
bool inside(const QString &root, const QString &path, bool allowRoot)
{
    const QString r = QFileInfo(root).canonicalFilePath();
    const QFileInfo p(path);
    const QString c = p.canonicalFilePath();
    if (r.isEmpty() || c.isEmpty() || p.isSymLink()) return false;
#ifdef Q_OS_WIN
    constexpr auto cs = Qt::CaseInsensitive;
#else
    constexpr auto cs = Qt::CaseSensitive;
#endif
    return (allowRoot && c.compare(r, cs) == 0) || c.startsWith(r + '/', cs);
}
bool validName(const QString &name)
{
    return !name.trimmed().isEmpty() && name != "." && name != ".."
        && !name.contains('/') && !name.contains('\\') && !name.contains(':')
        && !name.contains(QChar::Null) && name != ".NothingTrash"
        && !name.startsWith(".ingep_") && name != ".initialized";
}
static bool internal(const QString &name)
{ return name == ".NothingTrash" || name.startsWith(".ingep_") || name == ".initialized"; }
static QString kind(const QFileInfo &f)
{
    if (f.isDir()) return "folder";
    const QString e = f.suffix().toLower();
    if (QStringList{"jpg","jpeg","png","webp","gif","bmp","heic"}.contains(e)) return "image";
    if (QStringList{"mp4","mkv","avi","mov","webm","3gp"}.contains(e)) return "video";
    if (QStringList{"mp3","wav","m4a","ogg","flac","aac"}.contains(e)) return "audio";
    if (e == "apk") return "android";
    if (e == "pdf") return "picture_as_pdf";
    if (e == "zip") return "archive";
    if (QStringList{"txt","log","json","xml","doc","docx","xlsx","xls","csv","odt"}.contains(e)) return "description";
    return "insert_drive_file";
}
QVariantMap item(const QString &path)
{
    QFileInfo f(path);
    const QString k = kind(f);
    return {{"name",f.fileName()}, {"path",f.absoluteFilePath()}, {"directory",f.isDir()},
            {"bytes",f.isDir() ? 0 : f.size()}, {"modified",f.lastModified().toMSecsSinceEpoch()},
            {"date",f.lastModified().toString("dd MMM yyyy")}, {"extension",f.suffix().toLower()},
            {"icon", k == "video" ? "video_file" : k == "audio" ? "audio_file" : k},
            {"kind",k}, {"url",QUrl::fromLocalFile(f.absoluteFilePath()).toString()}, {"remote",false}};
}
QVariantMap scan(const QString &root, const QString &folder, const QString &route, const QString &category)
{
    if (!inside(root, root, true)) return failure("No se puede acceder a la carpeta de esta cuenta.");
    QVariantList rows, recent;
    QVariantMap stats;
    const QStorageInfo storage(root);
    if (storage.isValid() && storage.isReady()) {
        stats["total"] = storage.bytesTotal();
        stats["free"] = storage.bytesAvailable();
        stats["used"] = storage.bytesTotal() - storage.bytesAvailable();
    }
    const auto flags = QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::NoSymLinks;
    if (route == "trash") {
        const QDir trash(QDir(root).filePath(".NothingTrash"));
        for (const auto &bucket : trash.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot)) {
            if (!inside(root, bucket.filePath())) continue;
            for (const auto &f : QDir(bucket.filePath()).entryInfoList(flags)) {
                if (f.fileName() != "origin.json" && inside(root, f.filePath())) rows.append(item(f.filePath()));
            }
        }
        return {{"rows", rows}};
    }
    if (route == "files") {
        if (!inside(root, folder, true) || !QFileInfo(folder).isReadable()) return failure("Carpeta inaccesible o sin permiso de lectura.");
        for (const auto &f : QDir(folder).entryInfoList(flags)) {
            if (!internal(f.fileName()) && inside(root,f.filePath())) rows.append(item(f.filePath()));
        }
        return {{"rows",rows}};
    }
    QStringList pending{root};
    QVariantList junk, large, duplicates, oldDownloads, screenshots;
    QHash<qint64,QStringList> sizes;
    int visited = 0;
    QString scanError;
    while (!pending.isEmpty()) {
        const QString dir = pending.takeLast();
        if (!QFileInfo(dir).isReadable()) { scanError = "Algunas carpetas no tienen permiso de lectura."; continue; }
        for (const auto &f : QDir(dir).entryInfoList(flags)) {
            if (internal(f.fileName()) || !inside(root,f.filePath())) continue;
            if (++visited > 50000) { scanError = "Análisis limitado a 50 000 entradas; navega por carpetas para consultar el resto."; pending.clear(); break; }
            if (f.isDir()) { pending.append(f.filePath()); continue; }
            const QVariantMap row = item(f.filePath());
            const QString k = kind(f), e = f.suffix().toLower();
            const auto addBytes = [&](const QString &key) { stats[key] = stats.value(key).toLongLong() + f.size(); };
            if (k == "image") addBytes("images");
            if (k == "video") addBytes("videos");
            if (k == "audio") addBytes("audio");
            if (k == "description" || k == "picture_as_pdf") addBytes("docs");
            if (k == "android") addBytes("apks");
            if (QStringList{"tmp","log","cache"}.contains(e) && junk.size() < 50) junk.append(row);
            if (f.size() > 100LL*1024*1024 || (k == "video" && f.size() > 50LL*1024*1024)) large.append(row);
            if (k == "image" && f.filePath().contains("Screenshot",Qt::CaseInsensitive) && screenshots.size() < 20) screenshots.append(row);
            if (f.filePath().contains("Download",Qt::CaseInsensitive) && f.lastModified() < QDateTime::currentDateTime().addDays(-90) && oldDownloads.size() < 20) oldDownloads.append(row);
            if (f.size() > 1024*1024) sizes[f.size()].append(f.filePath());
            recent.append(row);
            if (recent.size() > 400) {
                std::sort(recent.begin(),recent.end(),[](const QVariant &a,const QVariant &b){return a.toMap()["modified"].toLongLong()>b.toMap()["modified"].toLongLong();});
                recent = recent.mid(0,200);
            }
            bool match = (category == "IMAGES" && k == "image") || (category == "VIDEOS" && k == "video")
                || (category == "AUDIO" && k == "audio") || (category == "APKS" && k == "android")
                || (category == "DOCS" && (k == "description" || k == "picture_as_pdf"))
                || (category == "DOWNLOADS" && f.filePath().contains("Download",Qt::CaseInsensitive));
            if (route == "category" && match) rows.append(row);
        }
    }
    // The donor compares size only. Require equal contents before offering cleanup.
    qint64 hashed = 0;
    for (auto it = sizes.cbegin(); it != sizes.cend() && duplicates.size() < 20; ++it) {
        if (it.value().size() < 2) continue;
        QSet<QByteArray> seen;
        for (const QString &path : it.value()) {
            if (hashed + it.key() > 512LL*1024*1024) { stats["duplicateLimit"] = true; break; }
            QFile file(path);
            if (!file.open(QIODevice::ReadOnly)) continue;
            QCryptographicHash hash(QCryptographicHash::Sha256);
            if (!hash.addData(&file)) continue;
            hashed += it.key();
            const QByteArray digest = hash.result();
            if (seen.contains(digest) && duplicates.size() < 20) duplicates.append(item(path));
            seen.insert(digest);
        }
    }
    std::sort(recent.begin(),recent.end(),[](const QVariant &a,const QVariant &b){return a.toMap()["modified"].toLongLong()>b.toMap()["modified"].toLongLong();});
    std::sort(large.begin(),large.end(),[](const QVariant &a,const QVariant &b){return a.toMap()["bytes"].toLongLong()>b.toMap()["bytes"].toLongLong();});
    stats["junk"] = junk; stats["large"] = large.mid(0,20); stats["duplicates"] = duplicates;
    stats["oldDownloads"] = oldDownloads; stats["screenshots"] = screenshots;
    if (route == "recents") rows = recent.mid(0,200);
    return {{"rows",rows},{"stats",stats},{"recents",recent.mid(0,15)},{"error",scanError}};
}

QVariantMap operate(const QString &root, const QString &folder, const QString &op,
                    const QStringList &paths, const QString &argument)
{
    const QString trashRoot = QDir(root).filePath(".NothingTrash");
    DocsOps ops;
    QString resultPath;
    if (op == "createFolder" || op == "createFile") {
        if (!inside(root,folder,true) || !validName(argument)) return failure("Nombre o carpeta de destino inválidos.");
        resultPath = QDir(folder).filePath(argument);
        if (QFileInfo::exists(resultPath)) return failure("Ya existe un archivo con ese nombre.");
        if (op == "createFolder") {
            if (!ops.makeDir(folder,argument)) return failure(ops.lastError());
        } else {
            QFile f(resultPath);
            if (!f.open(QIODevice::WriteOnly | QIODevice::NewOnly)) return failure(f.errorString());
        }
    }
    int done = 0;
    for (const QString &path : paths) {
        const auto fail = [&](const QString &why) { return failure(QString("%1 completado(s). %2").arg(done).arg(why)); };
        if (!inside(root,path) || internal(QFileInfo(path).fileName())) return fail("Ruta fuera de la cuenta o archivo protegido.");
        const QFileInfo source(path);
        const bool inTrash = inside(trashRoot,path);
        if (source.isDir() && (op == "copy" || op == "move" || op == "trash")) {
            QStringList directories{path};
            while (!directories.isEmpty()) {
                for (const auto &child : QDir(directories.takeLast()).entryInfoList(QDir::AllEntries|QDir::NoDotAndDotDot|QDir::Hidden|QDir::System)) {
                    if (child.isSymLink() || !inside(root,child.filePath())) return fail("La carpeta contiene enlaces o rutas fuera de esta cuenta.");
                    if (child.isDir()) directories.append(child.filePath());
                }
            }
        }
        if (inTrash && op != "restore" && op != "remove") return fail("Restaura el archivo antes de usarlo.");
        if (op == "trash") {
            const QString slot = QDir(trashRoot).filePath(QUuid::createUuid().toString(QUuid::WithoutBraces));
            if (!QDir().mkpath(slot)) return fail("No se pudo crear la papelera.");
            QSaveFile meta(QDir(slot).filePath("origin.json"));
            const auto bytes = QJsonDocument(QJsonObject{{"path",path},{"deleted",QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}}).toJson();
            if (!meta.open(QIODevice::WriteOnly) || meta.write(bytes) != bytes.size() || !meta.commit()) return fail("No se pudo guardar el origen del archivo.");
            resultPath = QDir(slot).filePath(source.fileName());
            if (!QFile::rename(path,resultPath)) return fail("No se pudo mover a la papelera. El original se conserva.");
        } else if (op == "restore") {
            if (!inTrash || QFileInfo(source.absolutePath()).absolutePath() != trashRoot) return fail("El archivo no es una entrada válida de papelera.");
            QFile meta(QDir(source.absolutePath()).filePath("origin.json"));
            if (!meta.open(QIODevice::ReadOnly)) return fail("No se encuentra la ubicación original.");
            resultPath = QJsonDocument::fromJson(meta.readAll()).object()["path"].toString();
            if (!inside(root,QFileInfo(resultPath).absolutePath(),true) || !validName(QFileInfo(resultPath).fileName()) || QFileInfo::exists(resultPath)) return fail("Destino original inexistente, inválido u ocupado. No se sobrescribió ningún archivo.");
            if (!QFile::rename(path,resultPath)) return fail("No se pudo restaurar el archivo.");
            meta.close(); QFile::remove(meta.fileName()); QDir().rmdir(source.absolutePath());
        } else if (op == "remove") {
            if (!inTrash || QFileInfo(source.absolutePath()).absolutePath() != trashRoot) return fail("La eliminación definitiva solo está permitida sobre entradas de papelera.");
            if (!(source.isDir() ? QDir(path).removeRecursively() : QFile::remove(path))) return fail("No se pudo eliminar el archivo.");
            QFile::remove(QDir(source.absolutePath()).filePath("origin.json")); QDir().rmdir(source.absolutePath());
        } else if (op == "rename") {
            if (!validName(argument)) return fail("Nombre inválido.");
            resultPath = QDir(source.absolutePath()).filePath(argument);
            if (QFileInfo::exists(resultPath)) return fail("El nombre ya existe.");
            if (!ops.renameInPlace(path,argument)) return fail(ops.lastError());
        } else if (op == "copy" || op == "move") {
            if (!inside(root,folder,true) || folder == path || inside(path,folder,true)) return fail("Destino inválido: no se puede copiar una carpeta dentro de sí misma.");
            if (QFileInfo::exists(QDir(folder).filePath(source.fileName()))) return fail("El destino ya contiene ese nombre.");
            resultPath = op == "copy" ? ops.copyToDir(path,folder) : ops.moveToDir(path,folder);
            if (resultPath.isEmpty()) return fail(ops.lastError());
        } else if (op == "read") {
            QFile f(path);
            if (f.size() > 2*1024*1024) return fail("El lector admite hasta 2 MB. Usa Abrir con para este archivo.");
            if (!f.open(QIODevice::ReadOnly)) return fail(f.errorString());
            return {{"text",QString::fromUtf8(f.readAll())}};
        } else if (op == "compress") {
            resultPath = QDir(source.absolutePath()).filePath(source.completeBaseName()+".zip");
            if (QFileInfo::exists(resultPath)) return fail("Ya existe el ZIP de destino.");
            QTemporaryFile output(QDir(source.absolutePath()).filePath(".nothingzip-XXXXXX"));
            if (!output.open()) return fail(output.errorString());
            QZipWriter writer(&output);
            QStringList pending{path};
            int count = 0;
            while (!pending.isEmpty()) {
                QString current = pending.takeLast();
                if (!inside(root,current) || ++count > 50000) return fail("Archivo inseguro o límite de 50 000 entradas superado.");
                QFileInfo f(current);
                const QString relative = QDir(source.absolutePath()).relativeFilePath(current);
                if (f.isDir()) {
                    writer.addDirectory(relative);
                    for (const auto &child : QDir(current).entryInfoList(QDir::AllEntries|QDir::NoDotAndDotDot|QDir::Hidden)) pending.append(child.filePath());
                } else {
                    QFile input(current);
                    if (!input.open(QIODevice::ReadOnly)) return fail(input.errorString());
                    writer.addFile(relative,&input);
                }
                if (writer.status() != QZipWriter::NoError) return fail("Error al escribir el ZIP.");
            }
            writer.close();
            if (writer.status() != QZipWriter::NoError || !output.rename(resultPath)) return fail("No se pudo finalizar el ZIP.");
            output.setAutoRemove(false);
        } else if (op == "extract") {
            resultPath = QDir(source.absolutePath()).filePath(source.completeBaseName());
            if (QFileInfo::exists(resultPath)) return fail("La carpeta de extracción ya existe.");
            QZipReader reader(path);
            const auto entries = reader.fileInfoList();
            if (reader.status() != QZipReader::NoError || entries.size() > 50000) return fail("ZIP inválido o con demasiadas entradas.");
            qint64 total = 0;
            for (const auto &e : entries) {
                const QString name = QDir::fromNativeSeparators(e.filePath);
                if (e.isSymLink || QDir::isAbsolutePath(name) || name.contains(':') || name.split('/').contains("..") || name.contains(QChar::Null)
                    || e.size < 0 || e.size > 128LL*1024*1024 || (total += e.size) > 2LL*1024*1024*1024)
                    return fail("ZIP inseguro o excede los límites: 128 MB por archivo, 2 GB total.");
            }
            // Extract into a new sibling staging directory; publish only when complete.
            const QString stage = resultPath + ".extract-" + QUuid::createUuid().toString(QUuid::WithoutBraces);
            if (!QDir().mkpath(stage)) return fail("No se pudo crear el destino.");
            bool ok = true;
            for (const auto &e : entries) {
                const QString dst = QDir(stage).filePath(e.filePath);
                if (e.isDir) { ok = QDir().mkpath(dst); }
                else {
                    ok = QDir().mkpath(QFileInfo(dst).absolutePath());
                    QSaveFile f(dst);
                    const QByteArray data = reader.fileData(e.filePath);
                    ok = ok && data.size() == e.size && f.open(QIODevice::WriteOnly) && f.write(data) == data.size() && f.commit();
                }
                if (!ok) break;
            }
            ok = ok && reader.status() == QZipReader::NoError && QDir().rename(stage,resultPath);
            if (!ok) { QDir(stage).removeRecursively(); return fail("Extracción fallida. El ZIP original se conserva."); }
        }
        ++done;
    }
    return {{"path",resultPath},{"message",QString("Operación completada%1").arg(done > 1 ? QString(" (%1 archivos)").arg(done) : QString())}};
}
}
