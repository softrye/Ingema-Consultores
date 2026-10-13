#include "flowhaptics.h"

#include <QCoreApplication>

#ifdef Q_OS_ANDROID
#include <QJniEnvironment>
#include <QJniObject>
#include <QtCore/qnativeinterface.h>
#endif

namespace {

struct HapticPulse
{
    int durationMs;
    int amplitude;
};

HapticPulse pulseForIntent(const QString &intent)
{
    const QString semanticIntent = intent.trimmed().toLower();
    if (semanticIntent == QStringLiteral("light"))
        return {18, 70};
    if (semanticIntent == QStringLiteral("medium"))
        return {28, 120};
    if (semanticIntent == QStringLiteral("strong"))
        return {42, 180};
    if (semanticIntent == QStringLiteral("success"))
        return {34, 145};
    if (semanticIntent == QStringLiteral("warning"))
        return {44, 185};
    if (semanticIntent == QStringLiteral("error"))
        return {56, 220};
    return {12, 50};
}

#ifdef Q_OS_ANDROID
bool clearJniException()
{
    QJniEnvironment environment;
    if (!environment->ExceptionCheck())
        return false;
    environment->ExceptionClear();
    return true;
}

QJniObject androidVibrator()
{
    const QJniObject context = QNativeInterface::QAndroidApplication::context();
    if (!context.isValid())
        return {};

    const QJniObject serviceName =
        QJniObject::fromString(QStringLiteral("vibrator"));
    QJniObject vibrator = context.callObjectMethod(
        "getSystemService",
        "(Ljava/lang/String;)Ljava/lang/Object;",
        serviceName.object<jstring>());
    if (clearJniException())
        return {};
    return vibrator;
}
#endif

} // namespace

FlowHaptics::FlowHaptics(QObject *parent)
    : QObject(parent)
{
}

bool FlowHaptics::enabled() const
{
    return m_enabled;
}

void FlowHaptics::setEnabled(bool enabled)
{
    if (m_enabled == enabled)
        return;
    m_enabled = enabled;
    emit enabledChanged();
}

bool FlowHaptics::supported() const
{
#ifdef Q_OS_ANDROID
    const QJniObject vibrator = androidVibrator();
    if (!vibrator.isValid())
        return false;
    const jboolean hasVibrator =
        vibrator.callMethod<jboolean>("hasVibrator", "()Z");
    if (clearJniException())
        return false;
    return hasVibrator == JNI_TRUE;
#else
    return false;
#endif
}

bool FlowHaptics::trigger(const QString &intent)
{
    if (!m_enabled)
        return false;

#ifdef Q_OS_ANDROID
    const QJniObject vibrator = androidVibrator();
    if (!vibrator.isValid())
        return false;

    const jboolean hasVibrator =
        vibrator.callMethod<jboolean>("hasVibrator", "()Z");
    if (clearJniException() || hasVibrator != JNI_TRUE)
        return false;

    const HapticPulse pulse = pulseForIntent(intent);
    const jint sdkVersion =
        QJniObject::getStaticField<jint>("android/os/Build$VERSION", "SDK_INT");
    if (clearJniException())
        return false;

    if (sdkVersion >= 26) {
        const QJniObject effect = QJniObject::callStaticObjectMethod(
            "android/os/VibrationEffect",
            "createOneShot",
            "(JI)Landroid/os/VibrationEffect;",
            static_cast<jlong>(pulse.durationMs),
            static_cast<jint>(pulse.amplitude));
        if (!effect.isValid() || clearJniException())
            return false;

        vibrator.callMethod<void>(
            "vibrate",
            "(Landroid/os/VibrationEffect;)V",
            effect.object<jobject>());
    } else {
        vibrator.callMethod<void>(
            "vibrate",
            "(J)V",
            static_cast<jlong>(pulse.durationMs));
    }

    return !clearJniException();
#else
    Q_UNUSED(intent)
    return false;
#endif
}
