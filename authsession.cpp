#include "authsession.h"
#ifdef INGE_MOBILE
#include "betadiagnostics.h"
#endif
#include "supabaseclient.h"

#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrlQuery>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QSettings>
#include <QSslError>
#include <QImageReader>
#include <QBuffer>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QDir>
#include <QDesktopServices>
#include <QImage>
#include <QRegularExpression>
#include <QVariantMap>
#include <QStringList>
#include <QTimer>
#include <QPointer>
#include <QThreadPool>
#include <algorithm>

#ifdef Q_OS_ANDROID
#include <QJniObject>
#include <QJniEnvironment>
#endif

static QString qurlToReadablePath(const QUrl& u) {
    if (!u.isValid()) return {};
    if (u.isLocalFile()) return u.toLocalFile();
    // Android puede dar content://... (Qt suele poder abrirlo vía QFile fileEngine)
    return u.toString();
}

static QByteArray readAndroidContentUriBytes(const QString& uriString)
{
#ifdef Q_OS_ANDROID
    QByteArray data;
    if (uriString.isEmpty())
        return data;

    QJniObject context;
    QJniObject activityThread = QJniObject::callStaticObjectMethod(
        "android/app/ActivityThread",
        "currentActivityThread",
        "()Landroid/app/ActivityThread;");

    if (activityThread.isValid()) {
        context = activityThread.callObjectMethod(
            "getApplication",
            "()Landroid/app/Application;");
    }

    if (!context.isValid()) {
        context = QJniObject::callStaticObjectMethod(
            "android/app/ActivityThread",
            "currentApplication",
            "()Landroid/app/Application;");
    }

    if (!context.isValid())
        return data;

    QJniObject resolver = context.callObjectMethod(
        "getContentResolver",
        "()Landroid/content/ContentResolver;");
    if (!resolver.isValid())
        return data;

    const QJniObject juriString = QJniObject::fromString(uriString);
    const QJniObject uri = QJniObject::callStaticObjectMethod(
        "android/net/Uri",
        "parse",
        "(Ljava/lang/String;)Landroid/net/Uri;",
        juriString.object<jstring>());
    if (!uri.isValid())
        return data;

    QJniObject input = resolver.callObjectMethod(
        "openInputStream",
        "(Landroid/net/Uri;)Ljava/io/InputStream;",
        uri.object<jobject>());
    if (!input.isValid())
        return data;

    QJniEnvironment env;
    jbyteArray buffer = env->NewByteArray(64 * 1024);
    constexpr qsizetype maxBytes = 32 * 1024 * 1024; // evita cargar fotos descontroladamente grandes

    while (data.size() < maxBytes) {
        const jint n = input.callMethod<jint>("read", "([B)I", buffer);
        if (env->ExceptionCheck()) {
            env->ExceptionClear();
            data.clear();
            break;
        }
        if (n <= 0)
            break;

        QByteArray chunk(n, Qt::Uninitialized);
        env->GetByteArrayRegion(buffer, 0, n, reinterpret_cast<jbyte*>(chunk.data()));
        data.append(chunk);
    }

    env->DeleteLocalRef(buffer);
    input.callMethod<void>("close", "()V");
    return data;
#else
    Q_UNUSED(uriString)
    return {};
#endif
}

// Avatar decode: centre square and at most 1024 px, applied by the reader
// itself. JPEG decodes at a reduced DCT scale instead of the full 12-50 MP
// frame (48-200 MB RGBA). The centre square is invariant under the EXIF
// rotation applied afterwards.
static QImage readAvatarImage(QImageReader& reader)
{
    reader.setAutoTransform(true);
    const QSize size = reader.size();
    if (size.isValid() && !size.isEmpty()) {
        const int side = qMin(size.width(), size.height());
        reader.setClipRect(QRect((size.width() - side) / 2,
                                 (size.height() - side) / 2, side, side));
        if (side > 1024)
            reader.setScaledSize(QSize(1024, 1024));
    }
    return reader.read();
}

static QImage readImageFromUrl(const QUrl& url)
{
    if (!url.isValid())
        return {};

    if (url.isLocalFile()) {
        QImageReader reader(url.toLocalFile());
        return readAvatarImage(reader);
    }

    const QString source = url.toString();
#ifdef Q_OS_ANDROID
    if (source.startsWith(QStringLiteral("content://"), Qt::CaseInsensitive)) {
        const QByteArray bytes = readAndroidContentUriBytes(source);
        if (bytes.isEmpty())
            return {};

        QBuffer buffer;
        buffer.setData(bytes);
        if (!buffer.open(QIODevice::ReadOnly))
            return {};

        QImageReader reader(&buffer);
        return readAvatarImage(reader);
    }
#endif

    // Recursos qrc y otras rutas soportadas directamente por Qt.
    QImageReader reader(source);
    return readAvatarImage(reader);
}

static QString guessMime(const QString& extLower)
{
    if (extLower == "png")  return "image/png";
    if (extLower == "jpg" || extLower == "jpeg") return "image/jpeg";
    if (extLower == "bmp")  return "image/bmp";
    return "application/octet-stream";
}

static QString safeAccountKey(QString value)
{
    value = value.trimmed();
    value.replace(QRegularExpression(QStringLiteral("[^A-Za-z0-9_-]+")), QStringLiteral("_"));
    if (value.isEmpty())
        value = QStringLiteral("unknown");
    return value;
}

static QString localAvatarDirectory(const QString& userId)
{
    const QString root = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    const QString dir = root + QStringLiteral("/avatars/") + safeAccountKey(userId);
    QDir().mkpath(dir);
    return dir;
}

static QString newLocalAvatarCachePath(const QString& userId)
{
    return localAvatarDirectory(userId)
        + QStringLiteral("/avatar_%1.png").arg(QDateTime::currentMSecsSinceEpoch());
}

static QString latestLocalAvatarCachePath(const QString& userId)
{
    QDir dir(localAvatarDirectory(userId));
    const QFileInfoList candidates = dir.entryInfoList(
        QStringList{QStringLiteral("avatar_*.png"), QStringLiteral("avatar.png")},
        QDir::Files | QDir::Readable,
        QDir::Time);
    return candidates.isEmpty() ? QString() : candidates.constFirst().absoluteFilePath();
}

static QImage squareAvatarImage(const QImage& original)
{
    if (original.isNull())
        return {};

    QImage image = original;
    const int side = qMin(image.width(), image.height());
    const int left = qMax(0, (image.width() - side) / 2);
    const int top = qMax(0, (image.height() - side) / 2);
    image = image.copy(left, top, side, side);

    // 1024 px conserva calidad suficiente y evita cargar fotos gigantes en QML.
    if (image.width() > 1024 || image.height() > 1024)
        image = image.scaled(1024, 1024, Qt::KeepAspectRatio, Qt::SmoothTransformation);

    return image.convertToFormat(QImage::Format_RGBA8888);
}

static QString cleanExt(QString ext)
{
    ext = ext.toLower().trimmed();
    if (ext.startsWith(".")) ext.remove(0, 1);
    if (ext.isEmpty()) ext = "png";
    return ext;
}

namespace {
static const char* kRememberEnabledKey   = "auth/remember_enabled";
static const char* kRememberUntilUtcKey  = "auth/remember_until_utc";
static const char* kCurrentAccountKey    = "auth/current_account_id";
static const char* kAccountIndexKey      = "auth/accounts_index";
static const char* kAccountsPrefix       = "auth/accounts/";
static const char* kDevOfflineActiveKey  = "auth/dev_offline_active";
static const char* kDevOfflineUntilKey   = "auth/dev_offline_until_utc";
static const char* kDevOfflineUserId     = "00000000-0000-0000-0000-000000000001";
}

static QUrl buildStorageObjectUrl(const QString& projectUrl, const QString& bucket, const QString& objectPath, bool upsert)
{
    // objectPath debe ser tipo: uid/avatar/avatar.png (solo chars seguros)
    QUrl u(projectUrl);
    u.setPath("/storage/v1/object/" + bucket + "/" + objectPath);

    if (upsert) {
        QUrlQuery q;
        q.addQueryItem("upsert", "true");
        u.setQuery(q);
    }
    return u;
}
AuthSession* AuthSession::s_instance = nullptr;

AuthSession* AuthSession::instance()
{
    return s_instance;
}


static QString parseSupabaseError(const QByteArray& body, const QString& fallback)
{
    const QString rawText = QString::fromUtf8(body);

    const auto doc = QJsonDocument::fromJson(body);
    if (doc.isObject()) {
        const auto o = doc.object();

        const QString msg = o.value("msg").toString();
        const QString code = o.value("error_code").toString();
        const QString err = o.value("error").toString();
        const QString desc = o.value("error_description").toString();
        const QString message = o.value("message").toString();
        const QString detail = o.value("detail").toString();

        if (code == "over_email_send_rate_limit")
            return "Se alcanzó el límite temporal de envío de correos de Supabase. Espera un momento o configura SMTP personalizado.";

        if (code == "unexpected_failure" &&
            msg.contains("Error sending confirmation email", Qt::CaseInsensitive))
            return "No se pudo enviar el correo de confirmación. Revisa la configuración SMTP en Supabase.";

        if (rawText.contains("users_email_partial_key", Qt::CaseInsensitive) ||
            rawText.contains("already exists", Qt::CaseInsensitive))
            return "Este correo ya está registrado. Revisa tu bandeja para confirmar la cuenta o inicia sesión.";

        if (!msg.isEmpty()) return msg;
        if (!message.isEmpty()) return message;
        if (!detail.isEmpty()) return detail;
        if (!err.isEmpty()) return err;
        if (!desc.isEmpty()) return desc;
    }

    return fallback;
}

struct AuthFailureDiagnostic
{
    QString code;
    QString message;
    QString result;
    QString userMessage;
};

static QString sanitizedAuthField(QString value, int maximumLength)
{
    value.replace(QRegularExpression(
        QStringLiteral("(?i)(authorization|apikey|access_token|refresh_token|password)\\s*[:=]\\s*[^\\s,;}]+")),
        QStringLiteral("\\1=<redacted>"));
    value.replace(QRegularExpression(
        QStringLiteral("[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}")),
        QStringLiteral("<redacted-jwt>"));
    value.replace(QRegularExpression(QStringLiteral("[\\r\\n\\t]+")), QStringLiteral(" "));
    return value.trimmed().left(maximumLength);
}

static AuthFailureDiagnostic classifyAuthFailure(const QByteArray& body,
                                                 int http,
                                                 QNetworkReply::NetworkError networkError)
{
    AuthFailureDiagnostic diagnostic;
    const QJsonDocument document = QJsonDocument::fromJson(body);
    if (document.isObject()) {
        const QJsonObject object = document.object();
        diagnostic.code = object.value(QStringLiteral("error_code")).toString();
        if (diagnostic.code.isEmpty())
            diagnostic.code = object.value(QStringLiteral("error")).toString();

        diagnostic.message = object.value(QStringLiteral("msg")).toString();
        if (diagnostic.message.isEmpty())
            diagnostic.message = object.value(QStringLiteral("message")).toString();
        if (diagnostic.message.isEmpty())
            diagnostic.message = object.value(QStringLiteral("error_description")).toString();
        if (diagnostic.message.isEmpty())
            diagnostic.message = object.value(QStringLiteral("detail")).toString();
    }

    diagnostic.code = sanitizedAuthField(diagnostic.code, 80);
    diagnostic.message = sanitizedAuthField(diagnostic.message, 240);

    const QString searchable = (diagnostic.code + QLatin1Char(' ') + diagnostic.message).toLower();
    const bool confirmedOffline =
        networkError == QNetworkReply::HostNotFoundError
        || networkError == QNetworkReply::NetworkSessionFailedError
        || networkError == QNetworkReply::TemporaryNetworkFailureError;
    if (http == 0 && confirmedOffline) {
        diagnostic.result = QStringLiteral("NETWORK_ERROR");
        diagnostic.userMessage = QStringLiteral("Sin conexión. Revisa tu red e inténtalo de nuevo.");
    } else if (http == 0) {
        // A timeout/cancellation is not evidence that Android is offline. On
        // validated but slow networks the previous branch produced a false
        // "Sin conexión" even though DNS and the HTTPS route were available.
        diagnostic.result = QStringLiteral("SERVICE_TIMEOUT");
        diagnostic.userMessage = QStringLiteral("El servicio tardó demasiado en responder. Inténtalo de nuevo.");
    } else if (searchable.contains(QStringLiteral("invalid_credentials"))
               || searchable.contains(QStringLiteral("invalid login credentials"))
               || searchable.contains(QStringLiteral("email_not_confirmed"))) {
        diagnostic.result = QStringLiteral("INVALID_CREDENTIALS");
        diagnostic.userMessage = searchable.contains(QStringLiteral("email_not_confirmed"))
            ? QStringLiteral("Confirma tu correo antes de iniciar sesión.")
            : QStringLiteral("Correo o contraseña incorrectos.");
    } else if (searchable.contains(QStringLiteral("api key"))
               || searchable.contains(QStringLiteral("apikey"))
               || searchable.contains(QStringLiteral("invalid_api_key"))
               || searchable.contains(QStringLiteral("project not found"))) {
        diagnostic.result = QStringLiteral("CONFIG_ERROR");
        diagnostic.userMessage = QStringLiteral("El servicio de inicio de sesión no está configurado correctamente.");
    } else if (http == 400 || http == 401) {
        diagnostic.result = QStringLiteral("MALFORMED_REQUEST");
        diagnostic.userMessage = QStringLiteral("No se pudo completar el inicio de sesión. Contacta a soporte.");
    } else if (networkError != QNetworkReply::NoError || http >= 500) {
        diagnostic.result = QStringLiteral("NETWORK_ERROR");
        diagnostic.userMessage = QStringLiteral("El servicio no está disponible temporalmente.");
    } else {
        diagnostic.result = QStringLiteral("CONFIG_ERROR");
        diagnostic.userMessage = QStringLiteral("No se pudo iniciar sesión por un problema de configuración.");
    }

    if (diagnostic.code.isEmpty())
        diagnostic.code = QStringLiteral("NONE");
    if (diagnostic.message.isEmpty())
        diagnostic.message = QStringLiteral("NONE");
    return diagnostic;
}

static bool signupNeedsEmailConfirmation(const QByteArray& body)
{
    const QString raw = QString::fromUtf8(body);
    return raw.contains(QStringLiteral("users_email_partial_key"), Qt::CaseInsensitive)
        || raw.contains(QStringLiteral("already registered"), Qt::CaseInsensitive)
        || raw.contains(QStringLiteral("already exists"), Qt::CaseInsensitive)
        || raw.contains(QStringLiteral("user_already_exists"), Qt::CaseInsensitive);
}

static QString sanitizeFolderName(QString s)
{
    s = s.trimmed();
    s.replace(QRegularExpression("\\s+"), "_");          // espacios -> _
    s.replace(QRegularExpression("[^A-Za-z0-9_]+"), "_"); // raros -> _
    s.replace(QRegularExpression("_+"), "_");            // __ -> _
    s = s.trimmed();
    if (s.startsWith('_')) s.remove(0, 1);
    if (s.endsWith('_')) s.chop(1);
    return s;
}

static bool looksLikeEmail(const QString& e)
{
    // Simple pero efectivo para UI
    const QString s = e.trimmed();
    return s.contains('@') && s.contains('.') && !s.contains(' ');
}

static QString passwordPolicyMessageCxx(const QString& pass)
{
    QStringList faltantes;
    if (pass.size() < 8) faltantes << "mínimo 8 caracteres";
    if (!pass.contains(QRegularExpression("\\p{Lu}"))) faltantes << "1 mayúscula";
    if (!pass.contains(QRegularExpression("\\p{Ll}"))) faltantes << "1 minúscula";
    if (!pass.contains(QRegularExpression("\\d")))     faltantes << "1 número";

    if (faltantes.isEmpty()) return {};
    return "La contraseña debe incluir: " + faltantes.join(", ") + ".";
}


AuthSession::AuthSession(SupabaseClient* api, QObject* parent)
    : QObject(parent)
    , m_api(api)   // ✅ CORRECTO
{
    s_instance = this;
}


void AuthSession::signInWithGoogle()
{
    signInWithOAuthProvider(QStringLiteral("google"));
}

void AuthSession::signInWithOAuthProvider(const QString& provider)
{
    if (!m_api) {
        emit loginFail(QStringLiteral("SupabaseClient no inicializado para OAuth."));
        return;
    }

    QUrl url = m_api->authUrl(QStringLiteral("authorize"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("provider"), provider.trimmed().toLower());
    q.addQueryItem(QStringLiteral("redirect_to"), QStringLiteral("com.ingema.ingeplus://login-callback"));
    url.setQuery(q);

    QDesktopServices::openUrl(url);
    emit oauthStarted(provider, url.toString());
}

void AuthSession::signInWithPassword(const QString& email, const QString& password)
{
    if (!m_api) { emit loginFail("SupabaseClient no inicializado."); return; }

    // El correo visible/persistido conserva exactamente lo escrito. La
    // validación usa una copia normalizada, pero nunca se reescribe el valor.
    const QString em = email;
    const QString pw = password;

    if (em.trimmed().isEmpty() || pw.isEmpty()) { emit loginFail("Ingresa usuario/email y contraseña."); return; }
    if (!looksLikeEmail(em))          { emit loginFail("Correo inválido."); return; }

    m_loginEmailExact = em;

    // Un toque mientras el POST sigue activo no crea otro intento remoto.
    if (m_loginReply) {
        qWarning().noquote() << "[Auth] LOGIN_REQUEST_IGNORED = IN_FLIGHT";
        return;
    }

    beginAuthOperation("password", /*cancelPasswordLogin=*/false);
    m_pendingSwitchAccountId.clear();
    const quint64 requestId = ++m_loginAttempt;
    startPasswordLoginRequest(em, pw, requestId, 1);
}

void AuthSession::startPasswordLoginRequest(const QString& email,
                                            const QString& password,
                                            quint64 requestId,
                                            int networkAttempt)
{
    if (!m_api || requestId != m_loginAttempt || m_loginReply)
        return;

    QUrl url = m_api->authUrl(QStringLiteral("token"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("grant_type"), QStringLiteral("password"));
    url.setQuery(q);

    QNetworkRequest req = m_api->makeRequest(
        url, QString(), /*transferTimeoutMs=*/30000);
    req.setRawHeader("Accept", "application/json");
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    // ✅ Si estás usando sb_publishable_..., NO lo mandes como JWT bearer.
    // Para publishable/anon key, usa el header apikey (makeRequest ya lo pone).
    // (Supabase explica diferencias y limitaciones de publishable keys) :contentReference[oaicite:0]{index=0}

    req.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);

    const QJsonObject body{{QStringLiteral("email"), email},
                           {QStringLiteral("password"), password}};

    qInfo().noquote()
        << QStringLiteral("[Auth] AUTH_NET_REQUEST_STARTED attempt=%1")
               .arg(networkAttempt);

    m_loginReply = m_api->nam()->post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    QNetworkReply* reply = m_loginReply.data();
    if (!reply) {
        m_loginReply = nullptr;
        qWarning().noquote() << "[Auth] AUTH_NET_ERROR_CODE=REQUEST_CREATION_FAILED";
        qWarning().noquote() << "[Auth] AUTH_NET_RETRY=NONE";
        qWarning().noquote() << "[Auth] LOGIN_RESULT=NETWORK_ERROR";
        emit loginFail(QStringLiteral("No se pudo crear la solicitud de red."));
        return;
    }

    connect(reply, &QNetworkReply::finished, this,
            [this, reply, email, password, requestId, networkAttempt]() {
        qInfo().noquote()
            << QStringLiteral("[Auth] AUTH_NET_REPLY_FINISHED attempt=%1")
                   .arg(networkAttempt);

        if (requestId != m_loginAttempt) {
            qInfo().noquote()
                << QStringLiteral("[Auth] AUTH_STALE_CALLBACK_IGNORED callback=passwordLogin callbackGen=%1 currentGen=%2")
                       .arg(requestId).arg(m_loginAttempt);
            reply->deleteLater();
            return;
        }

        const auto netErr = reply->error();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray raw = reply->isOpen() ? reply->readAll() : QByteArray();

        reply->deleteLater();
        if (m_loginReply == reply)
            m_loginReply = nullptr;

        const bool transferTimedOut = http == 0
            && (netErr == QNetworkReply::TimeoutError
                || netErr == QNetworkReply::OperationCanceledError);
        const bool transientNetworkError = transferTimedOut
            || netErr == QNetworkReply::TemporaryNetworkFailureError
            || netErr == QNetworkReply::RemoteHostClosedError;

        qInfo().noquote()
            << QStringLiteral("[Auth] AUTH_NET_HTTP_STATUS=%1").arg(http);
        qInfo().noquote()
            << QStringLiteral("[Auth] AUTH_NET_ERROR_CODE=%1")
                   .arg(static_cast<int>(netErr));
        qInfo().noquote()
            << QStringLiteral("[Auth] AUTH_NET_TIMEOUT_SOURCE=%1")
                   .arg(transferTimedOut
                            ? QStringLiteral("TRANSFER_TIMEOUT")
                            : QStringLiteral("NONE"));
        qInfo().noquote() << "[Auth] AUTH_NET_REPLY_ABORTED_BY_APP=NO";

        if (transientNetworkError && networkAttempt < 2) {
            qInfo().noquote() << "[Auth] AUTH_NET_RETRY=2";
            QTimer::singleShot(650, this,
                [this, email, password, requestId, networkAttempt]() {
                    if (requestId != m_loginAttempt || m_loginReply)
                        return;
                    startPasswordLoginRequest(email, password, requestId,
                                              networkAttempt + 1);
                });
            return;
        }

        qInfo().noquote() << "[Auth] AUTH_NET_RETRY=NONE";

        if (netErr != QNetworkReply::NoError || http < 200 || http >= 300) {
            const AuthFailureDiagnostic diagnostic = classifyAuthFailure(raw, http, netErr);
            qWarning().noquote()
                << QStringLiteral("[Auth] LOGIN_RESULT=%1")
                       .arg(diagnostic.result);
            emit loginFail(diagnostic.userMessage);
            return;
        }

        QJsonParseError pe{};
        const QJsonDocument doc = QJsonDocument::fromJson(raw, &pe);
        if (pe.error != QJsonParseError::NoError || !doc.isObject()) {
            qWarning().noquote() << "[Auth] LOGIN_RESULT=INVALID_RESPONSE";
            emit loginFail(QStringLiteral("Respuesta inválida de Supabase Auth."));
            return;
        }

        const QJsonObject o = doc.object();
        qInfo().noquote() << "[Auth] LOGIN_RESULT=SUCCESS";
        if (m_rememberFor30Days)
            m_rememberUntilUtc = QDateTime::currentDateTimeUtc().addDays(30);
        else
            m_rememberUntilUtc = QDateTime();

        finishAuthSuccess(o, /*emitLoginSignal=*/true);
    });
}





bool AuthSession::logged() const
{
    return m_devOffline
        || (!m_accessToken.isEmpty() && !m_userId.isEmpty() && profileActive());
}

void AuthSession::startDevOfflineSession(const QString& exactEmail, bool autoLogin)
{
    Q_UNUSED(exactEmail);
    clearDevOfflinePersistence();
    emit loginFail(QStringLiteral("El acceso de desarrollo ha sido retirado."));
    if (autoLogin) finishAutoLogin(false);
}

void AuthSession::clearDevOfflinePersistence() const
{
    QSettings settings;
    settings.remove(kDevOfflineActiveKey);
    settings.remove(kDevOfflineUntilKey);
    settings.sync();
}



void AuthSession::signUpWithEmail(const QString& email, const QString& password,
                                  const QString& nombre, const QString& apellido, const QString& phone)
{
    if (!m_api) {
        emit signUpFail("SupabaseClient no inicializado.");
        return;
    }

    const QString nom = nombre.trimmed();
    const QString ape = apellido.trimmed();
    // El correo se valida con una vista normalizada, pero se transmite y se
    // conserva exactamente como lo escribió la persona.
    const QString em  = email;
    const QString pho = phone.trimmed();
    const QString pw  = password;

    // ✅ Validación defensiva (en PC lo hacía MainWindow)
    if (nom.isEmpty() || ape.isEmpty() || em.isEmpty() || pho.isEmpty() || pw.isEmpty()) {
        emit signUpFail("Completa todos los campos.");
        return;
    }
    if (!looksLikeEmail(em)) {
        emit signUpFail("Correo inválido.");
        return;
    }

    const QString policy = passwordPolicyMessageCxx(pw);
    if (!policy.isEmpty()) {
        emit signUpFail(policy);
        return;
    }

    // POST /auth/v1/signup
    QUrl url = m_api->authUrl("signup");

    QNetworkRequest req = m_api->makeRequest(url);   // Content-Type + apikey
    req.setRawHeader("Accept", "application/json");

    // ✅ Compat: Authorization = Bearer <apikey> (igual al header "apikey")
    req.setRawHeader("Authorization", QByteArray("Bearer ") + m_api->anonKey().toUtf8());



    QJsonObject data{
        {"nombre", nombre},
        {"apellido", apellido},
        {"phone", phone},
        {"full_name", (nombre + " " + apellido).trimmed()},
        {"name", (nombre + " " + apellido).trimmed()}
    };

    QJsonObject body{
        {"email", em},
        {"password", pw},
        {"data", data}
    };

    auto* reply = m_api->nam()->post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));

    connect(reply, &QNetworkReply::finished, this, [this, reply, em]() {
        const QByteArray resp = reply->readAll();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto err = reply->error();
        const QString errStr = reply->errorString();

        qWarning() << "[Auth] signup finished"
                   << "http=" << http
                   << "err=" << err
                   << "errStr=" << errStr
                   << "body=" << QString::fromUtf8(resp);

        reply->deleteLater();

        if (err != QNetworkReply::NoError || http < 200 || http >= 300) {
            const QString msg = parseSupabaseError(
                resp,
                QString("Error al registrarse (HTTP %1): %2")
                    .arg(http)
                    .arg(err == QNetworkReply::NoError ? "HTTP error" : errStr)
                );

            // Si Supabase indica que el correo ya existe, puede tratarse de
            // un registro pendiente de confirmar. No mostramos un error rojo ni
            // bloqueamos al usuario: abrimos el flujo de código y dejamos que
            // pueda reenviar la confirmación o volver a iniciar sesión.
            if (signupNeedsEmailConfirmation(resp)) {
                emit signUpConfirmationRequired(em);
                return;
            }

            emit signUpFail(msg);
            return;
        }

        QJsonParseError pe{};
        const QJsonDocument doc = QJsonDocument::fromJson(resp, &pe);
        if (pe.error != QJsonParseError::NoError || !doc.isObject()) {
            emit signUpFail("Respuesta inválida de Supabase al crear la cuenta.");
            return;
        }

        const QJsonObject result = doc.object();
        const bool hasSession = !result.value(QStringLiteral("access_token")).toString().isEmpty()
                             && !result.value(QStringLiteral("user")).toObject()
                                      .value(QStringLiteral("id")).toString().isEmpty();

        if (hasSession) {
            // Proyectos sin confirmación obligatoria pueden devolver una sesión
            // inmediatamente. Conservamos ese comportamiento.
            if (m_rememberFor30Days)
                m_rememberUntilUtc = QDateTime::currentDateTimeUtc().addDays(30);
            finishAuthSuccess(result, /*emitLoginSignal=*/true);
            emit signUpOk();
            return;
        }

        // Con confirmación de correo activa, Supabase crea el usuario pero no
        // devuelve sesión hasta verificar el OTP/enlace.
        emit signUpConfirmationRequired(em);
    });
}
void AuthSession::verifySignupOtp(const QString& email, const QString& token)
{
    if (!m_api) {
        emit signupVerificationFail("SupabaseClient no inicializado.");
        return;
    }

    const QString em = email;
    QString otp = token.trimmed();
    otp.remove(QRegularExpression(QStringLiteral("\\s+")));

    if (!looksLikeEmail(em)) {
        emit signupVerificationFail("Correo inválido.");
        return;
    }
    if (otp.size() < 6) {
        emit signupVerificationFail("Ingresa el código completo enviado a tu correo.");
        return;
    }

    auto verifyAttempt = [this, em, otp](const QString& type, bool allowFallback) {
        QUrl url = m_api->authUrl(QStringLiteral("verify"));
        QNetworkRequest req = m_api->makeRequest(url);
        req.setRawHeader("Accept", "application/json");
        req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
        req.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
        req.setTransferTimeout(20000);
#endif

        QJsonObject body{
            {QStringLiteral("type"), type},
            {QStringLiteral("email"), em},
            {QStringLiteral("token"), otp}
        };

        auto* reply = m_api->nam()->post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
        connect(reply, &QNetworkReply::finished, this,
                [this, reply, em, otp, allowFallback]() {
            const QByteArray raw = reply->readAll();
            const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            const auto err = reply->error();
            const QString errStr = reply->errorString();
            reply->deleteLater();

            if (err != QNetworkReply::NoError || http < 200 || http >= 300) {
                // Compatibilidad con versiones/configuraciones de GoTrue que
                // todavía esperan type=signup en vez de type=email.
                if (allowFallback) {
                    QUrl retryUrl = m_api->authUrl(QStringLiteral("verify"));
                    QNetworkRequest retryReq = m_api->makeRequest(retryUrl);
                    retryReq.setRawHeader("Accept", "application/json");
                    retryReq.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
                    retryReq.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
                    retryReq.setTransferTimeout(20000);
#endif
                    QJsonObject retryBody{
                        {QStringLiteral("type"), QStringLiteral("signup")},
                        {QStringLiteral("email"), em},
                        {QStringLiteral("token"), otp}
                    };
                    auto* retry = m_api->nam()->post(
                        retryReq, QJsonDocument(retryBody).toJson(QJsonDocument::Compact));
                    connect(retry, &QNetworkReply::finished, this, [this, retry]() {
                        const QByteArray retryRaw = retry->readAll();
                        const int retryHttp = retry->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
                        const auto retryErr = retry->error();
                        const QString retryErrStr = retry->errorString();
                        retry->deleteLater();

                        if (retryErr != QNetworkReply::NoError || retryHttp < 200 || retryHttp >= 300) {
                            emit signupVerificationFail(parseSupabaseError(
                                retryRaw,
                                QString("No se pudo confirmar el código (HTTP %1): %2")
                                    .arg(retryHttp).arg(retryErrStr)));
                            return;
                        }

                        QJsonParseError pe{};
                        const QJsonDocument doc = QJsonDocument::fromJson(retryRaw, &pe);
                        if (pe.error != QJsonParseError::NoError || !doc.isObject()) {
                            emit signupVerificationFail("Respuesta inválida al confirmar la cuenta.");
                            return;
                        }

                        if (m_rememberFor30Days && !m_rememberUntilUtc.isValid())
                            m_rememberUntilUtc = QDateTime::currentDateTimeUtc().addDays(30);
                        finishAuthSuccess(doc.object(), /*emitLoginSignal=*/true);
                        emit signupVerificationOk();
                    });
                    return;
                }

                emit signupVerificationFail(parseSupabaseError(
                    raw,
                    QString("No se pudo confirmar el código (HTTP %1): %2").arg(http).arg(errStr)));
                return;
            }

            QJsonParseError pe{};
            const QJsonDocument doc = QJsonDocument::fromJson(raw, &pe);
            if (pe.error != QJsonParseError::NoError || !doc.isObject()) {
                emit signupVerificationFail("Respuesta inválida al confirmar la cuenta.");
                return;
            }

            if (m_rememberFor30Days && !m_rememberUntilUtc.isValid())
                m_rememberUntilUtc = QDateTime::currentDateTimeUtc().addDays(30);
            finishAuthSuccess(doc.object(), /*emitLoginSignal=*/true);
            emit signupVerificationOk();
        });
    };

    // Las plantillas modernas de Supabase verifican OTP de correo con type=email.
    verifyAttempt(QStringLiteral("email"), true);
}

QString AuthSession::accountGroup(const QString& accountId) const
{
    return QString::fromLatin1(kAccountsPrefix) + safeAccountKey(accountId);
}

QStringList AuthSession::savedAccountIds() const
{
    QSettings s;
    QStringList ids = s.value(kAccountIndexKey).toStringList();
    QStringList clean;
    for (const QString& id : ids) {
        const QString trimmed = id.trimmed();
        if (!trimmed.isEmpty() && !clean.contains(trimmed))
            clean.append(trimmed);
    }
    return clean;
}

QVariantList AuthSession::savedAccounts() const
{
    QSettings s;
    QVariantList result;
    const QStringList ids = savedAccountIds();

    for (const QString& id : ids) {
        const QString group = accountGroup(id);
        const QDateTime until = QDateTime::fromString(
            s.value(group + QStringLiteral("/remember_until_utc")).toString(),
            Qt::ISODate);

        // Las cuentas expiradas no se ofrecen como acceso rápido.
        if (!until.isValid() || QDateTime::currentDateTimeUtc() > until.toUTC())
            continue;

        QVariantMap item;
        item.insert(QStringLiteral("id"), id);
        item.insert(QStringLiteral("email"), s.value(group + QStringLiteral("/email")).toString());
        item.insert(QStringLiteral("name"), s.value(group + QStringLiteral("/nombre")).toString());
        item.insert(QStringLiteral("lastName"), s.value(group + QStringLiteral("/apellido")).toString());
        item.insert(QStringLiteral("avatarUrl"), s.value(group + QStringLiteral("/avatar_url_local")).toString());
        item.insert(QStringLiteral("avatarPath"), s.value(group + QStringLiteral("/avatar_path")).toString());
        item.insert(QStringLiteral("isCurrent"), id == m_currentAccountId && logged());
        item.insert(QStringLiteral("rememberUntil"), until.toString(Qt::ISODate));
        item.insert(QStringLiteral("lastUsed"), s.value(group + QStringLiteral("/last_used_utc")).toString());
        result.append(item);
    }

    // Si la sesión actual no fue marcada para recordar, igual debe aparecer
    // mientras la aplicación está abierta para que el panel no quede vacío.
    if (logged() && !m_userId.isEmpty() && !ids.contains(m_userId)) {
        QVariantMap current;
        current.insert(QStringLiteral("id"), m_userId);
        current.insert(QStringLiteral("email"), m_email);
        current.insert(QStringLiteral("name"), m_nombre);
        current.insert(QStringLiteral("lastName"), m_apellido);
        current.insert(QStringLiteral("avatarUrl"), m_avatarUrl);
        current.insert(QStringLiteral("avatarPath"), m_avatarPath);
        current.insert(QStringLiteral("isCurrent"), true);
        current.insert(QStringLiteral("transient"), true);
        result.prepend(current);
    }

    std::sort(result.begin(), result.end(), [](const QVariant& left, const QVariant& right) {
        const QVariantMap a = left.toMap();
        const QVariantMap b = right.toMap();

        const bool currentA = a.value(QStringLiteral("isCurrent")).toBool();
        const bool currentB = b.value(QStringLiteral("isCurrent")).toBool();
        if (currentA != currentB)
            return currentA;

        const QDateTime lastA = QDateTime::fromString(
            a.value(QStringLiteral("lastUsed")).toString(), Qt::ISODate);
        const QDateTime lastB = QDateTime::fromString(
            b.value(QStringLiteral("lastUsed")).toString(), Qt::ISODate);
        return lastA > lastB;
    });

    return result;
}

bool AuthSession::hasSavedAccount(const QString& accountId) const
{
    return savedAccountIds().contains(accountId.trimmed());
}

bool AuthSession::hasRestorableSession() const
{
    QSettings s;
    const QString currentId = s.value(kCurrentAccountKey).toString().trimmed();
    if (currentId.isEmpty()) {
        // Sesión heredada aún no migrada (misma condición que migrateLegacySessionIfNeeded).
        const QDateTime legacyUntil = QDateTime::fromString(
            s.value(kRememberUntilUtcKey).toString(), Qt::ISODate);
        return s.value(kRememberEnabledKey, false).toBool()
            && !s.value("auth/user_id").toString().isEmpty()
            && !s.value("auth/refresh_token").toString().isEmpty()
            && legacyUntil.isValid()
            && QDateTime::currentDateTimeUtc() <= legacyUntil.toUTC();
    }

    const QString group = accountGroup(currentId);
    const QDateTime until = QDateTime::fromString(
        s.value(group + QStringLiteral("/remember_until_utc")).toString(), Qt::ISODate);
    return until.isValid()
        && QDateTime::currentDateTimeUtc() <= until.toUTC()
        && !s.value(group + QStringLiteral("/refresh_token")).toString().isEmpty()
        && !s.value(group + QStringLiteral("/user_id")).toString().isEmpty();
}

quint64 AuthSession::beginAuthOperation(const char* kind, bool cancelPasswordLogin)
{
    const quint64 generation = ++m_authGeneration;
    if (cancelPasswordLogin) {
        // Una respuesta de login por contraseña aún en vuelo queda huérfana:
        // su requestId deja de coincidir y el callback se descarta.
        ++m_loginAttempt;
        m_loginReply = nullptr;
    }
    qInfo().noquote() << QStringLiteral("[Auth] AUTH_OP_BEGIN kind=%1 gen=%2")
                             .arg(QString::fromLatin1(kind)).arg(generation);
    return generation;
}

bool AuthSession::authOperationCurrent(quint64 generation, const char* callback) const
{
    if (generation == m_authGeneration)
        return true;
    qInfo().noquote()
        << QStringLiteral("[Auth] AUTH_STALE_CALLBACK_IGNORED callback=%1 callbackGen=%2 currentGen=%3")
               .arg(QString::fromLatin1(callback)).arg(generation).arg(m_authGeneration);
    return false;
}

void AuthSession::setCurrentAccountId(const QString& accountId)
{
    const QString normalized = accountId.trimmed();
    if (m_currentAccountId == normalized)
        return;

    m_currentAccountId = normalized;
    QSettings s;
    if (normalized.isEmpty())
        s.remove(kCurrentAccountKey);
    else
        s.setValue(kCurrentAccountKey, normalized);
    s.sync();
    emit currentAccountChanged();
    emit savedAccountsChanged();
}

void AuthSession::writeSavedAccount(const QString& accountId)
{
    const QString id = accountId.trimmed();
    if (id.isEmpty() || m_refreshToken.isEmpty())
        return;

    QSettings s;
    QStringList ids = savedAccountIds();
    if (!ids.contains(id))
        ids.append(id);
    s.setValue(kAccountIndexKey, ids);

    const QString group = accountGroup(id);
    s.setValue(group + QStringLiteral("/access_token"), m_accessToken);
    s.setValue(group + QStringLiteral("/refresh_token"), m_refreshToken);
    s.setValue(group + QStringLiteral("/user_id"), id);
    s.setValue(group + QStringLiteral("/expires_at_utc"), m_expiresAtUtc.toString(Qt::ISODate));
    s.setValue(group + QStringLiteral("/remember_until_utc"), m_rememberUntilUtc.toString(Qt::ISODate));
    s.setValue(group + QStringLiteral("/email"), m_email);
    s.setValue(group + QStringLiteral("/nombre"), m_nombre);
    s.setValue(group + QStringLiteral("/apellido"), m_apellido);
    s.setValue(group + QStringLiteral("/phone"), m_phone);
    s.setValue(group + QStringLiteral("/avatar_url_local"), m_avatarLocalFile);
    s.setValue(group + QStringLiteral("/avatar_path"), m_avatarPath);
    s.setValue(group + QStringLiteral("/profile_status"), m_profileStatus);
    s.setValue(group + QStringLiteral("/full_name"), m_fullName);
    s.setValue(group + QStringLiteral("/last_used_utc"), QDateTime::currentDateTimeUtc().toString(Qt::ISODate));
    s.sync();

    emit savedAccountsChanged();
}

bool AuthSession::loadSavedAccount(const QString& accountId)
{
    const QString id = accountId.trimmed();
    if (id.isEmpty())
        return false;

    QSettings s;
    const QString group = accountGroup(id);
    const QDateTime until = QDateTime::fromString(
        s.value(group + QStringLiteral("/remember_until_utc")).toString(),
        Qt::ISODate);

    if (!until.isValid() || QDateTime::currentDateTimeUtc() > until.toUTC()) {
        removeSavedAccountInternal(id, true);
        return false;
    }

    const QString refresh = s.value(group + QStringLiteral("/refresh_token")).toString();
    const QString uid = s.value(group + QStringLiteral("/user_id")).toString();
    if (refresh.isEmpty() || uid.isEmpty()) {
        removeSavedAccountInternal(id, true);
        return false;
    }

    clearSessionMemory();
    m_accessToken = s.value(group + QStringLiteral("/access_token")).toString();
    m_refreshToken = refresh;
    m_userId = uid;
    m_expiresAtUtc = QDateTime::fromString(
        s.value(group + QStringLiteral("/expires_at_utc")).toString(), Qt::ISODate);
    m_rememberUntilUtc = until;
    m_rememberFor30Days = true;
    m_email = s.value(group + QStringLiteral("/email")).toString();
    m_nombre = s.value(group + QStringLiteral("/nombre")).toString();
    m_apellido = s.value(group + QStringLiteral("/apellido")).toString();
    m_phone = s.value(group + QStringLiteral("/phone")).toString();
    m_avatarLocalFile = s.value(group + QStringLiteral("/avatar_url_local")).toString();
    m_avatarPath = s.value(group + QStringLiteral("/avatar_path")).toString();
    m_profileStatus = s.value(group + QStringLiteral("/profile_status")).toString();
    m_fullName = s.value(group + QStringLiteral("/full_name")).toString();
    m_profileReady = m_profileStatus == QStringLiteral("ACTIVO")
        && m_expiresAtUtc.isValid() && QDateTime::currentDateTimeUtc() < m_expiresAtUtc.addSecs(-60);


    const QString localPath = QUrl(m_avatarLocalFile).toLocalFile();
    m_avatarUrl = (!localPath.isEmpty() && QFile::exists(localPath)) ? m_avatarLocalFile : QString();

    setCurrentAccountId(id);
    emit rememberFor30DaysChanged();
    emit userInfoChanged();
    emit loggedChanged();
    return true;
}

void AuthSession::removeSavedAccountInternal(const QString& accountId, bool notify)
{
    const QString id = accountId.trimmed();
    if (id.isEmpty())
        return;

    QSettings s;
    QStringList ids = savedAccountIds();
    ids.removeAll(id);
    s.setValue(kAccountIndexKey, ids);
    s.remove(accountGroup(id));

    if (s.value(kCurrentAccountKey).toString() == id)
        s.remove(kCurrentAccountKey);
    s.sync();

    if (m_currentAccountId == id)
        m_currentAccountId.clear();

    if (notify) {
        emit currentAccountChanged();
        emit savedAccountsChanged();
    }
}

void AuthSession::removeSavedAccount(const QString& accountId)
{
    const QString id = accountId.trimmed();
    const bool wasActive = logged() && m_userId == id;
    if (id == QString::fromLatin1(kDevOfflineUserId))
        clearDevOfflinePersistence();
    removeSavedAccountInternal(id, true);
    qInfo().noquote() << QStringLiteral("[Auth] ACCOUNT_REMEMBERED_REMOVE uid8=%1 active=%2")
                             .arg(id.left(8), wasActive ? QStringLiteral("YES") : QStringLiteral("NO"));

    if (wasActive) {
        // "Recordar esta cuenta" y la sesión viva son conceptos distintos:
        // olvidar la cuenta activa deja de persistirla, pero no cierra la
        // sesión en curso por sorpresa.
        m_rememberFor30Days = false;
        m_rememberUntilUtc = QDateTime();
        clearLegacyActiveSession();
        emit rememberFor30DaysChanged();
        emit savedAccountsChanged();
    }
}

void AuthSession::clearSavedAccounts()
{
    clearDevOfflinePersistence();

    QSettings s;
    const QStringList ids = savedAccountIds();
    for (const QString& id : ids)
        s.remove(accountGroup(id));
    s.remove(kAccountIndexKey);
    s.remove(kCurrentAccountKey);
    s.sync();

    m_currentAccountId.clear();
    emit currentAccountChanged();
    emit savedAccountsChanged();
}

void AuthSession::clearLegacyActiveSession() const
{
    QSettings s;
    s.remove("auth/access_token");
    s.remove("auth/refresh_token");
    s.remove("auth/user_id");
    s.remove("auth/expires_at_utc");
    s.remove("auth/email");
    s.remove("auth/nombre");
    s.remove("auth/apellido");
    s.remove("auth/phone");
    s.remove("auth/avatar_url_local");
    s.remove("auth/avatar_path");
    s.remove(kRememberEnabledKey);
    s.remove(kRememberUntilUtcKey);
    s.sync();
}

void AuthSession::migrateLegacySessionIfNeeded()
{
    QSettings s;
    if (!savedAccountIds().isEmpty())
        return;

    const bool remember = s.value(kRememberEnabledKey, false).toBool();
    const QString uid = s.value("auth/user_id").toString();
    const QString refresh = s.value("auth/refresh_token").toString();
    const QDateTime until = QDateTime::fromString(
        s.value(kRememberUntilUtcKey).toString(), Qt::ISODate);

    if (!remember || uid.isEmpty() || refresh.isEmpty() || !until.isValid()
        || QDateTime::currentDateTimeUtc() > until.toUTC())
        return;

    m_rememberFor30Days = true;
    m_rememberUntilUtc = until;
    m_accessToken = s.value("auth/access_token").toString();
    m_refreshToken = refresh;
    m_userId = uid;
    m_expiresAtUtc = QDateTime::fromString(s.value("auth/expires_at_utc").toString(), Qt::ISODate);
    m_email = s.value("auth/email").toString();
    m_nombre = s.value("auth/nombre").toString();
    m_apellido = s.value("auth/apellido").toString();
    m_phone = s.value("auth/phone").toString();
    m_avatarLocalFile = s.value("auth/avatar_url_local").toString();
    m_avatarPath = s.value("auth/avatar_path").toString();
    m_avatarUrl = m_avatarLocalFile;

    writeSavedAccount(uid);
    setCurrentAccountId(uid);
}

void AuthSession::signOut()
{
    // Diagnósticos beta: el flush/finish toma una copia efímera del token
    // antes de que esta sesión lo elimine. Nunca persiste ni registra tokens.
#ifdef INGE_MOBILE
    if (BetaDiagnostics::instance())
        BetaDiagnostics::instance()->finishSession(QStringLiteral("LOGOUT"));
#endif

    // Revoca en Supabase la sesión activa. Se usa scope=local para no cerrar
    // las demás cuentas recordadas del dispositivo.
    if (m_api && !m_accessToken.isEmpty()) {
        QUrl url = m_api->authUrl(QStringLiteral("logout"));
        QUrlQuery query;
        query.addQueryItem(QStringLiteral("scope"), QStringLiteral("local"));
        url.setQuery(query);
        QNetworkRequest request = m_api->makeRequest(url, m_accessToken);
        auto *reply = m_api->nam()->post(request, QByteArrayLiteral("{}"));
        connect(reply, &QNetworkReply::finished, this, [reply]() {
            const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            if (reply->error() != QNetworkReply::NoError || http < 200 || http >= 300)
                qWarning() << "[Auth] Supabase logout no confirmado" << "http=" << http;
            reply->deleteLater();
        });
    }

    // Invalida cualquier login, restauración o cambio de cuenta en vuelo: su
    // respuesta tardía no puede volver a abrir la sesión que se está cerrando.
    beginAuthOperation("logout", /*cancelPasswordLogin=*/true);
    m_pendingSwitchAccountId.clear();
    setAutoLoginInProgress(false);

    // Cierra la sesión activa, pero conserva las cuentas que el usuario marcó
    // como recordadas. Se pueden eliminar desde "Gestionar cuentas".
    clearDevOfflinePersistence();
    clearSessionMemory();
    m_rememberFor30Days = false;
    m_rememberUntilUtc = QDateTime();
    clearLegacyActiveSession();
    setCurrentAccountId(QString());

    emit rememberFor30DaysChanged();
    emit userInfoChanged();
    emit loggedChanged();
    emit loggedOut();
}

void AuthSession::saveToDisk()
{
    QSettings s;

    s.setValue(kRememberEnabledKey, m_rememberFor30Days);
    if (m_rememberFor30Days && m_rememberUntilUtc.isValid())
        s.setValue(kRememberUntilUtcKey, m_rememberUntilUtc.toString(Qt::ISODate));
    else
        s.remove(kRememberUntilUtcKey);

    if (!m_rememberFor30Days || m_userId.isEmpty()) {
        clearLegacyActiveSession();
        if (!m_userId.isEmpty() && m_currentAccountId == m_userId)
            setCurrentAccountId(QString());
        return;
    }

    // Mantener las claves antiguas permite migrar instalaciones previas y no
    // rompe herramientas del proyecto que todavía leen auth/*.
    s.setValue("auth/access_token", m_accessToken);
    s.setValue("auth/refresh_token", m_refreshToken);
    s.setValue("auth/user_id", m_userId);
    s.setValue("auth/expires_at_utc", m_expiresAtUtc.toString(Qt::ISODate));
    s.setValue("auth/email", m_email);
    s.setValue("auth/nombre", m_nombre);
    s.setValue("auth/apellido", m_apellido);
    s.setValue("auth/phone", m_phone);
    s.setValue("auth/avatar_url_local", m_avatarLocalFile);
    s.setValue("auth/avatar_path", m_avatarPath);
    s.sync();

    writeSavedAccount(m_userId);
    setCurrentAccountId(m_userId);
}

void AuthSession::loadFromDisk()
{
    migrateLegacySessionIfNeeded();

    QSettings s;
    const QString currentId = s.value(kCurrentAccountKey).toString().trimmed();
    if (currentId.isEmpty() || !loadSavedAccount(currentId)) {
        clearSessionMemory();
        m_rememberFor30Days = false;
        m_rememberUntilUtc = QDateTime();
        m_currentAccountId.clear();
        emit rememberFor30DaysChanged();
        emit userInfoChanged();
        emit loggedChanged();
        emit currentAccountChanged();
        emit savedAccountsChanged();
    }
}

void AuthSession::setUserFromJson(const QJsonObject& user)
{
    if (user.isEmpty()) return;

    const QString uid = user.value("id").toString();
    if (!uid.isEmpty()) m_userId = uid;

    const QString em = user.value("email").toString();
    if (!em.isEmpty()) m_email = em;

    QJsonObject meta = user.value("user_metadata").toObject();
    if (meta.isEmpty())
        meta = user.value("raw_user_meta_data").toObject();

    const QString nom = meta.value("nombre").toString();
    const QString ape = meta.value("apellido").toString();
    const QString pho = meta.value("phone").toString();

    if (!nom.isEmpty()) m_nombre = nom;
    if (!ape.isEmpty()) m_apellido = ape;
    if (!pho.isEmpty()) m_phone = pho;

    const QString apath = meta.value("avatar_path").toString().trimmed();
    if (!apath.isEmpty()) m_avatarPath = apath;

    // ✅ Prioriza cache local si existe
    const QString local = m_avatarLocalFile;
    const QString localPath = QUrl(local).toLocalFile();
    if (!local.isEmpty() && !localPath.isEmpty() && QFile::exists(localPath)) {
        m_avatarUrl = local;          // file://...
    } else {
        m_avatarUrl.clear();          // fuerza default en QML
    }

    emit userInfoChanged();
}


void AuthSession::updateUserProfile(const QString& nombre,
                                    const QString& apellido,
                                    const QString& phone)
{
    if (!m_api) { emit profileUpdatedFail("SupabaseClient no inicializado."); return; }
    if (m_accessToken.isEmpty()) { emit profileUpdatedFail("No hay sesión activa."); return; }

    const QString nom = nombre.trimmed();
    const QString ape = apellido.trimmed();
    const QString pho = phone.trimmed();

    QUrl url = m_api->authUrl("user"); // /auth/v1/user

    QNetworkRequest req = m_api->makeRequest(url);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    // Bearer access_token (no anonKey)
    req.setRawHeader("Authorization", QByteArray("Bearer ") + m_accessToken.toUtf8());

    // apikey por compatibilidad
    req.setRawHeader("apikey", m_api->anonKey().toUtf8());

    QJsonObject data{
        {"nombre", nom},
        {"apellido", ape},
        {"phone", pho},
        {"full_name", (nom + " " + ape).trimmed()},
        {"name", (nom + " " + ape).trimmed()}
    };

    QJsonObject body{
        {"data", data}
    };

    auto* reply = m_api->nam()->put(req, QJsonDocument(body).toJson(QJsonDocument::Compact));

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray raw = reply->readAll();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto err = reply->error();
        reply->deleteLater();

        if (err != QNetworkReply::NoError || http < 200 || http >= 300) {
            emit profileUpdatedFail(parseSupabaseError(
                raw, QString("Error actualizando perfil (HTTP %1): %2")
                    .arg(http)
                    .arg(err == QNetworkReply::NoError ? "HTTP error" : reply->errorString())
                ));
            return;
        }

        QJsonParseError pe{};
        QJsonDocument doc = QJsonDocument::fromJson(raw, &pe);
        if (pe.error != QJsonParseError::NoError || !doc.isObject()) {
            emit profileUpdatedFail("Respuesta inválida actualizando perfil.");
            return;
        }

        setUserFromJson(doc.object());
        saveToDisk();
        emit userInfoChanged();
        emit profileUpdatedOk();
    });
}


QString AuthSession::localUserFolderName() const
{
    // Preferimos nombre/apellido (más “bonito” que email)
    QString base = (m_nombre + " " + m_apellido).trimmed();
    if (base.isEmpty())
        base = m_email; // fallback mobile: email

    base = sanitizeFolderName(base);
    if (base.isEmpty())
        base = "Usuario";

    QString shortId = m_userId;
    if (shortId.isEmpty())
        shortId = "nouid";
    else
        shortId = shortId.left(8);

    return base + "_" + shortId;
}




QString AuthSession::guessAvatarPath() const
{
    if (!m_avatarPath.isEmpty())
        return m_avatarPath;

    // fallback: intenta extraer desde URL pública
    const QString u = m_avatarUrl;
    const QString marker = "/storage/v1/object/public/avatars/";
    const int idx = u.indexOf(marker);
    if (idx >= 0) {
        QString tail = u.mid(idx + marker.length());
        // quitar query si hubiera
        const int q = tail.indexOf('?');
        if (q >= 0) tail = tail.left(q);
        return QUrl::fromPercentEncoding(tail.toUtf8());
    }
    return {};
}

void AuthSession::updateUserAvatar(const QUrl& fileUrl)
{
    if (!m_api) { emit profileUpdatedFail("SupabaseClient no inicializado."); return; }
    if (m_accessToken.isEmpty() || m_userId.isEmpty()) { emit profileUpdatedFail("No hay sesión activa."); return; }
    if (m_avatarJobRunning) {
        emit profileUpdatedFail("Ya se está procesando una foto de perfil.");
        return;
    }

    // Decode, crop, scale and PNG-encode off the GUI thread: on a 2-4 GB phone
    // this used to block Qt for seconds. content:// is read through JNI, and
    // QJniEnvironment attaches the pool thread. Local save, upload and signals
    // stay on the GUI thread (finishAvatarUpdate).
    m_avatarJobRunning = true;
    const QString userId = m_userId;
    QPointer<AuthSession> guard(this);
    QThreadPool::globalInstance()->start([guard, fileUrl, userId]() {
        const QImage avatarImage = squareAvatarImage(readImageFromUrl(fileUrl));
        QByteArray bytes;
        QString error;
        if (avatarImage.isNull()) {
            error = QStringLiteral("No se pudo leer la imagen seleccionada. Elige una foto JPG o PNG e inténtalo otra vez.");
        } else {
            QBuffer buffer(&bytes);
            if (!buffer.open(QIODevice::WriteOnly) || !avatarImage.save(&buffer, "PNG"))
                error = QStringLiteral("No se pudo preparar la imagen de perfil.");
            buffer.close();
        }
        if (!guard)
            return;
        QMetaObject::invokeMethod(guard.data(), [guard, userId, bytes, error]() {
            if (guard)
                guard->finishAvatarUpdate(userId, bytes, error);
        }, Qt::QueuedConnection);
    });
}

void AuthSession::finishAvatarUpdate(const QString& userId, const QByteArray& bytes,
                                     const QString& error)
{
    m_avatarJobRunning = false;
    // The account changed while the photo was processed: never write it into
    // another account's profile.
    if (userId != m_userId || m_accessToken.isEmpty()) {
        qInfo() << "INGE_AVATAR_DISCARDED reason=account_changed";
        return;
    }
    if (!error.isEmpty()) {
        emit profileUpdatedFail(error);
        return;
    }

    // Primero guardamos la copia local. Así el avatar cambia de inmediato incluso
    // si Storage está lento, sin políticas RLS o temporalmente sin conexión.
    const QString previousLocalPath = QUrl(m_avatarLocalFile).toLocalFile();
    const QString cachePath = newLocalAvatarCachePath(m_userId);
    QFile out(cachePath);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)
        || out.write(bytes) != bytes.size()) {
        emit profileUpdatedFail("No se pudo guardar el avatar en el almacenamiento interno.");
        return;
    }
    out.close();

    // Un nombre distinto en cada actualización evita que el caché de QML
    // conserve la foto anterior aunque el archivo haya cambiado.
    if (!previousLocalPath.isEmpty() && previousLocalPath != cachePath)
        QFile::remove(previousLocalPath);

    m_avatarLocalFile = QUrl::fromLocalFile(cachePath).toString();
    m_avatarUrl = m_avatarLocalFile;
    saveToDisk();
    emit userInfoChanged();
    emit savedAccountsChanged();
    emit profileUpdatedOk();

    // Sincronización remota en segundo plano. El fallo de nube no debe deshacer
    // la foto local que el usuario ya seleccionó.
    const QString objectPath = m_userId + QStringLiteral("/avatar/avatar.png");
    QSettings settings;
    QString bucket = settings.value(QStringLiteral("supabase/bucket")).toString().trimmed();
    if (bucket.isEmpty())
        bucket = QStringLiteral("IngePlus");

    QUrl upUrl = buildStorageObjectUrl(m_api->projectUrl(), bucket, objectPath, false);
    QNetworkRequest req = m_api->makeRequest(upUrl);
    req.setRawHeader("Authorization", QByteArray("Bearer ") + m_accessToken.toUtf8());
    req.setRawHeader("apikey", m_api->anonKey().toUtf8());
    req.setRawHeader("x-upsert", "true");
    req.setRawHeader("cache-control", "no-cache");
    req.setHeader(QNetworkRequest::ContentTypeHeader, QStringLiteral("image/png"));
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
    req.setTransferTimeout(25000);
#endif

    auto* reply = m_api->nam()->post(req, bytes);
    connect(reply, &QNetworkReply::finished, this, [this, reply, objectPath]() {
        const QByteArray raw = reply->readAll();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QString errStr = reply->errorString();
        const auto err = reply->error();
        reply->deleteLater();

        if (err != QNetworkReply::NoError || http < 200 || http >= 300) {
            emit profileAvatarSyncWarning(parseSupabaseError(
                raw,
                QString("La foto quedó guardada en el dispositivo, pero no se sincronizó con la nube (HTTP %1): %2")
                    .arg(http).arg(errStr)));
            return;
        }

        m_avatarPath = objectPath;
        saveToDisk();
        emit userInfoChanged();
        emit savedAccountsChanged();

        QUrl url = m_api->authUrl("user");
        QNetworkRequest req2 = m_api->makeRequest(url);
        req2.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
        req2.setRawHeader("Authorization", QByteArray("Bearer ") + m_accessToken.toUtf8());
        req2.setRawHeader("apikey", m_api->anonKey().toUtf8());
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
        req2.setTransferTimeout(20000);
#endif

        QJsonObject data{
            {"avatar_path", objectPath},
            {"avatar_updated_at", QDateTime::currentDateTimeUtc().toString(Qt::ISODate)}
        };
        QJsonObject body{{"data", data}};
        auto* reply2 = m_api->nam()->put(req2, QJsonDocument(body).toJson(QJsonDocument::Compact));

        connect(reply2, &QNetworkReply::finished, this, [this, reply2]() {
            const QByteArray raw2 = reply2->readAll();
            const int http2 = reply2->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            const QString errStr2 = reply2->errorString();
            const auto err2 = reply2->error();
            reply2->deleteLater();

            if (err2 != QNetworkReply::NoError || http2 < 200 || http2 >= 300) {
                emit profileAvatarSyncWarning(parseSupabaseError(
                    raw2,
                    QString("La foto quedó guardada, pero no se pudo actualizar su metadata (HTTP %1): %2")
                        .arg(http2).arg(errStr2)));
                return;
            }

            saveToDisk();
            emit userInfoChanged();
            emit savedAccountsChanged();
            emit profileAvatarSynced();
        });
    });
}

void AuthSession::clearUserAvatar()
{
    if (!m_api) { emit profileUpdatedFail("SupabaseClient no inicializado."); return; }
    if (m_accessToken.isEmpty() || m_userId.isEmpty()) { emit profileUpdatedFail("No hay sesión activa."); return; }

    const QString pathToDelete = m_avatarPath; // uid/avatar/avatar.ext

    auto finishClearMeta = [this]() {
        // Limpiar cache local
        QFile::remove(QUrl(m_avatarLocalFile).toLocalFile());
        m_avatarLocalFile.clear();
        m_avatarUrl.clear();
        m_avatarPath.clear();

        // Limpiar metadata en Auth
        QUrl url = m_api->authUrl("user");
        QNetworkRequest req2 = m_api->makeRequest(url);
        req2.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
        req2.setRawHeader("Authorization", QByteArray("Bearer ") + m_accessToken.toUtf8());
        req2.setRawHeader("apikey", m_api->anonKey().toUtf8());

        QJsonObject data{
            {"avatar_url", QJsonValue()},
            {"avatar_path", QJsonValue()},
            {"avatar_updated_at", QJsonValue()}
        };
        QJsonObject body{{"data", data}};

        auto* reply2 = m_api->nam()->put(req2, QJsonDocument(body).toJson(QJsonDocument::Compact));
        connect(reply2, &QNetworkReply::finished, this, [this, reply2]() {
            reply2->readAll();
            reply2->deleteLater();
            saveToDisk();
            emit userInfoChanged();
            emit savedAccountsChanged();
            emit profileUpdatedOk();
        });
    };

    // Si no hay nada que borrar en storage, igual limpia metadata
    if (pathToDelete.isEmpty()) {
        finishClearMeta();
        return;
    }

    const QString lf = QUrl(m_avatarLocalFile).toLocalFile();
    if (!lf.isEmpty())
        QFile::remove(lf);


    // 1) Borrar del Storage
    QUrl delUrl = buildStorageObjectUrl(m_api->projectUrl(), "IngePlus", pathToDelete, false);

    QNetworkRequest req = m_api->makeRequest(delUrl);
    req.setRawHeader("Authorization", QByteArray("Bearer ") + m_accessToken.toUtf8());
    req.setRawHeader("apikey", m_api->anonKey().toUtf8());

    auto* reply = m_api->nam()->deleteResource(req);

    connect(reply, &QNetworkReply::finished, this, [this, reply, finishClearMeta]() mutable {
        reply->readAll();
        reply->deleteLater();
        // aunque falle el delete (archivo no existe), limpiamos igual
        finishClearMeta();
    });
}

void AuthSession::updateUserMetadata(const QJsonObject& data)
{
    QUrl url = m_api->authUrl("user"); // /auth/v1/user
    QNetworkRequest req = m_api->makeRequest(url);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    req.setRawHeader("Authorization", QByteArray("Bearer ") + m_accessToken.toUtf8());
    req.setRawHeader("apikey", m_api->anonKey().toUtf8());

    QJsonObject body{{"data", data}};
    auto* reply = m_api->nam()->put(req, QJsonDocument(body).toJson(QJsonDocument::Compact));

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray raw = reply->readAll();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto err = reply->error();
        reply->deleteLater();

        if (err != QNetworkReply::NoError || http < 200 || http >= 300) {
            emit profileUpdatedFail(parseSupabaseError(
                raw, QString("Error actualizando metadata (HTTP %1): %2").arg(http).arg(reply->errorString())
                ));
            return;
        }

        QJsonParseError pe{};
        const QJsonDocument doc = QJsonDocument::fromJson(raw, &pe);
        if (pe.error != QJsonParseError::NoError || !doc.isObject()) {
            emit profileUpdatedFail("Respuesta inválida actualizando metadata.");
            return;
        }

        setUserFromJson(doc.object());
        saveToDisk();
        emit userInfoChanged();
        emit profileUpdatedOk();
    });
}

void AuthSession::setRememberFor30Days(bool enabled)
{
    if (m_rememberFor30Days == enabled)
        return;

    m_rememberFor30Days = enabled;

    if (!m_rememberFor30Days)
        m_rememberUntilUtc = QDateTime();

    emit rememberFor30DaysChanged();
}

void AuthSession::clearSessionMemory()
{
    ++m_backendGeneration;
    m_devOffline = false;
    m_accessToken.clear();
    m_refreshToken.clear();
    m_userId.clear();
    m_expiresAtUtc = {};
    m_email.clear();
    m_loginEmailExact.clear();
    m_nombre.clear();
    m_apellido.clear();
    m_phone.clear();
    m_avatarUrl.clear();
    m_avatarLocalFile.clear();
    m_avatarPath.clear();
    clearBackendState();
}

void AuthSession::clearBackendState()
{
    m_fullName.clear();
    m_position.clear();
    m_profileRole.clear();
    m_globalRole.clear();
    m_profileStatus.clear();
    m_profileReady = false;
    m_assignedProjects.clear();
    m_memberships.clear();
    m_capabilities.clear();
    emit backendProfileChanged();
    emit backendAccessChanged();
}

void AuthSession::clearSavedSession()
{
    clearLegacyActiveSession();
    setCurrentAccountId(QString());
}

void AuthSession::setAutoLoginInProgress(bool active)
{
    if (m_autoLoginInProgress == active)
        return;
    m_autoLoginInProgress = active;
    emit autoLoginInProgressChanged();
}

void AuthSession::finishAutoLogin(bool restored)
{
    setAutoLoginInProgress(false);
    emit autoLoginFinished(restored);
}

void AuthSession::finishAuthSuccess(const QJsonObject& o, bool emitLoginSignal)
{
    const QJsonObject userObj = o.value("user").toObject();
    const QString incomingUserId = userObj.value(QStringLiteral("id")).toString().trimmed();

    // Al iniciar sesión con una cuenta distinta no se debe reutilizar el nombre,
    // correo o avatar de la cuenta anterior que todavía estaba en memoria.
    if (!incomingUserId.isEmpty() && incomingUserId != m_userId) {
        m_email.clear();
        m_nombre.clear();
        m_apellido.clear();
        m_phone.clear();
        m_avatarUrl.clear();
        m_avatarPath.clear();
        m_avatarLocalFile.clear();
        clearBackendState();

        const QString cachedAvatar = latestLocalAvatarCachePath(incomingUserId);
        if (!cachedAvatar.isEmpty() && QFile::exists(cachedAvatar))
            m_avatarLocalFile = QUrl::fromLocalFile(cachedAvatar).toString();
    }

    m_accessToken  = o.value("access_token").toString();
    m_refreshToken = o.value("refresh_token").toString();
    m_expiresAtUtc = QDateTime::currentDateTimeUtc().addSecs(o.value("expires_in").toInt());

    if (!userObj.isEmpty())
        setUserFromJson(userObj);

    if (!m_loginEmailExact.isEmpty())
        m_email = m_loginEmailExact;

    if (m_accessToken.isEmpty() || m_userId.isEmpty()) {
        if (emitLoginSignal)
            emit loginFail("Login falló: faltan tokens/userId.");
        if (m_autoLoginInProgress)
            finishAutoLogin(false);
        if (!m_pendingSwitchAccountId.isEmpty()) {
            const QString failedId = m_pendingSwitchAccountId;
            m_pendingSwitchAccountId.clear();
            emit accountSwitchFail(failedId, QStringLiteral("La cuenta guardada no contiene una sesión válida."));
        }
        return;
    }

    // Tener tokens no concede acceso. El perfil NEW del backend es la puerta
    // obligatoria tanto en login como en restauración/refresh de sesión.
    loadBackendProfile(emitLoginSignal,
                       !m_pendingSwitchAccountId.isEmpty(),
                       m_autoLoginInProgress);
}

void AuthSession::loadBackendProfile(bool emitLoginSignal,
                                     bool accountSwitch,
                                     bool autoLogin)
{
    if (!m_api || m_accessToken.isEmpty() || m_userId.isEmpty()) {
        failBackendAuthorization(QStringLiteral("No existe una sesión válida para consultar el perfil."),
                                 false, accountSwitch, autoLogin);
        return;
    }

    const quint64 generation = ++m_backendGeneration;
    // Preserve an already-authorized local preview during the remote check.
    emit backendProfileChanged();
    emit loggedChanged();

    QUrl url = m_api->restUrl(QStringLiteral("profiles"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("select"),
                       QStringLiteral("id,email,full_name,avatar_url,phone,position,role,status,global_role"));
    query.addQueryItem(QStringLiteral("id"), QStringLiteral("eq.") + m_userId);
    query.addQueryItem(QStringLiteral("limit"), QStringLiteral("1"));
    url.setQuery(query);

    QNetworkRequest request = m_api->makeRequest(url, m_accessToken);
    request.setRawHeader("Accept", "application/json");
    auto *reply = m_api->nam()->get(request);

    connect(reply, &QNetworkReply::finished, this,
            [this, reply, generation, emitLoginSignal, accountSwitch, autoLogin]() {
        const QByteArray raw = reply->readAll();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto error = reply->error();
        const QString errorText = reply->errorString();
        reply->deleteLater();

        if (generation != m_backendGeneration)
            return;

        if (error != QNetworkReply::NoError || http < 200 || http >= 300) {
            failBackendAuthorization(
                parseSupabaseError(raw,
                    QStringLiteral("No se pudo verificar el perfil (HTTP %1): %2")
                        .arg(http).arg(errorText)),
                false, accountSwitch, autoLogin);
            return;
        }

        QJsonParseError parseError{};
        const QJsonDocument document = QJsonDocument::fromJson(raw, &parseError);
        if (parseError.error != QJsonParseError::NoError
            || !document.isArray() || document.array().size() != 1) {
            failBackendAuthorization(QStringLiteral("La cuenta no tiene un perfil autorizado en InGe+."),
                                     true, accountSwitch, autoLogin);
            return;
        }

        const QJsonObject profile = document.array().first().toObject();
        if (profile.value(QStringLiteral("id")).toString() != m_userId) {
            failBackendAuthorization(QStringLiteral("El perfil recibido no corresponde a la sesión."),
                                     true, accountSwitch, autoLogin);
            return;
        }

        m_fullName = profile.value(QStringLiteral("full_name")).toString().trimmed();
        m_position = profile.value(QStringLiteral("position")).toString().trimmed();
        m_profileRole = profile.value(QStringLiteral("role")).toString().trimmed();
        m_globalRole = profile.value(QStringLiteral("global_role")).toString().trimmed();
        m_profileStatus = profile.value(QStringLiteral("status")).toString().trimmed().toUpper();
        m_profileReady = true;

        // En una sesión restaurada se conserva el correo exacto persistido; en
        // una instalación nueva, el backend proporciona el valor inicial.
        if (m_email.isEmpty())
            m_email = profile.value(QStringLiteral("email")).toString();
        if (!profile.value(QStringLiteral("phone")).toString().trimmed().isEmpty())
            m_phone = profile.value(QStringLiteral("phone")).toString().trimmed();

        const QString backendAvatar =
            profile.value(QStringLiteral("avatar_url")).toString().trimmed();
        const QString localAvatarPath = QUrl(m_avatarLocalFile).toLocalFile();
        if (!localAvatarPath.isEmpty() && QFile::exists(localAvatarPath))
            m_avatarUrl = m_avatarLocalFile;
        else
            m_avatarUrl = backendAvatar;

        emit backendProfileChanged();
        emit userInfoChanged();

        if (!profileActive()) {
            const QString state = m_profileStatus.isEmpty()
                ? QStringLiteral("SIN_PERFIL_ACTIVO") : m_profileStatus;
            failBackendAuthorization(
                QStringLiteral("Acceso no autorizado. Estado del perfil: %1.").arg(state),
                true, accountSwitch, autoLogin);
            return;
        }

        loadAssignedProjects(generation, emitLoginSignal, accountSwitch, autoLogin);
    });
}

void AuthSession::completeAuthorizedLogin(bool emitLoginSignal,
                                          bool accountSwitch,
                                          bool autoLogin)
{
    if (m_rememberFor30Days && !m_rememberUntilUtc.isValid())
        m_rememberUntilUtc = QDateTime::currentDateTimeUtc().addDays(30);

    saveToDisk();
    emit userInfoChanged();
    emit backendProfileChanged();
    emit loggedChanged();
    emit savedAccountsChanged();

    if (emitLoginSignal)
        emit loginOk();

    if (accountSwitch) {
        const QString switchedId = m_userId;
        m_pendingSwitchAccountId.clear();
        emit accountSwitchOk(switchedId);
    }

    if (autoLogin)
        finishAutoLogin(true);
}

void AuthSession::failBackendAuthorization(const QString& message,
                                           bool unauthorized,
                                           bool accountSwitch,
                                           bool autoLogin)
{
    const QString attemptedId = m_userId;
    if (unauthorized && !attemptedId.isEmpty())
        removeSavedAccountInternal(attemptedId, true);

    clearLegacyActiveSession();
    setCurrentAccountId(QString());
    clearSessionMemory();
    m_rememberFor30Days = false;
    m_rememberUntilUtc = QDateTime();

    emit rememberFor30DaysChanged();
    emit userInfoChanged();
    emit loggedChanged();
    emit loginFail(message);

    if (accountSwitch) {
        m_pendingSwitchAccountId.clear();
        emit accountSwitchFail(attemptedId, message);
    }
    if (autoLogin)
        finishAutoLogin(false);
}

void AuthSession::loadAssignedProjects(quint64 generation,
                                       bool emitLoginSignal,
                                       bool accountSwitch,
                                       bool autoLogin)
{
    if (!m_api || generation != m_backendGeneration || !logged())
        return;

    const QUrl url = m_api->restUrl(
        QStringLiteral("rpc/list_my_project_memberships_v01"));
    QNetworkRequest request = m_api->makeRequest(url, m_accessToken);
    const QJsonObject body;
    auto *reply = m_api->nam()->post(
        request, QJsonDocument(body).toJson(QJsonDocument::Compact));
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, generation, emitLoginSignal, accountSwitch, autoLogin]() {
        const QByteArray raw = reply->readAll();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto error = reply->error();
        reply->deleteLater();

        if (generation != m_backendGeneration || !logged())
            return;

        QJsonParseError parseError{};
        const QJsonDocument document = QJsonDocument::fromJson(raw, &parseError);
        if (error != QNetworkReply::NoError || http < 200 || http >= 300
            || parseError.error != QJsonParseError::NoError || !document.isArray()) {
            qWarning() << "[Auth] list_my_project_memberships_v01 failed"
                       << "http=" << http << "error=" << error
                       << "fallback=SUPABASE_RLS_PROJECTS";
            loadAssignedProjectsByRls(generation, emitLoginSignal, accountSwitch, autoLogin);
            return;
        }

        m_assignedProjects.clear();
        m_memberships.clear();
        m_capabilities.clear();

        const QJsonArray rows = document.array();
        if (rows.isEmpty()) {
            qInfo() << "[Auth] PROJECT_MEMBERSHIPS_EMPTY fallback=SUPABASE_RLS_PROJECTS";
            loadAssignedProjectsByRls(generation, emitLoginSignal, accountSwitch, autoLogin);
            return;
        }
        for (const QJsonValue& value : rows) {
            if (!value.isObject())
                continue;

            const QVariantMap rpcRow = value.toObject().toVariantMap();
            QVariantMap membership;
            membership.insert(QStringLiteral("membership_id"),
                              rpcRow.value(QStringLiteral("membership_id")));
            membership.insert(QStringLiteral("project_id"),
                              rpcRow.value(QStringLiteral("project_id")));
            membership.insert(QStringLiteral("status"),
                              rpcRow.value(QStringLiteral("membership_status")));
            membership.insert(QStringLiteral("roles"),
                              rpcRow.value(QStringLiteral("roles")));
            membership.insert(QStringLiteral("starts_at"),
                              rpcRow.value(QStringLiteral("starts_at")));
            membership.insert(QStringLiteral("ends_at"),
                              rpcRow.value(QStringLiteral("ends_at")));
            m_memberships.append(membership);

            const QString projectId =
                membership.value(QStringLiteral("project_id")).toString().trimmed();
            if (projectId.isEmpty())
                continue;

            QVariantMap project;
            project.insert(QStringLiteral("id"), projectId);
            project.insert(QStringLiteral("code"),
                           rpcRow.value(QStringLiteral("project_code")));
            project.insert(QStringLiteral("name"),
                           rpcRow.value(QStringLiteral("project_name")));
            m_assignedProjects.append(project);
        }

        qDebug() << "[Auth] list_my_project_memberships_v01"
                 << "http=" << http
                 << "memberships=" << m_memberships.size()
                 << "projects=" << m_assignedProjects.size();
        emit backendAccessChanged();
        completeAuthorizedLogin(emitLoginSignal, accountSwitch, autoLogin);
        if (!m_assignedProjects.isEmpty())
            loadProjectCapabilities(0, generation);
    });
}

void AuthSession::loadAssignedProjectsByRls(quint64 generation,
                                               bool emitLoginSignal,
                                               bool accountSwitch,
                                               bool autoLogin)
{
    if (!m_api || generation != m_backendGeneration || !logged())
        return;

    QUrl url = m_api->restUrl(QStringLiteral("projects"));
    QUrlQuery query;
    query.addQueryItem(QStringLiteral("select"), QStringLiteral("id,code,name"));
    query.addQueryItem(QStringLiteral("order"), QStringLiteral("created_at.desc"));
    url.setQuery(query);

    QNetworkRequest request = m_api->makeRequest(url, m_accessToken);
    auto *reply = m_api->nam()->get(request);
    connect(reply, &QNetworkReply::finished, this,
            [this, reply, generation, emitLoginSignal, accountSwitch, autoLogin]() {
        const QByteArray raw = reply->readAll();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto error = reply->error();
        reply->deleteLater();

        if (generation != m_backendGeneration || !logged())
            return;

        QJsonParseError parseError{};
        const QJsonDocument document = QJsonDocument::fromJson(raw, &parseError);
        m_assignedProjects.clear();
        m_memberships.clear();
        m_capabilities.clear();

        if (error != QNetworkReply::NoError || http < 200 || http >= 300
            || parseError.error != QJsonParseError::NoError || !document.isArray()) {
            qWarning() << "[Auth] PROJECT_SOURCE=SUPABASE_RLS failed"
                       << "http=" << http << "error=" << error;
            emit backendAccessChanged();
            completeAuthorizedLogin(emitLoginSignal, accountSwitch, autoLogin);
            return;
        }

        const QJsonArray rows = document.array();
        for (const QJsonValue &value : rows) {
            if (!value.isObject())
                continue;
            const QVariantMap row = value.toObject().toVariantMap();
            const QString projectId = row.value(QStringLiteral("id")).toString().trimmed();
            if (projectId.isEmpty())
                continue;

            QVariantMap project;
            project.insert(QStringLiteral("id"), projectId);
            project.insert(QStringLiteral("code"), row.value(QStringLiteral("code")));
            project.insert(QStringLiteral("name"), row.value(QStringLiteral("name")));
            m_assignedProjects.append(project);
        }

        qInfo() << "[Auth] PROJECT_SOURCE=SUPABASE_RLS"
                << "http=" << http
                << "projects=" << m_assignedProjects.size()
                << "memberships=" << m_memberships.size();
        emit backendAccessChanged();
        completeAuthorizedLogin(emitLoginSignal, accountSwitch, autoLogin);
        if (!m_assignedProjects.isEmpty())
            loadProjectCapabilities(0, generation);
    });
}

void AuthSession::loadProjectCapabilities(int index, quint64 generation)
{
    if (generation != m_backendGeneration || !logged()
        || index < 0 || index >= m_assignedProjects.size())
        return;

    const QVariantMap project = m_assignedProjects.at(index).toMap();
    const QString projectId = project.value(QStringLiteral("id")).toString();
    if (projectId.isEmpty()) {
        finishProjectAccessItem(index, generation, {});
        return;
    }

    const QUrl url = m_api->restUrl(
        QStringLiteral("rpc/get_my_project_calicatas_access_context_v01"));
    QNetworkRequest request = m_api->makeRequest(url, m_accessToken);
    const QJsonObject body{{QStringLiteral("p_project_id"), projectId}};
    auto *reply = m_api->nam()->post(request,
        QJsonDocument(body).toJson(QJsonDocument::Compact));

    connect(reply, &QNetworkReply::finished, this,
            [this, reply, index, generation, projectId]() {
        const QByteArray raw = reply->readAll();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto error = reply->error();
        reply->deleteLater();

        if (generation != m_backendGeneration || !logged())
            return;

        QVariantMap context;
        context.insert(QStringLiteral("project_id"), projectId);
        context.insert(QStringLiteral("can_view_calicatas"), false);
        context.insert(QStringLiteral("can_create_calicata"), false);
        context.insert(QStringLiteral("can_archive_calicatas"), false);

        QJsonParseError parseError{};
        const QJsonDocument document = QJsonDocument::fromJson(raw, &parseError);
        if (error == QNetworkReply::NoError && http >= 200 && http < 300
            && parseError.error == QJsonParseError::NoError
            && document.isArray() && !document.array().isEmpty()) {
            const QVariantMap serverContext =
                document.array().first().toObject().toVariantMap();
            for (auto it = serverContext.constBegin(); it != serverContext.constEnd(); ++it)
                context.insert(it.key(), it.value());
        }

        loadProjectTeamCapabilities(index, generation, context);
    });
}

void AuthSession::loadProjectTeamCapabilities(int index,
                                              quint64 generation,
                                              const QVariantMap& calicatasContext)
{
    const QString projectId =
        m_assignedProjects.value(index).toMap().value(QStringLiteral("id")).toString();
    const QUrl url = m_api->restUrl(
        QStringLiteral("rpc/get_my_project_team_access_context_v01"));
    QNetworkRequest request = m_api->makeRequest(url, m_accessToken);
    const QJsonObject body{{QStringLiteral("p_project_id"), projectId}};
    auto *reply = m_api->nam()->post(request,
        QJsonDocument(body).toJson(QJsonDocument::Compact));

    connect(reply, &QNetworkReply::finished, this,
            [this, reply, index, generation, calicatasContext]() {
        const QByteArray raw = reply->readAll();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto error = reply->error();
        reply->deleteLater();

        if (generation != m_backendGeneration || !logged())
            return;

        QVariantMap context = calicatasContext;
        context.insert(QStringLiteral("can_view_team"), false);
        context.insert(QStringLiteral("can_manage_team"), false);

        QJsonParseError parseError{};
        const QJsonDocument document = QJsonDocument::fromJson(raw, &parseError);
        if (error == QNetworkReply::NoError && http >= 200 && http < 300
            && parseError.error == QJsonParseError::NoError
            && document.isArray() && !document.array().isEmpty()) {
            const QVariantMap serverContext =
                document.array().first().toObject().toVariantMap();
            for (auto it = serverContext.constBegin(); it != serverContext.constEnd(); ++it)
                context.insert(it.key(), it.value());
        }

        finishProjectAccessItem(index, generation, context);
    });
}

void AuthSession::finishProjectAccessItem(int index,
                                          quint64 generation,
                                          const QVariantMap& capabilityContext)
{
    if (generation != m_backendGeneration || !logged())
        return;

    const QString projectId =
        m_assignedProjects.value(index).toMap().value(QStringLiteral("id")).toString();
    if (!projectId.isEmpty())
        m_capabilities.insert(projectId, capabilityContext);
    emit backendAccessChanged();

    if (index + 1 < m_assignedProjects.size())
        loadProjectCapabilities(index + 1, generation);
}

void AuthSession::refreshSessionWithRefreshTokenInternal(bool accountSwitch, bool autoLogin)
{
    const QString attemptedId = m_userId;

    if (!m_api || m_refreshToken.isEmpty()) {
        if ((accountSwitch || autoLogin) && !attemptedId.isEmpty())
            removeSavedAccountInternal(attemptedId, true);
        clearSavedSession();
        clearSessionMemory();
        emit userInfoChanged();
        emit loggedChanged();
        if (accountSwitch)
            emit accountSwitchFail(attemptedId, QStringLiteral("La sesión guardada no tiene token de renovación."));
        if (autoLogin)
            finishAutoLogin(false);
        return;
    }

    QUrl url = m_api->authUrl("token");
    QUrlQuery q;
    q.addQueryItem("grant_type", "refresh_token");
    url.setQuery(q);

    QNetworkRequest req = m_api->makeRequest(url);
    req.setRawHeader("Accept", "application/json");
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    req.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);

    QJsonObject body{{"refresh_token", m_refreshToken}};
    auto* reply = m_api->nam()->post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));
    const quint64 authGeneration = m_authGeneration;

    connect(reply, &QNetworkReply::finished, this, [this, reply, attemptedId, accountSwitch, autoLogin, authGeneration]() {
        const QByteArray raw = reply->readAll();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto err = reply->error();
        const QString errStr = reply->errorString();
        reply->deleteLater();

        // Una operación posterior (logout, otro login o cambio) ya es dueña de
        // la sesión: esta respuesta no puede modificar estado ni emitir señales.
        if (!authOperationCurrent(authGeneration, "refreshSession"))
            return;

        if (err != QNetworkReply::NoError || http < 200 || http >= 300) {
            qWarning() << "[Auth] refresh session failed"
                       << "account=" << attemptedId
                       << "http=" << http << "err=" << errStr;

            if ((accountSwitch || autoLogin) && !attemptedId.isEmpty())
                removeSavedAccountInternal(attemptedId, true);
            clearSavedSession();
            clearSessionMemory();
            emit userInfoChanged();
            emit loggedChanged();

            const QString message = parseSupabaseError(
                raw,
                QStringLiteral("La sesión guardada expiró o ya no es válida."));
            if (accountSwitch) {
                m_pendingSwitchAccountId.clear();
                emit accountSwitchFail(attemptedId, message);
            }
            if (autoLogin)
                finishAutoLogin(false);
            return;
        }

        QJsonParseError pe{};
        const QJsonDocument doc = QJsonDocument::fromJson(raw, &pe);
        if (pe.error != QJsonParseError::NoError || !doc.isObject()) {
            if ((accountSwitch || autoLogin) && !attemptedId.isEmpty())
                removeSavedAccountInternal(attemptedId, true);
            clearSavedSession();
            clearSessionMemory();
            emit userInfoChanged();
            emit loggedChanged();
            if (accountSwitch) {
                m_pendingSwitchAccountId.clear();
                emit accountSwitchFail(attemptedId, QStringLiteral("Respuesta inválida al restaurar la cuenta."));
            }
            if (autoLogin)
                finishAutoLogin(false);
            return;
        }

        finishAuthSuccess(doc.object(), /*emitLoginSignal=*/true);
    });
}

void AuthSession::refreshSessionWithRefreshToken()
{
    refreshSessionWithRefreshTokenInternal(false, false);
}

void AuthSession::switchToSavedAccount(const QString& accountId)
{
    const QString id = accountId.trimmed();
    if (id.isEmpty()) {
        emit accountSwitchFail(id, QStringLiteral("Cuenta inválida."));
        return;
    }

    beginAuthOperation("switch", /*cancelPasswordLogin=*/true);
    setAutoLoginInProgress(false);
    emit accountSwitchStarted(id);
    if (!loadSavedAccount(id)) {
        emit accountSwitchFail(id, QStringLiteral("La cuenta guardada ya no está disponible."));
        return;
    }

    m_pendingSwitchAccountId = id;
    const QDateTime nowUtc = QDateTime::currentDateTimeUtc();
    if (!m_accessToken.isEmpty() && m_expiresAtUtc.isValid()
        && nowUtc < m_expiresAtUtc.addSecs(-60)) {
        loadBackendProfile(/*emitLoginSignal=*/true,
                           /*accountSwitch=*/true,
                           /*autoLogin=*/false);
        return;
    }

    refreshSessionWithRefreshTokenInternal(true, false);
}

void AuthSession::restoreSavedAccountWithBiometric(const QString& accountId)
{
    const QString id = accountId.trimmed();
    if (id.isEmpty()) {
        emit accountSwitchFail(id, QStringLiteral("Cuenta inválida."));
        return;
    }

    beginAuthOperation("biometric", /*cancelPasswordLogin=*/true);
    setAutoLoginInProgress(false);
    emit accountSwitchStarted(id);
    if (!loadSavedAccount(id)) {
        emit accountSwitchFail(id, QStringLiteral("La cuenta guardada ya no está disponible."));
        return;
    }

    // La aprobación biométrica sólo abre el acceso local. Forzar siempre un
    // refresh remoto evita entrar con un access token local cuya sesión ya fue
    // revocada; cualquier rechazo vuelve por accountSwitchFail al password.
    m_pendingSwitchAccountId = id;
    refreshSessionWithRefreshTokenInternal(true, false);
}

void AuthSession::tryAutoLogin()
{
    beginAuthOperation("restore", /*cancelPasswordLogin=*/false);
    m_pendingSwitchAccountId.clear();
    setAutoLoginInProgress(true);

    clearDevOfflinePersistence();

    loadFromDisk();

    // Un access token vencido o ausente no invalida una sesión recordada: el
    // refresh token es la credencial de restauración y siempre se valida con
    // Supabase antes de exponer la sesión.
    if (!m_rememberFor30Days || m_refreshToken.isEmpty() || m_userId.isEmpty()) {
        finishAutoLogin(false);
        return;
    }

    const QDateTime nowUtc = QDateTime::currentDateTimeUtc();
    if (!m_accessToken.isEmpty() && m_expiresAtUtc.isValid()
        && nowUtc < m_expiresAtUtc.addSecs(-60)) {
        if (profileActive()) {
            emit loginOk();
            finishAutoLogin(true);
            QTimer::singleShot(0, this, [this]() {
                loadBackendProfile(false, false, false);
            });
        } else {
            loadBackendProfile(true, false, true);
        }
        return;
    }

    refreshSessionWithRefreshTokenInternal(false, true);
}

void AuthSession::requestPasswordReset(const QString& email)
{
    if (!m_api) {
        emit passwordResetRequestedFail(QStringLiteral("SupabaseClient no inicializado."));
        return;
    }

    const QString em = email;
    if (!looksLikeEmail(em)) {
        emit passwordResetRequestedFail(QStringLiteral("Correo inválido."));
        return;
    }

    // Supabase Auth: POST /auth/v1/recover
    // Envía correo de recuperación. El redirect_to debe estar permitido en Supabase Auth > URL Configuration.
    QUrl url = m_api->authUrl(QStringLiteral("recover"));

    QNetworkRequest req = m_api->makeRequest(url);
    req.setRawHeader("Accept", "application/json");
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    req.setRawHeader("Authorization", QByteArray("Bearer ") + m_api->anonKey().toUtf8());
    req.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);

    QJsonObject body{
        {QStringLiteral("email"), em},
        {QStringLiteral("redirect_to"), QStringLiteral("com.ingema.ingeplus://login-callback")}
    };

    auto* reply = m_api->nam()->post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));

    connect(reply, &QNetworkReply::finished, this, [this, reply, em]() {
        const QByteArray raw = reply->readAll();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto err = reply->error();
        const QString errStr = reply->errorString();

        qWarning() << "[Auth] password reset finished"
                   << "http=" << http
                   << "err=" << err
                   << "errStr=" << errStr
                   << "body=" << QString::fromUtf8(raw);

        reply->deleteLater();

        if (err != QNetworkReply::NoError || http < 200 || http >= 300) {
            emit passwordResetRequestedFail(parseSupabaseError(
                raw,
                QStringLiteral("Error enviando recuperación (HTTP %1): %2")
                    .arg(http)
                    .arg(err == QNetworkReply::NoError ? QStringLiteral("HTTP error") : errStr)
            ));
            return;
        }

        emit passwordResetRequestedOk(em);
    });
}

void AuthSession::resendSignupConfirmation(const QString& email)
{
    if (!m_api) {
        emit confirmationResentFail("SupabaseClient no inicializado.");
        return;
    }

    const QString em = email;

    if (!looksLikeEmail(em)) {
        emit confirmationResentFail("Correo inválido.");
        return;
    }

    QUrl url = m_api->authUrl("resend");

    QNetworkRequest req = m_api->makeRequest(url);
    req.setRawHeader("Accept", "application/json");
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    req.setRawHeader("Authorization", QByteArray("Bearer ") + m_api->anonKey().toUtf8());

    QJsonObject body{
        {"type", "signup"},
        {"email", em}
    };

    auto* reply = m_api->nam()->post(req, QJsonDocument(body).toJson(QJsonDocument::Compact));

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        const QByteArray raw = reply->readAll();
        const int http = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto err = reply->error();
        const QString errStr = reply->errorString();

        qWarning() << "[Auth] resend signup confirmation finished"
                   << "http=" << http
                   << "err=" << err
                   << "errStr=" << errStr
                   << "body=" << QString::fromUtf8(raw);

        reply->deleteLater();

        if (err != QNetworkReply::NoError || http < 200 || http >= 300) {
            emit confirmationResentFail(parseSupabaseError(
                raw,
                QString("Error reenviando confirmación (HTTP %1): %2").arg(http).arg(errStr)
                ));
            return;
        }

        emit confirmationResentOk();
    });
}
