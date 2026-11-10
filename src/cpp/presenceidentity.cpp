#include "presenceidentity.h"

#include "appcontext.h"
#include "authsession.h"
#include "supabaseclient.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFileInfo>
#include <QImage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QSaveFile>
#include <QStandardPaths>
#include <QStringList>
#include <QUrl>
#include <QUrlQuery>

namespace PresenceIdentity {

QString colorFor(const QString &userId)
{
    // emerald, amber, rose, violet, sky, lime, fuchsia, orange (-400), como la Web.
    static const char *palette[] = { "#34D399", "#FBBF24", "#FB7185", "#A78BFA",
                                     "#38BDF8", "#A3E635", "#E879F9", "#FB923C" };
    quint32 hash = 0x811c9dc5u;
    for (const QChar ch : userId) {
        hash ^= ch.unicode();
        hash *= 0x01000193u;
    }
    return QString::fromLatin1(palette[hash % 8]);
}

QString initialsFor(const QString &name)
{
    const QStringList parts = name.split(QLatin1Char(' '), Qt::SkipEmptyParts);
    QString initials;
    for (int i = 0; i < parts.size() && initials.size() < 2; ++i) initials += parts.at(i).left(1).toUpper();
    return initials.isEmpty() ? QStringLiteral("?") : initials;
}

bool isAvatarRef(const QString &ref)
{
    static const QRegularExpression pattern(
        QStringLiteral("^storage://avatars/[0-9a-fA-F-]{36}/[A-Za-z0-9._/-]{1,160}$"));
    return pattern.match(ref).hasMatch() && !ref.contains(QStringLiteral(".."));
}

QString selfAvatarRef()
{
    auto *auth = appContext() ? appContext()->auth() : nullptr;
    const QString path = auth ? auth->avatarPath().trimmed() : QString();
    const QString ref = path.isEmpty() ? QString() : QStringLiteral("storage://avatars/") + path;
    return isAvatarRef(ref) ? ref : QString();
}

} // namespace PresenceIdentity

PresenceAvatarCache *PresenceAvatarCache::instance()
{
    static PresenceAvatarCache *cache = new PresenceAvatarCache();
    return cache;
}

PresenceAvatarCache::PresenceAvatarCache(QObject *parent) : QObject(parent) {}

QString PresenceAvatarCache::cachePath(const QString &ref) const
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
                        + QStringLiteral("/presence_avatars");
    const QByteArray key = QCryptographicHash::hash(ref.toUtf8(), QCryptographicHash::Sha1).toHex();
    return dir + QLatin1Char('/') + QString::fromLatin1(key) + QStringLiteral(".png");
}

QString PresenceAvatarCache::source(const QString &ref)
{
    if (!PresenceIdentity::isAvatarRef(ref)) return {};
    const QFileInfo cached(cachePath(ref));
    // La ruta del objeto es estable aunque cambie la foto: se renueva cada hora.
    const bool fresh = cached.exists() && cached.lastModified().secsTo(QDateTime::currentDateTime()) < 3600;
    if (!fresh && !m_pending.contains(ref)) {
        const QDateTime failed = m_failedAt.value(ref);
        if (!failed.isValid() || failed.secsTo(QDateTime::currentDateTimeUtc()) > 600) fetch(ref);
    }
    return cached.exists() ? QUrl::fromLocalFile(cached.absoluteFilePath()).toString() : QString();
}

void PresenceAvatarCache::fetch(const QString &ref)
{
    auto *ctx = appContext();
    auto *api = ctx ? ctx->supabase() : nullptr;
    auto *auth = ctx ? ctx->auth() : nullptr;
    if (!api || !auth || !auth->logged() || auth->accessToken().isEmpty()) return;
    const QString path = ref.mid(QStringLiteral("storage://avatars/").size());
    m_pending.insert(ref);
    auto fail = [this, ref]() {
        m_pending.remove(ref);
        m_failedAt.insert(ref, QDateTime::currentDateTimeUtc());
        qInfo().noquote() << "INGE_PRESENCE_AVATAR result=FALLBACK_INITIALS";
    };

    QUrl url(api->projectUrl());
    url.setPath(QStringLiteral("/storage/v1/object/sign/avatars/") + path);
    auto *sign = api->nam()->post(api->makeRequest(url, auth->accessToken()), QByteArrayLiteral("{\"expiresIn\":60}"));
    connect(sign, &QNetworkReply::finished, this, [this, sign, api, ref, path, fail]() {
        const QByteArray raw = sign->readAll();
        const int http = sign->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const bool ok = sign->error() == QNetworkReply::NoError && http >= 200 && http < 300;
        sign->deleteLater();
        const QString signedPath = QJsonDocument::fromJson(raw).object().value(QStringLiteral("signedURL")).toString();
        QUrl signedUrl;
        if (signedPath.startsWith(QStringLiteral("/object/sign/")))
            signedUrl = QUrl(api->projectUrl() + QStringLiteral("/storage/v1") + signedPath);
        else if (signedPath.startsWith(QStringLiteral("/storage/v1/object/sign/")))
            signedUrl = QUrl(api->projectUrl() + signedPath);
        const QUrl origin(api->projectUrl());
        if (!ok || signedUrl.host() != origin.host()
            || signedUrl.path() != QStringLiteral("/storage/v1/object/sign/avatars/") + path
            || QUrlQuery(signedUrl).queryItemValue(QStringLiteral("token")).isEmpty()) {
            fail();                                   // p. ej. RLS sin lectura de fotos ajenas
            return;
        }
        auto *download = api->nam()->get(api->makeRequest(signedUrl));
        connect(download, &QNetworkReply::finished, this, [this, download, ref, fail]() {
            const QByteArray bytes = download->readAll();
            const bool okBytes = download->error() == QNetworkReply::NoError && bytes.size() < 4 * 1024 * 1024;
            download->deleteLater();
            QImage image;
            if (!okBytes || !image.loadFromData(bytes)) { fail(); return; }
            const QImage small = image.scaled(128, 128, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
            const QString target = cachePath(ref);
            QDir().mkpath(QFileInfo(target).absolutePath());
            QSaveFile file(target);
            if (!file.open(QIODevice::WriteOnly) || !small.save(&file, "PNG") || !file.commit()) { fail(); return; }
            m_pending.remove(ref);
            m_failedAt.remove(ref);
            emit avatarReady(ref);
        });
    });
}
