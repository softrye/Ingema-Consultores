#ifndef HOMEWINDOW_H
#define HOMEWINDOW_H

#include "appcontext.h"
#include "authsession.h"

#include <QMainWindow>
#include <QResizeEvent>
#include <QEvent>
#include <QPointer>

QT_BEGIN_NAMESPACE
namespace Ui { class HomeWindow; }
QT_END_NAMESPACE

class AppContext;

class CalicatasEditorWindow;
class UbicacionWindow;
class PerfilWindow;
class TaludesEditorWindow;
class QWidget;
class QPushButton;
class QPropertyAnimation;
class QAbstractButton;
class QHideEvent;
class QLabel;
class QGraphicsOpacityEffect;
class QParallelAnimationGroup;
class QMainWindow;

class HomeWindow : public QMainWindow
{
    Q_OBJECT

public:
    explicit HomeWindow(AppContext* ctx, QWidget *parent = nullptr);
    ~HomeWindow() override;

    AppContext* ctx() const { return m_ctx; }

    PerfilWindow* perfilWin() const { return perfilWindow; }
    CalicatasEditorWindow* calicatasWin() const { return calicatasEditorWindow; }
    UbicacionWindow* ubicacionWin() const { return ubicacionWindow; }
    TaludesEditorWindow* taludesWin() const { return taludesEditorWindow; }

    void setHostWindow(QMainWindow* host);
    QMainWindow* hostWindow() const { return m_hostWindow.data(); }

    void requestLogout(QWidget* dialogParent = nullptr);
    void goToAny(QMainWindow* target);
    bool showDocumentsModule();

    void ensureTaludesEditorWindow();
    void ensureCalicatasEditorWindow();
    void ensureUbicacionWindow();
    void ensurePerfilWindow();

protected:
    void resizeEvent(QResizeEvent *event) override;
    void hideEvent(QHideEvent *event) override;
    bool eventFilter(QObject *obj, QEvent *event) override;

private:
    void setupOptionsPanel();
    void repositionOptionsPanel();

    void toggleOptionsPanel();
    void openOptionsPanel();
    void closeOptionsPanel();

    QString defaultProjectsDir() const;
    QString currentProjectsDir() const;
    void setCurrentProjectsDir(const QString &absDir);
    void refreshProjectsDirUi();

    void applyGpsAutoShare(bool enabled);
    bool gpsAutoShareEnabled() const;

    void goTo(QMainWindow* w);

    bool navigateHost(const char* slotName);
    bool openLoginInHost();

private:
    Ui::HomeWindow *ui = nullptr;
    AppContext* m_ctx = nullptr;

    QPointer<QMainWindow> m_hostWindow;

    TaludesEditorWindow *taludesEditorWindow = nullptr;
    CalicatasEditorWindow *calicatasEditorWindow = nullptr;
    UbicacionWindow  *ubicacionWindow  = nullptr;
    PerfilWindow     *perfilWindow     = nullptr;

    QAbstractButton *m_btnMenu = nullptr;

    QWidget *m_optionsPanel = nullptr;
    QPropertyAnimation *m_optionsAnim = nullptr;
    QPushButton *m_btnClosePanel = nullptr;

    QWidget *m_dimOverlay = nullptr;

    QLabel *m_lblProjectsDir = nullptr;
    QAbstractButton *m_swGps = nullptr;

    QGraphicsOpacityEffect *m_dimFx = nullptr;
    QPropertyAnimation *m_dimAnim = nullptr;
    QParallelAnimationGroup *m_optionsGroup = nullptr;

    bool m_optionsOpen = false;
    int  m_optionsWidth = 320;

    QPushButton* m_btnOpenSession = nullptr;
    QPushButton* m_btnLogout = nullptr;

private slots:
    void updateGreeting();
    void refreshFromAuth();
    void onLoggedOut();
    void onOpenSessionClicked();
};

#endif // HOMEWINDOW_H
