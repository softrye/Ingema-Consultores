#ifndef GUARDARCALICATADIALOG_H
#define GUARDARCALICATADIALOG_H

#include <QDialog>
#include <QString>
#include <QStringList>
#include <QSet>

class QTreeView;
class QFileSystemModel;
class QLineEdit;
class QLabel;
class QPushButton;
class QModelIndex;

class GuardarCalicataDialog : public QDialog
{
    Q_OBJECT
public:
    enum class Mode { Save, Open };

    explicit GuardarCalicataDialog(const QString &basePath,
                                   const QString &defaultFileName,
                                   QWidget *parent = nullptr);
    ~GuardarCalicataDialog() override;

    void setMode(Mode mode);
    Mode mode() const { return m_mode; }

    // Save
    QString selectedFolder() const;
    QString fileName() const;

    // Open (compat + multi)
    QString selectedFilePath() const;   // primer archivo seleccionado (compat)
    QStringList selectedFilePaths() const;
    QString selectedBaseName() const;

protected:
    void accept() override;
    void reject() override;

private slots:
    void onTreeClicked(const QModelIndex &index);
    void onTreeDoubleClicked(const QModelIndex &idx);

    void onExpanded(const QModelIndex &idx);
    void onCollapsed(const QModelIndex &idx);

private:
    void rebuildModel();
    void updateOkButtonState();
    void onAccept();

    // Persist/restore UI state
    QString settingsGroup() const;
    void scheduleRestoreUiState();
    void restoreUiState();
    void scheduleSaveUiState();
    void saveUiState() const;

    void expandPathChainAndRemember(const QString &absPath);

private:
    QString m_basePath;

    Mode m_mode = Mode::Save;

    QLabel *m_lblHelp = nullptr;

    QFileSystemModel *m_model = nullptr;
    QTreeView *m_tree = nullptr;

    QLineEdit *m_editFileName = nullptr;
    QPushButton *m_btnOk = nullptr;

    QString m_selectedPath;              // compat (primer archivo)
    mutable QSet<QString> m_expandedAbs; // carpetas expandidas

    bool m_restoring = false;
    bool m_restoreScheduled = false;
    bool m_saveScheduled = false;
};

#endif // GUARDARCALICATADIALOG_H
