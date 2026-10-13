#pragma once
#include "RetroplasmaCamera.h"
#include "RetroplasmaDataProvider.h"
#include <QObject>
#include <QFutureWatcher>
#include <QThreadPool>
#include <QElapsedTimer>
#include <QTimer>
#include <QHash>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class RetroplasmaController final : public QObject {
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
public:
    explicit RetroplasmaController(QObject *parent=nullptr);
    ~RetroplasmaController() override;
    bool active()const{return m_active;}
    bool busy()const{return m_manifestBusy||!m_jobs.empty();}
    bool ready()const{return bool(m_scene);}
    bool navigationMode()const{return m_navigationMode;}
    QString status()const{return m_status;}
    QString sourceName()const{return m_scene?m_scene->source:QString();}
    QString coordinates()const;
    QVariantMap metrics()const;
    Q_INVOKABLE void open();
    Q_INVOKABLE void close();
    Q_INVOKABLE void loadScene(const QUrl &url);
    Q_INVOKABLE bool command(const QString &name);
    Q_INVOKABLE void orbit(double dx,double dy);
    Q_INVOKABLE void pan(double dx,double dy);
    Q_INVOKABLE void zoom(double scale);
    Q_INVOKABLE bool goTo(double latitude,double longitude,double altitude=0);
    void setViewport(double width,double height);
    inge::rp::Mat4 viewProjection()const{return m_camera.viewProjection(m_width/m_height);}
    std::vector<inge::rp::RenderTile> renderTiles()const{return m_renderTiles;}
    std::shared_ptr<inge::rp::MetricsMailbox> mailbox()const{return m_mailbox;}
signals:
    void changed();
    void renderChanged();
private:
    void tick();
    void schedule();
    void cancelJobs();
    void trimCache(const QSet<QString> &protectedKeys);
    struct Job {std::shared_ptr<std::atomic_bool> cancelled;};
    struct CacheEntry {std::shared_ptr<const inge::rp::LoadedTile> tile;quint64 used=0;};
    std::shared_ptr<const inge::rp::RetroplasmaDataProvider> m_provider;
    std::shared_ptr<const inge::rp::Scene> m_scene;
    std::shared_ptr<inge::rp::MetricsMailbox> m_mailbox;
    std::shared_ptr<std::atomic_bool> m_manifestCancel;
    QThreadPool m_pool;
    QHash<QString,Job> m_jobs;
    QHash<QString,CacheEntry> m_cache;
    QHash<QString,QString> m_failed;
    std::vector<inge::rp::RenderTile> m_renderTiles;
    inge::rp::Camera m_camera;
    QTimer m_tick;
    QElapsedTimer m_clock,m_telemetryClock;
    quint64 m_generation=0,m_usage=0,m_lastFrameCount=0;
    int m_ticks=0;
    double m_width=1,m_height=1,m_fps=0,m_frameMs=0;
    bool m_active=false,m_manifestBusy=false,m_navigationMode=false,m_appVisible=true;
    QString m_status=QStringLiteral("CLOSED");
};
