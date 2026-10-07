#include "permissionhelper.h"

#include <QCoreApplication>
#include <QDebug>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFuture>
#include <QGeoCoordinate>
#include <QGeoPositionInfo>
#include <QGeoPositionInfoSource>
#include <QImageReader>
#include <QLocationPermission>
#include <QPermission>
#include <QPointer>
#include <QSaveFile>
#include <QStandardPaths>
#include <QUuid>
#include <QVariant>
#include <QtMath>

#include <functional>

#ifdef Q_OS_ANDROID
#include <QJniEnvironment>
#include <QJniObject>
#include <QtCore/qnativeinterface.h>

// Qt 6.9 mantiene startActivity/requestPermission en QtCore para integrar el
// resultado de Activities Android. Se declaran aquí para no agregar una
// dependencia CorePrivate ni modificar CMake por dos intents acotados.
namespace QtAndroidPrivate {
enum PermissionResult {
    Undetermined,
    Authorized,
    Denied
};
QFuture<PermissionResult> requestPermission(const QString &permission);
void startActivity(const QJniObject &intent, int receiverRequestCode,
                   std::function<void(int, int, const QJniObject &data)> callbackFunc);
}
#endif

namespace {
constexpr int kContinuousIntervalMs = 1500;
constexpr int kImmediateTimeoutMs = 20000;
constexpr int kWatchdogIntervalMs = 20000;
constexpr qint64 kMaximumFixAgeMs = 5 * 60 * 1000;
constexpr double kMaximumAcceptedAccuracyMeters = 5000.0;
constexpr double kMinimumDeadbandMeters = 2.5;
constexpr double kMaximumDeadbandMeters = 8.0;
constexpr double kMaximumPlausibleSpeedMetersPerSecond = 70.0;
constexpr int kCameraActivityRequestCode = 48101;
constexpr int kGalleryActivityRequestCode = 48102;
constexpr int kAndroidResultOk = -1;
constexpr qsizetype kMaximumImportedPhotoBytes = 64 * 1024 * 1024;

bool validPhotoTarget(int targetIdx)
{
    return targetIdx >= 1 && targetIdx <= 3;
}

QString photoImportRoot()
{
    QString cache = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    if (cache.isEmpty())
        cache = QStandardPaths::writableLocation(QStandardPaths::TempLocation);
    if (cache.isEmpty())
        return {};
    return QDir(cache).filePath(QStringLiteral("calicata_photo_imports"));
}

bool isInsideDirectory(QString filePath, QString directoryPath)
{
    filePath = QDir::cleanPath(filePath);
    directoryPath = QDir::cleanPath(directoryPath);
#ifdef Q_OS_WIN
    filePath = filePath.toLower();
    directoryPath = directoryPath.toLower();
#endif
    if (!directoryPath.endsWith('/'))
        directoryPath += '/';
    return filePath.startsWith(directoryPath);
}

#ifdef Q_OS_ANDROID
QJniObject androidContext()
{
    return QNativeInterface::QAndroidApplication::context();
}

QJniObject settingsIntent(const char *action)
{
    const QJniObject actionString = QJniObject::fromString(QString::fromLatin1(action));
    return QJniObject("android/content/Intent",
                      "(Ljava/lang/String;)V",
                      actionString.object<jstring>());
}

bool clearJniException(const char *where)
{
    QJniEnvironment env;
    if (!env->ExceptionCheck())
        return false;
    qWarning() << "[InGe+ Android] JNI exception in" << where;
    env->ExceptionDescribe();
    env->ExceptionClear();
    return true;
}

QJniObject androidContentResolver()
{
    const QJniObject context = androidContext();
    if (!context.isValid())
        return {};
    return context.callObjectMethod("getContentResolver",
                                    "()Landroid/content/ContentResolver;");
}

QJniObject uriFromString(const QString &uriText)
{
    if (uriText.isEmpty())
        return {};
    const QJniObject value = QJniObject::fromString(uriText);
    return QJniObject::callStaticObjectMethod(
                "android/net/Uri", "parse",
                "(Ljava/lang/String;)Landroid/net/Uri;",
                value.object<jstring>());
}

void putContentValue(QJniObject &values, const char *key, const QString &value)
{
    const QJniObject jKey = QJniObject::fromString(QString::fromLatin1(key));
    const QJniObject jValue = QJniObject::fromString(value);
    values.callMethod<void>("put", "(Ljava/lang/String;Ljava/lang/String;)V",
                            jKey.object<jstring>(), jValue.object<jstring>());
}

void putContentValue(QJniObject &values, const char *key, int value)
{
    const QJniObject jKey = QJniObject::fromString(QString::fromLatin1(key));
    const QJniObject jValue("java/lang/Integer", "(I)V", value);
    values.callMethod<void>("put", "(Ljava/lang/String;Ljava/lang/Integer;)V",
                            jKey.object<jstring>(), jValue.object<jobject>());
}

QString createPendingCameraUri(QString *outFilePath, QString *error)
{
    const QJniObject context = androidContext();
    if (!context.isValid()) {
        if (error) *error = QStringLiteral("Android no permitió preparar el archivo de la cámara.");
        return {};
    }

    const QJniObject cacheDir = context.callObjectMethod(
                "getCacheDir", "()Ljava/io/File;");
    if (clearJniException("Context.getCacheDir(camera)") || !cacheDir.isValid()) {
        if (error) *error = QStringLiteral("Android no devolvió la caché privada de la aplicación.");
        return {};
    }

    const QString cacheRoot = cacheDir.callObjectMethod(
                "getAbsolutePath", "()Ljava/lang/String;").toString();
    const QString cameraDir = QDir(cacheRoot).filePath(QStringLiteral("calicata_camera"));
    if (cacheRoot.isEmpty() || !QDir().mkpath(cameraDir)) {
        if (error) *error = QStringLiteral("No se pudo preparar la carpeta temporal de la cámara.");
        return {};
    }

    const QString filePath = QDir(cameraDir).filePath(
                QStringLiteral("ingeplus_capture_%1.jpg")
                .arg(QUuid::createUuid().toString(QUuid::WithoutBraces)));
    QFile file(filePath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        if (error) *error = QStringLiteral("No se pudo crear el destino temporal de la foto.");
        return {};
    }
    file.close();

    const QJniObject jPath = QJniObject::fromString(filePath);
    const QJniObject jFile("java/io/File", "(Ljava/lang/String;)V",
                           jPath.object<jstring>());
    const QJniObject packageName = context.callObjectMethod(
                "getPackageName", "()Ljava/lang/String;");
    const QString authorityText = packageName.toString() + QStringLiteral(".nothingfiles");
    const QJniObject authority = QJniObject::fromString(authorityText);
    const QJniObject uri = QJniObject::callStaticObjectMethod(
                "androidx/core/content/FileProvider", "getUriForFile",
                "(Landroid/content/Context;Ljava/lang/String;Ljava/io/File;)Landroid/net/Uri;",
                context.object<jobject>(), authority.object<jstring>(), jFile.object<jobject>());
    if (clearJniException("FileProvider.getUriForFile(camera)") || !uri.isValid()) {
        QFile::remove(filePath);
        if (error) *error = QStringLiteral("No se pudo publicar el destino seguro de la cámara.");
        return {};
    }

    if (outFilePath) *outFilePath = filePath;
    return uri.toString();
}

void revokeContentUriGrant(const QString &uriText)
{
    const QJniObject context = androidContext();
    const QJniObject uri = uriFromString(uriText);
    if (!context.isValid() || !uri.isValid())
        return;
    context.callMethod<void>("revokeUriPermission", "(Landroid/net/Uri;I)V",
                             uri.object<jobject>(), jint(3));
    clearJniException("Context.revokeUriPermission(camera)");
}

void deleteContentUri(const QString &uriText)
{
    const QJniObject resolver = androidContentResolver();
    const QJniObject uri = uriFromString(uriText);
    if (!resolver.isValid() || !uri.isValid())
        return;
    resolver.callMethod<jint>("delete",
                              "(Landroid/net/Uri;Ljava/lang/String;[Ljava/lang/String;)I",
                              uri.object<jobject>(), nullptr, nullptr);
    clearJniException("ContentResolver.delete(camera)");
}

QUrl copyContentUriToPrivateCache(const QString &uriText, QString *error)
{
    const QJniObject resolver = androidContentResolver();
    const QJniObject uri = uriFromString(uriText);
    if (!resolver.isValid() || !uri.isValid()) {
        if (error) *error = QStringLiteral("Android devolvió una imagen sin acceso válido.");
        return {};
    }

    const QJniObject input = resolver.callObjectMethod(
                "openInputStream", "(Landroid/net/Uri;)Ljava/io/InputStream;",
                uri.object<jobject>());
    if (clearJniException("ContentResolver.openInputStream(photo)") || !input.isValid()) {
        if (error) *error = QStringLiteral("No se pudo leer la imagen seleccionada.");
        return {};
    }

    QString suffix = QStringLiteral(".img");
    const QJniObject mime = resolver.callObjectMethod(
                "getType", "(Landroid/net/Uri;)Ljava/lang/String;",
                uri.object<jobject>());
    const QString mimeText = mime.toString().toLower();
    if (mimeText == QStringLiteral("image/jpeg")) suffix = QStringLiteral(".jpg");
    else if (mimeText == QStringLiteral("image/png")) suffix = QStringLiteral(".png");
    else if (mimeText == QStringLiteral("image/webp")) suffix = QStringLiteral(".webp");
    else if (mimeText == QStringLiteral("image/bmp")) suffix = QStringLiteral(".bmp");

    const QString root = photoImportRoot();
    if (root.isEmpty() || !QDir().mkpath(root)) {
        input.callMethod<void>("close", "()V");
        if (error) *error = QStringLiteral("No se pudo preparar la caché privada de fotografías.");
        return {};
    }

    const QString outPath = QDir(root).filePath(
                QUuid::createUuid().toString(QUuid::WithoutBraces) + suffix);
    QSaveFile output(outPath);
    if (!output.open(QIODevice::WriteOnly)) {
        input.callMethod<void>("close", "()V");
        if (error) *error = QStringLiteral("No se pudo crear la copia temporal de la imagen.");
        return {};
    }

    bool ok = true;
    qsizetype total = 0;
    QJniEnvironment env;
    jbyteArray buffer = env->NewByteArray(64 * 1024);
    while (ok) {
        const jint count = input.callMethod<jint>("read", "([B)I", buffer);
        if (env->ExceptionCheck()) {
            env->ExceptionClear();
            ok = false;
            break;
        }
        if (count <= 0)
            break;
        total += count;
        if (total > kMaximumImportedPhotoBytes) {
            ok = false;
            if (error) *error = QStringLiteral("La imagen supera el límite permitido de 64 MB.");
            break;
        }
        QByteArray chunk(count, Qt::Uninitialized);
        env->GetByteArrayRegion(buffer, 0, count,
                                reinterpret_cast<jbyte *>(chunk.data()));
        if (output.write(chunk) != chunk.size())
            ok = false;
    }
    env->DeleteLocalRef(buffer);
    input.callMethod<void>("close", "()V");

    if (!ok || total <= 0 || !output.commit()) {
        output.cancelWriting();
        QFile::remove(outPath);
        if (error && error->isEmpty())
            *error = QStringLiteral("No se pudo copiar completamente la imagen seleccionada.");
        return {};
    }

    QImageReader reader(outPath);
    reader.setAutoTransform(true);
    if (!reader.canRead()) {
        QFile::remove(outPath);
        if (error) *error = QStringLiteral("El archivo seleccionado no es una imagen válida.");
        return {};
    }
    return QUrl::fromLocalFile(outPath);
}

bool startAndroidActivity(const QJniObject &intent)
{
    if (!intent.isValid())
        return false;

    QFuture<QVariant> task =
        QNativeInterface::QAndroidApplication::runOnAndroidMainThread(
            [intent]() -> QVariant {
                const QJniObject context = androidContext();
                if (!context.isValid())
                    return QVariant(false);
                context.callMethod<void>("startActivity",
                                         "(Landroid/content/Intent;)V",
                                         intent.object<jobject>());
                return QVariant(!clearJniException("startActivity"));
            });
    task.waitForFinished();
    return task.result().toBool();
}

QJniObject androidLocationManager()
{
    const QJniObject context = androidContext();
    if (!context.isValid())
        return {};

    const QJniObject serviceName = QJniObject::fromString(QStringLiteral("location"));
    return context.callObjectMethod("getSystemService",
                                    "(Ljava/lang/String;)Ljava/lang/Object;",
                                    serviceName.object<jstring>());
}
#endif

QString errorTextForSource(QGeoPositionInfoSource::Error error)
{
    switch (error) {
    case QGeoPositionInfoSource::AccessError:
        return QStringLiteral("Android bloqueo el acceso a la ubicacion precisa");
    case QGeoPositionInfoSource::ClosedError:
        return QStringLiteral("La ubicacion del dispositivo esta desactivada");
    case QGeoPositionInfoSource::UnknownSourceError:
        return QStringLiteral("No hay un proveedor de ubicacion disponible");
    case QGeoPositionInfoSource::UpdateTimeoutError:
        return QStringLiteral("La ubicacion todavia no responde");
    case QGeoPositionInfoSource::NoError:
        break;
    }
    return {};
}
} // namespace

PermissionHelper::PermissionHelper(QObject *parent)
    : QObject(parent)
{
    m_watchdogTimer.setInterval(kWatchdogIntervalMs);
    m_watchdogTimer.setTimerType(Qt::CoarseTimer);
    connect(&m_watchdogTimer, &QTimer::timeout, this, [this]() {
        if (!m_nativeTracking || !m_positionSource || m_immediateRequestPending)
            return;

        const qint64 now = QDateTime::currentMSecsSinceEpoch();
        const bool sourceSilent = m_lastSourceEventMs <= 0
                || now - m_lastSourceEventMs > kWatchdogIntervalMs;
        if (sourceSilent) {
            qInfo() << "[InGe+ GPS] watchdog: proveedor silencioso; solicitando lectura fresca";
            requestImmediateLocationUpdate();
        }
    });

    m_immediateRequestTimer.setSingleShot(true);
    m_immediateRequestTimer.setInterval(kImmediateTimeoutMs + 1500);
    connect(&m_immediateRequestTimer, &QTimer::timeout, this, [this]() {
        if (!m_immediateRequestPending)
            return;
        setImmediateRequestPending(false);
        handleUpdateTimeout();
    });

    refreshPermissionState();
}

PermissionHelper::~PermissionHelper()
{
    stopNativeLocationUpdates();
#ifdef Q_OS_ANDROID
    if (!m_pendingCameraUri.isEmpty())
        revokeContentUriGrant(m_pendingCameraUri);
    if (!m_pendingCameraFilePath.isEmpty())
        QFile::remove(m_pendingCameraFilePath);
#endif
}

bool PermissionHelper::nativeLocationSupported() const
{
    return true;
}

void PermissionHelper::refreshPermissionState()
{
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
    QLocationPermission permission;
    permission.setAccuracy(QLocationPermission::Precise);
    permission.setAvailability(QLocationPermission::WhenInUse);

    QString next;
    switch (qApp->checkPermission(permission)) {
    case Qt::PermissionStatus::Granted:
        next = QStringLiteral("granted");
        break;
    case Qt::PermissionStatus::Denied:
        next = QStringLiteral("denied");
        break;
    case Qt::PermissionStatus::Undetermined:
        next = QStringLiteral("undetermined");
        break;
    }
#else
    const QString next = QStringLiteral("granted");
#endif

    if (m_permissionRequestPending)
        next = QStringLiteral("requesting");

    if (m_nativePermissionStatus != next) {
        m_nativePermissionStatus = next;
        emit nativePermissionChanged();
    }
}

bool PermissionHelper::hasLocationPermission() const
{
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
    QLocationPermission permission;
    permission.setAccuracy(QLocationPermission::Precise);
    permission.setAvailability(QLocationPermission::WhenInUse);
    return qApp->checkPermission(permission) == Qt::PermissionStatus::Granted;
#else
    return true;
#endif
}

void PermissionHelper::requestLocationPermission()
{
#if QT_VERSION >= QT_VERSION_CHECK(6, 5, 0)
    if (hasLocationPermission()) {
        refreshPermissionState();
        startNativeLocationUpdates();
        return;
    }
    if (m_permissionRequestPending)
        return;

    QLocationPermission permission;
    permission.setAccuracy(QLocationPermission::Precise);
    permission.setAvailability(QLocationPermission::WhenInUse);

    m_permissionRequestPending = true;
    refreshPermissionState();
    setNativeStatus(QStringLiteral("requesting_permission"), QString());
    qInfo() << "[InGe+ GPS] solicitando permiso de ubicacion PRECISA";

    qApp->requestPermission(permission, this, [this](const QPermission &result) {
        m_permissionRequestPending = false;

        bool preciseGranted = result.status() == Qt::PermissionStatus::Granted;
        const auto typedPermission = result.value<QLocationPermission>();
        if (typedPermission.has_value())
            preciseGranted = preciseGranted
                    && typedPermission->accuracy() == QLocationPermission::Precise;

        refreshPermissionState();
        qInfo() << "[InGe+ GPS] resultado permiso preciso:" << preciseGranted;

        if (preciseGranted || hasLocationPermission()) {
            setNativeStatus(QStringLiteral("permission_granted"), QString());
            startNativeLocationUpdates();
        } else {
            setNativeStatus(QStringLiteral("permission_denied"),
                            QStringLiteral("Activa 'Usar ubicacion precisa' en los permisos de Android"));
        }
    });
#else
    startNativeLocationUpdates();
#endif
}

void PermissionHelper::requestLocation()
{
    requestLocationPermission();
}

void PermissionHelper::requestPermissions()
{
    requestLocationPermission();
}

void PermissionHelper::capturePhoto(int targetIdx)
{
    if (!validPhotoTarget(targetIdx)) {
        emit photoSelectionError(targetIdx, QStringLiteral("invalid_target"),
                                 QStringLiteral("El bloque de fotografía no es válido."));
        return;
    }
    if (m_photoRequestInFlight) {
        emit photoSelectionError(targetIdx, QStringLiteral("photo_request_busy"),
                                 QStringLiteral("Ya hay una selección de fotografía en curso."));
        return;
    }

    m_photoRequestInFlight = true;
#ifdef Q_OS_ANDROID
    auto permissionFuture = QtAndroidPrivate::requestPermission(
                QStringLiteral("android.permission.CAMERA"));
    permissionFuture.then(this, [this, targetIdx](QtAndroidPrivate::PermissionResult result) {
        if (result != QtAndroidPrivate::Authorized) {
            m_photoRequestInFlight = false;
            emit photoSelectionError(targetIdx, QStringLiteral("camera_permission_denied"),
                                     QStringLiteral("Android denegó el permiso de cámara."));
            return;
        }
        if (QNativeInterface::QAndroidApplication::sdkVersion() <= 28) {
            auto storageFuture = QtAndroidPrivate::requestPermission(
                        QStringLiteral("android.permission.WRITE_EXTERNAL_STORAGE"));
            storageFuture.then(this, [this, targetIdx](QtAndroidPrivate::PermissionResult storageResult) {
                if (storageResult != QtAndroidPrivate::Authorized) {
                    m_photoRequestInFlight = false;
                    emit photoSelectionError(
                                targetIdx, QStringLiteral("photo_storage_permission_denied"),
                                QStringLiteral("Android denegó el acceso necesario para guardar la captura."));
                    return;
                }
                launchCamera(targetIdx);
            });
            return;
        }
        launchCamera(targetIdx);
    });
#else
    m_photoRequestInFlight = false;
    emit photoSelectionError(targetIdx, QStringLiteral("camera_unavailable"),
                             QStringLiteral("La cámara solo está disponible en Android."));
#endif
}

void PermissionHelper::pickPhoto(int targetIdx)
{
    if (!validPhotoTarget(targetIdx)) {
        emit photoSelectionError(targetIdx, QStringLiteral("invalid_target"),
                                 QStringLiteral("El bloque de fotografía no es válido."));
        return;
    }
    if (m_photoRequestInFlight) {
        emit photoSelectionError(targetIdx, QStringLiteral("photo_request_busy"),
                                 QStringLiteral("Ya hay una selección de fotografía en curso."));
        return;
    }

    m_photoRequestInFlight = true;
    launchGallery(targetIdx);
}

void PermissionHelper::releaseImportedPhoto(const QUrl &localUrl)
{
    if (!localUrl.isLocalFile())
        return;
    const QString root = photoImportRoot();
    const QString path = QDir::cleanPath(localUrl.toLocalFile());
    if (!root.isEmpty() && isInsideDirectory(path, root))
        QFile::remove(path);
}

void PermissionHelper::launchCamera(int targetIdx)
{
#ifdef Q_OS_ANDROID
    const QJniObject action = QJniObject::fromString(
                QStringLiteral("android.media.action.IMAGE_CAPTURE"));
    QJniObject intent("android/content/Intent", "(Ljava/lang/String;)V",
                      action.object<jstring>());

    const QJniObject context = androidContext();
    const QJniObject packageManager = context.callObjectMethod(
                "getPackageManager", "()Landroid/content/pm/PackageManager;");
    const QJniObject cameraActivity = intent.callObjectMethod(
                "resolveActivity",
                "(Landroid/content/pm/PackageManager;)Landroid/content/ComponentName;",
                packageManager.object<jobject>());
    if (!context.isValid() || !packageManager.isValid() || !cameraActivity.isValid()
            || clearJniException("Intent.resolveActivity(camera)")) {
        m_photoRequestInFlight = false;
        emit photoSelectionError(targetIdx, QStringLiteral("camera_unavailable"),
                                 QStringLiteral("No hay una aplicación de cámara disponible."));
        return;
    }

    QString error;
    m_pendingCameraUri = createPendingCameraUri(&m_pendingCameraFilePath, &error);
    if (m_pendingCameraUri.isEmpty()) {
        m_photoRequestInFlight = false;
        emit photoSelectionError(targetIdx, QStringLiteral("camera_destination_error"), error);
        return;
    }

    const QJniObject outputUri = uriFromString(m_pendingCameraUri);
    const QJniObject cameraPackage = cameraActivity.callObjectMethod(
                "getPackageName", "()Ljava/lang/String;");
    if (cameraPackage.isValid()) {
        intent.callObjectMethod("setPackage",
                                "(Ljava/lang/String;)Landroid/content/Intent;",
                                cameraPackage.object<jstring>());
        context.callMethod<void>("grantUriPermission",
                                 "(Ljava/lang/String;Landroid/net/Uri;I)V",
                                 cameraPackage.object<jstring>(),
                                 outputUri.object<jobject>(), jint(3));
    }
    if (clearJniException("grantUriPermission(camera)")) {
        QFile::remove(m_pendingCameraFilePath);
        m_pendingCameraFilePath.clear();
        m_pendingCameraUri.clear();
        m_photoRequestInFlight = false;
        emit photoSelectionError(targetIdx, QStringLiteral("camera_launch_error"),
                                 QStringLiteral("No se pudo conceder acceso temporal a la cámara."));
        return;
    }
    const QJniObject outputKey = QJniObject::fromString(
                QStringLiteral("output"));
    intent.callObjectMethod(
                "putExtra",
                "(Ljava/lang/String;Landroid/os/Parcelable;)Landroid/content/Intent;",
                outputKey.object<jstring>(), outputUri.object<jobject>());
    const QJniObject clipLabel = QJniObject::fromString(QStringLiteral("InGe+ camera output"));
    const QJniObject clipData = QJniObject::callStaticObjectMethod(
                "android/content/ClipData", "newRawUri",
                "(Ljava/lang/CharSequence;Landroid/net/Uri;)Landroid/content/ClipData;",
                clipLabel.object<jstring>(), outputUri.object<jobject>());
    if (clipData.isValid()) {
        intent.callMethod<void>("setClipData",
                                "(Landroid/content/ClipData;)V",
                                clipData.object<jobject>());
    }
    intent.callObjectMethod("addFlags", "(I)Landroid/content/Intent;", 3);
    if (clearJniException("Intent.putExtra(camera)")) {
        revokeContentUriGrant(m_pendingCameraUri);
        QFile::remove(m_pendingCameraFilePath);
        m_pendingCameraFilePath.clear();
        m_pendingCameraUri.clear();
        m_photoRequestInFlight = false;
        emit photoSelectionError(targetIdx, QStringLiteral("camera_launch_error"),
                                 QStringLiteral("No se pudo preparar la cámara."));
        return;
    }

    const QString cameraUri = m_pendingCameraUri;
    QPointer<PermissionHelper> guard(this);
    emit externalPhotoActivityStarted();
    QtAndroidPrivate::startActivity(
                intent, kCameraActivityRequestCode,
                [guard, targetIdx, cameraUri](int, int resultCode, const QJniObject &) {
        if (!guard)
            return;
        QMetaObject::invokeMethod(
                    guard.data(),
                    [guard, targetIdx, resultCode, cameraUri]() {
            if (guard)
                guard->finishPhotoActivity(targetIdx, QStringLiteral("camera"),
                                           resultCode, cameraUri);
        }, Qt::QueuedConnection);
    });
#else
    m_photoRequestInFlight = false;
    emit photoSelectionError(targetIdx, QStringLiteral("camera_unavailable"),
                             QStringLiteral("La cámara solo está disponible en Android."));
#endif
}

void PermissionHelper::launchGallery(int targetIdx)
{
#ifdef Q_OS_ANDROID
    const QJniObject context = androidContext();
    if (!context.isValid()) {
        m_photoRequestInFlight = false;
        emit photoSelectionError(targetIdx, QStringLiteral("gallery_unavailable"),
                                 QStringLiteral("Android no pudo abrir el selector de imágenes."));
        return;
    }

    const QJniObject packageManager = context.callObjectMethod(
                "getPackageManager", "()Landroid/content/pm/PackageManager;");
    if (!packageManager.isValid() || clearJniException("Context.getPackageManager(gallery)")) {
        m_photoRequestInFlight = false;
        emit photoSelectionError(targetIdx, QStringLiteral("gallery_unavailable"),
                                 QStringLiteral("Android no pudo consultar el selector de imágenes."));
        return;
    }

    auto buildPickerIntent = [](const QString &actionName, bool persistable) {
        const QJniObject action = QJniObject::fromString(actionName);
        QJniObject picker("android/content/Intent", "(Ljava/lang/String;)V",
                          action.object<jstring>());
        const QJniObject category = QJniObject::fromString(
                    QStringLiteral("android.intent.category.OPENABLE"));
        const QJniObject mime = QJniObject::fromString(QStringLiteral("image/*"));
        picker.callObjectMethod("addCategory",
                                "(Ljava/lang/String;)Landroid/content/Intent;",
                                category.object<jstring>());
        picker.callObjectMethod("setType",
                                "(Ljava/lang/String;)Landroid/content/Intent;",
                                mime.object<jstring>());
        int flags = 1; // FLAG_GRANT_READ_URI_PERMISSION
        if (persistable)
            flags |= 64; // FLAG_GRANT_PERSISTABLE_URI_PERMISSION
        picker.callObjectMethod("addFlags", "(I)Landroid/content/Intent;", flags);
        return picker;
    };

    QJniObject intent = buildPickerIntent(
                QStringLiteral("android.intent.action.OPEN_DOCUMENT"), true);
    QJniObject pickerActivity = intent.callObjectMethod(
                "resolveActivity",
                "(Landroid/content/pm/PackageManager;)Landroid/content/ComponentName;",
                packageManager.object<jobject>());
    bool resolveFailed = clearJniException("Intent.resolveActivity(OPEN_DOCUMENT)");

    // Algunos fabricantes no exponen OPEN_DOCUMENT al PackageManager aunque
    // sí permiten GET_CONTENT. Se usa como respaldo sin pedir acceso general
    // al almacenamiento.
    if (!pickerActivity.isValid() || resolveFailed) {
        intent = buildPickerIntent(
                    QStringLiteral("android.intent.action.GET_CONTENT"), false);
        pickerActivity = intent.callObjectMethod(
                    "resolveActivity",
                    "(Landroid/content/pm/PackageManager;)Landroid/content/ComponentName;",
                    packageManager.object<jobject>());
        resolveFailed = clearJniException("Intent.resolveActivity(GET_CONTENT)");
    }

    if (!pickerActivity.isValid() || resolveFailed) {
        m_photoRequestInFlight = false;
        emit photoSelectionError(targetIdx, QStringLiteral("gallery_unavailable"),
                                 QStringLiteral("No se encontró una aplicación para elegir imágenes."));
        return;
    }

    QPointer<PermissionHelper> guard(this);
    emit externalPhotoActivityStarted();
    QtAndroidPrivate::startActivity(
                intent, kGalleryActivityRequestCode,
                [guard, targetIdx](int, int resultCode, const QJniObject &data) {
        QString uriText;
        if (data.isValid()) {
            const QJniObject uri = data.callObjectMethod(
                        "getData", "()Landroid/net/Uri;");
            if (uri.isValid())
                uriText = uri.toString();
        }
        if (!guard)
            return;
        QMetaObject::invokeMethod(
                    guard.data(),
                    [guard, targetIdx, resultCode, uriText]() {
            if (guard)
                guard->finishPhotoActivity(targetIdx, QStringLiteral("gallery"),
                                           resultCode, uriText);
        }, Qt::QueuedConnection);
    });
#else
    m_photoRequestInFlight = false;
    emit photoSelectionError(targetIdx, QStringLiteral("gallery_unavailable"),
                             QStringLiteral("El selector de imágenes solo está disponible en Android."));
#endif
}

void PermissionHelper::finishPhotoActivity(int targetIdx, const QString &sourceKind,
                                           int resultCode, const QString &contentUri)
{
    m_photoRequestInFlight = false;
    emit externalPhotoActivityFinished();
    const bool fromCamera = sourceKind == QStringLiteral("camera");

    auto cleanupCamera = [this, fromCamera, contentUri]() {
#ifdef Q_OS_ANDROID
        if (fromCamera && !contentUri.isEmpty())
            revokeContentUriGrant(contentUri);
#endif
        if (fromCamera && !m_pendingCameraFilePath.isEmpty())
            QFile::remove(m_pendingCameraFilePath);
        m_pendingCameraFilePath.clear();
        m_pendingCameraUri.clear();
    };

    if (resultCode != kAndroidResultOk) {
        cleanupCamera();
        emit photoSelectionCanceled(targetIdx, sourceKind);
        return;
    }

    if (contentUri.isEmpty()) {
        cleanupCamera();
        emit photoSelectionError(targetIdx, QStringLiteral("empty_photo_result"),
                                 QStringLiteral("Android no devolvió ninguna imagen."));
        return;
    }

#ifdef Q_OS_ANDROID
    // Samsung y otros fabricantes pueden devolver RESULT_OK incluso si la
    // cámara no escribió una imagen válida. Nunca confirmar el slot hasta
    // verificar bytes reales y decodificables.
    if (fromCamera) {
        const QFileInfo captured(m_pendingCameraFilePath);
        if (m_pendingCameraFilePath.isEmpty() || !captured.exists()
                || captured.size() <= 0) {
            cleanupCamera();
            emit photoSelectionError(targetIdx, QStringLiteral("camera_empty_output"),
                                     QStringLiteral("La cámara no guardó una fotografía válida."));
            return;
        }
        QImageReader probe(m_pendingCameraFilePath);
        probe.setAutoTransform(true);
        if (!probe.canRead()) {
            cleanupCamera();
            emit photoSelectionError(targetIdx, QStringLiteral("camera_invalid_output"),
                                     QStringLiteral("La cámara devolvió un archivo de imagen inválido."));
            return;
        }
    }

    QString error;
    const QUrl localUrl = copyContentUriToPrivateCache(contentUri, &error);
    cleanupCamera();

    if (!localUrl.isValid()) {
        emit photoSelectionError(targetIdx, QStringLiteral("photo_import_error"), error);
        return;
    }
    emit photoSelected(targetIdx, localUrl, sourceKind);
#else
    cleanupCamera();
    Q_UNUSED(sourceKind)
    emit photoSelectionError(targetIdx, QStringLiteral("photo_import_error"),
                             QStringLiteral("No se pudo importar la imagen."));
#endif
}

bool PermissionHelper::isLocationServiceEnabled() const
{
#ifdef Q_OS_ANDROID
    const QJniObject manager = androidLocationManager();
    if (!manager.isValid())
        return false;
    const jboolean enabled = manager.callMethod<jboolean>("isLocationEnabled", "()Z");
    if (clearJniException("LocationManager.isLocationEnabled"))
        return false;
    return enabled == JNI_TRUE;
#else
    return true;
#endif
}

bool PermissionHelper::openLocationSettings()
{
#ifdef Q_OS_ANDROID
    if (startAndroidActivity(settingsIntent("android.settings.LOCATION_SOURCE_SETTINGS")))
        return true;
    return startAndroidActivity(settingsIntent("android.settings.SETTINGS"));
#else
    return false;
#endif
}

bool PermissionHelper::openApplicationSettings()
{
#ifdef Q_OS_ANDROID
    QJniObject intent = settingsIntent("android.settings.APPLICATION_DETAILS_SETTINGS");
    if (!intent.isValid())
        return false;

    const QJniObject context = androidContext();
    if (!context.isValid())
        return false;

    const QJniObject packageName = context.callObjectMethod("getPackageName", "()Ljava/lang/String;");
    const QJniObject uriText = QJniObject::fromString(
        QStringLiteral("package:") + packageName.toString());
    const QJniObject packageUri = QJniObject::callStaticObjectMethod(
        "android/net/Uri", "parse", "(Ljava/lang/String;)Landroid/net/Uri;",
        uriText.object<jstring>());
    if (!packageUri.isValid())
        return false;

    intent.callObjectMethod("setData",
                            "(Landroid/net/Uri;)Landroid/content/Intent;",
                            packageUri.object<jobject>());
    return startAndroidActivity(intent);
#else
    return false;
#endif
}

bool PermissionHelper::setFlutterHomeVisible(bool visible,
                                             const QString &themeMode,
                                             double motionScale,
                                             double glassIntensity,
                                             const QString &performanceProfile)
{
#ifdef Q_OS_ANDROID
    const QJniObject jTheme = QJniObject::fromString(themeMode);
    const QJniObject jProfile = QJniObject::fromString(performanceProfile);
    const jboolean accepted = QJniObject::callStaticMethod<jboolean>(
                "com/ingema/ingeplus/InGeQtActivity",
                "setFlutterHomeVisible",
                "(ZLjava/lang/String;DDLjava/lang/String;)Z",
                static_cast<jboolean>(visible), jTheme.object<jstring>(),
                static_cast<jdouble>(motionScale),
                static_cast<jdouble>(glassIntensity),
                jProfile.object<jstring>());
    return !clearJniException("InGeQtActivity.setFlutterHomeVisible")
            && accepted == JNI_TRUE;
#else
    Q_UNUSED(visible)
    Q_UNUSED(themeMode)
    Q_UNUSED(motionScale)
    Q_UNUSED(glassIntensity)
    Q_UNUSED(performanceProfile)
    return false;
#endif
}

bool PermissionHelper::isFlutterHomeReady() const
{
#ifdef Q_OS_ANDROID
    const jboolean ready = QJniObject::callStaticMethod<jboolean>(
                "com/ingema/ingeplus/InGeQtActivity",
                "isFlutterHomeReady", "()Z");
    return !clearJniException("InGeQtActivity.isFlutterHomeReady")
            && ready == JNI_TRUE;
#else
    return false;
#endif
}

bool PermissionHelper::setFlutterRenditionsVisible(
    bool visible, const QString &themeMode, double motionScale,
    double glassIntensity, const QString &performanceProfile)
{
#ifdef Q_OS_ANDROID
    const QJniObject jTheme = QJniObject::fromString(themeMode);
    const QJniObject jProfile = QJniObject::fromString(performanceProfile);
    const jboolean accepted = QJniObject::callStaticMethod<jboolean>(
        "com/ingema/ingeplus/InGeQtActivity",
        "setFlutterRenditionsVisible",
        "(ZLjava/lang/String;DDLjava/lang/String;)Z",
        static_cast<jboolean>(visible), jTheme.object<jstring>(),
        static_cast<jdouble>(motionScale),
        static_cast<jdouble>(glassIntensity), jProfile.object<jstring>());
    return !clearJniException("InGeQtActivity.setFlutterRenditionsVisible")
        && accepted == JNI_TRUE;
#else
    Q_UNUSED(visible)
    Q_UNUSED(themeMode)
    Q_UNUSED(motionScale)
    Q_UNUSED(glassIntensity)
    Q_UNUSED(performanceProfile)
    return false;
#endif
}

QString PermissionHelper::takeFlutterHomeAction()
{
#ifdef Q_OS_ANDROID
    const QJniObject action = QJniObject::callStaticObjectMethod(
                "com/ingema/ingeplus/InGeQtActivity",
                "takeFlutterHomeAction", "()Ljava/lang/String;");
    if (clearJniException("InGeQtActivity.takeFlutterHomeAction")
            || !action.isValid())
        return {};
    return action.toString();
#else
    return {};
#endif
}

bool PermissionHelper::setFlutterAuthVisible(bool visible,
                                              const QString &authStateJson,
                                              const QString &themeMode,
                                              double motionScale,
                                              double glassIntensity,
                                              const QString &performanceProfile)
{
#ifdef Q_OS_ANDROID
    const QJniObject jState = QJniObject::fromString(authStateJson);
    const QJniObject jTheme = QJniObject::fromString(themeMode);
    const QJniObject jProfile = QJniObject::fromString(performanceProfile);
    const jboolean accepted = QJniObject::callStaticMethod<jboolean>(
                "com/ingema/ingeplus/InGeQtActivity",
                "setFlutterAuthVisible",
                "(ZLjava/lang/String;Ljava/lang/String;DDLjava/lang/String;)Z",
                static_cast<jboolean>(visible), jState.object<jstring>(),
                jTheme.object<jstring>(), static_cast<jdouble>(motionScale),
                static_cast<jdouble>(glassIntensity), jProfile.object<jstring>());
    return !clearJniException("InGeQtActivity.setFlutterAuthVisible")
            && accepted == JNI_TRUE;
#else
    Q_UNUSED(visible)
    Q_UNUSED(authStateJson)
    Q_UNUSED(themeMode)
    Q_UNUSED(motionScale)
    Q_UNUSED(glassIntensity)
    Q_UNUSED(performanceProfile)
    return false;
#endif
}

bool PermissionHelper::setFlutterSecurityVisible(bool visible,
                                                  const QString &authStateJson,
                                                  const QString &themeMode,
                                                  double motionScale,
                                                  double glassIntensity,
                                                  const QString &performanceProfile)
{
#ifdef Q_OS_ANDROID
    const QJniObject jState = QJniObject::fromString(authStateJson);
    const QJniObject jTheme = QJniObject::fromString(themeMode);
    const QJniObject jProfile = QJniObject::fromString(performanceProfile);
    const jboolean accepted = QJniObject::callStaticMethod<jboolean>(
                "com/ingema/ingeplus/InGeQtActivity",
                "setFlutterSecurityVisible",
                "(ZLjava/lang/String;Ljava/lang/String;DDLjava/lang/String;)Z",
                static_cast<jboolean>(visible), jState.object<jstring>(),
                jTheme.object<jstring>(), static_cast<jdouble>(motionScale),
                static_cast<jdouble>(glassIntensity), jProfile.object<jstring>());
    return !clearJniException("InGeQtActivity.setFlutterSecurityVisible")
            && accepted == JNI_TRUE;
#else
    Q_UNUSED(visible)
    Q_UNUSED(authStateJson)
    Q_UNUSED(themeMode)
    Q_UNUSED(motionScale)
    Q_UNUSED(glassIntensity)
    Q_UNUSED(performanceProfile)
    return false;
#endif
}

bool PermissionHelper::updateFlutterAuthState(const QString &authStateJson)
{
#ifdef Q_OS_ANDROID
    const QJniObject jState = QJniObject::fromString(authStateJson);
    const jboolean accepted = QJniObject::callStaticMethod<jboolean>(
                "com/ingema/ingeplus/InGeQtActivity",
                "updateFlutterAuthState", "(Ljava/lang/String;)Z",
                jState.object<jstring>());
    return !clearJniException("InGeQtActivity.updateFlutterAuthState")
            && accepted == JNI_TRUE;
#else
    Q_UNUSED(authStateJson)
    return false;
#endif
}

QString PermissionHelper::takeFlutterAuthRequest()
{
#ifdef Q_OS_ANDROID
    const QJniObject request = QJniObject::callStaticObjectMethod(
                "com/ingema/ingeplus/InGeQtActivity",
                "takeFlutterAuthRequest", "()Ljava/lang/String;");
    if (clearJniException("InGeQtActivity.takeFlutterAuthRequest")
            || !request.isValid())
        return {};
    return request.toString();
#else
    return {};
#endif
}

bool PermissionHelper::ensurePositionSource()
{
    if (m_positionSource)
        return true;

    m_positionSource = QGeoPositionInfoSource::createDefaultSource(this);
    if (!m_positionSource) {
        setNativeStatus(QStringLiteral("no_provider"),
                        QStringLiteral("Qt no encontro el proveedor Android de ubicacion"));
        return false;
    }

    // Una sola fuente persistente. El filtro de distancia se implementa en
    // acceptPosition(), porque QGeoPositionInfoSource no expone un distanceFilter
    // portable. El intervalo evita saturar QML/mapa con eventos de 1 Hz.
    const int minimum = m_positionSource->minimumUpdateInterval();
    m_positionSource->setUpdateInterval(qMax(kContinuousIntervalMs, minimum));

    connect(m_positionSource, &QGeoPositionInfoSource::positionUpdated,
            this, &PermissionHelper::handlePositionUpdated, Qt::UniqueConnection);
    connect(m_positionSource, &QGeoPositionInfoSource::errorOccurred,
            this, [this](QGeoPositionInfoSource::Error error) {
                if (error == QGeoPositionInfoSource::UpdateTimeoutError) {
                    handleUpdateTimeout();
                    return;
                }
                handleSourceError(static_cast<int>(error));
            });

    qInfo() << "[InGe+ GPS] fuente unica creada"
            << "name=" << m_positionSource->sourceName()
            << "interval=" << m_positionSource->updateInterval()
            << "minimum=" << minimum;
    return true;
}

bool PermissionHelper::startNativeLocationUpdates()
{
    refreshPermissionState();
    if (!hasLocationPermission()) {
        setNativeStatus(QStringLiteral("permission_denied"),
                        QStringLiteral("Se requiere ubicacion precisa"));
        return false;
    }
    if (!isLocationServiceEnabled()) {
        setNativeStatus(QStringLiteral("service_disabled"),
                        QStringLiteral("La ubicacion del dispositivo esta desactivada"));
        return false;
    }
    if (!ensurePositionSource())
        return false;

    const bool startingNow = !m_nativeTracking;
    if (startingNow) {
        // Una posicion conocida solo sirve como arranque provisional. Las
        // lecturas demasiado antiguas siguen siendo rechazadas por acceptPosition().
        QGeoPositionInfo cached = m_positionSource->lastKnownPosition(true);
        if (!cached.isValid())
            cached = m_positionSource->lastKnownPosition(false);
        if (cached.isValid())
            acceptPosition(cached);

        m_lastSourceEventMs = QDateTime::currentMSecsSinceEpoch();
        m_positionSource->startUpdates();
        setNativeTracking(true);
        m_watchdogTimer.start();
        qInfo() << "[InGe+ GPS] tracking continuo iniciado";
    }

    setNativeStatus(m_nativeHasFix ? QStringLiteral("tracking")
                                   : QStringLiteral("searching"),
                    QString());

    // Solo al arrancar y sin una posicion util se pide un fix inmediato.
    // Volver a llamar startNativeLocationUpdates() nunca crea un request loop.
    if (startingNow && !m_nativeHasFix)
        requestImmediateLocationUpdate();
    return true;
}

void PermissionHelper::stopNativeLocationUpdates()
{
    m_watchdogTimer.stop();
    m_immediateRequestTimer.stop();
    setImmediateRequestPending(false);
    if (m_positionSource && m_nativeTracking)
        m_positionSource->stopUpdates();
    setNativeTracking(false);
    setNativeStatus(m_nativeHasFix ? QStringLiteral("paused_with_fix")
                                   : QStringLiteral("idle"),
                    QString());
}

void PermissionHelper::refreshNativeLocation()
{
    if (!m_nativeTracking) {
        startNativeLocationUpdates();
        return;
    }
    requestImmediateLocationUpdate();
}

bool PermissionHelper::requestImmediateLocationUpdate()
{
    if (!m_nativeTracking) {
        if (!startNativeLocationUpdates())
            return false;
        return true;
    }
    if (!m_positionSource)
        return false;
    if (m_immediateRequestPending) {
        qInfo() << "[InGe+ GPS] lectura inmediata ya pendiente; se omite duplicado";
        return true;
    }

    setNativeStatus(m_nativeHasFix ? QStringLiteral("tracking")
                                   : QStringLiteral("searching"),
                    QString());
    setImmediateRequestPending(true);
    m_immediateRequestTimer.start();
    m_positionSource->requestUpdate(kImmediateTimeoutMs);
    qInfo() << "[InGe+ GPS] lectura inmediata solicitada";
    return true;
}

void PermissionHelper::handlePositionUpdated(const QGeoPositionInfo &info)
{
    m_lastSourceEventMs = QDateTime::currentMSecsSinceEpoch();

    // Publica primero la lectura y recién después cierra la solicitud puntual.
    // El orden anterior notificaba "request terminado" antes de actualizar
    // nativeTimestampMs/nativeLatitude, por lo que QML podía mostrar timeout
    // aunque Android acabara de entregar una coordenada válida.
    const bool accepted = acceptPosition(info);
    if (m_immediateRequestPending && accepted) {
        m_immediateRequestTimer.stop();
        setImmediateRequestPending(false);
    }
}

bool PermissionHelper::acceptPosition(const QGeoPositionInfo &info)
{
    if (!info.isValid() || !info.coordinate().isValid()) {
        qWarning() << "[InGe+ GPS] lectura invalida recibida";
        return false;
    }

    const QGeoCoordinate rawCoordinate = info.coordinate();
    const double rawLatitude = rawCoordinate.latitude();
    const double rawLongitude = rawCoordinate.longitude();
    const bool hasAccuracy = info.hasAttribute(QGeoPositionInfo::HorizontalAccuracy);
    const double accuracy = hasAccuracy
            ? info.attribute(QGeoPositionInfo::HorizontalAccuracy)
            : qQNaN();
    // nativeTimestampMs debe ser el instante de adquisición (Location.getTime()).
    // Sin timestamp no se conoce la edad; usar la hora de recepción haría pasar
    // un fix cacheado antiguo como lectura actual.
    if (!info.timestamp().isValid()) {
        qDebug() << "[InGe+ GPS] lectura sin timestamp de adquisicion descartada";
        return false;
    }
    const qint64 timestamp = info.timestamp().toMSecsSinceEpoch();
    const qint64 now = QDateTime::currentMSecsSinceEpoch();
    const qint64 age = qMax<qint64>(0, now - timestamp);

    qDebug() << "[InGe+ GPS] fix bruto"
             << rawLatitude << rawLongitude
             << "accuracy=" << accuracy
             << "ageMs=" << age;

    if (!qIsFinite(rawLatitude) || !qIsFinite(rawLongitude)
            || rawLatitude < -90.0 || rawLatitude > 90.0
            || rawLongitude < -180.0 || rawLongitude > 180.0) {
        qWarning() << "[InGe+ GPS] coordenadas fuera de rango";
        return false;
    }

    if (!qIsFinite(accuracy) || accuracy <= 0.0
            || accuracy > kMaximumAcceptedAccuracyMeters) {
        setNativeStatus(QStringLiteral("searching"), QString());
        qDebug() << "[InGe+ GPS] lectura descartada por precision=" << accuracy;
        return false;
    }

    if (age > kMaximumFixAgeMs) {
        qDebug() << "[InGe+ GPS] lectura antigua descartada ageMs=" << age;
        return false;
    }

    QGeoCoordinate publishedCoordinate = rawCoordinate;
    double distance = 0.0;
    double deadband = kMinimumDeadbandMeters;
    double smoothingAlpha = 1.0;

    if (m_nativeHasFix) {
        if (timestamp + 5000 < m_nativeTimestampMs) {
            qDebug() << "[InGe+ GPS] lectura anterior a la publicada descartada";
            return false;
        }

        const QGeoCoordinate previous(m_nativeLatitude, m_nativeLongitude);
        distance = previous.distanceTo(rawCoordinate);
        const qint64 elapsedWallMs = m_lastPublishedWallClockMs > 0
                ? qMax<qint64>(250, now - m_lastPublishedWallClockMs)
                : kContinuousIntervalMs;
        const double elapsedSeconds = elapsedWallMs / 1000.0;
        const double previousAccuracy = qIsFinite(m_nativeAccuracy)
                ? m_nativeAccuracy : accuracy;
        const double allowedJump = qMax(accuracy + previousAccuracy + 35.0,
                                        elapsedSeconds * kMaximumPlausibleSpeedMetersPerSecond);

        if (qIsFinite(distance) && distance > allowedJump
                && accuracy >= previousAccuracy * 0.8) {
            qWarning() << "[InGe+ GPS] salto no plausible descartado"
                       << "distance=" << distance
                       << "allowed=" << allowedJump
                       << "accuracy=" << accuracy;
            return false;
        }

        deadband = qBound(kMinimumDeadbandMeters,
                          accuracy * 0.35,
                          kMaximumDeadbandMeters);
        const bool accuracyImproved = accuracy + 2.0 < previousAccuracy
                && accuracy < previousAccuracy * 0.78;

        // Si el dispositivo esta quieto, Android suele variar centimetros o
        // pocos metros dentro del propio error horizontal. No se publica ese
        // ruido a QML/mapa, por lo que el punto azul deja de parpadear.
        if (qIsFinite(distance) && distance < deadband && !accuracyImproved) {
            ++m_suppressedNoiseFixes;
            if (m_suppressedNoiseFixes == 1 || m_suppressedNoiseFixes % 20 == 0) {
                qDebug() << "[InGe+ GPS] ruido suprimido"
                         << "distance=" << distance
                         << "deadband=" << deadband
                         << "count=" << m_suppressedNoiseFixes;
            }

            // Una solicitud inmediata necesita confirmar una lectura fresca,
            // aunque el usuario esté quieto y no debamos mover el marcador.
            // Actualizamos metadatos y emitimos la señal sin introducir jitter.
            if (m_immediateRequestPending) {
                m_nativeAltitude = qIsFinite(rawCoordinate.altitude())
                        ? rawCoordinate.altitude() : qQNaN();
                m_nativeAccuracy = accuracy;
                m_nativeTimestampMs = timestamp;
                m_lastPublishedWallClockMs = now;
                m_nativeProvider = m_positionSource && !m_positionSource->sourceName().isEmpty()
                        ? m_positionSource->sourceName()
                        : QStringLiteral("android");
                setNativeStatus(accuracy <= 50.0
                                ? QStringLiteral("tracking_precise")
                                : QStringLiteral("tracking"),
                                QString());
                emit nativeLocationChanged();
                qInfo() << "[InGe+ GPS] lectura puntual confirmada sin mover marcador"
                        << "accuracy=" << accuracy
                        << "provider=" << m_nativeProvider;
                return true;
            }

            setNativeStatus(accuracy <= 50.0
                            ? QStringLiteral("tracking_precise")
                            : QStringLiteral("tracking"),
                            QString());
            return false;
        }

        m_suppressedNoiseFixes = 0;

        // Suavizado adaptativo: conserva respuesta inmediata al caminar o
        // trasladarse, pero amortigua saltos pequeños dentro de la precision.
        if (qIsFinite(distance) && distance < 30.0) {
            if (distance >= qMax(12.0, deadband * 3.0))
                smoothingAlpha = 0.78;
            else if (distance >= deadband * 1.8)
                smoothingAlpha = 0.58;
            else
                smoothingAlpha = 0.38;

            const double azimuth = previous.azimuthTo(rawCoordinate);
            if (qIsFinite(azimuth))
                publishedCoordinate = previous.atDistanceAndAzimuth(distance * smoothingAlpha,
                                                                     azimuth);
        }
    }

    m_nativeHasFix = true;
    m_nativeLatitude = publishedCoordinate.latitude();
    m_nativeLongitude = publishedCoordinate.longitude();
    m_nativeAltitude = qIsFinite(rawCoordinate.altitude())
            ? rawCoordinate.altitude() : qQNaN();
    m_nativeAccuracy = accuracy;
    m_nativeTimestampMs = timestamp;
    m_lastPublishedWallClockMs = now;
    m_nativeProvider = m_positionSource && !m_positionSource->sourceName().isEmpty()
            ? m_positionSource->sourceName()
            : QStringLiteral("android");

    const QString qualityStatus = accuracy <= 50.0
            ? QStringLiteral("tracking_precise")
            : (accuracy <= 250.0
               ? QStringLiteral("tracking")
               : QStringLiteral("tracking_approximate"));
    setNativeStatus(qualityStatus, QString());
    emit nativeLocationChanged();

    qInfo() << "[InGe+ GPS] posicion publicada"
            << m_nativeLatitude << m_nativeLongitude
            << "accuracy=" << m_nativeAccuracy
            << "movement=" << distance
            << "deadband=" << deadband
            << "alpha=" << smoothingAlpha
            << "provider=" << m_nativeProvider;
    return true;
}

void PermissionHelper::handleSourceError(int errorValue)
{
    const auto error = static_cast<QGeoPositionInfoSource::Error>(errorValue);
    if (error == QGeoPositionInfoSource::NoError)
        return;

    if (m_immediateRequestPending) {
        m_immediateRequestTimer.stop();
        setImmediateRequestPending(false);
    }

    const QString text = errorTextForSource(error);
    if (error == QGeoPositionInfoSource::AccessError) {
        refreshPermissionState();
        setNativeStatus(QStringLiteral("permission_denied"), text);
        setNativeTracking(false);
    } else if (error == QGeoPositionInfoSource::ClosedError) {
        setNativeStatus(QStringLiteral("service_disabled"), text);
        setNativeTracking(false);
    } else if (error == QGeoPositionInfoSource::UnknownSourceError) {
        setNativeStatus(QStringLiteral("no_provider"), text);
    } else {
        setNativeStatus(m_nativeHasFix ? QStringLiteral("tracking")
                                       : QStringLiteral("searching"),
                        QString());
    }
    qWarning() << "[InGe+ GPS] error de proveedor:" << error << text;
}

void PermissionHelper::handleUpdateTimeout()
{
    if (m_immediateRequestPending) {
        m_immediateRequestTimer.stop();
        setImmediateRequestPending(false);
    }
    if (!m_nativeTracking)
        return;
    setNativeStatus(m_nativeHasFix ? QStringLiteral("tracking")
                                   : QStringLiteral("searching"),
                    QString());
    qInfo() << "[InGe+ GPS] timeout puntual; el tracking continuo sigue activo";
}

void PermissionHelper::setNativeTracking(bool tracking)
{
    if (m_nativeTracking == tracking)
        return;
    m_nativeTracking = tracking;
    emit nativeTrackingChanged();
}

void PermissionHelper::setImmediateRequestPending(bool pending)
{
    if (m_immediateRequestPending == pending)
        return;
    m_immediateRequestPending = pending;
    emit nativeImmediateRequestPendingChanged();
}

void PermissionHelper::setNativeStatus(const QString &status, const QString &error)
{
    if (m_nativeLocationStatus == status && m_nativeLocationError == error)
        return;
    m_nativeLocationStatus = status;
    m_nativeLocationError = error;
    emit nativeLocationStatusChanged();
}
