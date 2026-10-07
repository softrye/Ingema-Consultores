#include "firstexperiencecontroller.h"
#include "settingshelper.h"

#include <QSettings>
#include <QtGlobal>

namespace {
constexpr auto kCompletedVersion = "experience/completed_version";
constexpr auto kLanguage = "experience/language";
constexpr auto kTheme = "experience/theme";
constexpr auto kThemeSchema = "experience/theme_schema";
constexpr int kCurrentThemeSchema = 2;
constexpr auto kMotion = "experience/motion_level";
constexpr auto kPerformance = "experience/performance_level";
constexpr auto kNarration = "experience/narration_enabled";
constexpr auto kLastScene = "experience/last_scene";
constexpr auto kLastSceneVersion = "experience/last_scene_version";
}

FirstExperienceController::FirstExperienceController(QObject *parent)
    : QObject(parent)
{
}

bool FirstExperienceController::completed() const
{
    QSettings s = appSettings();
    return s.value(kCompletedVersion, 0).toInt() >= experienceVersion();
}

QString FirstExperienceController::languageCode() const
{
    QSettings s = appSettings();
    return s.value(kLanguage, QStringLiteral("es")).toString();
}

int FirstExperienceController::themeMode() const
{
    QSettings s = appSettings();
    if (s.value(kThemeSchema, 0).toInt() < kCurrentThemeSchema) {
        const int legacyMode = qBound(0, s.value(kTheme, 0).toInt(), 2);
        const int migratedMode = legacyMode == 2 ? 1 : 0;
        s.setValue(kTheme, migratedMode);
        s.setValue(kThemeSchema, kCurrentThemeSchema);
        s.sync();
        return migratedMode;
    }
    return qBound(0, s.value(kTheme, 0).toInt(), 2);
}

int FirstExperienceController::motionLevel() const
{
    QSettings s = appSettings();
    return qBound(0, s.value(kMotion, 2).toInt(), 2);
}

int FirstExperienceController::performanceLevel() const
{
    QSettings s = appSettings();
    return qBound(0, s.value(kPerformance, 2).toInt(), 2);
}

bool FirstExperienceController::narrationEnabled() const
{
    QSettings s = appSettings();
    return s.value(kNarration, true).toBool();
}

int FirstExperienceController::lastScene() const
{
    QSettings s = appSettings();
    const int sceneVersion = s.value(kLastSceneVersion, 0).toInt();
    if (sceneVersion != experienceVersion())
        return 0;
    return qMax(0, s.value(kLastScene, 0).toInt());
}

void FirstExperienceController::setLanguageCode(const QString &value)
{
    const QString safe = value == QStringLiteral("en")
            || value == QStringLiteral("qu")
            || value == QStringLiteral("pt")
            ? value : QStringLiteral("es");
    if (safe == languageCode()) return;
    QSettings s = appSettings();
    s.setValue(kLanguage, safe);
    s.sync();
    emit languageCodeChanged();
}

void FirstExperienceController::setThemeMode(int value)
{
    value = qBound(0, value, 2);
    if (value == themeMode()) return;
    QSettings s = appSettings();
    s.setValue(kTheme, value);
    s.setValue(kThemeSchema, kCurrentThemeSchema);
    s.sync();
    emit themeModeChanged();
}

void FirstExperienceController::setMotionLevel(int value)
{
    value = qBound(0, value, 2);
    if (value == motionLevel()) return;
    QSettings s = appSettings();
    s.setValue(kMotion, value);
    s.sync();
    emit motionLevelChanged();
}

void FirstExperienceController::setPerformanceLevel(int value)
{
    value = qBound(0, value, 2);
    if (value == performanceLevel()) return;
    QSettings s = appSettings();
    s.setValue(kPerformance, value);
    s.sync();
    emit performanceLevelChanged();
}

void FirstExperienceController::setNarrationEnabled(bool value)
{
    if (value == narrationEnabled()) return;
    QSettings s = appSettings();
    s.setValue(kNarration, value);
    s.sync();
    emit narrationEnabledChanged();
}

void FirstExperienceController::setLastScene(int value)
{
    value = qMax(0, value);
    if (value == lastScene()) return;
    QSettings s = appSettings();
    s.setValue(kLastSceneVersion, experienceVersion());
    s.setValue(kLastScene, value);
    s.sync();
    emit lastSceneChanged();
}

void FirstExperienceController::complete()
{
    QSettings s = appSettings();
    const bool wasCompleted = completed();
    s.setValue(kCompletedVersion, experienceVersion());
    s.setValue(kLastSceneVersion, experienceVersion());
    s.setValue(kLastScene, 0);
    s.sync();
    if (!wasCompleted) emit completedChanged();
    emit lastSceneChanged();
}

void FirstExperienceController::reset()
{
    QSettings s = appSettings();
    const bool wasCompleted = completed();
    s.setValue(kCompletedVersion, 0);
    s.setValue(kLastSceneVersion, 0);
    s.setValue(kLastScene, 0);
    s.sync();
    if (wasCompleted) emit completedChanged();
    emit lastSceneChanged();
}
