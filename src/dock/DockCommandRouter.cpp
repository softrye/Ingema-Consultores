#include "DockCommandRouter.h"

#include "DockContextController.h"

#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPointer>

#ifdef Q_OS_ANDROID
#include <QJniEnvironment>
#include <QJniObject>
#include <jni.h>
#endif

namespace {
QPointer<DockCommandRouter> g_router;
constexpr int kReleaseTimeoutMs = 4000;
const char *const kQtActivityClass = "com/ingema/ingeplus/InGeQtActivity";
const QString kInGeCoreCapability = QStringLiteral("inge.core");
} // namespace

DockCommandRouter::DockCommandRouter(DockContextController *controller, QObject *parent)
    : QObject(parent)
    , m_controller(controller)
{
    g_router = this;
    m_releaseTimer.setSingleShot(true);
    m_releaseTimer.setInterval(kReleaseTimeoutMs);
    connect(&m_releaseTimer, &QTimer::timeout, this, [this]() { release(QStringLiteral("timeout")); });
}

DockCommandRouter::~DockCommandRouter()
{
    if (g_router == this)
        g_router.clear();
}

DockCommandRouter *DockCommandRouter::instance()
{
    return g_router.data();
}

bool DockCommandRouter::dispatch(const QString &actionId, int generation)
{
    if (!m_controller)
        return false;
    if (m_controller->transitionPending()
            || m_controller->ownerId() != m_controller->foregroundOwner()) {
        qInfo() << "INGE_DOCK_STALE tap rejected=foreground-transition";
        return false;
    }
    if (generation != m_controller->generation()) {
        qInfo().noquote() << QStringLiteral("INGE_DOCK_STALE tap generation=%1 active=%2 action=%3")
                                 .arg(generation).arg(m_controller->generation()).arg(actionId);
        return false;
    }
    const QVariantMap action = m_controller->actionById(actionId);
    if (action.isEmpty() || !action.value(QStringLiteral("visible")).toBool()
            || !action.value(QStringLiteral("enabled")).toBool()) {
        qWarning().noquote() << QStringLiteral("INGE_DOCK_INVALID reason=unavailable-action generation=%1 action=%2")
                                    .arg(generation).arg(actionId);
        return false;
    }
    const bool repeatable = action.value(QStringLiteral("repeatable")).toBool();
    const QString command = action.value(QStringLiteral("command")).toString();
    if (command.isEmpty()) {
        // A pure branch only opens its children inside the dock view.
        qWarning().noquote() << QStringLiteral("INGE_DOCK_INVALID reason=branch-without-command generation=%1 action=%2")
                                    .arg(generation).arg(actionId);
        return false;
    }
    if (busy() && !repeatable) {
        qInfo().noquote() << QStringLiteral("INGE_DOCK_COMMAND rejected=in-flight generation=%1 command=%2 pending=%3")
                                 .arg(generation).arg(command, m_inFlightCommand);
        return false;
    }

    const QString dispatchId = QStringLiteral("%1:%2").arg(generation).arg(++m_sequence);
    if (!repeatable) {
        m_inFlightId = dispatchId;
        m_inFlightCommand = command;
        m_releaseTimer.start();
        emit busyChanged();
    }

    const QString owner = m_controller->ownerId();
    const QString context = m_controller->contextId();
    const QString channel = m_controller->channel();
    qInfo().noquote() << QStringLiteral("INGE_DOCK_COMMAND generation=%1 command=%2 owner=%3 channel=%4")
                             .arg(generation).arg(command, owner, channel);

    if (channel == QLatin1String("qml")) {
        emit qmlCommand(owner, context, command, dispatchId);
        return true;
    }

    QJsonObject payload;
    payload.insert(QStringLiteral("ownerId"), owner);
    payload.insert(QStringLiteral("contextId"), context);
    payload.insert(QStringLiteral("command"), command);
    payload.insert(QStringLiteral("dispatchId"), dispatchId);
    payload.insert(QStringLiteral("generation"), generation);
    if (!deliverNative(channel, QString::fromUtf8(QJsonDocument(payload).toJson(QJsonDocument::Compact)))) {
        if (m_inFlightId == dispatchId)
            release(QStringLiteral("delivery-failed"));
        return false;
    }
    return true;
}

bool DockCommandRouter::dispatchGlobal(const QString &capabilityId)
{
    if (!m_controller || capabilityId != kInGeCoreCapability || !m_controller->ingeCoreAvailable()) {
        qWarning().noquote() << QStringLiteral("INGE_DOCK_INVALID reason=capability-unavailable capability=%1")
                                    .arg(capabilityId);
        return false;
    }
    qInfo().noquote() << QStringLiteral("INGE_DOCK_COMMAND generation=%1 command=%2 owner=global")
                             .arg(m_controller->generation()).arg(capabilityId);
    emit globalCapabilityRequested(capabilityId);
    return true;
}

void DockCommandRouter::complete(const QString &dispatchId)
{
    if (!dispatchId.isEmpty() && dispatchId == m_inFlightId)
        release(QStringLiteral("done"));
}

void DockCommandRouter::completeJson(const QString &json)
{
    const QJsonDocument document = QJsonDocument::fromJson(json.toUtf8());
    if (!document.isObject())
        return;
    complete(document.object().value(QStringLiteral("dispatchId")).toString());
}

void DockCommandRouter::release(const QString &reason)
{
    if (m_inFlightId.isEmpty())
        return;
    if (reason != QLatin1String("done"))
        qInfo().noquote() << QStringLiteral("INGE_DOCK_COMMAND released=%1 command=%2").arg(reason, m_inFlightCommand);
    m_releaseTimer.stop();
    m_inFlightId.clear();
    m_inFlightCommand.clear();
    emit busyChanged();
}

bool DockCommandRouter::deliverNative(const QString &channel, const QString &payload)
{
#ifdef Q_OS_ANDROID
    const QJniObject javaChannel = QJniObject::fromString(channel);
    const QJniObject javaPayload = QJniObject::fromString(payload);
    const jboolean accepted = QJniObject::callStaticMethod<jboolean>(
        kQtActivityClass, "deliverContextCommand", "(Ljava/lang/String;Ljava/lang/String;)Z",
        javaChannel.object<jstring>(), javaPayload.object<jstring>());
    QJniEnvironment env;
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        return false;
    }
    return accepted;
#else
    Q_UNUSED(channel)
    Q_UNUSED(payload)
    Q_UNUSED(kQtActivityClass)
    return false;
#endif
}

#ifdef Q_OS_ANDROID
extern "C" JNIEXPORT void JNICALL
Java_com_ingema_ingeplus_InGeQtActivity_nativeDockComplete(JNIEnv *, jclass, jstring json)
{
    const QPointer<DockCommandRouter> router = g_router;
    if (!router || !json)
        return;
    const QString payload = QJniObject(json).toString().left(512);
    QMetaObject::invokeMethod(router, [router, payload]() {
        if (router)
            router->completeJson(payload);
    }, Qt::QueuedConnection);
}
#endif
