#pragma once
#include "../documents/storageprovider.h"
#include "googledriveexporttransport.h"
#include <QSet>
#include <QSaveFile>
#include <QStandardPaths>
#include <QCryptographicHash>
#include <QDir>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QDateTime>
#include <QGuiApplication>
#include <QNetworkInformation>
#include <QUuid>
#include <QDebug>
#include <algorithm>

// Existing durable outbox. Explicit provider keeps Google XLSX separate from
// historical InGeDrive objects without another queue or destructive migration.
class RenditionExportService final : public QObject {
public:
    using Completion = std::function<void(bool, const QString &)>;
    static RenditionExportService *shared(SupabaseClient *api, AuthSession *auth) {
        static auto *service = new RenditionExportService(api, auth, auth);
        return service;
    }
    RenditionExportService(SupabaseClient *api, AuthSession *auth, QObject *parent = nullptr)
        : QObject(parent), m_auth(auth), m_provider(api,auth,this), m_google(this) {
        connect(auth,&AuthSession::accountSwitchStarted,this,[this](const QString &){ resetAccount(); });
        connect(auth,&AuthSession::loggedOut,this,[this]{ resetAccount(); });
        connect(auth,&AuthSession::loggedChanged,this,[this]{ schedule(); });
        connect(auth,&AuthSession::backendAccessChanged,this,[this]{
            if(selectAccount()) {
                const auto old=m_rows;
                for(auto it=m_rows.begin();it!=m_rows.end();++it) {
                    auto row=it.value().toMap();
                    if(row.value("error")=="AUTH_REQUIRED") {row["state"]="PENDING";row["nextRetryAt"]=0;it.value()=row;}
                }
                if(!save()) m_rows=old;
            }
            schedule();
        });
        if(auto *app=qobject_cast<QGuiApplication*>(QCoreApplication::instance()))
            connect(app,&QGuiApplication::applicationStateChanged,this,[this](Qt::ApplicationState state){
                if(state==Qt::ApplicationActive) schedule();
            });
        QNetworkInformation::loadDefaultBackend();
        if(auto *network=QNetworkInformation::instance())
            connect(network,&QNetworkInformation::reachabilityChanged,this,[this](QNetworkInformation::Reachability state){
                if(state==QNetworkInformation::Reachability::Online) schedule();
            });
        m_retry.setSingleShot(true);
        connect(&m_retry,&QTimer::timeout,this,[this]{ tick(); });
        schedule();
    }
    bool enqueue(const QString &path,const QString &project,const QString &rendition,
                 const QString &version,const QString &format) {
        if(QUuid(rendition).isNull() || QUuid(version).isNull() || (format!="xlsx" && format!="pdf")) return false;
        return enqueueDocument(path,project,"Export/Rendiciones/"+rendition+"/"+version+"/"+QFileInfo(path).fileName(),{});
    }
    bool enqueueDocument(const QString &path,const QString &project,const QString &logicalPath,
                         Completion completion,const QString &requiresRemotePath = {},const QString &calicataId = {},
                         const QString &provider = "SUPABASE", bool interactive = true,
                         const QString &displayFileName = {}) {
        if(provider!="SUPABASE" && provider!="GOOGLE_DRIVE") return false;
        if(!displayFileName.isEmpty() && (!validPath(displayFileName)
            || QFileInfo(displayFileName).fileName()!=displayFileName)) return false;
        if(provider=="GOOGLE_DRIVE" && !path.endsWith(".xlsx",Qt::CaseInsensitive)) return false;
        if(!selectAccount() || QUuid(project).isNull() || !validPath(logicalPath)) return false;
        if(!calicataId.isEmpty() && QUuid(calicataId).isNull()) return false;
        const bool calicataExport=logicalPath.startsWith("Calicatas/exports/");
        QFile source(path);
        if(!source.open(QIODevice::ReadOnly) || source.size()<1 || source.size()>50LL*1024*1024) return false;
        const auto bytes=source.readAll();
        if(bytes.size()!=source.size()) return false;
        const QString hash=digest(bytes);
        const QString id=digest((project+'/'+logicalPath+'/'+hash
            +(provider=="GOOGLE_DRIVE"?"/GOOGLE_DRIVE":QString())).toUtf8());
        if(m_rows.contains(id)) {
            if(provider=="GOOGLE_DRIVE" && interactive) m_googleInteractive.insert(id);
            auto row=m_rows.value(id).toMap();
            // A first local export can be enqueued before sync assigns its remote id.
            // Bind that identity when publishCalicata supplies the same operation.
            if(calicataExport && !calicataId.isEmpty() && row.value("calicataId").toString().isEmpty()
                && row.value("document_version_id").toString().isEmpty()) {
                const auto previous=m_rows;
                row["calicataId"]=QUuid(calicataId).toString(QUuid::WithoutBraces);m_rows[id]=row;
                if(!save()) {m_rows=previous;return false;}
            }
            if(row.value("state")=="UPLOADED") {
                if(completion) QTimer::singleShot(0,this,[completion]{completion(true,{});});
            } else {
                if(completion) m_completions[id].append(std::move(completion));
                if(row.value("state")=="ERROR") {
                    const auto previous=m_rows;row["state"]="PENDING";row["nextRetryAt"]=0;row["syncState"]="PENDING_SYNC";
                    m_rows[id]=row;if(!save()) {m_rows=previous;return false;}
                }
                schedule();
            }
            return true;
        }
        const QString directory=QFileInfo(m_path).absolutePath()+"/mirror/"+id;
        const QString local=directory+'/'+QFileInfo(logicalPath).fileName();
        if(!QDir().mkpath(directory)) return false;
        QSaveFile mirror(local);
        if(!mirror.open(QIODevice::WriteOnly) || mirror.write(bytes)!=bytes.size() || !mirror.commit()) return false;
        qint64 sequence=1;
        for(const auto &value:m_rows) sequence=qMax(sequence,value.toMap().value("sequence").toLongLong()+1);
        QString mime=QMimeDatabase().mimeTypeForFile(path).name();
        if(path.endsWith(".xlsx",Qt::CaseInsensitive)) mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
        m_rows[id]=QVariantMap{{"id",id},{"ownerId",m_user},{"projectId",project},{"localPath",local},
            {"logicalPath",logicalPath},{"remotePath",QString()},{"fileName",displayFileName.isEmpty()?QFileInfo(logicalPath).fileName():displayFileName},
            {"mimeType",mime},{"size",bytes.size()},{"sha256",hash},{"state","PENDING"},{"syncState","PENDING_SYNC"},
            {"requestId",uuid()},{"sequence",sequence},{"updatedAt",now()},{"requiresRemotePath",requiresRemotePath},
            {"provider",provider}};
        if(calicataExport) {
            auto row=m_rows[id].toMap();row["destinationKind"]="CALICATA_EXPORTS";
            row["calicataId"]=calicataId.isEmpty()?QString():QUuid(calicataId).toString(QUuid::WithoutBraces);
            m_rows[id]=row;
        }
        if(!save()) {m_rows.remove(id);return false;}
        if(provider=="GOOGLE_DRIVE" && interactive) m_googleInteractive.insert(id);
        if(completion) m_completions[id].append(std::move(completion));
        log(m_rows[id].toMap(),"pending"); schedule(); return true;
    }
    // Record generation before writing. The final workbook is atomically renamed
    // into this path, so recovery never adopts partially generated XLSX bytes.
    bool prepareGeneration(const QString &path,const QString &project,const QString &logicalStem,const QString &calicataId = {},
                           const QString &provider = "SUPABASE", const QString &displayFileName = {}) {
        if(!selectAccount() || QUuid(project).isNull() || !validPath(logicalStem+".xlsx")) return false;
        if(!calicataId.isEmpty() && QUuid(calicataId).isNull()) return false;
        const QString id="generation-"+digest(path.toUtf8());
        m_rows[id]=QVariantMap{{"id",id},{"ownerId",m_user},{"projectId",project},{"localPath",path},
            {"logicalStem",logicalStem},{"state","GENERATING"},{"syncState","PENDING_SYNC"},{"calicataId",calicataId},
            {"provider",provider},{"displayFileName",displayFileName}};
        if(save()) return true;
        m_rows.remove(id);return false;
    }
    void generationQueued(const QString &path) {
        const auto old=m_rows;m_rows.remove("generation-"+digest(path.toUtf8()));
        if(!save()) m_rows=old;
    }
    QVariantMap resultFor(const QString &project,const QString &logicalPath,const QString &provider = "SUPABASE") {
        if(!selectAccount()) return {};
        QVariantMap found;
        for(const auto &value:m_rows) {
            const auto row=value.toMap();
            if(row.value("projectId")==project && row.value("logicalPath",row.value("remotePath"))==logicalPath
                && row.value("provider","SUPABASE")==provider
                && (found.isEmpty() || row.value("sequence").toLongLong()>=found.value("sequence").toLongLong())) found=row;
        }
        if(found.isEmpty()) return {};
        return {{"success",found.value("syncState")=="SYNCED"},{"fileName",found.value("fileName")},
            {"localPhysicalPath",found.value("localPath")},{"localPath",found.value("localPath")},
            {"remoteLogicalPath",logicalPath},{"remotePath",found.value("remotePath")},
            {"remoteFolderPath",found.value("remoteFolderPath")},
            {"provider",found.value("provider","SUPABASE")},{"webViewLink",found.value("webViewLink")},
            {"remoteId",provider=="GOOGLE_DRIVE"?found.value("googleFileId"):found.value("document_node_id")},
            {"version",found.value("document_version_id")},
            {"awaitingRetry",found.value("state")=="PENDING" && !found.value("error").toString().isEmpty()},
            {"syncState",found.value("syncState","PENDING_SYNC")},{"error",found.value("error")}};
    }
    // Explicit retry releases errors after permissions/auth have been repaired.
    bool retryDocument(const QString &project,const QString &logicalPath,const QString &provider) {
        if(!selectAccount()) return false;
        for(const auto &id:m_rows.keys()) {
            auto row=m_rows[id].toMap();
            if(row.value("projectId")!=project || row.value("logicalPath")!=logicalPath
                || row.value("provider","SUPABASE")!=provider) continue;
            if(row.value("state")=="UPLOADED" || row.value("state")=="UPLOADING") return true;
            const auto old=m_rows;
            if(row.value("error")=="STALE_VERSION" && row.value("document_version_id").toString().isEmpty()) {
                row.remove("reservationMode"); row.remove("existingNodeId");
                row.remove("expectedNodeVersion"); row.remove("expectedContentVersion"); row["requestId"]=uuid();
            }
            row["state"]="PENDING";row["syncState"]="PENDING_SYNC";row["error"]=QString();row["nextRetryAt"]=0;
            m_rows[id]=row;if(!save()) {m_rows=old;return false;}
            if(provider=="GOOGLE_DRIVE") m_googleInteractive.insert(id);
            schedule();return true;
        }
        return false;
    }
    void retry() {
        if(!selectAccount()) return;
        const auto old=m_rows;
        for(auto it=m_rows.begin();it!=m_rows.end();++it) {
            auto row=it.value().toMap();
            if(row.value("state")=="ERROR" || row.value("state")=="PENDING") {
                row["state"]="PENDING";row["syncState"]="PENDING_SYNC";row["nextRetryAt"]=0;it.value()=row;
            }
        }
        if(!save()) {m_rows=old;return;} schedule();
    }
    // Aggregate ordering remains in RenditionLocalStore; binary transport is shared.
    SupabaseStorageProvider *storage() { return &m_provider; }
private:
    static QString uuid() {return QUuid::createUuid().toString(QUuid::WithoutBraces);}
    static QString now() {return QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);}
    static QString digest(const QByteArray &bytes) {return QString::fromLatin1(QCryptographicHash::hash(bytes,QCryptographicHash::Sha256).toHex());}
    static bool validPath(const QString &path) {
        if(path.isEmpty() || path.startsWith('/') || path.contains('\\')) return false;
        for(const auto &part:path.split('/'))
            if(part.isEmpty() || part=="." || part==".." || part.contains(QRegularExpression("[\\x00-\\x1f]"))) return false;
        return QFileInfo(path).fileName().size()<=255;
    }
    void resetAccount() {++m_epoch;m_google.cancel();m_googleInteractive.clear();m_retry.stop();m_active.clear();m_user.clear();m_path.clear();m_rows.clear();m_completions.clear();}
    void schedule() {QTimer::singleShot(0,this,[this]{tick();});}
    void log(const QVariantMap &row,const char *state) {
        qInfo().noquote()<<"INGE_DRIVE_EXPORT owner="<<(row.value("logicalPath").toString().startsWith("Calicatas/")?"calicatas":"renditions")
            <<"project="<<row.value("projectId").toString()<<"file="<<row.value("id").toString()<<"state="<<state;
    }
    bool selectAccount() {
        if(!m_auth->logged() || QUuid(m_auth->userId()).isNull()) return false;
        if(m_user==m_auth->userId()) return true;
        resetAccount();m_user=m_auth->userId();
        const QString directory=QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)+"/rendition-exports/"+m_user;
        if(!QDir().mkpath(directory)) {resetAccount();return false;}
        m_path=directory+"/outbox.json";QFile file(m_path);
        if(file.exists()) {
            if(!file.open(QIODevice::ReadOnly)) {resetAccount();return false;}
            QJsonParseError error;const auto doc=QJsonDocument::fromJson(file.readAll(),&error);
            if(error.error!=QJsonParseError::NoError || !doc.isObject()) {resetAccount();return false;}
            m_rows=doc.toVariant().toMap();
        }
        // Upgrade pending metadata in place. Completed legacy objects remain untouched.
        for(auto it=m_rows.begin();it!=m_rows.end();++it) {
            auto row=it.value().toMap();if(row.value("state")=="UPLOADED" || row.value("state")=="GENERATING") continue;
            if(!row.contains("logicalPath")) {row["logicalPath"]=row.value("remotePath");row["remotePath"]=QString();}
            if(row.value("requestId").toString().isEmpty()) row["requestId"]=uuid();
            if(row.value("fileName").toString().isEmpty()) row["fileName"]=QFileInfo(row.value("logicalPath").toString()).fileName();
            if(row.value("mimeType").toString().isEmpty()) row["mimeType"]=QMimeDatabase().mimeTypeForFile(row.value("localPath").toString()).name();
            if(!row.contains("size")) row["size"]=QFileInfo(row.value("localPath").toString()).size();
            row["ownerId"]=m_user;
            if(row.value("state")=="UPLOADING") row["state"]="PENDING";
            row["syncState"]=row.value("state")=="ERROR"?"ERROR":row.value("state")=="CONFLICT"?"CONFLICT":"PENDING_SYNC";
            it.value()=row;
        }
        if(!save()) {resetAccount();return false;}return true;
    }
    bool save() {
        if(m_path.isEmpty()) return false;
        QSaveFile file(m_path);const auto bytes=QJsonDocument::fromVariant(m_rows).toJson(QJsonDocument::Compact);
        return file.open(QIODevice::WriteOnly) && file.write(bytes)==bytes.size() && file.commit();
    }
    bool checkpoint(QVariantMap row) {
        const auto old=m_rows;row["updatedAt"]=now();m_rows[m_active]=row;
        if(save()) return true;
        m_rows=old;const auto id=m_active;m_active.clear();notify(id,false,"LOCAL_PERSISTENCE_FAILED");return false;
    }
    void notify(const QString &id,bool ok,const QString &error) {
        const auto callbacks=ok?m_completions.take(id):m_completions.value(id);
        for(const auto &callback:callbacks) if(callback) callback(ok,error);
    }
    void failed(const QString &error,bool retryable) {
        auto row=m_rows.value(m_active).toMap();
        const bool retryBaselineMissing=error=="STALE_VERSION" && !row.value("retryKey").toString().isEmpty();
        const bool conflict=!retryBaselineMissing && (error.contains("CONFLICT") || error.contains("STALE_VERSION"));
        row["state"]=conflict?"CONFLICT":retryable?"PENDING":"ERROR";
        row["syncState"]=conflict?"CONFLICT":retryable?"PENDING_SYNC":"ERROR";row["error"]=error;
        if(retryBaselineMissing) row["error"]="BACKEND_RETRY_BASELINE_OR_VERSION_CONFLICT";
        const int failures=qMin(10,row.value("failures").toInt()+1);row["failures"]=failures;
        const int delay=qMin(900000,15000*(1<<qMin(failures,6)));
        row["nextRetryAt"]=retryable?QDateTime::currentMSecsSinceEpoch()+delay:0;
        const auto id=m_active;if(!checkpoint(row)) return;
        log(row,retryable?"pending":"error");m_active.clear();notify(id,false,error);schedule();
    }
    void request(const QString &endpoint,const QVariantMap &args,std::function<void(QVariantMap)> done,bool get=false) {
        const auto epoch=m_epoch;const auto user=m_user;const auto id=m_active;
        m_provider.request(endpoint,args,get,[this,epoch,user,id,done](QVariantList rows,QString error,bool retryable){
            if(epoch!=m_epoch || user!=m_auth->userId() || !m_auth->logged() || id!=m_active) return;
            if(!error.isEmpty()) {failed(error,retryable || error=="UPLOAD_RESERVATION_EXPIRED");return;}
            if(rows.size()!=1) {failed("INVALID_RESPONSE",false);return;}done(rows.first().toMap());
        });
    }
    void tick() {
        if(!selectAccount() || !m_active.isEmpty()) return;
        // Recover the generation/enqueue crash boundary without a second journal.
        for(const auto &key:m_rows.keys()) {
            const auto intent=m_rows.value(key).toMap();
            if(intent.value("state")!="GENERATING") continue;
            QFile file(intent.value("localPath").toString());
            if(!file.open(QIODevice::ReadOnly) || file.size()<1) continue;
            const auto hash=digest(file.readAll());
            if(enqueueDocument(file.fileName(),intent.value("projectId").toString(),
                intent.value("logicalStem").toString()+'_'+hash.left(20)+".xlsx",{},{},intent.value("calicataId").toString(),
                intent.value("provider","SUPABASE").toString(),false,
                intent.value("displayFileName").toString())) generationQueued(file.fileName());
        }
        QStringList ids=m_rows.keys();
        std::stable_sort(ids.begin(),ids.end(),[this](const QString &a,const QString &b){
            if(m_googleInteractive.contains(a)!=m_googleInteractive.contains(b)) return m_googleInteractive.contains(a);
            return m_rows[a].toMap().value("sequence").toLongLong()<m_rows[b].toMap().value("sequence").toLongLong();
        });
        qint64 next=0;
        for(const auto &id:ids) {
            auto row=m_rows[id].toMap();const auto state=row.value("state").toString();
            if(state=="UPLOADED" || state=="ERROR" || state=="CONFLICT" || state=="GENERATING") continue;
            const auto retryAt=row.value("nextRetryAt").toLongLong();
            if(retryAt>QDateTime::currentMSecsSinceEpoch()) {next=next==0?retryAt:qMin(next,retryAt);continue;}
            const auto dependency=row.value("requiresRemotePath").toString();
            if(!dependency.isEmpty()) {
                bool ready=false;for(const auto &value:m_rows) {const auto other=value.toMap();
                    if(other.value("projectId")==row.value("projectId") && other.value("logicalPath",other.value("remotePath"))==dependency && other.value("state")=="UPLOADED") ready=true;}
                if(!ready) continue;
            }
            m_active=id;m_recoveryAttempts=0;QFile file(row.value("localPath").toString());
            if(QUuid(row.value("projectId").toString()).isNull() || !file.open(QIODevice::ReadOnly)
                || file.size()!=row.value("size").toLongLong() || digest(file.readAll())!=row.value("sha256").toString()) {failed("LOCAL_MIRROR_INVALID",false);return;}
            row["state"]="UPLOADING";row["syncState"]="UPLOADING";row["error"]=QString();
            if(!checkpoint(row)) return;
            log(row,"uploading");
            if(row.value("provider")=="GOOGLE_DRIVE") {
                const auto epoch=m_epoch;const auto user=m_user;const auto active=m_active;
                m_google.upload(row,[this,epoch,user,active](const QVariantMap &saved) {
                    if(epoch!=m_epoch || user!=m_auth->userId() || !m_auth->logged() || active!=m_active) return false;
                    return checkpoint(saved);
                },[this,epoch,user,active](QVariantMap result,QString error,bool retryable) {
                    if(epoch!=m_epoch || user!=m_auth->userId() || !m_auth->logged() || active!=m_active) return;
                    if(!error.isEmpty()) {failed(error,retryable);return;}
                    auto saved=m_rows[active].toMap();
                    for(auto it=result.cbegin();it!=result.cend();++it) saved[it.key()]=it.value();
                    saved["state"]="UPLOADED";saved["syncState"]="SYNCED";saved["error"]=QString();
                    if(!checkpoint(saved)) return;
                    log(saved,"synced");m_active.clear();notify(active,true,{});schedule();
                },m_googleInteractive.remove(id)>0);
                return;
            }
            if(row.value("destinationKind")=="CALICATA_EXPORTS" && row.value("document_version_id").toString().isEmpty()) {
                resolveCalicataDestination();
            } else if(row.value("spaceId").toString().isEmpty()) {
                const auto project=row.value("projectId").toString();
                request("document_spaces?select=id,project_id&space_type=eq.PROJECT&project_id=eq."+project+"&status=eq.ACTIVO&limit=2",{},[this,project](QVariantMap space){
                    if(QUuid(space.value("id").toString()).isNull() || space.value("project_id")!=project) {failed("PROJECT_SPACE_REQUIRED",false);return;}
                    auto row=m_rows[m_active].toMap();row["spaceId"]=space.value("id");if(checkpoint(row)) reserve();
                },true);
            } else reserve();
            return;
        }
        if(next>0) {
            const qint64 delayMs=qBound(qint64(1000),next-QDateTime::currentMSecsSinceEpoch(),qint64(900000));
            m_retry.start(int(delayMs)); // <= 900000 ms, fits int
        }
    }
    void resolveCalicataDestination() {
        const auto row=m_rows[m_active].toMap();
        const QString calicata=row.value("calicataId").toString();
        request("rpc/ensure_my_calicata_exports_folder_v01",
            {{"p_project_id",row.value("projectId")},{"p_calicata_id",calicata.isEmpty()?QVariant():QVariant(calicata)}},
            [this](QVariantMap folder) {
                if(QUuid(folder.value("space_id").toString()).isNull() || QUuid(folder.value("folder_id").toString()).isNull()
                    || folder.value("display_path").toString().isEmpty()) {failed("CALICATA_EXPORTS_INVALID_FOLDER",false);return;}
                auto row=m_rows[m_active].toMap();row["spaceId"]=folder.value("space_id");
                row["parentNodeId"]=folder.value("folder_id");
                row["remoteFolderPath"]=folder.value("display_path");
                if(checkpoint(row)) reserve();
            });
    }
    void reserve() {
        const auto row=m_rows[m_active].toMap();
        if(!row.value("retryKey").toString().isEmpty()) {retryReservation();return;}
        if(row.value("destinationKind")=="CALICATA_EXPORTS" && QUuid(row.value("parentNodeId").toString()).isNull()) {
            failed("CALICATA_EXPORTS_FOLDER_REQUIRED",false);return;
        }
        if(row.value("destinationKind")=="CALICATA_EXPORTS" && row.value("fileName").toString().endsWith(".xlsx",Qt::CaseInsensitive)) {
            reserveCalicataWorkbook(); return;
        }
        request("rpc/reserve_binary_document_upload_v01",{{"p_space_id",row.value("spaceId")},{"p_parent_node_id",row.value("parentNodeId")},
            {"p_file_name",row.value("fileName")},{"p_mime_type",row.value("mimeType")},{"p_size_bytes",row.value("size")},
            {"p_idempotency_key",row.value("requestId")}},[this](QVariantMap reservation){acceptReservation(reservation);});
    }
    void reserveCalicataWorkbook() {
        const auto row=m_rows[m_active].toMap();
        if(!row.value("reservationMode").toString().isEmpty()) {reserveWorkbookVersion();return;}
        auto quoted=[](QString text){return '"'+text.replace("\\","\\\\").replace("\"","\\\"")+'"';};
        const auto name=row.value("fileName").toString();
        const auto filter="(name.eq."+quoted(name)+",name.eq."+quoted(QFileInfo(name).completeBaseName())+")";
        const QString endpoint="document_nodes?select=id,mime_type,node_version,binary_content_version&space_id=eq."
            +row.value("spaceId").toString()+"&parent_id=eq."+row.value("parentNodeId").toString()
            +"&node_kind=eq.BINARY_DOCUMENT&lifecycle=eq.ACTIVE&or="+QString::fromLatin1(QUrl::toPercentEncoding(filter))+"&limit=2";
        const auto epoch=m_epoch; const auto user=m_user; const auto active=m_active;
        m_provider.request(endpoint,{},true,[this,epoch,user,active](QVariantList nodes,QString error,bool retryable){
            if(epoch!=m_epoch || user!=m_auth->userId() || !m_auth->logged() || active!=m_active) return;
            if(!error.isEmpty()) {failed(error,retryable);return;}
            if(nodes.size()>1) {failed("NAME_CONFLICT",false);return;}
            auto current=m_rows[active].toMap();
            if(nodes.isEmpty()) current["reservationMode"]="CREATE";
            else {
                const auto node=nodes.first().toMap();
                if(QUuid(node.value("id").toString()).isNull() || node.value("mime_type")!=current.value("mimeType")) {
                    failed("NAME_CONFLICT",false);return;
                }
                current["reservationMode"]="VERSION"; current["existingNodeId"]=node.value("id");
                current["expectedNodeVersion"]=node.value("node_version");
                current["expectedContentVersion"]=node.value("binary_content_version");
            }
            // Save the reservation mode before RPC: retry after lost responses is idempotent.
            if(checkpoint(current)) reserveWorkbookVersion();
        });
    }
    void reserveWorkbookVersion() {
        const auto row=m_rows[m_active].toMap();
        QVariantMap args{{"p_space_id",row.value("spaceId")},{"p_file_name",row.value("fileName")},
            {"p_mime_type",row.value("mimeType")},{"p_size_bytes",row.value("size")},{"p_idempotency_key",row.value("requestId")}};
        const bool version=row.value("reservationMode")=="VERSION";
        if(version) {
            args["p_document_node_id"]=row.value("existingNodeId");
            args["p_expected_node_version"]=row.value("expectedNodeVersion");
            args["p_expected_content_version"]=row.value("expectedContentVersion");
        } else args["p_parent_node_id"]=row.value("parentNodeId");
        request(version?"rpc/reserve_binary_document_version_v01":"rpc/reserve_binary_document_upload_v01",args,
                [this](QVariantMap reservation){acceptReservation(reservation);});
    }
    void acceptReservation(const QVariantMap &reservation,bool renewed=false) {
        auto row=m_rows[m_active].toMap();
        const auto node=reservation.value("document_node_id").toString(),version=reservation.value("document_version_id").toString();
        const auto path=reservation.value("storage_path").toString();
        const QString prefix="spaces/"+row.value("spaceId").toString()+"/nodes/"+node+"/versions/"+version+'/';
        if(QUuid(node).isNull() || QUuid(version).isNull() || QUuid(reservation.value("attempt_id").toString()).isNull()
            || reservation.value("bucket")!="project-files" || !path.startsWith(prefix) || path.split('/').size()!=7
            || !validPath(path) || reservation.value("size_bytes").toLongLong()!=row.value("size").toLongLong()
            || reservation.value("mime_type")!=row.value("mimeType")
            || (!row.value("document_version_id").toString().isEmpty() && row.value("document_version_id")!=version)) {failed("INVALID_RESERVATION",false);return;}
        for(auto it=reservation.cbegin();it!=reservation.cend();++it) row[it.key()]=it.value();
        row["remotePath"]=path;if(!checkpoint(row)) return;
        const auto status=row.value("attempt_status").toString();
        if(status=="FINALIZADO") {finalize();return;}
        const auto expiry=QDateTime::fromString(row.value("upload_expires_at").toString(),Qt::ISODateWithMs);
        if(!expiry.isValid()) {failed("INVALID_RESERVATION_EXPIRY",false);return;}
        if(status=="EXPIRADO" || status=="FALLIDO" || expiry<=QDateTime::currentDateTimeUtc()) {
            // New attempt key only: document/version/storage path remain identical.
            if(++m_recoveryAttempts>2) {failed("RESERVATION_EXPIRY_NOT_RECOVERED",false);return;}
            row["retryKey"]=uuid();if(checkpoint(row)) retryReservation();return;
        }
        if(status=="INDETERMINADO") {failed("OBJECT_CONFLICT",false);return;}
        if(status=="OBJETO_CARGADO") {finalize();return;}
        if(status!="RESERVADO" && status!="EN_CARGA") {failed("INVALID_ATTEMPT_STATUS",false);return;}
        if(!renewed && expiry<=QDateTime::currentDateTimeUtc().addSecs(90)) {
            request("rpc/renew_document_upload_lease_controlled",{{"p_attempt_id",row.value("attempt_id")}},[this,row](QVariantMap lease) mutable {
                if(lease.value("attempt_id")!=row.value("attempt_id")) {failed("INVALID_LEASE_RESPONSE",false);return;}
                for(auto it=lease.cbegin();it!=lease.cend();++it) row[it.key()]=it.value();
                acceptReservation(row,true);
            });return;
        }
        request("rpc/begin_binary_document_upload_v01",{{"p_attempt_id",row.value("attempt_id")}},[this](QVariantMap begun){
            if(begun.value("attempt_id")!=m_rows[m_active].toMap().value("attempt_id") || begun.value("attempt_status")!="EN_CARGA") {failed("INVALID_BEGIN_RESPONSE",false);return;}
            upload();
        });
    }
    void retryReservation() {
        const auto row=m_rows[m_active].toMap();
        request("rpc/retry_document_upload_controlled",{{"p_document_version_id",row.value("document_version_id")},
            {"p_idempotency_key",row.value("retryKey")}},[this](QVariantMap reservation){acceptReservation(reservation);});
    }
    void upload() {
        const auto row=m_rows[m_active].toMap();const auto epoch=m_epoch;const auto user=m_user;
        m_provider.uploadReserved(row.value("localPath").toString(),"project-files",row.value("remotePath").toString(),row.value("mimeType").toString(),
            [this,epoch,user](bool ok,QString error,bool retryable){
                if(epoch!=m_epoch || user!=m_auth->userId() || !m_auth->logged()) return;
                if(!ok) {failed(error,retryable);return;}finalize();
            });
    }
    void finalize() {
        const auto row=m_rows[m_active].toMap();
        request("rpc/finalize_binary_document_upload_v01",{{"p_attempt_id",row.value("attempt_id")}},[this](QVariantMap confirmed){
            auto row=m_rows[m_active].toMap();
            if(confirmed.value("attempt_status")!="FINALIZADO" || confirmed.value("document_version_id")!=row.value("document_version_id")
                || confirmed.value("document_node_id")!=row.value("document_node_id")) {failed("INVALID_FINALIZE_RESPONSE",false);return;}
            for(auto it=confirmed.cbegin();it!=confirmed.cend();++it) row[it.key()]=it.value();
            row["state"]="UPLOADED";row["syncState"]="SYNCED";row["error"]=QString();
            const auto id=m_active;if(!checkpoint(row)) return;
            log(row,"synced");m_active.clear();notify(id,true,{});schedule();
        });
    }
    AuthSession *m_auth;
    SupabaseStorageProvider m_provider;
    GoogleDriveExportTransport m_google;
    QSet<QString> m_googleInteractive;
    QTimer m_retry;
    int m_epoch=0,m_recoveryAttempts=0;
    QString m_user,m_path,m_active;
    QVariantMap m_rows;
    QHash<QString,QList<Completion>> m_completions;
};
