#include "DockContextController.h"

#include <QDebug>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPointer>
#include <QSet>

#include <algorithm>

#ifdef Q_OS_ANDROID
#include <QJniEnvironment>
#include <QJniObject>
#include <jni.h>
#endif

namespace {
QPointer<DockContextController> g_controller;
constexpr int kMaxActions = 8;
// Nested levels below the capsule (action -> sub -> sub-sub) and entries per
// level. The view shows one branch at a time, so these bound data, not pixels.
constexpr int kMaxDepth = 3;
constexpr int kMaxChildren = 10;
constexpr int kMaxPayload = 16384;
constexpr int kDefaultPriority = 100;
const char *const kQtActivityClass = "com/ingema/ingeplus/InGeQtActivity";

bool isNativeChannel(const QString &channel)
{
    return channel == QLatin1String("flutter") || channel == QLatin1String("earth");
}
} // namespace

DockContextController::DockContextController(QObject *parent)
    : QObject(parent)
{
    g_controller = this;
}

DockContextController::~DockContextController()
{
    if (g_controller == this)
        g_controller.clear();
}

DockContextController *DockContextController::instance()
{
    return g_controller.data();
}

void DockContextController::setForegroundOwner(const QString &ownerId)
{
    const QString owner = ownerId.trimmed();
    if (owner == m_foregroundOwner)
        return;
    m_foregroundOwner = owner;
    // Empty owner is the shell's explicit destination without a dock.
    // A named owner without a snapshot is a handoff, never an empty frame.
    if (owner.isEmpty()) {
        if (!m_active.isEmpty() || m_transitionPending)
            activate(Snapshot());
    } else if (m_latestByOwner.contains(owner)) {
        const Snapshot next = m_latestByOwner.value(owner);
        if (m_transitionPending || !m_active.sameAs(next))
            activate(next);
    } else {
        beginTransition();
    }
    emit foregroundOwnerChanged();
}

void DockContextController::beginTransition()
{
    if (m_transitionPending)
        return;
    m_transitionPending = true;
    ++m_generation; // Invalidates a press that began before the handoff.
    emit transitionPendingChanged();
    emit contextChanged();
}

void DockContextController::setIngeCoreAvailable(bool available)
{
    if (m_ingeCoreAvailable == available)
        return;
    m_ingeCoreAvailable = available;
    emit capabilitiesChanged();
}

bool DockContextController::buildSnapshot(const QString &ownerId, const QString &contextId,
                                          const QVariantList &actions, const QString &channel,
                                          Snapshot *out) const
{
    const QString owner = ownerId.trimmed();
    const QString context = contextId.trimmed();
    if (owner.isEmpty() || context.isEmpty() || channel.isEmpty()) {
        qWarning().noquote() << QStringLiteral("INGE_DOCK_INVALID reason=missing-owner-or-context owner=%1 context=%2")
                                    .arg(owner, context);
        return false;
    }

    QSet<QString> ids;
    out->ownerId = owner;
    out->contextId = context;
    out->channel = channel;
    out->actions = normalizeActions(actions, 0, owner, context, &ids);
    return true;
}

QVariantList DockContextController::normalizeActions(const QVariantList &actions, int depth,
                                                     const QString &owner, const QString &context,
                                                     QSet<QString> *ids) const
{
    const int limit = depth == 0 ? kMaxActions : kMaxChildren;
    QVariantList normalized;
    for (const QVariant &value : actions) {
        const QVariantMap in = value.toMap();
        const QString id = in.value(QStringLiteral("id")).toString().trimmed();
        const QString command = in.value(QStringLiteral("command")).toString().trimmed();
        QVariantList children;
        const QVariantList rawChildren = in.value(QStringLiteral("children")).toList();
        if (!rawChildren.isEmpty()) {
            if (depth < kMaxDepth)
                children = normalizeActions(rawChildren, depth + 1, owner, context, ids);
            else
                qWarning().noquote() << QStringLiteral("INGE_DOCK_INVALID reason=depth owner=%1 context=%2 action=%3")
                                            .arg(owner, context, id);
        }
        // A node needs an id and something to do: run a command or open children.
        if (id.isEmpty() || ids->contains(id) || (command.isEmpty() && children.isEmpty())) {
            qWarning().noquote() << QStringLiteral("INGE_DOCK_INVALID reason=action owner=%1 context=%2 action=%3")
                                        .arg(owner, context, id);
            continue;
        }
        ids->insert(id);

        // Only semantic fields cross this boundary; geometry/theme keys are dropped.
        QVariantMap action;
        action.insert(QStringLiteral("id"), id);
        action.insert(QStringLiteral("command"), command);
        action.insert(QStringLiteral("label"), in.value(QStringLiteral("label"), id).toString());
        action.insert(QStringLiteral("icon"), in.value(QStringLiteral("icon")).toString());
        action.insert(QStringLiteral("enabled"), in.contains(QStringLiteral("enabled"))
                                                     ? in.value(QStringLiteral("enabled")).toBool() : true);
        action.insert(QStringLiteral("visible"), in.contains(QStringLiteral("visible"))
                                                     ? in.value(QStringLiteral("visible")).toBool() : true);
        // `checked` is accepted as an alias of `selected` for menu entries.
        action.insert(QStringLiteral("selected"), in.value(QStringLiteral("selected")).toBool()
                                                      || in.value(QStringLiteral("checked")).toBool());
        action.insert(QStringLiteral("badge"), in.value(QStringLiteral("badge")).toString());
        bool priorityOk = false;
        const int priority = in.value(QStringLiteral("priority")).toInt(&priorityOk);
        action.insert(QStringLiteral("priority"), priorityOk ? priority : kDefaultPriority);
        action.insert(QStringLiteral("repeatable"), in.value(QStringLiteral("repeatable")).toBool());
        action.insert(QStringLiteral("destructive"), in.value(QStringLiteral("destructive")).toBool());
        action.insert(QStringLiteral("children"), children);
        normalized.append(action);
        if (normalized.size() >= limit)
            break;
    }

    // Capsule order follows priority; menu entries keep the published order.
    if (depth == 0) {
        std::stable_sort(normalized.begin(), normalized.end(), [](const QVariant &a, const QVariant &b) {
            return a.toMap().value(QStringLiteral("priority")).toInt()
                 < b.toMap().value(QStringLiteral("priority")).toInt();
        });
    }
    return normalized;
}

void DockContextController::activate(const Snapshot &snapshot)
{
    // A backdrop frame belongs to one owner; a different owner never sees it
    // (Earth -> Home, Home -> Renditions share nothing).
    if (!m_nativeBackdrop.isEmpty()
        && (snapshot.channel != m_nativeBackdropChannel || snapshot.ownerId != m_nativeBackdropOwner)) {
        m_nativeBackdrop.clear();
        m_nativeBackdropChannel.clear();
        m_nativeBackdropOwner.clear();
        m_nativeBackdropLuma = -1.0;
        emit nativeBackdropChanged();
    }
    // Single assignment + single notification: the view only ever observes
    // complete snapshots.
    m_active = snapshot;
    const bool wasPending = m_transitionPending;
    m_transitionPending = false;
    ++m_generation;
    qInfo().noquote() << QStringLiteral("INGE_DOCK_CONTEXT owner=%1 context=%2 generation=%3 actions=%4 channel=%5")
                             .arg(m_active.ownerId.isEmpty() ? QStringLiteral("-") : m_active.ownerId,
                                  m_active.contextId.isEmpty() ? QStringLiteral("-") : m_active.contextId)
                             .arg(m_generation)
                             .arg(m_active.actions.size())
                             .arg(m_active.channel.isEmpty() ? QStringLiteral("-") : m_active.channel);
    emit contextChanged();
    if (wasPending)
        emit transitionPendingChanged();
}

bool DockContextController::publishContext(const QString &ownerId, const QString &contextId,
                                           const QVariantList &actions, const QString &channel)
{
    Snapshot snapshot;
    if (!buildSnapshot(ownerId, contextId, actions, channel, &snapshot))
        return false;
    m_latestByOwner.insert(snapshot.ownerId, snapshot);
    // A background owner keeps its latest snapshot; it becomes active only
    // when the shell brings that owner to the foreground.
    const bool foreground = snapshot.ownerId == m_foregroundOwner;
    if (foreground && !m_commitQueued
            && (m_transitionPending || !m_active.sameAs(snapshot))) {
        m_commitQueued = true;
        // One event-loop commit: repeated publications replace the cached
        // snapshot, never expose intermediate construction states.
        QMetaObject::invokeMethod(this, [this]() {
            m_commitQueued = false;
            const auto it = m_latestByOwner.constFind(m_foregroundOwner);
            if (it != m_latestByOwner.constEnd()
                    && (m_transitionPending || !m_active.sameAs(it.value())))
                activate(it.value());
        }, Qt::QueuedConnection);
    }
    return true;
}

bool DockContextController::clearContext(const QString &ownerId)
{
    const QString owner = ownerId.trimmed();
    if (owner.isEmpty())
        return false;
    m_latestByOwner.remove(owner);
    for (auto it = m_preloaded.begin(); it != m_preloaded.end();) {
        if (it.value().ownerId == owner)
            it = m_preloaded.erase(it);
        else
            ++it;
    }
    if (m_transitionPending && m_foregroundOwner == owner && m_active.ownerId != owner) {
        // The destination explicitly withdrew its context: finish the handoff.
        activate(Snapshot());
        return true;
    }
    if (m_active.ownerId != owner) {
        if (!m_active.isEmpty())
            qInfo().noquote() << QStringLiteral("INGE_DOCK_STALE clear owner=%1 active=%2").arg(owner, m_active.ownerId);
        return false;
    }
    if (m_foregroundOwner != owner)
        return true; // Departing owner's teardown must not erase the held view.
    if (m_transitionPending)
        return true; // A duplicate teardown must not resolve the queued handoff.
    beginTransition();
    // Loader destruction can precede the foreground binding in the same turn.
    // Resolve once after that turn, with no timer or polling.
    QMetaObject::invokeMethod(this, [this, owner]() {
        if (m_foregroundOwner == owner && !m_latestByOwner.contains(owner))
            activate(Snapshot());
    }, Qt::QueuedConnection);
    return true;
}

QString DockContextController::preloadKey(const QString &ownerId, const QString &contextId)
{
    return ownerId.trimmed() + QLatin1Char('\n') + contextId.trimmed();
}

bool DockContextController::preloadContext(const QString &ownerId, const QString &contextId,
                                           const QVariantList &actions, const QString &channel)
{
    Snapshot snapshot;
    if (!buildSnapshot(ownerId, contextId, actions, channel, &snapshot))
        return false;
    m_preloaded.insert(preloadKey(snapshot.ownerId, snapshot.contextId), snapshot);
    return true;
}

bool DockContextController::activatePreloadedContext(const QString &ownerId, const QString &contextId)
{
    const auto it = m_preloaded.constFind(preloadKey(ownerId, contextId));
    if (it == m_preloaded.constEnd()) {
        qWarning().noquote() << QStringLiteral("INGE_DOCK_INVALID reason=no-preload owner=%1 context=%2")
                                    .arg(ownerId, contextId);
        return false;
    }
    const Snapshot snapshot = it.value();
    m_latestByOwner.insert(snapshot.ownerId, snapshot);
    const bool foreground = snapshot.ownerId == m_foregroundOwner;
    if (foreground && (m_transitionPending || !m_active.sameAs(snapshot)))
        activate(snapshot);
    return true;
}

namespace {
QVariantMap findAvailableAction(const QVariantList &actions, const QString &actionId)
{
    for (const QVariant &value : actions) {
        const QVariantMap action = value.toMap();
        if (action.value(QStringLiteral("id")).toString() == actionId)
            return action;
        // A branch hidden or disabled as a whole hides its descendants too.
        if (!action.value(QStringLiteral("visible")).toBool()
                || !action.value(QStringLiteral("enabled")).toBool())
            continue;
        const QVariantMap nested = findAvailableAction(
            action.value(QStringLiteral("children")).toList(), actionId);
        if (!nested.isEmpty())
            return nested;
    }
    return {};
}
} // namespace

QVariantMap DockContextController::actionById(const QString &actionId) const
{
    return findAvailableAction(m_active.actions, actionId);
}

bool DockContextController::publishJson(const QString &channel, const QString &json)
{
    if (!isNativeChannel(channel) || json.size() > kMaxPayload)
        return false;
    const QJsonDocument document = QJsonDocument::fromJson(json.toUtf8());
    if (!document.isObject()) {
        qWarning().noquote() << QStringLiteral("INGE_DOCK_INVALID reason=json channel=%1").arg(channel);
        return false;
    }
    const QVariantMap payload = document.object().toVariantMap();
    const QString owner = payload.value(QStringLiteral("ownerId")).toString();
    const QString context = payload.value(QStringLiteral("contextId")).toString();
    const QString mode = payload.value(QStringLiteral("mode")).toString();
    const QVariantList actions = payload.value(QStringLiteral("actions")).toList();
    if (mode == QLatin1String("preload"))
        return preloadContext(owner, context, actions, channel);
    if (mode == QLatin1String("activatePreloaded"))
        return activatePreloadedContext(owner, context);
    return publishContext(owner, context, actions, channel);
}

bool DockContextController::clearFromChannel(const QString &channel, const QString &ownerId)
{
    if (!isNativeChannel(channel))
        return false;
    // A surface of one framework cannot clear an active context owned by another.
    if (m_active.ownerId == ownerId && m_active.channel != channel)
        return false;
    return clearContext(ownerId);
}

void DockContextController::setNativeGeometry(float left, float width, float height,
                                             float bottom, float coreSize, float gap,
                                             float searchWidth, float searchHeight, float searchGap)
{
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>(kQtActivityClass, "setContextDockGeometry", "(FFFFFFFFF)V",
        jfloat(left), jfloat(width), jfloat(height), jfloat(bottom), jfloat(coreSize),
        jfloat(gap), jfloat(searchWidth), jfloat(searchHeight), jfloat(searchGap));
    QJniEnvironment env;
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        qWarning() << "INGE_DOCK_NATIVE_GEOMETRY_FAILED";
    }
#else
    Q_UNUSED(left) Q_UNUSED(width) Q_UNUSED(height) Q_UNUSED(bottom)
    Q_UNUSED(coreSize) Q_UNUSED(gap) Q_UNUSED(searchWidth) Q_UNUSED(searchHeight) Q_UNUSED(searchGap)
#endif
}

void DockContextController::setNativeBand(int pixels)
{
    const int band = std::max(0, pixels);
    if (band == m_nativeBand)
        return;
    m_nativeBand = band;
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>(kQtActivityClass, "setContextDockBand", "(I)V",
                                       static_cast<jint>(band));
    QJniEnvironment env;
    if (env->ExceptionCheck())
        env->ExceptionClear();
#else
    Q_UNUSED(kQtActivityClass)
#endif
}

#ifdef Q_OS_ANDROID
extern "C" JNIEXPORT void JNICALL
Java_com_ingema_ingeplus_InGeQtActivity_nativeDockPublish(JNIEnv *, jclass, jstring channel, jstring json)
{
    const QPointer<DockContextController> controller = g_controller;
    if (!controller || !channel || !json)
        return;
    const QString channelText = QJniObject(channel).toString();
    const QString payload = QJniObject(json).toString();
    if (payload.size() > kMaxPayload)
        return;
    QMetaObject::invokeMethod(controller, [controller, channelText, payload]() {
        if (controller)
            controller->publishJson(channelText, payload);
    }, Qt::QueuedConnection);
}

extern "C" JNIEXPORT void JNICALL
Java_com_ingema_ingeplus_InGeQtActivity_nativeDockClear(JNIEnv *, jclass, jstring channel, jstring ownerId)
{
    const QPointer<DockContextController> controller = g_controller;
    if (!controller || !channel || !ownerId)
        return;
    const QString channelText = QJniObject(channel).toString();
    const QString owner = QJniObject(ownerId).toString().left(64);
    QMetaObject::invokeMethod(controller, [controller, channelText, owner]() {
        if (controller)
            controller->clearFromChannel(channelText, owner);
    }, Qt::QueuedConnection);
}
#endif

void DockContextController::setNativeBackdrop(const QString &channel, const QString &json)
{
    // Only the framework that owns the active snapshot may feed the glass.
    if (channel != m_active.channel || json.size() > 65536)
        return;
    const QJsonObject payload = QJsonDocument::fromJson(json.toUtf8()).object();
    // Late captures of a previous owner are stale and dropped.
    const QString owner = payload.value(QStringLiteral("owner")).toString();
    if (!owner.isEmpty() && owner != m_active.ownerId)
        return;
    const QString image = payload.value(QStringLiteral("image")).toString();
    if (!image.startsWith(QLatin1String("data:image/jpeg;base64,"))
        && !image.startsWith(QLatin1String("data:image/png;base64,")))
        return;
    const qreal luma = payload.value(QStringLiteral("luma")).toDouble(-1.0);
    if (image == m_nativeBackdrop && qFuzzyCompare(luma + 2.0, m_nativeBackdropLuma + 2.0))
        return;
    m_nativeBackdrop = image;
    const bool firstFrame = m_nativeBackdropOwner != m_active.ownerId;
    m_nativeBackdropChannel = channel;
    m_nativeBackdropOwner = m_active.ownerId;
    m_nativeBackdropLuma = luma;
    if (firstFrame)
        qInfo().noquote() << QStringLiteral("INGE_DOCK_BACKDROP_STATE owner=%1 channel=%2 state=ready")
                                 .arg(m_nativeBackdropOwner, channel);
    emit nativeBackdropChanged();
}

#ifdef Q_OS_ANDROID
extern "C" JNIEXPORT void JNICALL
Java_com_ingema_ingeplus_InGeQtActivity_nativeDockBackdrop(JNIEnv *, jclass, jstring channel, jstring json)
{
    const QPointer<DockContextController> controller = g_controller;
    if (!controller || !channel || !json)
        return;
    const QString source = QJniObject(channel).toString();
    const QString payload = QJniObject(json).toString();
    if (payload.size() > 65536)
        return;
    QMetaObject::invokeMethod(controller, [controller, source, payload]() {
        if (controller)
            controller->setNativeBackdrop(source, payload);
    }, Qt::QueuedConnection);
}
#endif
