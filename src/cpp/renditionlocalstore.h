#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>

class AuthSession;

class RenditionLocalStore final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString accountId READ accountId NOTIFY accountIdChanged)
    Q_PROPERTY(QString accountScope READ accountId NOTIFY accountIdChanged)
    Q_PROPERTY(QVariantList renditions READ renditions NOTIFY renditionsChanged)
    Q_PROPERTY(QVariantList outbox READ outbox NOTIFY outboxChanged)
    Q_PROPERTY(int pendingCount READ pendingCount NOTIFY pendingCountChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit RenditionLocalStore(AuthSession *auth, QObject *parent = nullptr);
    // Explicit isolated storage scope for native domain tests/tools without Auth.
    explicit RenditionLocalStore(const QString &accountScope, QObject *parent = nullptr);

    QString accountId() const { return m_accountScope; }
    QVariantList renditions() const;
    bool removeDraft(const QString &localId);
    bool markDraftDeleted(const QString &localId, const QVariantMap &remote);
    QVariantList outbox() const { return m_outbox; }
    int pendingCount() const;
    QString lastError() const { return m_lastError; }
    QVariantMap editorDrafts() const { return m_editorDrafts; }
    bool saveEditorDraft(const QString &key, const QVariantMap &draft);

    Q_INVOKABLE void reload();
    Q_INVOKABLE QString createDraft(const QString &periodStart,
                                    const QString &periodEnd,
                                    const QVariantList &projectIds,
                                    const QString &primaryProjectId,
                                    const QString &documentParentNodeId = {},
                                    const QString &spaceId = {},
                                    bool stageForSync = true);
    Q_INVOKABLE bool saveDraft(const QString &localId,
                               const QString &periodStart,
                               const QString &periodEnd,
                               const QVariantList &projectIds,
                               const QString &primaryProjectId,
                               qint64 rowVersion,
                               const QString &documentParentNodeId = {},
                               const QString &documentNodeId = {},
                               qint64 documentNodeVersion = 0,
                               const QString &spaceId = {},
                               bool stageForSync = true);
    Q_INVOKABLE QString addLocalExpense(const QString &renditionLocalId,
                                        const QVariantMap &expense,
                                        bool stageForSync = true);
    Q_INVOKABLE bool saveLocalExpense(const QString &renditionLocalId,
                                      const QString &expenseLocalId,
                                      const QVariantMap &expense,
                                      bool stageForSync = true);
    Q_INVOKABLE bool stageLocalOnlyChanges(bool requireDocumentLocation);
    Q_INVOKABLE bool removeLocalExpense(const QString &renditionLocalId,
                                        const QString &expenseLocalId);
    Q_INVOKABLE QString addLocalAttachment(const QString &renditionLocalId,
                                           const QString &expenseLocalId,
                                           const QVariantMap &attachment);
    Q_INVOKABLE bool updateAttachmentPhase(const QString &renditionLocalId,
                                           const QString &expenseLocalId,
                                           const QString &attachmentLocalId,
                                           const QString &phase,
                                           const QVariantMap &remote = {});
    Q_INVOKABLE QVariantMap rendition(const QString &localId) const;
    Q_INVOKABLE QVariantList expensesFor(const QString &localId) const;
    Q_INVOKABLE QVariantList attachmentsFor(const QString &localId,
                                             const QString &expenseLocalId) const;
    Q_INVOKABLE void mergeRemoteRenditions(const QVariantList &remoteRows);
    void reconcileCompleteRenditionList(const QVariantList &remoteRows);
    Q_INVOKABLE void mergeRemoteExpenses(const QString &renditionLocalId,
                                         const QVariantList &remoteRows);
    void mergeRemoteAttachments(const QString &localId, const QVariantList &rows);
    void adoptRemoteSummary(const QString &localId, const QVariantMap &summary);
    QVariantMap syncStatus(const QString &localId, bool active = false) const;
    Q_INVOKABLE bool adoptDocumentLocation(const QString &renditionLocalId,
                                           const QVariantMap &location);
    Q_INVOKABLE QString newRequestId() const;
    Q_INVOKABLE QString ensurePresentationRequestId(const QString &localId);
    Q_INVOKABLE QString presentationBlocker(const QString &localId) const;

    QVariantList pendingOperations() const;
    bool markRenditionSyncing(const QString &localId);
    Q_INVOKABLE bool markRenditionSynced(const QString &localId,
                                         const QVariantMap &remote);
    Q_INVOKABLE bool markRenditionState(const QString &localId,
                                        const QString &state,
                                        const QString &error = {});
    Q_INVOKABLE bool markPresentationState(const QString &localId,
                                           const QString &state,
                                           const QString &error = {});
    Q_INVOKABLE bool markRenditionPresented(const QString &localId,
                                            const QVariantMap &remote);
    bool markExpenseSyncing(const QString &renditionLocalId,
                            const QString &expenseLocalId);
    bool markExpenseSynced(const QString &renditionLocalId,
                           const QString &expenseLocalId,
                           const QVariantMap &remote);
    bool markExpenseState(const QString &renditionLocalId,
                          const QString &expenseLocalId,
                          const QString &state,
                          const QString &error = {});
    bool markExpenseNeedsReconciliation(const QString &renditionLocalId,
                                        const QString &expenseLocalId,
                                        const QString &error);

signals:
    void accountIdChanged();
    void renditionsChanged();
    void outboxChanged();
    void pendingCountChanged();
    void lastErrorChanged();
    void persistenceFailed(const QString &message);

private:
    void selectAccount(const QString &accountScope);
    QString storagePath() const;
    bool persist();
    void setLastError(const QString &message);
    int renditionIndex(const QString &localId) const;
    int renditionIndexByRemoteId(const QString &remoteId) const;
    int expenseIndex(const QVariantList &expenses, const QString &localId) const;
    int outboxIndex(const QString &operation, const QString &aggregateLocalId,
                    const QString &childLocalId = {}) const;
    void upsertOutbox(const QString &operation,
                      const QString &aggregateLocalId,
                      const QString &remoteId,
                      const QString &childLocalId,
                      const QString &requestId,
                      const QVariantMap &payload,
                      const QString &state);
    void markOutboxState(const QString &operation,
                         const QString &aggregateLocalId,
                         const QString &childLocalId,
                         const QString &state,
                         const QString &error = {});
    void rebuildLegacyOutbox();
    bool assertDraftStatus(const QVariantMap &rendition);
    static QString nowUtc();
    static QString newUuid();
    static QString remoteId(const QVariantMap &remote, const QString &entity = QStringLiteral("rendition"));
    static qint64 remoteRowVersion(const QVariantMap &remote, qint64 fallback);
    static QVariantMap canonicalDraftPayload(const QVariantMap &draft);
    static QByteArray payloadHash(const QVariantMap &payload);

    AuthSession *m_auth = nullptr;
    QString m_accountScope;
    QVariantList m_renditions;
    QVariantList m_outbox;
    QVariantMap m_editorDrafts;
    qint64 m_nextSequence = 1;
    QString m_lastError;
};
