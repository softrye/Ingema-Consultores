#include "OnboardingState.h"

#include <QDebug>
#include <QDir>
#include <QSettings>
#include <QDateTime>
#include <QStandardPaths>

namespace {
constexpr int kSchema = 1;
constexpr auto kSchemaKey = "onboarding/schema";
constexpr auto kWelcomeCompletedKey = "onboarding/welcome_completed";
constexpr auto kReturningKey = "onboarding/returning_user";
constexpr auto kLastUserKey = "onboarding/last_user_id";
constexpr auto kNamesGroup = "onboarding/display_names";

// userId de Supabase (UUID): apto como clave de QSettings sin escapar.
bool validUserId(const QString &userId)
{
    if (userId.isEmpty() || userId.size() > 64)
        return false;
    for (const QChar c : userId) {
        if (!(c.isLetterOrNumber() || c == QLatin1Char('-') || c == QLatin1Char('_')))
            return false;
    }
    return true;
}
}

OnboardingState::OnboardingState(QObject *parent)
    : QObject(parent)
{
    QSettings settings;
    if (settings.value(kSchemaKey).toInt() < kSchema)
        migrateExistingInstall();
    m_welcomeCompleted = settings.value(kWelcomeCompletedKey, false).toBool();
    m_returningUser = settings.value(kReturningKey, false).toBool();
    m_lastUserId = settings.value(kLastUserKey).toString();
    qInfo().noquote() << "INGE_ONBOARDING_STATE welcomeCompleted=" << m_welcomeCompleted
                      << " returning=" << m_returningUser
                      << " hasLastUser=" << !m_lastUserId.isEmpty();
}

// Instalaciones anteriores a Login V1: cualquier rastro de sesión, cuentas
// guardadas o datos de trabajo locales indica un ingeniero que ya usó la app.
void OnboardingState::migrateExistingInstall()
{
    QSettings settings;
    const QString legacyUser = settings.value(QStringLiteral("auth/user_id")).toString();
    const QString legacyCurrent = settings.value(QStringLiteral("auth/current_account_id")).toString();
    bool priorUse = !legacyUser.isEmpty() || !legacyCurrent.isEmpty()
        || settings.contains(QStringLiteral("auth/accounts_index"))
        || settings.contains(QStringLiteral("auth/remember_enabled"));
    if (!priorUse) {
        // Carpetas que solo crean los servicios de InGe+ (BetaDiagnostics,
        // AuthSession, CalicataCloudService, CalicataDocument). Este objeto se
        // construye antes que ellos: en una instalación nueva no existen.
        const QDir data(QStandardPaths::writableLocation(QStandardPaths::AppDataLocation));
        for (const auto *name : {"diagnostics", "avatars", "calicata-media-cache", "calicata-imports"}) {
            if (data.exists(QLatin1String(name))) {
                priorUse = true;
                break;
            }
        }
    }
    if (priorUse) {
        settings.setValue(kWelcomeCompletedKey, true);
        settings.setValue(kReturningKey, true);
        const QString lastUser = !legacyCurrent.isEmpty() ? legacyCurrent : legacyUser;
        if (validUserId(lastUser))
            settings.setValue(kLastUserKey, lastUser);
    }
    settings.setValue(kSchemaKey, kSchema);
    settings.sync();
    qInfo().noquote() << "INGE_ONBOARDING_MIGRATION priorUse=" << priorUse;
}

QString OnboardingState::greetingName() const
{
    return verifiedNameFor(m_lastUserId);
}

QString OnboardingState::verifiedNameFor(const QString &userId) const
{
    if (!validUserId(userId))
        return {};
    QSettings settings;
    settings.beginGroup(kNamesGroup);
    return settings.value(userId).toString();
}

void OnboardingState::recordAuthenticatedUser(const QString &userId,
                                              const QString &verifiedName)
{
    if (!validUserId(userId))
        return;
    QSettings settings;
    const QString name = verifiedName.trimmed().left(120);
    if (!name.isEmpty()) {
        settings.beginGroup(kNamesGroup);
        settings.setValue(userId, name);
        settings.endGroup();
    }
    settings.setValue(kLastUserKey, userId);
    settings.setValue(kReturningKey, true);
    settings.sync();
    m_lastUserId = userId;
    m_returningUser = true;
    emit changed();
}

void OnboardingState::completeWelcome()
{
    if (m_welcomeCompleted)
        return;
    QSettings settings;
    settings.setValue(kWelcomeCompletedKey, true);
    settings.sync();
    m_welcomeCompleted = true;
    qInfo().noquote() << "INGE_ONBOARDING_WELCOME_COMPLETED";
    emit changed();
}

// ------------------------------------------------------------------ Sesión
namespace {
const QString kBackgroundAtKey = QStringLiteral("session/background_utc_ms");
const QString kBackgroundExternalKey = QStringLiteral("session/background_external");
constexpr qint64 kGraceMs = 60 * 1000;
// Sin ampliaciones silenciosas: también con cámara o selector de fotos.
constexpr qint64 kExternalGraceMs = kGraceMs;
}

void OnboardingState::clearBackgroundRecord()
{
    QSettings settings;
    if (!settings.contains(kBackgroundAtKey) && !settings.contains(kBackgroundExternalKey))
        return;
    settings.remove(kBackgroundAtKey);
    settings.remove(kBackgroundExternalKey);
    settings.sync();
}

void OnboardingState::setSessionTracked(bool tracked)
{
    if (m_sessionTracked == tracked)
        return;
    m_sessionTracked = tracked;
    if (!tracked) {
        m_backgroundClock.invalidate();
        clearBackgroundRecord();
    }
}

void OnboardingState::setExternalActivity(bool active)
{
    m_externalActivity = active;
}

void OnboardingState::handleApplicationState(Qt::ApplicationState state)
{
    if (state == Qt::ApplicationSuspended || state == Qt::ApplicationHidden) {
        if (!m_sessionTracked || m_sessionLocked || m_backgroundClock.isValid())
            return;
        m_backgroundClock.start();
        m_backgroundExternal = m_externalActivity;
        QSettings settings;
        settings.setValue(kBackgroundAtKey, QDateTime::currentMSecsSinceEpoch());
        settings.setValue(kBackgroundExternalKey, m_backgroundExternal);
        settings.sync();
        qInfo().noquote() << "INGE_SESSION_BACKGROUND external=" << m_backgroundExternal;
        return;
    }
    if (state != Qt::ApplicationActive || !m_backgroundClock.isValid())
        return;
    const qint64 elapsed = m_backgroundClock.elapsed();
    const qint64 limit = m_backgroundExternal ? kExternalGraceMs : kGraceMs;
    m_backgroundClock.invalidate();
    clearBackgroundRecord();
    if (m_sessionTracked && elapsed >= limit)
        lockSession(QStringLiteral("background_timeout"));
    else
        qInfo().noquote() << "INGE_SESSION_GRACE_VALID elapsedMs=" << elapsed;
}

bool OnboardingState::consumeStartupGrace()
{
    QSettings settings;
    bool ok = false;
    const qint64 stamp = settings.value(kBackgroundAtKey).toLongLong(&ok);
    const bool external = settings.value(kBackgroundExternalKey, false).toBool();
    clearBackgroundRecord();
    if (!ok || stamp <= 0) {
        // Sin registro fiable (cierre en primer plano, crash, primera vez).
        qInfo() << "INGE_SESSION_LOCK_REQUIRED reason=no_background_record";
        return false;
    }
    const qint64 elapsed = QDateTime::currentMSecsSinceEpoch() - stamp;
    const qint64 limit = external ? kExternalGraceMs : kGraceMs;
    if (elapsed < 0 || elapsed >= limit) {
        qInfo().noquote() << "INGE_SESSION_LOCK_REQUIRED reason=" << (elapsed < 0 ? "clock" : "expired");
        return false;
    }
    qInfo().noquote() << "INGE_SESSION_GRACE_VALID elapsedMs=" << elapsed << " source=process_restart";
    return true;
}

void OnboardingState::lockSession(const QString &reason)
{
    m_backgroundClock.invalidate();
    if (m_sessionLocked)
        return;
    m_sessionLocked = true;
    qInfo().noquote() << "INGE_SESSION_LOCK_REQUIRED reason=" << reason;
    emit sessionLockChanged();
}

void OnboardingState::unlockSession()
{
    if (!m_sessionLocked)
        return;
    m_sessionLocked = false;
    qInfo() << "INGE_SESSION_REAUTH_SUCCESS";
    emit sessionLockChanged();
}

void OnboardingState::endSession()
{
    // Cierre de sesión explícito: sin período de gracia.
    m_sessionTracked = false;
    m_backgroundClock.invalidate();
    clearBackgroundRecord();
    if (m_sessionLocked) {
        m_sessionLocked = false;
        emit sessionLockChanged();
    }
    qInfo() << "INGE_SESSION_ENDED";
}

// ------------------------------------------------------- Usuario recordado
namespace {
const QString kLastEmailKey = QStringLiteral("onboarding/last_email");
const QString kLastEmailUserKey = QStringLiteral("onboarding/last_email_user_id");
}

QString OnboardingState::lastEmail() const
{
    QSettings settings;
    // Solo el correo del último usuario autenticado (no uno de otra cuenta).
    if (settings.value(kLastEmailUserKey).toString() != lastUserId())
        return QString();
    return settings.value(kLastEmailKey).toString();
}

void OnboardingState::rememberAccountEmail(const QString &userId, const QString &email)
{
    if (userId.trimmed().isEmpty() || !email.contains(QLatin1Char('@')))
        return;
    QSettings settings;
    if (settings.value(kLastEmailKey).toString() == email
            && settings.value(kLastEmailUserKey).toString() == userId)
        return;
    settings.setValue(kLastEmailKey, email);          // exacto, como se escribió
    settings.setValue(kLastEmailUserKey, userId);
    settings.sync();
    qInfo() << "INGE_ACCESS_IDENTITY_REMEMBERED";
    emit changed();
}

void OnboardingState::forgetAccountEmail()
{
    QSettings settings;
    settings.remove(kLastEmailKey);
    settings.remove(kLastEmailUserKey);
    settings.sync();
    qInfo() << "INGE_ACCESS_IDENTITY_FORGOTTEN";
    emit changed();
}
