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
    bool requestDraftTrash(const QString &localId);
    bool markDraftTrashed(const QString &localId, const QVariantMap &remote);
    bool rejectDraftTrash(const QString &localId, const QString &error);
    bool requestRenditionArchive(const QString &localId);
    bool markRenditionArchived(const QString &localId, const QVariantMap &remote);
    bool rejectRenditionArchive(const QString &localId, const QString &error);
    QVariantList outbox() const { return m_outbox; }
    int pendingCount() const;
    QString lastError() const { return m_lastError; }
    QVariantMap editorDrafts() const { return m_editorDrafts; }
    // quiet: autoguardado mientras se escribe; no republica el estado (evita reconstruir la UI).
    bool saveEditorDraft(const QString &key, const QVariantMap &draft, bool quiet = false);

    Q_INVOKABLE void reload();
    bool saveFinancial(const QString &localId, const QString &kind,
                       const QVariantMap &values, qint64 expectedRowVersion);
    bool markFinancialState(const QString &localId, const QString &kind,
                            const QString &requestId, const QString &state,
                            const QString &error = {});
    bool markFinancialSynced(const QString &localId, const QString &kind,
                             const QString &requestId, const QVariantMap &remote);
    Q_INVOKABLE QString createDraft(const QString &periodStart,
                                    const QString &periodEnd,
                                    const QVariantList &projectIds,
                                    const QString &primaryProjectId,
                                    const QString &documentParentNodeId = {},
                                    const QString &spaceId = {},
                                    bool stageForSync = true,
                                    const QString &displayName = {});
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
    Q_INVOKABLE void mergeRemoteRenditions(const QVariantList &remoteRows, bool fromActiveList = true);
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

    // ---- Working Document (borradores de gasto en la nube, Web PR #6).
    // Mismo almacén persistente y MISMO outbox (working_save / working_promote /
    // working_archive) que procesa RenditionSyncController: un solo motor.
    // Implementación: renditionlocalstore_working.cpp.
    QVariantList workingRowsFor(const QString &renditionLocalId) const;   // vista para UI
    QVariantMap workingRow(const QString &workingId) const;
    int activeWorkingCount(const QString &renditionLocalId) const;
    int workingConflictCount(const QString &renditionLocalId) const;
    // Borradores cuya promoción a gasto CONFIRMÓ el servidor (no basta el outbox).
    QStringList promotedWorkingIds(const QString &renditionLocalId) const;
    // Crea/actualiza la intención deseada (form + sustentos). files: [{localUri,
    // fileName, mimeType, sizeBytes} | {id (sustento ya existente)}]. Devuelve el id.
    QString saveWorkingDraft(const QString &renditionLocalId, const QString &workingId,
                             const QVariantMap &form, const QVariantList &files,
                             const QString &expenseLocalId = {});
    bool requestWorkingPromotion(const QString &renditionLocalId, const QString &workingId);
    bool requestWorkingArchive(const QString &renditionLocalId, const QString &workingId);
    // Conflicto real: keepLocal=true reaplica la intención local sobre la versión
    // vigente del servidor (serverRow); false adopta la versión del servidor.
    bool resolveWorkingConflict(const QString &renditionLocalId, const QString &workingId,
                                bool keepLocal, const QVariantMap &serverRow);
    void mergeRemoteWorkingRows(const QString &renditionLocalId, const QVariantList &rows);
    // Transiciones de la cola.
    bool markWorkingSending(const QString &workingId, const QVariantMap &saveArguments);
    bool markWorkingSaved(const QString &workingId, const QVariantMap &serverRow);
    QVariantList workingPendingSources(const QString &workingId) const;
    bool markWorkingSourcePhase(const QString &workingId, const QString &sourceId,
                                const QString &phase, const QVariantMap &file = {});
    bool finishWorkingSave(const QString &workingId);
    bool markWorkingPromoted(const QString &workingId, const QVariantMap &result);
    bool markWorkingArchived(const QString &workingId, const QVariantMap &serverRow);
    bool markWorkingFailed(const QString &operation, const QString &workingId,
                           const QString &state, const QString &error);

signals:
    void accountIdChanged();
    void renditionsChanged();
    void outboxChanged();
    void pendingCountChanged();
    void lastErrorChanged();
    void persistenceFailed(const QString &message);

private:
    bool requestRenditionLifecycle(const QString &localId, bool archive);
    bool markRenditionLifecycle(const QString &localId, const QVariantMap &remote, bool archive);
    bool rejectRenditionLifecycle(const QString &localId, const QString &error, bool archive);
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
    // Working (renditionlocalstore_working.cpp)
    int workingIndex(const QString &workingId) const;
    QVariantMap workingDocument(const QVariantMap &row) const;
    QVariantMap workingOperation(const QVariantMap &outboxEntry) const;
    void adoptOwnRenditionVersion(const QString &renditionLocalId, qint64 version);
    QVariantList m_workingRows;

    AuthSession *m_auth = nullptr;
    QString m_accountScope;
    QVariantList m_renditions;
    QVariantList m_outbox;
    QVariantMap m_editorDrafts;
    qint64 m_nextSequence = 1;
    QString m_lastError;
};
