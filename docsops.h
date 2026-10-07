#pragma once
#include <QObject>
#include <QFutureWatcher>
#include <QtQml/qqmlregistration.h>

class DocsOps : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit DocsOps(QObject* parent=nullptr);
    ~DocsOps() override;

    QString lastError() const { return m_lastError; }

    Q_INVOKABLE static QString ingeBasePath();
    Q_INVOKABLE QString localUserRoot() const;
    Q_INVOKABLE QString userRoot(const QString& uid) const;

    // ⚠️ SLOW (sync). No la llames desde QML en UI thread si quieres evitar freezes.
    static QString scopedRoot(const QString& uid);

    // ✅ ASYNC (safe): resuelve root en worker thread y emite scopedRootReady(...)
    Q_INVOKABLE void applyScopedRoot(const QString& uid);

    Q_INVOKABLE QString parentDir(const QString& path) const;

    Q_INVOKABLE bool makeDir(const QString& parentDir, const QString& name);
    Q_INVOKABLE bool removePath(const QString& path);
    Q_INVOKABLE bool renameInPlace(const QString& oldPath, const QString& newName);

    Q_INVOKABLE QString copyToDir(const QString& srcPath, const QString& dstDir);
    Q_INVOKABLE QString moveToDir(const QString& srcPath, const QString& dstDir);
    Q_INVOKABLE bool exportLocalDataToUser(const QString& userDir, bool overwrite);

signals:
    void lastErrorChanged();

    // ok, rootAbs, err
    void scopedRootReady(bool ok, const QString& rootAbs, const QString& err);

private:
    void setErr(const QString& e);

    static void ensureDefaultRecursos(const QString& userRoot);
    bool copyDirRec(const QString& srcDir, const QString& dstDir);

    struct ScopedResult {
        int token = 0;
        bool ok = false;
        QString rootAbs;
        QString err;
    };

    void startScopedRootAsync(int token, const QString& uid);

    QString m_lastError;

    // tokens para ignorar resultados viejos
    int m_scopedReqToken = 0;
    int m_scopedRunningToken = 0;
    QString m_scopedPendingUid;
    QFutureWatcher<ScopedResult> m_scopedWatcher;
};
