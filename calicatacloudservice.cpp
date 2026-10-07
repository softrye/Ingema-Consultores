#include "calicatacloudservice.h"

#include "appcontext.h"
#include "authsession.h"
#include "calicatadocument.h"
#include "supabaseclient.h"

#include <QCryptographicHash>
#include <QRandomGenerator>
#include <QSslSocket>
#include <QDateTime>
#include <QImageIOHandler>
#include <QImageReader>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPointer>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QTimer>
#include <QElapsedTimer>
#include <QUrlQuery>
#include <QUuid>
#include <QtMath>

#include <functional>
#include <memory>

namespace {

QString trimmedText(const QVariant &value)
{
    return value.toString().trimmed();
}

QVariant nullableText(const QVariant &value)
{
    const QString text = trimmedText(value);
    return text.isEmpty() ? QVariant() : QVariant(text);
}

QVariant nullableNumber(const QVariant &value)
{
    QString text = trimmedText(value);
    if (text.isEmpty()) return QVariant();
    text.replace(',', '.');
    bool ok = false;
    const double number = text.toDouble(&ok);
    return ok && qIsFinite(number) ? QVariant(number) : QVariant();
}

// Columnas con CHECK en el servidor (20261007181000): un valor local fuera del
// conjunto viaja como NULL, nunca como un rechazo de toda la sincronización.
QVariant nullableEnum(const QVariant &value, std::initializer_list<const char *> allowed)
{
    const QString text = trimmedText(value);
    for (const char *candidate : allowed)
        if (text == QLatin1String(candidate)) return QVariant(text);
    return QVariant();
}

// calicatas.start_time (time): "HH:mm:ss" / "HH:mm" o NULL.
QVariant nullableTime(const QVariant &value)
{
    const QString text = trimmedText(value);
    static const QRegularExpression timePattern(QStringLiteral("^([01]\\d|2[0-3]):[0-5]\\d(?::[0-5]\\d)?$"));
    return timePattern.match(text).hasMatch() ? QVariant(text.size() == 5 ? text + QStringLiteral(":00") : text) : QVariant();
}

// calicatas.altitude_evidence: array JSON (<= 16 KB) o NULL.
QVariant nullableEvidence(const QVariant &value)
{
    const QVariantList list = value.toList();
    if (list.isEmpty()) return QVariant();
    return QJsonDocument::fromVariant(list).toJson(QJsonDocument::Compact).size() <= 16000 ? QVariant(list) : QVariant();
}

// `calicatas.utm_zone` is a smallint 1..60 (`calicatas_utm_zone_check`).
// Android keeps the latitude band locally ("18L"); the cloud gets 18.
QVariant canonicalUtmZone(const QVariant &value)
{
    static const QRegularExpression zonePattern(QStringLiteral("^(\\d{1,2})(?:\\s*[C-HJ-NP-X])?$"),
                                                QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch match = zonePattern.match(trimmedText(value));
    if (!match.hasMatch()) return QVariant();
    const int zone = match.captured(1).toInt();
    return zone >= 1 && zone <= 60 ? QVariant(zone) : QVariant();
}

QVariant nullableDepth(const QVariant &value)
{
    const QVariant parsed = nullableNumber(value);
    if (!parsed.isValid() || parsed.isNull()) return QVariant();
    const double depth = parsed.toDouble();
    // Web's canonical field contract uses exact 0.05 m increments.
    const double steps = depth / 0.05;
    if (depth < 0.0 || qAbs(steps - qRound64(steps)) > 0.000001)
        return QVariant();
    return QVariant(qRound64(steps) * 0.05);
}

bool isUuid(const QString &value)
{
    return !QUuid(value.trimmed()).isNull();
}

QString normalizedUuid(const QString &value)
{
    const QUuid id(value.trimmed());
    return id.isNull() ? QString() : id.toString(QUuid::WithoutBraces);
}

QString responseCode(const QJsonDocument &document)
{
    if (!document.isObject()) return {};
    const QJsonObject object = document.object();
    return object.value(QStringLiteral("code")).toString(
        object.value(QStringLiteral("error")).toString());
}

QString responseMessage(const QJsonDocument &document, const QString &fallback)
{
    if (!document.isObject()) return fallback;
    const QJsonObject object = document.object();
    const QString message = object.value(QStringLiteral("message")).toString();
    return message.isEmpty() ? fallback : message;
}

QString humanCloudError(const QString &code, const QString &message)
{
    if (code == QLatin1String("23505") || message.contains(QStringLiteral("23505")))
        return QStringLiteral("Ya existe una calicata con ese código en este proyecto.");
    if (code == QLatin1String("40001") || message.contains(QStringLiteral("STALE"), Qt::CaseInsensitive))
        return QStringLiteral("La calicata cambió en el servidor. Vuelve a abrirla antes de guardar nuevamente.");
    if (code == QLatin1String("42501"))
        return QStringLiteral("Tu usuario no tiene permiso para modificar esta calicata.");
    if (code == QLatin1String("AUTH_REQUIRED"))
        return QStringLiteral("Inicia sesión para sincronizar la calicata.");
    return message.isEmpty()
        ? QStringLiteral("No se pudo sincronizar la calicata con InGe+ Web.") : message;
}

QVariantMap firstRow(const QJsonDocument &document)
{
    if (document.isArray() && !document.array().isEmpty() && document.array().first().isObject())
        return document.array().first().toObject().toVariantMap();
    if (document.isObject()) return document.object().toVariantMap();
    return {};
}

QVariantList rows(const QJsonDocument &document)
{
    return document.isArray() ? document.array().toVariantList() : QVariantList{};
}

QString canonicalStatus(const QVariant &value)
{
    static const QSet<QString> statuses = {
        QStringLiteral("BORRADOR"), QStringLiteral("EN_REVISION"),
        QStringLiteral("OBSERVADO"), QStringLiteral("REVISADO"),
        QStringLiteral("APROBADO"), QStringLiteral("EXPORTADO"),
        QStringLiteral("ARCHIVADO")
    };
    const QString status = trimmedText(value).toUpper();
    return statuses.contains(status) ? status : QStringLiteral("BORRADOR");
}

QString moistureFor(const QVariantMap &row)
{
    const QString explicitValue = trimmedText(row.value(QStringLiteral("moisture_condition"))).toUpper();
    if (QSet<QString>{"SECO", "BAJO", "MEDIO", "AGUA"}.contains(explicitValue))
        return explicitValue;
    bool ok = false;
    const int index = row.value(QStringLiteral("humedad")).toInt(&ok);
    static const QStringList values = {"SECO", "BAJO", "MEDIO", "AGUA"};
    return ok && index >= 0 && index < values.size() ? values.at(index) : QString();
}

QString excavabilityFor(const QVariantMap &row)
{
    const QString explicitValue = trimmedText(row.value(QStringLiteral("excavability"))).toUpper();
    if (QSet<QString>{"RENDIMIENTO_BAJO", "RENDIMIENTO_MEDIO", "RENDIMIENTO_ALTO", "RENDIMIENTO_MUY_ALTO"}.contains(explicitValue))
        return explicitValue;
    bool ok = false;
    const int index = row.value(QStringLiteral("excavabilidad")).toInt(&ok);
    static const QStringList values = {
        "RENDIMIENTO_BAJO", "RENDIMIENTO_MEDIO", "RENDIMIENTO_ALTO", "RENDIMIENTO_MUY_ALTO"
    };
    return ok && index >= 0 && index < values.size() ? values.at(index) : QString();
}

QString consistencyFor(const QVariantMap &row)
{
    const QVariantMap extra = row.value(QStringLiteral("_extra")).toMap();
    QString value = trimmedText(row.value(QStringLiteral("consistency_compaction"))).toUpper();
    if (value.isEmpty()) value = trimmedText(extra.value(QStringLiteral("consistency_compaction"))).toUpper();
    return QSet<QString>{"SUELTO", "MEDIANAMENTE_DENSO", "RIGIDO", "MUY_RIGIDO"}.contains(value)
        ? value : QString();
}

QString sampleTypeFor(const QVariantMap &row)
{
    const QString value = trimmedText(row.value(QStringLiteral("tipo_muestra"))).toUpper();
    return QSet<QString>{"MA", "MS", "MI", "MW"}.contains(value) ? value : QString();
}

QString normalizedColor(const QVariantMap &row)
{
    QString value = trimmedText(row.value(QStringLiteral("color"))).toUpper();
    if (value.isEmpty()) {
        QVariantMap extra = row.value(QStringLiteral("_extra")).toMap();
        if (extra.isEmpty()) {
            const QJsonDocument extraDoc = QJsonDocument::fromJson(
                row.value(QStringLiteral("_extraJson")).toString().toUtf8());
            if (extraDoc.isObject()) extra = extraDoc.object().toVariantMap();
        }
        value = trimmedText(extra.value(QStringLiteral("color"))).toUpper();
    }
    return QRegularExpression(QStringLiteral("^#[0-9A-F]{6}$")).match(value).hasMatch()
        ? value : QString();
}

QVariantMap extraFor(const QVariantMap &row)
{
    QVariantMap extra = row.value(QStringLiteral("_extra")).toMap();
    if (!extra.isEmpty()) return extra;
    const QString json = row.value(QStringLiteral("_extraJson")).toString();
    const QJsonDocument doc = QJsonDocument::fromJson(json.toUtf8());
    return doc.isObject() ? doc.object().toVariantMap() : QVariantMap{};
}

// Resultado de laboratorio que el contrato Web no admite tal cual (LL/LP con
// decimales, fila inválida): el valor local se conserva, el estrato queda
// marcado pendiente en su _extraJson (lab_cloud_pending) y la ficha no se
// declara "Al día".
QVariantMap withLabPending(QVariantMap row, const QString &reason, bool pending)
{
    QVariantMap extra = extraFor(row);
    QStringList reasons = extra.value(QStringLiteral("lab_cloud_pending")).toStringList();
    reasons.removeAll(reason);
    if (pending) reasons.append(reason);
    if (reasons.isEmpty()) extra.remove(QStringLiteral("lab_cloud_pending"));
    else extra[QStringLiteral("lab_cloud_pending")] = reasons;
    // Filas exportadas por el formulario llevan las claves extra aplanadas.
    if (reasons.isEmpty()) row.remove(QStringLiteral("lab_cloud_pending"));
    else row[QStringLiteral("lab_cloud_pending")] = reasons;
    if (row.contains(QStringLiteral("_extra"))) row[QStringLiteral("_extra")] = extra;
    row[QStringLiteral("_extraJson")] = QString::fromUtf8(QJsonDocument::fromVariant(extra).toJson(QJsonDocument::Compact));
    return row;
}

QString validAashto(const QString &raw)
{
    const QString value = raw.trimmed();
    static const QSet<QString> valid = {
        "A-1-a", "A-1-b", "A-2-4", "A-2-5", "A-2-6", "A-2-7",
        "A-3", "A-4", "A-5", "A-6", "A-7-5", "A-7-6"
    };
    return valid.contains(value) ? value : QString();
}

struct SyncContext {
    QPointer<CalicataDocument> doc;
    QString localId;
    QString projectId;
    QString remoteId;
    qint64 rowVersion = 0;
    QVariantMap header;
    QString observations;
    QVariantList cortes;
    QVariantList remoteStrata;
    QVariantList remoteSamples;
    int index = 0;
    QString reason;
    bool created = false;
    QVariantMap serverRoot; // row returned by the confirmed root PATCH
    // P3: synced strata deleted on Android (persisted in the draft header as
    // deleted_remote_strata) and the ones delete_my_calicata_stratum_v02 confirmed.
    QStringList tombstones;
    QStringList deletedConfirmed;
    int strataPasses = 0;   // guard: one refetch per confirmed deletion, never unbounded
    qint64 startRevision = 0;   // revisión esperada al empezar (trazas)
    quint64 generation = 0;     // n.º de sync de este carril
    bool retried = false;       // reintento único tras un rebase propio
};

} // namespace

CalicataCloudService::CalicataCloudService(QObject *parent)
    : QObject(parent)
{
    if (auto *auth = appContext() ? appContext()->auth() : nullptr) {
        connect(auth, &AuthSession::loggedChanged, this, &CalicataCloudService::syncAccountContext);
        connect(auth, &AuthSession::userInfoChanged, this, &CalicataCloudService::syncAccountContext);
        connect(auth, &AuthSession::currentAccountChanged, this, &CalicataCloudService::syncAccountContext);
    }
    syncAccountContext();
}

void CalicataCloudService::syncAccountContext()
{
    auto *auth = appContext() ? appContext()->auth() : nullptr;
    const QString owner = auth && auth->logged() ? normalizedUuid(auth->userId()) : QString();
    if (owner == m_contextOwner) return;
    m_contextOwner = owner;
    ++m_contextEpoch;
    m_projects.clear();
    m_projectCalicatas.clear();
    m_archivedProjectCalicatas.clear();
    m_allProjectCalicatas.clear();
    m_listedProjectId.clear();
    leavePresence();
    emit projectsChanged();
    emit projectCalicatasChanged();
}

void CalicataCloudService::beginRequest()
{
    const bool oldBusy = busy();
    ++m_pendingRequests;
    if (oldBusy != busy()) emit busyChanged();
}

void CalicataCloudService::endRequest()
{
    const bool oldBusy = busy();
    if (m_pendingRequests > 0) --m_pendingRequests;
    if (oldBusy != busy()) emit busyChanged();
}

void CalicataCloudService::setLastError(const QString &message)
{
    if (m_lastError == message) return;
    m_lastError = message;
    emit lastErrorChanged();
}

void CalicataCloudService::getJson(const QUrl &url, JsonCallback callback)
{
    syncAccountContext();
    const quint64 epoch = m_contextEpoch;
    auto *ctx = appContext();
    auto *api = ctx ? ctx->supabase() : nullptr;
    auto *auth = ctx ? ctx->auth() : nullptr;
    if (!api || !auth || !auth->logged() || auth->accessToken().isEmpty()) {
        callback(false, QJsonDocument(), QStringLiteral("AUTH_REQUIRED"),
                 QStringLiteral("Inicia sesión para acceder a Calicatas."));
        return;
    }

    QNetworkRequest request = api->makeRequest(url, auth->accessToken());
    request.setRawHeader("x-ingeplus-platform", "ANDROID");
    request.setRawHeader("X-Client-Info", "InGePlus-Android-Calicatas/1.0");
    QNetworkReply *reply = api->nam()->get(request);
    beginRequest();
    QTimer::singleShot(30000, reply, [reply]() { if (!reply->isFinished()) reply->abort(); });
    connect(reply, &QNetworkReply::finished, this, [this, reply, epoch, callback = std::move(callback)]() mutable {
        endRequest();
        const QByteArray raw = reply->readAll();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto networkError = reply->error();
        const QString networkMessage = reply->errorString();
        reply->deleteLater();
        if (epoch != m_contextEpoch) {
            callback(false, {}, QStringLiteral("ACCOUNT_CHANGED"), QStringLiteral("La cuenta cambió durante la operación."));
            return;
        }
        QJsonParseError parseError{};
        const QJsonDocument document = QJsonDocument::fromJson(raw, &parseError);
        if (networkError != QNetworkReply::NoError || http < 200 || http >= 300) {
            const QString code = http == 401 ? QStringLiteral("AUTH_REQUIRED") : responseCode(document);
            callback(false, document, code,
                     responseMessage(document, networkMessage.isEmpty()
                         ? QStringLiteral("HTTP_%1").arg(http) : networkMessage));
            return;
        }
        if (parseError.error != QJsonParseError::NoError) {
            callback(false, document, QStringLiteral("INVALID_JSON"),
                     QStringLiteral("El servidor devolvió una respuesta de Calicatas inválida."));
            return;
        }
        callback(true, document, {}, {});
    });
}

void CalicataCloudService::postRpc(const QString &rpcName, const QVariantMap &arguments,
                                   JsonCallback callback)
{
    syncAccountContext();
    const quint64 epoch = m_contextEpoch;
    auto *ctx = appContext();
    auto *api = ctx ? ctx->supabase() : nullptr;
    auto *auth = ctx ? ctx->auth() : nullptr;
    if (!api || !auth || !auth->logged() || auth->accessToken().isEmpty()) {
        callback(false, QJsonDocument(), QStringLiteral("AUTH_REQUIRED"),
                 QStringLiteral("Inicia sesión para sincronizar la calicata."));
        return;
    }
    QNetworkRequest request = api->makeRequest(
        api->restUrl(QStringLiteral("rpc/") + rpcName), auth->accessToken());
    request.setRawHeader("Prefer", "return=representation");
    request.setRawHeader("x-ingeplus-platform", "ANDROID");
    request.setRawHeader("X-Client-Info", "InGePlus-Android-Calicatas/1.0");
    QNetworkReply *reply = api->nam()->post(
        request, QJsonDocument::fromVariant(arguments).toJson(QJsonDocument::Compact));
    beginRequest();
    QTimer::singleShot(30000, reply, [reply]() { if (!reply->isFinished()) reply->abort(); });
    connect(reply, &QNetworkReply::finished, this, [this, reply, epoch, callback = std::move(callback)]() mutable {
        endRequest();
        const QByteArray raw = reply->readAll();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto networkError = reply->error();
        const QString networkMessage = reply->errorString();
        reply->deleteLater();
        if (epoch != m_contextEpoch) {
            callback(false, {}, QStringLiteral("ACCOUNT_CHANGED"), QStringLiteral("La cuenta cambió durante la operación."));
            return;
        }
        QJsonParseError parseError{};
        const QJsonDocument document = QJsonDocument::fromJson(raw, &parseError);
        if (networkError != QNetworkReply::NoError || http < 200 || http >= 300) {
            const QString code = http == 401 ? QStringLiteral("AUTH_REQUIRED") : responseCode(document);
            callback(false, document, code,
                     responseMessage(document, networkMessage.isEmpty()
                         ? QStringLiteral("HTTP_%1").arg(http) : networkMessage));
            return;
        }
        if (!raw.trimmed().isEmpty() && parseError.error != QJsonParseError::NoError) {
            callback(false, document, QStringLiteral("INVALID_JSON"),
                     QStringLiteral("Respuesta RPC inválida para Calicatas."));
            return;
        }
        callback(true, document, {}, {});
    });
}

void CalicataCloudService::patchRows(const QString &table, const QUrlQuery &query,
                                     const QVariantMap &changes, JsonCallback callback)
{
    syncAccountContext();
    const quint64 epoch = m_contextEpoch;
    auto *ctx = appContext();
    auto *api = ctx ? ctx->supabase() : nullptr;
    auto *auth = ctx ? ctx->auth() : nullptr;
    if (!api || !auth || !auth->logged() || auth->accessToken().isEmpty()) {
        callback(false, QJsonDocument(), QStringLiteral("AUTH_REQUIRED"),
                 QStringLiteral("Inicia sesión para sincronizar la calicata."));
        return;
    }
    QUrl url = api->restUrl(table);
    url.setQuery(query);
    QNetworkRequest request = api->makeRequest(url, auth->accessToken());
    request.setRawHeader("Prefer", "return=representation");
    request.setRawHeader("x-ingeplus-platform", "ANDROID");
    request.setRawHeader("X-Client-Info", "InGePlus-Android-Calicatas/1.0");
    QNetworkReply *reply = api->nam()->sendCustomRequest(
        request, QByteArrayLiteral("PATCH"),
        QJsonDocument::fromVariant(changes).toJson(QJsonDocument::Compact));
    beginRequest();
    QTimer::singleShot(30000, reply, [reply]() { if (!reply->isFinished()) reply->abort(); });
    connect(reply, &QNetworkReply::finished, this, [this, reply, epoch, callback = std::move(callback)]() mutable {
        endRequest();
        const QByteArray raw = reply->readAll();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto networkError = reply->error();
        const QString networkMessage = reply->errorString();
        reply->deleteLater();
        if (epoch != m_contextEpoch) {
            callback(false, {}, QStringLiteral("ACCOUNT_CHANGED"), QStringLiteral("La cuenta cambió durante la operación."));
            return;
        }
        QJsonParseError parseError{};
        const QJsonDocument document = QJsonDocument::fromJson(raw, &parseError);
        if (networkError != QNetworkReply::NoError || http < 200 || http >= 300) {
            callback(false, document, responseCode(document),
                     responseMessage(document, networkMessage.isEmpty()
                         ? QStringLiteral("HTTP_%1").arg(http) : networkMessage));
            return;
        }
        if (!raw.trimmed().isEmpty() && parseError.error != QJsonParseError::NoError) {
            callback(false, document, QStringLiteral("INVALID_JSON"),
                     QStringLiteral("Respuesta REST inválida para Calicatas."));
            return;
        }
        callback(true, document, {}, {});
    });
}

void CalicataCloudService::insertRow(const QString &table, const QVariantMap &row,
                                     JsonCallback callback)
{
    syncAccountContext();
    const quint64 epoch = m_contextEpoch;
    auto *ctx = appContext();
    auto *api = ctx ? ctx->supabase() : nullptr;
    auto *auth = ctx ? ctx->auth() : nullptr;
    if (!api || !auth || !auth->logged() || auth->accessToken().isEmpty()) {
        callback(false, QJsonDocument(), QStringLiteral("AUTH_REQUIRED"),
                 QStringLiteral("Inicia sesión para registrar la actividad."));
        return;
    }
    QNetworkRequest request = api->makeRequest(api->restUrl(table), auth->accessToken());
    request.setRawHeader("Prefer", "return=minimal");
    request.setRawHeader("x-ingeplus-platform", "ANDROID");
    request.setRawHeader("X-Client-Info", "InGePlus-Android-Calicatas/1.0");
    QNetworkReply *reply = api->nam()->post(
        request, QJsonDocument::fromVariant(row).toJson(QJsonDocument::Compact));
    beginRequest();
    QTimer::singleShot(30000, reply, [reply]() { if (!reply->isFinished()) reply->abort(); });
    connect(reply, &QNetworkReply::finished, this, [this, reply, epoch, callback = std::move(callback)]() mutable {
        endRequest();
        const QByteArray raw = reply->readAll();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto networkError = reply->error();
        const QString networkMessage = reply->errorString();
        reply->deleteLater();
        if (epoch != m_contextEpoch) {
            callback(false, {}, QStringLiteral("ACCOUNT_CHANGED"), QStringLiteral("La cuenta cambió durante la operación."));
            return;
        }
        const QJsonDocument document = QJsonDocument::fromJson(raw);
        if (networkError != QNetworkReply::NoError || http < 200 || http >= 300) {
            const QString code = http == 401 ? QStringLiteral("AUTH_REQUIRED") : responseCode(document);
            callback(false, document, code,
                     responseMessage(document, networkMessage.isEmpty()
                         ? QStringLiteral("HTTP_%1").arg(http) : networkMessage));
            return;
        }
        callback(true, document, {}, {});
    });
}

bool CalicataCloudService::resolveElevation(const QString &requestId, const QVariantMap &input)
{
    auto *ctx = appContext();
    auto *api = ctx ? ctx->supabase() : nullptr;
    auto *auth = ctx ? ctx->auth() : nullptr;
    if (!api || !auth || !auth->logged() || requestId.isEmpty() || requestId.size() > 64) return false;
    // Solo coordenadas y evidencias del teléfono; nada del proyecto. La clave de
    // los proveedores vive en los secretos de la Edge Function, nunca en Android.
    QVariantMap body;
    for (const char *key : {"latitude", "longitude", "gpsAltitude", "gpsAccuracy", "gpsVerticalReference",
                            "referenceAltitude", "referenceSource"}) {
        const QString k = QString::fromLatin1(key);
        if (input.contains(k)) body.insert(k, input.value(k));
    }
    QNetworkRequest request = api->makeRequest(QUrl(api->projectUrl() + QStringLiteral("/functions/v1/resolve-calicata-elevation")),
                                               auth->accessToken(), 25000);
    QNetworkReply *reply = api->nam()->post(request, QJsonDocument(QJsonObject::fromVariantMap(body)).toJson(QJsonDocument::Compact));
    const quint64 epoch = m_contextEpoch;
    qInfo().noquote() << "INGE_ELEVATION_REQUEST requestId=" << requestId;
    connect(reply, &QNetworkReply::finished, this, [this, reply, requestId, epoch]() {
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray bytes = reply->readAll();
        reply->deleteLater();
        QVariantMap result = QJsonDocument::fromJson(bytes).object().toVariantMap();
        if (epoch != m_contextEpoch) {
            result = {{QStringLiteral("ok"), false}, {QStringLiteral("error"), QStringLiteral("La cuenta cambió durante la consulta.")}};
        } else if (status < 200 || status >= 300 || !result.value(QStringLiteral("ok")).toBool()) {
            result[QStringLiteral("ok")] = false;
            if (result.value(QStringLiteral("error")).toString().isEmpty())
                result[QStringLiteral("error")] = status == 0
                    ? QStringLiteral("Sin conexión con el servicio de altitud. Ingresa la cota manualmente.")
                    : QStringLiteral("No se pudo resolver la altitud. Ingresa la cota manualmente.");
        }
        result[QStringLiteral("http_status")] = status;
        qInfo().noquote() << "INGE_ELEVATION_RESULT requestId=" << requestId << "http=" << status
                          << "ok=" << result.value(QStringLiteral("ok")).toBool()
                          << "status=" << result.value(QStringLiteral("status")).toString()
                          << "source=" << result.value(QStringLiteral("source")).toString()
                          << "by=" << result.value(QStringLiteral("assessment")).toMap().value(QStringLiteral("by")).toString();
        emit elevationResolved(requestId, result);
    });
    return true;
}

void CalicataCloudService::refreshProjects()
{
    // syncAccountContext() ya vacía la lista si cambió la cuenta. Con la misma cuenta,
    // la lista anterior sigue visible mientras llega la respuesta (red lenta / sin red):
    // el selector abre al instante y se actualiza al recibir las membresías.
    syncAccountContext();
    qInfo() << "[CalicataCloud] PROJECT_SOURCE=SUPABASE_MEMBERSHIPS";
    postRpc(QStringLiteral("list_my_project_memberships_v01"), {},
            [this](bool ok, const QJsonDocument &document, const QString &code, const QString &message) {
        // Respuesta de la cuenta anterior: la lista de la cuenta actual se pide
        // de nuevo con ella; no es un error visible.
        if (code == QLatin1String("ACCOUNT_CHANGED")) return;
        if (!ok) {
            setLastError(humanCloudError(code, message));
            emit projectsLoadFailed(m_lastError);
            return;
        }
        QVariantList projects;
        QSet<QString> seen;
        const QDateTime now = QDateTime::currentDateTimeUtc();
        for (const QVariant &value : rows(document)) {
            const QVariantMap membership = value.toMap();
            if (membership.value(QStringLiteral("membership_status")).toString() != QLatin1String("ACTIVO")) continue;
            const QDateTime starts = QDateTime::fromString(membership.value(QStringLiteral("starts_at")).toString(), Qt::ISODateWithMs);
            const QDateTime ends = QDateTime::fromString(membership.value(QStringLiteral("ends_at")).toString(), Qt::ISODateWithMs);
            if ((starts.isValid() && starts > now) || (ends.isValid() && ends <= now)) continue;
            const QString id = normalizedUuid(membership.value(QStringLiteral("project_id")).toString());
            if (id.isEmpty() || seen.contains(id)) continue;
            seen.insert(id);
            projects.append(QVariantMap{{QStringLiteral("id"), id},
                {QStringLiteral("code"), membership.value(QStringLiteral("project_code"))},
                {QStringLiteral("name"), membership.value(QStringLiteral("project_name"))}});
        }
        m_projects = projects;
        setLastError({});
        emit projectsChanged();
    });
}

void CalicataCloudService::listProjectCalicatas(const QString &projectId)
{
    const quint64 requestId = ++m_projectListRequest;
    const QString pid = normalizedUuid(projectId);
    auto *ctx = appContext();
    auto *api = ctx ? ctx->supabase() : nullptr;
    if (!api || pid.isEmpty()) {
        emit projectCalicatasLoadFailed(projectId, QStringLiteral("Proyecto inválido."));
        return;
    }
    QUrl url = api->restUrl(QStringLiteral("calicatas"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("select"), QStringLiteral(
        "id,project_id,code,title,location,progresiva,easting,northing,altitude_m,depth_m,groundwater_depth_m,utm_zone,supervisor,machine,start_date,end_date,start_time,description,observations,status,altitude_source,altitude_mode,altitude_confidence,altitude_accuracy_m,altitude_vertical_reference,altitude_resolved_at,altitude_evidence,created_by,created_at,updated_at,row_version"));
    query.addQueryItem(QStringLiteral("project_id"), QStringLiteral("eq.") + pid);
    // Archived rows are listed too: they keep their code (UNIQUE per project)
    // and are the secondary "Archivadas" view. The main list hides them.
    query.addQueryItem(QStringLiteral("order"), QStringLiteral("created_at.desc"));
    url.setQuery(query);
    getJson(url, [this, pid, requestId](bool ok, const QJsonDocument &document,
                             const QString &code, const QString &message) {
        if (requestId != m_projectListRequest) return;
        if (!ok) {
            const QString error = humanCloudError(code, message);
            setLastError(error);
            emit projectCalicatasLoadFailed(pid, error);
            return;
        }
        m_listedProjectId = pid;
        m_allProjectCalicatas = rows(document);
        m_projectCalicatas.clear();
        m_archivedProjectCalicatas.clear();
        for (const QVariant &value : std::as_const(m_allProjectCalicatas)) {
            if (value.toMap().value(QStringLiteral("status")).toString() == QLatin1String("ARCHIVADO"))
                m_archivedProjectCalicatas.append(value);
            else
                m_projectCalicatas.append(value);
        }
        emit projectCalicatasChanged();
        emit projectCalicatasLoaded(pid, m_projectCalicatas);
    });
}

void CalicataCloudService::resolveProjectWorkspace(const QString &projectId)
{
    const QString pid = normalizedUuid(projectId);
    if (pid.isEmpty()) {
        emit workspaceResolveFailed(projectId, QStringLiteral("Proyecto inválido."));
        return;
    }
    postRpc(QStringLiteral("get_my_project_workspace_v01"),
            {{QStringLiteral("p_project_id"), pid}},
            [this, pid](bool ok, const QJsonDocument &document,
                        const QString &code, const QString &message) {
        const QVariantMap row = firstRow(document);
        const QString spaceId = row.value(QStringLiteral("space_id")).toString();
        if (!ok || row.value(QStringLiteral("project_id")).toString() != pid || !isUuid(spaceId)) {
            const QString error = humanCloudError(code,
                ok ? QStringLiteral("El proyecto no tiene un espacio documental disponible.") : message);
            emit workspaceResolveFailed(pid, error);
            return;
        }
        emit workspaceResolved(pid, normalizedUuid(spaceId));
    });
}


void CalicataCloudService::loadRemoteDocument(CalicataDocument *document,
                                               const QString &projectId,
                                               const QString &calicataId)
{
    const QPointer<CalicataDocument> target(document);
    const QString localId = document ? document->instanceId() : QString();
    const QString pid = normalizedUuid(projectId);
    const QString cid = normalizedUuid(calicataId);
    if (!target || target->closed() || pid.isEmpty() || cid.isEmpty()) {
        const QString error = QStringLiteral("Proyecto o calicata remota inválidos.");
        setLastError(error);
        emit remoteLoadFailed(localId, error);
        return;
    }

    auto *api = appContext() ? appContext()->supabase() : nullptr;
    if (!api) {
        const QString error = QStringLiteral("Supabase no está disponible.");
        setLastError(error);
        emit remoteLoadFailed(localId, error);
        return;
    }

    auto *auth = appContext() ? appContext()->auth() : nullptr;
    const QString owner = auth ? normalizedUuid(auth->userId()) : QString();
    const QVariantMap originalHeader = target->header();
    const QVariantList originalCortes = target->cortes();
    const QString originalObservations = target->observaciones();
    auto elapsed = std::make_shared<QElapsedTimer>();
    elapsed->start();
    postRpc(QStringLiteral("get_my_calicata_snapshot_v01"),
            {{QStringLiteral("p_project_id"), pid}, {QStringLiteral("p_calicata_id"), cid}},
            [this, target, localId, pid, cid, owner, originalHeader, originalCortes, originalObservations, elapsed]
            (bool ok, const QJsonDocument &snapshotDocument, const QString &code, const QString &message) {
        if (!target || target->closed()) return;
        auto *auth = appContext() ? appContext()->auth() : nullptr;
        const QVariantMap snapshot = firstRow(snapshotDocument);
        const QVariantMap remoteRoot = snapshot.value(QStringLiteral("calicata")).toMap();
        if (!auth || !auth->logged() || normalizedUuid(auth->userId()) != owner) {
            emit remoteLoadFailed(localId, QStringLiteral("La cuenta cambió durante la carga."));
            return;
        }
        if (!ok || remoteRoot.value(QStringLiteral("id")).toString() != cid
            || remoteRoot.value(QStringLiteral("project_id")).toString() != pid
            || remoteRoot.value(QStringLiteral("row_version")).toLongLong() < 1) {
            const QString error = humanCloudError(code, ok
                ? QStringLiteral("La calicata no existe en este proyecto o no está autorizada.") : message);
            setLastError(error); emit remoteLoadFailed(localId, error); return;
        }
        if (target->header() != originalHeader || target->cortes() != originalCortes
            || target->observaciones() != originalObservations) {
            emit remoteLoadFailed(localId, QStringLiteral("La ficha cambió durante la carga. Los cambios locales se conservan."));
            return;
        }
        const qint64 networkMs = elapsed->elapsed();
        const QVariantList remoteStrata = snapshot.value(QStringLiteral("strata")).toList();
        const QVariantList remoteSamples = snapshot.value(QStringLiteral("samples")).toList();
        const QVariantList remoteLabs = snapshot.value(QStringLiteral("labs")).toList();

        auto valueText = [](const QVariant &value) -> QString {
            if (!value.isValid() || value.isNull()) return {};
            bool okNumber = false;
            const double number = value.toDouble(&okNumber);
            if (okNumber && qIsFinite(number))
                return QString::number(number, 'f', 2);
            return value.toString();
        };
        auto enumIndex = [](const QString &value, const QStringList &catalog) -> int {
            return catalog.indexOf(value.trimmed().toUpper());
        };

        QVariantList localCortes;
        localCortes.reserve(remoteStrata.size());
        for (const QVariant &stratumValue : remoteStrata) {
            const QVariantMap stratum = stratumValue.toMap();
            const QString stratumId = normalizedUuid(stratum.value(QStringLiteral("id")).toString());
            if (stratumId.isEmpty()) continue;

            QVariantList samplesForStratum;
            for (const QVariant &sampleValue : remoteSamples) {
                const QVariantMap sample = sampleValue.toMap();
                if (normalizedUuid(sample.value(QStringLiteral("stratum_id")).toString()) == stratumId)
                    samplesForStratum.append(sample);
            }
            QVariantMap primarySample = samplesForStratum.isEmpty()
                ? QVariantMap{} : samplesForStratum.first().toMap();

            QVariantMap laboratory;
            for (const QVariant &labValue : remoteLabs) {
                const QVariantMap candidate = labValue.toMap();
                if (normalizedUuid(candidate.value(QStringLiteral("stratum_id")).toString()) == stratumId) {
                    laboratory = candidate; break;
                }
            }

            QVariantMap extra;
            extra[QStringLiteral("remote_stratum_id")] = stratumId;
            extra[QStringLiteral("local_stratum_id")] = stratumId;
            extra[QStringLiteral("remote_sequence_number")] = stratum.value(QStringLiteral("sequence_number"));
            extra[QStringLiteral("consistency_compaction")] = stratum.value(QStringLiteral("consistency_compaction"));
            extra[QStringLiteral("color")] = stratum.value(QStringLiteral("color"));
            extra[QStringLiteral("observations")] = stratum.value(QStringLiteral("observations"));
            extra[QStringLiteral("remote_samples")] = samplesForStratum;
            if (!laboratory.isEmpty()) {
                extra[QStringLiteral("passing_no4")] = laboratory.value(QStringLiteral("sieve_no4_pct"));
                extra[QStringLiteral("primary_sucs")] = laboratory.value(QStringLiteral("primary_sucs"));
                extra[QStringLiteral("is_composite")] = laboratory.value(QStringLiteral("is_composite"));
                extra[QStringLiteral("secondary_sucs")] = laboratory.value(QStringLiteral("secondary_sucs"));
                extra[QStringLiteral("laboratory_source")] = laboratory.value(QStringLiteral("laboratory_source"));
                extra[QStringLiteral("test_date")] = laboratory.value(QStringLiteral("test_date"));
                extra[QStringLiteral("remote_lab_result_id")] = laboratory.value(QStringLiteral("id"));
                extra[QStringLiteral("lab_confirmed_aashto")] = laboratory.value(QStringLiteral("aashto")).toString().trimmed();
            }

            QVariantMap local;
            local[QStringLiteral("id")] = stratumId;
            local[QStringLiteral("local_stratum_id")] = stratumId;
            local[QStringLiteral("remote_stratum_id")] = stratumId;
            local[QStringLiteral("remote_sequence_number")] = stratum.value(QStringLiteral("sequence_number"));
            local[QStringLiteral("material_origin")] = QString();
            local[QStringLiteral("descripcion")] = stratum.value(QStringLiteral("description"));
            local[QStringLiteral("humedad")] = enumIndex(
                stratum.value(QStringLiteral("moisture_condition")).toString(),
                {QStringLiteral("SECO"), QStringLiteral("BAJO"), QStringLiteral("MEDIO"), QStringLiteral("AGUA")});
            local[QStringLiteral("excavabilidad")] = enumIndex(
                stratum.value(QStringLiteral("excavability")).toString(),
                {QStringLiteral("RENDIMIENTO_BAJO"), QStringLiteral("RENDIMIENTO_MEDIO"),
                 QStringLiteral("RENDIMIENTO_ALTO"), QStringLiteral("RENDIMIENTO_MUY_ALTO")});
            // Android's legacy 'estabilidad' is not Web consistency_compaction.
            local[QStringLiteral("estabilidad")] = -1;
            const QString sampleType = primarySample.value(QStringLiteral("sample_type"),
                stratum.value(QStringLiteral("sample_type"))).toString().trimmed().toUpper();
            local[QStringLiteral("tipo_muestra")] = sampleType;
            local[QStringLiteral("tipoText")] = sampleType;
            local[QStringLiteral("tipo_otro")] = QString();
            local[QStringLiteral("de")] = valueText(stratum.value(QStringLiteral("from_depth_m")));
            local[QStringLiteral("a")] = valueText(stratum.value(QStringLiteral("to_depth_m")));
            local[QStringLiteral("sample_code")] = primarySample.value(QStringLiteral("sample_code")).toString();
            local[QStringLiteral("remote_sample_id")] = primarySample.value(QStringLiteral("id")).toString();
            local[QStringLiteral("muestra_desde")] = valueText(primarySample.value(QStringLiteral("from_depth_m")));
            local[QStringLiteral("muestra_hasta")] = valueText(primarySample.value(QStringLiteral("to_depth_m")));
            local[QStringLiteral("resultados")] = QString();

            // Contrato Web: la clasificación vigente es la del laboratorio
            // (primary_sucs / is_composite / secondary_sucs / aashto, ya en extra);
            // calicata_strata.sucs/aashto es el valor anterior del estrato y se
            // conserva tal cual (Web exportModel lo usa solo si el laboratorio
            // está vacío). lab_confirmed_sucs = espejo de compatibilidad local.
            QString labSucs = laboratory.value(QStringLiteral("primary_sucs")).toString().trimmed().toUpper();
            if (!labSucs.isEmpty() && laboratory.value(QStringLiteral("is_composite")).toBool()) {
                const QString secondary = laboratory.value(QStringLiteral("secondary_sucs")).toString().trimmed().toUpper();
                if (!secondary.isEmpty() && secondary != labSucs) labSucs += QStringLiteral("-") + secondary;
            }
            extra[QStringLiteral("lab_confirmed_sucs")] = labSucs;
            local[QStringLiteral("sucs")] = stratum.value(QStringLiteral("sucs")).toString().trimmed();
            local[QStringLiteral("aashto")] = stratum.value(QStringLiteral("aashto")).toString().trimmed();
            local[QStringLiteral("gmax")] = valueText(laboratory.value(QStringLiteral("sieve_max_pct")));
            local[QStringLiteral("g2")] = valueText(laboratory.value(QStringLiteral("sieve_2mm_pct")));
            local[QStringLiteral("g04")] = valueText(laboratory.value(QStringLiteral("sieve_04mm_pct")));
            local[QStringLiteral("g008")] = valueText(laboratory.value(QStringLiteral("sieve_008mm_pct")));
            local[QStringLiteral("g002")] = QString();
            local[QStringLiteral("wl")] = valueText(laboratory.value(QStringLiteral("liquid_limit")));
            local[QStringLiteral("lp")] = valueText(laboratory.value(QStringLiteral("plastic_limit")));
            local[QStringLiteral("hum2")] = valueText(laboratory.value(QStringLiteral("natural_moisture_pct")));
            local[QStringLiteral("_percentageFieldsJson")] = QStringLiteral("[]");
            // Pendiente local (el servidor aún no lo admite) o solo local (fechas de
            // confirmación): se conserva del documento abierto, nunca se pierde.
            if (target) {
                for (const QVariant &value : target->cortes()) {
                    const QVariantMap mine = value.toMap();
                    QVariantMap mineExtra = extraFor(mine);
                    if (mineExtra.isEmpty()) mineExtra = mine;   // fila exportada con claves aplanadas
                    if (normalizedUuid(mineExtra.value(QStringLiteral("remote_stratum_id")).toString()) != stratumId) continue;
                    QStringList pending = mineExtra.value(QStringLiteral("lab_cloud_pending")).toStringList();
                    // Datos solo locales de fichas anteriores (fuera del contrato
                    // Web, ya no se editan ni viajan): se conservan, nunca se borran.
                    for (const char *key : {"lab_confirmed_at", "lab_visual_aashto_at", "lab_confirmed_ig", "field_sucs", "field_aashto",
                                            "d10", "d30", "d60", "nonplastic_confirmed", "lab_observations", "lab_visual_aashto"})
                        if (mineExtra.contains(QLatin1String(key))) extra[QLatin1String(key)] = mineExtra.value(QLatin1String(key));
                    // LL/LP con decimales (fichas anteriores): el servidor solo admite
                    // enteros; el valor local se conserva hasta que el técnico lo corrija.
                    if (pending.contains(QStringLiteral("LAB_LIMITS"))) {
                        local[QStringLiteral("wl")] = mine.value(QStringLiteral("wl"));
                        local[QStringLiteral("lp")] = mine.value(QStringLiteral("lp"));
                    }
                    pending.removeAll(QStringLiteral("LAB_EXTENSION"));
                    pending.removeAll(QStringLiteral("FIELD_CLASS"));
                    if (!pending.isEmpty()) extra[QStringLiteral("lab_cloud_pending")] = pending;
                    break;
                }
            }
            local[QStringLiteral("_extraJson")] = QString::fromUtf8(
                QJsonDocument::fromVariant(extra).toJson(QJsonDocument::Compact));
            localCortes.append(local);
        }

        QVariantMap authoritativeRoot = remoteRoot;
        authoritativeRoot[QStringLiteral("remoteCalicataId")] = cid;
        authoritativeRoot[QStringLiteral("remoteRowVersion")] = remoteRoot.value(QStringLiteral("row_version"));
        const QVariantMap project = snapshot.value(QStringLiteral("project")).toMap();
        authoritativeRoot[QStringLiteral("projectCode")] = project.value(QStringLiteral("code"));
        authoritativeRoot[QStringLiteral("projectName")] = project.value(QStringLiteral("name"));
        target->applyRemoteSnapshot(authoritativeRoot, localCortes);
        if (!target->errorString().isEmpty()) {
            const QString error = target->errorString();
            setLastError(error); emit remoteLoadFailed(localId, error); return;
        }
        setLastError({});
        {
            // Estado del servidor adoptado por el documento: nueva base del carril.
            auto &lane = m_lanes[localId];
            if (!lane.busy()) {
                lane.baseRoot = remoteRoot;
                lane.ownLive.clear();
                lane.uncertainOwnBumps = 0;
                noteConfirmedRevision(localId, cid, remoteRoot.value(QStringLiteral("row_version")).toLongLong());
            }
        }
        if (qEnvironmentVariableIsSet("INGE_CALICATA_TRACE"))
            qInfo() << "INGE_CALICATA_HYDRATE_TIMING requests=1 networkMs=" << networkMs
                    << "applyMs=" << elapsed->elapsed() - networkMs;
        emit remoteLoadSucceeded(localId, pid, cid);
    });
}

QString CalicataCloudService::syncDocument(CalicataDocument *document, const QString &reason)
{
    if (!document || document->closed()) return {};
    const QString requestedReason = (reason == QLatin1String("export") || reason == QLatin1String("autosave"))
        ? reason : QStringLiteral("save");
    {
        // Una sola escritura en vuelo por ficha: otra sync no compite con CAS
        // paralelo; se coalesce y al terminar sube el snapshot local MÁS reciente.
        auto &lane = m_lanes[document->instanceId()];
        m_laneDocs[document->instanceId()] = document;
        if (lane.busy()) {
            lane.requestSync(requestedReason);
            qInfo().noquote() << "INGE_CALICATA_SYNC_COALESCED reason=" << requestedReason
                              << "queued=" << lane.queuedSync() << "generation=" << lane.generation();
            return document->instanceId();
        }
    }
    const QVariantMap header = document->header();
    const QString projectId = normalizedUuid(header.value(QStringLiteral("projectId")).toString());
    const QString code = trimmedText(header.value(QStringLiteral("code"),
                                      header.value(QStringLiteral("codigo"))));
    const QString localId = document->instanceId();
    QString error;
    if (projectId.isEmpty())
        error = QStringLiteral("Selecciona un proyecto antes de guardar online.");
    else if (code.isEmpty())
        error = QStringLiteral("El código de la calicata es obligatorio.");
    else if (document->status() == QLatin1String("ARCHIVADO"))
        error = QStringLiteral("La calicata está archivada. Restáurala antes de sincronizar cambios.");
    else
        error = codeConflict(document);
    if (!error.isEmpty()) {
        setLastError(error);
        emit syncFailed(localId, error);
        return {};
    }

    auto &lane = m_lanes[localId];
    lane.requestSync(requestedReason);   // carril libre: Started
    auto ctx = std::make_shared<SyncContext>();
    ctx->doc = document;
    ctx->localId = localId;
    ctx->projectId = projectId;
    ctx->header = header;
    ctx->observations = document->observaciones();
    ctx->cortes = document->cortes();
    ctx->remoteId = normalizedUuid(header.value(QStringLiteral("remoteCalicataId"),
                                 header.value(QStringLiteral("remote_calicata_id"))).toString());
    const qint64 documentRevision = header.value(QStringLiteral("remoteRowVersion"),
                                    header.value(QStringLiteral("row_version"))).toLongLong();
    // Nunca se envía una revisión menor que la que el servidor ya confirmó a
    // esta sesión (p. ej. documento reabierto desde un borrador anterior).
    ctx->rowVersion = ctx->remoteId.isEmpty() ? documentRevision
        : CalicataSync::expectedRevision(documentRevision, m_confirmedRevisions.value(ctx->remoteId));
    if (ctx->rowVersion != documentRevision)
        qInfo().noquote() << "INGE_CALICATA_SYNC_REBASE reason=local_stale documentRevision=" << documentRevision
                          << "confirmedRevision=" << ctx->rowVersion << "calicataId=" << ctx->remoteId;
    ctx->startRevision = ctx->rowVersion;
    ctx->generation = lane.generation();
    ctx->retried = lane.retryAfterRebase;
    lane.retryAfterRebase = false;
    // "autosave": background sync of the draft (P0). It records CREATE_CALICATA
    // on the first creation only, never one UPDATE_CALICATA per keystroke.
    ctx->reason = requestedReason;
    qInfo().noquote() << "INGE_CALICATA_SYNC_QUEUED reason=" << ctx->reason
                      << "projectId=" << ctx->projectId << "calicataId=" << ctx->remoteId;
    qInfo().noquote() << "INGE_CALICATA_SYNC_BEGIN reason=" << ctx->reason << "expectedRevision=" << ctx->rowVersion
                      << "generation=" << ctx->generation << "retry=" << ctx->retried
                      << "queuedSync=" << lane.queuedSync() << "deferred=" << lane.deferredCount()
                      << "dirty=" << document->dirty();
    for (const QVariant &value : header.value(QStringLiteral("deleted_remote_strata")).toList()) {
        const QString id = normalizedUuid(value.toString());
        if (!id.isEmpty() && !ctx->tombstones.contains(id)) ctx->tombstones << id;
    }
    document->setSyncState(QStringLiteral("SYNCING"));

    // Every server write is verified (row_version + 1), so the last confirmed
    // cloud identity and version are known exactly. Binding them to the local
    // mirror as soon as they exist means a retry after a partial failure (or
    // process death) updates the same row instead of creating a duplicate.
    const auto bindIdentity = [ctx](bool continuing) {
        if (!ctx->doc || ctx->remoteId.isEmpty() || ctx->rowVersion < 1) return;
        ctx->doc->applyCloudSync({{QStringLiteral("id"), ctx->remoteId},
                                  {QStringLiteral("project_id"), ctx->projectId},
                                  {QStringLiteral("row_version"), ctx->rowVersion},
                                  {QStringLiteral("deleted_remote_strata_confirmed"), ctx->deletedConfirmed}}, {});
        if (!continuing) return;
        const bool editedMeanwhile = ctx->doc->syncState() == QLatin1String("PENDING");
        ctx->doc->setSyncState(QStringLiteral("SYNCING"));
        if (editedMeanwhile) ctx->doc->markDirty();
    };

    // Cierre de una sync fallida. `conflict` = conflicto REAL ya demostrado.
    const auto finishFailure = [this, ctx, bindIdentity](const QString &codeValue, const QString &message, bool conflict) {
        qWarning().noquote() << "INGE_CALICATA_SYNC_REJECTED code=" << codeValue
                            << "projectId=" << ctx->projectId << "calicataId=" << ctx->remoteId
                            << "confirmedRevision=" << ctx->rowVersion << "generation=" << ctx->generation;
        const QString error = humanCloudError(codeValue, message);
        // Una sync coalescida fallaría igual (sin red, rechazo o conflicto): se
        // descarta y este resultado responde también a esa petición.
        m_lanes[ctx->localId].dropQueuedSync();
        if (codeValue == QLatin1String("ACCOUNT_CHANGED")) {
            emit syncFailed(ctx->localId, error);
            releaseLane(ctx->localId);
            return; // never persist the previous account's snapshot in a new session
        }
        bindIdentity(false);
        noteConfirmedRevision(ctx->localId, ctx->remoteId, ctx->rowVersion);
        if (ctx->doc) {
            const bool confirmedIdentity = !normalizedUuid(ctx->doc->header()
                .value(QStringLiteral("remoteCalicataId")).toString()).isEmpty();
            ctx->doc->setSyncState(conflict ? QStringLiteral("CONFLICT")
                                   : (confirmedIdentity ? QStringLiteral("PENDING") : QStringLiteral("LOCAL")));
        }
        setLastError(conflict ? error : (codeValue == QLatin1String("40001")
            ? QStringLiteral("No se pudo sincronizar la calicata; se reintentará.") : error));
        emit syncFailed(ctx->localId, error);
        releaseLane(ctx->localId);
    };

    // 40001/STALE: antes de mostrar "Conflicto" se lee la fila remota y se
    // decide si el salto de revisión es de esta misma sesión (rebase + UN
    // reintento) o de otro cliente (conflicto real, nunca se sobrescribe).
    const auto fail = [this, ctx, finishFailure](const QString &codeValue, const QString &message) {
        const bool stale = codeValue == QLatin1String("40001")
            || message.contains(QStringLiteral("STALE"), Qt::CaseInsensitive);
        if (!stale || !ctx->doc || ctx->remoteId.isEmpty()) {
            finishFailure(codeValue, message, false);
            return;
        }
        probeRoot(ctx->projectId, ctx->remoteId, [this, ctx, finishFailure, codeValue, message](bool ok, const QVariantMap &server) {
            auto &lane = m_lanes[ctx->localId];
            const qint64 serverRevision = server.value(QStringLiteral("row_version")).toLongLong();
            const bool consistent = ok && CalicataSync::rootMatches(server, lane.baseRoot, lane.ownLive);
            const auto verdict = ok
                ? CalicataSync::classifyStale(ctx->rowVersion, serverRevision, lane.uncertainOwnBumps, consistent, ctx->retried)
                : CalicataSync::Stale::RealConflict;
            if (!ok) {
                // Sin poder leer la fila no se puede demostrar nada: queda pendiente, no "Conflicto".
                finishFailure(codeValue, message, false);
                return;
            }
            if (verdict == CalicataSync::Stale::Rebase && ctx->doc
                && ctx->doc->checkpointCloudRevision(ctx->projectId, ctx->remoteId, serverRevision)) {
                qInfo().noquote() << "INGE_CALICATA_SYNC_REBASE reason=own_unverified_write expectedRevision=" << ctx->rowVersion
                                  << "serverRevision=" << serverRevision << "ownUnverified=" << lane.uncertainOwnBumps
                                  << "generation=" << ctx->generation;
                lane.uncertainOwnBumps = 0;
                lane.baseRoot = server;
                lane.ownLive.clear();
                noteConfirmedRevision(ctx->localId, ctx->remoteId, serverRevision);
                lane.retryAfterRebase = true;
                lane.requestSync(ctx->reason);   // carril ocupado: queda como siguiente
                if (ctx->doc) ctx->doc->setSyncState(QStringLiteral("PENDING"));
                releaseLane(ctx->localId);       // reintento único con el snapshot más reciente
                return;
            }
            qWarning().noquote() << "INGE_CALICATA_SYNC_REAL_CONFLICT expectedRevision=" << ctx->rowVersion
                                 << "serverRevision=" << serverRevision << "ownUnverified=" << lane.uncertainOwnBumps
                                 << "rootMatchesOwn=" << consistent << "retried=" << ctx->retried
                                 << "reason=" << ctx->reason << "generation=" << ctx->generation;
            finishFailure(codeValue, message, true);
        });
    };

    auto syncStrata = std::make_shared<std::function<void()>>();
    auto syncOneStratum = std::make_shared<std::function<void()>>();
    auto syncSampleAndLab = std::make_shared<std::function<void(const QString &, QVariantMap, std::function<void()>)>>();
    auto finalizeSmartDocument = std::make_shared<std::function<void()>>();
    auto ensureSmartDocument = std::make_shared<std::function<void()>>();

    // Carpeta canónica de Calicatas: 04_PROYECTOS/<proyecto>/06_GABINETE (FIELD).
    // El servidor la crea/enlaza en esta misma operación antes del Smart Document.
    *finalizeSmartDocument = [this, ctx, fail, ensureSmartDocument]() {
        ensureProjectGabinete(ctx->projectId,
                              [fail, ensureSmartDocument](bool ready, const QString &, const QString &,
                                                          const QString &error) {
            if (!ready) { fail({}, error); return; }
            (*ensureSmartDocument)();
        });
    };
    *ensureSmartDocument = [this, ctx, fail]() {
        postRpc(QStringLiteral("ensure_calicata_smart_document_v01"),
                {{QStringLiteral("p_calicata_id"), ctx->remoteId}},
                [this, ctx, fail](bool ok, const QJsonDocument &document,
                                  const QString &code, const QString &message) {
            if (!ok) {
                fail(code, message.contains(QStringLiteral("CANONICAL_PARENT_UNAVAILABLE"))
                     ? QStringLiteral("La carpeta 06_GABINETE del proyecto no está disponible. "
                                      "La ficha se conserva en el dispositivo.")
                     : message);
                return;
            }
            const QVariantMap smart = firstRow(document);
            const QString documentNodeId = normalizedUuid(smart.value(QStringLiteral("document_node_id")).toString());
            const QString spaceId = normalizedUuid(smart.value(QStringLiteral("space_id")).toString());
            const QString parentNodeId = normalizedUuid(smart.value(QStringLiteral("parent_node_id")).toString());
            const QString projectId = normalizedUuid(smart.value(QStringLiteral("project_id")).toString());
            const QString targetId = normalizedUuid(smart.value(QStringLiteral("target_id")).toString());
            const QString targetType = trimmedText(smart.value(QStringLiteral("target_type"))).toUpper();
            const QString lifecycle = trimmedText(smart.value(QStringLiteral("lifecycle"))).toUpper();
            const QString resultCode = trimmedText(smart.value(QStringLiteral("result_code"))).toUpper();
            const QString name = trimmedText(smart.value(QStringLiteral("name")));
            const qint64 nodeVersion = smart.value(QStringLiteral("node_version")).toLongLong();
            const bool validLifecycle = QSet<QString>{QStringLiteral("ACTIVE"), QStringLiteral("ARCHIVED"),
                                                      QStringLiteral("TRASHED")}.contains(lifecycle);
            const bool validResult = resultCode == QLatin1String("CREATED")
                || resultCode == QLatin1String("IDEMPOTENT_REPLAY");
            if (documentNodeId.isEmpty() || spaceId.isEmpty() || parentNodeId.isEmpty()
                || projectId != ctx->projectId || targetId != ctx->remoteId
                || targetType != QLatin1String("CALICATA") || name.isEmpty()
                || nodeVersion < 1 || !validLifecycle || !validResult) {
                fail({}, QStringLiteral("El servidor devolvió un Smart Document de Calicata incoherente."));
                return;
            }

            QVariantMap result;
            result[QStringLiteral("remoteCalicataId")] = ctx->remoteId;
            result[QStringLiteral("row_version")] = ctx->rowVersion;
            result[QStringLiteral("project_id")] = ctx->projectId;
            result[QStringLiteral("status")] = canonicalStatus(ctx->header.value(QStringLiteral("status")));
            result[QStringLiteral("document_node_id")] = documentNodeId;
            result[QStringLiteral("space_id")] = spaceId;
            result[QStringLiteral("parent_node_id")] = parentNodeId;
            result[QStringLiteral("node_version")] = nodeVersion;
            result[QStringLiteral("name")] = name;
            result[QStringLiteral("lifecycle")] = lifecycle;
            result[QStringLiteral("smart_document_result_code")] = resultCode;
            // Server-owned authorship and timestamps (set_updated_at trigger).
            for (const char *key : {"created_by", "created_at", "updated_at"}) {
                const QString k = QString::fromLatin1(key);
                if (ctx->serverRoot.contains(k)) result[k] = ctx->serverRoot.value(k);
            }
            result[QStringLiteral("deleted_remote_strata_confirmed")] = ctx->deletedConfirmed;
            if (ctx->doc) ctx->doc->applyCloudSync(result, ctx->cortes);
            setLastError({});

            const QString codeText = trimmedText(ctx->serverRoot.value(QStringLiteral("code"),
                ctx->header.value(QStringLiteral("code"))));
            QVariantMap metadata;
            metadata[QStringLiteral("code")] = codeText;
            metadata[QStringLiteral("title")] = ctx->serverRoot.value(QStringLiteral("title"));
            metadata[QStringLiteral("status")] = result.value(QStringLiteral("status"));
            metadata[QStringLiteral("row_version")] = ctx->rowVersion;
            metadata[QStringLiteral("strata_count")] = ctx->cortes.size();
            if (ctx->created)
                enqueueActivity(ctx->projectId, ctx->remoteId, QStringLiteral("CREATE_CALICATA"),
                                QStringLiteral("Calicata creada: %1").arg(codeText), metadata);
            else if (ctx->reason == QLatin1String("autosave"))
                ;   // background draft sync: no audit entry per autosave
            else if (ctx->reason == QLatin1String("export"))
                enqueueActivity(ctx->projectId, ctx->remoteId, QStringLiteral("SYNC_CALICATA"),
                                QStringLiteral("Calicata sincronizada para exportación: %1").arg(codeText), metadata);
            else
                enqueueActivity(ctx->projectId, ctx->remoteId, QStringLiteral("UPDATE_CALICATA"),
                                QStringLiteral("Calicata actualizada: %1").arg(codeText), metadata);
            // La revisión confirmada ya está en el documento (checkpoint por paso);
            // el carril la registra ANTES de liberar la siguiente escritura.
            auto &lane = m_lanes[ctx->localId];
            noteConfirmedRevision(ctx->localId, ctx->remoteId, ctx->rowVersion);
            if (!ctx->serverRoot.isEmpty()) lane.baseRoot = ctx->serverRoot;
            lane.ownLive.clear();
            lane.uncertainOwnBumps = 0;
            const bool editedMeanwhile = ctx->doc && ctx->doc->syncState() == QLatin1String("PENDING");
            qInfo().noquote() << "INGE_CALICATA_SYNC_OK reason=" << ctx->reason << "previousRevision=" << ctx->startRevision
                              << "confirmedRevision=" << ctx->rowVersion << "generation=" << ctx->generation
                              << "editedMeanwhile=" << editedMeanwhile << "queuedSync=" << lane.queuedSync();
            // Con una sync coalescida pendiente, la petición termina cuando suba
            // el snapshot más nuevo: ella emitirá el resultado.
            if (lane.queuedSync().isEmpty()) emit syncSucceeded(ctx->localId, result);
            releaseLane(ctx->localId);
        });
    };

    *syncSampleAndLab = [this, ctx, fail](const QString &remoteStratumId, QVariantMap localRow, std::function<void()> done) {
        const QVariantMap extra = extraFor(localRow);
        const QString sampleType = sampleTypeFor(localRow);
        QString remoteSampleId = normalizedUuid(localRow.value(QStringLiteral("remote_sample_id")).toString());
        if (remoteSampleId.isEmpty()) {
            for (const QVariant &value : ctx->remoteSamples) {
                const QVariantMap remoteSample = value.toMap();
                if (normalizedUuid(remoteSample.value(QStringLiteral("stratum_id")).toString()) == remoteStratumId) {
                    remoteSampleId = normalizedUuid(remoteSample.value(QStringLiteral("id")).toString());
                    break;
                }
            }
        }

        auto syncLab = std::make_shared<std::function<void()>>();
        *syncLab = [this, ctx, fail, remoteStratumId, localRow, extra, done]() {
            QString primarySucs = trimmedText(extra.value(QStringLiteral("primary_sucs"))).toUpper();
            QString secondarySucs = trimmedText(extra.value(QStringLiteral("secondary_sucs"))).toUpper();
            const bool composite = extra.value(QStringLiteral("is_composite")).toBool();
            static const QSet<QString> webSucs = {
                "GW", "GP", "GM", "GC", "SW", "SP", "SM", "SC",
                "ML", "CL", "OL", "MH", "CH", "OH", "PT"
            };
            // Autoridad del laboratorio (contrato Web upsert_my_calicata_lab_result_v02):
            // primary_sucs / is_composite / secondary_sucs / aashto adoptados en
            // Laboratorio. Nunca se derivan del valor anterior del estrato.
            if (!webSucs.contains(primarySucs)) primarySucs.clear();
            if (!webSucs.contains(secondarySucs) || secondarySucs == primarySucs) secondarySucs.clear();
            const QString aashto = validAashto(trimmedText(extra.value(QStringLiteral("lab_confirmed_aashto"))));
            const QVariant sieveMax = nullableNumber(localRow.value(QStringLiteral("gmax")));
            const QVariant sieveNo4 = nullableNumber(extra.value(QStringLiteral("passing_no4")));
            const QVariant sieve2 = nullableNumber(localRow.value(QStringLiteral("g2")));
            const QVariant sieve04 = nullableNumber(localRow.value(QStringLiteral("g04")));
            const QVariant sieve008 = nullableNumber(localRow.value(QStringLiteral("g008")));
            const QVariant ll = nullableNumber(localRow.value(QStringLiteral("wl")));
            const QVariant lp = nullableNumber(localRow.value(QStringLiteral("lp")));
            // calicata_lab_results.liquid_limit / plastic_limit son integer (Web
            // validateInteger). Un decimal de una ficha anterior no se redondea:
            // ese resultado queda pendiente, visible, con el valor local intacto.
            const auto fractional = [](const QVariant &v) {
                if (!v.isValid() || v.isNull()) return false;
                const double d = v.toDouble();
                return d != static_cast<double>(static_cast<qint64>(d));
            };
            const bool decimalLimits = fractional(ll) || fractional(lp);
            const auto markPending = [ctx](const QString &reason, bool pending) {
                if (ctx->index >= 0 && ctx->index < ctx->cortes.size())
                    ctx->cortes[ctx->index] = withLabPending(ctx->cortes.at(ctx->index).toMap(), reason, pending);
            };
            const QVariant moisture = nullableNumber(localRow.value(QStringLiteral("hum2")));
            const QString source = trimmedText(extra.value(QStringLiteral("laboratory_source")));
            const QString testDate = trimmedText(extra.value(QStringLiteral("test_date")));

            const bool hasLab = sieveMax.isValid() || sieveNo4.isValid() || sieve2.isValid()
                || sieve04.isValid() || sieve008.isValid() || ll.isValid() || lp.isValid()
                || moisture.isValid() || !primarySucs.isEmpty() || !aashto.isEmpty()
                || !source.isEmpty() || !testDate.isEmpty();
            if (!hasLab) {
                markPending(QStringLiteral("LAB_LIMITS"), false);
                markPending(QStringLiteral("LAB_INVALID"), false);
                done();
                return;
            }
            // Web no guarda una fila de laboratorio inválida (validateCalicataLaboratoryForm):
            // queda local y pendiente hasta corregirla en Laboratorio.
            const bool labInvalid = extra.value(QStringLiteral("web_lab_valid")).typeId() == QMetaType::Bool
                && !extra.value(QStringLiteral("web_lab_valid")).toBool();
            markPending(QStringLiteral("LAB_INVALID"), labInvalid && !decimalLimits);
            if (labInvalid && !decimalLimits) {
                qWarning().noquote() << "INGE_LAB_CLOUD_PENDING reason=LAB_INVALID stratumId=" << remoteStratumId;
                done();
                return;
            }
            if (decimalLimits) {
                qWarning().noquote() << "INGE_LAB_CLOUD_PENDING reason=LAB_LIMITS_NOT_INTEGER stratumId=" << remoteStratumId;
                markPending(QStringLiteral("LAB_LIMITS"), true);
                done();
                return;
            }

            QVariantMap args;
            args[QStringLiteral("p_project_id")] = ctx->projectId;
            args[QStringLiteral("p_calicata_id")] = ctx->remoteId;
            args[QStringLiteral("p_stratum_id")] = remoteStratumId;
            args[QStringLiteral("p_expected_calicata_row_version")] = ctx->rowVersion;
            args[QStringLiteral("p_sieve_max_pct")] = sieveMax;
            args[QStringLiteral("p_sieve_no4_pct")] = sieveNo4;
            args[QStringLiteral("p_sieve_2mm_pct")] = sieve2;
            args[QStringLiteral("p_sieve_04mm_pct")] = sieve04;
            args[QStringLiteral("p_sieve_008mm_pct")] = sieve008;
            args[QStringLiteral("p_liquid_limit")] = ll;
            args[QStringLiteral("p_plastic_limit")] = lp;
            args[QStringLiteral("p_natural_moisture_pct")] = moisture;
            args[QStringLiteral("p_primary_sucs")] = primarySucs.isEmpty() ? QVariant() : QVariant(primarySucs);
            args[QStringLiteral("p_is_composite")] = composite && !primarySucs.isEmpty() && !secondarySucs.isEmpty();
            args[QStringLiteral("p_secondary_sucs")] = composite && !secondarySucs.isEmpty() ? QVariant(secondarySucs) : QVariant();
            args[QStringLiteral("p_aashto")] = aashto.isEmpty() ? QVariant() : QVariant(aashto);
            args[QStringLiteral("p_laboratory_source")] = source.isEmpty() ? QVariant() : QVariant(source);
            args[QStringLiteral("p_test_date")] = testDate.isEmpty() ? QVariant() : QVariant(testDate);

            postRpc(QStringLiteral("upsert_my_calicata_lab_result_v02"), args,
                    [ctx, fail, done, markPending](bool ok, const QJsonDocument &document,
                                                   const QString &code, const QString &message) {
                if (!ok) { fail(code, message); return; }
                const QVariantMap row = firstRow(document);
                const qint64 version = row.value(QStringLiteral("calicata_row_version")).toLongLong();
                if (version != ctx->rowVersion + 1) {
                    fail({}, QStringLiteral("El laboratorio devolvió una versión de calicata incoherente."));
                    return;
                }
                ctx->rowVersion = version;
                if (ctx->doc && !ctx->doc->checkpointCloudRevision(ctx->projectId, ctx->remoteId, version)) {
                    fail(QStringLiteral("LOCAL_PERSISTENCE"), ctx->doc->errorString());
                    return;
                }
                markPending(QStringLiteral("LAB_LIMITS"), false);
                done();
            });
        };

        if (sampleType.isEmpty()) {
            // If this Android row is explicitly linked to a canonical Web sample and the
            // user clears the sample type, remove that one sample through the canonical
            // RPC. Additional Web samples are never deleted implicitly.
            const QString explicitlyLinked = normalizedUuid(
                localRow.value(QStringLiteral("remote_sample_id")).toString());
            if (explicitlyLinked.isEmpty()) { (*syncLab)(); return; }
            QVariantMap deleteArgs;
            deleteArgs[QStringLiteral("p_project_id")] = ctx->projectId;
            deleteArgs[QStringLiteral("p_calicata_id")] = ctx->remoteId;
            deleteArgs[QStringLiteral("p_stratum_id")] = remoteStratumId;
            deleteArgs[QStringLiteral("p_sample_id")] = explicitlyLinked;
            deleteArgs[QStringLiteral("p_expected_calicata_row_version")] = ctx->rowVersion;
            postRpc(QStringLiteral("delete_my_calicata_sample_v01"), deleteArgs,
                    [this, ctx, fail, syncLab, explicitlyLinked](bool ok,
                        const QJsonDocument &document, const QString &code, const QString &message) {
                if (!ok) { fail(code, message); return; }
                const QVariantMap result = firstRow(document);
                const qint64 version = result.value(QStringLiteral("calicata_row_version")).toLongLong();
                if (normalizedUuid(result.value(QStringLiteral("deleted_sample_id")).toString()) != explicitlyLinked
                    || version != ctx->rowVersion + 1) {
                    fail({}, QStringLiteral("El servidor no confirmó la eliminación de la muestra."));
                    return;
                }
                ctx->rowVersion = version;
                if (ctx->doc && !ctx->doc->checkpointCloudRevision(ctx->projectId, ctx->remoteId, version)) {
                    fail(QStringLiteral("LOCAL_PERSISTENCE"), ctx->doc->errorString());
                    return;
                }
                if (ctx->index >= 0 && ctx->index < ctx->cortes.size()) {
                    QVariantMap local = ctx->cortes.at(ctx->index).toMap();
                    local.remove(QStringLiteral("remote_sample_id"));
                    local.remove(QStringLiteral("sample_code"));
                    ctx->cortes[ctx->index] = local;
                }
                (*syncLab)();
            });
            return;
        }

        QVariantMap sampleArgs;
        sampleArgs[QStringLiteral("p_project_id")] = ctx->projectId;
        sampleArgs[QStringLiteral("p_calicata_id")] = ctx->remoteId;
        sampleArgs[QStringLiteral("p_stratum_id")] = remoteStratumId;
        sampleArgs[QStringLiteral("p_expected_calicata_row_version")] = ctx->rowVersion;
        const QString sampleCode = trimmedText(localRow.value(QStringLiteral("sample_code"))).isEmpty()
            ? QStringLiteral("%1-M%2").arg(trimmedText(ctx->header.value(QStringLiteral("code"),
                                        ctx->header.value(QStringLiteral("codigo")))))
                                      .arg(ctx->index + 1)
            : trimmedText(localRow.value(QStringLiteral("sample_code")));
        sampleArgs[QStringLiteral("p_sample_code")] = sampleCode;
        sampleArgs[QStringLiteral("p_sample_type")] = sampleType;
        QVariant sampleFrom = nullableDepth(localRow.value(QStringLiteral("muestra_desde")));
        QVariant sampleTo = nullableDepth(localRow.value(QStringLiteral("muestra_hasta")));
        if (!sampleFrom.isValid()) sampleFrom = nullableDepth(localRow.value(QStringLiteral("de")));
        if (!sampleTo.isValid()) sampleTo = nullableDepth(localRow.value(QStringLiteral("a")));
        sampleArgs[QStringLiteral("p_from_depth_m")] = sampleFrom;
        sampleArgs[QStringLiteral("p_to_depth_m")] = sampleTo;

        QString rpc = QStringLiteral("add_my_calicata_sample_v01");
        if (!remoteSampleId.isEmpty()) {
            rpc = QStringLiteral("update_my_calicata_sample_v01");
            sampleArgs[QStringLiteral("p_sample_id")] = remoteSampleId;
        }
        postRpc(rpc, sampleArgs,
                [this, ctx, fail, syncLab, remoteSampleId, sampleCode](bool ok,
                    const QJsonDocument &document, const QString &code, const QString &message) {
            if (!ok) { fail(code, message); return; }
            const QVariantMap result = firstRow(document);
            const qint64 version = result.value(QStringLiteral("calicata_row_version")).toLongLong();
            if (version != ctx->rowVersion + 1) {
                fail({}, QStringLiteral("La muestra devolvió una versión de calicata incoherente."));
                return;
            }
            ctx->rowVersion = version;
            if (ctx->doc && !ctx->doc->checkpointCloudRevision(ctx->projectId, ctx->remoteId, version)) {
                fail(QStringLiteral("LOCAL_PERSISTENCE"), ctx->doc->errorString());
                return;
            }
            if (ctx->index >= 0 && ctx->index < ctx->cortes.size()) {
                QVariantMap local = ctx->cortes.at(ctx->index).toMap();
                local[QStringLiteral("remote_sample_id")] = result.value(QStringLiteral("id"));
                local[QStringLiteral("sample_code")] = sampleCode;
                ctx->cortes[ctx->index] = local;
            }
            (*syncLab)();
        });
    };

    *syncOneStratum = [this, ctx, fail, syncOneStratum, syncSampleAndLab, finalizeSmartDocument]() {
        if (!ctx->doc) return;
        if (ctx->index >= ctx->cortes.size()) {
            (*finalizeSmartDocument)();
            return;
        }

        QVariantMap local = ctx->cortes.at(ctx->index).toMap();
        QString remoteStratumId = normalizedUuid(local.value(QStringLiteral("remote_stratum_id")).toString());
        QVariantMap paired;
        if (!remoteStratumId.isEmpty()) {
            for (const QVariant &value : ctx->remoteStrata) {
                const QVariantMap row = value.toMap();
                if (normalizedUuid(row.value(QStringLiteral("id")).toString()) == remoteStratumId) {
                    paired = row; break;
                }
            }
        }
        if (!remoteStratumId.isEmpty() && paired.isEmpty()) {
            fail(QStringLiteral("40001"), QStringLiteral("El UUID del estrato ya no existe en la ficha remota. Reconciliación requerida."));
            return;
        }
        // add_my_calicata_stratum_v03 only appends. A new local stratum is
        // valid once every remote stratum has been paired by UUID before it;
        // one inserted between synced strata needs a reorder RPC the backend
        // does not expose (BLOCKED_BY_BACKEND_SCHEMA), never an index guess.
        if (remoteStratumId.isEmpty() && ctx->index < ctx->remoteStrata.size()) {
            fail(QStringLiteral("40001"), QStringLiteral("Estrato nuevo entre estratos ya sincronizados: el servidor solo permite agregarlos al final. Muévelo al final o sincroniza antes de insertarlo."));
            return;
        }
        if (!paired.isEmpty() && paired.value(QStringLiteral("sequence_number")).toInt() != ctx->index + 1) {
            fail(QStringLiteral("40001"), QStringLiteral("El orden local difiere del remoto. No hay RPC autorizado para mover UUIDs."));
            return;
        }

        auto update = [this, ctx, fail, syncOneStratum, syncSampleAndLab, local]
                      (const QString &stratumId) mutable {
            const QVariant toDepth = nullableDepth(local.value(QStringLiteral("a")));
            if (!trimmedText(local.value(QStringLiteral("a"))).isEmpty() && !toDepth.isValid()) {
                fail({}, QStringLiteral("Los límites de estrato deben usar pasos de 0.05 m antes de sincronizar."));
                return;
            }
            QVariantMap args;
            args[QStringLiteral("p_project_id")] = ctx->projectId;
            args[QStringLiteral("p_calicata_id")] = ctx->remoteId;
            args[QStringLiteral("p_stratum_id")] = stratumId;
            args[QStringLiteral("p_expected_calicata_row_version")] = ctx->rowVersion;
            args[QStringLiteral("p_to_depth_m")] = toDepth;
            args[QStringLiteral("p_description")] = nullableText(local.value(QStringLiteral("descripcion")));
            const QString moisture = moistureFor(local);
            const QString consistency = consistencyFor(local);
            const QString excavability = excavabilityFor(local);
            const QString color = normalizedColor(local);
            const QString sampleType = sampleTypeFor(local);
            const QVariantMap extra = extraFor(local);
            args[QStringLiteral("p_moisture_condition")] = moisture.isEmpty() ? QVariant() : QVariant(moisture);
            args[QStringLiteral("p_consistency_compaction")] = consistency.isEmpty() ? QVariant() : QVariant(consistency);
            args[QStringLiteral("p_excavability")] = excavability.isEmpty() ? QVariant() : QVariant(excavability);
            args[QStringLiteral("p_color")] = color.isEmpty() ? QVariant() : QVariant(color);
            args[QStringLiteral("p_sample_type")] = sampleType.isEmpty() ? QVariant() : QVariant(sampleType);
            args[QStringLiteral("p_observations")] = nullableText(extra.value(QStringLiteral("observations")));
            postRpc(QStringLiteral("update_my_calicata_stratum_v03"), args,
                    [this, ctx, fail, syncOneStratum, syncSampleAndLab, stratumId]
                    (bool ok, const QJsonDocument &document, const QString &code, const QString &message) {
                if (!ok) { fail(code, message); return; }
                const QVariantMap result = firstRow(document);
                const qint64 version = result.value(QStringLiteral("calicata_row_version")).toLongLong();
                if (version != ctx->rowVersion + 1) {
                    fail({}, QStringLiteral("El estrato devolvió una versión de calicata incoherente."));
                    return;
                }
                ctx->rowVersion = version;
                if (ctx->doc && !ctx->doc->checkpointCloudRevision(ctx->projectId, ctx->remoteId, version)) {
                    fail(QStringLiteral("LOCAL_PERSISTENCE"), ctx->doc->errorString());
                    return;
                }
                if (ctx->index < ctx->cortes.size()) {
                    QVariantMap localRow = ctx->cortes.at(ctx->index).toMap();
                    localRow[QStringLiteral("remote_stratum_id")] = stratumId;
                    localRow[QStringLiteral("remote_sequence_number")] = result.value(QStringLiteral("sequence_number"));
                    ctx->cortes[ctx->index] = localRow;
                }
                const QVariantMap localRow = ctx->cortes.at(ctx->index).toMap();
                (*syncSampleAndLab)(stratumId, localRow, [ctx, syncOneStratum]() {
                    ++ctx->index;
                    (*syncOneStratum)();
                });
            });
        };

        if (!remoteStratumId.isEmpty()) { update(remoteStratumId); return; }
        QVariantMap args;
        args[QStringLiteral("p_project_id")] = ctx->projectId;
        args[QStringLiteral("p_calicata_id")] = ctx->remoteId;
        args[QStringLiteral("p_expected_calicata_row_version")] = ctx->rowVersion;
        postRpc(QStringLiteral("add_my_calicata_stratum_v03"), args,
                [this, ctx, fail, update](bool ok, const QJsonDocument &document,
                                    const QString &code, const QString &message) mutable {
            if (!ok) { fail(code, message); return; }
            const QVariantMap result = firstRow(document);
            const QString id = normalizedUuid(result.value(QStringLiteral("id")).toString());
            const qint64 version = result.value(QStringLiteral("calicata_row_version")).toLongLong();
            if (id.isEmpty() || version != ctx->rowVersion + 1) {
                fail({}, QStringLiteral("El servidor no confirmó el nuevo estrato."));
                return;
            }
            ctx->rowVersion = version;
            if (ctx->doc && !ctx->doc->checkpointCloudRevision(ctx->projectId, ctx->remoteId, version)) {
                fail(QStringLiteral("LOCAL_PERSISTENCE"), ctx->doc->errorString());
                return;
            }
            if (ctx->index < ctx->cortes.size()) {
                QVariantMap localRow = ctx->cortes.at(ctx->index).toMap();
                localRow[QStringLiteral("remote_stratum_id")] = id;
                ctx->cortes[ctx->index] = localRow;
                const QString localStratumId = trimmedText(localRow.value(QStringLiteral("local_stratum_id"),
                                                     extraFor(localRow).value(QStringLiteral("local_stratum_id"))));
                if (ctx->doc) ctx->doc->bindStratumIdentity(localStratumId, id);
            }
            update(id);
        });
    };

    std::weak_ptr<std::function<void()>> weakSyncStrata = syncStrata;
    *syncStrata = [this, ctx, fail, syncOneStratum, weakSyncStrata]() {
        const auto syncStrata = weakSyncStrata.lock();
        if (!syncStrata || !ctx->doc) return;
        if (++ctx->strataPasses > 64) {
            fail({}, QStringLiteral("Demasiadas pasadas de sincronización de estratos; se reintentará."));
            return;
        }
        auto *api = appContext() ? appContext()->supabase() : nullptr;
        if (!api) { fail({}, QStringLiteral("Supabase no está disponible.")); return; }
        QUrl strataUrl = api->restUrl(QStringLiteral("calicata_strata"));
        QUrlQuery strataQuery;
        strataQuery.addQueryItem(QStringLiteral("select"), QStringLiteral(
            "id,calicata_id,sequence_number,from_depth_m,to_depth_m,description,moisture_condition,consistency_compaction,excavability,color,sample_type,sucs,aashto,observations,created_at,updated_at"));
        strataQuery.addQueryItem(QStringLiteral("calicata_id"), QStringLiteral("eq.") + ctx->remoteId);
        strataQuery.addQueryItem(QStringLiteral("order"), QStringLiteral("sequence_number.asc"));
        strataUrl.setQuery(strataQuery);
        getJson(strataUrl, [this, ctx, fail, syncOneStratum, syncStrata](bool ok,
            const QJsonDocument &document, const QString &code, const QString &message) {
            if (!ok) { fail(code, message); return; }
            ctx->remoteStrata = rows(document);
            // P3 remote delete: one CAS delete per tombstone, then refetch so
            // sequence numbers are the server's. Already-gone UUIDs are done.
            while (!ctx->tombstones.isEmpty()) {
                const QString target = ctx->tombstones.first();
                bool present = false;
                for (const QVariant &value : ctx->remoteStrata)
                    if (normalizedUuid(value.toMap().value(QStringLiteral("id")).toString()) == target) present = true;
                if (!present) { ctx->deletedConfirmed << ctx->tombstones.takeFirst(); continue; }
                postRpc(QStringLiteral("delete_my_calicata_stratum_v02"),
                        {{QStringLiteral("p_project_id"), ctx->projectId}, {QStringLiteral("p_calicata_id"), ctx->remoteId},
                         {QStringLiteral("p_stratum_id"), target},
                         {QStringLiteral("p_expected_calicata_row_version"), ctx->rowVersion},
                         {QStringLiteral("p_confirm_nonempty"), true}},
                        [service = this, ctx, fail, syncStrata, target](bool okDelete, const QJsonDocument &deleted,
                                                        const QString &codeDelete, const QString &messageDelete) {
                    if (!okDelete) { fail(codeDelete, messageDelete); return; }
                    const QVariantMap row = firstRow(deleted);
                    const qint64 version = row.value(QStringLiteral("calicata_row_version")).toLongLong();
                    if (normalizedUuid(row.value(QStringLiteral("deleted_stratum_id")).toString()) != target
                        || version != ctx->rowVersion + 1) {
                        fail({}, QStringLiteral("El servidor no confirmó la eliminación del estrato."));
                        return;
                    }
                    ctx->rowVersion = version;
                    if (ctx->doc && !ctx->doc->checkpointCloudRevision(ctx->projectId, ctx->remoteId, version)) {
                        fail(QStringLiteral("LOCAL_PERSISTENCE"), ctx->doc->errorString());
                        return;
                    }
                    ctx->tombstones.removeAll(target);
                    ctx->deletedConfirmed << target;
                    qInfo().noquote() << "INGE_CALICATA_STRATUM_DELETED stratumId=" << target;
                    Q_UNUSED(service);
                    (*syncStrata)();
                });
                return;
            }
            auto *api = appContext() ? appContext()->supabase() : nullptr;
            QUrl samplesUrl = api->restUrl(QStringLiteral("calicata_samples"));
            QUrlQuery samplesQuery;
            samplesQuery.addQueryItem(QStringLiteral("select"), QStringLiteral(
                "id,calicata_id,stratum_id,sample_code,sample_type,from_depth_m,to_depth_m,observations,created_at,updated_at"));
            samplesQuery.addQueryItem(QStringLiteral("calicata_id"), QStringLiteral("eq.") + ctx->remoteId);
            samplesQuery.addQueryItem(QStringLiteral("order"), QStringLiteral("created_at.asc"));
            samplesUrl.setQuery(samplesQuery);
            getJson(samplesUrl, [ctx, fail, syncOneStratum](bool samplesOk,
                const QJsonDocument &samplesDocument, const QString &samplesCode,
                const QString &samplesMessage) {
                if (!samplesOk) { fail(samplesCode, samplesMessage); return; }
                ctx->remoteSamples = rows(samplesDocument);
                ctx->index = 0;
                (*syncOneStratum)();
            });
        });
    };

    auto updateRoot = [this, ctx, fail, syncStrata]() {
        QVariantMap changes;
        const auto value = [&ctx](const char *canonical, const char *legacy = nullptr) -> QVariant {
            QVariant v = ctx->header.value(QString::fromLatin1(canonical));
            if ((!v.isValid() || trimmedText(v).isEmpty()) && legacy)
                v = ctx->header.value(QString::fromLatin1(legacy));
            return v;
        };
        changes[QStringLiteral("code")] = trimmedText(value("code", "codigo"));
        changes[QStringLiteral("title")] = nullableText(value("title", "titulo"));
        // `location` is the road side (Web "Lado de la vía"). Android's
        // "Ubicación / Tramo" (`ubicacion`) is local and never travels here.
        changes[QStringLiteral("location")] = nullableText(value("location", "lado_via"));
        changes[QStringLiteral("progresiva")] = nullableText(value("progresiva", "pk"));
        changes[QStringLiteral("easting")] = nullableNumber(value("easting", "utm_x"));
        changes[QStringLiteral("northing")] = nullableNumber(value("northing", "utm_y"));
        changes[QStringLiteral("altitude_m")] = nullableNumber(value("altitude_m", "utm_z"));
        // Derived from the cortes by the form; the manual target depth
        // (`final_depth_m`/`requested_depth_m`) is local only.
        changes[QStringLiteral("depth_m")] = nullableNumber(value("depth_m"));
        const QString waterStatus = trimmedText(ctx->header.value(QStringLiteral("water_table_status"))).toUpper();
        changes[QStringLiteral("groundwater_depth_m")] = waterStatus == QLatin1String("ENCONTRADO")
            ? nullableNumber(value("groundwater_depth_m", "water_table_depth")) : QVariant();
        changes[QStringLiteral("utm_zone")] = canonicalUtmZone(value("utm_zone", "zona"));
        changes[QStringLiteral("supervisor")] = nullableText(value("supervisor"));
        changes[QStringLiteral("machine")] = nullableText(value("machine", "maquina"));
        changes[QStringLiteral("start_date")] = nullableText(value("start_date", "fecha_inicio"));
        changes[QStringLiteral("end_date")] = nullableText(value("end_date", "fecha_fin"));
        // Hora de la ficha y metadato de la cota (cross-device, 20261007181000).
        changes[QStringLiteral("start_time")] = nullableTime(value("start_time", "hora_inicio"));
        changes[QStringLiteral("altitude_source")] = nullableEnum(value("altitude_source"),
                                                                  {"MANUAL", "GOOGLE_ELEVATION", "DEM", "GPS_ELIPSOIDAL"});
        changes[QStringLiteral("altitude_mode")] = nullableEnum(value("altitude_mode"), {"MANUAL", "AUTOMATICA"});
        changes[QStringLiteral("altitude_confidence")] = nullableEnum(value("altitude_confidence"), {"ALTA", "MEDIA", "BAJA"});
        changes[QStringLiteral("altitude_accuracy_m")] = nullableNumber(value("altitude_accuracy_m"));
        changes[QStringLiteral("altitude_vertical_reference")] = nullableEnum(value("altitude_vertical_reference"),
                                                                              {"terrain_msl", "ellipsoid", "unknown"});
        changes[QStringLiteral("altitude_resolved_at")] = nullableText(value("altitude_resolved_at"));
        changes[QStringLiteral("altitude_evidence")] = nullableEvidence(ctx->header.value(QStringLiteral("altitude_evidence")));
        // "Título de la ficha / testificación". The Android-only technical
        // description (`technical_description`) is local and never replaces it.
        changes[QStringLiteral("description")] = nullableText(value("description"));
        changes[QStringLiteral("observations")] = nullableText(ctx->observations);
        changes[QStringLiteral("status")] = canonicalStatus(ctx->header.value(QStringLiteral("status")));

        QUrlQuery query;
        query.addQueryItem(QStringLiteral("id"), QStringLiteral("eq.") + ctx->remoteId);
        query.addQueryItem(QStringLiteral("project_id"), QStringLiteral("eq.") + ctx->projectId);
        query.addQueryItem(QStringLiteral("row_version"), QStringLiteral("eq.") + QString::number(ctx->rowVersion));
        query.addQueryItem(QStringLiteral("select"), QStringLiteral(
            "id,project_id,code,title,location,progresiva,easting,northing,altitude_m,depth_m,groundwater_depth_m,utm_zone,supervisor,machine,start_date,end_date,start_time,description,observations,status,altitude_source,altitude_mode,altitude_confidence,altitude_accuracy_m,altitude_vertical_reference,altitude_resolved_at,altitude_evidence,created_by,created_at,updated_at,row_version"));
        patchRows(QStringLiteral("calicatas"), query, changes,
                  [this, ctx, fail, syncStrata](bool ok, const QJsonDocument &document,
                                           const QString &code, const QString &message) {
            if (!ok) { fail(code, message); return; }
            const QVariantMap row = firstRow(document);
            if (row.isEmpty()) {
                // Web probes the readable row before classifying an empty CAS
                // update as stale. Keep the same distinction on Android.
                auto *api = appContext() ? appContext()->supabase() : nullptr;
                if (!api) { fail({}, QStringLiteral("Supabase no está disponible.")); return; }
                QUrl probeUrl = api->restUrl(QStringLiteral("calicatas"));
                QUrlQuery probe;
                probe.addQueryItem(QStringLiteral("select"), QStringLiteral("id,project_id,row_version"));
                probe.addQueryItem(QStringLiteral("id"), QStringLiteral("eq.") + ctx->remoteId);
                probe.addQueryItem(QStringLiteral("project_id"), QStringLiteral("eq.") + ctx->projectId);
                probe.addQueryItem(QStringLiteral("limit"), QStringLiteral("1"));
                probeUrl.setQuery(probe);
                getJson(probeUrl, [ctx, fail](bool probeOk, const QJsonDocument &probeDoc,
                                              const QString &probeCode, const QString &probeMessage) {
                    if (!probeOk) { fail(probeCode, probeMessage); return; }
                    const QVariantMap current = firstRow(probeDoc);
                    if (!current.isEmpty()
                        && current.value(QStringLiteral("row_version")).toLongLong() != ctx->rowVersion) {
                        qWarning() << "INGE_CALICATA_ROOT_STALE expected=" << ctx->rowVersion
                                   << "actual=" << current.value(QStringLiteral("row_version")).toLongLong();
                        fail(QStringLiteral("40001"), QStringLiteral("CALICATA_ROOT_STALE"));
                        return;
                    }
                    fail({}, QStringLiteral("La calicata existe pero el servidor no autorizó la actualización raíz."));
                });
                return;
            }
            const qint64 version = row.value(QStringLiteral("row_version")).toLongLong();
            if (row.value(QStringLiteral("id")).toString() != ctx->remoteId
                || row.value(QStringLiteral("project_id")).toString() != ctx->projectId
                || version != ctx->rowVersion + 1) {
                fail({}, QStringLiteral("El servidor devolvió una versión raíz incoherente."));
                return;
            }
            ctx->rowVersion = version;
            if (ctx->doc && !ctx->doc->checkpointCloudRevision(ctx->projectId, ctx->remoteId, version)) {
                fail(QStringLiteral("LOCAL_PERSISTENCE"), ctx->doc->errorString());
                return;
            }
            ctx->serverRoot = row;
            ctx->header[QStringLiteral("remoteCalicataId")] = ctx->remoteId;
            ctx->header[QStringLiteral("row_version")] = ctx->rowVersion;
            (*syncStrata)();
        });
    };

    if (!ctx->remoteId.isEmpty() && ctx->rowVersion >= 1) {
        updateRoot();
        return ctx->localId;
    }

    QVariantMap args;
    args[QStringLiteral("p_project_id")] = ctx->projectId;
    args[QStringLiteral("p_code")] = code;
    args[QStringLiteral("p_title")] = nullableText(header.value(QStringLiteral("title")));
    args[QStringLiteral("p_location")] = nullableText(header.value(QStringLiteral("location"),
                                                      header.value(QStringLiteral("lado_via"))));
    args[QStringLiteral("p_progresiva")] = nullableText(header.value(QStringLiteral("progresiva"),
                                                        header.value(QStringLiteral("pk"))));
    args[QStringLiteral("p_easting")] = nullableNumber(header.value(QStringLiteral("easting"),
                                                      header.value(QStringLiteral("utm_x"))));
    args[QStringLiteral("p_northing")] = nullableNumber(header.value(QStringLiteral("northing"),
                                                       header.value(QStringLiteral("utm_y"))));
    args[QStringLiteral("p_altitude_m")] = nullableNumber(header.value(QStringLiteral("altitude_m"),
                                                         header.value(QStringLiteral("utm_z"))));
    args[QStringLiteral("p_depth_m")] = nullableNumber(header.value(QStringLiteral("depth_m")));
    const QString water = trimmedText(header.value(QStringLiteral("water_table_status"))).toUpper();
    args[QStringLiteral("p_groundwater_depth_m")] = water == QLatin1String("ENCONTRADO")
        ? nullableNumber(header.value(QStringLiteral("groundwater_depth_m"),
                                     header.value(QStringLiteral("water_table_depth")))) : QVariant();
    args[QStringLiteral("p_description")] = nullableText(header.value(QStringLiteral("description")));
    args[QStringLiteral("p_observations")] = nullableText(document->observaciones());

    postRpc(QStringLiteral("create_my_project_calicata_v02"), args,
            [ctx, fail, updateRoot, bindIdentity](bool ok, const QJsonDocument &document,
                                    const QString &codeValue, const QString &message) mutable {
        if (!ok) { fail(codeValue, message); return; }
        const QVariantMap row = firstRow(document);
        const QString remoteId = normalizedUuid(row.value(QStringLiteral("id")).toString());
        const qint64 rowVersion = row.value(QStringLiteral("row_version")).toLongLong();
        if (remoteId.isEmpty() || row.value(QStringLiteral("project_id")).toString() != ctx->projectId
            || rowVersion != 1) {
            fail({}, QStringLiteral("El servidor no confirmó la creación canónica de la calicata."));
            return;
        }
        ctx->remoteId = remoteId;
        ctx->rowVersion = rowVersion;
        ctx->created = true;
        bindIdentity(true);
        updateRoot();
    });
    return ctx->localId;
}

void CalicataCloudService::patchRemoteStatus(CalicataDocument *document, const QString &status,
                                             StatusCallback callerDone)
{
    // The status PATCH and syncDocument both CAS on calicatas.row_version. Run
    // concurrently from this device, the second one is rejected with 40001
    // against our own write (INGE_CALICATA_SYNC_REJECTED → CONFLICT). The status
    // change therefore runs in the same per-document lane as a sync (it waits).
    const QString localId = document->instanceId();
    auto &lane = m_lanes[localId];
    m_laneDocs[localId] = document;
    if (!lane.tryAcquire()) {
        // Espera su turno (después de la sync en vuelo y de la coalescida): sin CAS paralelo.
        qInfo().noquote() << "INGE_CALICATA_STATUS_QUEUED status=" << status << "generation=" << lane.generation();
        lane.defer([this, target = QPointer<CalicataDocument>(document), localId, status, callerDone]() {
            if (!target || target->closed()) {
                callerDone(false, QStringLiteral("DOCUMENT_CLOSED"), QStringLiteral("La ficha se cerró antes de confirmar el estado."));
                releaseLane(localId);
                return;
            }
            patchRemoteStatus(target, status, callerDone);
        });
        return;
    }
    const StatusCallback done = [this, localId, callerDone](bool ok, const QString &code, const QString &message) {
        callerDone(ok, code, message);
        releaseLane(localId);
    };
    const QVariantMap header = document->header();
    const QString projectId = normalizedUuid(header.value(QStringLiteral("projectId")).toString());
    const QString remoteId = normalizedUuid(header.value(QStringLiteral("remoteCalicataId")).toString());
    const qint64 rowVersion = CalicataSync::expectedRevision(
        header.value(QStringLiteral("remoteRowVersion"), header.value(QStringLiteral("row_version"))).toLongLong(),
        m_confirmedRevisions.value(remoteId));
    if (projectId.isEmpty() || remoteId.isEmpty() || rowVersion < 1) {
        done(false, QStringLiteral("NO_REMOTE_IDENTITY"),
             QStringLiteral("Esta calicata todavía no tiene una identidad remota confirmada."));
        return;
    }
    // Only the status travels here. Content edits not yet confirmed keep the
    // mirror PENDING after the status is confirmed.
    const bool keepPending = document->syncState() != QLatin1String("SYNCED")
        || document->dirty();
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("id"), QStringLiteral("eq.") + remoteId);
    query.addQueryItem(QStringLiteral("project_id"), QStringLiteral("eq.") + projectId);
    query.addQueryItem(QStringLiteral("row_version"), QStringLiteral("eq.") + QString::number(rowVersion));
    query.addQueryItem(QStringLiteral("select"),
                       QStringLiteral("id,project_id,status,row_version,created_by,created_at,updated_at"));
    patchRows(QStringLiteral("calicatas"), query, {{QStringLiteral("status"), status}},
              [this, target = QPointer<CalicataDocument>(document), localId, projectId, remoteId, rowVersion,
               status, keepPending, done](bool ok, const QJsonDocument &json,
                                          const QString &code, const QString &message) {
        if (!ok) { done(false, code, message); return; }
        const QVariantMap row = firstRow(json);
        if (row.isEmpty()) {
            // Same distinction as Web: an empty CAS update is stale only when
            // the readable row moved to another version.
            auto *api = appContext() ? appContext()->supabase() : nullptr;
            if (!api) { done(false, QStringLiteral("NO_API"), QStringLiteral("Supabase no está disponible.")); return; }
            QUrl probeUrl = api->restUrl(QStringLiteral("calicatas"));
            QUrlQuery probe;
            probe.addQueryItem(QStringLiteral("select"), QStringLiteral("id,project_id,row_version,status"));
            probe.addQueryItem(QStringLiteral("id"), QStringLiteral("eq.") + remoteId);
            probe.addQueryItem(QStringLiteral("project_id"), QStringLiteral("eq.") + projectId);
            probe.addQueryItem(QStringLiteral("limit"), QStringLiteral("1"));
            probeUrl.setQuery(probe);
            getJson(probeUrl, [rowVersion, done](bool probeOk, const QJsonDocument &probeDoc,
                                                 const QString &probeCode, const QString &probeMessage) {
                if (!probeOk) { done(false, probeCode, probeMessage); return; }
                const QVariantMap current = firstRow(probeDoc);
                if (!current.isEmpty()
                    && current.value(QStringLiteral("row_version")).toLongLong() != rowVersion) {
                    done(false, QStringLiteral("40001"), QStringLiteral("CALICATA_ROOT_STALE"));
                    return;
                }
                done(false, QStringLiteral("42501"),
                     QStringLiteral("La calicata existe pero el servidor no autorizó el cambio de estado."));
            });
            return;
        }
        if (normalizedUuid(row.value(QStringLiteral("id")).toString()) != remoteId
            || normalizedUuid(row.value(QStringLiteral("project_id")).toString()) != projectId
            || row.value(QStringLiteral("status")).toString() != status
            || row.value(QStringLiteral("row_version")).toLongLong() != rowVersion + 1) {
            done(false, QStringLiteral("INCOHERENT"), QStringLiteral("El servidor no confirmó el cambio de estado."));
            return;
        }
        if (target) {
            target->applyCloudSync(row, target->cortes());
            if (keepPending) target->setSyncState(QStringLiteral("PENDING"));
        }
        noteConfirmedRevision(localId, remoteId, rowVersion + 1);
        auto &statusLane = m_lanes[localId];
        if (!statusLane.baseRoot.isEmpty()) statusLane.baseRoot[QStringLiteral("status")] = status;
        qInfo().noquote() << "INGE_CALICATA_SYNC_OK reason=status previousRevision=" << rowVersion
                          << "confirmedRevision=" << rowVersion + 1;
        done(true, {}, {});
    });
}

void CalicataCloudService::releaseLane(const QString &localId)
{
    auto &lane = m_lanes[localId];
    const CalicataSync::Lane::Next next = lane.release();
    const QPointer<CalicataDocument> doc = m_laneDocs.value(localId);
    if (!next.syncReason.isEmpty()) {
        // La sync coalescida lee el documento al arrancar: sube el snapshot más nuevo.
        QTimer::singleShot(0, this, [this, localId, doc, reason = next.syncReason]() {
            if (!doc || doc->closed() || syncDocument(doc, reason).isEmpty()) {
                // No pudo arrancar (ficha cerrada o validación): el carril sigue drenando.
                if (!m_lanes[localId].busy()) releaseLane(localId);
            }
        });
    } else if (next.operation) {
        QTimer::singleShot(0, this, next.operation);
    }
}

void CalicataCloudService::noteConfirmedRevision(const QString &localId, const QString &remoteId, qint64 revision)
{
    if (remoteId.isEmpty() || revision < 1) return;
    if (revision > m_confirmedRevisions.value(remoteId)) m_confirmedRevisions[remoteId] = revision;
    auto &lane = m_lanes[localId];
    if (revision > lane.confirmedRevision) lane.confirmedRevision = revision;
}

void CalicataCloudService::probeRoot(const QString &projectId, const QString &remoteId,
                                     std::function<void(bool, const QVariantMap &)> done)
{
    auto *api = appContext() ? appContext()->supabase() : nullptr;
    if (!api || projectId.isEmpty() || remoteId.isEmpty()) { done(false, {}); return; }
    QUrl url = api->restUrl(QStringLiteral("calicatas"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("select"),
                       CalicataSync::rootColumns().join(QLatin1Char(',')) + QStringLiteral(",row_version"));
    query.addQueryItem(QStringLiteral("id"), QStringLiteral("eq.") + remoteId);
    query.addQueryItem(QStringLiteral("project_id"), QStringLiteral("eq.") + projectId);
    query.addQueryItem(QStringLiteral("limit"), QStringLiteral("1"));
    url.setQuery(query);
    getJson(url, [done](bool ok, const QJsonDocument &document, const QString &, const QString &) {
        const QVariantMap row = ok ? firstRow(document) : QVariantMap();
        done(ok && row.value(QStringLiteral("row_version")).toLongLong() > 0, row);
    });
}

namespace {
bool isOfflineCode(const QString &code)
{
    // Transport failures carry no PostgREST code; a missing session is
    // treated the same way: the work stays local and syncs later.
    return code.isEmpty() || code == QLatin1String("AUTH_REQUIRED");
}

bool isConflictCode(const QString &code, const QString &message)
{
    return code == QLatin1String("40001") || message.contains(QStringLiteral("STALE"), Qt::CaseInsensitive);
}

QVariantMap activityMetadata(CalicataDocument *document)
{
    const QVariantMap header = document->header();
    QVariantMap metadata;
    metadata[QStringLiteral("code")] = trimmedText(header.value(QStringLiteral("code"),
                                                                header.value(QStringLiteral("codigo"))));
    metadata[QStringLiteral("title")] = nullableText(header.value(QStringLiteral("title")));
    return metadata;
}
} // namespace

QString CalicataCloudService::archiveDocument(CalicataDocument *document)
{
    if (!document || document->closed()) return {};
    const QString localId = document->instanceId();
    const QString previous = document->status();
    if (previous == QLatin1String("ARCHIVADO")) {
        setLastError(QStringLiteral("La calicata ya está archivada."));
        emit archiveFailed(localId, m_lastError);
        return {};
    }
    const QString remoteId = normalizedUuid(document->header().value(QStringLiteral("remoteCalicataId")).toString());
    if (remoteId.isEmpty()) {
        // A draft that never reached Supabase is archived locally; its data stays.
        if (!document->transitionStatus(QStringLiteral("ARCHIVADO"))) {
            setLastError(document->errorString());
            emit archiveFailed(localId, m_lastError);
            return {};
        }
        QTimer::singleShot(0, this, [this, localId]() { emit archiveSucceeded(localId); });
        return localId;
    }

    QVariantMap metadata = activityMetadata(document);
    metadata[QStringLiteral("previous_status")] = previous;
    metadata[QStringLiteral("new_status")] = QStringLiteral("ARCHIVADO");
    const QString projectId = normalizedUuid(document->header().value(QStringLiteral("projectId")).toString());
    patchRemoteStatus(document, QStringLiteral("ARCHIVADO"),
                      [this, target = QPointer<CalicataDocument>(document), localId, projectId, remoteId, metadata]
                      (bool confirmed, const QString &code, const QString &message) {
        if (!confirmed) {
            if (target && isConflictCode(code, message)) target->setSyncState(QStringLiteral("CONFLICT"));
            setLastError(isOfflineCode(code)
                ? QStringLiteral("Archivar una calicata sincronizada requiere conexión. Los datos locales se conservan.")
                : humanCloudError(code, message));
            emit archiveFailed(localId, m_lastError);
            return;
        }
        setLastError({});
        enqueueActivity(projectId, remoteId, QStringLiteral("ARCHIVE_CALICATA"),
                        QStringLiteral("Calicata archivada: %1").arg(metadata.value(QStringLiteral("code")).toString()),
                        metadata);
        emit archiveSucceeded(localId);
    });
    return localId;
}

QString CalicataCloudService::changeStatus(CalicataDocument *document, const QString &status)
{
    if (!document || document->closed()) return {};
    const QString next = status.trimmed().toUpper();
    if (next == QLatin1String("ARCHIVADO"))
        return archiveDocument(document);
    const QString localId = document->instanceId();
    const QString projectId = normalizedUuid(document->header().value(QStringLiteral("projectId")).toString());
    const QString remoteId = normalizedUuid(document->header().value(QStringLiteral("remoteCalicataId")).toString());
    if (projectId.isEmpty() || remoteId.isEmpty()) {
        commitStatusChange(document, next);
        return localId;
    }
    // Flujo Web (CalicataDetailPanel.handleStatusTransition): el servidor decide
    // qué transiciones ofrece a este usuario (get_my_calicata_status_actions_v01)
    // y luego el estado viaja por la misma actualización CAS de la ficha.
    QVariantMap args;
    args[QStringLiteral("p_project_id")] = projectId;
    args[QStringLiteral("p_calicata_id")] = remoteId;
    postRpc(QStringLiteral("get_my_calicata_status_actions_v01"), args,
            [this, target = QPointer<CalicataDocument>(document), localId, next]
            (bool ok, const QJsonDocument &json, const QString &code, const QString &message) {
        if (!target || target->closed()) {
            emit statusChangeFailed(localId, QStringLiteral("La ficha se cerró antes de confirmar el estado."));
            return;
        }
        if (!ok && !isOfflineCode(code)) {
            setLastError(humanCloudError(code, message));
            emit statusChangeFailed(localId, m_lastError);
            return;
        }
        if (ok) {
            QStringList allowed;
            for (const QJsonValue &row : json.array())
                allowed << row.toObject().value(QStringLiteral("next_status")).toString();
            if (!allowed.contains(next)) {
                qInfo().noquote() << "INGE_CALICATA_STATUS_NOT_OFFERED next=" << next << "offered=" << allowed.join(QLatin1Char(','));
                setLastError(QStringLiteral("El servidor no ofrece el cambio a %1 para tu usuario en el estado actual de la ficha.").arg(next));
                emit statusChangeFailed(localId, m_lastError);
                return;
            }
        }
        // Sin conexión: el trabajo de campo no se bloquea (la transición local
        // viaja con la próxima sincronización, con CAS sobre row_version).
        commitStatusChange(target, next);
    });
    return localId;
}

void CalicataCloudService::commitStatusChange(CalicataDocument *document, const QString &next)
{
    if (!document || document->closed()) return;
    const QString localId = document->instanceId();
    const QString previous = document->status();
    if (!document->transitionStatus(next)) {
        setLastError(document->errorString().isEmpty()
            ? QStringLiteral("El cambio de estado no está permitido.") : document->errorString());
        emit statusChangeFailed(localId, m_lastError);
        return;
    }
    const QString remoteId = normalizedUuid(document->header().value(QStringLiteral("remoteCalicataId")).toString());
    if (remoteId.isEmpty()) {
        // Lifecycle before the first sync is local drafting; the creation
        // carries the status and CREATE_CALICATA records it.
        QTimer::singleShot(0, this, [this, localId, next]() { emit statusChangeSucceeded(localId, next, false); });
        return;
    }

    QVariantMap metadata = activityMetadata(document);
    metadata[QStringLiteral("previous_status")] = previous;
    metadata[QStringLiteral("new_status")] = next;
    const QString projectId = normalizedUuid(document->header().value(QStringLiteral("projectId")).toString());
    patchRemoteStatus(document, next,
                      [this, target = QPointer<CalicataDocument>(document), localId, projectId, remoteId,
                       previous, next, metadata](bool confirmed, const QString &code, const QString &message) {
        if (confirmed) {
            setLastError({});
            enqueueActivity(projectId, remoteId, QStringLiteral("CHANGE_CALICATA_STATUS"),
                            QStringLiteral("Estado de calicata %1: %2 → %3")
                                .arg(metadata.value(QStringLiteral("code")).toString(), previous, next),
                            metadata);
            emit statusChangeSucceeded(localId, next, true);
            return;
        }
        if (isOfflineCode(code)) {
            // Field work is not blocked: the transition is kept locally and the
            // root PATCH of the next sync carries it (with row_version CAS).
            if (target) target->setSyncState(QStringLiteral("PENDING"));
            emit statusChangeSucceeded(localId, next, false);
            return;
        }
        if (target && isConflictCode(code, message)) target->setSyncState(QStringLiteral("CONFLICT"));
        setLastError(humanCloudError(code, message));
        emit statusChangeFailed(localId, m_lastError);
    });
}

QString CalicataCloudService::restoreDocument(CalicataDocument *document)
{
    if (!document || document->closed()) return {};
    const QString localId = document->instanceId();
    if (document->status() != QLatin1String("ARCHIVADO")) {
        setLastError(QStringLiteral("La calicata no está archivada."));
        emit restoreFailed(localId, m_lastError);
        return {};
    }
    const QString remoteId = normalizedUuid(document->header().value(QStringLiteral("remoteCalicataId")).toString());
    // Ficha sincronizada: como Web, ARCHIVADO/EXPORTADO solo vuelve a OBSERVADO
    // (private.can_transition_calicata_status_v01, validado también por el
    // trigger). Un borrador solo local recupera su estado anterior.
    const QString target = remoteId.isEmpty() ? document->restoreTargetStatus() : QStringLiteral("OBSERVADO");
    if (remoteId.isEmpty()) {
        if (!document->restoreFromArchive()) {
            setLastError(document->errorString());
            emit restoreFailed(localId, m_lastError);
            return {};
        }
        QTimer::singleShot(0, this, [this, localId, target]() { emit restoreSucceeded(localId, target, false); });
        return localId;
    }

    QVariantMap metadata = activityMetadata(document);
    metadata[QStringLiteral("previous_status")] = QStringLiteral("ARCHIVADO");
    metadata[QStringLiteral("new_status")] = target;
    const QString projectId = normalizedUuid(document->header().value(QStringLiteral("projectId")).toString());
    patchRemoteStatus(document, target,
                      [this, doc = QPointer<CalicataDocument>(document), localId, projectId, remoteId,
                       target, metadata](bool confirmed, const QString &code, const QString &message) {
        if (!confirmed) {
            if (doc && isConflictCode(code, message)) doc->setSyncState(QStringLiteral("CONFLICT"));
            setLastError(isOfflineCode(code)
                ? QStringLiteral("Restaurar una calicata sincronizada requiere conexión.")
                : humanCloudError(code, message));
            emit restoreFailed(localId, m_lastError);
            return;
        }
        setLastError({});
        enqueueActivity(projectId, remoteId, QStringLiteral("RESTORE_CALICATA"),
                        QStringLiteral("Calicata restaurada: %1").arg(metadata.value(QStringLiteral("code")).toString()),
                        metadata);
        emit restoreSucceeded(localId, target, true);
    });
    return localId;
}

QString CalicataCloudService::codeConflict(CalicataDocument *document) const
{
    if (!document) return {};
    const QVariantMap header = document->header();
    const QString code = trimmedText(header.value(QStringLiteral("code"), header.value(QStringLiteral("codigo"))));
    const QString projectId = normalizedUuid(header.value(QStringLiteral("projectId")).toString());
    const QString remoteId = normalizedUuid(header.value(QStringLiteral("remoteCalicataId")).toString());
    if (code.isEmpty() || projectId.isEmpty()) return {};

    const QString message = QStringLiteral("Ya existe una calicata con el código %1 en este proyecto%2. "
                                           "Cambia el código o abre la ficha existente.");
    if (m_listedProjectId == projectId) {
        // Server mirror of the project, archived rows included (the unique
        // index covers them too).
        for (const QVariant &value : m_allProjectCalicatas) {
            const QVariantMap row = value.toMap();
            if (trimmedText(row.value(QStringLiteral("code"))) != code) continue;
            if (normalizedUuid(row.value(QStringLiteral("id")).toString()) == remoteId) continue;
            const bool archived = row.value(QStringLiteral("status")).toString() == QLatin1String("ARCHIVADO");
            return message.arg(code, archived ? QStringLiteral(" (archivada)") : QString());
        }
        return {};
    }
    // Offline: local mirrors of other confirmed cloud rows of the same project.
    for (const QVariant &value : document->listProjectDrafts(projectId, true)) {
        const QVariantMap item = value.toMap();
        const QString otherRemote = normalizedUuid(item.value(QStringLiteral("remoteCalicataId")).toString());
        if (otherRemote.isEmpty() || otherRemote == remoteId) continue;
        if (item.value(QStringLiteral("instanceId")).toString() == document->instanceId()) continue;
        if (item.value(QStringLiteral("code")).toString() == code)
            return message.arg(code, QString());
    }
    return {};
}

namespace {
QString activityOutboxPath(const QString &userId)
{
    const QString base = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    const QString owner = normalizedUuid(userId);
    if (base.isEmpty() || owner.isEmpty()) return {};
    return QDir(base).filePath(QStringLiteral("calicatas-activity/%1.json").arg(owner));
}

constexpr int kMaxActivityOutbox = 500;
} // namespace

void CalicataCloudService::ensureActivityOutbox()
{
    auto *ctx = appContext();
    auto *auth = ctx ? ctx->auth() : nullptr;
    const QString userId = auth && auth->logged() ? normalizedUuid(auth->userId()) : QString();
    if (userId.isEmpty() || userId == m_activityUserId) return;
    // Multi-account: each user has its own outbox; actor_id is always that user.
    m_activityUserId = userId;
    m_activityOutbox.clear();
    QFile file(activityOutboxPath(userId));
    if (file.open(QIODevice::ReadOnly)) {
        const QJsonDocument stored = QJsonDocument::fromJson(file.readAll());
        if (stored.isArray()) m_activityOutbox = stored.array().toVariantList();
    }
    emit pendingActivityChanged();
}

void CalicataCloudService::saveActivityOutbox()
{
    const QString path = activityOutboxPath(m_activityUserId);
    if (path.isEmpty()) return;
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning() << "[CalicataCloud] ACTIVITY_OUTBOX_WRITE_FAILED";
        return;
    }
    file.write(QJsonDocument::fromVariant(m_activityOutbox).toJson(QJsonDocument::Compact));
    if (!file.commit())
        qWarning() << "[CalicataCloud] ACTIVITY_OUTBOX_COMMIT_FAILED";
}

void CalicataCloudService::enqueueActivity(const QString &projectId, const QString &calicataId,
                                           const QString &action, const QString &description,
                                           const QVariantMap &metadata)
{
    // Creation/edits/status are audited by the transaction's server trigger.
    // Sending them again is both redundant and forbidden by activity_logs ACL.
    if (action != QLatin1String("EXPORT_CALICATA")) return;
    ensureActivityOutbox();
    const QString entityId = normalizedUuid(calicataId);
    if (m_activityUserId.isEmpty() || entityId.isEmpty()) return;
    QVariantMap entry;
    // Persistent event identity: the export RPC returns the same row on retry.
    entry[QStringLiteral("id")] = QUuid::createUuid().toString(QUuid::WithoutBraces);
    entry[QStringLiteral("project_id")] = normalizedUuid(projectId);
    entry[QStringLiteral("entity_id")] = entityId;
    entry[QStringLiteral("action")] = action;
    entry[QStringLiteral("description")] = description;
    QVariantMap meta = QJsonDocument::fromVariant(metadata).toVariant().toMap();
    meta[QStringLiteral("client_occurred_at")] = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
    entry[QStringLiteral("metadata")] = meta;
    m_activityOutbox.append(entry);
    while (m_activityOutbox.size() > kMaxActivityOutbox) {
        qWarning() << "[CalicataCloud] ACTIVITY_OUTBOX_FULL dropped_oldest";
        m_activityOutbox.removeFirst();
    }
    saveActivityOutbox();
    emit pendingActivityChanged();
    qInfo().noquote() << QStringLiteral("[CalicataCloud] ACTIVITY_QUEUED action=%1 pending=%2")
                             .arg(action).arg(m_activityOutbox.size());
    flushActivity();
}

int CalicataCloudService::pendingActivityCount() const
{
    int count = 0;
    for (const QVariant &value : m_activityOutbox) {
        const QVariantMap entry = value.toMap();
        if (entry.value(QStringLiteral("action")).toString() == QLatin1String("EXPORT_CALICATA")
            && !entry.contains(QStringLiteral("rejected_code"))) ++count;
    }
    return count;
}

void CalicataCloudService::flushActivity()
{
    ensureActivityOutbox();
    auto *auth = appContext() ? appContext()->auth() : nullptr;
    if (m_activityFlushing || !auth || !auth->logged()
        || normalizedUuid(auth->userId()) != m_activityUserId) return;
    QVariantMap entry;
    // Preserve legacy entries on disk. Server-owned lifecycle events are not
    // resubmitted as client INSERTs, and do not block actual export events.
    for (const QVariant &value : m_activityOutbox) {
        const QVariantMap candidate = value.toMap();
        if (candidate.value(QStringLiteral("action")).toString() == QLatin1String("EXPORT_CALICATA")
            && !candidate.contains(QStringLiteral("rejected_code"))) { entry = candidate; break; }
    }
    if (entry.isEmpty()) return;
    const QString entryId = entry.value(QStringLiteral("id")).toString();
    const QString owner = m_activityUserId;
    const QString format = entry.value(QStringLiteral("metadata")).toMap()
        .value(QStringLiteral("format"), QStringLiteral("XLSX")).toString().toUpper();
    QVariantMap args{{QStringLiteral("p_event_id"), entryId},
                     {QStringLiteral("p_project_id"), entry.value(QStringLiteral("project_id"))},
                     {QStringLiteral("p_calicata_id"), entry.value(QStringLiteral("entity_id"))},
                     {QStringLiteral("p_format"), format == QLatin1String("PDF") ? QStringLiteral("pdf") : QStringLiteral("excel")},
                     {QStringLiteral("p_platform"), QStringLiteral("ANDROID")}};
    m_activityFlushing = true;
    postRpc(QStringLiteral("record_my_calicata_export_v02"), args,
            [this, owner, entryId](bool ok, const QJsonDocument &document, const QString &code, const QString &) {
        m_activityFlushing = false;
        if (owner != m_activityUserId) return;
        const bool confirmed = ok && firstRow(document).value(QStringLiteral("event_id")).toString() == entryId;
        const bool permanent = code == QLatin1String("42501") || code.startsWith(QLatin1String("22"));
        if (!confirmed && !permanent) return; // transient/malformed response stays pending
        for (qsizetype i = 0; i < m_activityOutbox.size(); ++i) {
            QVariantMap item = m_activityOutbox.at(i).toMap();
            if (item.value(QStringLiteral("id")).toString() != entryId) continue;
            if (confirmed) m_activityOutbox.removeAt(i);
            else {
                item[QStringLiteral("rejected_code")] = code; // preserve for diagnosis
                m_activityOutbox[i] = item;
                qWarning().noquote() << QStringLiteral("[CalicataCloud] ACTIVITY_REJECTED rpc=record_my_calicata_export_v02 code=%1").arg(code);
            }
            break;
        }
        saveActivityOutbox();
        emit pendingActivityChanged();
        QTimer::singleShot(0, this, &CalicataCloudService::flushActivity);
    });
}

bool CalicataCloudService::logActivity(CalicataDocument *document, const QString &action,
                                       const QString &description, const QVariantMap &metadata)
{
    // Writes confirmed by this service log themselves; QML only reports the
    // semantic event it owns (Excel export).
    if (!document || action != QLatin1String("EXPORT_CALICATA")) return false;
    const QVariantMap header = document->header();
    const QString projectId = normalizedUuid(header.value(QStringLiteral("projectId")).toString());
    const QString remoteId = normalizedUuid(header.value(QStringLiteral("remoteCalicataId")).toString());
    if (projectId.isEmpty() || remoteId.isEmpty()) return false;
    QVariantMap meta = activityMetadata(document);
    for (auto it = metadata.cbegin(); it != metadata.cend(); ++it) meta.insert(it.key(), it.value());
    meta[QStringLiteral("status")] = document->status();
    enqueueActivity(projectId, remoteId, action, description, meta);
    return true;
}

// ===================== Media Cloud (P1) =====================
// Same RPCs, bucket and path shape as InGe+ Web (mediaCloudSync.ts):
//   PHOTO: create_my_calicata_media_v01 -> reserve_my_calicata_media_version_v01
//          -> Storage upload (original + derivative) -> finalize_my_calicata_media_version_v01
//   LOGO:  create_my_calicata_media_v01 -> reserve_my_calicata_media_original_v01
//          -> Storage upload -> finalize_my_calicata_media_original_v01
//   set_my_calicata_media_active_version_v01 (CAS row_version), empty_my_calicata_media_slot_v01.
// The outbox is written before any request, so a pending operation survives
// the ficha, the app and the process. SYNCED is only set on a READY answer.
namespace {

const QString kMediaBucket = QStringLiteral("calicata-media");
constexpr int kMaxMediaAttempts = 8;

QString mediaOutboxPath(const QString &userId)
{
    const QString base = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    const QString owner = normalizedUuid(userId);
    if (base.isEmpty() || owner.isEmpty()) return {};
    return QDir(base).filePath(QStringLiteral("calicatas-media/%1.json").arg(owner));
}

QString mediaMimeType(const QString &path)
{
    const QString suffix = QFileInfo(path).suffix().toLower();
    if (suffix == QLatin1String("png")) return QStringLiteral("image/png");
    if (suffix == QLatin1String("webp")) return QStringLiteral("image/webp");
    return QStringLiteral("image/jpeg");
}

QString mediaExtension(const QString &mime)
{
    if (mime == QLatin1String("image/png")) return QStringLiteral("png");
    if (mime == QLatin1String("image/webp")) return QStringLiteral("webp");
    return QStringLiteral("jpg");
}

// Web binaryArgs(): file name, MIME, bytes, pixels and sha256 of one file.
QVariantMap mediaBinaryArgs(const QString &prefix, const QString &absPath, const QString &fileName)
{
    QVariantMap args;
    const auto key = [&prefix](const char *name) { return QStringLiteral("p_%1_%2").arg(prefix, QLatin1String(name)); };
    QFile file(absPath);
    if (absPath.isEmpty() || !file.open(QIODevice::ReadOnly)) {
        for (const char *name : {"file_name", "mime_type", "size_bytes", "width", "height", "sha256"})
            args[key(name)] = QVariant();
        return args;
    }
    QCryptographicHash hash(QCryptographicHash::Sha256);
    hash.addData(&file);
    QImageReader reader(absPath);
    QSize size = reader.size();
    if (reader.transformation() & QImageIOHandler::TransformationRotate90) size.transpose();
    const QString mime = mediaMimeType(absPath);
    args[key("file_name")] = fileName + QLatin1Char('.') + mediaExtension(mime);
    args[key("mime_type")] = mime;
    args[key("size_bytes")] = QFileInfo(absPath).size();
    args[key("width")] = size.width() > 0 ? QVariant(size.width()) : QVariant();
    args[key("height")] = size.height() > 0 ? QVariant(size.height()) : QVariant();
    args[key("sha256")] = QString::fromLatin1(hash.result().toHex());
    return args;
}

bool transientMediaError(const QString &code)
{
    // No server code: the request never got an answer (offline / timeout).
    return code.isEmpty() || code == QLatin1String("AUTH_REQUIRED") || code.startsWith(QLatin1String("HTTP_5"));
}

bool conflictMediaError(const QString &code, const QString &message)
{
    return code == QLatin1String("40001") || message.contains(QLatin1String("row_version"), Qt::CaseInsensitive);
}

} // namespace

void CalicataCloudService::ensureMediaOutbox()
{
    auto *ctx = appContext();
    auto *auth = ctx ? ctx->auth() : nullptr;
    const QString userId = auth && auth->logged() ? normalizedUuid(auth->userId()) : QString();
    if (userId.isEmpty() || userId == m_mediaUserId) return;
    m_mediaUserId = userId;   // multi-account: one outbox per user
    m_mediaOutbox.clear();
    m_mediaConfirmed.clear();
    QFile file(mediaOutboxPath(userId));
    if (file.open(QIODevice::ReadOnly)) {
        const QVariantMap stored = QJsonDocument::fromJson(file.readAll()).toVariant().toMap();
        m_mediaOutbox = stored.value(QStringLiteral("entries")).toList();
        m_mediaConfirmed = stored.value(QStringLiteral("confirmed")).toMap();
    }
    // A process killed mid-request left SYNCING entries: they are pending again.
    for (QVariant &value : m_mediaOutbox) {
        QVariantMap entry = value.toMap();
        if (entry.value(QStringLiteral("state")) == QLatin1String("SYNCING")) {
            entry[QStringLiteral("state")] = QStringLiteral("PENDING");
            value = entry;
        }
    }
    emit mediaQueueChanged();
}

void CalicataCloudService::saveMediaOutbox()
{
    const QString path = mediaOutboxPath(m_mediaUserId);
    if (path.isEmpty()) return;
    QDir().mkpath(QFileInfo(path).absolutePath());
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning() << "[CalicataCloud] MEDIA_OUTBOX_WRITE_FAILED";
        return;
    }
    QVariantMap stored;
    stored[QStringLiteral("entries")] = m_mediaOutbox;
    stored[QStringLiteral("confirmed")] = m_mediaConfirmed;
    file.write(QJsonDocument::fromVariant(stored).toJson(QJsonDocument::Compact));
    if (!file.commit())
        qWarning() << "[CalicataCloud] MEDIA_OUTBOX_COMMIT_FAILED";
    emit mediaQueueChanged();
}

QString CalicataCloudService::enqueuePhotoSync(CalicataDocument *document, int idx)
{
    // Confirmaciones del servidor que la UI no aplicó (formulario recreado, otra
    // ficha visible…): se aplican ANTES de fijar la base de conflicto. Sin esto la
    // propia publicación anterior se leía como "cambió en otro dispositivo".
    if (document && !document->closed()) {
        ensureMediaOutbox();
        const QString confirmedDoc = document->instanceId();
        const QVariantList confirmed = m_mediaConfirmed.value(confirmedDoc).toList();
        if (!confirmed.isEmpty()) {
            for (const QVariant &value : confirmed) {
                QVariantMap change = value.toMap();
                const int confirmedIdx = change.take(QStringLiteral("idx")).toInt();
                change.remove(QStringLiteral("category_code"));
                if (confirmedIdx >= 1 && confirmedIdx <= 3) document->setPhotoCloudState(confirmedIdx, change);
            }
            m_mediaConfirmed.remove(confirmedDoc);
            saveMediaOutbox();
        }
    }
    if (!document || document->closed() || idx < 1 || idx > 3) return {};
    ensureMediaOutbox();
    if (m_mediaUserId.isEmpty()) return {};   // offline without session: the slot stays PENDING in the ficha
    const QVariantMap header = document->header();
    const QVariantMap images = document->images();
    const auto key = [idx](const char *suffix) { return QStringLiteral("foto%1_%2").arg(idx).arg(QLatin1String(suffix)); };
    const QString op = images.value(key("pending_op"), QStringLiteral("PUBLISH")).toString();
    const QString localId = document->instanceId();

    QVariantMap entry;
    entry[QStringLiteral("id")] = QUuid::createUuid().toString(QUuid::WithoutBraces);
    entry[QStringLiteral("local_document_id")] = localId;
    entry[QStringLiteral("project_id")] = normalizedUuid(header.value(QStringLiteral("projectId")).toString());
    entry[QStringLiteral("calicata_id")] = normalizedUuid(header.value(QStringLiteral("remoteCalicataId")).toString());
    entry[QStringLiteral("idx")] = idx;
    entry[QStringLiteral("resource_type")] = QStringLiteral("PHOTO");
    entry[QStringLiteral("category_code")] = document->photoCategoryCode(idx);
    entry[QStringLiteral("op")] = op;
    entry[QStringLiteral("state")] = QStringLiteral("PENDING");
    entry[QStringLiteral("attempts")] = 0;
    // What this device believed the slot held: the basis of conflict detection.
    entry[QStringLiteral("base_media_id")] = images.value(key("media_id"));
    entry[QStringLiteral("base_cloud_version_id")] = images.value(key("cloud_active_version_id"));
    // Versiones cloud que este dispositivo ya conoce para el slot (propias): nunca
    // son "otro dispositivo" (contrato Web: una versión distinta no es conflicto por sí sola).
    QStringList knownCloudVersions;
    for (const QVariant &value : images.value(key("versions")).toList()) {
        const QString known = normalizedUuid(value.toMap().value(QStringLiteral("cloud_version_id")).toString());
        if (!known.isEmpty()) knownCloudVersions << known;
    }
    const QString activeCloudVersion = normalizedUuid(images.value(key("cloud_active_version_id")).toString());
    if (!activeCloudVersion.isEmpty()) knownCloudVersions << activeCloudVersion;
    entry[QStringLiteral("known_cloud_version_ids")] = knownCloudVersions;

    const bool newOriginal = images.value(key("new_original")).toBool()
        || normalizedUuid(images.value(key("media_id")).toString()).isEmpty();
    entry[QStringLiteral("media_id")] = newOriginal ? QUuid::createUuid().toString(QUuid::WithoutBraces)
                                                    : normalizedUuid(images.value(key("media_id")).toString());
    entry[QStringLiteral("new_media")] = newOriginal;

    if (op == QLatin1String("PUBLISH") || op == QLatin1String("ACTIVATE")) {
        const QString activeLocal = images.value(key("active_local_version")).toString();
        QVariantMap version;
        for (const QVariant &value : images.value(key("versions")).toList())
            if (value.toMap().value(QStringLiteral("local_version_id")).toString() == activeLocal) version = value.toMap();
        entry[QStringLiteral("local_version_id")] = activeLocal;
        entry[QStringLiteral("cloud_version_id")] = version.value(QStringLiteral("cloud_version_id"));
        if (op == QLatin1String("ACTIVATE") && version.value(QStringLiteral("cloud_version_id")).toString().isEmpty())
            entry[QStringLiteral("op")] = QStringLiteral("PUBLISH");
        entry[QStringLiteral("version_id")] = QUuid::createUuid().toString(QUuid::WithoutBraces);
        entry[QStringLiteral("original_abs")] = document->originalPhotoUrl(idx).toLocalFile();
        entry[QStringLiteral("derived_abs")] = document->resolvedPhotoAbs(images.value(key("path")).toString());
        // annotation = edición de la foto + fecha/hora DOCUMENTALES (rótulo) y, aparte,
        // los datos de CAPTURA (EXIF / hora del sistema fijada una vez): viajan con la
        // versión para que otro dispositivo regenere la foto con la misma hora.
        QVariantMap annotation = images.value(key("edit")).toMap();
        const QVariantMap stamped = annotation.value(QStringLiteral("metadata")).toMap();
        annotation[QStringLiteral("document")] = QVariantMap{
            {QStringLiteral("photo_document_date"), stamped.value(QStringLiteral("date"))},
            {QStringLiteral("photo_document_time"), stamped.value(QStringLiteral("time"))},
            {QStringLiteral("time_source"), stamped.value(QStringLiteral("time_source"))}};
        const QVariantMap capture = images.value(key("capture")).toMap();
        if (!capture.isEmpty()) annotation[QStringLiteral("capture")] = capture;
        entry[QStringLiteral("annotation")] = annotation;
        if (entry.value(QStringLiteral("original_abs")).toString().isEmpty()) return {};
    }

    // The latest intent for a slot replaces an older one that never reached
    // the server; an entry already in flight is left to finish.
    for (int i = m_mediaOutbox.size() - 1; i >= 0; --i) {
        const QVariantMap other = m_mediaOutbox.at(i).toMap();
        if (other.value(QStringLiteral("local_document_id")) == localId && other.value(QStringLiteral("idx")).toInt() == idx
            && other.value(QStringLiteral("state")) != QLatin1String("SYNCING")) {
            // Misma revisión local = mismo envío: conserva media_id/version_id (el
            // servidor deduplica por version_id); un reintento nunca crea otra revisión.
            const QString sameLocal = entry.value(QStringLiteral("local_version_id")).toString();
            if (!sameLocal.isEmpty() && other.value(QStringLiteral("local_version_id")).toString() == sameLocal
                && !other.value(QStringLiteral("version_id")).toString().isEmpty()) {
                entry[QStringLiteral("version_id")] = other.value(QStringLiteral("version_id"));
                entry[QStringLiteral("media_id")] = other.value(QStringLiteral("media_id"));
                entry[QStringLiteral("new_media")] = other.value(QStringLiteral("new_media"));
            }
            m_mediaOutbox.removeAt(i);
        }
    }
    m_mediaOutbox.append(entry);
    saveMediaOutbox();
    QVariantMap changes;
    changes[QStringLiteral("sync")] = QStringLiteral("PENDING");
    changes[QStringLiteral("new_original")] = false;
    changes[QStringLiteral("media_id")] = entry.value(QStringLiteral("media_id"));
    document->setPhotoCloudState(idx, changes);
    flushMedia();
    return entry.value(QStringLiteral("id")).toString();
}

QString CalicataCloudService::enqueueLogoSync(CalicataDocument *document, const QString &categoryCode)
{
    if (!document || document->closed()
        || (categoryCode != QLatin1String("PROJECT") && categoryCode != QLatin1String("ENTITY")))
        return {};
    ensureMediaOutbox();
    if (m_mediaUserId.isEmpty()) return {};
    const QVariantMap header = document->header();
    const QVariantMap images = document->images();
    const QString rel = images.value(categoryCode == QLatin1String("ENTITY") ? QStringLiteral("logo_mtc_path")
                                                                            : QStringLiteral("logo_proyecto_path")).toString();
    const bool empty = rel.trimmed().isEmpty();
    const QString abs = rel.startsWith(QLatin1String("qrc:")) ? QString() : document->resolvedPhotoAbs(rel);
    if (!empty && (abs.isEmpty() || !QFileInfo::exists(abs))) return {};   // bundled default logos stay local

    QVariantMap entry;
    entry[QStringLiteral("id")] = QUuid::createUuid().toString(QUuid::WithoutBraces);
    entry[QStringLiteral("local_document_id")] = document->instanceId();
    entry[QStringLiteral("project_id")] = normalizedUuid(header.value(QStringLiteral("projectId")).toString());
    entry[QStringLiteral("calicata_id")] = normalizedUuid(header.value(QStringLiteral("remoteCalicataId")).toString());
    entry[QStringLiteral("idx")] = 0;
    entry[QStringLiteral("resource_type")] = QStringLiteral("LOGO");
    entry[QStringLiteral("category_code")] = categoryCode;
    entry[QStringLiteral("op")] = empty ? QStringLiteral("EMPTY_SLOT") : QStringLiteral("PUBLISH_LOGO");
    entry[QStringLiteral("media_id")] = QUuid::createUuid().toString(QUuid::WithoutBraces);   // a logo has no revisions
    entry[QStringLiteral("original_abs")] = abs;
    entry[QStringLiteral("state")] = QStringLiteral("PENDING");
    entry[QStringLiteral("attempts")] = 0;
    for (int i = m_mediaOutbox.size() - 1; i >= 0; --i) {
        const QVariantMap other = m_mediaOutbox.at(i).toMap();
        if (other.value(QStringLiteral("local_document_id")) == document->instanceId()
            && other.value(QStringLiteral("category_code")) == categoryCode
            && other.value(QStringLiteral("state")) != QLatin1String("SYNCING"))
            m_mediaOutbox.removeAt(i);
    }
    m_mediaOutbox.append(entry);
    saveMediaOutbox();
    flushMedia();
    return entry.value(QStringLiteral("id")).toString();
}

void CalicataCloudService::bindMediaIdentity(CalicataDocument *document)
{
    if (!document) return;
    ensureMediaOutbox();
    const QString projectId = normalizedUuid(document->header().value(QStringLiteral("projectId")).toString());
    const QString calicataId = normalizedUuid(document->header().value(QStringLiteral("remoteCalicataId")).toString());
    if (projectId.isEmpty() || calicataId.isEmpty()) return;
    bool changed = false;
    for (QVariant &value : m_mediaOutbox) {
        QVariantMap entry = value.toMap();
        if (entry.value(QStringLiteral("local_document_id")) != document->instanceId()) continue;
        if (!entry.value(QStringLiteral("calicata_id")).toString().isEmpty()) continue;
        entry[QStringLiteral("project_id")] = projectId;
        entry[QStringLiteral("calicata_id")] = calicataId;
        value = entry;
        changed = true;
    }
    if (changed) saveMediaOutbox();
    flushMedia();
}

QVariantList CalicataCloudService::mediaEntriesFor(const QString &localDocumentId) const
{
    QVariantList result;
    for (const QVariant &value : m_mediaOutbox)
        if (value.toMap().value(QStringLiteral("local_document_id")) == localDocumentId) result << value;
    return result;
}

QVariantList CalicataCloudService::takeConfirmedMedia(const QString &localDocumentId)
{
    ensureMediaOutbox();
    const QVariantList confirmed = m_mediaConfirmed.take(localDocumentId).toList();
    if (!confirmed.isEmpty()) saveMediaOutbox();
    return confirmed;
}

bool CalicataCloudService::resolveMediaConflict(const QString &entryId, bool keepMine)
{
    for (int i = 0; i < m_mediaOutbox.size(); ++i) {
        QVariantMap entry = m_mediaOutbox.at(i).toMap();
        if (entry.value(QStringLiteral("id")) != entryId) continue;
        if (keepMine) {
            if (entry.value(QStringLiteral("state")).toString() == QLatin1String("CONFLICT"))
                entry[QStringLiteral("force")] = true;
            entry[QStringLiteral("state")] = QStringLiteral("PENDING");
            entry[QStringLiteral("attempts")] = 0;
            m_mediaOutbox[i] = entry;
        } else {
            m_mediaOutbox.removeAt(i);   // local files are kept; only the cloud op is dropped
        }
        saveMediaOutbox();
        flushMedia();
        return true;
    }
    return false;
}

void CalicataCloudService::finishMediaEntry(const QString &entryId, const QString &state,
                                            const QString &message, const QVariantMap &changes)
{
    for (int i = 0; i < m_mediaOutbox.size(); ++i) {
        QVariantMap entry = m_mediaOutbox.at(i).toMap();
        if (entry.value(QStringLiteral("id")) != entryId) continue;
        const QString localId = entry.value(QStringLiteral("local_document_id")).toString();
        const int idx = entry.value(QStringLiteral("idx")).toInt();
        if (state == QLatin1String("SYNCED")) {
            m_mediaOutbox.removeAt(i);
            QVariantMap confirmed = changes;
            confirmed[QStringLiteral("idx")] = idx;
            confirmed[QStringLiteral("category_code")] = entry.value(QStringLiteral("category_code"));
            QVariantList list = m_mediaConfirmed.value(localId).toList();
            list << confirmed;
            m_mediaConfirmed[localId] = list;
        } else {
            entry[QStringLiteral("state")] = state;
            entry[QStringLiteral("error")] = message;
            m_mediaOutbox[i] = entry;
        }
        saveMediaOutbox();
        emit mediaSyncChanged(localId, idx, state, message, changes);
        return;
    }
}

void CalicataCloudService::flushMedia()
{
    ensureMediaOutbox();
    if (m_mediaFlushing || m_mediaUserId.isEmpty()) return;
    for (int i = 0; i < m_mediaOutbox.size(); ++i) {
        const QVariantMap entry = m_mediaOutbox.at(i).toMap();
        if (entry.value(QStringLiteral("state")) != QLatin1String("PENDING")) continue;
        if (entry.value(QStringLiteral("calicata_id")).toString().isEmpty()
            || entry.value(QStringLiteral("project_id")).toString().isEmpty())
            continue;   // waits for the ficha's first cloud sync (bindMediaIdentity)
        processMediaEntry(i);
        return;
    }
}

void CalicataCloudService::uploadStorageObject(const QString &path, const QString &localFile,
                                               const QString &mimeType,
                                               std::function<void(bool, const QString &)> done,
                                               const QString &bucket)
{
    auto *ctx = appContext();
    auto *api = ctx ? ctx->supabase() : nullptr;
    auto *auth = ctx ? ctx->auth() : nullptr;
    if (!api || !auth || !auth->logged() || auth->accessToken().isEmpty()) { done(false, QStringLiteral("AUTH_REQUIRED")); return; }
    QFile file(localFile);
    if (!file.open(QIODevice::ReadOnly)) { done(false, QStringLiteral("LOCAL_FILE_MISSING")); return; }
    const QByteArray body = file.readAll();
    // Same Supabase project, Storage API instead of PostgREST.
    QString base = api->restUrl(QString()).toString();
    base.replace(QStringLiteral("/rest/v1"), QStringLiteral("/storage/v1"));
    if (!base.endsWith(QLatin1Char('/'))) base += QLatin1Char('/');
    const QUrl url(base + QStringLiteral("object/") + (bucket.isEmpty() ? kMediaBucket : bucket)
                   + QLatin1Char('/') + path);
    QNetworkRequest request = api->makeRequest(url, auth->accessToken());
    request.setHeader(QNetworkRequest::ContentTypeHeader, mimeType);
    request.setRawHeader("x-upsert", "false");   // immutable object, as Web (upsert: false)
    request.setRawHeader("cache-control", "max-age=31536000");
    request.setRawHeader("x-ingeplus-platform", "ANDROID");
    QNetworkReply *reply = api->nam()->post(request, body);
    beginRequest();
    QTimer::singleShot(120000, reply, [reply]() { if (!reply->isFinished()) reply->abort(); });
    connect(reply, &QNetworkReply::finished, this, [this, reply, done = std::move(done)]() {
        endRequest();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray raw = reply->readAll();
        const bool networkFailed = reply->error() != QNetworkReply::NoError && http == 0;
        reply->deleteLater();
        if (http >= 200 && http < 300) { done(true, {}); return; }
        // An interrupted earlier attempt may already have written the exact
        // reserved bytes; finalize is what decides (Web does the same).
        if (http == 409 || raw.contains("Duplicate") || raw.contains("already exists")) { done(true, {}); return; }
        if (!networkFailed) {
            const QJsonObject body = QJsonDocument::fromJson(raw).object();
            const QString reason = body.value(QStringLiteral("message")).toString(body.value(QStringLiteral("error")).toString());
            qWarning().noquote() << "INGE_CALICATA_MEDIA_UPLOAD_REJECTED http=" + QString::number(http)
                                    + " reason=" + reason.simplified().left(200);
        }
        done(false, networkFailed ? QString() : QStringLiteral("HTTP_%1").arg(http));
    });
}

void CalicataCloudService::processMediaEntry(int index)
{
    QVariantMap entry = m_mediaOutbox.at(index).toMap();
    const QString entryId = entry.value(QStringLiteral("id")).toString();
    entry[QStringLiteral("state")] = QStringLiteral("SYNCING");
    entry[QStringLiteral("attempts")] = entry.value(QStringLiteral("attempts")).toInt() + 1;
    m_mediaOutbox[index] = entry;
    m_mediaFlushing = true;
    saveMediaOutbox();
    emit mediaSyncChanged(entry.value(QStringLiteral("local_document_id")).toString(),
                          entry.value(QStringLiteral("idx")).toInt(), QStringLiteral("SYNCING"), {}, {});

    const QString op = entry.value(QStringLiteral("op")).toString();
    const QString projectId = entry.value(QStringLiteral("project_id")).toString();
    const QString calicataId = entry.value(QStringLiteral("calicata_id")).toString();
    const QString mediaId = normalizedUuid(entry.value(QStringLiteral("media_id")).toString());
    const QString resourceType = entry.value(QStringLiteral("resource_type")).toString();
    const QString category = entry.value(QStringLiteral("category_code")).toString();
    const int attempts = entry.value(QStringLiteral("attempts")).toInt();
    const QString traceVersion = normalizedUuid(entry.value(QStringLiteral("version_id")).toString());
    const qint64 startedMs = QDateTime::currentMSecsSinceEpoch();
    const QString traceIds = QStringLiteral(" media_id=") + mediaId + QStringLiteral(" version_id=")
        + (traceVersion.isEmpty() ? QStringLiteral("-") : traceVersion);
    auto trace = [op, traceIds, startedMs](const char *stage) {
        qInfo().noquote() << QStringLiteral("INGE_CALICATA_MEDIA_%1 op=%2%3 elapsedMs=%4")
                                 .arg(QLatin1String(stage), op, traceIds)
                                 .arg(QDateTime::currentMSecsSinceEpoch() - startedMs);
    };
    if (op == QLatin1String("PUBLISH")) trace("PUBLISH_BEGIN");

    // Common failure policy: offline stays PENDING, CAS -> CONFLICT, the rest
    // retries a few times and then waits as FAILED (never silently dropped).
    // phase: the exact step that failed (SLOT_CHECK, CREATE, RESERVE, UPLOAD_ORIGINAL,
    // UPLOAD_DERIVATIVE, FINALIZE, ACTIVATE). One technical line per failure, no paths
    // or tokens: it is what makes "No se pudo completar" diagnosable from logcat.
    auto fail = [this, entryId, attempts, op, traceIds, startedMs](const QString &code, const QString &message, const QString &phase = QString()) {
        m_mediaFlushing = false;
        const QString text = humanCloudError(code, message);
        const QString state = conflictMediaError(code, message) ? QStringLiteral("CONFLICT")
            : (transientMediaError(code) && attempts < kMaxMediaAttempts) ? QStringLiteral("PENDING")
            : QStringLiteral("FAILED");
        qWarning().noquote() << (op == QLatin1String("PUBLISH") ? QStringLiteral("INGE_CALICATA_MEDIA_PUBLISH_ERROR op=")
                                                                : QStringLiteral("INGE_CALICATA_MEDIA_FAILED op=")) + op
                                + traceIds
                                + " phase=" + (phase.isEmpty() ? QStringLiteral("UNKNOWN") : phase)
                                + " code=" + (code.isEmpty() ? QStringLiteral("NETWORK") : code)
                                + " attempt=" + QString::number(attempts) + " state=" + state
                                + " elapsedMs=" + QString::number(QDateTime::currentMSecsSinceEpoch() - startedMs)
                                + " message=" + message.simplified().left(200);
        finishMediaEntry(entryId, state, text, {});
        if (!transientMediaError(code)) flushMedia();   // do not spin while offline
    };
    auto succeed = [this, entryId, entry, op, projectId, calicataId, mediaId, category](const QVariantMap &changes) {
        m_mediaFlushing = false;
        qInfo().noquote() << "INGE_CALICATA_MEDIA_SYNCED op=" + op + " category=" + category;
        finishMediaEntry(entryId, QStringLiteral("SYNCED"), {}, changes);
        flushMedia();
    };

    if (op == QLatin1String("EMPTY_SLOT")) {
        postRpc(QStringLiteral("empty_my_calicata_media_slot_v01"),
                {{QStringLiteral("p_project_id"), projectId}, {QStringLiteral("p_calicata_id"), calicataId},
                 {QStringLiteral("p_resource_type"), resourceType}, {QStringLiteral("p_category_code"), category}},
                [fail, succeed](bool ok, const QJsonDocument &, const QString &code, const QString &message) {
            if (!ok) { fail(code, message); return; }
            succeed({{QStringLiteral("sync"), QStringLiteral("SYNCED")}, {QStringLiteral("cloud_active_version_id"), QString()},
                     {QStringLiteral("pending_op"), QString()}, {QStringLiteral("sync_error"), QString()}});
        });
        return;
    }

    if (op == QLatin1String("PUBLISH_LOGO")) {
        const QString abs = entry.value(QStringLiteral("original_abs")).toString();
        const QString mime = mediaMimeType(abs);
        const QString fileName = QStringLiteral("logo_%1_%2").arg(category.toLower(), mediaId.left(8));
        const QString storagePath = QStringList{QStringLiteral("projects"), projectId, QStringLiteral("calicatas"), calicataId,
            QStringLiteral("media"), mediaId, QStringLiteral("original"), fileName + QLatin1Char('.') + mediaExtension(mime)}
            .join(QLatin1Char('/'));   // buildCalicataMediaOriginalPath
        QVariantMap createArgs = mediaBinaryArgs(QStringLiteral("original"), abs, fileName);
        createArgs[QStringLiteral("p_project_id")] = projectId;
        createArgs[QStringLiteral("p_calicata_id")] = calicataId;
        createArgs[QStringLiteral("p_resource_type")] = QStringLiteral("LOGO");
        createArgs[QStringLiteral("p_category_code")] = category;
        createArgs[QStringLiteral("p_media_id")] = mediaId;
        postRpc(QStringLiteral("create_my_calicata_media_v01"), createArgs,
                [this, fail, succeed, mediaId, storagePath, abs, mime](bool ok, const QJsonDocument &, const QString &code, const QString &message) {
            if (!ok && code != QLatin1String("23505")) { fail(code, message); return; }   // create is idempotent by media_id
            postRpc(QStringLiteral("reserve_my_calicata_media_original_v01"),
                    {{QStringLiteral("p_media_id"), mediaId}, {QStringLiteral("p_storage_path"), storagePath}},
                    [this, fail, succeed, mediaId, storagePath, abs, mime](bool okReserve, const QJsonDocument &reserved, const QString &codeReserve, const QString &messageReserve) {
                if (!okReserve) { fail(codeReserve, messageReserve); return; }
                if (firstRow(reserved).value(QStringLiteral("original_storage_path")).toString() != storagePath) {
                    fail(QStringLiteral("INVALID_RESERVATION"), QStringLiteral("El servidor no confirmó la reserva del logo."));
                    return;
                }
                uploadStorageObject(storagePath, abs, mime, [this, fail, succeed, mediaId](bool, const QString &) {
                    postRpc(QStringLiteral("finalize_my_calicata_media_original_v01"), {{QStringLiteral("p_media_id"), mediaId}},
                            [fail, succeed, mediaId](bool okFinal, const QJsonDocument &finalized, const QString &codeFinal, const QString &messageFinal) {
                        if (!okFinal) { fail(codeFinal, messageFinal); return; }
                        if (firstRow(finalized).value(QStringLiteral("sync_state")).toString() != QLatin1String("UPLOADED")) {
                            fail(QStringLiteral("INVALID_RESPONSE"), QStringLiteral("El servidor no confirmó el logo."));
                            return;
                        }
                        succeed({{QStringLiteral("media_id"), mediaId}});
                    });
                });
            });
        });
        return;
    }

    // PHOTO slot: detect a remote replacement first, then publish or activate.
    const QString baseMediaId = normalizedUuid(entry.value(QStringLiteral("base_media_id")).toString());
    const QString baseVersionId = normalizedUuid(entry.value(QStringLiteral("base_cloud_version_id")).toString());
    const bool force = entry.value(QStringLiteral("force")).toBool();
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("select"), QStringLiteral("media_id,active_version_id,row_version,updated_at"));
    query.addQueryItem(QStringLiteral("project_id"), QStringLiteral("eq.") + projectId);
    query.addQueryItem(QStringLiteral("calicata_id"), QStringLiteral("eq.") + calicataId);
    query.addQueryItem(QStringLiteral("resource_type"), QStringLiteral("eq.PHOTO"));
    query.addQueryItem(QStringLiteral("category_code"), QStringLiteral("eq.") + category);
    query.addQueryItem(QStringLiteral("sync_state"), QStringLiteral("eq.UPLOADED"));
    query.addQueryItem(QStringLiteral("discarded_at"), QStringLiteral("is.null"));
    query.addQueryItem(QStringLiteral("order"), QStringLiteral("updated_at.desc"));
    query.addQueryItem(QStringLiteral("limit"), QStringLiteral("1"));
    auto *ctx = appContext();
    auto *api = ctx ? ctx->supabase() : nullptr;
    if (!api) { fail(QString(), QStringLiteral("Sin conexión con Supabase."), QStringLiteral("SLOT_CHECK")); return; }
    QUrl slotUrl = api->restUrl(QStringLiteral("calicata_media"));
    slotUrl.setQuery(query);
    getJson(slotUrl, [this, entry, fail, succeed, op, mediaId, baseMediaId, baseVersionId, force, projectId, calicataId, category, trace]
            (bool ok, const QJsonDocument &slotDocument, const QString &code, const QString &message) mutable {
        if (!ok) { fail(code, message, QStringLiteral("SLOT_CHECK")); return; }
        const QVariantMap remote = firstRow(slotDocument);
        const QString remoteMedia = normalizedUuid(remote.value(QStringLiteral("media_id")).toString());
        const QString remoteVersion = normalizedUuid(remote.value(QStringLiteral("active_version_id")).toString());
        const bool ourMedia = !remoteMedia.isEmpty() && remoteMedia == mediaId;
        // Una versión que este dispositivo ya publicó/conoce nunca es ajena.
        const QStringList knownVersions = entry.value(QStringLiteral("known_cloud_version_ids")).toStringList();
        const bool remoteIsKnown = !remoteVersion.isEmpty() && knownVersions.contains(remoteVersion);
        // Someone else changed the slot since this device last saw it.
        const bool replacedElsewhere = !remoteMedia.isEmpty() && remoteMedia != baseMediaId && !ourMedia && !remoteIsKnown;
        const bool revisedElsewhere = ourMedia && !baseVersionId.isEmpty() && !remoteVersion.isEmpty()
            && remoteVersion != baseVersionId && !remoteIsKnown
            && remoteVersion != normalizedUuid(entry.value(QStringLiteral("cloud_version_id")).toString());
        if (!force && (replacedElsewhere || revisedElsewhere)) {
            m_mediaFlushing = false;
            finishMediaEntry(entry.value(QStringLiteral("id")).toString(), QStringLiteral("CONFLICT"),
                             QStringLiteral("La fotografía de esta categoría cambió en otro dispositivo. "
                                            "Elige conservar la tuya o mantener la remota."), {});
            flushMedia();
            return;
        }

        if (op == QLatin1String("ACTIVATE")) {
            const QString cloudVersion = normalizedUuid(entry.value(QStringLiteral("cloud_version_id")).toString());
            postRpc(QStringLiteral("set_my_calicata_media_active_version_v01"),
                    {{QStringLiteral("p_media_id"), mediaId}, {QStringLiteral("p_version_id"), cloudVersion},
                     {QStringLiteral("p_expected_row_version"), ourMedia ? remote.value(QStringLiteral("row_version")) : QVariant()}},
                    [fail, succeed, entry, cloudVersion](bool okActive, const QJsonDocument &, const QString &codeActive, const QString &messageActive) {
                if (!okActive) { fail(codeActive, messageActive, QStringLiteral("ACTIVATE")); return; }
                succeed({{QStringLiteral("sync"), QStringLiteral("SYNCED")}, {QStringLiteral("pending_op"), QString()},
                         {QStringLiteral("cloud_active_version_id"), cloudVersion}, {QStringLiteral("sync_error"), QString()},
                         {QStringLiteral("local_version_id"), entry.value(QStringLiteral("local_version_id"))},
                         {QStringLiteral("version_state"), QStringLiteral("SYNCED")}});
            });
            return;
        }

        // PUBLISH: one immutable revision (original + derivative) of the slot media.
        const QString originalAbs = entry.value(QStringLiteral("original_abs")).toString();
        const QString derivedAbs = entry.value(QStringLiteral("derived_abs")).toString();
        const QString versionId = normalizedUuid(entry.value(QStringLiteral("version_id")).toString());
        const QString stem = QStringLiteral("%1_%2").arg(category.toLower(), mediaId.left(8));
        const QVariantMap originalArgs = mediaBinaryArgs(QStringLiteral("original"), originalAbs, stem + QStringLiteral("_original"));
        const QVariantMap derivativeArgs = mediaBinaryArgs(QStringLiteral("derivative"), derivedAbs,
                                                           stem + QStringLiteral("_") + versionId.left(8));
        auto reserve = [this, fail, succeed, trace, entry, mediaId, versionId, originalArgs, derivativeArgs, originalAbs, derivedAbs]() {
            QVariantMap args = originalArgs;
            for (auto it = derivativeArgs.cbegin(); it != derivativeArgs.cend(); ++it) args.insert(it.key(), it.value());
            args[QStringLiteral("p_media_id")] = mediaId;
            args[QStringLiteral("p_version_id")] = versionId;
            args[QStringLiteral("p_annotation")] = entry.value(QStringLiteral("annotation")).toMap();
            postRpc(QStringLiteral("reserve_my_calicata_media_version_v01"), args,
                    [this, fail, succeed, trace, entry, versionId, originalAbs, derivedAbs, originalArgs, derivativeArgs]
                    (bool okReserve, const QJsonDocument &reserved, const QString &codeReserve, const QString &messageReserve) {
                if (!okReserve) { fail(codeReserve, messageReserve, QStringLiteral("RESERVE")); return; }
                trace("RESERVE_OK");
                const QVariantMap row = firstRow(reserved);
                const QString state = row.value(QStringLiteral("state")).toString();
                const QVariantMap confirmed = {
                    {QStringLiteral("sync"), QStringLiteral("SYNCED")}, {QStringLiteral("pending_op"), QString()},
                    {QStringLiteral("cloud_active_version_id"), versionId}, {QStringLiteral("sync_error"), QString()},
                    {QStringLiteral("media_id"), entry.value(QStringLiteral("media_id"))},
                    {QStringLiteral("local_version_id"), entry.value(QStringLiteral("local_version_id"))},
                    {QStringLiteral("cloud_version_id"), versionId}, {QStringLiteral("version_state"), QStringLiteral("SYNCED")}};
                if (state == QLatin1String("READY")) { succeed(confirmed); return; }
                if (state != QLatin1String("UPLOADING")) {
                    fail(QStringLiteral("INVALID_RESERVATION"), QStringLiteral("La reserva de la fotografía no es válida."),
                         QStringLiteral("RESERVE"));
                    return;
                }
                const QString originalPath = row.value(QStringLiteral("original_storage_path")).toString();
                const QString derivativePath = row.value(QStringLiteral("derivative_storage_path")).toString();
                auto finalize = [this, fail, succeed, trace, versionId, confirmed]() {
                    // Finalize even after an upload collision (Web): it checks the bytes.
                    trace("FINALIZE_BEGIN");
                    postRpc(QStringLiteral("finalize_my_calicata_media_version_v01"), {{QStringLiteral("p_version_id"), versionId}},
                            [this, fail, succeed, trace, versionId, confirmed](bool okFinal, const QJsonDocument &finalized, const QString &codeFinal, const QString &messageFinal) {
                        if (okFinal && firstRow(finalized).value(QStringLiteral("state")).toString() == QLatin1String("READY")) {
                            trace("FINALIZE_OK");
                            succeed(confirmed);
                            return;
                        }
                        if (!okFinal && !transientMediaError(codeFinal)) {
                            // Close the reservation as FAILED; the retry reserves a fresh version.
                            postRpc(QStringLiteral("fail_my_calicata_media_version_v01"), {{QStringLiteral("p_version_id"), versionId}},
                                    [](bool, const QJsonDocument &, const QString &, const QString &) {});
                            for (QVariant &value : m_mediaOutbox) {
                                QVariantMap other = value.toMap();
                                if (normalizedUuid(other.value(QStringLiteral("version_id")).toString()) != versionId) continue;
                                other[QStringLiteral("version_id")] = QUuid::createUuid().toString(QUuid::WithoutBraces);
                                value = other;
                            }
                        }
                        fail(okFinal ? QStringLiteral("INVALID_RESPONSE") : codeFinal,
                             okFinal ? QStringLiteral("El servidor no confirmó la fotografía.") : messageFinal,
                             QStringLiteral("FINALIZE"));
                    });
                };
                auto uploadOriginal = [this, fail, finalize, trace, originalPath, originalAbs, originalArgs]() {
                    trace("UPLOAD_ORIGINAL_BEGIN");
                    uploadStorageObject(originalPath, originalAbs, originalArgs.value(QStringLiteral("p_original_mime_type")).toString(),
                                        [fail, finalize, trace](bool okOriginal, const QString &uploadError) {
                        if (!okOriginal) {
                            fail(uploadError, uploadError.isEmpty()
                                     ? QStringLiteral("Sin conexión: la fotografía queda pendiente.")
                                     : QStringLiteral("El almacenamiento rechazó la fotografía original (%1).").arg(uploadError),
                                 QStringLiteral("UPLOAD_ORIGINAL"));
                            return;
                        }
                        trace("UPLOAD_ORIGINAL_OK");
                        finalize();
                    });
                };
                // The card rendition reaches Storage first; FINALIZE still needs both objects.
                if (derivativePath.isEmpty() || derivedAbs.isEmpty()) { uploadOriginal(); return; }
                trace("UPLOAD_DERIVATIVE_BEGIN");
                uploadStorageObject(derivativePath, derivedAbs, derivativeArgs.value(QStringLiteral("p_derivative_mime_type")).toString(),
                                    [fail, uploadOriginal, trace](bool okDerived, const QString &derivedError) {
                    if (!okDerived) {
                        fail(derivedError, derivedError.isEmpty()
                                 ? QStringLiteral("Sin conexión: la fotografía queda pendiente.")
                                 : QStringLiteral("El almacenamiento rechazó la fotografía derivada (%1).").arg(derivedError),
                             QStringLiteral("UPLOAD_DERIVATIVE"));
                        return;
                    }
                    trace("UPLOAD_DERIVATIVE_OK");
                    uploadOriginal();
                });
            });
        };

        if (!entry.value(QStringLiteral("new_media")).toBool() || ourMedia) { reserve(); return; }
        QVariantMap createArgs = originalArgs;
        createArgs[QStringLiteral("p_project_id")] = projectId;
        createArgs[QStringLiteral("p_calicata_id")] = calicataId;
        createArgs[QStringLiteral("p_resource_type")] = QStringLiteral("PHOTO");
        createArgs[QStringLiteral("p_category_code")] = category;
        createArgs[QStringLiteral("p_media_id")] = mediaId;
        postRpc(QStringLiteral("create_my_calicata_media_v01"), createArgs,
                [fail, reserve](bool okCreate, const QJsonDocument &, const QString &codeCreate, const QString &messageCreate) {
            if (!okCreate && codeCreate != QLatin1String("23505")) { fail(codeCreate, messageCreate, QStringLiteral("CREATE")); return; }
            reserve();
        });
    });
}

void CalicataCloudService::loadPhotoHistory(CalicataDocument *document, int idx)
{
    if (!document || idx < 1 || idx > 3) return;
    const QString localId = document->instanceId();
    const QString mediaId = normalizedUuid(document->images().value(QStringLiteral("foto%1_media_id").arg(idx)).toString());
    auto *ctx = appContext();
    auto *api = ctx ? ctx->supabase() : nullptr;
    if (mediaId.isEmpty() || !api) { emit photoHistoryLoaded(localId, idx, {}); return; }
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("select"), QStringLiteral("version_id,media_id,version_number,derivative_storage_path,finalized_at,state,discarded_at"));
    query.addQueryItem(QStringLiteral("media_id"), QStringLiteral("eq.") + mediaId);
    query.addQueryItem(QStringLiteral("state"), QStringLiteral("eq.READY"));
    query.addQueryItem(QStringLiteral("discarded_at"), QStringLiteral("is.null"));
    query.addQueryItem(QStringLiteral("order"), QStringLiteral("version_number.desc"));
    query.addQueryItem(QStringLiteral("limit"), QStringLiteral("30"));
    QUrl url = api->restUrl(QStringLiteral("calicata_media_versions"));
    url.setQuery(query);
    getJson(url, [this, localId, idx](bool ok, const QJsonDocument &document, const QString &, const QString &) {
        // Unknown history is a shorter list, never an error for the ficha (Web).
        emit photoHistoryLoaded(localId, idx, ok ? rows(document) : QVariantList());
    });
}

// ===================== P6 activity + P1/P5 remote media =====================

void CalicataCloudService::loadActivity(CalicataDocument *document, int offset)
{
    if (!document) return;
    const QString localId = document->instanceId();
    const QString calicataId = normalizedUuid(document->header().value(QStringLiteral("remoteCalicataId")).toString());
    auto *api = appContext() ? appContext()->supabase() : nullptr;
    if (calicataId.isEmpty() || !api) { emit activityLoaded(localId, {}, offset, false); return; }
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("select"), QStringLiteral("id,action,description,actor_id,platform,created_at,metadata"));
    query.addQueryItem(QStringLiteral("entity_type"), QStringLiteral("eq.CALICATA"));
    query.addQueryItem(QStringLiteral("entity_id"), QStringLiteral("eq.") + calicataId);
    query.addQueryItem(QStringLiteral("order"), QStringLiteral("created_at.desc"));
    query.addQueryItem(QStringLiteral("limit"), QStringLiteral("30"));
    query.addQueryItem(QStringLiteral("offset"), QString::number(qMax(0, offset)));
    QUrl url = api->restUrl(QStringLiteral("activity_logs"));
    url.setQuery(query);
    getJson(url, [this, localId, offset](bool ok, const QJsonDocument &document, const QString &, const QString &message) {
        const QVariantList list = ok ? rows(document) : QVariantList();
        if (!ok) setLastError(message);
        emit activityLoaded(localId, list, offset, ok && list.size() == 30);
    });
}

void CalicataCloudService::downloadStorageObject(const QString &path, const QString &destAbs,
                                                 std::function<void(bool, const QString &)> done)
{
    auto *ctx = appContext();
    auto *api = ctx ? ctx->supabase() : nullptr;
    auto *auth = ctx ? ctx->auth() : nullptr;
    if (!api || !auth || !auth->logged() || auth->accessToken().isEmpty() || path.isEmpty()) {
        done(false, QStringLiteral("AUTH_REQUIRED")); return;
    }
    QString base = api->restUrl(QString()).toString();
    base.replace(QStringLiteral("/rest/v1"), QStringLiteral("/storage/v1"));
    if (!base.endsWith(QLatin1Char('/'))) base += QLatin1Char('/');
    // Same signed read as Web (createSignedUrl): RLS decides, no service role.
    QNetworkRequest sign = api->makeRequest(QUrl(base + QStringLiteral("object/sign/calicata-media/") + path), auth->accessToken());
    sign.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("application/json"));
    QNetworkReply *reply = api->nam()->post(sign, QByteArrayLiteral("{\"expiresIn\":600}"));
    beginRequest();
    QTimer::singleShot(30000, reply, [reply]() { if (!reply->isFinished()) reply->abort(); });
    connect(reply, &QNetworkReply::finished, this, [this, reply, base, destAbs, done]() {
        endRequest();
        const QJsonObject object = QJsonDocument::fromJson(reply->readAll()).object();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        reply->deleteLater();
        QString signedPath = object.value(QStringLiteral("signedURL")).toString();
        if (signedPath.isEmpty()) signedPath = object.value(QStringLiteral("signedUrl")).toString();
        if (http < 200 || http >= 300 || signedPath.isEmpty()) { done(false, QStringLiteral("HTTP_%1").arg(http)); return; }
        if (signedPath.startsWith(QLatin1Char('/'))) signedPath = signedPath.mid(1);
        const QUrl url = signedPath.startsWith(QLatin1String("http")) ? QUrl(signedPath) : QUrl(base + signedPath);
        QNetworkReply *download = appContext()->supabase()->nam()->get(QNetworkRequest(url));
        beginRequest();
        QTimer::singleShot(120000, download, [download]() { if (!download->isFinished()) download->abort(); });
        connect(download, &QNetworkReply::finished, this, [this, download, destAbs, done]() {
            endRequest();
            const int status = download->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            const QByteArray bytes = download->readAll();
            download->deleteLater();
            if (status < 200 || status >= 300 || bytes.isEmpty()) { done(false, QStringLiteral("HTTP_%1").arg(status)); return; }
            QDir().mkpath(QFileInfo(destAbs).absolutePath());
            QSaveFile file(destAbs);
            if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size() || !file.commit()) {
                done(false, QStringLiteral("LOCAL_WRITE_FAILED")); return;
            }
            done(true, {});
        });
    });
}

// Web -> Android: the slot's media in use (newest non-discarded, as Web's
// read) and its active revision are downloaded into the local cache and
// adopted as original + derivative. Never overwrites an unpublished local edit.
void CalicataCloudService::downloadRemotePhoto(CalicataDocument *document, int idx, const QString &versionId)
{
    if (!document || idx < 1 || idx > 3) return;
    const QString localId = document->instanceId();
    const QVariantMap header = document->header();
    const QString projectId = normalizedUuid(header.value(QStringLiteral("projectId")).toString());
    const QString calicataId = normalizedUuid(header.value(QStringLiteral("remoteCalicataId")).toString());
    auto *api = appContext() ? appContext()->supabase() : nullptr;
    const QString category = document->photoCategoryCode(idx);
    if (projectId.isEmpty() || calicataId.isEmpty() || !api) return;
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("select"), QStringLiteral("media_id,active_version_id,row_version,original_storage_path,original_file_name,updated_at"));
    query.addQueryItem(QStringLiteral("project_id"), QStringLiteral("eq.") + projectId);
    query.addQueryItem(QStringLiteral("calicata_id"), QStringLiteral("eq.") + calicataId);
    query.addQueryItem(QStringLiteral("resource_type"), QStringLiteral("eq.PHOTO"));
    query.addQueryItem(QStringLiteral("category_code"), QStringLiteral("eq.") + category);
    query.addQueryItem(QStringLiteral("sync_state"), QStringLiteral("eq.UPLOADED"));
    query.addQueryItem(QStringLiteral("discarded_at"), QStringLiteral("is.null"));
    query.addQueryItem(QStringLiteral("order"), QStringLiteral("updated_at.desc"));
    query.addQueryItem(QStringLiteral("limit"), QStringLiteral("1"));
    QUrl url = api->restUrl(QStringLiteral("calicata_media"));
    url.setQuery(query);
    QPointer<CalicataDocument> doc(document);
    getJson(url, [this, doc, idx, localId, versionId](bool ok, const QJsonDocument &slotDocument, const QString &, const QString &message) {
        const QVariantMap media = firstRow(slotDocument);
        if (!ok || media.isEmpty() || !doc) {
            emit mediaSyncChanged(localId, idx, ok ? QStringLiteral("REMOTE_EMPTY") : QStringLiteral("REMOTE_FAILED"), message, {});
            return;
        }
        const QString mediaId = normalizedUuid(media.value(QStringLiteral("media_id")).toString());
        const QString activeVersion = versionId.isEmpty()
            ? normalizedUuid(media.value(QStringLiteral("active_version_id")).toString()) : normalizedUuid(versionId);
        const QString originalPath = media.value(QStringLiteral("original_storage_path")).toString();
        auto *api = appContext()->supabase();
        QUrlQuery versionQuery;
        versionQuery.addQueryItem(QStringLiteral("select"), QStringLiteral("version_id,derivative_storage_path,state,annotation"));
        versionQuery.addQueryItem(QStringLiteral("version_id"), QStringLiteral("eq.") + activeVersion);
        QUrl versionUrl = api->restUrl(QStringLiteral("calicata_media_versions"));
        versionUrl.setQuery(versionQuery);
        auto finish = [this, doc, idx, localId, mediaId, activeVersion, originalPath, media](const QVariantMap &version) {
            if (!doc) return;
            const QString folder = doc->cachedPhotosFolderUrl(idx).toLocalFile();
            const QString cacheDir = folder.isEmpty()
                ? QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/calicata-media-cache")
                : folder;
            const QString originalAbs = QDir(cacheDir).filePath(QStringLiteral("remote_original_") + mediaId + QLatin1Char('.')
                                                                + QFileInfo(originalPath).suffix());
            const QString derivativePath = version.value(QStringLiteral("derivative_storage_path")).toString();
            downloadStorageObject(originalPath, originalAbs, [this, doc, idx, localId, mediaId, activeVersion, derivativePath, cacheDir, originalAbs, version, media](bool okOriginal, const QString &error) {
                if (!okOriginal || !doc) { emit mediaSyncChanged(localId, idx, QStringLiteral("REMOTE_FAILED"), error, {}); return; }
                const QString derivedAbs = derivativePath.isEmpty() ? QString()
                    : QDir(cacheDir).filePath(QStringLiteral("remote_derivada_") + activeVersion + QLatin1Char('.') + QFileInfo(derivativePath).suffix());
                auto adopt = [this, doc, idx, localId, mediaId, activeVersion, originalAbs, version, media](const QString &derived) {
                    if (!doc) return;
                    QVariantMap remote;
                    remote[QStringLiteral("media_id")] = mediaId;
                    remote[QStringLiteral("version_id")] = activeVersion;
                    remote[QStringLiteral("row_version")] = media.value(QStringLiteral("row_version"));
                    remote[QStringLiteral("original_abs")] = originalAbs;
                    remote[QStringLiteral("derived_abs")] = derived.isEmpty() ? originalAbs : derived;
                    remote[QStringLiteral("annotation")] = version.value(QStringLiteral("annotation"));
                    const bool adopted = doc->adoptRemotePhoto(idx, remote);
                    emit mediaSyncChanged(localId, idx, adopted ? QStringLiteral("SYNCED") : QStringLiteral("CONFLICT"),
                                          adopted ? QString() : QStringLiteral("Hay una edición local sin publicar; no se reemplazó."), {});
                };
                if (derivedAbs.isEmpty()) { adopt({}); return; }
                downloadStorageObject(derivativePath, derivedAbs, [adopt, derivedAbs](bool okDerived, const QString &) {
                    adopt(okDerived ? derivedAbs : QString());
                });
            });
        };
        if (activeVersion.isEmpty()) { finish({}); return; }
        getJson(versionUrl, [finish](bool okVersion, const QJsonDocument &versionDocument, const QString &, const QString &) {
            finish(okVersion ? firstRow(versionDocument) : QVariantMap());
        });
    });
}

// Cloud-only revision in use again: CAS on the media row_version, then pull it.
void CalicataCloudService::activateCloudPhotoVersion(CalicataDocument *document, int idx, const QString &versionId)
{
    if (!document || idx < 1 || idx > 3) return;
    const QString mediaId = normalizedUuid(document->images().value(QStringLiteral("foto%1_media_id").arg(idx)).toString());
    const QString localId = document->instanceId();
    auto *api = appContext() ? appContext()->supabase() : nullptr;
    if (mediaId.isEmpty() || versionId.isEmpty() || !api) return;
    QUrl url = api->restUrl(QStringLiteral("calicata_media"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("select"), QStringLiteral("media_id,row_version"));
    query.addQueryItem(QStringLiteral("media_id"), QStringLiteral("eq.") + mediaId);
    url.setQuery(query);
    QPointer<CalicataDocument> doc(document);
    getJson(url, [this, doc, idx, localId, mediaId, versionId](bool ok, const QJsonDocument &mediaDocument, const QString &code, const QString &message) {
        if (!ok) { emit mediaSyncChanged(localId, idx, QStringLiteral("FAILED"), humanCloudError(code, message), {}); return; }
        postRpc(QStringLiteral("set_my_calicata_media_active_version_v01"),
                {{QStringLiteral("p_media_id"), mediaId}, {QStringLiteral("p_version_id"), normalizedUuid(versionId)},
                 {QStringLiteral("p_expected_row_version"), firstRow(mediaDocument).value(QStringLiteral("row_version"))}},
                [this, doc, idx, localId, versionId](bool okActive, const QJsonDocument &, const QString &codeActive, const QString &messageActive) {
            if (!okActive) {
                emit mediaSyncChanged(localId, idx, conflictMediaError(codeActive, messageActive) ? QStringLiteral("CONFLICT") : QStringLiteral("FAILED"),
                                      humanCloudError(codeActive, messageActive), {});
                return;
            }
            if (doc) downloadRemotePhoto(doc, idx, versionId);
        });
    });
}

// Web discard_my_calicata_media_version_v01: soft, undone by the same call.
void CalicataCloudService::discardCloudPhotoVersion(CalicataDocument *document, int idx, const QString &versionId, bool discarded)
{
    if (!document || versionId.isEmpty()) return;
    const QString mediaId = normalizedUuid(document->images().value(QStringLiteral("foto%1_media_id").arg(idx)).toString());
    const QString localId = document->instanceId();
    QPointer<CalicataDocument> doc(document);
    postRpc(QStringLiteral("discard_my_calicata_media_version_v01"),
            {{QStringLiteral("p_media_id"), mediaId}, {QStringLiteral("p_version_id"), normalizedUuid(versionId)},
             {QStringLiteral("p_discarded"), discarded}},
            [this, doc, idx, localId](bool ok, const QJsonDocument &, const QString &code, const QString &message) {
        if (!ok) { emit mediaSyncChanged(localId, idx, QStringLiteral("FAILED"), humanCloudError(code, message), {}); return; }
        if (doc) loadPhotoHistory(doc, idx);
    });
}

// P5: logo in use for PROJECT / ENTITY (newest non-discarded LOGO media) into
// the local Recursos cache; also lists its cloud history (Web listLogoOriginals).
void CalicataCloudService::loadRemoteLogos(CalicataDocument *document, const QString &resourcesDir)
{
    if (!document) return;
    const QVariantMap header = document->header();
    const QString projectId = normalizedUuid(header.value(QStringLiteral("projectId")).toString());
    const QString calicataId = normalizedUuid(header.value(QStringLiteral("remoteCalicataId")).toString());
    auto *api = appContext() ? appContext()->supabase() : nullptr;
    const QString localId = document->instanceId();
    if (projectId.isEmpty() || calicataId.isEmpty() || !api || resourcesDir.isEmpty()) return;
    for (const QString category : {QStringLiteral("PROJECT"), QStringLiteral("ENTITY")}) {
        QUrlQuery query;
        query.addQueryItem(QStringLiteral("select"), QStringLiteral("media_id,original_storage_path,original_file_name,updated_at,discarded_at"));
        query.addQueryItem(QStringLiteral("project_id"), QStringLiteral("eq.") + projectId);
        query.addQueryItem(QStringLiteral("calicata_id"), QStringLiteral("eq.") + calicataId);
        query.addQueryItem(QStringLiteral("resource_type"), QStringLiteral("eq.LOGO"));
        query.addQueryItem(QStringLiteral("category_code"), QStringLiteral("eq.") + category);
        query.addQueryItem(QStringLiteral("sync_state"), QStringLiteral("eq.UPLOADED"));
        query.addQueryItem(QStringLiteral("order"), QStringLiteral("updated_at.desc"));
        query.addQueryItem(QStringLiteral("limit"), QStringLiteral("20"));
        QUrl url = api->restUrl(QStringLiteral("calicata_media"));
        url.setQuery(query);
        getJson(url, [this, localId, category, resourcesDir](bool ok, const QJsonDocument &document, const QString &, const QString &) {
            const QVariantList history = ok ? rows(document) : QVariantList();
            QVariantMap current;
            for (const QVariant &value : history)
                if (value.toMap().value(QStringLiteral("discarded_at")).isNull()) { current = value.toMap(); break; }
            if (current.isEmpty()) { emit remoteLogoLoaded(localId, category, QString(), history); return; }
            const QString path = current.value(QStringLiteral("original_storage_path")).toString();
            const QString dest = QDir(resourcesDir).filePath(QStringLiteral("logo_%1_%2.%3")
                .arg(category.toLower(), normalizedUuid(current.value(QStringLiteral("media_id")).toString()).left(8),
                     QFileInfo(path).suffix()));
            if (QFileInfo::exists(dest)) { emit remoteLogoLoaded(localId, category, dest, history); return; }
            downloadStorageObject(path, dest, [this, localId, category, dest, history](bool okDownload, const QString &) {
                emit remoteLogoLoaded(localId, category, okDownload ? dest : QString(), history);
            });
        });
    }
}

// P5: restoring a cloud logo is a publish of those bytes (Web readCalicataLogoRevision):
// download the chosen revision into Recursos; the page then republishes it.
void CalicataCloudService::restoreRemoteLogo(CalicataDocument *document, const QString &categoryCode,
                                             const QString &storagePath, const QString &resourcesDir)
{
    if (!document || storagePath.isEmpty() || resourcesDir.isEmpty()) return;
    const QString localId = document->instanceId();
    // Cache keyed by the media folder in the storage path (…/media/<media_id>/original/…).
    const QStringList parts = storagePath.split(QLatin1Char('/'));
    const int mediaIndex = parts.indexOf(QStringLiteral("media"));
    const QString mediaKey = mediaIndex >= 0 && mediaIndex + 1 < parts.size() ? parts.at(mediaIndex + 1).left(8) : QStringLiteral("x");
    const QString dest = QDir(resourcesDir).filePath(QStringLiteral("logo_%1_%2_%3").arg(categoryCode.toLower(), mediaKey,
                            QFileInfo(storagePath).fileName()));
    downloadStorageObject(storagePath, dest, [this, localId, categoryCode, dest](bool ok, const QString &error) {
        emit remoteLogoRestored(localId, categoryCode, ok ? dest : QString(), ok ? QString() : error);
    });
}

// ===================== P6: presencia (Supabase Realtime) =====================
// Same contract as Web presenceService.ts: private channel
// "calicata:<calicatas.id>", presence keyed by the user id, meta
// {userId, name, field, joinedAt}. field == null -> VIEWING, else EDITING.
// Transport: RFC 6455 WebSocket over QSslSocket (QtNetwork; the Qt kits have no
// Qt WebSockets module) speaking Phoenix vsn 1.0.0. No polling, no fake roster.
namespace {
const int kPresenceRetryMs[] = {1000, 2000, 4000, 8000, 15000, 30000};
QString presenceTopic(const QString &calicataId) { return QStringLiteral("realtime:calicata:") + calicataId; }
}

void CalicataCloudService::setPresenceState(const QString &state)
{
    if (m_presenceState == state) return;
    m_presenceState = state;
    emit presenceChanged();
}

void CalicataCloudService::joinPresence(CalicataDocument *document)
{
    const QString calicataId = document ? normalizedUuid(document->header().value(QStringLiteral("remoteCalicataId")).toString()) : QString();
    if (calicataId == m_rtCalicataId && m_rtSocket) return;
    rtDisconnect(true);
    m_rtCalicataId = calicataId;
    m_rtField.clear();
    m_rtEverJoined = false;
    m_liveSeen.clear();
    m_liveSeenOrder.clear();
    m_rtJoinedAt = QDateTime::currentMSecsSinceEpoch();
    m_rtRetryStep = 0;
    if (calicataId.isEmpty()) { setPresenceState(QStringLiteral("OFF")); return; }
    rtConnect();
}

void CalicataCloudService::leavePresence()
{
    rtDisconnect(true);
    m_rtCalicataId.clear();
    setPresenceState(QStringLiteral("OFF"));
}

void CalicataCloudService::setPresenceActive(bool active)
{
    if (m_rtActive == active) return;
    m_rtActive = active;
    if (!active) { rtDisconnect(true); setPresenceState(QStringLiteral("PAUSED")); }   // background: leave, no ghost
    else if (!m_rtCalicataId.isEmpty()) { m_rtRetryStep = 0; rtConnect(); }           // foreground: rejoin
}

void CalicataCloudService::setPresenceField(const QString &field)
{
    const QString trimmed = field.trimmed().left(80);   // PRESENCE_FIELD_MAX_LENGTH
    if (trimmed == m_rtField) return;
    m_rtField = trimmed;
    if (m_presenceState == QLatin1String("JOINED")) rtTrack();
}

void CalicataCloudService::rtConnect()
{
    auto *ctx = appContext();
    auto *api = ctx ? ctx->supabase() : nullptr;
    auto *auth = ctx ? ctx->auth() : nullptr;
    if (!m_rtActive || m_rtCalicataId.isEmpty()) return;
    if (!api || !auth || !auth->logged() || auth->accessToken().isEmpty()) { setPresenceState(QStringLiteral("UNAVAILABLE")); return; }
    const QUrl base(api->projectUrl());
    if (base.host().isEmpty()) { setPresenceState(QStringLiteral("UNAVAILABLE")); return; }
    rtDisconnect(false);
    m_rtSocket = new QSslSocket(this);
    m_rtBuffer.clear();
    m_rtFragment.clear();
    m_rtHandshaken = false;
    m_rtToken = auth->accessToken();
    setPresenceState(QStringLiteral("CONNECTING"));
    qInfo().noquote() << "INGE_LIVE_JOIN calicataId=" << m_rtCalicataId;
    QSslSocket *socket = m_rtSocket;
    const QString host = base.host();
    connect(socket, &QSslSocket::encrypted, this, [this, socket, host, api]() {
        if (socket != m_rtSocket) return;
        QByteArray nonce(16, Qt::Uninitialized);
        for (char &c : nonce) c = char(QRandomGenerator::global()->bounded(256));
        const QByteArray request =
            "GET /realtime/v1/websocket?apikey=" + QUrl::toPercentEncoding(api->anonKey()) + "&vsn=1.0.0 HTTP/1.1\r\n"
            "Host: " + host.toUtf8() + "\r\n"
            "Upgrade: websocket\r\nConnection: Upgrade\r\n"
            "Sec-WebSocket-Key: " + nonce.toBase64() + "\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n";
        socket->write(request);
    });
    connect(socket, &QSslSocket::readyRead, this, [this, socket]() { if (socket == m_rtSocket) rtOnReadyRead(); });
    connect(socket, &QSslSocket::disconnected, this, [this, socket]() {
        if (socket != m_rtSocket) return;
        qInfo().noquote() << "INGE_LIVE_DISCONNECT calicataId=" << m_rtCalicataId;
        m_rtSocket = nullptr;
        socket->deleteLater();
        if (m_rtHeartbeat) m_rtHeartbeat->stop();
        m_rtPresence.clear();
        rtRebuildMembers();
        rtScheduleRetry();
    });
    connect(socket, &QSslSocket::errorOccurred, this, [this, socket](QAbstractSocket::SocketError) {
        if (socket == m_rtSocket) socket->abort();
    });
    socket->connectToHostEncrypted(host, quint16(base.port(443)));
}

void CalicataCloudService::rtScheduleRetry()
{
    if (!m_rtActive || m_rtCalicataId.isEmpty() || m_presenceState == QLatin1String("UNAVAILABLE")) return;
    setPresenceState(QStringLiteral("RECONNECTING"));
    if (!m_rtRetry) {
        m_rtRetry = new QTimer(this);
        m_rtRetry->setSingleShot(true);
        connect(m_rtRetry, &QTimer::timeout, this, [this]() { rtConnect(); });
    }
    const int steps = int(sizeof(kPresenceRetryMs) / sizeof(kPresenceRetryMs[0]));
    m_rtRetry->start(kPresenceRetryMs[qBound(0, m_rtRetryStep, steps - 1)]);
    m_rtRetryStep = qMin(m_rtRetryStep + 1, steps - 1);
}

void CalicataCloudService::rtDisconnect(bool leave)
{
    if (m_rtRetry) m_rtRetry->stop();
    if (m_rtHeartbeat) m_rtHeartbeat->stop();
    QSslSocket *socket = m_rtSocket;
    m_rtSocket = nullptr;
    if (socket) {
        if (leave && m_rtHandshaken && socket->state() == QAbstractSocket::ConnectedState) {
            const QString topic = presenceTopic(m_rtCalicataId);
            m_rtSocket = socket;   // allow the goodbye frames
            rtSendJson({{QStringLiteral("topic"), topic}, {QStringLiteral("event"), QStringLiteral("presence")},
                        {QStringLiteral("payload"), QVariantMap{{QStringLiteral("type"), QStringLiteral("presence")},
                                                                 {QStringLiteral("event"), QStringLiteral("untrack")}}},
                        {QStringLiteral("ref"), QString::number(++m_rtRef)}, {QStringLiteral("join_ref"), m_rtJoinRef}});
            rtSendJson({{QStringLiteral("topic"), topic}, {QStringLiteral("event"), QStringLiteral("phx_leave")},
                        {QStringLiteral("payload"), QVariantMap()}, {QStringLiteral("ref"), QString::number(++m_rtRef)},
                        {QStringLiteral("join_ref"), m_rtJoinRef}});
            rtSendFrame(0x8, QByteArray::fromHex("03e8"));   // close 1000
            m_rtSocket = nullptr;
            socket->flush();
        }
        socket->disconnect(this);
        socket->disconnectFromHost();
        socket->deleteLater();
    }
    m_rtHandshaken = false;
    m_rtPresence.clear();
    rtRebuildMembers();
}

void CalicataCloudService::rtSendFrame(quint8 opcode, const QByteArray &payload)
{
    if (!m_rtSocket) return;
    QByteArray frame;
    frame.append(char(0x80 | (opcode & 0x0F)));
    const qint64 size = payload.size();
    if (size < 126) frame.append(char(0x80 | size));
    else if (size <= 0xFFFF) { frame.append(char(0x80 | 126)); frame.append(char((size >> 8) & 0xFF)); frame.append(char(size & 0xFF)); }
    else { frame.append(char(0x80 | 127)); for (int shift = 56; shift >= 0; shift -= 8) frame.append(char((size >> shift) & 0xFF)); }
    char mask[4];
    for (char &c : mask) c = char(QRandomGenerator::global()->bounded(256));
    frame.append(mask, 4);
    QByteArray masked = payload;
    for (qsizetype i = 0; i < masked.size(); ++i) masked[i] = char(masked.at(i) ^ mask[i % 4]);   // client frames are masked
    frame.append(masked);
    m_rtSocket->write(frame);
}

void CalicataCloudService::rtSendJson(const QVariantMap &message)
{
    rtSendFrame(0x1, QJsonDocument::fromVariant(message).toJson(QJsonDocument::Compact));
}

void CalicataCloudService::rtOnReadyRead()
{
    m_rtBuffer.append(m_rtSocket->readAll());
    if (!m_rtHandshaken) {
        const qsizetype end = m_rtBuffer.indexOf("\r\n\r\n");
        if (end < 0) return;
        const QByteArray status = m_rtBuffer.left(m_rtBuffer.indexOf("\r\n"));
        m_rtBuffer.remove(0, end + 4);
        if (!status.contains(" 101")) { setPresenceState(QStringLiteral("UNAVAILABLE")); rtDisconnect(false); return; }
        m_rtHandshaken = true;
        m_rtJoinRef = QString::number(++m_rtRef);
        QVariantMap config;
        config[QStringLiteral("broadcast")] = QVariantMap{{QStringLiteral("ack"), false}, {QStringLiteral("self"), false}};
        // Canonical Web presence: keyed by userId (tabs of one person grouped).
        config[QStringLiteral("presence")] = QVariantMap{{QStringLiteral("key"), normalizedUuid(appContext()->auth()->userId())},
                                                         {QStringLiteral("enabled"), true}};
        config[QStringLiteral("postgres_changes")] = QVariantList();
        config[QStringLiteral("private")] = true;
        rtSendJson({{QStringLiteral("topic"), presenceTopic(m_rtCalicataId)}, {QStringLiteral("event"), QStringLiteral("phx_join")},
                    {QStringLiteral("payload"), QVariantMap{{QStringLiteral("config"), config},
                                                            {QStringLiteral("access_token"), m_rtToken}}},
                    {QStringLiteral("ref"), m_rtJoinRef}, {QStringLiteral("join_ref"), m_rtJoinRef}});
        if (!m_rtHeartbeat) {
            m_rtHeartbeat = new QTimer(this);
            m_rtHeartbeat->setInterval(25000);
            connect(m_rtHeartbeat, &QTimer::timeout, this, [this]() {
                if (!m_rtSocket || !m_rtHandshaken) return;
                rtSendJson({{QStringLiteral("topic"), QStringLiteral("phoenix")}, {QStringLiteral("event"), QStringLiteral("heartbeat")},
                            {QStringLiteral("payload"), QVariantMap()}, {QStringLiteral("ref"), QString::number(++m_rtRef)}});
                // Auth refresh: a renewed session token is handed to the channel.
                auto *auth = appContext() ? appContext()->auth() : nullptr;
                if (auth && auth->logged() && !auth->accessToken().isEmpty() && auth->accessToken() != m_rtToken) {
                    m_rtToken = auth->accessToken();
                    rtSendJson({{QStringLiteral("topic"), presenceTopic(m_rtCalicataId)}, {QStringLiteral("event"), QStringLiteral("access_token")},
                                {QStringLiteral("payload"), QVariantMap{{QStringLiteral("access_token"), m_rtToken}}},
                                {QStringLiteral("ref"), QString::number(++m_rtRef)}, {QStringLiteral("join_ref"), m_rtJoinRef}});
                }
            });
        }
        m_rtHeartbeat->start();
    }
    for (;;) {
        if (m_rtBuffer.size() < 2 || !m_rtSocket) return;
        const quint8 b0 = quint8(m_rtBuffer.at(0)), b1 = quint8(m_rtBuffer.at(1));
        const bool fin = b0 & 0x80, masked = b1 & 0x80;
        const quint8 opcode = b0 & 0x0F;
        qint64 length = b1 & 0x7F;
        qsizetype offset = 2;
        if (length == 126) {
            if (m_rtBuffer.size() < 4) return;
            length = (quint8(m_rtBuffer.at(2)) << 8) | quint8(m_rtBuffer.at(3));
            offset = 4;
        } else if (length == 127) {
            if (m_rtBuffer.size() < 10) return;
            length = 0;
            for (int i = 2; i < 10; ++i) length = (length << 8) | quint8(m_rtBuffer.at(i));
            offset = 10;
        }
        if (length < 0 || length > 16 * 1024 * 1024) { rtDisconnect(false); rtScheduleRetry(); return; }
        const qsizetype maskOffset = offset;
        if (masked) offset += 4;
        if (m_rtBuffer.size() < offset + length) return;
        QByteArray payload = m_rtBuffer.mid(offset, length);
        if (masked) for (qsizetype i = 0; i < payload.size(); ++i) payload[i] = char(payload.at(i) ^ m_rtBuffer.at(maskOffset + i % 4));
        m_rtBuffer.remove(0, offset + length);
        if (opcode == 0x9) { rtSendFrame(0xA, payload); continue; }
        if (opcode == 0xA) continue;
        if (opcode == 0x8) { QSslSocket *s = m_rtSocket; if (s) s->disconnectFromHost(); return; }
        if (opcode == 0x1 || opcode == 0x0) {
            m_rtFragment.append(payload);
            if (!fin) continue;
            const QByteArray message = m_rtFragment;
            m_rtFragment.clear();
            rtHandleMessage(message);
        }
    }
}

void CalicataCloudService::rtHandleMessage(const QByteArray &raw)
{
    const QVariantMap message = QJsonDocument::fromJson(raw).toVariant().toMap();
    const QString event = message.value(QStringLiteral("event")).toString();
    const QVariantMap payload = message.value(QStringLiteral("payload")).toMap();
    if (event == QLatin1String("phx_reply") && message.value(QStringLiteral("ref")).toString() == m_rtJoinRef) {
        if (payload.value(QStringLiteral("status")).toString() == QLatin1String("ok")) {
            m_rtRetryStep = 0;
            setPresenceState(QStringLiteral("JOINED"));
            rtTrack();
            if (m_rtEverJoined) {
                // Patches sent while we were away are not replayed: revalidate.
                qInfo().noquote() << "INGE_LIVE_RECONNECT calicataId=" << m_rtCalicataId;
                emit liveResyncRequested(m_rtCalicataId);
            } else {
                qInfo().noquote() << "INGE_LIVE_READY calicataId=" << m_rtCalicataId;
            }
            m_rtEverJoined = true;
        } else {
            // Refused by RLS or not deployed: honest "unavailable", no retry storm.
            setPresenceState(QStringLiteral("UNAVAILABLE"));
            rtDisconnect(false);
        }
        return;
    }
    if (event == QLatin1String("phx_error") || event == QLatin1String("phx_close")) {
        if (m_rtSocket) m_rtSocket->abort();
        return;
    }
    if (event == QLatin1String("broadcast")) {
        rtHandleBroadcast(payload);
        return;
    }
    if (event == QLatin1String("presence_state")) {
        m_rtPresence = payload;
        rtRebuildMembers();
        return;
    }
    if (event == QLatin1String("presence_diff")) {
        const QVariantMap joins = payload.value(QStringLiteral("joins")).toMap();
        const QVariantMap leaves = payload.value(QStringLiteral("leaves")).toMap();
        for (auto it = leaves.cbegin(); it != leaves.cend(); ++it) {
            QSet<QString> gone;
            for (const QVariant &meta : it.value().toMap().value(QStringLiteral("metas")).toList())
                gone.insert(meta.toMap().value(QStringLiteral("phx_ref")).toString());
            QVariantList kept;
            for (const QVariant &meta : m_rtPresence.value(it.key()).toMap().value(QStringLiteral("metas")).toList())
                if (!gone.contains(meta.toMap().value(QStringLiteral("phx_ref")).toString())) kept << meta;
            if (kept.isEmpty()) m_rtPresence.remove(it.key());
            else m_rtPresence[it.key()] = QVariantMap{{QStringLiteral("metas"), kept}};
        }
        for (auto it = joins.cbegin(); it != joins.cend(); ++it) {
            QVariantList metas = m_rtPresence.value(it.key()).toMap().value(QStringLiteral("metas")).toList();
            metas += it.value().toMap().value(QStringLiteral("metas")).toList();
            m_rtPresence[it.key()] = QVariantMap{{QStringLiteral("metas"), metas}};
        }
        rtRebuildMembers();
    }
}

void CalicataCloudService::rtTrack()
{
    auto *auth = appContext() ? appContext()->auth() : nullptr;
    if (!auth || !m_rtSocket) return;
    QString name = auth->property("displayName").toString().trimmed();
    if (name.isEmpty()) name = auth->property("email").toString().section(QLatin1Char('@'), 0, 0);
    QVariantMap meta;
    meta[QStringLiteral("userId")] = normalizedUuid(auth->userId());
    meta[QStringLiteral("name")] = name.left(60);   // PRESENCE_NAME_MAX_LENGTH
    meta[QStringLiteral("field")] = m_rtField.isEmpty() ? QVariant() : QVariant(m_rtField);
    meta[QStringLiteral("joinedAt")] = m_rtJoinedAt;
    rtSendJson({{QStringLiteral("topic"), presenceTopic(m_rtCalicataId)}, {QStringLiteral("event"), QStringLiteral("presence")},
                {QStringLiteral("payload"), QVariantMap{{QStringLiteral("type"), QStringLiteral("presence")},
                                                         {QStringLiteral("event"), QStringLiteral("track")},
                                                         {QStringLiteral("payload"), meta}}},
                {QStringLiteral("ref"), QString::number(++m_rtRef)}, {QStringLiteral("join_ref"), m_rtJoinRef}});
}

void CalicataCloudService::rtRebuildMembers()
{
    auto *auth = appContext() ? appContext()->auth() : nullptr;
    const QString self = auth ? normalizedUuid(auth->userId()) : QString();
    QVariantList members;
    // Canonical Web roster: one entry per person (presence key = userId); the
    // newest meta represents that person's tabs/devices.
    for (auto it = m_rtPresence.cbegin(); it != m_rtPresence.cend(); ++it) {
        const QVariantList metas = it.value().toMap().value(QStringLiteral("metas")).toList();
        if (metas.isEmpty()) continue;
        const QVariantMap meta = metas.last().toMap();
        const QString name = meta.value(QStringLiteral("name")).toString().left(60);
        const QString field = meta.value(QStringLiteral("field")).toString();
        members << QVariantMap{{QStringLiteral("userId"), it.key()}, {QStringLiteral("name"), name},
                               {QStringLiteral("initial"), name.isEmpty() ? QStringLiteral("?") : name.left(1).toUpper()},
                               {QStringLiteral("mode"), field.isEmpty() ? QStringLiteral("VIEWING") : QStringLiteral("EDITING")},
                               {QStringLiteral("field"), field}, {QStringLiteral("self"), it.key() == self},
                               {QStringLiteral("joinedAt"), meta.value(QStringLiteral("joinedAt"))}};
    }
    if (members == m_presenceMembers) return;
    m_presenceMembers = members;
    qInfo().noquote() << "INGE_LIVE_PRESENCE calicataId=" << m_rtCalicataId << "people=" << members.size();
    emit presenceChanged();
}

// ===================== Live field changes (canonical Web contract) =====================
// docs/CALICATAS_LIVE_COLLAB_V1.md. Source of truth: ingeplus-web
// feature/calicatas-cloud-media-04a (fieldChanges.ts / fieldChangeService.ts).
// Persist first, broadcast after: the durable RPC apply_calicata_field_change_v02
// decides the standing change for target+field; only that standing change is
// announced with the Web event "calicata-field-change". Structure
// (add/delete/move strata) is NOT a field change and keeps its own RPC + CAS.
// Prose (calicata-prose, Yjs) is not implemented on Android: prose fields are
// never sent live here; they persist through the normal save.
namespace {
const QString kFieldChangeEvent = QStringLiteral("calicata-field-change");
const QString kProseEvent = QStringLiteral("calicata-prose");
const QStringList kCalicataFields{
    QStringLiteral("code"), QStringLiteral("title"), QStringLiteral("location"), QStringLiteral("progresiva"),
    QStringLiteral("easting"), QStringLiteral("northing"), QStringLiteral("altitude_m"), QStringLiteral("depth_m"),
    QStringLiteral("groundwater_depth_m"), QStringLiteral("utm_zone"), QStringLiteral("supervisor"),
    QStringLiteral("machine"), QStringLiteral("start_date"), QStringLiteral("end_date"),
    QStringLiteral("description"), QStringLiteral("observations")};
const QStringList kStratumFields{
    QStringLiteral("to_depth_m"), QStringLiteral("description"), QStringLiteral("moisture_condition"),
    QStringLiteral("consistency_compaction"), QStringLiteral("excavability"), QStringLiteral("color"),
    QStringLiteral("sample_type"), QStringLiteral("observations")};
// LAB_RESULT (target.id = id del estrato): campos confirmados en el servidor Dev.
const QStringList kLabResultFields{
    QStringLiteral("sieve_max_pct"), QStringLiteral("sieve_no4_pct"), QStringLiteral("sieve_2mm_pct"),
    QStringLiteral("sieve_04mm_pct"), QStringLiteral("sieve_008mm_pct"), QStringLiteral("liquid_limit"),
    QStringLiteral("plastic_limit"), QStringLiteral("natural_moisture_pct"), QStringLiteral("primary_sucs"),
    QStringLiteral("is_composite"), QStringLiteral("secondary_sucs"), QStringLiteral("aashto"),
    QStringLiteral("laboratory_source"), QStringLiteral("test_date")};

bool fieldAllowed(const QString &type, const QString &field)
{
    if (type == QLatin1String("CALICATA")) return kCalicataFields.contains(field);
    if (type == QLatin1String("STRATUM")) return kStratumFields.contains(field);
    if (type == QLatin1String("LAB_RESULT")) return kLabResultFields.contains(field);
    return false;
}

QVariantMap canonicalFieldChange(const QString &changeId, const QString &type, const QString &targetId,
                                 const QString &field, const QVariant &value, const QString &authorId,
                                 const QString &at)
{
    return {{QStringLiteral("changeId"), changeId},
            {QStringLiteral("target"), QVariantMap{{QStringLiteral("type"), type}, {QStringLiteral("id"), targetId}}},
            {QStringLiteral("field"), field},
            {QStringLiteral("value"), value.isNull() || !value.isValid() ? QVariant() : QVariant(value.toString())},
            {QStringLiteral("authorId"), authorId},
            {QStringLiteral("at"), at}};
}
}

bool CalicataCloudService::applyFieldChange(CalicataDocument *document, const QString &targetType,
                                            const QString &targetId, const QString &field, const QVariant &value)
{
    auto *auth = appContext() ? appContext()->auth() : nullptr;
    const QPointer<CalicataDocument> target(document);
    if (!target || target->closed() || !auth || !auth->logged()) return false;
    const QVariantMap header = target->header();
    const QString projectId = normalizedUuid(header.value(QStringLiteral("projectId")).toString());
    const QString calicataId = normalizedUuid(header.value(QStringLiteral("remoteCalicataId")).toString());
    const QString targetUuid = normalizedUuid(targetId);
    // Live editing is draft-only on the server; outside a joined live session the
    // normal full save carries the value. No local "success" is invented.
    if (projectId.isEmpty() || calicataId.isEmpty() || targetUuid.isEmpty() || calicataId != m_rtCalicataId
        || m_presenceState != QLatin1String("JOINED") || !fieldAllowed(targetType, field)
        || target->status() != QLatin1String("BORRADOR")) return false;
    if (targetType == QLatin1String("CALICATA") && targetUuid != calicataId) return false;

    const QString owner = normalizedUuid(auth->userId());
    const QString localId = target->instanceId();
    const QVariant textValue = value.isNull() || !value.isValid() ? QVariant() : QVariant(value.toString());
    // after(state): 1 = nuestro UPDATE se aplicó, 0 = no se aplicó (rechazo /
    // vigente de otra persona), 2 = desconocido (sin respuesta del servidor).
    const auto send = [this, projectId, calicataId, targetType, targetUuid, field, textValue, owner, localId]
                      (std::function<void(int)> after) {
        const QString changeId = QUuid::createUuid().toString(QUuid::WithoutBraces);
        const QString clientAt = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
        qInfo().noquote() << "INGE_LIVE_FIELD_TX_BEGIN calicataId=" << calicataId << "target=" << targetType
                          << targetUuid << "field=" << field;
        postRpc(QStringLiteral("apply_calicata_field_change_v02"),
                {{QStringLiteral("p_project_id"), projectId}, {QStringLiteral("p_calicata_id"), calicataId},
                 {QStringLiteral("p_target_type"), targetType}, {QStringLiteral("p_target_id"), targetUuid},
                 {QStringLiteral("p_change_id"), changeId}, {QStringLiteral("p_field"), field},
                 {QStringLiteral("p_value"), textValue}, {QStringLiteral("p_client_at"), clientAt}},
                [this, localId, calicataId, targetType, targetUuid, field, changeId, owner, after]
                (bool ok, const QJsonDocument &document, const QString &code, const QString &message) {
            QVariantMap result{{QStringLiteral("changeId"), changeId}, {QStringLiteral("field"), field},
                               {QStringLiteral("target"), QVariantMap{{QStringLiteral("type"), targetType},
                                                                       {QStringLiteral("id"), targetUuid}}}};
            if (!ok) {
                // No JSON error code = network/server unreachable; PostgREST errors
                // (e.g. RPC not deployed) are unavailability too. Anything else is a
                // server decision (draft-only, not authorized, unknown field...).
                const bool unavailable = code.isEmpty() || code == QLatin1String("AUTH_REQUIRED")
                    || code == QLatin1String("INVALID_JSON") || code == QLatin1String("ACCOUNT_CHANGED")
                    || code.startsWith(QLatin1String("PGRST"));
                result[QStringLiteral("outcome")] = unavailable ? QStringLiteral("UNAVAILABLE") : QStringLiteral("REFUSED");
                result[QStringLiteral("message")] = humanCloudError(code, message);
                qWarning().noquote() << "INGE_LIVE_FIELD_TX_" << result.value(QStringLiteral("outcome")).toString()
                                     << "field=" << field << "code=" << code;
                emit fieldChangeSettled(localId, result);   // never announced to peers
                // Sin código = sin respuesta: el servidor pudo haber aplicado el cambio.
                if (after) after(code.isEmpty() ? 2 : 0);
                return;
            }
            // Standing change returned by the server (tolerant to snake/camel keys).
            const QVariantMap row = firstRow(document);
            const auto pick = [&row](std::initializer_list<const char *> keys) -> QVariant {
                for (const char *key : keys) {
                    const QString k = QString::fromLatin1(key);
                    if (row.contains(k)) return row.value(k);
                }
                return {};
            };
            // RETURNS public.calicata_field_changes: row.id is the standing changeId.
            const QString standingId = normalizedUuid(pick({"id", "change_id", "changeId"}).toString());
            const QVariant standingValue = pick({"value", "standing_value"});
            const QString standingAuthor = normalizedUuid(pick({"author_id", "authorId", "actor_id"}).toString());
            const QString standingAt = pick({"client_at", "at", "applied_at", "created_at"}).toString();
            if (standingId.isEmpty()) {
                result[QStringLiteral("outcome")] = QStringLiteral("UNAVAILABLE");
                result[QStringLiteral("message")] = QStringLiteral("El servidor no devolvió el cambio vigente.");
                emit fieldChangeSettled(localId, result);
                if (after) after(2);
                return;
            }
            const bool applied = standingId == changeId;
            const QVariantMap standing = canonicalFieldChange(standingId, targetType, targetUuid, field, standingValue,
                                                              standingAuthor.isEmpty() && applied ? owner : standingAuthor,
                                                              standingAt);
            result = standing;
            result[QStringLiteral("outcome")] = applied ? QStringLiteral("APPLIED") : QStringLiteral("SUPERSEDED");
            // Durable first, then the canonical announcement of what actually stands.
            if (calicataId == m_rtCalicataId && m_presenceState == QLatin1String("JOINED")) {
                rtSendJson({{QStringLiteral("topic"), presenceTopic(m_rtCalicataId)}, {QStringLiteral("event"), QStringLiteral("broadcast")},
                            {QStringLiteral("payload"), QVariantMap{{QStringLiteral("type"), QStringLiteral("broadcast")},
                                                                     {QStringLiteral("event"), kFieldChangeEvent},
                                                                     {QStringLiteral("payload"), standing}}},
                            {QStringLiteral("ref"), QString::number(++m_rtRef)}, {QStringLiteral("join_ref"), m_rtJoinRef}});
            }
            qInfo().noquote() << "INGE_LIVE_FIELD_TX_" << result.value(QStringLiteral("outcome")).toString()
                              << "calicataId=" << calicataId << "field=" << field;
            emit fieldChangeSettled(localId, result);
            // CALICATA: el servidor PUEDE mover row_version (valor ya vigente = 0
            // columnas cambiadas = +1). El carril sondea y atribuye (runLiveCalicataChange).
            if (after) after(applied ? 1 : 0);
        });
    };
    if (targetType == QLatin1String("CALICATA")) {
        runLiveCalicataChange(target, field, textValue, send);
        return true;
    }
    // STRATUM / LAB_RESULT no tocan public.calicatas: no mueven row_version.
    send({});
    return true;
}

void CalicataCloudService::runLiveCalicataChange(CalicataDocument *document, const QString &field, const QVariant &value,
                                                 std::function<void(std::function<void(int)>)> send)
{
    const QPointer<CalicataDocument> target(document);
    if (!target || target->closed()) return;
    const QString localId = target->instanceId();
    auto &lane = m_lanes[localId];
    m_laneDocs[localId] = target;
    if (!lane.tryAcquire()) {
        // Hay una escritura de la ficha en vuelo: el cambio espera su turno (sin CAS en paralelo).
        qInfo().noquote() << "INGE_LIVE_FIELD_QUEUED field=" << field << "generation=" << lane.generation();
        lane.defer([this, target, localId, field, value, send]() {
            if (!target || target->closed()) { releaseLane(localId); return; }
            runLiveCalicataChange(target, field, value, send);
        });
        return;
    }
    const QVariantMap header = target->header();
    const QString projectId = normalizedUuid(header.value(QStringLiteral("projectId")).toString());
    const QString remoteId = normalizedUuid(header.value(QStringLiteral("remoteCalicataId")).toString());
    const qint64 confirmed = CalicataSync::expectedRevision(
        header.value(QStringLiteral("remoteRowVersion"), header.value(QStringLiteral("row_version"))).toLongLong(),
        m_confirmedRevisions.value(remoteId));
    probeRoot(projectId, remoteId, [this, target, localId, projectId, remoteId, confirmed, field, value, send]
              (bool okBefore, const QVariantMap &before) {
        if (!okBefore) {
            // Sin lectura previa no se puede atribuir su efecto: el valor viaja con la sync completa.
            qWarning().noquote() << "INGE_LIVE_FIELD_DEFERRED_TO_SYNC field=" << field << "reason=probe_failed";
            m_lanes[localId].requestSync(QStringLiteral("autosave"));
            releaseLane(localId);
            return;
        }
        const qint64 revisionBefore = before.value(QStringLiteral("row_version")).toLongLong();
        auto &seed = m_lanes[localId];
        if (revisionBefore == confirmed && seed.baseRoot.isEmpty()) seed.baseRoot = before;
        send([this, target, localId, projectId, remoteId, confirmed, field, value, before, revisionBefore](int applied) {
            if (applied == 0) { releaseLane(localId); return; }   // nuestro UPDATE no se ejecutó
            probeRoot(projectId, remoteId, [this, target, localId, projectId, remoteId, confirmed, field, value,
                                            before, revisionBefore](bool okAfter, const QVariantMap &after) {
                auto &lane = m_lanes[localId];
                if (!okAfter) {
                    ++lane.uncertainOwnBumps;
                    lane.ownLive[field] = value;
                    qWarning().noquote() << "INGE_LIVE_FIELD_REVISION_UNVERIFIED field=" << field
                                         << "confirmedRevision=" << confirmed << "ownUnverified=" << lane.uncertainOwnBumps;
                    releaseLane(localId);
                    return;
                }
                const qint64 revisionAfter = after.value(QStringLiteral("row_version")).toLongLong();
                bool othersUnchanged = true;
                for (const QString &column : CalicataSync::rootColumns())
                    if (column != field && !CalicataSync::sameValue(after.value(column), before.value(column)))
                        othersUnchanged = false;
                const bool ours = CalicataSync::sameValue(after.value(field), value);
                switch (CalicataSync::attributeLiveWrite(confirmed, revisionBefore, revisionAfter, ours, othersUnchanged)) {
                case CalicataSync::LiveWrite::Unchanged:
                    lane.ownLive[field] = value;
                    break;
                case CalicataSync::LiveWrite::OwnNoopBump:
                    if (target && target->checkpointCloudRevision(projectId, remoteId, revisionAfter)) {
                        noteConfirmedRevision(localId, remoteId, revisionAfter);
                        lane.baseRoot = after;
                        lane.ownLive.clear();
                        qInfo().noquote() << "INGE_CALICATA_SYNC_REBASE reason=live_field_noop field=" << field
                                          << "previousRevision=" << revisionBefore << "confirmedRevision=" << revisionAfter;
                    } else {
                        ++lane.uncertainOwnBumps;
                        lane.ownLive[field] = value;
                    }
                    break;
                case CalicataSync::LiveWrite::Unexplained:
                    // Hubo escrituras de otro cliente: no se adopta su revisión (la
                    // próxima sync lo detecta como conflicto real, sin sobrescribir).
                    lane.ownLive[field] = value;
                    qWarning().noquote() << "INGE_LIVE_FIELD_REVISION_UNEXPLAINED field=" << field
                                         << "confirmedRevision=" << confirmed << "before=" << revisionBefore
                                         << "after=" << revisionAfter;
                    break;
                }
                releaseLane(localId);
            });
        });
    });
}

void CalicataCloudService::rtHandleBroadcast(const QVariantMap &broadcast)
{
    const QString event = broadcast.value(QStringLiteral("event")).toString();
    if (event == kProseEvent) return;   // Yjs prose: not implemented on Android (never corrupt it)
    if (event != kFieldChangeEvent) return;
    const QVariantMap change = broadcast.value(QStringLiteral("payload")).toMap();
    const QVariantMap targetMap = change.value(QStringLiteral("target")).toMap();
    const QString changeId = normalizedUuid(change.value(QStringLiteral("changeId")).toString());
    const QString type = targetMap.value(QStringLiteral("type")).toString();
    const QString targetId = normalizedUuid(targetMap.value(QStringLiteral("id")).toString());
    const QString field = change.value(QStringLiteral("field")).toString();
    const QString authorId = normalizedUuid(change.value(QStringLiteral("authorId")).toString());
    const QVariant value = change.value(QStringLiteral("value"));
    if (changeId.isEmpty() || targetId.isEmpty() || !fieldAllowed(type, field)) return;
    if (type == QLatin1String("CALICATA") && targetId != m_rtCalicataId) return;
    if (value.isValid() && !value.isNull() && value.typeId() != QMetaType::QString) return;
    // Canonical self rule (same as Web): a change authored by this person is ours.
    auto *auth = appContext() ? appContext()->auth() : nullptr;
    if (auth && authorId == normalizedUuid(auth->userId())) return;
    // Local dedup only (not part of the payload contract).
    if (m_liveSeen.contains(changeId)) return;
    m_liveSeen.insert(changeId);
    m_liveSeenOrder << changeId;
    while (m_liveSeenOrder.size() > 512) m_liveSeen.remove(m_liveSeenOrder.takeFirst());
    qInfo().noquote() << "INGE_LIVE_FIELD_RX calicataId=" << m_rtCalicataId << "target=" << type << targetId
                      << "field=" << field;
    emit fieldChangeReceived(m_rtCalicataId, change);
}

// ===== InGeDrive: copia JSON versionada de la ficha =====
// El Smart Document (<código>.calicata, ensure_calicata_smart_document_v01) sigue
// siendo la representación canónica de la calicata en InGeDrive. Esta copia usa
// el contrato binario real del servidor (reserve → begin → Storage → finalize,
// document_versions) y las mutaciones reales de carpetas (inge_drive_mutate_v03).
// Identidad: drive_json_* en el header de la ficha (viaja también dentro del JSON),
// de modo que cada Guardar crea una versión del mismo nodo, nunca un duplicado.
namespace {
const QString kDriveJsonMime = QStringLiteral("application/json");

// Only transport bookkeeping is excluded; user data/resources stay in the hash.
QJsonValue driveContentIdentity(const QJsonValue &value)
{
    if (value.isArray()) {
        QJsonArray result;
        for (const QJsonValue &item : value.toArray()) result.append(driveContentIdentity(item));
        return result;
    }
    if (!value.isObject()) return value;
    QJsonObject result = value.toObject();
    const QStringList keys = result.keys();
    for (const QString &key : keys) {
        if (key.startsWith(QLatin1String("drive_json_"))
            || key == QLatin1String("saved_at_utc") || key == QLatin1String("updated_at")
            || key == QLatin1String("row_version") || key == QLatin1String("remoteRowVersion")
            || key == QLatin1String("sync_state") || key == QLatin1String("node_version")
            || key == QLatin1String("smart_document_result_code"))
            result.remove(key);
        else result[key] = driveContentIdentity(result.value(key));
    }
    return result;
}

QString driveRowKind(const QVariantMap &row)
{
    return row.value(QStringLiteral("item_kind"), row.value(QStringLiteral("node_kind"))).toString().toUpper();
}
} // namespace

void CalicataCloudService::listDriveChildren(const QString &spaceId, const QString &parentNodeId,
                                             std::function<void(bool, const QVariantList &, const QString &)> done)
{
    const QString parent = normalizedUuid(parentNodeId);
    postRpc(QStringLiteral("inge_drive_list_v02"),
            {{QStringLiteral("p_space_id"), spaceId},
             {QStringLiteral("p_parent_node_id"), parent.isEmpty() ? QVariant() : QVariant(parent)}},
            [done](bool ok, const QJsonDocument &document, const QString &code, const QString &message) {
        if (!ok) { done(false, {}, humanCloudError(code, message)); return; }
        done(true, rows(document), {});
    });
}

void CalicataCloudService::listDriveFolders(const QString &projectId, const QString &parentNodeId)
{
    const QString pid = normalizedUuid(projectId);
    if (pid.isEmpty()) {
        emit driveFoldersFailed(QStringLiteral("Selecciona un proyecto antes de guardar en InGeDrive."));
        return;
    }
    postRpc(QStringLiteral("get_my_project_workspace_v01"), {{QStringLiteral("p_project_id"), pid}},
            [this, pid, parentNodeId](bool ok, const QJsonDocument &document,
                                      const QString &code, const QString &message) {
        const QString spaceId = normalizedUuid(firstRow(document).value(QStringLiteral("space_id")).toString());
        if (!ok || spaceId.isEmpty()) {
            emit driveFoldersFailed(humanCloudError(code, ok
                ? QStringLiteral("El proyecto no tiene un espacio documental disponible.") : message));
            return;
        }
        listDriveChildren(spaceId, parentNodeId, [this, pid, parentNodeId, spaceId](
                              bool listed, const QVariantList &items, const QString &error) {
            if (!listed) { emit driveFoldersFailed(error); return; }
            QVariantList folders;
            for (const QVariant &value : items) {
                const QVariantMap row = value.toMap();
                if (driveRowKind(row) != QLatin1String("FOLDER")) continue;
                folders.append(QVariantMap{{QStringLiteral("id"), normalizedUuid(row.value(QStringLiteral("id")).toString())},
                                           {QStringLiteral("name"), trimmedText(row.value(QStringLiteral("name")))}});
            }
            emit driveFoldersListed(pid, normalizedUuid(parentNodeId), spaceId, folders);
        });
    });
}

QString CalicataCloudService::saveJsonToDrive(CalicataDocument *document, const QString &resourcesBase,
                                              const QString &targetFolderId)
{
    const QPointer<CalicataDocument> target(document);
    auto *auth = appContext() ? appContext()->auth() : nullptr;
    if (!target || target->closed()) return QStringLiteral("La ficha no está disponible.");
    if (!auth || !auth->logged()) return QStringLiteral("Inicia sesión para guardar en InGeDrive.");
    const QVariantMap header = target->header();
    const QString localId = target->instanceId();
    const QString projectId = normalizedUuid(header.value(QStringLiteral("projectId")).toString());
    const QString remoteId = normalizedUuid(header.value(QStringLiteral("remoteCalicataId"),
                                                         header.value(QStringLiteral("remote_calicata_id"))).toString());
    if (projectId.isEmpty() || remoteId.isEmpty())
        return QStringLiteral("Sincroniza primero la calicata con su proyecto.");
    const QString owner = normalizedUuid(auth->userId());
    const QString operationKey = owner + QLatin1Char('/') + projectId + QLatin1Char('/') + remoteId;
    if (m_driveJsonOperations.contains(operationKey))
        return QStringLiteral("La ficha ya se está guardando en InGeDrive.");

    const QVariantMap state = target->portableState(resourcesBase);
    if (state.isEmpty()) return target->errorString();
    const QJsonObject snapshot = QJsonObject::fromVariantMap(state);
    const QByteArray fingerprint = QJsonDocument(driveContentIdentity(snapshot).toObject()).toJson(QJsonDocument::Compact);
    const QString contentHash = QString::fromLatin1(QCryptographicHash::hash(fingerprint, QCryptographicHash::Sha256).toHex());
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
        + QStringLiteral("/inge-drive-json/") + owner;
    if (!QDir().mkpath(dir)) return QStringLiteral("No se pudo preparar el JSON local.");
    QString localFile = QDir(dir).filePath(remoteId + QLatin1Char('-') + contentHash + QStringLiteral(".json"));
    // Immutable snapshot per content identity. A retry reuses precisely the bytes
    // of its reservation, even if local timestamps/remote row_version changed.
    if (!QFileInfo::exists(localFile)) {
        const QByteArray bytes = QJsonDocument(snapshot).toJson(QJsonDocument::Indented);
        QSaveFile out(localFile);
        if (!out.open(QIODevice::WriteOnly) || out.write(bytes) != bytes.size() || !out.commit())
            return QStringLiteral("No se pudo conservar el JSON local.");
    }
    // Drain an interrupted immutable snapshot before reserving newer content.
    // Otherwise a later edit would strand its earlier pending server version.
    const QString pendingFile = QDir(dir).filePath(remoteId + QStringLiteral(".pending"));
    QString uploadHash = contentHash;
    QFile pending(pendingFile);
    if (pending.exists()) {
        if (!pending.open(QIODevice::ReadOnly))
            return QStringLiteral("No se pudo leer el guardado JSON pendiente.");
        uploadHash = QString::fromLatin1(pending.readAll()).trimmed();
        static const QRegularExpression hashPattern(QStringLiteral("^[0-9a-f]{64}$"));
        if (!hashPattern.match(uploadHash).hasMatch())
            return QStringLiteral("La identidad del JSON pendiente no es válida; el borrador se conserva.");
        localFile = QDir(dir).filePath(remoteId + QLatin1Char('-') + uploadHash + QStringLiteral(".json"));
        if (!QFileInfo::exists(localFile))
            return QStringLiteral("Falta la copia del JSON pendiente; el borrador se conserva.");
        pending.close();
    } else {
        QSaveFile journal(pendingFile);
        const QByteArray hashBytes = uploadHash.toLatin1();
        if (!journal.open(QIODevice::WriteOnly) || journal.write(hashBytes) != hashBytes.size() || !journal.commit())
            return QStringLiteral("No se pudo conservar la identidad del guardado JSON.");
    }
    const bool drainingPrevious = uploadHash != contentHash;
    const qint64 size = QFileInfo(localFile).size();
    const QString requestedFolder = normalizedUuid(targetFolderId);
    const QString requestId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    m_driveJsonOperations.insert(operationKey);
    const auto sameAccount = [owner]() {
        auto *a = appContext() ? appContext()->auth() : nullptr;
        return a && a->logged() && normalizedUuid(a->userId()) == owner;
    };
    const auto fail = [this, localId, operationKey](const QString &code, const QString &message) {
        m_driveJsonOperations.remove(operationKey);
        const QString error = humanCloudError(code, message);
        setLastError(error);
        emit driveJsonSaveFailed(localId, error);
    };
    // Server-owned binding replaces filename/local-header guessing. It reserves
    // once per calicata and returns the same attempt after a lost response.
    postRpc(QStringLiteral("reserve_my_calicata_json_v01"),
            {{QStringLiteral("p_project_id"), projectId}, {QStringLiteral("p_calicata_id"), remoteId},
             {QStringLiteral("p_parent_node_id"), requestedFolder.isEmpty() || drainingPrevious ? QVariant() : QVariant(requestedFolder)},
             {QStringLiteral("p_size_bytes"), size}, {QStringLiteral("p_content_hash"), uploadHash},
             {QStringLiteral("p_idempotency_key"), requestId}},
            [=](bool ok, const QJsonDocument &reservation, const QString &code, const QString &message) {
        if (!sameAccount()) { fail(QStringLiteral("AUTH_REQUIRED"), QStringLiteral("La sesión cambió; el borrador se conserva.")); return; }
        const QVariantMap slot = firstRow(reservation);
        const QString nodeId = normalizedUuid(slot.value(QStringLiteral("document_node_id")).toString());
        const QString attemptId = normalizedUuid(slot.value(QStringLiteral("attempt_id")).toString());
        const QString bucket = trimmedText(slot.value(QStringLiteral("bucket")));
        const QString path = trimmedText(slot.value(QStringLiteral("storage_path")));
        if (!ok || nodeId.isEmpty() || attemptId.isEmpty() || bucket.isEmpty() || path.isEmpty()) {
            fail(code, ok ? QStringLiteral("La reserva JSON no devolvió una identidad válida.") : message); return;
        }
        const auto complete = [=](const QVariantMap &row) {
            if (normalizedUuid(row.value(QStringLiteral("document_node_id")).toString()) != nodeId
                || row.value(QStringLiteral("attempt_status")).toString() != QLatin1String("FINALIZADO")) {
                fail({}, QStringLiteral("No se pudo confirmar la versión del JSON.")); return;
            }
            if (!QFile::remove(pendingFile)) {
                fail({}, QStringLiteral("El JSON está confirmado; no se pudo cerrar su registro local.")); return;
            }
            // La copia inmutable solo sirve para reintentar este intento; ya
            // confirmado en el servidor, no se acumula en el dispositivo.
            QFile::remove(localFile);
            if (drainingPrevious) {
                m_driveJsonOperations.remove(operationKey);
                const QString nextError = saveJsonToDrive(target, resourcesBase, targetFolderId);
                if (!nextError.isEmpty()) fail({}, nextError);
                return;
            }
            QVariantMap result;
            result[QStringLiteral("drive_json_node_id")] = nodeId;
            result[QStringLiteral("drive_json_version_id")] = row.value(QStringLiteral("document_version_id"));
            result[QStringLiteral("drive_json_version_number")] = row.value(QStringLiteral("version_number"));
            result[QStringLiteral("drive_json_node_version")] = row.value(QStringLiteral("node_version"));
            result[QStringLiteral("drive_json_content_version")] = row.value(QStringLiteral("content_version"));
            if (!requestedFolder.isEmpty()) result[QStringLiteral("drive_json_folder_id")] = requestedFolder;
            result[QStringLiteral("drive_json_name")] = slot.value(QStringLiteral("file_name"));
            result[QStringLiteral("drive_json_saved_at")] = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);
            result[QStringLiteral("drive_json_content_hash")] = contentHash;
            m_driveJsonOperations.remove(operationKey);
            setLastError({});
            emit driveJsonSaved(localId, result);
        };
        if (slot.value(QStringLiteral("attempt_status")).toString() == QLatin1String("FINALIZADO")) {
            complete(slot); return; // no begin/upload for an already confirmed snapshot
        }
        if (slot.value(QStringLiteral("size_bytes")).toLongLong() != size) {
            fail({}, QStringLiteral("El intento pendiente pertenece a otra copia local; conserva el borrador y reintenta desde el equipo original.")); return;
        }
        const auto finalize = [=]() {
            if (!sameAccount()) { fail(QStringLiteral("AUTH_REQUIRED"), QStringLiteral("La sesión cambió.")); return; }
            postRpc(QStringLiteral("finalize_binary_document_upload_v01"), {{QStringLiteral("p_attempt_id"), attemptId}},
                    [=](bool finalized, const QJsonDocument &done, const QString &fc, const QString &fm) {
                if (!sameAccount()) { fail(QStringLiteral("AUTH_REQUIRED"), QStringLiteral("La sesión cambió.")); return; }
                if (!finalized) { fail(fc, fm); return; }
                complete(firstRow(done));
            });
        };
        const QString attemptStatus = slot.value(QStringLiteral("attempt_status")).toString();
        if (attemptStatus == QLatin1String("OBJETO_CARGADO")) {
            finalize(); return;
        }
        const auto upload = [=]() {
            uploadStorageObject(path, localFile, kDriveJsonMime, [=](bool uploaded, const QString &error) {
                if (!uploaded) { fail(QStringLiteral("NETWORK"), error); return; }
                finalize();
            }, bucket);
        };
        // Intento reanudado que ya había comenzado (respuesta perdida tras begin):
        // se sube y finaliza el MISMO intento, sin un segundo begin.
        if (attemptStatus == QLatin1String("EN_CARGA")) {
            upload(); return;
        }
        postRpc(QStringLiteral("begin_binary_document_upload_v01"), {{QStringLiteral("p_attempt_id"), attemptId}},
                [=](bool begun, const QJsonDocument &, const QString &bc, const QString &bm) {
            if (!sameAccount()) { fail(QStringLiteral("AUTH_REQUIRED"), QStringLiteral("La sesión cambió.")); return; }
            if (!begun) { fail(bc, bm); return; }
            upload();
        });
    });
    return {};
}

// 04_PROYECTOS/<proyecto>/06_GABINETE como FIELD canónico, resuelto por el
// servidor en la misma operación (ensure_calicata_field_folder_v01: project_id →
// espacio real → crea/enlaza 06_GABINETE; idempotente). Nunca por nombre de proyecto.
void CalicataCloudService::ensureProjectGabinete(
    const QString &projectId,
    std::function<void(bool ok, const QString &spaceId, const QString &folderId, const QString &error)> done)
{
    const QString pid = normalizedUuid(projectId);
    if (pid.isEmpty()) {
        done(false, {}, {}, QStringLiteral("Selecciona un proyecto antes de guardar en InGeDrive."));
        return;
    }
    postRpc(QStringLiteral("ensure_calicata_field_folder_v01"), {{QStringLiteral("p_project_id"), pid}},
            [done](bool ok, const QJsonDocument &document, const QString &code, const QString &message) {
        const QVariantMap row = firstRow(document);
        const QString spaceId = normalizedUuid(row.value(QStringLiteral("space_id")).toString());
        const QString folderId = normalizedUuid(row.value(QStringLiteral("folder_id")).toString());
        if (!ok || spaceId.isEmpty() || folderId.isEmpty()) {
            done(false, spaceId, {}, humanCloudError(code, ok
                ? QStringLiteral("No se pudo preparar la carpeta 06_GABINETE del proyecto.") : message));
            return;
        }
        done(true, spaceId, folderId, {});
    });
}

void CalicataCloudService::openDriveJson(const QString &spaceId, const QString &nodeId, const QString &versionId)
{
    postRpc(QStringLiteral("get_binary_document_access_v01"),
            {{QStringLiteral("p_space_id"), normalizedUuid(spaceId)},
             {QStringLiteral("p_document_node_id"), normalizedUuid(nodeId)},
             {QStringLiteral("p_document_version_id"), normalizedUuid(versionId)}},
            [this, nodeId, versionId](bool ok, const QJsonDocument &document,
                                      const QString &code, const QString &message) {
        const QVariantMap access = firstRow(document);
        const QString bucket = trimmedText(access.value(QStringLiteral("bucket")));
        const QString storagePath = trimmedText(access.value(QStringLiteral("storage_path")));
        if (!ok || bucket.isEmpty() || storagePath.isEmpty()) {
            emit driveJsonDownloadFailed(humanCloudError(code, ok
                ? QStringLiteral("No hay una versión descargable del JSON.") : message));
            return;
        }
        auto *api = appContext() ? appContext()->supabase() : nullptr;
        if (!api) { emit driveJsonDownloadFailed(QStringLiteral("Supabase no está disponible.")); return; }
        QString base = api->restUrl(QString()).toString();
        base.replace(QStringLiteral("/rest/v1"), QStringLiteral("/storage/v1"));
        if (!base.endsWith(QLatin1Char('/'))) base += QLatin1Char('/');
        getJson(QUrl(base + QStringLiteral("object/authenticated/") + bucket + QLatin1Char('/') + storagePath),
                [this, nodeId, versionId](bool fetched, const QJsonDocument &json,
                                          const QString &fc, const QString &fm) {
            if (!fetched || !json.isObject()) {
                emit driveJsonDownloadFailed(humanCloudError(fc, fm.isEmpty()
                    ? QStringLiteral("El JSON descargado no es una ficha válida.") : fm));
                return;
            }
            const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
                                + QStringLiteral("/inge-drive-json/") + normalizedUuid(nodeId);
            if (!QDir().mkpath(dir)) { emit driveJsonDownloadFailed(QStringLiteral("No se pudo guardar la copia local.")); return; }
            const QString path = QDir(dir).filePath(normalizedUuid(versionId) + QStringLiteral(".calicata.json"));
            QSaveFile out(path);
            const QByteArray bytes = json.toJson(QJsonDocument::Indented);
            if (!out.open(QIODevice::WriteOnly) || out.write(bytes) != bytes.size() || !out.commit()) {
                emit driveJsonDownloadFailed(QStringLiteral("No se pudo guardar la copia local."));
                return;
            }
            emit driveJsonDownloaded(path);
        });
    });
}
