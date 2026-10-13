#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <QMainWindow>
#include <QShowEvent>
#include <QLineEdit>
#include <QPointer>

QT_BEGIN_NAMESPACE
namespace Ui { class MainWindow; }
QT_END_NAMESPACE

class AppContext;
class AuthSession;

class HomeWindow;
class UbicacionWindow;
class PerfilWindow;
class CalicatasEditorWindow;
class TaludesEditorWindow;

class QLabel;

class MainWindow : public QMainWindow
{
    Q_OBJECT

public:
    explicit MainWindow(AppContext* ctx, QWidget *parent = nullptr);
    ~MainWindow() override;

public slots:
    void showLoginPage();
    void showRegisterPage();
    void showAppPage();

    void showHomePage();
    void showDocumentsPage();
    void showLocationPage();
    void showProfilePage();
    void showCalicataEditorPage();
    void showTaludEditorPage();

protected:
    void showEvent(QShowEvent *event) override;

private slots:
    void on_btnLogin_clicked();
    void on_btnRegistro_clicked();
    void volverALogin();
    void on_btnRegistrarme_clicked();
    void on_btnOffline_clicked();

private:
    void updateAuthChrome();

    void setLoginError(const QString& msg);
    void clearLoginError();

    void setRegisterError(const QString& msg, bool okStyle = false);
    void clearRegisterError();

    void setBusy(bool busy);

    void installPasswordToggles();
    void installPasswordToggle(QLineEdit* edit);
    QString passwordPolicyMessage(const QString& pass) const;
    void setRegisterHint();

    void loadRememberedLoginUi();
    void saveRememberedLoginUi(const QString& email);
    void clearRememberedLoginUi(bool clearEmail = false);

    // ===============================
    // Páginas embebidas
    // ===============================
    void setupEmbeddedPages();
    void embedWindowInHost(QMainWindow* child, QWidget* host, QLabel* placeholder = nullptr);

    void ensureHomeWindow();
    void ensureLocationWindow();
    void ensureProfileWindow();
    void ensureCalicataEditorWindow();
    void ensureTaludEditorWindow();

private:
    Ui::MainWindow *ui = nullptr;
    AppContext* m_ctx = nullptr;

    QString m_pendingSignupEmail;
    QString m_pendingLoginEmail;
    bool m_busy = false;

    QPointer<HomeWindow> m_homeWindow;
    QPointer<UbicacionWindow> m_ubicacionWindow;
    QPointer<PerfilWindow> m_perfilWindow;
    QPointer<CalicatasEditorWindow> m_calicatasEditorWindow;
    QPointer<TaludesEditorWindow> m_taludesEditorWindow;
};

#endif // MAINWINDOW_H
