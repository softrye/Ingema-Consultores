#pragma once

#include <QElapsedTimer>
#include <QObject>
#include <QString>

// Estado local del acceso (Login V1, 2026-10-12). Persistido con QSettings,
// sin secretos: solo la marca de bienvenida inicial completada, la última
// cuenta autenticada y el nombre de presentación verificado de cada cuenta,
// indexado por userId (nunca derivado del correo).
//
// Una instalación nueva (o datos de la app borrados) no tiene ninguna clave:
// muestra "Welcome to InGe+, Engineer" y la bienvenida tras el primer login.
// Las instalaciones anteriores a esta versión (con datos de sesión o de
// cuentas guardadas) se migran como usuarios recurrentes con la bienvenida
// ya completada, para no mostrarla por una actualización.
class OnboardingState final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool welcomeCompleted READ welcomeCompleted NOTIFY changed)
    Q_PROPERTY(bool returningUser READ returningUser NOTIFY changed)
    Q_PROPERTY(QString lastUserId READ lastUserId NOTIFY changed)
    Q_PROPERTY(QString greetingName READ greetingName NOTIFY changed)
    // Correo verificado del último usuario (no es un secreto; nunca contraseñas).
    Q_PROPERTY(QString lastEmail READ lastEmail NOTIFY changed)
    // Bloqueo de la interfaz autenticada tras 60 s en segundo plano.
    Q_PROPERTY(bool sessionLocked READ sessionLocked NOTIFY sessionLockChanged)

public:
    explicit OnboardingState(QObject *parent = nullptr);

    bool welcomeCompleted() const { return m_welcomeCompleted; }
    bool returningUser() const { return m_returningUser; }
    QString lastUserId() const { return m_lastUserId; }
    // Nombre verificado de la última cuenta autenticada ("" si no hay).
    QString greetingName() const;

    // Cuenta autenticada correctamente. verifiedName vacío conserva el nombre
    // ya verificado de esa misma cuenta; nunca se copia entre cuentas.
    Q_INVOKABLE void recordAuthenticatedUser(const QString &userId,
                                             const QString &verifiedName);
    Q_INVOKABLE QString verifiedNameFor(const QString &userId) const;
    // Get Started en la bienvenida inicial.
    Q_INVOKABLE void completeWelcome();
    QString lastEmail() const;
    Q_INVOKABLE void rememberAccountEmail(const QString &userId, const QString &email);
    Q_INVOKABLE void forgetAccountEmail();

    // Sesión (Home V2): gracia de 60 s desde que la app sale de primer plano.
    // Reloj monotónico mientras vive el proceso; marca UTC persistida para
    // decidir tras la muerte del proceso. Nunca guarda contraseñas ni tokens.
    bool sessionLocked() const { return m_sessionLocked; }
    Q_INVOKABLE void setSessionTracked(bool tracked);
    Q_INVOKABLE bool consumeStartupGrace();
    Q_INVOKABLE void lockSession(const QString &reason);
    Q_INVOKABLE void unlockSession();
    Q_INVOKABLE void endSession();
    void setExternalActivity(bool active);
    void handleApplicationState(Qt::ApplicationState state);

signals:
    void sessionLockChanged();
    void changed();

private:
    void clearBackgroundRecord();
    bool m_sessionTracked = false;
    bool m_sessionLocked = false;
    bool m_externalActivity = false;
    bool m_backgroundExternal = false;
    QElapsedTimer m_backgroundClock;
    void migrateExistingInstall();

    bool m_welcomeCompleted = false;
    bool m_returningUser = false;
    QString m_lastUserId;
};
