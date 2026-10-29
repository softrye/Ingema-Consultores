#include "gpsmanager.h"
#include <QtPositioning/QGeoPositionInfo>
#include <QDebug>
#include <QtMath>

// ------------------------------------------------------------
// Logs
// ------------------------------------------------------------
// true  = deja logs importantes (creación, start, stop, errores)
// false = apaga por completo esos logs también
static constexpr bool kLogGpsLifecycle = false;

// true  = imprime cada posición nueva (spam)
// false = NO imprime cada actualización de posición
static constexpr bool kLogGpsPosition = false;

GpsManager* GpsManager::s_instance = nullptr;

GpsManager* GpsManager::instance()
{
    if (!s_instance)
        s_instance = new GpsManager();
    return s_instance;
}

GpsManager::GpsManager(QObject* parent)
    : QObject(parent)
{
    if (kLogGpsLifecycle) {
        qDebug() << "[GpsManager] Available position sources:"
                 << QGeoPositionInfoSource::availableSources();

        qDebug() << "[GpsManager] Creando fuente de posicion...";
    }

    m_source = QGeoPositionInfoSource::createDefaultSource(this);

    // ✅ Si no hay fuente default, probamos NMEA (laptop / simulación)
    if (!m_source) {
        const auto sources = QGeoPositionInfoSource::availableSources();
        if (sources.contains("nmea")) {
            if (kLogGpsLifecycle)
                qDebug() << "[GpsManager] No hay default. Usando NMEA SimulationMode...";

            m_nmeaFile = new QFile(":/gps/demo.nmea", this);
            if (!m_nmeaFile->open(QIODevice::ReadOnly | QIODevice::Text)) {
                if (kLogGpsLifecycle)
                    qDebug() << "[GpsManager] ERROR: No pude abrir :/gps/demo.nmea";
                return;
            }

            m_nmea = new QNmeaPositionInfoSource(QNmeaPositionInfoSource::SimulationMode, this);
            m_nmea->setDevice(m_nmeaFile);
            m_nmea->setUpdateInterval(1000); // 1 Hz
            m_source = m_nmea;

            connect(m_source, &QGeoPositionInfoSource::positionUpdated,
                    this, &GpsManager::onPositionUpdated);

#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
            connect(m_source, &QGeoPositionInfoSource::errorOccurred, this, [](auto err){
                if (kLogGpsLifecycle)
                    qDebug() << "[GpsManager] errorOccurred:" << int(err);
            });
#endif

            // Timer para reiniciar el archivo NMEA al llegar al final
            m_nmeaLoopTimer.setInterval(300);
            connect(&m_nmeaLoopTimer, &QTimer::timeout, this, [this](){
                if (m_nmeaFile && m_nmeaFile->isOpen() && m_nmeaFile->atEnd()) {
                    m_nmeaFile->seek(0);
                    if (kLogGpsPosition)
                        qDebug() << "[GpsManager] NMEA loop(timer): seek(0)";
                }
            });

            if (kLogGpsLifecycle)
                qDebug() << "[GpsManager] Fuente NMEA lista.";

            return;
        }

        if (kLogGpsLifecycle)
            qDebug() << "[GpsManager] ERROR: createDefaultSource() devolvió nullptr y no hay NMEA.";

        return;
    }

    // Si sí hay fuente default
    if (kLogGpsLifecycle)
        qDebug() << "[GpsManager] Fuente de posicion creada:" << m_source->sourceName();

    m_source->setUpdateInterval(1000); // 1 Hz

    connect(m_source, &QGeoPositionInfoSource::positionUpdated,
            this, &GpsManager::onPositionUpdated);

#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
    connect(m_source, &QGeoPositionInfoSource::errorOccurred, this, [](auto err){
        if (kLogGpsLifecycle)
            qDebug() << "[GpsManager] errorOccurred:" << int(err);
    });
#endif
}

void GpsManager::start()
{
    if (!m_source)
        return;

    if (m_active)
        return;   // ya estaba activo

    if (m_nmeaFile && m_nmeaFile->isOpen() && m_nmeaFile->atEnd())
        m_nmeaFile->seek(0);

    if (m_nmea)
        m_nmeaLoopTimer.start();

    if (kLogGpsLifecycle)
        qDebug() << "[GpsManager] start(): iniciando actualizaciones de posicion...";

    m_source->startUpdates();
    m_active = true;
}

void GpsManager::stop()
{
    if (!m_source)
        return;

    if (!m_active)
        return;   // ya estaba inactivo

    if (m_nmeaLoopTimer.isActive())
        m_nmeaLoopTimer.stop();

    if (kLogGpsLifecycle)
        qDebug() << "[GpsManager] stop(): deteniendo actualizaciones de posicion.";

    m_source->stopUpdates();
    m_active = false;
}

void GpsManager::onPositionUpdated(const QGeoPositionInfo& info)
{
    if (!info.isValid()) {
        if (kLogGpsPosition)
            qDebug() << "[GpsManager] positionUpdated(): info no es valida.";
        return;
    }

    m_lastCoord = info.coordinate();
    m_lastAltitude = m_lastCoord.altitude(); // puede ser NaN
    m_lastTime = info.timestamp();

    if (!m_lastTime.isValid())
        m_lastTime = QDateTime::currentDateTimeUtc();

    if (kLogGpsPosition) {
        qDebug() << "[GpsManager] NUEVA POSICION:"
                 << "lat =" << m_lastCoord.latitude()
                 << "lon =" << m_lastCoord.longitude()
                 << "alt =" << m_lastAltitude
                 << "hora =" << m_lastTime;
    }

    emit positionUpdated(m_lastCoord, m_lastAltitude, m_lastTime);

    // loop para laptop con demo.nmea
    if (m_nmeaFile && m_nmeaFile->isOpen() && m_nmeaFile->atEnd()) {
        m_nmeaFile->seek(0);
        if (kLogGpsPosition)
            qDebug() << "[GpsManager] NMEA loop: seek(0)";
    }
}

// ------------------------------------------------------------
// Conversión Lat/Lon (WGS84) --> UTM
// Fórmulas estándar, precisión suficiente para uso de campo.
// ------------------------------------------------------------

static QChar latitudeBandLetter(double latDeg)
{
    // Bandas UTM C..X (omitidas I y O)
    if      (latDeg >= -80 && latDeg < -72) return 'C';
    else if (latDeg >= -72 && latDeg < -64) return 'D';
    else if (latDeg >= -64 && latDeg < -56) return 'E';
    else if (latDeg >= -56 && latDeg < -48) return 'F';
    else if (latDeg >= -48 && latDeg < -40) return 'G';
    else if (latDeg >= -40 && latDeg < -32) return 'H';
    else if (latDeg >= -32 && latDeg < -24) return 'J';
    else if (latDeg >= -24 && latDeg < -16) return 'K';
    else if (latDeg >= -16 && latDeg <  -8) return 'L';
    else if (latDeg >=  -8 && latDeg <   0) return 'M';
    else if (latDeg >=   0 && latDeg <   8) return 'N';
    else if (latDeg >=   8 && latDeg <  16) return 'P';
    else if (latDeg >=  16 && latDeg <  24) return 'Q';
    else if (latDeg >=  24 && latDeg <  32) return 'R';
    else if (latDeg >=  32 && latDeg <  40) return 'S';
    else if (latDeg >=  40 && latDeg <  48) return 'T';
    else if (latDeg >=  48 && latDeg <  56) return 'U';
    else if (latDeg >=  56 && latDeg <  64) return 'V';
    else if (latDeg >=  64 && latDeg <  72) return 'W';
    else if (latDeg >=  72 && latDeg <= 84) return 'X';
    return QChar();
}

bool GpsManager::toUTM(const QGeoCoordinate& coord, UTMCoord& outUTM)
{
    double latDeg = coord.latitude();
    double lonDeg = coord.longitude();

    // UTM solo está definido aproximadamente entre -80 y +84°
    if (latDeg < -80.0 || latDeg > 84.0)
        return false;

    // 1. Calcular zona UTM
    int zone = static_cast<int>(std::floor((lonDeg + 180.0) / 6.0)) + 1;

    // 2. Meridiano central de la zona
    double lon0Deg = (zone - 1) * 6 - 180 + 3;
    double lonRad  = qDegreesToRadians(lonDeg);
    double lon0Rad = qDegreesToRadians(lon0Deg);
    double latRad  = qDegreesToRadians(latDeg);

    // 3. Parámetros del elipsoide WGS84
    const double a  = 6378137.0;
    const double f  = 1.0 / 298.257223563;
    const double k0 = 0.9996;

    const double b  = a * (1.0 - f);
    const double e2 = (a*a - b*b) / (a*a);
    const double ep2 = e2 / (1.0 - e2);

    double sinLat = qSin(latRad);
    double cosLat = qCos(latRad);
    double tanLat = qTan(latRad);

    double N = a / qSqrt(1.0 - e2 * sinLat * sinLat);
    double T = tanLat * tanLat;
    double C = ep2 * cosLat * cosLat;
    double A = (lonRad - lon0Rad) * cosLat;

    // 4. Arco meridiano
    double M = a * (
                   (1 - e2/4.0 - 3*e2*e2/64.0 - 5*e2*e2*e2/256.0) * latRad
                   - (3*e2/8.0 + 3*e2*e2/32.0 + 45*e2*e2*e2/1024.0) * qSin(2*latRad)
                   + (15*e2*e2/256.0 + 45*e2*e2*e2/1024.0) * qSin(4*latRad)
                   - (35*e2*e2*e2/3072.0) * qSin(6*latRad)
                   );

    // 5. Coordenadas UTM
    double easting = k0 * N * ( A
                               + (1 - T + C) * qPow(A,3) / 6.0
                               + (5 - 18*T + T*T + 72*C - 58*ep2) * qPow(A,5) / 120.0
                               ) + 500000.0;

    double northing = k0 * ( M + N * tanLat * (
                                    A*A / 2.0
                                    + (5 - T + 9*C + 4*C*C) * qPow(A,4) / 24.0
                                    + (61 - 58*T + T*T + 600*C - 330*ep2) * qPow(A,6) / 720.0
                                    ));

    if (latDeg < 0)
        northing += 10000000.0;

    QChar band = latitudeBandLetter(latDeg);
    if (band.isNull())
        return false;

    outUTM.zone     = zone;
    outUTM.band     = band;
    outUTM.easting  = easting;
    outUTM.northing = northing;

    return true;
}


bool GpsManager::fromUTM(const UTMCoord& utm, QGeoCoordinate& outCoord)
{
    if (utm.zone < 1 || utm.zone > 60 || !utm.band.isLetter())
        return false;

    const bool northHemisphere = utm.band.toUpper() >= QChar('N');

    const double a = 6378137.0;
    const double f = 1.0 / 298.257223563;
    const double k0 = 0.9996;

    const double e = qSqrt(f * (2.0 - f));
    const double e2 = e * e;
    const double ep2 = e2 / (1.0 - e2);

    double x = utm.easting - 500000.0;
    double y = utm.northing;

    if (!northHemisphere)
        y -= 10000000.0;

    const double lon0Deg = (utm.zone - 1) * 6 - 180 + 3;
    const double lon0 = qDegreesToRadians(lon0Deg);

    const double M = y / k0;
    const double mu = M / (a * (1.0 - e2 / 4.0 - 3.0 * qPow(e2, 2) / 64.0 - 5.0 * qPow(e2, 3) / 256.0));

    const double e1 = (1.0 - qSqrt(1.0 - e2)) / (1.0 + qSqrt(1.0 - e2));

    const double J1 = 3.0 * e1 / 2.0 - 27.0 * qPow(e1, 3) / 32.0;
    const double J2 = 21.0 * qPow(e1, 2) / 16.0 - 55.0 * qPow(e1, 4) / 32.0;
    const double J3 = 151.0 * qPow(e1, 3) / 96.0;
    const double J4 = 1097.0 * qPow(e1, 4) / 512.0;

    const double fp = mu
                      + J1 * qSin(2.0 * mu)
                      + J2 * qSin(4.0 * mu)
                      + J3 * qSin(6.0 * mu)
                      + J4 * qSin(8.0 * mu);

    const double sinFp = qSin(fp);
    const double cosFp = qCos(fp);
    const double tanFp = qTan(fp);

    const double C1 = ep2 * cosFp * cosFp;
    const double T1 = tanFp * tanFp;
    const double N1 = a / qSqrt(1.0 - e2 * sinFp * sinFp);
    const double R1 = a * (1.0 - e2) / qPow(1.0 - e2 * sinFp * sinFp, 1.5);
    const double D = x / (N1 * k0);

    const double lat = fp - (N1 * tanFp / R1) *
                                (D * D / 2.0
                                 - (5.0 + 3.0 * T1 + 10.0 * C1 - 4.0 * C1 * C1 - 9.0 * ep2) * qPow(D, 4) / 24.0
                                 + (61.0 + 90.0 * T1 + 298.0 * C1 + 45.0 * T1 * T1 - 252.0 * ep2 - 3.0 * C1 * C1) * qPow(D, 6) / 720.0);

    const double lon = lon0 +
                       (D
                        - (1.0 + 2.0 * T1 + C1) * qPow(D, 3) / 6.0
                        + (5.0 - 2.0 * C1 + 28.0 * T1 - 3.0 * C1 * C1 + 8.0 * ep2 + 24.0 * T1 * T1) * qPow(D, 5) / 120.0) / cosFp;

    outCoord = QGeoCoordinate(qRadiansToDegrees(lat), qRadiansToDegrees(lon));
    return outCoord.isValid();
}
