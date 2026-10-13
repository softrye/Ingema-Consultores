// SPDX-License-Identifier: GPL-3.0-only
// Qt port of Nothing Files (see THIRD_PARTY_NOTICES_NOTHING.md).
#pragma once
#include <QAbstractListModel>
#include <QFutureWatcher>
#include <QSet>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>
#include <functional>
#include "drivejournal.h"
class SupabaseStorageProvider;
class QTimer;

class CloudDocs;
class DocsOps;
class NothingDocuments : public QAbstractListModel
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(QString route READ route NOTIFY changed)
    Q_PROPERTY(QString folder READ folder NOTIFY changed)
    Q_PROPERTY(QString rootPath READ rootPath NOTIFY changed)
    Q_PROPERTY(QString category READ category NOTIFY changed)
    Q_PROPERTY(QString query READ query WRITE setQuery NOTIFY changed)
    Q_PROPERTY(QString sortOrder READ sortOrder WRITE setSortOrder NOTIFY changed)
    Q_PROPERTY(bool grid READ grid WRITE setGrid NOTIFY changed)
    Q_PROPERTY(QString theme READ theme WRITE setTheme NOTIFY changed)
    Q_PROPERTY(bool oled READ oled WRITE setOled NOTIFY changed)
    Q_PROPERTY(bool busy READ busy NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QVariantMap stats READ stats NOTIFY changed)
    Q_PROPERTY(QVariantList recents READ recents NOTIFY changed)
    Q_PROPERTY(int selectedCount READ selectedCount NOTIFY changed)
    Q_PROPERTY(int clipboardCount READ clipboardCount NOTIFY changed)
    Q_PROPERTY(int count READ count NOTIFY changed)
    Q_PROPERTY(bool moreRemote READ moreRemote NOTIFY changed)
    Q_PROPERTY(QString location READ location NOTIFY changed)
    Q_PROPERTY(QString remoteTitle READ remoteTitle NOTIFY changed)
    Q_PROPERTY(int pendingSync READ pendingSync NOTIFY changed)
    // Server-resolved capabilities (get_document_structural_capabilities_v02)
    // of the open InGe Drive folder; the backend stays the final authority.
    Q_PROPERTY(QVariantMap folderCapabilities READ folderCapabilities NOTIFY changed)
    Q_PROPERTY(int capabilitiesRevision READ capabilitiesRevision NOTIFY changed)
    Q_PROPERTY(QString currentFolderPath READ currentFolderPath NOTIFY changed)
    // Destino canónico de "Subir a InGe Drive": última carpeta de InGe Drive abierta.
    Q_PROPERTY(QString uploadTargetLabel READ uploadTargetLabel NOTIFY changed)
public:
    explicit NothingDocuments(QObject *parent = nullptr);
    ~NothingDocuments() override;
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int,QByteArray> roleNames() const override;
    QString route() const { return m_route; }
    QString folder() const { return m_folder; }
    QString rootPath() const { return m_root; }
    QString category() const { return m_category; }
    QString query() const { return m_query; }
    QString sortOrder() const { return m_sort; }
    QString theme() const { return m_theme; }
    bool grid() const { return m_grid; }
    bool oled() const { return m_oled; }
    bool busy() const { return m_busy; }
    QString error() const { return m_error; }
    QVariantMap stats() const { return m_stats; }
    QVariantList recents() const { return m_recents; }
    int selectedCount() const { return m_selected.size(); }
    int clipboardCount() const { return m_clipboard.size() + (m_remoteMove.isEmpty() ? 0 : 1); }
    QString location() const { return m_route == "drive" ? "DRIVE:" + m_project + ":" + m_remoteDir : "LOCAL:" + m_folder; }
    QString remoteTitle() const { return m_remoteTitle; }
    int count() const { return m_rows.size(); }
    bool moreRemote() const { return m_moreRemote; }
    int pendingSync() const { return m_journal.outbox.size(); }
    QVariantMap folderCapabilities() const { return m_folderCaps; }
    int capabilitiesRevision() const { return m_capsRevision; }
    QString currentFolderPath() const { return m_currentEntry.value("path").toString(); }
    QString uploadTargetLabel() const { return m_uploadSpace.isEmpty() ? QString() : (m_uploadTitle.isEmpty() ? QStringLiteral("InGe Drive") : m_uploadTitle); }
    // Per-node capabilities (item menu). requestCapabilities fetches them; the
    // result is read with capabilitiesFor(path) (bind to capabilitiesRevision).
    Q_INVOKABLE void requestCapabilities(const QString &path);
    Q_INVOKABLE QVariantMap capabilitiesFor(const QString &path) const { return m_nodeCaps.value(path); }
    Q_INVOKABLE QVariantMap currentFolderEntry() const { return m_currentEntry; }
    // Human-readable location of the open folder ("InGe Drive / Espacio / Carpeta").
    Q_INVOKABLE QString breadcrumb() const;
    Q_INVOKABLE void retrySync();
    Q_INVOKABLE void keepServerVersion();
    void setQuery(const QString &value);
    void setSortOrder(const QString &value);
    void setGrid(bool value);
    void setTheme(const QString &value);
    void setOled(bool value);
    Q_INVOKABLE void navigate(const QString &route, const QString &value = {});
    Q_INVOKABLE bool back();
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void loadMore();
    Q_INVOKABLE void toggleSelection(const QString &path);
    Q_INVOKABLE void clearSelection();
    Q_INVOKABLE void selectAll();
    Q_INVOKABLE bool selected(const QString &path) const;
    Q_INVOKABLE QStringList selection() const;
    Q_INVOKABLE void clipboard(const QStringList &paths, bool cut);
    Q_INVOKABLE void cancelClipboard();
    Q_INVOKABLE void paste();
    Q_INVOKABLE void create(const QString &name, bool directory);
    Q_INVOKABLE void rename(const QString &path, const QString &name);
    Q_INVOKABLE void trash(const QStringList &paths);
    Q_INVOKABLE void restore(const QStringList &paths);
    Q_INVOKABLE void removeForever(const QStringList &paths);
    Q_INVOKABLE void emptyTrash();
    Q_INVOKABLE void archive(const QString &path, bool extract);
    Q_INVOKABLE void readText(const QString &path);
    Q_INVOKABLE void open(const QVariantMap &entry, bool chooser = false, bool share = false);
    Q_INVOKABLE void upload(const QString &localPath, const QString &projectId, const QString &relativePath);
    Q_INVOKABLE void download(const QVariantMap &entry);
    Q_INVOKABLE void requestStorageAccess();
    Q_INVOKABLE bool hasStorageAccess() const;
    Q_INVOKABLE static QString formatSize(qint64 bytes);
signals:
    void renditionOpenRequested(const QString &renditionId);
    void calicataOpenRequested(const QString &projectId, const QString &calicataId);
    void changed();
    void completed(const QString &message, const QString &path);
    void textReady(const QString &content);
private:
    void resetAccount();
    void applyRows();
    void saveSettings();
    void run(std::function<QVariantMap()> job, bool operation = false);
    void localOperation(const QString &op, const QStringList &paths, const QString &argument = {});
    void configureCloud();
    void remoteList(bool append = false);
    void onlineRequest(const QString &endpoint, const QVariantMap &arguments,
                       std::function<void(const QVariantList &)> success, bool get = false);
    void remoteMutation(const QString &operation, const QString &node, const QString &argument = {});
    QString treeKey() const { return m_space+":"+m_remoteDir; }
    void reconcile();
    void storageUsage();
    QVariantMap remoteEntry(const QString &path) const;
    void setError(const QString &error);
    bool checkPaths(const QStringList &paths, bool allowTrash = false);
    void loadCapabilities(const QString &nodeId, const QString &path);
    // Espejo local Files Core: identidad (space_id, node_id); contenido por content_version.
    QString mirrorDir(const QString &space, const QString &nodeId) const;
    QVariantMap readMirror(const QString &dir) const;
    QString mirrorState(const QString &nodeId, qint64 remoteContentVersion) const;
    void openMirrored(const QString &path, const QString &state);
    void finishDownload(const QString &path);
    QString m_root, m_folder, m_uid, m_category, m_query, m_error;
    QString m_route = "home", m_sort = "name", m_theme = "system";
    bool m_grid = false, m_oled = false, m_busy = true, m_cut = false;
    bool m_moreRemote = false, m_appendRemote = false, m_pendingRefresh = false;
    int m_epoch = 0, m_remoteOffset = 0;
    QString m_project, m_remoteDir, m_downloadOpen;
    QString m_space, m_remoteTitle;
    QVariantMap m_remoteMove;
    QVariantMap m_downloadEntry;
    QVariantList m_all, m_rows, m_recents, m_history;
    QVariantMap m_stats;
    QSet<QString> m_selected;
    QStringList m_clipboard;
    QFutureWatcher<QVariantMap> m_worker;
    DocsOps *m_rootResolver = nullptr;
    CloudDocs *m_cloud = nullptr;
    SupabaseStorageProvider *m_provider = nullptr;
    DriveJournal m_journal;
    QTimer *m_searchTimer = nullptr;
    bool m_syncing = false;
    QVariantMap m_currentEntry;            // open remote folder (id, node_version, name, path)
    QVariantMap m_folderCaps;              // capabilities of the open folder
    QHash<QString, QVariantMap> m_nodeCaps; // by path; also keeps the last known set per folder offline
    int m_capsRevision = 0;
    QString m_uploadSpace, m_uploadParent, m_uploadTitle;
};
