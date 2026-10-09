#pragma once

#include <QObject>
#include <QString>
#include <QDateTime>
#include <QUrl>
#include <QJsonObject>
#include <QPointer>
#include <QVariantList>
#include <QVariantMap>
#include <QStringList>

class SupabaseClient;
class QNetworkReply;

class AuthSession : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool logged READ logged NOTIFY loggedChanged)
    Q_PROPERTY(bool devOffline READ devOffline NOTIFY loggedChanged)
    Q_PROPERTY(QString userId READ userId NOTIFY userInfoChanged)
    Q_PROPERTY(QString email READ email NOTIFY userInfoChanged)
    Q_PROPERTY(QString nombre READ nombre NOTIFY userInfoChanged)
    Q_PROPERTY(QString apellido READ apellido NOTIFY userInfoChanged)
    Q_PROPERTY(QString fullName READ fullName NOTIFY backendProfileChanged)
    Q_PROPERTY(QString phone READ phone NOTIFY userInfoChanged)
    Q_PROPERTY(QString avatarUrl READ avatarUrl NOTIFY userInfoChanged)
    Q_PROPERTY(QString avatarPath READ avatarPath NOTIFY userInfoChanged)
    Q_PROPERTY(QString position READ position NOTIFY backendProfileChanged)
    Q_PROPERTY(QString profileRole READ profileRole NOTIFY backendProfileChanged)
    Q_PROPERTY(QString globalRole READ globalRole NOTIFY backendProfileChanged)
    Q_PROPERTY(QString role READ role NOTIFY backendProfileChanged)
    Q_PROPERTY(QString profileStatus READ profileStatus NOTIFY backendProfileChanged)
    Q_PROPERTY(bool profileReady READ profileReady NOTIFY backendProfileChanged)
    Q_PROPERTY(bool profileActive READ profileActive NOTIFY backendProfileChanged)
    Q_PROPERTY(QVariantList assignedProjects READ assignedProjects NOTIFY backendAccessChanged)
    Q_PROPERTY(QVariantList memberships READ memberships NOTIFY backendAccessChanged)
    Q_PROPERTY(QVariantMap capabilities READ capabilities NOTIFY backendAccessChanged)
    Q_PROPERTY(bool rememberFor30Days READ rememberFor30Days WRITE setRememberFor30Days NOTIFY rememberFor30DaysChanged)
    Q_PROPERTY(QVariantList savedAccounts READ savedAccounts NOTIFY savedAccountsChanged)
    Q_PROPERTY(QString currentAccountId READ currentAccountId NOTIFY currentAccountChanged)
    Q_PROPERTY(bool autoLoginInProgress READ autoLoginInProgress NOTIFY autoLoginInProgressChanged)

public:
    explicit AuthSession(SupabaseClient* api, QObject* parent = nullptr);

    static AuthSession* instance();

    bool logged() const;
    bool devOffline() const { return m_devOffline; }

    QString accessToken() const { return m_accessToken; }
    QString refreshToken() const { return m_refreshToken; }
    QString userId() const { return m_userId; }
    QString email() const { return m_email; }
    QString nombre() const { return m_nombre; }
    QString apellido() const { return m_apellido; }
    QString fullName() const { return m_fullName; }
    QString phone() const { return m_phone; }
    QString avatarUrl() const { return m_avatarUrl; }
    QString avatarPath() const { return m_avatarPath; }
    QString position() const { return m_position; }
    QString profileRole() const { return m_profileRole; }
    QString globalRole() const { return m_globalRole; }
    QString role() const { return m_globalRole.isEmpty() ? m_profileRole : m_globalRole; }
    QString profileStatus() const { return m_profileStatus; }
    bool profileReady() const { return m_profileReady; }
    bool profileActive() const { return m_profileReady && m_profileStatus == QStringLiteral("ACTIVO"); }
    QVariantList assignedProjects() const { return m_assignedProjects; }
    QVariantList memberships() const { return m_memberships; }
    QVariantMap capabilities() const { return m_capabilities; }
    bool rememberFor30Days() const { return m_rememberFor30Days; }
    QVariantList savedAccounts() const;
    QString currentAccountId() const { return m_currentAccountId; }
    bool autoLoginInProgress() const { return m_autoLoginInProgress; }

    Q_INVOKABLE void signInWithPassword(const QString& email, const QString& password);
    Q_INVOKABLE void signInWithGoogle();
    Q_INVOKABLE void signInWithOAuthProvider(const QString& provider);
    Q_INVOKABLE void signUpWithEmail(const QString& email,
                                     const QString& password,
                                     const QString& nombre,
                                     const QString& apellido,
                                     const QString& phone);
    Q_INVOKABLE void signOut();
    Q_INVOKABLE void loadFromDisk();
    Q_INVOKABLE void saveToDisk();
    Q_INVOKABLE void tryAutoLogin();
    Q_INVOKABLE void refreshSessionWithRefreshToken();
    Q_INVOKABLE void resendSignupConfirmation(const QString& email);
    Q_INVOKABLE void verifySignupOtp(const QString& email, const QString& token);
    Q_INVOKABLE void requestPasswordReset(const QString& email);

    Q_INVOKABLE void updateUserProfile(const QString& nombre,
                                       const QString& apellido,
                                       const QString& phone);
    Q_INVOKABLE void updateUserAvatar(const QUrl& fileUrl);
    Q_INVOKABLE void clearUserAvatar();
    Q_INVOKABLE void setRememberFor30Days(bool enabled);

    // Gestión segura de varias sesiones recordadas. Nunca guarda contraseñas;
    // conserva únicamente los tokens de sesión que Supabase ya entrega.
    Q_INVOKABLE void switchToSavedAccount(const QString& accountId);
    Q_INVOKABLE void restoreSavedAccountWithBiometric(const QString& accountId);
    Q_INVOKABLE void removeSavedAccount(const QString& accountId);
    Q_INVOKABLE void clearSavedAccounts();
    Q_INVOKABLE bool hasSavedAccount(const QString& accountId) const;
    // Pista de arranque: existe una sesión recordada que tryAutoLogin puede
    // intentar restaurar. No carga tokens ni modifica el estado activo.
    Q_INVOKABLE bool hasRestorableSession() const;

    QString localUserFolderName() const;
    QString guessAvatarPath() const;
    void updateUserMetadata(const QJsonObject& data);

signals:
    void loginOk();
    void loginFail(const QString& message);
    void signUpOk();
    void signUpFail(const QString& message);
    void signUpConfirmationRequired(const QString& email);
    void signupVerificationOk();
    void signupVerificationFail(const QString& message);
    void loggedOut();

    void loggedChanged();
    void userInfoChanged();
    void rememberFor30DaysChanged();
    void savedAccountsChanged();
    void currentAccountChanged();
    void autoLoginInProgressChanged();
    void autoLoginFinished(bool restored);
    void backendProfileChanged();
    void backendAccessChanged();

    void accountSwitchStarted(const QString& accountId);
    void accountSwitchOk(const QString& accountId);
    void accountSwitchFail(const QString& accountId, const QString& message);

    void profileUpdatedOk();
    void profileUpdatedFail(const QString& message);
    void profileAvatarSynced();
    void profileAvatarSyncWarning(const QString& message);

    void confirmationResentOk();
    void confirmationResentFail(const QString& message);
    void passwordResetRequestedOk(const QString& email);
    void passwordResetRequestedFail(const QString& message);
    void oauthStarted(const QString& provider, const QString& url);

private:
    void setUserFromJson(const QJsonObject& user);
    void clearSessionMemory();
    void clearSavedSession();
    void clearLegacyActiveSession() const;
    void finishAuthSuccess(const QJsonObject& o, bool emitLoginSignal);
    void startPasswordLoginRequest(const QString& email,
                                   const QString& password,
                                   quint64 requestId,
                                   int networkAttempt);

    QString accountGroup(const QString& accountId) const;
    QStringList savedAccountIds() const;
    void writeSavedAccount(const QString& accountId);
    bool loadSavedAccount(const QString& accountId);
    void removeSavedAccountInternal(const QString& accountId, bool notify);
    void migrateLegacySessionIfNeeded();
    void setCurrentAccountId(const QString& accountId);
    void setAutoLoginInProgress(bool active);
    void finishAutoLogin(bool restored);
    void refreshSessionWithRefreshTokenInternal(bool accountSwitch, bool autoLogin);
    void loadBackendProfile(bool emitLoginSignal, bool accountSwitch, bool autoLogin);
    void completeAuthorizedLogin(bool emitLoginSignal, bool accountSwitch, bool autoLogin);
    void failBackendAuthorization(const QString& message,
                                  bool unauthorized,
                                  bool accountSwitch,
                                  bool autoLogin);
    void loadAssignedProjects(quint64 generation,
                              bool emitLoginSignal,
                              bool accountSwitch,
                              bool autoLogin);
    void loadAssignedProjectsByRls(quint64 generation,
                                   bool emitLoginSignal,
                                   bool accountSwitch,
                                   bool autoLogin);
    void loadProjectCapabilities(int index, quint64 generation);
    void loadProjectTeamCapabilities(int index,
                                     quint64 generation,
                                     const QVariantMap& calicatasContext);
    void finishProjectAccessItem(int index,
                                 quint64 generation,
                                 const QVariantMap& capabilityContext);
    void clearBackendState();
    void startDevOfflineSession(const QString& exactEmail, bool autoLogin);
    void clearDevOfflinePersistence() const;
    // Toda operación de sesión (login, logout, cambio, restauración) abre una
    // generación nueva; las respuestas de red de generaciones previas se
    // descartan y nunca pueden resucitar ni sustituir la sesión actual.
    quint64 beginAuthOperation(const char* kind, bool cancelPasswordLogin);
    bool authOperationCurrent(quint64 generation, const char* callback) const;
    void finishAvatarUpdate(const QString& userId, const QByteArray& pngBytes,
                            const QString& error);

private:
    static AuthSession* s_instance;

    SupabaseClient* m_api = nullptr;

    QString m_accessToken;
    QString m_refreshToken;
    QString m_userId;
    QDateTime m_expiresAtUtc;
    bool m_devOffline = false;

    QString m_email;
    QString m_loginEmailExact;
    QString m_nombre;
    QString m_apellido;
    QString m_fullName;
    QString m_phone;

    QString m_position;
    QString m_profileRole;
    QString m_globalRole;
    QString m_profileStatus;
    bool m_profileReady = false;
    QVariantList m_assignedProjects;
    QVariantList m_memberships;
    QVariantMap m_capabilities;

    QString m_avatarUrl;
    QString m_avatarLocalFile;
    QString m_avatarPath;
    bool m_avatarJobRunning = false;

    bool m_rememberFor30Days = false;
    QDateTime m_rememberUntilUtc;

    QString m_currentAccountId;
    QString m_pendingSwitchAccountId;
    bool m_autoLoginInProgress = false;

    QPointer<QNetworkReply> m_loginReply;
    quint64 m_loginAttempt = 0;
    quint64 m_backendGeneration = 0;
    quint64 m_authGeneration = 0;
};
