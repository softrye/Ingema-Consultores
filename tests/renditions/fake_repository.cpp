// Costura de enlace para pruebas de la cola real (RenditionSyncController): misma
// clase y mismas señales que src/cpp/renditionrepository.h, sin red ni Supabase.
// Cada llamada se registra en FakeServer::calls; la prueba responde emitiendo las
// señales reales del repositorio (éxito, conflicto CAS, fallo de transporte…).
#include "src/cpp/renditionrepository.h"
#include "fake_repository.h"

QVariantList FakeServer::calls;

static void record(const QString &method, const QVariantMap &args = {})
{
    FakeServer::calls.append(QVariantMap{{QStringLiteral("method"), method}, {QStringLiteral("args"), args}});
}

RenditionRepository::RenditionRepository(QObject *parent) : QObject(parent) {}
void RenditionRepository::clear() { ++m_requestEpoch; record(QStringLiteral("clear")); }
void RenditionRepository::setFinancial(const QString &kind, const QVariantMap &operation) { record(QStringLiteral("setFinancial"), {{QStringLiteral("kind"), kind}, {QStringLiteral("operation"), operation}}); }
void RenditionRepository::requestExchangeQuote(const QString &, const QString &) {}
void RenditionRepository::receivedCommand(const QString &requestId, const QString &operation, const QVariantMap &arguments)
{ record(QStringLiteral("receivedCommand"), {{QStringLiteral("requestId"), requestId}, {QStringLiteral("operation"), operation}, {QStringLiteral("arguments"), arguments}}); }
void RenditionRepository::accessReceivedAttachment(const QString &, const QString &) {}
void RenditionRepository::listRenditions(int, const QString &, const QString &) { record(QStringLiteral("listRenditions")); }
void RenditionRepository::getRendition(const QString &id) { record(QStringLiteral("getRendition"), {{QStringLiteral("id"), id}}); }
void RenditionRepository::listProjects() { record(QStringLiteral("listProjects")); }
void RenditionRepository::createRendition(const QString &requestId, const QString &, const QString &, const QVariantList &, const QString &, const QString &)
{ record(QStringLiteral("createRendition"), {{QStringLiteral("requestId"), requestId}}); }
void RenditionRepository::editRendition(const QString &id, qint64 version, const QString &, const QString &, const QVariantList &, const QString &, const QString &, qint64)
{ record(QStringLiteral("editRendition"), {{QStringLiteral("id"), id}, {QStringLiteral("version"), version}}); }
void RenditionRepository::getDocumentLocation(const QString &) {}
void RenditionRepository::setDocumentLocation(const QString &, const QString &, qint64) {}
void RenditionRepository::getProjectWorkspace(const QString &) {}
void RenditionRepository::getDocumentSpace(const QString &) {}
void RenditionRepository::listDocumentFolders(const QString &, const QString &) {}
void RenditionRepository::getDocumentCapabilities(const QString &, const QString &) {}
void RenditionRepository::listExpenseCatalogs() {}
void RenditionRepository::listExpenses(const QString &id) { record(QStringLiteral("listExpenses"), {{QStringLiteral("id"), id}}); }
void RenditionRepository::getExpenseSummary(const QString &) {}
void RenditionRepository::addExpense(const QString &requestId, const QString &renditionId, qint64 expectedVersion,
                                     const QString &, const QString &, const QString &, const QString &, const QString &,
                                     const QString &, const QString &, const QString &, const QString &, const QString &,
                                     const QString &, const QString &amount, const QString &)
{ record(QStringLiteral("addExpense"), {{QStringLiteral("requestId"), requestId}, {QStringLiteral("renditionId"), renditionId},
                                        {QStringLiteral("expectedVersion"), expectedVersion}, {QStringLiteral("amount"), amount}}); }
void RenditionRepository::updateExpense(const QString &expenseId, const QString &, qint64 version, qint64, const QVariantMap &)
{ record(QStringLiteral("updateExpense"), {{QStringLiteral("expenseId"), expenseId}, {QStringLiteral("version"), version}}); }
void RenditionRepository::deleteExpense(const QString &, const QString &expenseId, qint64, qint64)
{ record(QStringLiteral("deleteExpense"), {{QStringLiteral("expenseId"), expenseId}}); }
void RenditionRepository::deleteDraft(const QString &, qint64) {}
void RenditionRepository::listVersions(const QString &) {}
void RenditionRepository::presentRendition(const QString &, qint64, const QString &) {}
void RenditionRepository::reserveAttachment(const QString &, const QString &, const QString &requestId, const QString &, const QString &, qint64, const QString &, const QString &)
{ record(QStringLiteral("reserveAttachment"), {{QStringLiteral("requestId"), requestId}}); }
QVariantMap RenditionRepository::localFileMetadata(const QString &) const { return {}; }
void RenditionRepository::uploadReservedAttachment(const QString &localFilePath, const QString &bucket, const QString &objectPath,
                                                   const QString &mimeType, const QString &attachmentId)
{ record(QStringLiteral("upload"), {{QStringLiteral("localFilePath"), localFilePath}, {QStringLiteral("bucket"), bucket},
                                    {QStringLiteral("objectPath"), objectPath}, {QStringLiteral("mimeType"), mimeType},
                                    {QStringLiteral("id"), attachmentId}}); }
void RenditionRepository::finalizeAttachment(const QString &) {}
void RenditionRepository::listAttachments(const QString &) {}
void RenditionRepository::getAttachmentAccess(const QString &) {}
void RenditionRepository::archiveAttachment(const QString &, qint64) {}
void RenditionRepository::listWorkingRows(const QString &id) { record(QStringLiteral("listWorkingRows"), {{QStringLiteral("id"), id}}); }
void RenditionRepository::saveWorkingRow(const QVariantMap &arguments) { record(QStringLiteral("saveWorkingRow"), arguments); }
void RenditionRepository::archiveWorkingRow(const QVariantMap &arguments) { record(QStringLiteral("archiveWorkingRow"), arguments); }
void RenditionRepository::reserveWorkingFile(const QVariantMap &arguments) { record(QStringLiteral("reserveWorkingFile"), arguments); }
void RenditionRepository::confirmWorkingFile(const QString &fileId) { record(QStringLiteral("confirmWorkingFile"), {{QStringLiteral("p_file_id"), fileId}}); }
void RenditionRepository::promoteWorkingRow(const QVariantMap &arguments) { record(QStringLiteral("promoteWorkingRow"), arguments); }
void RenditionRepository::openAuthorizedObject(const QString &, const QString &, const QVariantMap &) {}
