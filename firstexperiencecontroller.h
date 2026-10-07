#pragma once

#include <QObject>
#include <QString>

class FirstExperienceController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool completed READ completed NOTIFY completedChanged)
    Q_PROPERTY(int experienceVersion READ experienceVersion CONSTANT)
    Q_PROPERTY(QString languageCode READ languageCode WRITE setLanguageCode NOTIFY languageCodeChanged)
    Q_PROPERTY(int themeMode READ themeMode WRITE setThemeMode NOTIFY themeModeChanged)
    Q_PROPERTY(int motionLevel READ motionLevel WRITE setMotionLevel NOTIFY motionLevelChanged)
    Q_PROPERTY(int performanceLevel READ performanceLevel WRITE setPerformanceLevel NOTIFY performanceLevelChanged)
    Q_PROPERTY(bool narrationEnabled READ narrationEnabled WRITE setNarrationEnabled NOTIFY narrationEnabledChanged)
    Q_PROPERTY(int lastScene READ lastScene WRITE setLastScene NOTIFY lastSceneChanged)

public:
    explicit FirstExperienceController(QObject *parent = nullptr);

    bool completed() const;
    int experienceVersion() const { return 4; }
    QString languageCode() const;
    int themeMode() const;
    int motionLevel() const;
    int performanceLevel() const;
    bool narrationEnabled() const;
    int lastScene() const;

    Q_INVOKABLE void setLanguageCode(const QString &value);
    Q_INVOKABLE void setThemeMode(int value);
    Q_INVOKABLE void setMotionLevel(int value);
    Q_INVOKABLE void setPerformanceLevel(int value);
    Q_INVOKABLE void setNarrationEnabled(bool value);
    Q_INVOKABLE void setLastScene(int value);
    Q_INVOKABLE void complete();
    Q_INVOKABLE void reset();

signals:
    void completedChanged();
    void languageCodeChanged();
    void themeModeChanged();
    void motionLevelChanged();
    void performanceLevelChanged();
    void narrationEnabledChanged();
    void lastSceneChanged();
};
