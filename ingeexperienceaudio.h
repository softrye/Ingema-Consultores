#pragma once

#include <QObject>
#include <QString>

class InGeExperienceAudio final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(bool ambientPlaying READ ambientPlaying NOTIFY ambientPlayingChanged)
    Q_PROPERTY(bool narrationPlaying READ narrationPlaying NOTIFY narrationPlayingChanged)
    Q_PROPERTY(double ambientVolume READ ambientVolume WRITE setAmbientVolume NOTIFY volumesChanged)
    Q_PROPERTY(double narrationVolume READ narrationVolume WRITE setNarrationVolume NOTIFY volumesChanged)
    Q_PROPERTY(double sfxVolume READ sfxVolume WRITE setSfxVolume NOTIFY volumesChanged)

public:
    explicit InGeExperienceAudio(QObject *parent = nullptr);
    ~InGeExperienceAudio() override;

    bool available() const;
    bool ambientPlaying() const { return m_ambientPlaying; }
    bool narrationPlaying() const { return m_narrationPlaying; }
    double ambientVolume() const { return m_ambientVolume; }
    double narrationVolume() const { return m_narrationVolume; }
    double sfxVolume() const { return m_sfxVolume; }

    void setAmbientVolume(double value);
    void setNarrationVolume(double value);
    void setSfxVolume(double value);

    Q_INVOKABLE bool hasBundledNarration(const QString &languageCode) const;
    Q_INVOKABLE void playAmbient();
    Q_INVOKABLE void stopAmbient(int fadeMs = 420);
    Q_INVOKABLE bool playNarration(int sceneIndex, const QString &languageCode);
    Q_INVOKABLE void stopNarration();
    Q_INVOKABLE void playSfx(const QString &name, double gain = 1.0);
    Q_INVOKABLE void stopAll();

signals:
    void ambientPlayingChanged();
    void narrationPlayingChanged();
    void volumesChanged();

private:
    void applyVolumes();
    void setAmbientPlaying(bool value);
    void setNarrationPlaying(bool value);

    bool m_ambientPlaying = false;
    bool m_narrationPlaying = false;
    double m_ambientVolume = 0.28;
    double m_narrationVolume = 0.92;
    double m_sfxVolume = 0.72;
};
