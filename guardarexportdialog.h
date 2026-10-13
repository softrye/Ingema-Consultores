#pragma once
#include <QDialog>
#include <QString>

class QFileSystemModel;
class QTreeView;
class QLineEdit;

class GuardarExportDialog : public QDialog
{
    Q_OBJECT
public:
    explicit GuardarExportDialog(const QString& rootDir,
                                 const QString& initialDir,
                                 const QString& defaultFileName,
                                 const QString& extension,
                                 QWidget* parent = nullptr);

    QString selectedFilePath() const { return m_selectedPath; }

private slots:
    void onOkClicked();

private:
    QString currentSelectedDir() const;

    QFileSystemModel* m_model = nullptr;
    QTreeView*        m_tree  = nullptr;
    QLineEdit*        m_file  = nullptr;

    QString m_rootDir;
    QString m_extension;     // ".xlsx"
    QString m_selectedPath;  // resultado final
};
