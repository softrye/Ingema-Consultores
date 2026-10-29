#pragma once
#include "RetroplasmaCamera.h"
#include "RetroplasmaDataProvider.h"
#include "RetroplasmaTileScheduler.h"
#include "RetroplasmaGeoDocument.h"
#include <QObject>
#include <QFutureWatcher>
#include <QThreadPool>
#include <QElapsedTimer>
#include <QTimer>
#include <QHash>
#include <QSet>
#include <optional>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class RetroplasmaController : public QObject {
    Q_OBJECT
    QML_ANONYMOUS
    Q_PROPERTY(bool active READ active NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(bool ready READ ready NOTIFY changed)
    Q_PROPERTY(bool navigationMode READ navigationMode NOTIFY changed)
    Q_PROPERTY(QString status READ status NOTIFY changed)
    Q_PROPERTY(QString sourceName READ sourceName NOTIFY changed)
    Q_PROPERTY(QString coordinates READ coordinates NOTIFY changed)
    Q_PROPERTY(QVariantMap metrics READ metrics NOTIFY changed)
    Q_PROPERTY(QVariantMap cameraInfo READ cameraInfo NOTIFY changed)
    Q_PROPERTY(QVariantList geoLayers READ geoLayers NOTIFY geoChanged)
    Q_PROPERTY(QString documentMessage READ documentMessage NOTIFY geoChanged)
    Q_PROPERTY(double measurementKm READ measurementKm NOTIFY geoChanged)
    Q_PROPERTY(bool measuring READ measuring NOTIFY geoChanged)
public:
    explicit RetroplasmaController(QObject *parent=nullptr);
    ~RetroplasmaController() override;
    bool active()const{return m_active;}
    bool renderActive()const{return m_active&&m_appVisible;}
    quint64 sceneRevision()const{return m_generation;}
    bool busy()const{return m_manifestBusy||!m_jobs.empty();}
    bool ready()const{return bool(m_scene);}
    bool navigationMode()const{return m_navigationMode;}
    QString status()const{return m_status;}
    QString sourceName()const;
    QString coordinates()const;
    QVariantMap metrics()const;
    QVariantMap cameraInfo()const;
    QVariantList geoLayers()const;
    QString documentMessage()const{return m_documentMessage;}
    double measurementKm()const{return m_measurementKm;}
    bool measuring()const{return m_measuring;}
    Q_INVOKABLE bool importDocument(const QString &path);
    Q_INVOKABLE QString exportDocument(const QString &folder,const QString &name,bool kmz=false);
    Q_INVOKABLE void setLayerVisible(const QString &id,bool visible);
    Q_INVOKABLE void removeGeoLayer(const QString &id);
    Q_INVOKABLE void clearGeoLayers();
    Q_INVOKABLE void centerGeoLayer(const QString &id,int feature=-1);
    Q_INVOKABLE void addPlace(const QString &name);
    Q_INVOKABLE void beginMeasure();
    Q_INVOKABLE void cancelMeasure();
    Q_INVOKABLE bool selectPosition(double x,double y,bool marker=false);
    Q_INVOKABLE double scaleMetres(double pixels)const;
    Q_INVOKABLE void open();
    Q_INVOKABLE void close();
    Q_INVOKABLE void loadScene(const QUrl &url);
    Q_INVOKABLE void loadLocalScene(const QString &path);
    Q_INVOKABLE void retryScene();
    Q_INVOKABLE void openPlanet();
    Q_INVOKABLE void setPlanetImagery(const QString &layer,const QString &date=QString());
    Q_INVOKABLE bool command(const QString &name);
    Q_INVOKABLE void orbit(double dx,double dy);
    Q_INVOKABLE void pan(double dx,double dy);
    Q_INVOKABLE void zoom(double scale);
    Q_INVOKABLE void rotateView(double radians);
    Q_INVOKABLE bool goTo(double latitude,double longitude,double altitude=0);
    void setViewport(double width,double height,double pixelRatio=1);
    void framePresented();
    inge::rp::Mat4 viewProjection()const{return m_camera.viewProjection(m_width/m_height);}
    inge::rp::Vec3 viewLight()const{return m_scene&&m_scene->planetary?inge::rp::normalized(m_camera.eye()):inge::rp::Vec3{.25,1,.4};}
    std::vector<inge::rp::RenderTile> renderTiles()const{auto result=m_renderTiles;if(m_scene&&m_scene->planetary)result.insert(result.end(),m_geoTiles.begin(),m_geoTiles.end());return result;}
    std::shared_ptr<inge::rp::MetricsMailbox> mailbox()const{return m_mailbox;}
signals:
    void changed();
    void renderChanged();
    void geoChanged();
private:
    struct GeoLayer {QString id;inge::rp::GeoDocument document;bool visible=true;};
    void rebuildGeoTiles();
    std::vector<GeoLayer> m_geoLayers;
    std::vector<inge::rp::RenderTile> m_geoTiles;
    inge::rp::GeoFeature m_measureLine;
    bool m_measuring=false;
    double m_measurementKm=0,m_geoWidth=0;
    quint64 m_geoRevision=0;
    QString m_documentMessage;
    void tick();
    void schedule();
    void cancelJobs();
    void trimCache(const QSet<QString> &protectedKeys);
    inge::rp::Schedule chooseTiles(const QHash<QString,std::shared_ptr<const inge::rp::LoadedTile>> &)const;
    struct Job {std::shared_ptr<std::atomic_bool> cancelled;};
    struct CacheEntry {std::shared_ptr<const inge::rp::LoadedTile> tile;quint64 used=0;};
    std::shared_ptr<const inge::rp::RetroplasmaDataProvider> m_provider;
    std::shared_ptr<const inge::rp::Scene> m_scene;
    QUrl m_sceneUrl;
    std::shared_ptr<inge::rp::MetricsMailbox> m_mailbox;
    std::shared_ptr<std::atomic_bool> m_manifestCancel;
    QThreadPool m_pool;
    QHash<QString,Job> m_jobs;
    QHash<QString,CacheEntry> m_cache;
    QHash<QString,QString> m_failed;
    std::vector<inge::rp::RenderTile> m_renderTiles;
    inge::rp::Camera m_camera;
    std::optional<inge::rp::GeoPoint> m_pendingTarget;
    std::optional<inge::rp::Camera> m_preservedCamera;
    QTimer m_tick;
    QElapsedTimer m_clock,m_telemetryClock;
    quint64 m_generation=0,m_usage=0,m_presentedFrames=0,m_lastFrameCount=0;
    int m_ticks=0;
    double m_width=1,m_height=1,m_pixelRatio=1,m_fps=0,m_frameMs=0;
    bool m_active=false,m_manifestBusy=false,m_navigationMode=false,m_appVisible=true;
    QString m_status=QStringLiteral("CLOSED");
};
