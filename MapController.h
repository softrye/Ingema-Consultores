#ifndef MAPCONTROLLER_H
#define MAPCONTROLLER_H

#pragma once

#include <QObject>
#include <QGeoCoordinate>

class MapController : public QObject {
    Q_OBJECT
    Q_PROPERTY(QGeoCoordinate coordinate READ coordinate WRITE setCoordinate NOTIFY coordinateChanged)
    Q_PROPERTY(bool coordinateValid READ coordinateValid NOTIFY coordinateChanged)
    Q_PROPERTY(int zoom READ zoom WRITE setZoom NOTIFY zoomChanged)
    Q_PROPERTY(bool followGps READ followGps WRITE setFollowGps NOTIFY followGpsChanged)
    Q_PROPERTY(bool gpsActive READ gpsActive WRITE setGpsActive NOTIFY gpsActiveChanged)

public:
    explicit MapController(QObject* parent = nullptr) : QObject(parent) {}

    QGeoCoordinate coordinate() const { return m_coord; }
    void setCoordinate(const QGeoCoordinate& c) {
        if (m_coord == c) return;
        m_coord = c;
        emit coordinateChanged();
    }

    bool coordinateValid() const { return m_coord.isValid(); }

    int zoom() const { return m_zoom; }
    void setZoom(int z) {
        if (m_zoom == z) return;
        m_zoom = z;
        emit zoomChanged();
    }

    bool followGps() const { return m_followGps; }
    void setFollowGps(bool on) {
        if (m_followGps == on) return;
        m_followGps = on;
        emit followGpsChanged();
    }

    bool gpsActive() const { return m_gpsActive; }
    void setGpsActive(bool on) {
        if (m_gpsActive == on) return;
        m_gpsActive = on;
        emit gpsActiveChanged();
    }

    Q_INVOKABLE void pickCoordinate(const QGeoCoordinate& c) {
        if (!c.isValid()) return;
        setCoordinate(c);
        emit coordinatePicked(c);
    }

    Q_INVOKABLE void beginManualDrag()
    {
        if (m_manualDragActive)
            return;

        m_manualDragActive = true;
        m_manualDragStart = m_coord;
        emit manualDragStarted(m_manualDragStart);
    }

    Q_INVOKABLE void endManualDrag()
    {
        if (!m_manualDragActive)
            return;

        m_manualDragActive = false;
        emit manualDragFinished(m_coord);
    }

signals:
    void coordinateChanged();
    void zoomChanged();
    void followGpsChanged();
    void gpsActiveChanged();
    void coordinatePicked(const QGeoCoordinate& c);

    void manualDragStarted(const QGeoCoordinate& startCoord);
    void manualDragFinished(const QGeoCoordinate& endCoord);

private:
    QGeoCoordinate m_coord;
    int m_zoom = 16;
    bool m_followGps = true;
    bool m_gpsActive = false;

    bool m_manualDragActive = false;
    QGeoCoordinate m_manualDragStart;
};

#endif // MAPCONTROLLER_H
