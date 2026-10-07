#include "ingenarrator.h"

#ifdef Q_OS_ANDROID
#include <QJniObject>
#include <QCoreApplication>
#endif

InGeNarrator::InGeNarrator(QObject *parent)
    : QObject(parent)
{
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>(
        "com/ingema/ingeplus/InGeNarrator",
        "initialize",
        "(Landroid/content/Context;)V",
        QNativeInterface::QAndroidApplication::context());
#endif
}

bool InGeNarrator::available() const
{
#ifdef Q_OS_ANDROID
    return true;
#else
    return false;
#endif
}

void InGeNarrator::setSpeaking(bool value)
{
    if (m_speaking == value) return;
    m_speaking = value;
    emit speakingChanged();
}

void InGeNarrator::speak(const QString &text, const QString &localeTag,
                         double rate, double pitch)
{
    if (text.trimmed().isEmpty()) return;
#ifdef Q_OS_ANDROID
    const QJniObject jText = QJniObject::fromString(text);
    const QJniObject jLocale = QJniObject::fromString(localeTag);
    QJniObject::callStaticMethod<void>(
        "com/ingema/ingeplus/InGeNarrator",
        "speak",
        "(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;FF)V",
        QNativeInterface::QAndroidApplication::context(),
        jText.object<jstring>(),
        jLocale.object<jstring>(),
        static_cast<jfloat>(rate),
        static_cast<jfloat>(pitch));
    setSpeaking(true);
#else
    Q_UNUSED(localeTag)
    Q_UNUSED(rate)
    Q_UNUSED(pitch)
#endif
}

void InGeNarrator::stop()
{
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>(
        "com/ingema/ingeplus/InGeNarrator",
        "stop",
        "()V");
#endif
    setSpeaking(false);
}
