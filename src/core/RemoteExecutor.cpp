#include "RemoteExecutor.h"
#include "InGeCore.h"
#include "../../authsession.h"
#include "../../supabaseclient.h"
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonArray>
#include <QUrlQuery>
#include <QSaveFile>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QDir>
#include <QUuid>
#include <QFutureWatcher>
#include <QtConcurrent>

namespace inge::core {
RemoteExecutor::RemoteExecutor(SupabaseClient *api,AuthSession *auth,QObject *parent)
    :QObject(parent),m_api(api),m_auth(auth) {
    m_timer.setInterval(2500);
    connect(&m_timer,&QTimer::timeout,this,&RemoteExecutor::tick);
    connect(auth,&AuthSession::loggedChanged,this,&RemoteExecutor::selectAccount);
    connect(auth,&AuthSession::currentAccountChanged,this,&RemoteExecutor::selectAccount);
}
void RemoteExecutor::start() {
    if(!InGeCore::instance().initializeLightweight()) return;
    InGeCore::instance().setExecutor(this);
    selectAccount(); m_timer.start(); tick();
}
void RemoteExecutor::selectAccount() {
    const QString user=m_auth->logged()?m_auth->userId():QString();
    if(user==m_user) return;
    const auto old=m_pending.keys();
    ++m_epoch; m_pending.clear(); m_user=user; m_online=false; m_healthBusy=false; m_healthNext=0;
    for(const auto &id:old) emit completed(id,{},QStringLiteral("ACCOUNT_CHANGED"));
    m_journal.clear();
    InGeCoreContext context; context.authenticatedUserId=user;
    InGeCore::instance().updateContext(context);
    if(!user.isEmpty()) {
        const QString dir=QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)+"/inge-core/"+user;
        QDir().mkpath(dir); m_journal=dir+"/outbox.json";
        QFile f(m_journal);
        if(f.open(QIODevice::ReadOnly)) {
            const auto items=QJsonDocument::fromJson(f.readAll()).array();
            for(const auto &v:items) {
                const auto body=v.toObject(); const auto id=body.value("p_request_id").toString();
                if(!id.isEmpty()) m_pending.insert(id,{body,QDateTime::currentMSecsSinceEpoch(),0,false,false});
            }
        }
    }
    emit healthChanged();
}
void RemoteExecutor::persist() {
    if(m_journal.isEmpty()) return;
    QJsonArray list; for(const auto &pending:m_pending) list.append(pending.body);
    QSaveFile file(m_journal);
    if(!file.open(QIODevice::WriteOnly) || file.write(QJsonDocument(list).toJson(QJsonDocument::Compact))<0 || !file.commit())
        qWarning("INGE_CORE_OUTBOX_WRITE_FAILED");
}
bool RemoteExecutor::canExecute(const Request &request) const {
    return request.allowRemote && !m_user.isEmpty() && request.context.authenticatedUserId==m_user;
}
ExecutorHealth RemoteExecutor::health() const { return m_online?ExecutorHealth::READY:ExecutorHealth::NOT_AVAILABLE; }
Response RemoteExecutor::execute(const Request &request) {
    Response response; response.requestId=request.requestId;
    if(!canExecute(request) || request.requestId.isEmpty() || m_pending.size()>=6) {
        response.status=Status::FAILED; response.errorCode="AI_UNAVAILABLE"; return response;
    }
    if(!m_pending.contains(request.requestId)) {
        const auto skill=request.skill==Skill::Calicatas?"Calicatas":request.skill==Skill::Drive?"Drive":"Renditions";
        auto payload = request.payload;
        payload.insert("context", request.context.toVariantMap());
        QJsonObject body{{"p_request_id",request.requestId},{"p_skill",skill},{"p_operation",request.operation},
            {"p_payload",QJsonObject::fromVariantMap(payload)},{"p_priority",int(request.priority)}};
        if(!QUuid(request.context.activeProjectId).isNull()) body.insert("p_project_id",request.context.activeProjectId);
        m_pending.insert(request.requestId,{body,QDateTime::currentMSecsSinceEpoch(),0,false,false}); persist();
    }
    response.status=Status::QUEUED; response.source=Source::Remote; tick(); return response;
}
void RemoteExecutor::finish(const QString &id,const QVariantMap &result,const QString &error) {
    m_pending.remove(id); persist(); emit completed(id,result,error);
}
bool RemoteExecutor::cancel(const QString &id) {
    if(!m_pending.contains(id)) return false;
    auto *reply=m_api->nam()->post(m_api->makeRequest(m_api->restUrl("rpc/inge_ai_cancel"),m_auth->accessToken()),
        QJsonDocument(QJsonObject{{"p_request_id",id}}).toJson(QJsonDocument::Compact));
    connect(reply,&QNetworkReply::finished,reply,&QObject::deleteLater);
    finish(id,{},"CANCELLED"); return true;
}
void RemoteExecutor::tick() {
    if(m_user.isEmpty() || !m_timer.isActive()) return;
    const auto now=QDateTime::currentMSecsSinceEpoch(); const auto epoch=m_epoch;
    if(!m_healthBusy && now>=m_healthNext) {
        m_healthBusy=true; m_healthNext=now+20000;
        auto *reply=m_api->nam()->get(m_api->makeRequest(m_api->restUrl("inge_ai_workers?select=heartbeat_at&enabled=eq.true"),m_auth->accessToken()));
        QTimer::singleShot(15000,reply,[reply]{if(reply->isRunning())reply->abort();});
        connect(reply,&QNetworkReply::finished,this,[this,reply,epoch]{
            const auto rows=QJsonDocument::fromJson(reply->readAll()).array(); reply->deleteLater();
            if(epoch!=m_epoch) return;
            m_healthBusy=false; bool ready=false;
            for(const auto &v:rows) {
                const auto beat=QDateTime::fromString(v.toObject().value("heartbeat_at").toString(),Qt::ISODateWithMs);
                ready |= beat.isValid() && beat.secsTo(QDateTime::currentDateTimeUtc())>=0 && beat.secsTo(QDateTime::currentDateTimeUtc())<90;
            }
            if(ready!=m_online){m_online=ready;emit healthChanged();}
        });
    }
    for(const auto &id:m_pending.keys()) {
        auto &p=m_pending[id];
        if(p.busy || now<p.next) continue;
        if(now-p.started>600000){cancel(id);continue;}
        p.busy=true; p.next=now+5000; const bool submitted=p.submitted;
        QNetworkReply *reply=nullptr;
        if(!submitted) reply=m_api->nam()->post(m_api->makeRequest(m_api->restUrl("rpc/inge_ai_submit"),m_auth->accessToken()),QJsonDocument(p.body).toJson(QJsonDocument::Compact));
        else {
            auto url=m_api->restUrl("inge_ai_jobs"); QUrlQuery q;
            q.addQueryItem("select","id,status,result,error_code"); q.addQueryItem("request_id","eq."+id);
            q.addQueryItem("user_id","eq."+m_user); url.setQuery(q);
            reply=m_api->nam()->get(m_api->makeRequest(url,m_auth->accessToken()));
        }
        QTimer::singleShot(25000,reply,[reply]{if(reply->isRunning())reply->abort();});
        connect(reply,&QNetworkReply::finished,this,[this,reply,id,epoch,submitted]{
            const auto raw=reply->readAll(); const auto code=reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            const auto error=reply->error(); reply->deleteLater();
            if(epoch!=m_epoch || !m_pending.contains(id)) return;
            auto &p=m_pending[id]; p.busy=false;
            if(error!=QNetworkReply::NoError) {
                if(code>=400 && code<500 && code!=429){finish(id,{},"AI_BUS_REJECTED_"+QString::number(code));return;}
                p.next=QDateTime::currentMSecsSinceEpoch()+15000; return;
            }
            const auto doc=QJsonDocument::fromJson(raw);
            const auto row=submitted?doc.array().isEmpty()?QJsonObject():doc.array().at(0).toObject():doc.object();
            if(row.isEmpty()){p.submitted=false;return;}
            p.submitted=true;
            const auto status=row.value("status").toString();
            if(status=="SUCCEEDED") {
                if(p.body.value("p_skill").toString()=="Drive") {
                    const auto context=p.body.value("p_payload").toObject().value("context").toObject();
                    const QJsonObject args{{"p_job_id",row.value("id")},{"p_node_id",context.value("entity_id")},
                        {"p_version_id",context.value("entity").toObject().value("version_id")}};
                    p.next=QDateTime::currentMSecsSinceEpoch()+15000; p.busy=true;
                    auto *publish=m_api->nam()->post(m_api->makeRequest(m_api->restUrl("rpc/inge_drive_publish_index_v02"),m_auth->accessToken()),QJsonDocument(args).toJson(QJsonDocument::Compact));
                    QTimer::singleShot(25000,publish,[publish]{if(publish->isRunning())publish->abort();});
                    connect(publish,&QNetworkReply::finished,this,[this,publish,id,epoch]{
                        const bool ok=publish->error()==QNetworkReply::NoError;
                        const auto code=publish->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt(); publish->deleteLater();
                        if(epoch!=m_epoch || !m_pending.contains(id)) return;
                        if(ok) finish(id,{{"indexed",true}},{});
                        else if(code>=400 && code<500 && code!=429) finish(id,{},"INDEX_VERSION_CHANGED_OR_REJECTED");
                        else m_pending[id].busy=false;
                    });
                } else finish(id,row.value("result").toObject().toVariantMap(),{});
            }
            else if(status=="FAILED" || status=="CANCELLED") finish(id,{},row.value("error_code").toString(status));
        });
    }
}
QString RemoteExecutor::interpretCalicata(const QVariantMap &snapshot) {
    auto payload = snapshot;
    payload.insert("analysis_purpose", "GEOTECHNICAL_INTERPRETATION");
    payload.insert("summary_instruction", QStringLiteral(
        "En summary redacta una interpretación geotécnica breve del perfil registrado, "
        "en español, como texto listo para el campo de la ficha, con sus intervalos, materiales, "
        "origen y nivel freático documentados. Usa un máximo de 1000 caracteres. "
        "Distingue observaciones de inferencias y señala datos faltantes. "
        "La profundidad solicitada es el límite de la ficha, no confirma estratos sin describir. "
        "No supongas relleno antrópico, resistencia, capacidad portante, estabilidad ni ensayos. "
        "No recalcules espesores ni alteres clasificaciones. No añadas listas de revisión a summary."));
    return reviewCalicata(payload);
}

QString RemoteExecutor::reviewCalicata(const QVariantMap &snapshot) {
    const QString id=QUuid::createUuid().toString(QUuid::WithoutBraces);
    Request request; request.requestId=id; request.skill=Skill::Calicatas; request.operation="review";
    request.context=InGeCore::instance().context(); request.context.activeModule="calicatas";
    const auto header=snapshot.value("header").toMap();
    request.context.activeProjectId=header.value("projectId",header.value("project_id")).toString();
    request.context.activeEntityId=header.value("codigo").toString();
    request.context.currentFields=header;
    request.context.entity={{"strata",snapshot.value("cortes")}};
    request.payload=snapshot; request.allowRemote=true;
    const auto response=InGeCore::instance().submit(request);
    if(response.status!=Status::QUEUED) QTimer::singleShot(0,this,[this,id,response]{emit completed(id,{},response.errorCode);});
    return id;
}
void RemoteExecutor::analyzeEvidence(const QString &id,const QVariantList &attachments,const QVariantMap &context) {
    auto *watcher=new QFutureWatcher<QVariantMap>(this); const auto epoch=m_epoch;
    connect(watcher,&QFutureWatcher<QVariantMap>::finished,this,[this,watcher,id,epoch,context]{
        const auto payload=watcher->result(); watcher->deleteLater();
        if(epoch!=m_epoch){emit completed(id,{},"ACCOUNT_CHANGED");return;}
        if(payload.contains("error")){emit completed(id,{},payload.value("error").toString());return;}
        Request request; request.requestId=id; request.skill=Skill::Renditions; request.operation="smartfill";
        request.context=InGeCore::instance().context(); request.context.activeModule="renditions";
        request.context.activeProjectId=context.value("project_id").toString();
        request.context.activeEntityId=context.value("entity_id").toString();
        request.context.entity=context.value("entity").toMap();
        request.context.currentFields=context.value("current_fields").toMap();
        request.context.rules=context.value("rules").toMap();
        request.context.relatedHistory=context.value("related_history").toList().mid(0,20);
        if(context.value("module")=="drive") {request.skill=Skill::Drive;request.operation="summarize";request.context.activeModule="drive";}
        request.payload=payload; request.allowRemote=true;
        const auto response=InGeCore::instance().submit(request);
        if(response.status!=Status::QUEUED) emit completed(id,{},response.errorCode);
    });
    watcher->setFuture(QtConcurrent::run([attachments]{
        QVariantList evidence; qint64 total=0;
        if(attachments.isEmpty() || attachments.size()>6) return QVariantMap{{"error","EVIDENCE_COUNT_LIMIT"}};
        for(const auto &v:attachments) {
            const auto row=v.toMap(); auto path=row.value("localUri",row.value("local_uri")).toString();
            if(path.startsWith("file:")) path=QUrl(path).toLocalFile();
            const auto base=QFileInfo(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)).canonicalFilePath();
            const auto canonical=QFileInfo(path).canonicalFilePath();
            if(base.isEmpty() || !canonical.startsWith(base+"/")) return QVariantMap{{"error","EVIDENCE_PATH_DENIED"}};
            QFile file(canonical); total+=file.size();
            if(total>8000000 || !file.open(QIODevice::ReadOnly)) return QVariantMap{{"error","EVIDENCE_READ_LIMIT"}};
            evidence.append(QVariantMap{{"id",row.value("localId",QString::number(evidence.size()))},
                {"name",QFileInfo(path).fileName()},{"data",QString::fromLatin1(file.readAll().toBase64())}});
        }
        return QVariantMap{{"evidences",evidence}};
    }));
}
void RemoteExecutor::indexDocument(const QString &path,const QString &node,const QString &version,const QString &project) {
    if(QUuid(node).isNull() || QUuid(version).isNull()) return;
    const QString id="drive-index:"+node+":"+version;
    if(m_pending.contains(id)) return;
    analyzeEvidence(id,{QVariantMap{{"localUri",path},{"localId",version}}},
        {{"module","drive"},{"project_id",project},{"entity_id",node},{"entity",QVariantMap{{"version_id",version}}}});
}
}
