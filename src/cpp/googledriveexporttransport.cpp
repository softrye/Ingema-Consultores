#include "googledriveexporttransport.h"
#include <QCoreApplication>
#include <QGuiApplication>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QCryptographicHash>
#include <QSettings>
#include <QTimer>
#include <QUuid>
#include <QUrl>
#include <QDebug>
#include <QRegularExpression>
#ifdef Q_OS_ANDROID
#include <QJniObject>
#include <QJniEnvironment>
#endif

namespace {
QPointer<GoogleDriveExportTransport> transport;
const QString folderId = QStringLiteral("1UJnOr5Ef5TYdtP_g0HTRcRGIr0TgfeuX");
const QString fileFields = QStringLiteral("id,name,size,mimeType,parents,md5Checksum,appProperties,webViewLink,trashed");
const QString xlsxMime = QStringLiteral("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
}
GoogleDriveExportTransport::GoogleDriveExportTransport(QObject *parent) : QObject(parent), m_network(this) {
    transport = this;
}
void GoogleDriveExportTransport::dispatchAuthorization(const QString &id, const QString &token,
                                                       const QString &picked, const QString &error) {
    QMetaObject::invokeMethod(QCoreApplication::instance(), [id, token, picked, error] {
        if (transport) transport->authorized(id, token, picked, error);
    }, Qt::QueuedConnection);
}
#ifdef Q_OS_ANDROID
extern "C" JNIEXPORT void JNICALL
Java_com_ingema_ingeplus_GoogleDriveAuthorization_nativeAuthorized(JNIEnv *, jclass, jstring id,
                                                                 jstring token, jstring picked, jstring error) {
    GoogleDriveExportTransport::dispatchAuthorization(QJniObject(id).toString(), QJniObject(token).toString(),
                                                      QJniObject(picked).toString(), QJniObject(error).toString());
}
#endif
void GoogleDriveExportTransport::cancel() {
    ++m_epoch;
#ifdef Q_OS_ANDROID
    if (!m_request.isEmpty()) {
        auto activity = QNativeInterface::QAndroidApplication::context();
        auto id = QJniObject::fromString(m_request);
        QJniObject::callStaticMethod<void>("com/ingema/ingeplus/GoogleDriveAuthorization", "cancel",
            "(Landroid/app/Activity;Ljava/lang/String;)V", activity.object(), id.object<jstring>());
        QJniEnvironment env; if (env->ExceptionCheck()) env->ExceptionClear();
    }
#endif
    m_done = {}; m_checkpoint = {}; m_request.clear(); m_token.clear(); m_bytes.clear();
    if (m_reply) { m_reply->abort(); m_reply.clear(); }
}
void GoogleDriveExportTransport::upload(const QVariantMap &row, Checkpoint checkpoint, Completion done, bool interactive) {
    cancel();
    m_row = row; m_checkpoint = std::move(checkpoint); m_done = std::move(done);
    m_interactive = interactive; m_triedPicker = false; m_afterUpload = false;
    QFile file(row.value("localPath").toString());
    if (!file.open(QIODevice::ReadOnly) || file.size() < 1 || file.size() > 50LL*1024*1024) {
        finish({}, "No se pudo leer el Excel privado."); return;
    }
    m_bytes = file.readAll();
    if (m_bytes.size() != row.value("size").toLongLong()
        || QString::fromLatin1(QCryptographicHash::hash(m_bytes, QCryptographicHash::Sha256).toHex()) != row.value("sha256").toString()) {
        finish({}, "El Excel privado no coincide con la exportación encolada."); return;
    }
    m_account = QSettings().value("google-drive/" + row.value("ownerId").toString() + "/account").toString();
    if (m_account.isEmpty() && !interactive) {
        finish({}, "Autoriza Google Drive tocando Reintentar en la exportación."); return;
    }
    authorize(m_account.isEmpty());
}
void GoogleDriveExportTransport::authorize(bool picker) {
    m_picker = picker; m_triedPicker |= picker;
    m_request = QUuid::createUuid().toString(QUuid::WithoutBraces);
#ifdef Q_OS_ANDROID
    auto activity = QNativeInterface::QAndroidApplication::context();
    // Public certificate fingerprint only. Never include account, token or Intent extras.
    const auto identity = QJniObject::callStaticObjectMethod(
        "com/ingema/ingeplus/GoogleDriveAuthorization", "signingIdentity",
        "(Landroid/app/Activity;)Ljava/lang/String;", activity.object());
    {
        QJniEnvironment env;
        if (env->ExceptionCheck()) env->ExceptionClear();
        else if (identity.isValid()) {
            const auto parts = identity.toString().split('|');
            if (parts.size()==2 && QRegularExpression("^[A-F0-9]{2}(:[A-F0-9]{2}){19}$").match(parts[1]).hasMatch())
                qInfo().noquote() << "INGE_GOOGLE_OAUTH_APK package=" << parts[0] << "sha1=" << parts[1];
        }
    }
    auto id = QJniObject::fromString(m_request), account = QJniObject::fromString(m_account), target = QJniObject::fromString(folderId);
    QJniObject::callStaticMethod<void>("com/ingema/ingeplus/GoogleDriveAuthorization", "authorize",
        "(Landroid/app/Activity;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;ZZ)V",
        activity.object(), id.object<jstring>(), account.object<jstring>(), target.object<jstring>(),
        jboolean(picker), jboolean(m_interactive));
    QJniEnvironment env;
    if (env->ExceptionCheck()) { env->ExceptionClear(); finish({}, "No se pudo iniciar Google Identity Services."); return; }
    const auto epoch = m_epoch;
    const auto requestId = m_request;
    QTimer::singleShot(180000, this, [this, epoch, requestId] {
        if (epoch == m_epoch && m_request == requestId) {
            auto done = std::move(m_done); cancel();
            if (done) done({}, "La autorización Google no terminó. Reintenta al cerrar su pantalla.", false);
        }
    });
#else
    finish({}, "La autorización Google de esta integración requiere Android.");
#endif
}
void GoogleDriveExportTransport::authorized(const QString &id, const QString &token, const QString &picked, const QString &error) {
    if (id != m_request || !m_done) return;
    m_request.clear();
    const auto status = QRegularExpression("código (-?[0-9]+)").match(error);
    qInfo().noquote() << "INGE_GOOGLE_AUTH_RESULT state=" << (error.isEmpty()?"received":"error")
                     << "status=" << (status.hasMatch()?status.captured(1):"unspecified");
    if (!error.isEmpty()) { finish({}, error); return; }
    if (token.isEmpty()) { finish({}, "Google no devolvió autorización para Drive."); return; }
    if (m_picker && picked.split(',', Qt::SkipEmptyParts) != QStringList{folderId}) {
        finish({}, "Selecciona la carpeta de destino 01_CALICATAS y confirma el acceso. Si no aparece, usa la cuenta de Lechemayo o comparte esa carpeta con la cuenta elegida como Editor."); return;
    }
    m_token = token; folder();
}
void GoogleDriveExportTransport::request(const QByteArray &method, const QString &path, const QByteArray &body,
                                        const QByteArray &mime, std::function<void(int, QJsonObject)> next) {
    QNetworkRequest req(QUrl("https://www.googleapis.com/" + path));
    req.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::ManualRedirectPolicy);
    req.setTransferTimeout(90000);
    req.setRawHeader("Authorization", "Bearer " + m_token.toUtf8());
    if (!mime.isEmpty()) req.setRawHeader("Content-Type", mime);
    auto *reply = m_network.sendCustomRequest(req, method, body); m_reply = reply;
    const auto epoch = m_epoch;
    connect(reply, &QNetworkReply::finished, this, [this, reply, epoch, next] {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        auto object = QJsonDocument::fromJson(reply->readAll()).object();
        reply->deleteLater();
        if (epoch != m_epoch || !m_done) return;
        m_reply.clear();
        if (status == 401) {
#ifdef Q_OS_ANDROID
            auto activity = QNativeInterface::QAndroidApplication::context();
            auto token = QJniObject::fromString(m_token);
            QJniObject::callStaticMethod<void>("com/ingema/ingeplus/GoogleDriveAuthorization", "invalidateToken",
                "(Landroid/app/Activity;Ljava/lang/String;)V", activity.object(), token.object<jstring>());
            QJniEnvironment env; if (env->ExceptionCheck()) env->ExceptionClear();
#endif
            finish({}, "Google rechazó la autorización. Reintenta para renovarla."); return;
        }
        if (status == 0 || status == 429 || status >= 500) {
            finish({}, "Google Drive no respondió. El Excel se conserva para reintentar.", true); return;
        }
        next(status, object);
    });
}
void GoogleDriveExportTransport::folder() {
    request("GET", "drive/v3/files/" + folderId + "?supportsAllDrives=true&fields=id,mimeType,trashed,capabilities(canAddChildren)", {}, {},
        [this](int status, QJsonObject obj) {
            if ((status == 403 || status == 404) && m_interactive && !m_triedPicker) { authorize(true); return; }
            if (status != 200 || obj.value("id").toString() != folderId || obj.value("trashed").toBool()
                || obj.value("mimeType").toString() != "application/vnd.google-apps.folder"
                || !obj.value("capabilities").toObject().value("canAddChildren").toBool()) {
                finish({}, "No hay permiso para guardar en 01_CALICATAS. Usa la cuenta de Lechemayo o comparte esa carpeta con la cuenta elegida como Editor y vuelve a autorizarla."); return;
            }
            request("GET", "drive/v3/about?fields=user(emailAddress)", {}, {}, [this](int status, QJsonObject obj) {
                const auto email = obj.value("user").toObject().value("emailAddress").toString();
                if (status != 200 || email.isEmpty()) { finish({}, "No se pudo identificar la cuenta Google autorizada."); return; }
                // Account binding is metadata, never an access/refresh token.
                const auto existing = m_row.value("googleAccount").toString();
                if (!existing.isEmpty() && existing != email) { finish({}, "Reintenta con la cuenta Google de esta exportación."); return; }
                m_account = email; m_row["googleAccount"] = email;
                if (!m_checkpoint(m_row)) { finish({}, "No se pudo conservar la cuenta de esta exportación."); return; }
                QSettings settings; settings.setValue("google-drive/" + m_row.value("ownerId").toString() + "/account", email);
                if (m_row.value("googleFileId").toString().isEmpty()) reserve(); else probe();
            });
        });
}
void GoogleDriveExportTransport::reserve() {
    request("GET", "drive/v3/files/generateIds?count=1&space=drive&type=files", {}, {}, [this](int status, QJsonObject obj) {
        auto ids = obj.value("ids").toArray();
        if (status != 200 || ids.size() != 1 || ids.first().toString().isEmpty()) { finish({}, "Google no pudo reservar el identificador del Excel."); return; }
        m_row["googleFileId"] = ids.first().toString();
        if (!m_checkpoint(m_row)) { finish({}, "No se pudo conservar el identificador Google antes de subir."); return; }
        probe();
    });
}
bool GoogleDriveExportTransport::verify(const QJsonObject &file) const {
    return file.value("id").toString() == m_row.value("googleFileId").toString()
        && file.value("parents").toArray().contains(folderId) && !file.value("trashed").toBool()
        && file.value("name").toString() == m_row.value("fileName").toString()
        && file.value("mimeType").toString() == xlsxMime
        && file.value("size").toString().toLongLong() == m_bytes.size()
        && file.value("md5Checksum").toString() == QString::fromLatin1(QCryptographicHash::hash(m_bytes, QCryptographicHash::Md5).toHex())
        && file.value("appProperties").toObject().value("ingeSha256").toString() == m_row.value("sha256").toString();
}
void GoogleDriveExportTransport::probe() {
    request("GET", "drive/v3/files/" + m_row.value("googleFileId").toString()
        + "?supportsAllDrives=true&fields=" + fileFields, {}, {}, [this](int status, QJsonObject obj) {
            if (status == 404 && !m_afterUpload) { sendFile(); return; }
            if (status != 200 || !verify(obj)) { finish({}, "No se pudo confirmar que Google guardó el Excel completo en 01_CALICATAS."); return; }
            finish({{"remoteId",obj.value("id").toString()}, {"remotePath",folderId + '/' + obj.value("id").toString()},
                {"remoteFolderPath","01_CALICATAS"}, {"webViewLink",obj.value("webViewLink").toString()}});
        });
}
void GoogleDriveExportTransport::sendFile() {
    const QJsonObject metadata{{"id",m_row.value("googleFileId").toString()}, {"name",m_row.value("fileName").toString()},
        {"mimeType",xlsxMime}, {"parents",QJsonArray{folderId}},
        {"appProperties",QJsonObject{{"ingeSha256",m_row.value("sha256").toString()}}}};
    const QByteArray boundary = "inge-" + QUuid::createUuid().toByteArray(QUuid::WithoutBraces);
    QByteArray body = "--" + boundary + "\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n"
        + QJsonDocument(metadata).toJson(QJsonDocument::Compact) + "\r\n--" + boundary
        + "\r\nContent-Type: " + xlsxMime.toUtf8() + "\r\n\r\n" + m_bytes + "\r\n--" + boundary + "--\r\n";
    request("POST", "upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true&fields=id", body,
        "multipart/related; boundary=" + boundary, [this](int status, QJsonObject obj) {
            if (status == 200 || status == 201 || status == 409) { m_afterUpload = true; probe(); return; }
            Q_UNUSED(obj)
            finish({}, "Google rechazó la subida del Excel (HTTP " + QString::number(status) + "). Revisa espacio y permisos.");
        });
}
void GoogleDriveExportTransport::finish(QVariantMap result, const QString &error, bool retryable) {
    auto done = std::move(m_done); m_checkpoint = {}; m_request.clear(); m_token.clear(); m_bytes.clear();
    if (done) done(result, error, retryable);
}
