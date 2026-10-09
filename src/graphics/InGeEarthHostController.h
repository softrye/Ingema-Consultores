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

    // Selector de coordenadas de Calicatas sobre el mismo WebView de Earth.
    // rect = píxeles físicos de pantalla del área de mapa del selector Qt.
    QString defaultMapUrl() const;
    bool showPicker(const QString &json, int left, int top, int width, int height);
    void updatePickerRect(int left, int top, int width, int height);
    void setPickerPoint(const QString &json);
    void setPickerSuspended(bool suspended);
    void hidePicker();

signals:
    void pickerPointSelected(double latitude, double longitude);
    void pickerStateChanged(const QString &state);
    void pickerSnapshot(const QString &mapType, double latitude, double longitude,
                        const QString &dataUrl);
    void stateChanged();
    void coordinateForCalicata(double latitude, double longitude,
                               double altitude, double accuracy,
                               const QString &timestamp,
                               const QString &source);

private:
    bool m_active = false;
    QString m_state = QStringLiteral("UNINITIALIZED");
};
