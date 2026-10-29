#pragma once

#include <QObject>
#include <QTimer>
#ifdef Q_OS_ANDROID
#include <QJniEnvironment>
#include <QJniObject>
#endif

// Huella o rostro del sistema para QML («biometric»): disponibilidad y una
// verificación con BiometricPrompt (InGeBiometricActivity). El resultado se
// obtiene sondeando InGeQtActivity; no se guardan secretos aquí.
class BiometricGate : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
public:
    explicit BiometricGate(QObject *parent = nullptr) : QObject(parent)
    {
        m_poll.setInterval(150);
        connect(&m_poll, &QTimer::timeout, this, &BiometricGate::poll);
    }

    bool available() const
    {
#ifdef Q_OS_ANDROID
        const jboolean ok = QJniObject::callStaticMethod<jboolean>(
            "com/ingema/ingeplus/InGeQtActivity", "qtBiometricAvailable", "()Z");
        QJniEnvironment env;
        if (env->ExceptionCheck()) { env->ExceptionClear(); return false; }
        return ok;
#else
        return false;
#endif
    }
    bool busy() const { return m_busy; }

    Q_INVOKABLE void refresh() { emit availableChanged(); }

    Q_INVOKABLE void authenticate()
    {
        if (m_busy) return;
#ifdef Q_OS_ANDROID
        QJniObject::callStaticMethod<void>("com/ingema/ingeplus/InGeQtActivity", "qtStartBiometric", "()V");
        QJniEnvironment env;
        if (env->ExceptionCheck()) { env->ExceptionClear(); emit finished(false); return; }
        m_busy = true;
        m_ticks = 0;
        emit busyChanged();
        m_poll.start();
#else
        emit finished(false);
#endif
    }

signals:
    void availableChanged();
    void busyChanged();
    void finished(bool ok);

private:
    void poll()
    {
#ifdef Q_OS_ANDROID
        const jint state = QJniObject::callStaticMethod<jint>(
            "com/ingema/ingeplus/InGeQtActivity", "qtBiometricState", "()I");
        QJniEnvironment env;
        if (env->ExceptionCheck()) env->ExceptionClear();
        const bool timedOut = ++m_ticks > 600;            // 90 s máximo
        if (state < 0 && !timedOut) return;
        m_poll.stop();
        QJniObject::callStaticMethod<void>("com/ingema/ingeplus/InGeQtActivity", "qtBiometricConsume", "()V");
        if (env->ExceptionCheck()) env->ExceptionClear();
        m_busy = false;
        emit busyChanged();
        emit finished(state == 1);
#endif
    }

    QTimer m_poll;
    bool m_busy = false;
    int m_ticks = 0;
};
