#pragma once
#include <QObject>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonObject>
#include <QFile>
#include <QRegularExpression>
#include <QVariantList>
#include <QVariantMap>
#include <QTimer>
#include <functional>
#include "../../supabaseclient.h"
#include "../../authsession.h"

class IStorageProvider {
public:
    using Completion=std::function<void(QVariantList,QString,bool)>;
    virtual ~IStorageProvider()=default;
    virtual void request(const QString &endpoint,const QVariantMap &body,bool get,Completion done)=0;
};

// Metadata transport boundary. Caller owns outbox policy and account epochs.
class SupabaseStorageProvider final : public QObject, public IStorageProvider {
public:
    SupabaseStorageProvider(SupabaseClient *api,AuthSession *auth,QObject *parent)
        :QObject(parent),m_api(api),m_auth(auth) {}
    void request(const QString &endpoint,const QVariantMap &body,bool get,Completion done) override {
        if(!m_auth || !m_auth->logged()) { done({},"AUTH_REQUIRED",false); return; }
        auto request=m_api->makeRequest(m_api->restUrl(endpoint),m_auth->accessToken(),20000);
        auto *reply=get?m_api->nam()->get(request):m_api->nam()->post(request,QJsonDocument::fromVariant(body).toJson(QJsonDocument::Compact));
        QTimer::singleShot(25000,reply,[reply]{if(reply->isRunning()) reply->abort();});
        connect(reply,&QNetworkReply::finished,this,[reply,done=std::move(done)] {
            const auto raw=reply->readAll(); const auto status=reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            const auto failure=reply->error(); reply->deleteLater();
            QJsonParseError parse; const auto doc=QJsonDocument::fromJson(raw,&parse);
            if(failure!=QNetworkReply::NoError || status<200 || status>=300) {
                const auto message=doc.object().value("message").toString();
                const auto code=QRegularExpression("^[A-Z][A-Z0-9_]{2,100}$").match(message).hasMatch()
                    ? message : "DRIVE_HTTP_"+QString::number(status);
                done({},status==401?"AUTH_REQUIRED":status==403?"FORBIDDEN":code,
                     status==0 || status==408 || status==429 || status>=500); return;
            }
            if(parse.error!=QJsonParseError::NoError || !doc.isArray()) {done({},"INVALID_RESPONSE",false);return;}
            done(doc.toVariant().toList(),{},false);
        });
    }
    // Shared immutable binary transport. A duplicate is only permission to
    // reconcile via the domain finalize RPC, never proof that a file is synced.
    using UploadCompletion=std::function<void(bool,QString,bool)>;
    void uploadReserved(const QString &localPath,const QString &bucket,const QString &objectPath,
                        const QString &mime,UploadCompletion done) {
        if(!m_api || !m_auth || !m_auth->logged() || m_auth->accessToken().isEmpty()) {
            done(false,"AUTH_REQUIRED",false); return;
        }
        const auto parts=objectPath.split('/');
        if(bucket!="project-files" || parts.contains("..") || parts.contains(".")
            || parts.contains("") || objectPath.contains('\\')) {
            done(false,"INVALID_STORAGE_PATH",false); return;
        }
        QFile file(localPath);
        if(!file.open(QIODevice::ReadOnly) || file.size()<1 || file.size()>50LL*1024*1024) {
            done(false,"LOCAL_FILE_INVALID",false); return;
        }
        QStringList encoded;
        for(const auto &part:parts) encoded.append(QString::fromLatin1(QUrl::toPercentEncoding(part)));
        auto request=m_api->makeRequest(QUrl(m_api->projectUrl()+"/storage/v1/object/"+bucket+"/"+encoded.join('/')),
                                        m_auth->accessToken(),60000);
        request.setHeader(QNetworkRequest::ContentTypeHeader,mime);
        request.setRawHeader("x-upsert","false");
        const auto bytes=file.readAll();
        if(bytes.size()!=file.size()) {done(false,"LOCAL_READ_FAILED",false);return;}
        auto *reply=m_api->nam()->post(request,bytes);
        QTimer::singleShot(65000,reply,[reply]{if(reply->isRunning()) reply->abort();});
        connect(reply,&QNetworkReply::finished,reply,&QObject::deleteLater);
        connect(reply,&QNetworkReply::finished,this,[reply,bucket,objectPath,done=std::move(done)] {
            const int status=reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            QJsonParseError parse;
            const auto document=QJsonDocument::fromJson(reply->readAll(),&parse);
            const auto body=document.object();
            const bool valid=parse.error==QJsonParseError::NoError && document.isObject();
            const bool duplicate=valid && (status==400 || status==409)
                && (body.value("error")=="Duplicate" || body.value("code")=="Duplicate"
                    || body.value("message")=="The resource already exists");
            const bool uploaded=valid && reply->error()==QNetworkReply::NoError && status>=200 && status<300
                && body.value("Key").toString()==bucket+"/"+objectPath;
            if(uploaded || duplicate) { done(true,{},false); return; }
            done(false,status==401?"AUTH_REQUIRED":status==403?"FORBIDDEN":
                 status>=200 && status<300?"INVALID_UPLOAD_RESPONSE":"STORAGE_HTTP_"+QString::number(status),
                 status==0 || status==408 || status==429 || status>=500);
        });
    }
private:
    SupabaseClient *m_api; AuthSession *m_auth;
};
