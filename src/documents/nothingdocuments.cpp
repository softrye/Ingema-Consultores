// SPDX-License-Identifier: GPL-3.0-only
#include "nothingdocuments.h"
#include <QDebug>
#include "storageprovider.h"
#include "../core/RemoteExecutor.h"
#include <QCoreApplication>
#include "nothingfileops.h"
#include "appcontext.h"
#include "authsession.h"
#include "clouddocs.h"
#include "docsops.h"
#include "docscontroller.h"
#include "supabaseclient.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QMimeDatabase>
#include <QSaveFile>
#include <QFile>
#include <QStandardPaths>
#include <QNetworkReply>
#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QSettings>
#include <QTimer>
#include <QUrl>
#include <QUuid>
#include <QDateTime>
#include <QtConcurrent>
#include <algorithm>
#ifdef Q_OS_ANDROID
#include <QJniObject>
#include <QJniEnvironment>
#include <QCoreApplication>
#endif

NothingDocuments::NothingDocuments(QObject *parent) : QAbstractListModel(parent)
{
    m_searchTimer=new QTimer(this); m_searchTimer->setSingleShot(true); m_searchTimer->setInterval(350);
    connect(m_searchTimer,&QTimer::timeout,this,[this]{ if(m_route=="drive") { if(m_busy) m_searchTimer->start(); else remoteList(); } });
    QSettings settings;
    m_theme = settings.value("NothingDocuments/theme","system").toString();
    m_oled = settings.value("NothingDocuments/oled",false).toBool();
    m_grid = settings.value("NothingDocuments/grid",false).toBool();
    m_sort = settings.value("NothingDocuments/sort","name").toString();
    m_rootResolver = new DocsOps(this);
    connect(m_rootResolver,&DocsOps::scopedRootReady,this,[this](bool ok,const QString &root,const QString &error){
        m_busy = false;
        if (!ok) { setError(error); return; }
        m_root = root; m_folder = root;
        if (!QFileInfo(root).isReadable()) { setError("No hay permiso para leer la carpeta de esta cuenta."); return; }
        refresh();
    });
    if (auto *auth = AuthSession::instance()) {
        connect(auth,&AuthSession::loggedChanged,this,&NothingDocuments::resetAccount);
        connect(auth,&AuthSession::currentAccountChanged,this,&NothingDocuments::resetAccount);
        connect(auth,&AuthSession::userInfoChanged,this,[this,auth]{
            if ((auth->logged() ? auth->userId() : QString()) != m_uid) resetAccount();
        });
    }
    QTimer::singleShot(0,this,&NothingDocuments::resetAccount);
}
NothingDocuments::~NothingDocuments() = default;
int NothingDocuments::rowCount(const QModelIndex &parent) const { return parent.isValid() ? 0 : m_rows.size(); }
QVariant NothingDocuments::data(const QModelIndex &index,int role) const
{ return index.isValid() && index.row() >= 0 && index.row() < m_rows.size() && role == Qt::UserRole+1 ? m_rows[index.row()] : QVariant(); }
QHash<int,QByteArray> NothingDocuments::roleNames() const { return {{Qt::UserRole+1,"entry"}}; }
void NothingDocuments::setError(const QString &error) { m_error = error; emit changed(); }
void NothingDocuments::saveSettings()
{
    QSettings s; s.setValue("NothingDocuments/theme",m_theme); s.setValue("NothingDocuments/oled",m_oled);
    s.setValue("NothingDocuments/grid",m_grid); s.setValue("NothingDocuments/sort",m_sort);
    emit changed();
}
void NothingDocuments::setTheme(const QString &v) { if (QStringList{"system","light","dark"}.contains(v)) { m_theme=v; saveSettings(); } }
void NothingDocuments::setOled(bool v) { m_oled=v; saveSettings(); }
void NothingDocuments::setGrid(bool v) { m_grid=v; saveSettings(); }
void NothingDocuments::setSortOrder(const QString &v) { if (QStringList{"name","date","size"}.contains(v)) { m_sort=v; saveSettings(); applyRows(); } }
void NothingDocuments::setQuery(const QString &v) { m_query=v.left(500); if(m_route=="drive") m_searchTimer->start(); else applyRows(); }
QString NothingDocuments::formatSize(qint64 bytes)
{
    double value = double(bytes); QStringList units{"B","KB","MB","GB","TB"}; int i=0;
    while (value >= 1024 && i < units.size()-1) { value/=1024; ++i; }
    return QString::number(value,'f',i ? 1 : 0)+' '+units[i];
}
void NothingDocuments::applyRows()
{
    beginResetModel(); m_rows.clear();
    for (const QVariant &v : std::as_const(m_all)) if (m_route=="drive" || v.toMap()["name"].toString().contains(m_query,Qt::CaseInsensitive)) m_rows.append(v);
    std::sort(m_rows.begin(),m_rows.end(),[this](const QVariant &av,const QVariant &bv){
        const auto a=av.toMap(),b=bv.toMap();
        if (m_sort == "date") return a["modified"].toLongLong() > b["modified"].toLongLong();
        if (m_sort == "size") return a["bytes"].toLongLong() > b["bytes"].toLongLong();
        if (a["directory"].toBool() != b["directory"].toBool()) return a["directory"].toBool();
        return QString::compare(a["name"].toString(),b["name"].toString(),Qt::CaseInsensitive)<0;
    });
    endResetModel(); emit changed();
}
void NothingDocuments::resetAccount()
{
    const auto *auth = AuthSession::instance();
    const QString uid = auth && auth->logged() ? auth->userId() : QString();
    m_searchTimer->stop(); m_syncing=false;
    ++m_epoch; m_uid=uid; m_root.clear(); m_folder.clear(); m_all.clear(); m_selected.clear();
    m_clipboard.clear(); m_history.clear(); m_recents.clear(); m_stats.clear(); m_query.clear();
    m_route="home"; m_project.clear(); m_remoteDir.clear(); m_downloadOpen.clear(); m_error.clear();
    m_space.clear(); m_remoteTitle.clear(); m_remoteMove.clear(); m_downloadEntry.clear();
    m_moreRemote=false; m_pendingRefresh=false; m_busy=true;
    configureCloud();
    if(!m_journal.load(uid)) { m_busy=false; setError("No se pudo leer el estado de sincronización. Los datos se conservan."); return; }
    m_space=m_journal.trees.value("_root_space").toString();
    applyRows(); m_rootResolver->applyScopedRoot(uid);
}
void NothingDocuments::run(std::function<QVariantMap()> job,bool operation)
{
    if (m_worker.isRunning()) { m_pendingRefresh=true; return; }
    m_busy=true; m_error.clear(); emit changed();
    const int epoch=m_epoch;
    disconnect(&m_worker,nullptr,this,nullptr);
    connect(&m_worker,&QFutureWatcher<QVariantMap>::finished,this,[this,epoch,operation]{
        const auto result=m_worker.result();
        if (epoch != m_epoch) { if (!m_root.isEmpty()) { m_busy=false; refresh(); } return; }
        m_busy=false;
        const QString error=result.value("error").toString();
        if (operation) {
            m_selected.clear();
            if (!error.isEmpty()) setError(error);
            else if (result.contains("text")) emit textReady(result["text"].toString());
            else {
                if (result.value("clearClipboard").toBool()) m_clipboard.clear();
                emit completed(result["message"].toString(),result["path"].toString());
                refresh();
            }
        } else {
            m_all=result.value("rows").toList();
            if (result.contains("stats")) m_stats=result["stats"].toMap();
            if (result.contains("recents")) m_recents=result["recents"].toList();
            m_error=error; applyRows();
        }
        emit changed();
        if (m_pendingRefresh) { m_pendingRefresh=false; refresh(); }
    });
    m_worker.setFuture(QtConcurrent::run(std::move(job)));
}
void NothingDocuments::refresh()
{
    if (m_root.isEmpty()) { if (!m_busy) resetAccount(); return; }
    if (m_worker.isRunning()) { m_pendingRefresh=true; return; }
    if (m_route == "drive") { if (!m_busy) { if(!m_journal.outbox.isEmpty()) reconcile(); else remoteList(); } return; }
    if (m_route == "home") { if(!m_busy) storageUsage(); return; }
    const auto root=m_root,folder=m_folder,route=m_route,category=m_category;
    run([=]{ return NothingFiles::scan(root,folder,route,category); });
}
bool NothingDocuments::hasStorageAccess() const
{
#ifdef Q_OS_ANDROID
    return QJniObject::callStaticMethod<jboolean>("com/ingema/ingeplus/NothingFileBridge","hasAccess","()Z");
#else
    return true;
#endif
}
void NothingDocuments::requestStorageAccess()
{
#ifdef Q_OS_ANDROID
    const auto context=QNativeInterface::QAndroidApplication::context();
    QJniObject::callStaticMethod<void>("com/ingema/ingeplus/NothingFileBridge","requestAccess","(Landroid/content/Context;)V",context.object());
#endif
}
void NothingDocuments::navigate(const QString &route,const QString &value)
{
    if (m_busy) return;
    if (!QStringList{"home","files","category","recents","trash","drive"}.contains(route)) return;
    if (route == "files" && !NothingFiles::inside(m_root,value.isEmpty()?m_root:value,true)) { setError("Carpeta fuera de esta cuenta."); return; }
    m_history.append(QVariantMap{{"route",m_route},{"folder",m_folder},{"category",m_category},{"project",m_project},{"space",m_space},{"title",m_remoteTitle},{"remoteDir",m_remoteDir},{"query",m_query},{"entry",m_currentEntry}});
    m_route=route; m_query.clear(); m_selected.clear(); m_category.clear();
    if (route == "files") m_folder=value.isEmpty()?m_root:value;
    if (route == "category") m_category=value;
    if (route == "drive") {
        if (value.isEmpty()) { m_project.clear(); m_space.clear(); m_remoteDir.clear(); m_remoteTitle.clear(); m_currentEntry.clear(); }
        else {
            const auto entry = remoteEntry(value);
            if (entry.isEmpty()) { m_history.removeLast(); setError("Actualiza la carpeta antes de abrirla."); return; }
            if (entry.value("kind") == "SPACE") { m_space=entry.value("id").toString(); m_project=entry.value("project").toString(); m_remoteDir.clear(); m_currentEntry.clear(); }
            else { m_remoteDir=entry.value("id").toString(); m_currentEntry=entry; }
            m_remoteTitle=entry.value("name").toString();
        }
    }
    m_all.clear(); applyRows(); refresh();
}
bool NothingDocuments::back()
{
    if (m_busy) return true;
    if (!m_selected.isEmpty()) { clearSelection(); return true; }
    if (!m_query.isEmpty()) { setQuery({}); return true; }
    if (m_history.isEmpty()) return false;
    const auto state=m_history.takeLast().toMap();
    m_route=state["route"].toString(); m_folder=state["folder"].toString();
    m_category=state["category"].toString(); m_project=state["project"].toString();
    m_space=state["space"].toString(); m_remoteTitle=state["title"].toString();
    m_remoteDir=state["remoteDir"].toString(); m_query=state["query"].toString();
    m_currentEntry=state["entry"].toMap(); m_folderCaps.clear(); ++m_capsRevision;
    m_all.clear(); applyRows(); refresh(); return true;
}
bool NothingDocuments::selected(const QString &path) const { return m_selected.contains(path); }
QStringList NothingDocuments::selection() const { return m_selected.values(); }
void NothingDocuments::toggleSelection(const QString &path)
{
    if (m_busy || m_route == "drive") return;
    if (m_selected.contains(path)) m_selected.remove(path); else m_selected.insert(path);
    emit changed();
}
void NothingDocuments::clearSelection() { m_selected.clear(); emit changed(); }
void NothingDocuments::selectAll() { if (m_route == "drive" || m_busy) return; for (const auto &v:m_rows) m_selected.insert(v.toMap()["path"].toString()); emit changed(); }
bool NothingDocuments::checkPaths(const QStringList &paths,bool allowTrash)
{
    if (m_busy || m_root.isEmpty()) return false;
    for (const auto &path:paths) {
        if (!NothingFiles::inside(m_root,path) || (!allowTrash && NothingFiles::inside(QDir(m_root).filePath(".NothingTrash"),path))) { setError("Ruta fuera de esta cuenta o dentro de la papelera."); return false; }
        auto *ctx=AppContext::instance();
        if (ctx && (ctx->isOpenFile(path) || ctx->hasOpenUnderDir(path))) { setError("Cierra el documento abierto antes de modificarlo."); return false; }
        // Keep the existing Recursos protection in the host's operations layer.
        const QString rel=QDir(m_root).relativeFilePath(path);
        if (rel == "Recursos" || rel.startsWith("Recursos/Logo_MTC") || rel.startsWith("Recursos/Logo_Aldesa")) { setError("Recurso protegido de InGe+."); return false; }
    }
    return true;
}
void NothingDocuments::localOperation(const QString &op,const QStringList &paths,const QString &argument)
{
    if (!checkPaths(paths,op=="restore" || op=="remove")) return;
    const auto root=m_root,folder=m_folder;
    run([=]{ auto result=NothingFiles::operate(root,folder,op,paths,argument); if (op=="copy" || op=="move") result["clearClipboard"]=true; return result; },true);
}
void NothingDocuments::clipboard(const QStringList &paths,bool cut) {
    if (m_route=="drive") {
        if (m_busy || !cut || paths.size()!=1) return;
        const auto entry=remoteEntry(paths.first());
        if (entry.value("kind")!="FOLDER" && entry.value("kind")!="FILE") return;
        m_remoteMove=entry; m_remoteMove["space"]=m_space; m_clipboard.clear(); emit changed(); return;
    }
    if(checkPaths(paths)) { m_remoteMove.clear(); m_clipboard=paths; m_cut=cut; clearSelection(); }
}
void NothingDocuments::cancelClipboard() { m_clipboard.clear(); m_remoteMove.clear(); emit changed(); }
void NothingDocuments::paste() {
    if (m_route=="drive" && !m_remoteMove.isEmpty()) {
        if (m_remoteMove.value("space").toString()!=m_space) { setError("El destino debe pertenecer al mismo espacio del proyecto."); return; }
        remoteMutation("move",m_remoteMove.value("id").toString(),m_remoteDir); return;
    }
    if(m_route=="files" && !m_clipboard.isEmpty()) localOperation(m_cut?"move":"copy",m_clipboard);
}
void NothingDocuments::create(const QString &name,bool directory) {
    if(m_route=="drive" && directory) remoteMutation("create",{},name);
    else if(m_route=="files") localOperation(directory?"createFolder":"createFile",{},name);
}
void NothingDocuments::rename(const QString &path,const QString &name) {
    if(m_route=="drive") remoteMutation("rename",remoteEntry(path).value("id").toString(),name);
    else localOperation("rename",{path},name);
}
void NothingDocuments::trash(const QStringList &paths) {
    if(m_route=="drive") { if(paths.size()==1) remoteMutation("trash",remoteEntry(paths.first()).value("id").toString()); }
    else localOperation("trash",paths);
}
void NothingDocuments::restore(const QStringList &paths) { localOperation("restore",paths); }
void NothingDocuments::removeForever(const QStringList &paths) { localOperation("remove",paths); }
void NothingDocuments::emptyTrash() { QStringList paths; for(const auto &v:m_all) paths.append(v.toMap()["path"].toString()); removeForever(paths); }
void NothingDocuments::archive(const QString &path,bool extract) { localOperation(extract?"extract":"compress",{path}); }
void NothingDocuments::readText(const QString &path) { localOperation("read",{path}); }
void NothingDocuments::open(const QVariantMap &entry,bool chooser,bool share)
{
    if (m_busy) return;
    const QString path=entry["path"].toString();
    if (entry["remote"].toBool()) {
        if(entry["directory"].toBool()) navigate("drive",entry["path"].toString());
        // A .calicata from Web/InGeDrive is a Smart Document: resolve its
        // project_id + calicatas.id instead of downloading it as a local file.
        else if(entry.value("kind")=="SMART_DOCUMENT" || entry.value("extension")=="rend"
                || entry.value("extension").toString().toLower()=="calicata"
                || entry.value("name").toString().toLower().endsWith(".calicata")
                || entry.value("name").toString().toLower().endsWith(".calicata.json")) {
            const QString entryProject = entry.value("project").toString().isEmpty()
                    ? m_project : entry.value("project").toString();
            onlineRequest("rpc/get_smart_document_access_v01", {{"p_document_node_id",entry.value("id")}},
                [this, entryProject](const QVariantList &rows) {
                    const auto access=rows.value(0).toMap();
                    const QString targetType=access.value("target_type").toString().trimmed().toUpper();
                    const QString targetId=access.value("target_id").toString().trimmed();
                    if(rows.size()!=1 || targetId.isEmpty()) {
                        setError("Este Smart Document no contiene una referencia autorizada."); return;
                    }
                    if(targetType=="RENDITION") {
                        emit renditionOpenRequested(targetId);
                        return;
                    }
                    if(targetType=="CALICATA") {
                        const QString projectId=access.value("project_id").toString().isEmpty()
                                ? entryProject : access.value("project_id").toString();
                        if(projectId.isEmpty()) {
                            setError("La calicata no tiene un proyecto autorizado asociado."); return;
                        }
                        emit calicataOpenRequested(projectId,targetId);
                        return;
                    }
                    setError("Este Smart Document pertenece a otro tipo de contenido.");
                });
        }
        else { m_downloadOpen=share?"share":chooser?"chooser":"open"; download(entry); }
        return;
    }
    const auto mirror=QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)+"/inge-drive/"+m_uid+"/mirror";
    if (!NothingFiles::inside(m_root,path) && !NothingFiles::inside(mirror,path)) { setError("No se puede abrir esta ruta."); return; }
    if (entry["directory"].toBool()) { if(!share && !chooser) navigate("files",path); else setError("Comprime la carpeta para compartirla."); return; }
#ifdef Q_OS_ANDROID
    const QJniObject context=QNativeInterface::QAndroidApplication::context();
    const QJniObject file=QJniObject::fromString(path);
    const QJniObject error=QJniObject::callStaticObjectMethod("com/ingema/ingeplus/NothingFileBridge","open",
        "(Landroid/content/Context;Ljava/lang/String;ZZ)Ljava/lang/String;",context.object(),file.object<jstring>(),jboolean(chooser),jboolean(share));
    QJniEnvironment env;
    if(env->ExceptionCheck()) { env->ExceptionClear(); setError("No se pudo abrir el archivo con Android."); }
    else if(!error.isValid()) setError("No se pudo contactar con el visor Android.");
    else if(!error.toString().isEmpty()) setError(error.toString());
#else
    if(share) { setError("Compartir requiere Android."); return; }
    if(!QDesktopServices::openUrl(QUrl::fromLocalFile(path))) setError("No hay una aplicación disponible para abrir este archivo.");
#endif
}
void NothingDocuments::configureCloud()
{
    if(m_provider) { delete m_provider; m_provider=nullptr; }
    if(m_cloud) { delete m_cloud; m_cloud=nullptr; }
    auto *ctx=AppContext::instance(); if(!ctx) return;
    m_provider=new SupabaseStorageProvider(ctx->supabase(),ctx->auth(),this);
    m_cloud=new CloudDocs(ctx->supabase(),ctx->auth(),this);
    connect(m_cloud,&CloudDocs::listOk,this,[this](const QVector<CloudDocItem> &items){
        if(m_route!="drive") return;
        if(!m_appendRemote) m_all.clear();
        for(const auto &f:items) {
            const QString rel=m_project.isEmpty()?f.name:f.relativePath;
            m_all.append(QVariantMap{{"name",QFileInfo(f.name).fileName()},{"path",f.objectKey},{"relative",rel},
                {"directory",f.isFolder},{"bytes",f.size},{"modified",QDateTime::fromString(f.updatedAt,Qt::ISODate).toMSecsSinceEpoch()},
                {"date",f.updatedAt.left(10)},{"extension",QFileInfo(f.name).suffix().toLower()},
                {"icon",f.isFolder?"folder":"insert_drive_file"},{"remote",true}});
        }
        m_remoteOffset+=items.size(); m_moreRemote=items.size()==100; m_busy=false; applyRows();
    });
    const auto failure=[this](const QString &message){m_busy=false; m_downloadOpen.clear(); setError(message);};
    connect(m_cloud,&CloudDocs::listFail,this,failure);
    connect(m_cloud,&CloudDocs::downloadFail,this,failure);
    connect(m_cloud,&CloudDocs::uploadFail,this,failure);
    connect(m_cloud,&CloudDocs::downloadOk,this,&NothingDocuments::finishDownload);
    connect(m_cloud,&CloudDocs::uploadOk,this,[this](const QString &){m_busy=false; emit completed("Archivo subido a InGe Drive",{}); refresh();});
}
void NothingDocuments::finishDownload(const QString &path)
{
        m_busy=false; emit changed();
        const QString mirror=m_downloadEntry.value("mirror_dir").toString();
        if(!mirror.isEmpty()) {
            const QVariantMap previous=readMirror(mirror);
            QVariantMap manifest{{"node_id",m_downloadEntry.value("id")},{"space_id",m_downloadEntry.value("space_id")},
                {"document_version_id",m_downloadEntry.value("current_version_id")},
                {"content_version",m_downloadEntry.value("content_version")},{"file",path},
                {"materialized_at",QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}};
            QSaveFile out(QDir(mirror).filePath("mirror.json"));
            const QByteArray bytes=QJsonDocument(QJsonObject::fromVariantMap(manifest)).toJson(QJsonDocument::Compact);
            if(out.open(QIODevice::WriteOnly) && out.write(bytes)==bytes.size() && out.commit()) {
                const QString old=previous.value("file").toString();
                if(!old.isEmpty() && QFileInfo(old).absolutePath()!=QFileInfo(path).absolutePath())
                    QDir(QFileInfo(old).absolutePath()).removeRecursively();   // la versión anterior ya no es la vigente
            } else {
                m_downloadEntry.clear(); m_downloadOpen.clear();
                setError("Se descargó el archivo, pero no se pudo registrar su copia local. Reintenta.");
                return;
            }
            qInfo().noquote() << "INGE_DRIVE_BINARY state=LOCAL_AVAILABLE node=" << m_downloadEntry.value("id").toString()
                              << "content_version=" << m_downloadEntry.value("content_version").toLongLong();
        }
        emit completed("Descarga completada",path);
        if(auto *core=QCoreApplication::instance()->findChild<inge::core::RemoteExecutor*>())
            core->indexDocument(path,m_downloadEntry.value("id").toString(),m_downloadEntry.value("current_version_id").toString(),m_downloadEntry.value("project").toString());
        m_downloadEntry.clear();
        const auto action=m_downloadOpen; m_downloadOpen.clear();
        if(!action.isEmpty()) open(NothingFiles::item(path),action=="chooser",action=="share");
}
QVariantMap NothingDocuments::remoteEntry(const QString &path) const
{
    for(const auto &value:m_all) if(value.toMap().value("path").toString()==path) return value.toMap();
    if(!path.isEmpty() && m_currentEntry.value("path").toString()==path) return m_currentEntry;
    return {};
}
namespace {
QString onlineError(const QString &code)
{
    if(code.contains("AUTH") || code=="PGRST301" || code=="PGRST303") return "La sesión venció. Vuelve a iniciar sesión.";
    if(code=="NAME_CONFLICT") return "Ya existe una carpeta con ese nombre.";
    if(code=="STALE_VERSION") return "La carpeta cambió en otro dispositivo. Actualiza e inténtalo otra vez.";
    if(code.contains("PARENT") || code.contains("NOT_FOUND")) return "La carpeta ya no está disponible o no tienes acceso. Actualiza.";
    if(code.contains("FORBIDDEN")) return "No tienes permiso para modificar esta carpeta.";
    if(code=="CYCLE_DETECTED" || code=="INVALID_DESTINATION" || code=="CROSS_SPACE") return "No se puede mover la carpeta a ese destino.";
    if(code=="INVALID_NAME") return "Escribe un nombre válido de hasta 255 caracteres.";
    return "No se pudo completar la operación en InGe Drive. Actualiza e inténtalo otra vez.";
}
}
void NothingDocuments::onlineRequest(const QString &endpoint,const QVariantMap &arguments,
                                    std::function<void(const QVariantList &)> success,bool get)
{
    if(!m_provider || m_uid.isEmpty()) { m_busy=false; setError("Inicia sesión para usar InGe Drive."); return; }
    const int epoch=m_epoch;
    m_busy=true; m_error.clear(); emit changed();
    m_provider->request(endpoint,arguments,get,[this,epoch,success=std::move(success)](QVariantList rows,QString error,bool retryable){
        if(epoch!=m_epoch) return;
        m_busy=false;
        if(!error.isEmpty()) {
            m_downloadOpen.clear();
            if(retryable && m_route=="drive") { m_all=m_journal.local(treeKey()); applyRows(); }
            setError(retryable?"Sin conexión. Se muestra la última copia sincronizada.":onlineError(error)); return;
        }
        success(rows); emit changed();
    });
}
void NothingDocuments::storageUsage() {
    onlineRequest("rpc/inge_drive_storage_usage_v03",{{"p_space_id",m_space.isEmpty()?QVariant():QVariant(m_space)}},
        [this](const QVariantList &rows){m_stats=rows.value(0).toMap(); emit changed();});
}
void NothingDocuments::retrySync() {
    if(m_busy || m_syncing) return;
    for(auto &value:m_journal.outbox) {
        auto row=value.toMap();
        // Conflicts keep their original expected version; retry never adopts server state.
        if(row.value("state")=="RETRY") row["state"]="PENDING";
        value=row;
    }
    if(!m_journal.save()) { setError("No se pudo guardar la cola."); return; }
    reconcile();
}
void NothingDocuments::keepServerVersion() {
    if(m_busy || m_syncing || m_journal.outbox.isEmpty()) return;
    const auto operation=m_journal.outbox.first().toMap();
    if(operation.value("state")!="CONFLICT" && operation.value("state")!="REJECTED") return;
    const auto old=m_journal.outbox;
    const auto oldTrees=m_journal.trees;
    auto tree=m_journal.trees.value(operation.value("tree").toString()).toMap();
    tree["local"]=tree.value("synced");
    m_journal.trees[operation.value("tree").toString()]=tree;
    m_journal.outbox.removeFirst();
    if(!m_journal.save()) {m_journal.outbox=old;m_journal.trees=oldTrees;setError("No se pudo guardar la resolución.");return;}
    m_error.clear(); refresh();
}
void NothingDocuments::reconcile() {
    if(m_syncing || m_busy || !m_provider || m_journal.outbox.isEmpty()) return;
    const auto operation=m_journal.outbox.first().toMap();
    if(operation.value("state")=="CONFLICT" || operation.value("state")=="REJECTED") {
        m_all=m_journal.local(treeKey()); applyRows();
        setError("Cambio pendiente en conflicto. Se conserva la versión remota; revisa el cambio antes de resolverlo."); return;
    }
    const auto epoch=m_epoch; m_syncing=true; m_busy=true; emit changed();
    m_provider->request("rpc/inge_drive_mutate_v03",operation.value("args").toMap(),false,
        [this,epoch](QVariantList rows,QString error,bool retryable){
            if(epoch!=m_epoch) return;
            m_syncing=false; m_busy=false;
            auto operation=m_journal.outbox.first().toMap();
            const auto result=rows.value(0).toMap();
            const auto args=operation.value("args").toMap();
            const QString op=args.value("p_operation").toString();
            const QString logOp=op=="CREATE_FOLDER"?"CREATE":op=="TRASH"?"DELETE":op;
            if(error.isEmpty() && result.value("success").toBool()) {
                const auto previous=m_journal.outbox; m_journal.outbox.removeFirst();
                if(!m_journal.save()) {m_journal.outbox=previous;setError("No se pudo confirmar el estado local. Reintento seguro disponible.");return;}
                qInfo().noquote() << QStringLiteral("INGE_DOC_FOLDER_%1_OK").arg(logOp) << "node=" << args.value("p_node_id").toString();
                const QString nodeId=args.value("p_node_id").toString();
                const bool onCurrent=!m_currentEntry.isEmpty() && nodeId==m_currentEntry.value("id").toString();
                const qint64 adopted=result.value("node_version").toLongLong();
                const QString adoptedName=result.value("name",args.value("p_name")).toString();
                if(adopted>0 && !nodeId.isEmpty()) for(int i=0;i<m_all.size();++i) {
                    auto row=m_all.at(i).toMap(); if(row.value("id").toString()!=nodeId) continue;
                    row["node_version"]=adopted; if(op=="RENAME") row["name"]=adoptedName; m_all[i]=row;
                }
                if(onCurrent && adopted>0) m_currentEntry["node_version"]=adopted;
                if(onCurrent && op=="RENAME") {
                    m_currentEntry["name"]=adoptedName; m_remoteTitle=adoptedName;
                    qInfo().noquote() << "INGE_DOC_RENAME_REFRESH node=" << nodeId << "version=" << adopted
                                      << "source=" << (adopted>0?"result":"missing");
                    emit changed();
                }
                if(onCurrent && op=="TRASH" && m_journal.outbox.isEmpty()) { emit completed("Carpeta enviada a la papelera",{}); back(); return; }
                emit completed("Cambio sincronizado",{});
                if(!m_journal.outbox.isEmpty()) reconcile(); else remoteList();
                return;
            }
            const auto code=result.value("error_code").toString();
            qWarning().noquote() << QStringLiteral("INGE_DOC_FOLDER_%1_FAIL").arg(logOp) << "code=" << (error.isEmpty()?code:error)
                                 << "retryable=" << retryable;
            operation["state"]=retryable?"RETRY":code.contains("VERSION") || code.contains("CONFLICT")?"CONFLICT":"REJECTED";
            operation["error"]=error.isEmpty()?code:error;
            m_journal.outbox[0]=operation;
            if(!m_journal.save()) {setError("No se pudo guardar el error de sincronización.");return;}
            setError(retryable?"Cambio guardado en el dispositivo; pendiente de sincronizar.":onlineError(code));
        });
}
void NothingDocuments::remoteMutation(const QString &operation,const QString &node,const QString &argument)
{
    if(m_busy || m_route!="drive" || m_space.isEmpty()) return;
    if((operation=="create" || operation=="rename") && !NothingFiles::validName(argument)) { setError(onlineError("INVALID_NAME")); return; }
    if(!m_journal.outbox.isEmpty()) {setError("Sincroniza o resuelve el cambio pendiente antes de modificar otro documento.");return;}
    QVariantMap entry;
    for(const auto &value:m_all) if(value.toMap().value("id").toString()==node) entry=value.toMap();
    if(entry.isEmpty() && !node.isEmpty() && m_currentEntry.value("id").toString()==node) entry=m_currentEntry;
    const QString logOp=operation=="create"?"CREATE":operation=="trash"?"DELETE":operation.toUpper();
    qInfo().noquote() << QStringLiteral("INGE_DOC_FOLDER_%1_BEGIN").arg(logOp) << "space=" << m_space << "node=" << node;
    if(operation=="move" && entry.isEmpty()) entry=m_remoteMove;
    if(operation!="create" && (entry.isEmpty() || entry.value("node_version").toLongLong()<1)) {setError("Actualiza la carpeta para obtener la versión del documento.");return;}
    QVariantMap args{{"p_operation_id",QUuid::createUuid().toString(QUuid::WithoutBraces)},
        {"p_operation",operation=="create"?"CREATE_FOLDER":operation.toUpper()},{"p_space_id",m_space},
        {"p_node_id",node.isEmpty()?QVariant():QVariant(node)},
        {"p_expected_version",operation=="create"?QVariant():entry.value("node_version")}};
    if(operation=="create" || operation=="rename") args["p_name"]=argument;
    // The QML trash entry point always presents a contents-inclusive confirmation.
    if(operation=="trash") args["p_confirm_nonempty"]=true;
    if(operation=="create" || operation=="move") {
        const auto parent=operation=="create"?m_remoteDir:argument;
        args["p_parent_id"]=parent.isEmpty()?QVariant():QVariant(parent);
    }
    auto visible=m_all;
    for(qsizetype i=0;i<visible.size();++i) if(visible[i].toMap().value("id").toString()==node) {
        auto row=visible[i].toMap(); row["sync_state"]="PENDING";
        if(operation=="rename") row["name"]=argument;
        visible[i]=row;
        if(operation=="trash" || operation=="move") visible.removeAt(i);
        break;
    }
    if(operation=="create") visible.append(QVariantMap{{"id",args["p_operation_id"]},{"name",argument},
        {"directory",true},{"remote",true},{"kind","FOLDER"},{"sync_state","PENDING"}});
    if(!m_journal.enqueue({{"args",args},{"state","PENDING"},{"tree",treeKey()}},treeKey(),visible)) {
        setError("No se pudo guardar el cambio. No se ha enviado al servidor.");return;
    }
    m_all=visible; m_remoteMove.clear(); applyRows(); reconcile();
}

void NothingDocuments::remoteList(bool append)
{
    m_appendRemote=append; if(!append) m_remoteOffset=0;
    if (m_space.isEmpty()) {
        onlineRequest("rpc/get_my_document_space_v02",{},[this](const QVariantList &rows){
            if(rows.size()!=1) { setError("No se encontró el espacio de documentos."); return; }
            const auto space=rows.first().toMap(); m_space=space.value("id").toString();
            m_journal.trees["_root_space"]=m_space;
            if(!m_journal.save()) {setError("No se pudo guardar el espacio para usarlo sin conexión.");return;}
            m_project=space.value("project_id").toString(); m_remoteTitle=space.value("name").toString();
            remoteList();
        }); return;
    }
    const bool searching=!m_query.trimmed().isEmpty();
    const QString requestQuery=m_query, requestTree=treeKey();
    const QString endpoint=searching?"rpc/inge_drive_search_v02":QString("rpc/inge_drive_list_v02?offset=%1&limit=100").arg(m_remoteOffset);
    const QVariantMap arguments=searching?QVariantMap{{"p_query",m_query},{"p_space_id",m_space}}:
        QVariantMap{{"p_space_id",m_space},{"p_parent_node_id",m_remoteDir.isEmpty()?QVariant():QVariant(m_remoteDir)}};
    onlineRequest(endpoint,arguments,
        [this,append,searching,requestQuery,requestTree](const QVariantList &items){
            if(requestQuery!=m_query || requestTree!=treeKey()) {m_searchTimer->start();return;}
            if(!append) m_all.clear();
            for(const auto &value:items) {
                const auto f=value.toMap(); auto kind=f.value("item_kind",f.value("node_kind")).toString();
                if(kind=="BINARY_DOCUMENT") kind="FILE";
                const auto id=f.value("id").toString(),name=f.value("name").toString();
                const bool directory=kind=="SPACE" || kind=="FOLDER";
                const auto date=f.value("updated_at").toString();
                m_all.append(QVariantMap{{"id",id},{"kind",kind},{"project",f.value("project_id")},
                    {"name",name},{"path","DRIVE:"+m_space+":"+id},{"directory",directory},
                    {"node_version",f.value("node_version")},{"current_version_id",f.value("current_version_id")},
                    {"content_version",f.value("content_version")},
                    {"local_state",directory?QString():mirrorState(id,f.value("content_version").toLongLong())},
                    {"snippet",f.value("snippet")},{"sync_state","SYNCED"},
                    {"bytes",f.value("size_bytes")},{"modified",QDateTime::fromString(date,Qt::ISODate).toMSecsSinceEpoch()},
                    {"date",date.left(10)},{"extension",QFileInfo(name).suffix().toLower()},
                    {"icon",directory?"folder":"insert_drive_file"},{"remote",true}});
            }
            m_remoteOffset+=items.size(); m_moreRemote=!searching && items.size()==100;
            if(!searching && m_journal.outbox.isEmpty() && !m_journal.remember(treeKey(),m_all)) setError("No se pudo guardar la copia para uso sin conexión.");
            applyRows();
            if(!searching && !append) loadCapabilities(m_remoteDir, QStringLiteral("folder:")+treeKey());
            if(!searching && !m_space.isEmpty()) { m_uploadSpace=m_space; m_uploadParent=m_remoteDir; m_uploadTitle=m_remoteTitle; }
        });
}
// Capabilities come only from the server (get_document_structural_capabilities_v02:
// memberships, ACL, scope and structure governance, e.g. protected/system folders).
// UI hides what is not allowed; inge_drive_mutate_v03 still enforces everything.
void NothingDocuments::loadCapabilities(const QString &nodeId, const QString &path)
{
    if(!m_provider || m_space.isEmpty()) return;
    const int epoch=m_epoch;
    const QString space=m_space, tree=treeKey();
    m_provider->request("rpc/get_document_structural_capabilities_v02",
        {{"p_space_id",space},{"p_node_id",nodeId.isEmpty()?QVariant():QVariant(nodeId)}},false,
        [this,epoch,space,tree,path,nodeId](QVariantList rows,QString error,bool){
            if(epoch!=m_epoch || space!=m_space) return;
            const auto row=rows.value(0).toMap();
            QVariantMap caps;
            if(error.isEmpty() && !row.isEmpty()) {
                const bool active=row.value("lifecycle").toString().isEmpty() || row.value("lifecycle").toString()=="ACTIVE";
                caps={{"ready",true},{"lifecycle",row.value("lifecycle")},{"canCreateFolder",active && row.value("can_create_folder").toBool()},
                      {"canRenameFolder",active && row.value("can_rename").toBool()},
                      {"canDeleteFolder",active && row.value("can_trash").toBool()},
                      {"canMoveFolder",active && row.value("can_move").toBool()},
                      {"canReorderFolder",active && row.value("can_manage_structure").toBool()},
                      {"canViewFolderInfo",row.value("can_read").toBool()},
                      {"governance",row.value("structure_governance")}};
                m_nodeCaps.insert(path,caps);   // last known set, reused offline
            } else {
                caps=m_nodeCaps.value(path);    // offline: last server answer, or nothing
            }
            qInfo().noquote() << "INGE_DOC_PERMISSION path=" << path << "ready=" << caps.value("ready").toBool()
                              << "create=" << caps.value("canCreateFolder").toBool() << "rename=" << caps.value("canRenameFolder").toBool()
                              << "delete=" << caps.value("canDeleteFolder").toBool() << "governance=" << caps.value("governance").toString();
            if(path.startsWith(QStringLiteral("folder:"))) {
                if(tree!=treeKey()) return;
                m_folderCaps=caps;
                if(nodeId.isEmpty())   // space root: Dock "…" -> Nueva carpeta only if the server allows it
                    qInfo().noquote() << "INGE_DOC_HOME_CREATE_CAPABILITY space=" << space << "ready=" << caps.value("ready").toBool()
                                      << "create=" << caps.value("canCreateFolder").toBool();
            }
            ++m_capsRevision; emit changed();
        });
}
QString NothingDocuments::breadcrumb() const
{
    QStringList parts{QStringLiteral("InGe Drive")};
    const auto add=[&parts](const QString &title){ if(!title.isEmpty() && parts.last()!=title) parts.append(title); };
    for(const auto &value:m_history) {
        const auto state=value.toMap();
        if(state.value("route").toString()!="drive") { parts=QStringList{QStringLiteral("InGe Drive")}; continue; }
        add(state.value("title").toString());
    }
    if(m_route=="drive") add(m_remoteTitle);
    return parts.join(QStringLiteral(" / "));
}
void NothingDocuments::requestCapabilities(const QString &path)
{
    if(m_route!="drive") return;
    const auto entry=remoteEntry(path);
    if(entry.isEmpty() || entry.value("kind")=="SPACE") return;
    loadCapabilities(entry.value("id").toString(),path);
}
void NothingDocuments::loadMore() { if(m_route=="drive" && m_moreRemote && !m_busy) remoteList(true); }
// ===== Files Core 01E: espejo local híbrido =====
// Identidad = (space_id, node_id). El contenido vigente lo decide el servidor
// (get_binary_document_access_v01 con versión NULL). La copia local se asocia a
// content_version: igual -> se abre sin descargar; mayor -> STALE_LOCAL y se
// actualiza; sin red -> se abre la copia válida o se informa sin crash.
QString NothingDocuments::mirrorDir(const QString &space, const QString &nodeId) const
{
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)+"/inge-drive/"+m_uid+"/mirror/"+space+"/"+nodeId;
}
QVariantMap NothingDocuments::readMirror(const QString &dir) const
{
    QFile file(QDir(dir).filePath("mirror.json"));
    if(!file.open(QIODevice::ReadOnly)) return {};
    const auto manifest=QJsonDocument::fromJson(file.readAll()).object().toVariantMap();
    return QFileInfo::exists(manifest.value("file").toString()) ? manifest : QVariantMap{};
}
QString NothingDocuments::mirrorState(const QString &nodeId, qint64 remoteContentVersion) const
{
    if(m_space.isEmpty() || nodeId.isEmpty() || !QDir(mirrorDir(m_space,nodeId)).exists()) return "REMOTE_ONLY";
    const auto manifest=readMirror(mirrorDir(m_space,nodeId));
    if(manifest.isEmpty()) return "REMOTE_ONLY";
    return remoteContentVersion>0 && manifest.value("content_version").toLongLong()<remoteContentVersion ? "STALE_LOCAL" : "LOCAL_AVAILABLE";
}
void NothingDocuments::openMirrored(const QString &path, const QString &state)
{
    qInfo().noquote() << "INGE_DRIVE_BINARY state=" << state << "source=mirror";
    const auto action=m_downloadOpen; m_downloadOpen.clear();
    emit completed(action.isEmpty() ? "Archivo disponible en este dispositivo"
                   : state=="LOCAL_AVAILABLE_OFFLINE" ? "Sin conexión: se abre la copia local" : "Abierto desde la copia local",path);
    if(!action.isEmpty()) open(NothingFiles::item(path),action=="chooser",action=="share");
}
void NothingDocuments::download(const QVariantMap &entry)
{
    if(m_busy || !m_cloud || !m_provider || m_space.isEmpty() || entry.value("kind")!="FILE") { m_downloadOpen.clear(); setError("Selecciona un archivo binario dentro de un espacio online."); return; }
    const QString name=entry["name"].toString();
    if(!NothingFiles::validName(name)) { m_downloadOpen.clear(); setError("Nombre remoto inválido."); return; }
    const QString nodeId=entry.value("id").toString();
    if(QUuid(nodeId).isNull()) { m_downloadOpen.clear(); setError("Actualiza para obtener el documento."); return; }
    const QString space=m_space, mirror=mirrorDir(space,nodeId);
    const QVariantMap cached=readMirror(mirror);
    const int epoch=m_epoch;
    qInfo().noquote() << "INGE_DRIVE_BINARY state=RESOLVING_CURRENT_VERSION node=" << nodeId;
    m_busy=true; m_error.clear(); emit changed();
    m_provider->request("rpc/get_binary_document_access_v01",
        {{"p_space_id",space},{"p_document_node_id",nodeId},{"p_document_version_id",QVariant()}},false,
        [this,epoch,entry,space,nodeId,name,mirror,cached](QVariantList rows,QString error,bool retryable){
            if(epoch!=m_epoch) return;
            m_busy=false;
            if(!error.isEmpty()) {
                if(retryable && !cached.isEmpty()) { emit changed(); openMirrored(cached.value("file").toString(),"LOCAL_AVAILABLE_OFFLINE"); return; }
                m_downloadOpen.clear();
                setError(retryable ? "Sin conexión y sin copia local de este archivo." : onlineError(error));
                emit changed(); return;
            }
            const auto access=rows.value(0).toMap();
            const QString versionId=access.value("document_version_id").toString();
            const qint64 content=access.value("content_version").toLongLong();
            if(access.value("bucket")!="project-files" || access.value("storage_path").toString().isEmpty() || QUuid(versionId).isNull()) {
                m_downloadOpen.clear(); setError("No hay una versión descargable disponible."); emit changed(); return;
            }
            if(!cached.isEmpty() && cached.value("content_version").toLongLong()==content
               && cached.value("document_version_id").toString()==versionId) {
                emit changed(); openMirrored(cached.value("file").toString(),"LOCAL_AVAILABLE"); return;
            }
            qInfo().noquote() << "INGE_DRIVE_BINARY state=" << (cached.isEmpty() ? "REMOTE_ONLY" : "STALE_LOCAL")
                              << "-> DOWNLOADING node=" << nodeId << "content_version=" << content;
            const QString dir=QDir(mirror).filePath(versionId);
            if(!QDir().mkpath(dir)) { m_downloadOpen.clear(); setError("No se pudo crear la copia del archivo."); emit changed(); return; }
            const QString fileName=NothingFiles::validName(access.value("file_name").toString()) ? access.value("file_name").toString() : name;
            m_downloadEntry=entry;
            m_downloadEntry["space_id"]=space;
            m_downloadEntry["mirror_dir"]=mirror;
            m_downloadEntry["current_version_id"]=versionId;
            m_downloadEntry["content_version"]=content;
            const auto savePath=QDir(dir).filePath(fileName);
            m_busy=true; emit changed();
            m_cloud->downloadExact(access.value("bucket").toString(), access.value("storage_path").toString(),
                savePath, access.value("size_bytes").toLongLong(),
                [this,epoch,savePath](bool ok,const QString &error) {
                    if(epoch!=m_epoch) return;
                    if(ok) { finishDownload(savePath); return; }
                    m_busy=false; m_downloadOpen.clear(); m_downloadEntry.clear();
                    setError(error); emit changed();
                });
        });
}
// Files Core 01E: Node + Version canónicos (reserve -> begin -> Storage exacto
// sin upsert -> finalize) en la última carpeta de InGe Drive abierta. Nunca un
// objeto Storage huérfano. projectId se conserva por compatibilidad de firma.
void NothingDocuments::upload(const QString &localPath,const QString &,const QString &relativePath)
{
    if(!m_cloud || !m_provider || m_uid.isEmpty() || !checkPaths({localPath}) || QFileInfo(localPath).isDir()) return;
    if(m_uploadSpace.isEmpty()) { setError("Abre en InGe Drive la carpeta de destino y vuelve a intentarlo."); return; }
    QString name=relativePath.section('/',-1).trimmed();
    if(name.isEmpty()) name=QFileInfo(localPath).fileName();
    if(!NothingFiles::validName(name)) { setError("Nombre remoto inválido."); return; }
    const QString space=m_uploadSpace, parent=m_uploadParent;
    const QString mime=QMimeDatabase().mimeTypeForFile(localPath).name();
    const int epoch=m_epoch;
    m_busy=true; m_error.clear(); emit changed();
    qInfo().noquote() << "INGE_DRIVE_UPLOAD_BEGIN space=" << space << "parent=" << parent;
    const auto fail=[this,epoch](const QString &error) {
        if(epoch!=m_epoch) return;
        m_busy=false;
        qWarning().noquote() << "INGE_DRIVE_UPLOAD_FAIL code=" << error;
        setError(error=="NETWORK" ? "No se pudo subir el archivo. Reintenta con conexión." : onlineError(error));
        emit changed();
    };
    m_provider->request("rpc/reserve_binary_document_upload_v01",
        {{"p_space_id",space},{"p_parent_node_id",parent.isEmpty()?QVariant():QVariant(parent)},{"p_file_name",name},
         {"p_mime_type",mime},{"p_size_bytes",QFileInfo(localPath).size()},{"p_idempotency_key",QUuid::createUuid().toString(QUuid::WithoutBraces)}},false,
        [this,epoch,fail,localPath,mime](QVariantList rows,QString error,bool){
            if(epoch!=m_epoch) return;
            const auto slot=rows.value(0).toMap();
            const QString attempt=slot.value("attempt_id").toString(), bucket=slot.value("bucket").toString(), path=slot.value("storage_path").toString();
            if(!error.isEmpty() || QUuid(attempt).isNull() || bucket.isEmpty() || path.isEmpty()) { fail(error.isEmpty()?"UNAVAILABLE":error); return; }
            m_provider->request("rpc/begin_binary_document_upload_v01",{{"p_attempt_id",attempt}},false,
                [this,epoch,fail,localPath,mime,attempt,bucket,path](QVariantList,QString error,bool){
                    if(epoch!=m_epoch) return;
                    if(!error.isEmpty()) { fail(error); return; }
                    m_cloud->uploadExact(localPath,bucket,path,mime,[this,epoch,fail,attempt](bool ok,const QString &){
                        if(epoch!=m_epoch) return;
                        if(!ok) { fail("NETWORK"); return; }
                        m_provider->request("rpc/finalize_binary_document_upload_v01",{{"p_attempt_id",attempt}},false,
                            [this,epoch,fail](QVariantList rows,QString error,bool){
                                if(epoch!=m_epoch) return;
                                const auto done=rows.value(0).toMap();
                                if(!error.isEmpty() || done.value("attempt_status").toString()!="FINALIZADO") { fail(error.isEmpty()?"UNAVAILABLE":error); return; }
                                m_busy=false;
                                qInfo().noquote() << "INGE_DRIVE_UPLOAD_OK node=" << done.value("document_node_id").toString()
                                                  << "content_version=" << done.value("content_version").toLongLong();
                                emit completed("Archivo subido a InGe Drive",{});
                                if(m_route=="drive") refresh();
                                emit changed();
                            });
                    });
                });
        });
}
