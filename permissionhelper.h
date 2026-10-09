#pragma once

#include <QObject>
#include <QTimer>
#include <QDateTime>
#include <QUrl>
#include <QtGlobal>
#include <QtCore/qnumeric.h>

class QGeoPositionInfo;
class QGeoPositionInfoSource;

// Fuente unica de geolocalizacion para QML.
// - Solicita permiso PRECISO.
// - Mantiene un unico watcher continuo.
// - El boton de ubicacion solo recentra o pide una lectura inmediata;
//   nunca duplica listeners ni reinicia el proveedor.
class PermissionHelper : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool nativeLocationSupported READ nativeLocationSupported CONSTANT)
    Q_PROPERTY(bool nativePermissionGranted READ nativePermissionGranted NOTIFY nativePermissionChanged)
    Q_PROPERTY(QString nativePermissionStatus READ nativePermissionStatus NOTIFY nativePermissionChanged)
    Q_PROPERTY(bool nativeTracking READ nativeTracking NOTIFY nativeTrackingChanged)
    Q_PROPERTY(bool nativeImmediateRequestPending READ nativeImmediateRequestPending NOTIFY nativeImmediateRequestPendingChanged)
    Q_PROPERTY(bool nativeHasFix READ nativeHasFix NOTIFY nativeLocationChanged)
    Q_PROPERTY(double nativeLatitude READ nativeLatitude NOTIFY nativeLocationChanged)
    Q_PROPERTY(double nativeLongitude READ nativeLongitude NOTIFY nativeLocationChanged)
    Q_PROPERTY(double nativeAltitude READ nativeAltitude NOTIFY nativeLocationChanged)
    Q_PROPERTY(double nativeAccuracy READ nativeAccuracy NOTIFY nativeLocationChanged)
    Q_PROPERTY(qint64 nativeTimestampMs READ nativeTimestampMs NOTIFY nativeLocationChanged)
    Q_PROPERTY(QString nativeProvider READ nativeProvider NOTIFY nativeLocationChanged)
    Q_PROPERTY(QString nativeLocationStatus READ nativeLocationStatus NOTIFY nativeLocationStatusChanged)
    Q_PROPERTY(QString nativeLocationError READ nativeLocationError NOTIFY nativeLocationStatusChanged)

public:
    explicit PermissionHelper(QObject *parent = nullptr);
    ~PermissionHelper() override;

    Q_INVOKABLE void requestLocationPermission();
    Q_INVOKABLE void requestLocation();
    Q_INVOKABLE void requestPermissions();
    Q_INVOKABLE bool hasLocationPermission() const;
    Q_INVOKABLE bool isLocationServiceEnabled() const;
    Q_INVOKABLE bool openLocationSettings();
    Q_INVOKABLE bool openApplicationSettings();

    // Adaptador acotado del Home Flutter add-to-app. NavigationShellV51 sigue
    // siendo propiedad de QML y consume las acciones mediante take...().
    Q_INVOKABLE bool setFlutterHomeVisible(bool visible,
                                             const QString &themeMode,
                                             double motionScale,
                                             double glassIntensity,
                                             const QString &performanceProfile);
    Q_INVOKABLE bool setFlutterRenditionsVisible(bool visible,
                                                 const QString &themeMode,
                                                 double motionScale,
                                                 double glassIntensity,
                                                 const QString &performanceProfile);
    Q_INVOKABLE bool isFlutterHomeReady() const;
    Q_INVOKABLE QString takeFlutterHomeAction();
    Q_INVOKABLE bool setFlutterAuthVisible(bool visible,
                                           const QString &authStateJson,
                                           const QString &themeMode,
                                           double motionScale,
                                           double glassIntensity,
                                           const QString &performanceProfile);
    Q_INVOKABLE bool setFlutterSecurityVisible(bool visible,
                                               const QString &authStateJson,
                                               const QString &themeMode,
                                               double motionScale,
                                               double glassIntensity,
                                               const QString &performanceProfile);
    Q_INVOKABLE bool updateFlutterAuthState(const QString &authStateJson);
    Q_INVOKABLE QString takeFlutterAuthRequest();

    Q_INVOKABLE bool startNativeLocationUpdates();
    Q_INVOKABLE void stopNativeLocationUpdates();
    Q_INVOKABLE void refreshNativeLocation();
    Q_INVOKABLE bool requestImmediateLocationUpdate();

    // Selector Android compartido por el formulario de calicatas. El resultado
    // se copia a cache privado antes de llegar a QML para que content:// no quede
    // atado a la vida de la Activity externa.
    Q_INVOKABLE void capturePhoto(int targetIdx);
    Q_INVOKABLE void pickPhoto(int targetIdx);
    Q_INVOKABLE void releaseImportedPhoto(const QUrl &localUrl);
    // Android puede matar el proceso mientras la camara externa esta delante
    // (habitual en equipos de 2-4 GB). La captura pendiente se guarda en
    // QSettings con la ficha que la pidio; al reabrir esa ficha se recupera
    // por el mismo camino (photoSelected) y no se pierde la foto.
    Q_INVOKABLE void setPhotoCaptureContext(const QString &contextKey);
    Q_INVOKABLE int pendingCaptureSlot(const QString &contextKey) const;
    Q_INVOKABLE bool recoverPendingCapture(const QString &contextKey);

    bool nativeLocationSupported() const;
    bool nativePermissionGranted() const { return hasLocationPermission(); }
    QString nativePermissionStatus() const { return m_nativePermissionStatus; }
    bool nativeTracking() const { return m_nativeTracking; }
    bool nativeImmediateRequestPending() const { return m_immediateRequestPending; }
    bool nativeHasFix() const { return m_nativeHasFix; }
    double nativeLatitude() const { return m_nativeLatitude; }
    double nativeLongitude() const { return m_nativeLongitude; }
    double nativeAltitude() const { return m_nativeAltitude; }
    double nativeAccuracy() const { return m_nativeAccuracy; }
    qint64 nativeTimestampMs() const { return m_nativeTimestampMs; }
    QString nativeProvider() const { return m_nativeProvider; }
    QString nativeLocationStatus() const { return m_nativeLocationStatus; }
    QString nativeLocationError() const { return m_nativeLocationError; }

signals:
    void nativePermissionChanged();
    void nativeTrackingChanged();
    void nativeImmediateRequestPendingChanged();
    void nativeLocationChanged();
    void nativeLocationStatusChanged();
    void photoSelected(int targetIdx, const QUrl &localUrl, const QString &sourceKind);
    void photoSelectionCanceled(int targetIdx, const QString &sourceKind);
    void photoSelectionError(int targetIdx, const QString &code, const QString &message);
    // Permite al GraphicsCore relajar la persistencia del scene graph mientras
    // Android sustituye temporalmente la Surface de Qt por Cámara/Galería.
    void externalPhotoActivityStarted();
    void externalPhotoActivityFinished();

private:
    bool ensurePositionSource();
    void refreshPermissionState();
    void handlePositionUpdated(const QGeoPositionInfo &info);
    void handleSourceError(int errorValue);
    void handleUpdateTimeout();
    bool acceptPosition(const QGeoPositionInfo &info);
    void setNativeTracking(bool tracking);
    void setImmediateRequestPending(bool pending);
    void setNativeStatus(const QString &status, const QString &error);
    void launchCamera(int targetIdx);
    void launchGallery(int targetIdx);
    void finishPhotoActivity(int targetIdx, const QString &sourceKind,
                             int resultCode, const QString &contentUri);
    void persistPendingCapture(int targetIdx);
    void clearPersistedPendingCapture();

    QGeoPositionInfoSource *m_positionSource = nullptr;
    QTimer m_watchdogTimer;
    QTimer m_immediateRequestTimer;
    bool m_permissionRequestPending = false;
    bool m_nativeTracking = false;
    bool m_immediateRequestPending = false;
    bool m_nativeHasFix = false;
    double m_nativeLatitude = qQNaN();
    double m_nativeLongitude = qQNaN();
    double m_nativeAltitude = qQNaN();
    double m_nativeAccuracy = qQNaN();
    qint64 m_nativeTimestampMs = 0;
    qint64 m_lastSourceEventMs = 0;
    qint64 m_lastPublishedWallClockMs = 0;
    int m_suppressedNoiseFixes = 0;
    QString m_nativeProvider;
    QString m_nativePermissionStatus = QStringLiteral("undetermined");
    QString m_nativeLocationStatus = QStringLiteral("idle");
    QString m_nativeLocationError;
    bool m_photoRequestInFlight = false;
    QString m_pendingCameraUri;
    QString m_pendingCameraFilePath;
    QString m_photoCaptureContext;
};
