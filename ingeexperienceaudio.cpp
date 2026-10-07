#include "ingeexperienceaudio.h"

#include <QtGlobal>

#ifdef Q_OS_ANDROID
#include <QJniObject>
#include <QCoreApplication>
#endif

namespace {
double clamped(double value) { return qBound(0.0, value, 1.0); }
}

InGeExperienceAudio::InGeExperienceAudio(QObject *parent)
    : QObject(parent)
{
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>(
        "com/ingema/ingeplus/InGeExperienceAudio",
        "initialize",
        "(Landroid/content/Context;)V",
        QNativeInterface::QAndroidApplication::context());
    applyVolumes();
#endif
}

InGeExperienceAudio::~InGeExperienceAudio()
{
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>(
        "com/ingema/ingeplus/InGeExperienceAudio", "release", "()V");
#endif
}

bool InGeExperienceAudio::available() const
{
#ifdef Q_OS_ANDROID
    return true;
#else
    return false;
#endif
}

void InGeExperienceAudio::setAmbientPlaying(bool value)
{
    if (m_ambientPlaying == value) return;
    m_ambientPlaying = value;
    emit ambientPlayingChanged();
}

void InGeExperienceAudio::setNarrationPlaying(bool value)
{
    if (m_narrationPlaying == value) return;
    m_narrationPlaying = value;
    emit narrationPlayingChanged();
}

void InGeExperienceAudio::setAmbientVolume(double value)
{
    value = clamped(value);
    if (qFuzzyCompare(m_ambientVolume, value)) return;
    m_ambientVolume = value;
    applyVolumes();
    emit volumesChanged();
}

void InGeExperienceAudio::setNarrationVolume(double value)
{
    value = clamped(value);
    if (qFuzzyCompare(m_narrationVolume, value)) return;
    m_narrationVolume = value;
    applyVolumes();
    emit volumesChanged();
}

void InGeExperienceAudio::setSfxVolume(double value)
{
    value = clamped(value);
    if (qFuzzyCompare(m_sfxVolume, value)) return;
    m_sfxVolume = value;
    applyVolumes();
    emit volumesChanged();
}

void InGeExperienceAudio::applyVolumes()
{
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>(
        "com/ingema/ingeplus/InGeExperienceAudio", "setVolumes", "(FFF)V",
        static_cast<jfloat>(m_ambientVolume),
        static_cast<jfloat>(m_narrationVolume),
        static_cast<jfloat>(m_sfxVolume));
#endif
}

bool InGeExperienceAudio::hasBundledNarration(const QString &languageCode) const
{
#ifdef Q_OS_ANDROID
    const QJniObject jLang = QJniObject::fromString(languageCode);
    return QJniObject::callStaticMethod<jboolean>(
        "com/ingema/ingeplus/InGeExperienceAudio", "hasBundledNarration",
        "(Landroid/content/Context;Ljava/lang/String;)Z",
        QNativeInterface::QAndroidApplication::context(),
        jLang.object<jstring>());
#else
    Q_UNUSED(languageCode)
    return false;
#endif
}

void InGeExperienceAudio::playAmbient()
{
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>(
        "com/ingema/ingeplus/InGeExperienceAudio", "playAmbient",
        "(Landroid/content/Context;F)V",
        QNativeInterface::QAndroidApplication::context(),
        static_cast<jfloat>(m_ambientVolume));
    setAmbientPlaying(true);
#endif
}

void InGeExperienceAudio::stopAmbient(int fadeMs)
{
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>(
        "com/ingema/ingeplus/InGeExperienceAudio", "stopAmbient", "(I)V",
        static_cast<jint>(qMax(0, fadeMs)));
#endif
    setAmbientPlaying(false);
}

bool InGeExperienceAudio::playNarration(int sceneIndex, const QString &languageCode)
{
#ifdef Q_OS_ANDROID
    const QJniObject jLang = QJniObject::fromString(languageCode);
    const bool ok = QJniObject::callStaticMethod<jboolean>(
        "com/ingema/ingeplus/InGeExperienceAudio", "playNarration",
        "(Landroid/content/Context;ILjava/lang/String;F)Z",
        QNativeInterface::QAndroidApplication::context(),
        static_cast<jint>(sceneIndex), jLang.object<jstring>(),
        static_cast<jfloat>(m_narrationVolume));
    setNarrationPlaying(ok);
    return ok;
#else
    Q_UNUSED(sceneIndex)
    Q_UNUSED(languageCode)
    return false;
#endif
}

void InGeExperienceAudio::stopNarration()
{
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>(
        "com/ingema/ingeplus/InGeExperienceAudio", "stopNarration", "()V");
#endif
    setNarrationPlaying(false);
}

void InGeExperienceAudio::playSfx(const QString &name, double gain)
{
#ifdef Q_OS_ANDROID
    const QJniObject jName = QJniObject::fromString(name);
    QJniObject::callStaticMethod<void>(
        "com/ingema/ingeplus/InGeExperienceAudio", "playSfx",
        "(Landroid/content/Context;Ljava/lang/String;F)V",
        QNativeInterface::QAndroidApplication::context(),
        jName.object<jstring>(), static_cast<jfloat>(clamped(gain)));
#else
    Q_UNUSED(name)
    Q_UNUSED(gain)
#endif
}

void InGeExperienceAudio::stopAll()
{
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>(
        "com/ingema/ingeplus/InGeExperienceAudio", "stopAll", "()V");
#endif
    setAmbientPlaying(false);
    setNarrationPlaying(false);
}
