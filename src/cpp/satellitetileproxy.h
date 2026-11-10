#pragma once

#include <QByteArray>
#include <QJsonObject>
#include <QList>
#include <QNetworkAccessManager>
#include <QObject>
#include <QPointer>
#include <QString>
#include <QStringList>
#include <QTcpServer>
#include <QTcpSocket>

// Traductor local de cuadros satelitales: el plugin QtLocation "osm" solo arma
// host/z/x/y.png; las imágenes de Cesium ion (Bing Aerial, asset 2) usan quadkey.
// Este proxy escucha en 127.0.0.1 (puerto efímero) y devuelve el JPEG real.
// El token de Cesium ion NUNCA sale de C++ ni se escribe en logs.
class SatelliteTileProxy : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString baseUrl READ baseUrl NOTIFY stateChanged)
    Q_PROPERTY(bool available READ available NOTIFY stateChanged)
    Q_PROPERTY(QString attribution READ attribution NOTIFY stateChanged)
    Q_PROPERTY(int maxZoom READ maxZoom NOTIFY stateChanged)

public:
    explicit SatelliteTileProxy(QObject *parent = nullptr);

    // Arranca el servidor y carga los metadatos (una sola vez). Seguro de repetir.
    Q_INVOKABLE void ensureStarted();

    QString baseUrl() const;
    bool available() const { return m_state != State::Failed; }
    QString attribution() const { return m_attribution; }
    int maxZoom() const { return m_maxZoom; }

signals:
    void stateChanged();

private:
    enum class State { Idle, Loading, Ready, Failed };
    struct Pending { int z; int x; int y; QPointer<QTcpSocket> socket; };

    static QString cesiumIonToken();
    static QString quadKey(int z, int x, int y);

    void onNewConnection();
    void onReadyRead(QTcpSocket *socket);
    void serveTile(const Pending &request);
    void loadMetadata();
    void fail(const char *reason);
    void respond(QTcpSocket *socket, int status, const QByteArray &contentType, const QByteArray &body);

    QTcpServer m_server;
    QNetworkAccessManager m_network;
    State m_state = State::Idle;
    QString m_imageUrl;
    QStringList m_subdomains;
    QString m_attribution = QStringLiteral("© Microsoft Bing · Cesium ion");
    int m_maxZoom = 19;
    QList<Pending> m_pending;
};
