#pragma once

#include <QObject>
#include <QString>

class FlowHaptics final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(bool supported READ supported CONSTANT)

public:
    explicit FlowHaptics(QObject *parent = nullptr);

    bool enabled() const;
    void setEnabled(bool enabled);
    bool supported() const;

    Q_INVOKABLE bool trigger(const QString &intent = QStringLiteral("selection"));

signals:
    void enabledChanged();

private:
    bool m_enabled = true;
};
