#include "FusionBridgeController.h"

#include <QGuiApplication>
#include <QImage>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMutex>
#include <QMutexLocker>
#include <QQuickImageProvider>
#include <cmath>
#include <atomic>
#ifdef Q_OS_ANDROID
#include <QJniEnvironment>
#include <QJniObject>
#include <jni.h>
#endif

struct FusionFrameStore {
    QMutex mutex;
    QImage image;
    qint64 generation = 0;
    quint64 revision = 0;
};

namespace {
// JNI writes into a bounded, latest-only mailbox. No QObject pointer crosses
// Java threads; callbacks after shutdown cannot dereference the controller.
QMutex mailboxMutex;
std::weak_ptr<FusionFrameStore> mailbox;
std::atomic<qint64> sessionSequence{0};
constexpr const char *bridgeClass = "com/ingema/ingeplus/fusionbridge/FusionBridgeNative";

class EarthFrameImageProvider final : public QQuickImageProvider {
public:
    explicit EarthFrameImageProvider(std::shared_ptr<FusionFrameStore> frames)
        : QQuickImageProvider(QQuickImageProvider::Image), m_frames(std::move(frames)) {}
    QImage requestImage(const QString &, QSize *size, const QSize &) override {
        QMutexLocker lock(&m_frames->mutex);
        if (size) *size = m_frames->image.size();
        return m_frames->image;
    }
private:
    std::shared_ptr<FusionFrameStore> m_frames;
};
#ifdef Q_OS_ANDROID
bool jniFailed() {
    QJniEnvironment env;
    if (!env->ExceptionCheck()) return false;
    // Exception text may contain tokens; report a fixed code instead.
    env->ExceptionClear();
    return true;
}
#endif
}

FusionBridgeController::FusionBridgeController(QObject *parent)
    : QObject(parent), m_frames(std::make_shared<FusionFrameStore>())
{
    { QMutexLocker lock(&mailboxMutex); mailbox = m_frames; }
    m_poll.setInterval(200);
    connect(&m_poll, &QTimer::timeout, this, &FusionBridgeController::poll);
    connect(qGuiApp, &QGuiApplication::applicationStateChanged, this,
            [this](Qt::ApplicationState state) {
        if (state != Qt::ApplicationActive) clearFrame();
    });
    connect(qGuiApp, &QCoreApplication::aboutToQuit, this, &FusionBridgeController::close);
}

FusionBridgeController::~FusionBridgeController()
{
    close();
    QMutexLocker lock(&mailboxMutex);
    mailbox.reset();
}

QQuickImageProvider *FusionBridgeController::createImageProvider()
{
    return new EarthFrameImageProvider(m_frames);
}

QString FusionBridgeController::frameUrl() const
{
    return m_frameFresh ? QStringLiteral("image://fusionbridge/frame/%1").arg(m_frameRevision) : QString();
}

void FusionBridgeController::open()
{
    if (m_active) return;
    m_active = true;
    m_generation = ++sessionSequence;
    { QMutexLocker lock(&m_frames->mutex); m_frames->generation = m_generation; }
    m_target.clear();
    emit targetChanged();
    clearFrame();
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>(bridgeClass, "open", "(J)V", static_cast<jlong>(m_generation));
    if (jniFailed()) { fail(QStringLiteral("JNI_OPEN_ERROR")); return; }
    m_state = QStringLiteral("DETECTING");
    m_detail = QStringLiteral("EARTH_COOPERATION_UNVERIFIED");
    m_poll.start();
#else
    m_state = QStringLiteral("BLOCKED");
    m_detail = QStringLiteral("ANDROID_REQUIRED");
#endif
    emit stateChanged();
}

void FusionBridgeController::close()
{
    if (!m_active) return;
    m_poll.stop();
    m_active = false;
    { QMutexLocker lock(&m_frames->mutex); m_frames->generation = 0; }
    clearFrame();
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>(bridgeClass, "close", "()V");
    if (jniFailed()) m_detail = QStringLiteral("JNI_CLOSE_ERROR");
    else m_detail = QStringLiteral("MODULE_CLOSED");
#else
    m_detail = QStringLiteral("MODULE_CLOSED");
#endif
    m_state = QStringLiteral("CLOSED");
    m_target.clear();
    emit targetChanged();
    emit stateChanged();
}

void FusionBridgeController::requestCaptureProbe()
{
    if (!m_active) return;
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>(bridgeClass, "requestCaptureProbe", "(J)V",
                                      static_cast<jlong>(m_generation));
    if (jniFailed()) fail(QStringLiteral("JNI_PROBE_ERROR"));
#else
    fail(QStringLiteral("ANDROID_REQUIRED"));
#endif
}

bool FusionBridgeController::command(const QString &name)
{
    if (!m_active) return false;
#ifdef Q_OS_ANDROID
    const auto text = QJniObject::fromString(name);
    QJniObject::callStaticMethod<void>(bridgeClass, "command", "(Ljava/lang/String;)V", text.object<jstring>());
    if (jniFailed()) fail(QStringLiteral("JNI_COMMAND_ERROR"));
#else
    Q_UNUSED(name)
    fail(QStringLiteral("EARTH_INPUT_NO_COOPERATIVE_CHANNEL"));
#endif
    // Receipt is not a geographic effect. No commands succeed without a channel.
    return false;
}

bool FusionBridgeController::setTarget(double latitude, double longitude, const QString &label)
{
    if (!m_active || !std::isfinite(latitude) || !std::isfinite(longitude)
            || latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180)
        return false;
    m_target = {{QStringLiteral("latitude"), latitude}, {QStringLiteral("longitude"), longitude},
                {QStringLiteral("label"), label}};
    emit targetChanged();
    return true; // target preserved, never means camera moved
}

void FusionBridgeController::poll()
{
    if (!m_active) return;
#ifdef Q_OS_ANDROID
    const QJniObject result = QJniObject::callStaticObjectMethod(bridgeClass, "snapshotJson", "()Ljava/lang/String;");
    if (jniFailed() || !result.isValid()) { fail(QStringLiteral("JNI_DIAGNOSTICS_ERROR")); return; }
    const QString json = result.toString();
    const auto doc = QJsonDocument::fromJson(json.toUtf8());
    if (!doc.isObject()) { fail(QStringLiteral("INVALID_DIAGNOSTICS")); return; }
    const auto status = doc.object();
    const qint64 nativeSession = static_cast<qint64>(status.value(QStringLiteral("moduleSession")).toDouble());
    if (nativeSession != m_generation) {
        // Qt may survive an Android Activity recreation. Never retain the old
        // image or wait forever for the now-invalid Java session generation.
        if (nativeSession == 0 && status.value(QStringLiteral("hostSessionLost")).toBool()) {
            clearFrame();
            if (status.value(QStringLiteral("hostSessionRecoveryReady")).toBool()) {
                const QVariantMap target = m_target;
                close();
                open(); // new generation; no projection / consent token restored
                m_target = target;
                emit targetChanged();
            } else {
                m_state = QStringLiteral("BLOCKED");
                m_detail = QStringLiteral("HOST_RECREATED_WAITING_RESUME");
                emit stateChanged();
            }
        }
        return; // other queued results cannot revive a previous entry
    }
    if (m_diagnostics != json) {
        const auto detection = status.value(QStringLiteral("detection")).toObject();
        m_state = status.value(QStringLiteral("state")).toString();
        m_detail = status.value(QStringLiteral("detail")).toString();
        m_installed = detection.value(QStringLiteral("installed")).toBool();
        m_version = detection.value(QStringLiteral("version")).toString();
        m_probeSupported = detection.value(QStringLiteral("projectionProbeSupported")).toBool();
        m_diagnostics = json;
        emit stateChanged();
    }
#endif
    bool changed = false;
    {
        QMutexLocker lock(&m_frames->mutex);
        if (m_observedRevision != m_frames->revision) {
            m_observedRevision = m_frames->revision;
            m_frameFresh = !m_frames->image.isNull();
            ++m_frameRevision;
            if (m_frameFresh) m_lastFrame.restart();
            changed = true;
        }
    }
    if (changed) emit frameChanged();
    if (m_frameFresh && m_lastFrame.isValid() && m_lastFrame.elapsed() >= 2500)
        clearFrame();
}

void FusionBridgeController::clearFrame()
{
    { QMutexLocker lock(&m_frames->mutex);
      m_frames->image = QImage();
      m_observedRevision = ++m_frames->revision; }
    const bool wasFresh = m_frameFresh;
    m_frameFresh = false;
    m_lastFrame.invalidate();
    if (wasFresh) emit frameChanged();
}

void FusionBridgeController::fail(const QString &code)
{
    clearFrame();
    m_state = QStringLiteral("BLOCKED");
    m_detail = code;
    emit stateChanged();
}

#ifdef Q_OS_ANDROID
extern "C" JNIEXPORT void JNICALL
Java_com_ingema_ingeplus_fusionbridge_FusionBridgeNative_nativeFrame(
        JNIEnv *env, jclass, jlong generation, jbyteArray pixels, jint width, jint height)
{
    if (!pixels || width <= 0 || height <= 0 || width > 640 || height > 640) return;
    const jsize length = width * height * 4;
    if (env->GetArrayLength(pixels) != length) return;
    std::shared_ptr<FusionFrameStore> target;
    { QMutexLocker lock(&mailboxMutex); target = mailbox.lock(); }
    if (!target) return;
    QMutexLocker lock(&target->mutex);
    if (generation == 0 || target->generation != generation) return;
    QImage next(width, height, QImage::Format_RGBA8888);
    if (next.isNull()) return;
    env->GetByteArrayRegion(pixels, 0, length, reinterpret_cast<jbyte *>(next.bits()));
    if (env->ExceptionCheck()) { env->ExceptionClear(); return; }
    target->image = std::move(next);
    ++target->revision;
}

extern "C" JNIEXPORT void JNICALL
Java_com_ingema_ingeplus_fusionbridge_FusionBridgeNative_nativeClear(
        JNIEnv *, jclass, jlong generation)
{
    std::shared_ptr<FusionFrameStore> target;
    { QMutexLocker lock(&mailboxMutex); target = mailbox.lock(); }
    if (!target) return;
    QMutexLocker lock(&target->mutex);
    if (generation == 0 || target->generation != generation) return;
    target->image = QImage();
    ++target->revision;
}
#endif
