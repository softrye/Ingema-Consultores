#include "../../../authsession.h"
#include "../../../supabaseclient.h"
#include <QCoreApplication>
#include <QBuffer>
#include <QElapsedTimer>
#include <QFile>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSettings>
#include <QStandardPaths>
#include <QTcpServer>
#include <QTcpSocket>
#include <QTemporaryDir>
#include <QThread>
#include <QUrlQuery>
#include <functional>
#include <cstdio>

namespace {
bool waitFor(const std::function<bool()> &predicate)
{
    QElapsedTimer timer; timer.start();
    while (!predicate() && timer.elapsed() < 4000) {
        QCoreApplication::processEvents(); QThread::msleep(1);
    }
    return predicate();
}
struct Request { QByteArray method, target, headers, body; QPointer<QTcpSocket> socket; };
struct Server {
    QTcpServer listener;
    QList<Request> requests;
    Server() {
        QObject::connect(&listener,&QTcpServer::newConnection,&listener,[this] {
            while (auto *socket=listener.nextPendingConnection()) {
                auto bytes=std::make_shared<QByteArray>();
                auto complete=std::make_shared<bool>(false);
                QObject::connect(socket,&QTcpSocket::readyRead,&listener,[this,socket,bytes,complete] {
                    bytes->append(socket->readAll()); if(*complete) return;
                    const int split=bytes->indexOf("\r\n\r\n"); if(split<0) return;
                    const QByteArray headers=bytes->left(split);
                    int size=0;
                    for (const auto &line:headers.split('\n'))
                        if(line.toLower().startsWith("content-length:")) size=line.mid(15).trimmed().toInt();
                    if(bytes->size()<split+4+size) return;
                    const auto first=headers.left(headers.indexOf("\r\n")).split(' ');
                    requests.append({first.value(0),first.value(1),headers,bytes->mid(split+4,size),socket});
                    *complete=true;
                });
            }
        });
        listener.listen(QHostAddress::LocalHost,0);
    }
    QString origin() const { return QStringLiteral("http://localhost:%1").arg(listener.serverPort()); }
    void respond(int index,const QByteArray &body,int status=200) {
        auto socket=requests.at(index).socket; if(!socket) return;
        socket->write(QByteArrayLiteral("HTTP/1.1 ")+QByteArray::number(status)+" Response\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: "+QByteArray::number(body.size())+"\r\n\r\n"+body);
        socket->disconnectFromHost();
    }
};
}

int authChecks()
{
    QTemporaryDir temp;
    QCoreApplication::setOrganizationName(QStringLiteral("InGeAccountTests"));
    QCoreApplication::setApplicationName(QStringLiteral("AccountChecks"));
    QSettings::setDefaultFormat(QSettings::IniFormat);
    QSettings::setPath(QSettings::IniFormat,QSettings::UserScope,temp.path());
    QSettings::setPath(QSettings::IniFormat,QSettings::SystemScope,temp.path());
    QStandardPaths::setTestModeEnabled(true);
    const QString a=QStringLiteral("11111111-1111-4111-8111-111111111111");
    const QString b=QStringLiteral("22222222-2222-4222-8222-222222222222");
    auto selectAccount=[&](const QString &id) {
        QSettings settings;
        settings.setValue(QStringLiteral("auth/current_account_id"),id);
        settings.setValue(QStringLiteral("auth/accounts_index"),QStringList{a,b});
        const QString group=QStringLiteral("auth/accounts/")+id;
        settings.setValue(group+QStringLiteral("/user_id"),id);
        settings.setValue(group+QStringLiteral("/access_token"),QStringLiteral("fixture-access"));
        settings.setValue(group+QStringLiteral("/refresh_token"),QStringLiteral("fixture-refresh"));
        settings.setValue(group+QStringLiteral("/email"),QStringLiteral("Case.Preserved@example.invalid"));
        settings.setValue(group+QStringLiteral("/profile_status"),QStringLiteral("ACTIVO"));
        settings.setValue(group+QStringLiteral("/remember_until_utc"),QDateTime::currentDateTimeUtc().addDays(1).toString(Qt::ISODate));
        settings.setValue(group+QStringLiteral("/expires_at_utc"),QDateTime::currentDateTimeUtc().addSecs(3600).toString(Qt::ISODate));
        settings.sync();
    };
    Server server;
    SupabaseClient api(server.origin(),QStringLiteral("fixture-public-key"));
    int finishedRequests=0;
    QObject::connect(api.nam(),&QNetworkAccessManager::finished,api.nam(),[&]{++finishedRequests;});
    AuthSession auth(&api);
    auto fail=[](const char *message){std::fprintf(stderr,"FAIL: %s\n",message);return 1;};
    selectAccount(a); auth.loadFromDisk();
    auth.refreshActiveSessions();
    if(!waitFor([&]{return server.requests.size()==1;})) return fail("sessions request missing");
    selectAccount(b); auth.loadFromDisk(); selectAccount(a); auth.loadFromDisk();
    server.respond(0,"[{\"id\":\"stale\",\"current\":true}]");
    if(!waitFor([&]{return !server.requests[0].socket || server.requests[0].socket->state()==QAbstractSocket::UnconnectedState;})) return fail("held reply not delivered");
    for(int i=0;i<15;++i) {QCoreApplication::processEvents();QThread::msleep(1);}
    if(!auth.activeSessions().isEmpty()) return fail("A-B-A restore accepted a session list from the old account epoch");

    int failures=0,profileOk=0,avatarOk=0;
    bool wrongEmailSignal=false;
    QObject::connect(&auth,&AuthSession::userInfoChanged,&auth,[&]{
        if(auth.email()!=QStringLiteral("Case.Preserved@example.invalid")) wrongEmailSignal=true;
    });
    QObject::connect(&auth,&AuthSession::sessionsActionFail,&auth,[&]{++failures;});
    QObject::connect(&auth,&AuthSession::profileUpdatedFail,&auth,[&]{++failures;});
    QObject::connect(&auth,&AuthSession::profileUpdatedOk,&auth,[&]{++profileOk;});
    QObject::connect(&auth,&AuthSession::profileAvatarSynced,&auth,[&]{++avatarOk;});
    auth.refreshActiveSessions();
    if(!waitFor([&]{return server.requests.size()==2;})) return fail("sessions reload missing");
    server.respond(1,"{}");
    if(!waitFor([&]{return failures==1;})) return fail("malformed session array was silently accepted");
    auth.updateUserProfile(QStringLiteral("Nombre"),QStringLiteral("Apellido"),QString());
    if(!waitFor([&]{return server.requests.size()==3;})) return fail("profile update missing");
    const auto profileBody=QJsonDocument::fromJson(server.requests[2].body).object().value(QStringLiteral("data")).toObject();
    if(profileBody.value(QStringLiteral("full_name")).toString()!=QStringLiteral("Nombre Apellido")
       || profileBody.value(QStringLiteral("phone")).toString()!=QString() || profileBody.contains(QStringLiteral("area"))) return fail("profile payload escaped the personal-field contract");
    const QByteArray profileReply=QJsonDocument(QJsonObject{{"id",a},{"email","case.preserved@example.invalid"},
        {"user_metadata",QJsonObject{{"nombre","Nombre"},{"apellido","Apellido"},{"full_name","Nombre Apellido"},{"phone",""}}}}).toJson();
    server.respond(2,profileReply);
    if(!waitFor([&]{return profileOk==1;})) return fail("profile success missing");
    if(wrongEmailSignal || auth.email()!=QStringLiteral("Case.Preserved@example.invalid") || auth.fullName()!=QStringLiteral("Nombre Apellido") || !auth.phone().isEmpty()) return fail("profile refresh changed email spelling or failed to clear phone");

    int warnings=0;
    QObject::connect(&auth,&AuthSession::profileAvatarSyncWarning,&auth,[&](const QString &message){
        if(!message.isEmpty()) ++warnings;
    });
    int cursor=3;
    auto next=[&]() { return waitFor([&]{return server.requests.size()>cursor;}) ? cursor++ : -1; };
    auto authAvatarReply=[&](bool clear) {
        return QJsonDocument(QJsonObject{{"id",a},{"user_metadata",QJsonObject{
            {"avatar_url",clear ? QJsonValue(QJsonValue::Null) : QJsonValue(QStringLiteral("storage://avatars/")+a+"/avatar.jpg")},
            {"avatar_path",clear ? QJsonValue(QJsonValue::Null) : QJsonValue(a+"/avatar.jpg")}}}}).toJson();
    };
    auto imageBytes=[](QColor color) {
        QImage image(32,32,QImage::Format_RGB32); image.fill(color);
        QByteArray bytes; QBuffer buffer(&bytes); buffer.open(QIODevice::WriteOnly); image.save(&buffer,"PNG"); return bytes;
    };
    const QString png=temp.filePath(QStringLiteral("avatar.png"));
    QImage image(2400,1600,QImage::Format_RGB32); image.fill(Qt::blue); image.save(png,"PNG");
    const QString path=a+QStringLiteral("/avatar.jpg");
    auth.updateUserAvatar(QUrl::fromLocalFile(png));
    int index=next(); if(index<0) return fail("avatar upload missing");
    const auto upload=server.requests[index];
    const auto prepared=QImage::fromData(upload.body);
    if(upload.target!="/storage/v1/object/avatars/"+path.toUtf8()
       || !upload.headers.toLower().contains("content-type: image/jpeg")
       || !upload.headers.toLower().contains("x-upsert: true")
       || !upload.body.startsWith(QByteArray::fromHex("ffd8")) || upload.body.size()>5242880
       || prepared.isNull() || prepared.width()>1024 || prepared.height()>1024 || prepared.width()!=prepared.height())
        return fail("avatar upload used wrong path, encoding, dimensions or upsert");
    if(avatarOk!=0) return fail("avatar success emitted before server confirmation");
    server.respond(index,"{}",403);
    if(!waitFor([&]{return warnings==1;}) || avatarOk || !auth.avatarPath().isEmpty()) return fail("failed upload claimed success");

    auth.updateUserAvatar(QUrl::fromLocalFile(png));
    index=next(); if(index<0) return fail("avatar upload retry missing"); server.respond(index,"{}");
    index=next(); if(index<0) return fail("avatar metadata missing");
    const auto avatarMetadata=QJsonDocument::fromJson(server.requests[index].body).object().value("data").toObject();
    if(avatarMetadata.value("avatar_url").toString()!=QStringLiteral("storage://avatars/")+path
       || avatarMetadata.value("avatar_path").toString()!=path) return fail("Auth reference is not stable");
    server.respond(index,"{}"); // HTTP 200 with no acknowledgement must fail.
    if(!waitFor([&]{return warnings==2;}) || avatarOk) return fail("malformed metadata claimed success");
    auth.updateUserAvatar(QUrl::fromLocalFile(png));
    index=next(); if(index<0) return fail("avatar second retry missing"); server.respond(index,"{}");
    index=next(); if(index<0) return fail("avatar metadata retry missing"); server.respond(index,authAvatarReply(false));
    index=next(); if(index<0) return fail("legacy cleanup missing");
    const auto oldPaths=QJsonDocument::fromJson(server.requests[index].body).object().value("prefixes").toArray();
    if(server.requests[index].method!="DELETE" || oldPaths.size()!=3 || oldPaths.contains(path))
        return fail("legacy cleanup could delete canonical avatar");
    if(avatarOk) return fail("success preceded server cleanup");
    server.respond(index,"[]");
    index=next(); if(index<0 || avatarOk!=1) return fail("private signature missing");
    if(server.requests[index].target!="/storage/v1/object/sign/avatars/"+path.toUtf8()
       || QJsonDocument::fromJson(server.requests[index].body).object().value("expiresIn").toInt()!=300)
        return fail("private signature endpoint or expiry wrong");
    const QByteArray signatureReply=QJsonDocument(QJsonObject{{"signedURL","/object/sign/avatars/"+path+"?token=fixture-signature"}}).toJson();
    const QString staged=auth.avatarUrl();
    server.respond(index,signatureReply);
    index=next(); if(index<0) return fail("download skipped because a local cache exists");
    if(server.requests[index].method!="GET" || server.requests[index].headers.contains("Bearer fixture-access"))
        return fail("signed download transport wrong");
    server.respond(index,imageBytes(Qt::green));
    if(!waitFor([&]{return auth.avatarUrl()!=staged && QUrl(auth.avatarUrl()).isLocalFile();})) return fail("private download did not replace cache");
    if(QImage(QUrl(auth.avatarUrl()).toLocalFile()).pixelColor(0,0).green()<200) return fail("downloaded image not displayed");
    const QString firstCache=auth.avatarUrl();
    auth.updateUserProfile("Nombre","Apellido","");
    index=next(); if(index<0) return fail("profile refresh missing"); server.respond(index,profileReply);
    index=next(); if(index<0) return fail("signature refresh missing"); server.respond(index,signatureReply);
    index=next(); if(index<0) return fail("stable path did not refresh");
    server.respond(index,imageBytes(Qt::red));
    if(!waitFor([&]{return auth.avatarUrl()!=firstCache;})) return fail("remote replacement stayed stale");
    const QString freshCache=auth.avatarUrl();
    auth.updateUserProfile("Nombre","Apellido","");
    index=next(); if(index<0) return fail("profile refresh before account race missing"); server.respond(index,profileReply);
    index=next(); if(index<0) return fail("signature before race missing"); server.respond(index,signatureReply);
    index=next(); if(index<0) return fail("held download missing");
    selectAccount(b); auth.loadFromDisk();
    if(auth.avatarUrl()==freshCache) return fail("account B inherited account A avatar");
    selectAccount(a); auth.loadFromDisk();
    server.respond(index,imageBytes(Qt::blue));
    if(!waitFor([&]{return finishedRequests>=cursor;})) return fail("held response not processed");
    if(auth.avatarUrl()!=freshCache) return fail("A-B-A accepted a stale avatar download");
    if(!QUrl(auth.avatarUrl()).toLocalFile().contains("/"+a+"/") || auth.avatarUrl().contains("token="))
        return fail("avatar cache not scoped to account or leaks signed URL");
    { QSettings settings;
      if(settings.value("auth/avatar_url_local").toString().contains("token=")) return fail("signed credentials persisted"); }

    // A personal-field response can contain an older full Auth user snapshot.
    auth.updateUserProfile("Nombre","Apellido","");
    const int heldPersonal=next(); if(heldPersonal<0) return fail("held personal update missing");
    auth.clearUserAvatar();
    index=next(); if(index<0) return fail("avatar delete missing");
    const auto deletePaths=QJsonDocument::fromJson(server.requests[index].body).object().value("prefixes").toArray();
    if(server.requests[index].method!="DELETE" || server.requests[index].target!="/storage/v1/object/avatars"
       || !deletePaths.contains(path) || deletePaths.size()!=4) return fail("avatar delete omitted canonical/legacy keys");
    server.respond(index,"{}",403);
    if(!waitFor([&]{return warnings==3;}) || auth.avatarPath().isEmpty() || avatarOk!=1) return fail("delete failure hidden");
    auth.clearUserAvatar();
    index=next(); if(index<0) return fail("avatar delete retry missing"); server.respond(index,"[]");
    index=next(); if(index<0) return fail("avatar metadata clear missing");
    const int heldClearMetadata=index;
    // A session refresh may read profiles while clear is already in flight.
    auth.refreshSessionWithRefreshToken();
    index=next(); if(index<0) return fail("refresh during clear missing");
    server.respond(index,QJsonDocument(QJsonObject{{"access_token","fixture-access"},{"refresh_token","fixture-refresh"},
        {"expires_in",3600},{"user",QJsonObject{{"id",a},{"email","Case.Preserved@example.invalid"}}}}).toJson());
    const int heldBackend=next(); if(heldBackend<0) return fail("profile read during clear missing");
    server.respond(heldClearMetadata,authAvatarReply(true));
    if(!waitFor([&]{return auth.avatarPath().isEmpty() && auth.avatarUrl().isEmpty() && avatarOk==2;})) return fail("clear not confirmed");
    const int beforePersonal=profileOk;
    server.respond(heldPersonal,authAvatarReply(false));
    if(!waitFor([&]{return profileOk==beforePersonal+1;})) return fail("held personal response not processed");
    if(!auth.avatarPath().isEmpty() || !auth.avatarUrl().isEmpty()) return fail("old personal-field response resurrected a deleted avatar");
    server.respond(heldBackend,QJsonDocument(QJsonArray{QJsonObject{{"id",a},{"status","ACTIVO"},
        {"email","Case.Preserved@example.invalid"},{"avatar_url","storage://avatars/"+path}}}).toJson());
    index=next(); if(index<0 || server.requests[index].target!="/rest/v1/rpc/list_my_project_memberships_v01") return fail("old profiles response resurrected a deleted avatar");
    server.respond(index,"[]");
    index=next(); if(index<0 || !server.requests[index].target.startsWith("/rest/v1/projects?")) return fail("refresh project check missing");
    server.respond(index,"[]");
    if(!waitFor([&]{return auth.profileActive();}) || !auth.avatarPath().isEmpty()) return fail("profile refresh lost latest avatar state");
    const QString oversized=temp.filePath(QStringLiteral("oversized.png"));
    { QFile file(oversized); file.open(QIODevice::WriteOnly); file.resize(5242881); }
    auth.updateUserAvatar(QUrl::fromLocalFile(oversized));
    if(!waitFor([&]{return warnings==4;})) return fail("oversized source not rejected");
    const QString bmp=temp.filePath(QStringLiteral("avatar.bmp")); image.save(bmp,"BMP");
    auth.updateUserAvatar(QUrl::fromLocalFile(bmp));
    if(!waitFor([&]{return warnings==5;})) return fail("unsupported format not rejected");
    if(server.requests.size()!=cursor) return fail("invalid image reached transport");

    auto switchWithProfile=[&](const QString &id,bool hasPhoto) {
        auth.switchToSavedAccount(id);
        int item=next(); if(item<0 || !server.requests[item].target.startsWith("/rest/v1/profiles?")) return false;
        const QJsonObject profile{{"id",id},{"status","ACTIVO"},{"email","Case.Preserved@example.invalid"},
            {"avatar_url",hasPhoto ? QJsonValue("storage://avatars/"+id+"/avatar.jpg") : QJsonValue(QJsonValue::Null)}};
        server.respond(item,QJsonDocument(QJsonArray{profile}).toJson());
        // Real profile-loading route: signing/download can interleave with membership checks.
        const int expected=hasPhoto ? 4 : 2;
        for(int j=0;j<expected;++j) {
            item=next(); if(item<0) return false;
            const auto &request=server.requests[item];
            if(request.target.startsWith("/storage/v1/object/sign/avatars/") && request.method=="POST") {
                if(!request.target.contains(id.toUtf8()+"/avatar.jpg")) return false;
                server.respond(item,QJsonDocument(QJsonObject{{"signedURL","/object/sign/avatars/"+id+"/avatar.jpg?token=fixture-signature"}}).toJson());
            } else if(request.method=="GET" && request.target.startsWith("/storage/v1/object/sign/avatars/")) {
                server.respond(item,imageBytes(Qt::yellow));
            } else if(request.target.startsWith("/rest/v1/rpc/list_my_project_memberships_v01")
                      || request.target.startsWith("/rest/v1/projects?")) server.respond(item,"[]");
            else return false;
        }
        return waitFor([&]{return auth.userId()==id && (hasPhoto ? QUrl(auth.avatarUrl()).isLocalFile() : auth.avatarUrl().isEmpty());});
    };
    // A different device has no cache or metadata; profiles alone must start the download.
    if(!switchWithProfile(b,true)) return fail("other account did not download automatically from profiles");
    const QString bCache=auth.avatarUrl();
    if(!QUrl(bCache).toLocalFile().contains("/"+b+"/")) return fail("account B used another cache directory");
    // A remote delete must override a previously saved cache on the next profile load.
    if(!switchWithProfile(a,false) || !switchWithProfile(b,false)) return fail("remote avatar removal did not clear the cached preview");
    if(QFile::exists(QUrl(bCache).toLocalFile())) return fail("remote removal left a cache that could be rediscovered on login");
    if(!auth.avatarPath().isEmpty()) return fail("remote avatar removal retained a stale reference");
    if(!switchWithProfile(a,false)) return fail("account A restoration failed");
    int sessionOk=0;
    QObject::connect(&auth,&AuthSession::sessionsActionOk,&auth,[&]{++sessionOk;});
    auth.revokeSession(QStringLiteral("33333333-3333-4333-8333-333333333333"));
    index=next(); if(index<0) return fail("session revocation request missing");
    if(server.requests[index].target!="/rest/v1/rpc/revoke_my_auth_session_v01"
       || !QJsonDocument::fromJson(server.requests[index].body).object().contains("p_session_id")) return fail("session revocation request contract wrong");
    server.respond(index,"{\"ok\":true}");
    index=next(); if(index<0 || sessionOk!=1) return fail("session list not refreshed after revocation");
    server.respond(index,"[]");
    if(!waitFor([&]{return !auth.sessionsBusy();})) return fail("session refresh did not finish");
    auth.signOutOtherSessions();
    index=next(); if(index<0) return fail("other-session signout missing");
    const QUrl logout(QString::fromUtf8(server.requests[index].target));
    if(logout.path()!=QStringLiteral("/auth/v1/logout") || QUrlQuery(logout).queryItemValue("scope")!=QStringLiteral("others")) return fail("signout scope could close the current account");
    server.respond(index,"{}");
    index=next(); if(index<0 || sessionOk!=2) return fail("other-session signout not confirmed");
    server.respond(index,"[]");
    if(!waitFor([&]{return !auth.sessionsBusy();}) || auth.userId()!=a) return fail("other-session signout changed current account");
    std::puts("PASS: account epochs, profile, exact email, private avatar upload/sign/delete and input limits");
    return 0;
}
