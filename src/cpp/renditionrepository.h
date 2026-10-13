#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

#include <functional>

class SupabaseClient;

class RenditionRepository final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QString contractMode READ contractMode CONSTANT)
    Q_PROPERTY(bool v02Enabled READ v02Enabled CONSTANT)
    Q_PROPERTY(QVariantList renditions READ renditions NOTIFY renditionsChanged)
    Q_PROPERTY(QVariantList projects READ projects NOTIFY projectsChanged)
    Q_PROPERTY(QVariantMap currentRendition READ currentRendition NOTIFY currentRenditionChanged)
    Q_PROPERTY(QVariantList expenses READ expenses NOTIFY expensesChanged)
    Q_PROPERTY(QVariantMap expenseSummary READ expenseSummary NOTIFY expenseSummaryChanged)
    Q_PROPERTY(QVariantList expenseCatalogs READ expenseCatalogs NOTIFY expenseCatalogsChanged)
    Q_PROPERTY(QVariantList versions READ versions NOTIFY versionsChanged)
    Q_PROPERTY(QVariantList attachments READ attachments NOTIFY attachmentsChanged)
    Q_PROPERTY(QVariantMap documentLocation READ documentLocation NOTIFY documentLocationChanged)
    Q_PROPERTY(QVariantMap documentWorkspace READ documentWorkspace NOTIFY documentWorkspaceChanged)
    Q_PROPERTY(QVariantMap documentSpace READ documentSpace NOTIFY documentSpaceChanged)
    Q_PROPERTY(QVariantList documentFolders READ documentFolders NOTIFY documentFoldersChanged)
    Q_PROPERTY(QVariantMap documentCapabilities READ documentCapabilities NOTIFY documentCapabilitiesChanged)

public:
    enum ContractMode { V01, V02 };
    Q_ENUM(ContractMode)

    // Único punto de cutover. Cambiar a V02 sólo después de confirmar que
    // backend #74 fue desplegado y validado en InGePlus-Dev.
    static constexpr ContractMode ActiveContractMode = V02;

    explicit RenditionRepository(QObject *parent = nullptr);

    bool busy() const { return m_pendingRequests > 0; }
    QString lastError() const { return m_lastError; }
    QString contractMode() const { return ActiveContractMode == V02 ? QStringLiteral("V02") : QStringLiteral("V01"); }
    bool v02Enabled() const { return ActiveContractMode == V02; }
    QVariantList renditions() const { return m_renditions; }
    QVariantList projects() const { return m_projects; }
    QVariantMap currentRendition() const { return m_currentRendition; }
    QVariantList expenses() const { return m_expenses; }
    QVariantMap expenseSummary() const { return m_expenseSummary; }
    QVariantList expenseCatalogs() const { return m_expenseCatalogs; }
    QVariantList versions() const { return m_versions; }
    QVariantList attachments() const { return m_attachments; }
    QVariantMap documentLocation() const { return m_documentLocation; }
    QVariantMap documentWorkspace() const { return m_documentWorkspace; }
    QVariantMap documentSpace() const { return m_documentSpace; }
    QVariantList documentFolders() const { return m_documentFolders; }
    QVariantMap documentCapabilities() const { return m_documentCapabilities; }

    Q_INVOKABLE void clear();
    // Administrative V2 adapter; contracts verified in InGePlus-Dev.
    void receivedCommand(const QString &requestId, const QString &operation,
                         const QVariantMap &arguments);
    void accessReceivedAttachment(const QString &requestId, const QString &attachmentId);
    Q_INVOKABLE void listRenditions(int limit = 20,
                                    const QString &afterUpdatedAt = {},
                                    const QString &afterId = {});
    Q_INVOKABLE void getRendition(const QString &renditionId);
    Q_INVOKABLE void listProjects();
    Q_INVOKABLE void createRendition(const QString &requestId,
                                     const QString &periodStart,
                                     const QString &periodEnd,
                                     const QVariantList &projectIds,
                                     const QString &primaryProjectId,
                                     const QString &documentParentNodeId = {});
    Q_INVOKABLE void editRendition(const QString &renditionId,
                                   qint64 expectedRowVersion,
                                   const QString &periodStart,
                                   const QString &periodEnd,
                                   const QVariantList &projectIds,
                                   const QString &primaryProjectId,
                                   const QString &documentParentNodeId = {},
                                   qint64 expectedDocumentNodeVersion = 0);

    Q_INVOKABLE void getDocumentLocation(const QString &renditionId);
    Q_INVOKABLE void setDocumentLocation(const QString &renditionId,
                                         const QString &documentParentNodeId,
                                         qint64 expectedDocumentNodeVersion = 0);
    Q_INVOKABLE void getProjectWorkspace(const QString &projectId);
    Q_INVOKABLE void getDocumentSpace(const QString &spaceId);
    Q_INVOKABLE void listDocumentFolders(const QString &spaceId,
                                         const QString &parentNodeId = {});
    Q_INVOKABLE void getDocumentCapabilities(const QString &spaceId,
                                             const QString &nodeId = {});

    Q_INVOKABLE void listExpenseCatalogs();
    Q_INVOKABLE void listExpenses(const QString &renditionId);
    Q_INVOKABLE void getExpenseSummary(const QString &renditionId);
    Q_INVOKABLE void addExpense(const QString &requestId,
                                const QString &renditionId,
                                qint64 expectedRenditionRowVersion,
                                const QString &projectId,
                                const QString &expenseDate,
                                const QString &categoryCode,
                                const QString &expenseConcept,
                                const QString &beneficiary,
                                const QString &paymentMethodCode,
                                const QString &paymentMethodDetail,
                                const QString &supportTypeCode,
                                const QString &supportNumber,
                                const QString &supportDetail,
                                const QString &currencyCode,
                                const QString &amount,
                                const QString &justification);
    Q_INVOKABLE void updateExpense(const QString &expenseId,
                                   const QString &renditionId,
                                   qint64 expectedExpenseRowVersion,
                                   qint64 expectedRenditionRowVersion,
                                   const QVariantMap &expense);
    Q_INVOKABLE void deleteExpense(const QString &renditionId,
                                   const QString &expenseId,
                                   qint64 expectedExpenseRowVersion,
                                   qint64 expectedRenditionRowVersion);
    void deleteDraft(const QString &renditionId, qint64 expectedRowVersion);

    Q_INVOKABLE void listVersions(const QString &renditionId);
    Q_INVOKABLE void presentRendition(const QString &renditionId,
                                      qint64 expectedRowVersion,
                                      const QString &requestId);

    Q_INVOKABLE void reserveAttachment(const QString &renditionId,
                                       const QString &expenseId,
                                       const QString &requestId,
                                       const QString &fileName,
                                       const QString &mimeType,
                                       qint64 sizeBytes,
                                       const QString &supportTypeCode,
                                       const QString &documentNumber = {});
    Q_INVOKABLE QVariantMap localFileMetadata(const QString &localFilePath) const;
    Q_INVOKABLE void uploadReservedAttachment(const QString &localFilePath,
                                              const QString &bucket,
                                              const QString &objectPath,
                                              const QString &mimeType,
                                              const QString &attachmentId);
    Q_INVOKABLE void finalizeAttachment(const QString &attachmentId);
    Q_INVOKABLE void listAttachments(const QString &renditionId);
    Q_INVOKABLE void getAttachmentAccess(const QString &attachmentId);
    Q_INVOKABLE void archiveAttachment(const QString &attachmentId,
                                       qint64 expectedRowVersion);

signals:
    void expensesLoaded(const QString &renditionId, const QVariantList &rows);
    void attachmentsLoaded(const QString &renditionId, const QVariantList &rows);
    void summaryLoaded(const QString &renditionId, const QVariantMap &summary);
    void documentLocationLoaded(const QString &renditionId, const QVariantMap &location);
    void receivedResult(const QString &requestId, const QString &operation,
                        const QVariant &payload);
    void receivedReset();
    void busyChanged();
    void lastErrorChanged();
    void renditionsChanged();
    void projectsChanged();
    void currentRenditionChanged();
    void expensesChanged();
    void expenseSummaryChanged();
    void expenseCatalogsChanged();
    void versionsChanged();
    void attachmentsChanged();
    void documentLocationChanged();
    void documentWorkspaceChanged();
    void documentSpaceChanged();
    void documentFoldersChanged();
    void documentCapabilitiesChanged();

    void operationFailed(const QString &operation,
                         const QString &code,
                         const QString &message);
    void operationSucceeded(const QString &operation);
    void renditionCreated(const QVariantMap &result);
    void renditionEdited(const QVariantMap &result);
    void expenseAdded(const QVariantMap &result);
    void expenseEdited(const QVariantMap &result);
    void expenseDeleted(const QVariantMap &result);
    void draftDeleted(const QVariantMap &result);
    void renditionPresented(const QVariantMap &result);
    void attachmentReserved(const QVariantMap &result);
    void attachmentUploaded(const QString &attachmentId);
    void attachmentFinalized(const QVariantMap &result);
    void attachmentAccessReady(const QVariantMap &result);
    void attachmentArchived(const QVariantMap &result);
    void documentLocationSet(const QVariantMap &result);

private:
    using SuccessHandler = std::function<void(const QVariant &)>;

    SupabaseClient *supabase() const;
    void callRpc(const QString &operation,
                 const QString &rpcName,
                 const QVariantMap &arguments,
                 SuccessHandler onSuccess);
    bool requireV02(const QString &operation);
    void setLastError(const QString &message);
    void beginRequest();
    void endRequest();

    static QVariantList rows(const QVariant &payload);
    static QVariantMap firstRow(const QVariant &payload);
    static QVariant nullableText(const QString &value);
    static QVariant nullablePositiveVersion(qint64 value);
    static QVariantList uuidArray(const QVariantList &values);
    static QVariantMap expenseArguments(const QVariantMap &expense);

    int m_pendingRequests = 0;
    quint64 m_requestEpoch = 0;
    QString m_lastError;
    QVariantList m_renditions;
    QVariantList m_projects;
    QVariantMap m_currentRendition;
    QVariantList m_expenses;
    QVariantMap m_expenseSummary;
    QVariantList m_expenseCatalogs;
    QVariantList m_versions;
    QVariantList m_attachments;
    QVariantMap m_documentLocation;
    QVariantMap m_documentWorkspace;
    QVariantMap m_documentSpace;
    QVariantList m_documentFolders;
    QVariantMap m_documentCapabilities;
};
