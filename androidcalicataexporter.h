#pragma once

#include <QObject>
#include <QVariantMap>
#include <QString>
#include <QHash>
class RenditionExportService;

class AndroidCalicataExporter : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QVariantMap lastExportResult READ lastExportResult NOTIFY exportResultChanged)

public:
    explicit AndroidCalicataExporter(QObject *parent = nullptr);

    QString lastError() const;
    QVariantMap lastExportResult() const;
    Q_INVOKABLE void retryPendingExports();
    Q_INVOKABLE bool openLastExport(bool share = false);

    Q_INVOKABLE QString defaultExportDir() const;
    Q_INVOKABLE QString exportStateToXlsx(const QVariantMap &state, const QString &fileBaseName = QString(),
                                         const QString &provider = QStringLiteral("GOOGLE_DRIVE"));
    Q_INVOKABLE QString exportJsonFileToXlsx(const QString &jsonPath, const QString &fileBaseName = QString());
    // Importación de Calicatas: lectura segura (solo .xlsx, sin macros ni objetos)
    // de las celdas de texto y rangos combinados. La interpretación vive en
    // qml/Mobile/lib/CalicataExcelImport.js (detector + adapters + reporte).
    Q_INVOKABLE QVariantMap readWorkbookCells(const QString &path) const;
    Q_INVOKABLE bool publishCalicata(const QVariantMap &portableState, const QString &xlsxPath = QString());
    // P6: PDF of the ficha from the portable state (named by its hash) and its
    // publication to the project's InGeDrive through the persistent export queue.
    Q_INVOKABLE QString exportCalicataToPdf(const QVariantMap &portableState, const QString &resourcesBase = QString());
    Q_INVOKABLE bool publishCalicataPdf(const QVariantMap &portableState, const QString &pdfPath);
    Q_INVOKABLE bool openExportedFile(const QString &path, bool share = false);
    Q_INVOKABLE bool sharePublishedCalicata(const QString &documentId);
    Q_INVOKABLE QString exportGenericWorkbookToXlsx(const QVariantMap &state, const QString &fileBaseName = QString());
    QString exportRenditionToXlsx(const QVariantMap &state, const QString &fileBaseName = QString());
    QString exportRenditionToPdf(const QVariantMap &state, const QString &fileBaseName = QString());
    QString exportReceivedSnapshot(const QVariantMap &received, const QString &format);

signals:
    void calicataPublished(const QString &documentId);
    void calicataSavedOnline(const QString &documentId);
    void calicataPublishFailed(const QString &documentId, const QString &message);
    void lastErrorChanged();
    void exportResultChanged();

private:
    void setLastError(const QString &error);
    QString safeFileName(QString name) const;
    QString makeOutputPath(const QString &fileBaseName) const;
    QString makeOutputPathWithExtension(const QString &fileBaseName,
                                        const QString &extension) const;
    QVariantMap readJsonObject(const QString &jsonPath);

    QString m_lastError;
    QVariantMap m_exportResult;
    QString m_exportProject;
    QString m_exportLogicalPath;
    RenditionExportService *m_exports = nullptr;
    QHash<QString, QString> m_publishedFiles;
    QString m_publishedUser;
};
