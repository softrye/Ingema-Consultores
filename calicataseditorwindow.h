#ifndef CALICATASEDITORWINDOW_H
#define CALICATASEDITORWINDOW_H

#include <QMainWindow>
#include <QString>
#include <QToolButton>
#include <QMovie>
#include <QIcon>
#include <QPointer>
#include <QHash>
#include <QFileSystemWatcher>

QT_BEGIN_NAMESPACE
namespace Ui { class CalicatasEditorWindow; }
QT_END_NAMESPACE

class QCloseEvent;
class QShowEvent;
class QAction;
class QMenu;

class CalicataWindow;
class UbicacionWindow;
class HomeWindow;
class CalicataMapDialog;

class CalicatasEditorWindow : public QMainWindow
{
    Q_OBJECT

public:
    explicit CalicatasEditorWindow(QWidget *parent = nullptr);
    ~CalicatasEditorWindow() override;

    void setHome(HomeWindow *h) { m_home = h; }

public slots:
    void openFile(const QString &filePath);

protected:
    void closeEvent(QCloseEvent *event) override;
    void showEvent(QShowEvent *event) override;

private slots:
    void onNuevoTab();
    void onAbrir();
    void onGuardar();
    void onGuardarComo();
    void onTabCloseRequested(int index);
    void onCurrentTabChanged(int);
    void onAutoSaveToggled(bool enabled);
    void onVolver();
    void onExportExcel();
    void onExportExcelBatch();
    void onGpsToggled(bool on);

    void onShowInteractiveMap();

    void onExternalEditableTitleChanged(const QString& editableFolderAbs, const QString& newTitle);
    void onExternalEditableLogosChanged(const QString& editableFolderAbs,
                                        const QString& mtcRel,
                                        const QString& proyectoRel);

    void onWatchedFileChanged(const QString& path);

    void onUndoCurrent();
    void onRedoCurrent();

private:
    QFileSystemWatcher* m_fsWatcher = nullptr;
    QHash<QString, QPointer<CalicataWindow>> m_tabByKey;
    QString baseProjectsPath() const;

    void crearTabPorDefecto();
    void addNewTab();
    void addNewTab(const QString &title);

    CalicataWindow* currentCalicata() const;
    bool isFileAlreadyOpen(const QString &filePath, int *outIndex = nullptr) const;

    void hookCalicataSignals(CalicataWindow *w);
    void updateTabTitleFor(CalicataWindow *w);
    void updateActionsForCurrent();
    bool anyDirtyTabs() const;
    void updateEditorTitle();
    void ensureGpsLink();

    void syncGpsMenuState(bool on);
    void pushCurrentCalicataToMapDialog();
    void applyDialogUtmToCurrentCalicata(const QString& zona,
                                         const QString& x,
                                         const QString& y,
                                         const QString& alt);

    QToolButton *m_btnGps = nullptr;
    bool m_gpsLinked = false;
    QHash<QString, int> m_tabByAbs;
    QFileSystemWatcher  m_watcher;
    void ensureWatcher();
    void watchCalicataFile(CalicataWindow* cw, const QString& absReal);
    void unwatchCalicataFile(CalicataWindow* cw);
    void refreshLastMTime(CalicataWindow* cw);

    QToolButton *m_btnUndo = nullptr;
    QToolButton *m_btnRedo = nullptr;
    void updateUndoRedoForCurrent();

private:
    Ui::CalicatasEditorWindow *ui = nullptr;
    QString m_baseTitle;
    int m_docCounter = 1;

    QToolButton *m_btnGuardar = nullptr;
    QToolButton *m_btnGuardarComo = nullptr;
    QToolButton *m_btnExport = nullptr;
    QToolButton *m_btnAutoSave = nullptr;

    void setGpsButtonVisual(bool on);

    QMovie *m_gpsBtnMovie = nullptr;
    QIcon  m_gpsBtnInactiveIcon;
    bool   m_gpsOn = false;
    QPointer<HomeWindow> m_home;

    QMenu* m_gpsMenu = nullptr;
    QAction* m_actGpsToggle = nullptr;
    QAction* m_actShowMap = nullptr;
    QPointer<CalicataMapDialog> m_mapDialog;
};

#endif // CALICATASEDITORWINDOW_H
