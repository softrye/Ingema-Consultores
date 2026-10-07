#pragma once
#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QUrl>

class SupabaseClient : public QObject {
    Q_OBJECT
public:
    SupabaseClient(const QString& projectUrl,
                   const QString& anonKey,
                   QObject* parent = nullptr);

    QString projectUrl() const { return m_projectUrl; }
    QString anonKey()    const { return m_anonKey; }

    QNetworkAccessManager* nam() { return &m_nam; }

    QNetworkRequest makeRequest(const QUrl& url,
                                const QString& bearerToken = QString(),
                                int transferTimeoutMs = 20000) const;

    QUrl authUrl(const QString& path) const; // /auth/v1/...
    QUrl restUrl(const QString& path) const; // /rest/v1/...

private:
    QString m_projectUrl;
    QString m_anonKey;
    mutable QNetworkAccessManager m_nam;
};
