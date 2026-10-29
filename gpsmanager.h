#pragma once

#include <QObject>
#include <QtPositioning/QGeoPositionInfoSource>
#include <QtPositioning/QGeoCoordinate>
#include <QDateTime>
#include <QtPositioning/QNmeaPositionInfoSource>
#include <QFile>
#include <QTimer>


class GpsManager : public QObject
{
    Q_OBJECT
public:
    // Estructura para coordenadas UTM
    struct UTMCoord {
        int   zone = 0;       // 18, 17, etc.
        QChar band;           // C..X (ej. 'L')
        double easting = 0.0; // X (Este)
        double northing = 0.0;// Y (Norte)
    };

    // Acceso global al único GpsManager
    static GpsManager* instance();

    // Encender y apagar el GPS
    void start();
    void stop();

    // Estado actual
    bool isActive() const { return m_active; }
    bool hasSource() const { return m_source != nullptr; }

    QGeoCoordinate lastCoordinate() const { return m_lastCoord; }
    QDateTime lastTimestamp() const { return m_lastTime; }
    double lastAltitude() const { return m_lastAltitude; }

    // 🔹 Conversión WGS84 Lat/Lon → UTM
    // Devuelve true si la conversión fue posible (lat entre -80 y +84)
    static bool toUTM(const QGeoCoordinate& coord, UTMCoord& outUTM);

    static bool fromUTM(const UTMCoord& utm, QGeoCoordinate& outCoord);

signals:
    // Se emite cada vez que llega una nueva posición
    void positionUpdated(const QGeoCoordinate& coord,
                         double altitude,
                         const QDateTime& timestamp);

private slots:
    void onPositionUpdated(const QGeoPositionInfo& info);

private:
    explicit GpsManager(QObject* parent = nullptr);
    static GpsManager* s_instance;

    QGeoPositionInfoSource* m_source = nullptr;
    QGeoCoordinate m_lastCoord;
    QDateTime m_lastTime;
    double m_lastAltitude = 0.0;
    bool m_active = false;

    QNmeaPositionInfoSource* m_nmea = nullptr;
    QFile* m_nmeaFile = nullptr;

    QTimer m_nmeaLoopTimer;

};
