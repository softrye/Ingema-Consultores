#pragma once

#include <QMainWindow>
#include <QString>
#include <QToolButton>
#include <QMovie>
#include <QIcon>
#include <QPointer>
#include <QHash>
#include <QFileSystemWatcher>

QT_BEGIN_NAMESPACE
namespace Ui { class TaludesEditorWindow; }
QT_END_NAMESPACE

class QCloseEvent;
class QShowEvent;
class HomeWindow;
class TaludFormBase;

class TaludesEditorWindow : public QMainWindow
{
    Q_OBJECT

public:
    explicit TaludesEditorWindow(QWidget *parent = nullptr);
    ~TaludesEditorWindow() override;

    void setHome(HomeWindow *h) { m_home = h; }

public slots:
    void openFile(const QString &filePath);

protected:
    void closeEvent(QCloseEvent *event) override;
    void showEvent(QShowEvent *event) override;

private slots:
    void onNuevoTabSuelo();
    void onNuevoTabRoca();
    void onAbrir();
    void onGuardar();
    void onGuardarComo();
    void onTabCloseRequested(int index);
    void onCurrentTabChanged(int);
    void onAutoSaveToggled(bool enabled);
    void onVolver();
    void onExportExcel();
    void onGpsToggled(bool on);
    void onWatchedFileChanged(const QString& path);

private:
    QString baseProjectsPath() const;

    void crearTabPorDefecto();

    void addNewSueloTab();
    void addNewRocaTab();
    void addNewTab(TaludFormBase *w, const QString &title);

    TaludFormBase* currentTalud() const;
    bool isFileAlreadyOpen(const QString &filePath, int *outIndex = nullptr) const;

    void hookTaludSignals(TaludFormBase *w);
    void updateTabTitleFor(TaludFormBase *w);
    void updateActionsForCurrent();
    bool anyDirtyTabs() const;
    void updateEditorTitle();

    void ensureGpsLink();
    void setGpsButtonVisual(bool on);

    void ensureWatcher();
    void watchTaludFile(TaludFormBase* w, const QString& absReal);
    void unwatchTaludFile(TaludFormBase* w);
    void refreshLastMTime(TaludFormBase* w);

    TaludFormBase* createTaludFromFileType(const QString& filePath) const;
    QString detectFormTypeFromJson(const QString& filePath) const;

private:
    Ui::TaludesEditorWindow *ui = nullptr;

    QString m_baseTitle;
    int m_docCounterSuelo = 1;
    int m_docCounterRoca  = 1;

    // botones corner
    QToolButton *m_btnGps = nullptr;
    QToolButton *m_btnGuardar = nullptr;
    QToolButton *m_btnGuardarComo = nullptr;
    QToolButton *m_btnExport = nullptr;
    QToolButton *m_btnAutoSave = nullptr;

    // GPS
    QMovie *m_gpsBtnMovie = nullptr;
    QIcon  m_gpsBtnInactiveIcon;
    bool   m_gpsOn = false;
    bool   m_gpsLinked = false;

    // watcher
    QFileSystemWatcher* m_fsWatcher = nullptr;
    QHash<QString, QPointer<TaludFormBase>> m_tabByKey;

    QPointer<HomeWindow> m_home;
};
