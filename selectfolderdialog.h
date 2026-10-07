#pragma once
#include <QDialog>
#include <QString>

class QFileSystemModel;
class QTreeView;

class SelectFolderDialog : public QDialog
{
    Q_OBJECT
public:
    explicit SelectFolderDialog(const QString& rootDir,
                                const QString& initialDir = QString(),
                                QWidget* parent = nullptr);

    QString selectedDir() const { return m_selectedDir; }

private slots:
    void onOkClicked();
    void onNewFolderClicked();

private:
    QString currentSelectedDir() const;
    bool isUnderRoot(const QString& absPath) const;

    QFileSystemModel* m_model = nullptr;
    QTreeView*        m_tree  = nullptr;

    QString m_rootDir;
    QString m_selectedDir;
};
