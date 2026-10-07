#pragma once

#include <QObject>
#include <QString>

class InGeEarthHostController final : public QObject
{
    Q_OBJECT

public:
    explicit InGeEarthHostController(QObject *parent = nullptr);

    bool supported() const;
    bool active() const;
    QString state() const;

    bool openEarth(const QString &, double, double, const QString &);
    bool focusEarth(double latitude, double longitude, double altitude,
                    const QString &label);
    void closeEarth();

signals:
    void stateChanged();
    void coordinateForCalicata(double latitude, double longitude,
                               double altitude, double accuracy,
                               const QString &timestamp,
                               const QString &source);

private:
    bool m_active = false;
    QString m_state = QStringLiteral("UNINITIALIZED");
};
