#ifndef EXPORTEXCELBATCHDIALOG_H
#define EXPORTEXCELBATCHDIALOG_H

#include <QDialog>
#include <QStringList>

class QTableWidget;
class QPushButton;
class QLineEdit;
class QRadioButton;
class QCheckBox;

class ExportExcelBatchDialog : public QDialog
{
    Q_OBJECT
public:
    explicit ExportExcelBatchDialog(const QString& projectsRoot, QWidget* parent=nullptr);

private slots:
    void addFiles();
    void removeSelected();
    void clearAll();

    // Usa selector interno (SelectFolderDialog)
    void browseOutDir();

    void doExport();

private:
    enum class DestMode {
        SameFolder,     // mismo folder del JSON
        ExcelSubfolder, // .../Calicatas/EXCEL (junto a Edit)
        OneFolder       // un solo folder para todos
    };

    DestMode currentDestMode() const;

    static QString calicatasRootDirForJson(const QString& jsonPath);
    QString normalizedBaseName(const QString& jsonPath) const;
    QString computeOutPath(const QString& jsonPath) const;

    void setRowStatus(int row, const QString& status);
    void syncOutPathsColumn();

    bool exportOneJsonToExcel(const QString& jsonPath, const QString& outXlsx, QString* err);

private:
    // Root seguro del proyecto (p.ej. ~/InGePlusProyectos)
    QString m_projectsRoot;

    // UI
    QTableWidget*  m_table = nullptr;

    QPushButton*   m_btnAdd = nullptr;
    QPushButton*   m_btnRemove = nullptr;
    QPushButton*   m_btnClear = nullptr;

    QRadioButton*  m_rbSameFolder = nullptr;
    QRadioButton*  m_rbExcelSubfolder = nullptr;
    QRadioButton*  m_rbOneFolder = nullptr;

    QLineEdit*     m_editOutDir = nullptr;
    QPushButton*   m_btnBrowse = nullptr;

    QLineEdit*     m_editPrefix = nullptr;
    QLineEdit*     m_editSuffix = nullptr;

    QCheckBox*     m_chkOverwrite = nullptr;

    QPushButton*   m_btnExport = nullptr;
    QPushButton*   m_btnCancel = nullptr;
};

#endif // EXPORTEXCELBATCHDIALOG_H
