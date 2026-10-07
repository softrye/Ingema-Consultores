#pragma once

#include <QObject>
#include <QString>
#include <QNetworkAccessManager>
#include <QPointer>

class QNetworkReply;

class DropboxBridge : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    Q_PROPERTY(QString accountLabel READ accountLabel NOTIFY accountLabelChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit DropboxBridge(QObject *parent = nullptr);

    bool connected() const { return !m_accessToken.trimmed().isEmpty(); }
    QString accountLabel() const { return m_accountLabel; }
    QString lastError() const { return m_lastError; }

    Q_INVOKABLE void connectWithToken(const QString& token);
    Q_INVOKABLE void clearToken();
    Q_INVOKABLE void openOAuthUrl(const QString& appKey);
    Q_INVOKABLE void uploadFile(const QString& localPathOrUrl, const QString& dropboxPath);
    Q_INVOKABLE QString normalizeDropboxPath(const QString& path) const;

signals:
    void connectedChanged();
    void accountLabelChanged();
    void lastErrorChanged();
    void connectedOk();
    void uploadOk(const QString& dropboxPath);
    void uploadFail(const QString& message);
    void oauthUrlOpened(const QString& url);

private:
    QString readablePath(const QString& localPathOrUrl) const;
    void setError(const QString& message);

private:
    QString m_accessToken;
    QString m_accountLabel;
    QString m_lastError;
    QNetworkAccessManager m_nam;
    QPointer<QNetworkReply> m_reply;
};
