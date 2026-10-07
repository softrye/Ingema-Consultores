#pragma once

#include <QObject>
#include <QString>

class InGeNarrator final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)
    Q_PROPERTY(bool speaking READ speaking NOTIFY speakingChanged)

public:
    explicit InGeNarrator(QObject *parent = nullptr);

    bool available() const;
    bool speaking() const { return m_speaking; }

    Q_INVOKABLE void speak(const QString &text,
                           const QString &localeTag = QStringLiteral("es-PE"),
                           double rate = 0.94,
                           double pitch = 1.0);
    Q_INVOKABLE void stop();

signals:
    void speakingChanged();

private:
    void setSpeaking(bool value);
    bool m_speaking = false;
};
