#pragma once
#include <QObject>
#include <QVariantMap>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QNetworkReply>
#include <QJsonObject>
#include <functional>

// Transport only: the existing RenditionExportService owns persistence/retries.
class GoogleDriveExportTransport final : public QObject {
public:
    using Checkpoint = std::function<bool(const QVariantMap &)>;
    using Completion = std::function<void(QVariantMap, QString, bool)>;
    explicit GoogleDriveExportTransport(QObject *parent = nullptr);
    void upload(const QVariantMap &row, Checkpoint checkpoint, Completion done, bool interactive);
    void cancel();
    void authorized(const QString &request, const QString &token, const QString &picked, const QString &error);
    static void dispatchAuthorization(const QString &, const QString &, const QString &, const QString &);
private:
    void authorize(bool picker);
    void folder();
    void reserve();
    void probe();
    void sendFile();
    bool verify(const QJsonObject &file) const;
    void request(const QByteArray &method, const QString &path, const QByteArray &body,
                 const QByteArray &mime, std::function<void(int, QJsonObject)> next);
    void finish(QVariantMap result, const QString &error = {}, bool retryable = false);
    QNetworkAccessManager m_network;
    QPointer<QNetworkReply> m_reply;
    QVariantMap m_row;
    Checkpoint m_checkpoint;
    Completion m_done;
    QByteArray m_bytes;
    QString m_request, m_token, m_account;
    quint64 m_epoch = 0;
    bool m_interactive = false, m_picker = false, m_triedPicker = false, m_afterUpload = false;
};
