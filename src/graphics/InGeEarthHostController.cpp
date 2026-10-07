#include "InGeEarthHostController.h"

#include <QMetaObject>
#include <QPointer>
#include <QStringList>

#ifdef Q_OS_ANDROID
#include <QJniEnvironment>
#include <QJniObject>
#include <jni.h>
#endif

namespace {
constexpr auto kQtActivityClass = "com/ingema/ingeplus/InGeQtActivity";
QPointer<InGeEarthHostController> g_earthHostController;
}

InGeEarthHostController::InGeEarthHostController(QObject *parent)
    : QObject(parent)
{
    g_earthHostController = this;
}

bool InGeEarthHostController::supported() const
{
#ifdef Q_OS_ANDROID
    return QJniObject::callStaticMethod<jboolean>(
        kQtActivityClass, "isEarthAvailable", "()Z");
#else
    return false;
#endif
}

bool InGeEarthHostController::active() const { return m_active; }
QString InGeEarthHostController::state() const { return m_state; }

bool InGeEarthHostController::openEarth(
    const QString &, double, double, const QString &)
{
#ifdef Q_OS_ANDROID
    const bool opened = QJniObject::callStaticMethod<jboolean>(
        kQtActivityClass, "setDirectEarthVisible", "(Z)Z", JNI_TRUE);
    QJniEnvironment env;
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        return false;
    }
    if (opened) {
        m_active = true;
        m_state = QStringLiteral("ACTIVE");
        emit stateChanged();
    }
    return opened;
#else
    return false;
#endif
}

bool InGeEarthHostController::focusEarth(double latitude, double longitude,
                                         double altitude,
                                         const QString &label)
{
#ifdef Q_OS_ANDROID
    const QJniObject javaLabel = QJniObject::fromString(label.left(80));
    const bool accepted = QJniObject::callStaticMethod<jboolean>(
        kQtActivityClass, "focusEarthCoordinate",
        "(DDDLjava/lang/String;)Z", latitude, longitude, altitude,
        javaLabel.object<jstring>());
    QJniEnvironment env;
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        return false;
    }
    return accepted;
#else
    Q_UNUSED(latitude)
    Q_UNUSED(longitude)
    Q_UNUSED(altitude)
    Q_UNUSED(label)
    return false;
#endif
}

void InGeEarthHostController::closeEarth()
{
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<jboolean>(
        kQtActivityClass, "setDirectEarthVisible", "(Z)Z", JNI_FALSE);
#endif
    m_active = false;
    m_state = QStringLiteral("CLOSED");
    emit stateChanged();
}

#ifdef Q_OS_ANDROID
extern "C" JNIEXPORT jboolean JNICALL
Java_com_ingema_ingeplus_InGeQtActivity_nativeRequestEarthBackToHome(
    JNIEnv *, jclass)
{
    const QPointer<InGeEarthHostController> controller = g_earthHostController;
    if (!controller)
        return JNI_FALSE;

    const bool queued = QMetaObject::invokeMethod(
        controller,
        [controller]() {
            if (controller)
                controller->closeEarth();
        },
        Qt::QueuedConnection);
    return queued ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_ingema_ingeplus_InGeQtActivity_nativeUseEarthPointInCalicata(
    JNIEnv *, jclass, jdouble latitude, jdouble longitude, jdouble altitude,
    jdouble accuracy, jstring timestamp, jstring source)
{
    const QPointer<InGeEarthHostController> controller = g_earthHostController;
    if (!controller)
        return JNI_FALSE;

    const QString timestampText = timestamp
        ? QJniObject(timestamp).toString() : QString();
    const QString sourceText = source
        ? QJniObject(source).toString() : QStringLiteral("InGe Earth");
    const bool queued = QMetaObject::invokeMethod(
        controller,
        [controller, latitude, longitude, altitude, accuracy,
         timestampText, sourceText]() {
            if (!controller)
                return;
            emit controller->coordinateForCalicata(
                latitude, longitude, altitude, accuracy,
                timestampText, sourceText);
            controller->closeEarth();
        },
        Qt::QueuedConnection);
    return queued ? JNI_TRUE : JNI_FALSE;
}
#endif
