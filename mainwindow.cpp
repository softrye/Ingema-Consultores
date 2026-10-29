#include "mainwindow.h"
#include "./ui_mainwindow.h"

#include "appcontext.h"
#include "authsession.h"

#include "homewindow.h"
#include "ubicacionwindow.h"
#include "perfilwindow.h"
#include "calicataseditorwindow.h"
#include "taludeseditorwindow.h"

#include <QAction>
#include <QApplication>
#include <QDateTime>
#include <QGraphicsOpacityEffect>
#include <QLineEdit>
#include <QPropertyAnimation>
#include <QRegularExpression>
#include <QSettings>
#include <QStringList>
#include <QTimer>
#include <QVBoxLayout>
#include <QLabel>

static void fadeInLabel(QLabel* lbl)
{
    if (!lbl) return;

    auto *effect = new QGraphicsOpacityEffect(lbl);
    lbl->setGraphicsEffect(effect);

    auto *anim = new QPropertyAnimation(effect, "opacity");
    anim->setDuration(450);
    anim->setStartValue(0.0);
    anim->setEndValue(1.0);
    anim->setEasingCurve(QEasingCurve::InOutQuad);
    anim->start(QAbstractAnimation::DeleteWhenStopped);
}

namespace {
static const char* kRememberEnabledKey = "auth/remember_enabled";
static const char* kRememberEmailKey   = "auth/remember_email";
static const char* kRememberUntilKey   = "auth/remember_until_utc";
}

MainWindow::MainWindow(AppContext *ctx, QWidget *parent)
    : QMainWindow(parent)
    , ui(new Ui::MainWindow)
    , m_ctx(ctx)
{
    ui->setupUi(this);

    if (ui->statusbar)
        ui->statusbar->hide();

    setupEmbeddedPages();

    ui->stackedWidget->setCurrentWidget(ui->Pagina_Login);

    if (ui->appStack)
        ui->appStack->setCurrentWidget(ui->pageHome);

    setWindowIcon(QApplication::windowIcon());

    // ... todo lo demás igual ...

    // ===============================
    // ENTER -> INICIAR SESIÓN
    // ===============================
    connect(ui->lineUsuario,  &QLineEdit::returnPressed,
            ui->btnLogin,     &QPushButton::click);

    connect(ui->linePassword, &QLineEdit::returnPressed,
            ui->btnLogin,     &QPushButton::click);

    // ===============================
    // Hints para password
    // ===============================
    const auto pwdHints = Qt::ImhNoAutoUppercase
                          | Qt::ImhNoPredictiveText
                          | Qt::ImhSensitiveData;

    ui->linePassword->setInputMethodHints(pwdHints);
    ui->linePassword_1->setInputMethodHints(pwdHints);
    ui->linePassword_2->setInputMethodHints(pwdHints);

    // Ojos de password
    installPasswordToggles();

    // Recordar cuenta
    loadRememberedLoginUi();

    // Página inicial
    showLoginPage();

    // ===============================
    // Navegación Auth
    // ===============================
    connect(ui->btnRegistro, &QPushButton::clicked,
            this, &MainWindow::on_btnRegistro_clicked);

    connect(ui->btnVolverRegistrar, &QPushButton::clicked,
            this, &MainWindow::volverALogin);

    // ===============================
    // Enter = registrar
    // ===============================
    connect(ui->lineNombre,     &QLineEdit::returnPressed, this, &MainWindow::on_btnRegistrarme_clicked);
    connect(ui->lineApellido,   &QLineEdit::returnPressed, this, &MainWindow::on_btnRegistrarme_clicked);
    connect(ui->lineCorreo,     &QLineEdit::returnPressed, this, &MainWindow::on_btnRegistrarme_clicked);
    connect(ui->linePassword_1, &QLineEdit::returnPressed, this, &MainWindow::on_btnRegistrarme_clicked);
    connect(ui->linePassword_2, &QLineEdit::returnPressed, this, &MainWindow::on_btnRegistrarme_clicked);
    connect(ui->linePhone,      &QLineEdit::returnPressed, this, &MainWindow::on_btnRegistrarme_clicked);

    // ===============================
    // Botones principales
    // ===============================
    connect(ui->btnLogin,        &QPushButton::clicked, this, &MainWindow::on_btnLogin_clicked);
    connect(ui->btnRegistrarme,  &QPushButton::clicked, this, &MainWindow::on_btnRegistrarme_clicked);
    connect(ui->btnOffline,      &QPushButton::clicked, this, &MainWindow::on_btnOffline_clicked);

    // Hint visual de password registro
    connect(ui->linePassword_1, &QLineEdit::textChanged, this, [this](const QString& t){
        const QString msg = passwordPolicyMessage(t);
        if (msg.isEmpty()) {
            ui->lblError_Regis->setText("Contraseña segura ✅");
            ui->lblError_Regis->setStyleSheet("color: #1b5e20; font-weight: 500;");
        } else {
            setRegisterHint();
        }
    });

    clearLoginError();
    clearRegisterError();
    updateAuthChrome();

    // ===============================
    // AuthSession
    // ===============================
    if (m_ctx && m_ctx->auth()) {

        connect(m_ctx->auth(), &AuthSession::loginOk, this, [this]() {
            if (ui->checkRecordarCuenta->isChecked())
                saveRememberedLoginUi(m_pendingLoginEmail);
            else
                clearRememberedLoginUi(false);

            clearLoginError();
            setBusy(false);

            showAppPage();
            showHomePage();
        });

        connect(m_ctx->auth(), &AuthSession::loginFail, this, [this](const QString& msg) {
            setBusy(false);
            setLoginError(msg.isEmpty() ? "No se pudo iniciar sesión." : msg);
        });

        connect(m_ctx->auth(), &AuthSession::signUpOk, this, [this]() {
            setBusy(false);

            const QString mail = m_pendingSignupEmail.isEmpty()
                                     ? QString("tu correo")
                                     : m_pendingSignupEmail;

            setRegisterError(
                QString("✅ Te enviamos un enlace de confirmación a %1.\n"
                        "Revisa tu bandeja (y spam) y luego inicia sesión.")
                    .arg(mail),
                true
                );

            QTimer::singleShot(1500, this, [this]() {
                showLoginPage();
                if (!m_pendingSignupEmail.isEmpty())
                    ui->lineUsuario->setText(m_pendingSignupEmail);
            });
        });

        connect(m_ctx->auth(), &AuthSession::signUpFail, this, [this](const QString& msg) {
            setBusy(false);

            const QString m = msg.toLower();

            const bool looksLikeRateLimit =
                m.contains("rate limit") ||
                m.contains("too many requests") ||
                m.contains("over_email_send_rate_limit") ||
                m.contains("límite temporal");

            if (looksLikeRateLimit) {
                setRegisterError(
                    "Se alcanzó el límite temporal de envío de correos. "
                    "Espera un momento o revisa la configuración SMTP.",
                    false
                    );
                return;
            }

            setRegisterError(msg.isEmpty() ? "No se pudo crear la cuenta." : msg, false);
        });

        ui->stackedWidget->setCurrentWidget(ui->Pagina_Login);
        showLoginPage();
    }
}

MainWindow::~MainWindow()
{
    delete ui;
}

void MainWindow::showEvent(QShowEvent *event)
{
    QMainWindow::showEvent(event);

    static bool firstShow = true;
    if (firstShow) {
        firstShow = false;
        QTimer::singleShot(50, this, [this]() {
            this->setWindowState(Qt::WindowMaximized);
        });
    }
}

void MainWindow::updateAuthChrome()
{
    const bool authPage =
        ui->stackedWidget->currentWidget() == ui->Pagina_Login ||
        ui->stackedWidget->currentWidget() == ui->Pagina_Registro;

    ui->lblMarca->setVisible(authPage);
}

void MainWindow::showLoginPage()
{
    setWindowTitle("Iniciar sesión");

    ui->stackedWidget->setCurrentWidget(ui->Pagina_Login);
    updateAuthChrome();

    clearLoginError();

    ui->btnLogin->setDefault(true);
    ui->btnLogin->setAutoDefault(true);

    ui->lineUsuario->setFocus();
}

void MainWindow::showRegisterPage()
{
    setWindowTitle("Crear cuenta");

    ui->stackedWidget->setCurrentWidget(ui->Pagina_Registro);
    updateAuthChrome();

    clearRegisterError();

    ui->btnRegistrarme->setDefault(true);
    ui->btnRegistrarme->setAutoDefault(true);

    ui->lineNombre->setFocus();
}

void MainWindow::showAppPage()
{
    setWindowTitle("InGe+");

    ui->stackedWidget->setCurrentWidget(ui->Pagina_App);
    updateAuthChrome();

    clearLoginError();
    clearRegisterError();
    setBusy(false);
}

void MainWindow::showHomePage()
{
    ensureHomeWindow();
    ui->appStack->setCurrentWidget(ui->pageHome);
}

void MainWindow::showDocumentsPage()
{
    ui->appStack->setCurrentWidget(ui->pageDocumentos);
}

void MainWindow::showLocationPage()
{
    ensureLocationWindow();
    ui->appStack->setCurrentWidget(ui->pageUbicacion);
}

void MainWindow::showProfilePage()
{
    ensureProfileWindow();
    ui->appStack->setCurrentWidget(ui->pagePerfil);
}

void MainWindow::showCalicataEditorPage()
{
    ensureCalicataEditorWindow();
    ui->appStack->setCurrentWidget(ui->pageCalicataEditor);
}

void MainWindow::showTaludEditorPage()
{
    ensureTaludEditorWindow();
    ui->appStack->setCurrentWidget(ui->pageTaludEditor);
}

void MainWindow::on_btnRegistro_clicked()
{
    showRegisterPage();
}

void MainWindow::volverALogin()
{
    showLoginPage();
}

void MainWindow::setBusy(bool busy)
{
    m_busy = busy;

    // Login
    ui->btnLogin->setEnabled(!busy);
    ui->btnRegistro->setEnabled(!busy);
    ui->lineUsuario->setEnabled(!busy);
    ui->linePassword->setEnabled(!busy);
    ui->checkRecordarCuenta->setEnabled(!busy);

    // Registro
    ui->btnRegistrarme->setEnabled(!busy);
    ui->btnVolverRegistrar->setEnabled(!busy);
    ui->lineNombre->setEnabled(!busy);
    ui->lineApellido->setEnabled(!busy);
    ui->lineCorreo->setEnabled(!busy);
    ui->linePassword_1->setEnabled(!busy);
    ui->linePassword_2->setEnabled(!busy);
    ui->linePhone->setEnabled(!busy);

    ui->btnLogin->setText(busy ? "Procesando..." : "Iniciar sesión");
    ui->btnRegistrarme->setText(busy ? "Procesando..." : "Registrarme");
}

void MainWindow::clearLoginError()
{
    ui->lblError->setText("");
    ui->lblError->setStyleSheet("color: transparent;");
    ui->linePassword->setStyleSheet("");
}

void MainWindow::setLoginError(const QString& msg)
{
    ui->lblError->setText(msg);
    ui->lblError->setStyleSheet("color: red; font-weight: 500;");
    fadeInLabel(ui->lblError);

    ui->linePassword->setStyleSheet(
        "QLineEdit { border: 2px solid #d93025; border-radius: 6px; background-color: #fffafa; }"
        );

    QTimer::singleShot(2000, this, [this]() {
        ui->linePassword->setStyleSheet("");
    });
}

void MainWindow::setRegisterHint()
{
    ui->lblError_Regis->setText("Requisitos: 8+ caracteres, 1 mayúscula, 1 minúscula y 1 número.");
    ui->lblError_Regis->setStyleSheet("color: #607d8b; font-weight: 400;");
}

void MainWindow::clearRegisterError()
{
    ui->linePassword_1->setStyleSheet("");
    ui->linePassword_2->setStyleSheet("");
    setRegisterHint();
}

void MainWindow::setRegisterError(const QString& msg, bool okStyle)
{
    ui->lblError_Regis->setText(msg);
    ui->lblError_Regis->setStyleSheet(
        okStyle
            ? "color: #1b5e20; font-weight: 500;"
            : "color: red; font-weight: 500;"
        );

    fadeInLabel(ui->lblError_Regis);
}

void MainWindow::on_btnLogin_clicked()
{
    if (!m_ctx || !m_ctx->auth()) {
        setLoginError("Error interno: AppContext/AuthSession no inicializado.");
        return;
    }

    const QString email = ui->lineUsuario->text().trimmed();
    const QString pass  = ui->linePassword->text();

    clearLoginError();

    if (email.isEmpty() || pass.isEmpty()) {
        setLoginError("Ingresa usuario/email y contraseña.");
        return;
    }

    m_pendingLoginEmail = email;

    if (m_busy)
        return;

    m_ctx->auth()->setRememberFor30Days(ui->checkRecordarCuenta->isChecked());

    setBusy(true);
    m_ctx->auth()->signInWithPassword(email, pass);
}

void MainWindow::on_btnRegistrarme_clicked()
{
    if (m_busy)
        return;

    if (!m_ctx || !m_ctx->auth()) {
        setRegisterError("Error interno: AppContext/AuthSession no inicializado.");
        return;
    }

    const QString nombre   = ui->lineNombre->text().trimmed();
    const QString apellido = ui->lineApellido->text().trimmed();
    const QString email    = ui->lineCorreo->text().trimmed().toLower();
    const QString pass1    = ui->linePassword_1->text();
    const QString pass2    = ui->linePassword_2->text();
    const QString phone    = ui->linePhone->text().trimmed();

    clearRegisterError();

    if (nombre.isEmpty() || apellido.isEmpty() || email.isEmpty() ||
        pass1.isEmpty() || pass2.isEmpty() || phone.isEmpty()) {
        setRegisterError("Completa todos los campos.");
        return;
    }

    if (pass1 != pass2) {
        ui->linePassword_1->setStyleSheet("QLineEdit{ border:2px solid #d93025; border-radius:6px; }");
        ui->linePassword_2->setStyleSheet("QLineEdit{ border:2px solid #d93025; border-radius:6px; }");
        setRegisterError("Las contraseñas no coinciden.");
        return;
    }

    const QString policyMsg = passwordPolicyMessage(pass1);
    if (!policyMsg.isEmpty()) {
        ui->linePassword_1->setStyleSheet("QLineEdit{ border:2px solid #d93025; border-radius:6px; }");
        setRegisterError(policyMsg);
        return;
    }

    m_pendingSignupEmail = email;

    ui->lblError_Regis->setText(QString("Enviando enlace de confirmación a %1...").arg(email));
    ui->lblError_Regis->setStyleSheet("color: #607d8b; font-weight: 500;");
    fadeInLabel(ui->lblError_Regis);

    setBusy(true);
    m_ctx->auth()->signUpWithEmail(email, pass1, nombre, apellido, phone);
}

void MainWindow::installPasswordToggles()
{
    installPasswordToggle(ui->linePassword);
    installPasswordToggle(ui->linePassword_1);
    installPasswordToggle(ui->linePassword_2);
}

void MainWindow::installPasswordToggle(QLineEdit* edit)
{
    if (!edit) return;

    const QIcon iconShow(":/icons/OJO_CLOSE.png");
    const QIcon iconHide(":/icons/OJO_OPEN.png");

    edit->setEchoMode(QLineEdit::Password);

    QAction* act = edit->addAction(iconShow, QLineEdit::TrailingPosition);
    act->setToolTip("Mostrar / ocultar contraseña");
    act->setCheckable(true);
    act->setChecked(false);

    connect(act, &QAction::toggled, this, [edit, act, iconShow, iconHide](bool show) {
        edit->setEchoMode(show ? QLineEdit::Normal : QLineEdit::Password);
        act->setIcon(show ? iconHide : iconShow);
    });
}

QString MainWindow::passwordPolicyMessage(const QString& pass) const
{
    QStringList faltantes;

    if (pass.size() < 8) faltantes << "mínimo 8 caracteres";
    if (!pass.contains(QRegularExpression("\\p{Lu}"))) faltantes << "1 mayúscula";
    if (!pass.contains(QRegularExpression("\\p{Ll}"))) faltantes << "1 minúscula";
    if (!pass.contains(QRegularExpression("\\d")))     faltantes << "1 número";

    if (faltantes.isEmpty())
        return QString();

    return "La contraseña debe incluir: " + faltantes.join(", ") + ".";
}

void MainWindow::on_btnOffline_clicked()
{
    if (m_busy)
        return;

    clearLoginError();
    clearRegisterError();
    setBusy(false);

    if (m_ctx && m_ctx->auth()) {
        auto* auth = m_ctx->auth();
        if (auth->isLogged())
            auth->signOut();
    }

    showAppPage();
    showHomePage();
}

void MainWindow::loadRememberedLoginUi()
{
    QSettings s;

    const bool enabled = s.value(kRememberEnabledKey, false).toBool();
    const QString email = s.value(kRememberEmailKey).toString().trimmed();
    const QDateTime until = s.value(kRememberUntilKey).toDateTime();

    const bool stillValid =
        enabled &&
        until.isValid() &&
        QDateTime::currentDateTimeUtc() <= until.toUTC();

    if (stillValid) {
        ui->checkRecordarCuenta->setChecked(true);
        ui->lineUsuario->setText(email);
        return;
    }

    s.remove(kRememberEnabledKey);
    s.remove(kRememberEmailKey);
    s.remove(kRememberUntilKey);

    ui->checkRecordarCuenta->setChecked(false);
}

void MainWindow::saveRememberedLoginUi(const QString& email)
{
    QSettings s;
    s.setValue(kRememberEnabledKey, true);
    s.setValue(kRememberEmailKey, email.trimmed());
    s.setValue(kRememberUntilKey, QDateTime::currentDateTimeUtc().addDays(30));
}

void MainWindow::clearRememberedLoginUi(bool clearEmail)
{
    QSettings s;
    s.remove(kRememberEnabledKey);
    s.remove(kRememberEmailKey);
    s.remove(kRememberUntilKey);

    ui->checkRecordarCuenta->setChecked(false);

    if (clearEmail)
        ui->lineUsuario->clear();
}


void MainWindow::embedWindowInHost(QMainWindow* child, QWidget* host, QLabel* placeholder)
{
    if (!child || !host)
        return;

    child->setParent(host);
    child->setWindowFlags(Qt::Widget);
    child->setContentsMargins(0, 0, 0, 0);
    child->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);

    if (!host->layout()) {
        auto* lay = new QVBoxLayout(host);
        lay->setContentsMargins(0, 0, 0, 0);
        lay->setSpacing(0);
    }

    host->layout()->addWidget(child);

    if (placeholder)
        placeholder->hide();

    child->show();
}

void MainWindow::setupEmbeddedPages()
{
    ensureHomeWindow();
    ensureLocationWindow();
    ensureProfileWindow();
    ensureCalicataEditorWindow();
    ensureTaludEditorWindow();
}

void MainWindow::ensureHomeWindow()
{
    if (m_homeWindow)
        return;

    m_homeWindow = new HomeWindow(m_ctx, this);

    // Obligatorio
    m_homeWindow->setHostWindow(this);

    embedWindowInHost(
        m_homeWindow,
        ui->frameHomeHost,
        ui->lblHomePlaceholder
        );
}

void MainWindow::ensureLocationWindow()
{
    if (m_ubicacionWindow)
        return;

    m_ubicacionWindow = new UbicacionWindow(this);

    if (m_homeWindow)
        m_ubicacionWindow->setHome(m_homeWindow);

    embedWindowInHost(
        m_ubicacionWindow,
        ui->frameUbicacionHost,
        ui->lblUbicacionPlaceholder
        );
}

void MainWindow::ensureProfileWindow()
{
    if (m_perfilWindow)
        return;

    m_perfilWindow = new PerfilWindow(m_ctx, this);

    if (m_homeWindow)
        m_perfilWindow->setHome(m_homeWindow);

    embedWindowInHost(
        m_perfilWindow,
        ui->framePerfilHost,
        ui->lblPerfilPlaceholder
        );
}

void MainWindow::ensureCalicataEditorWindow()
{
    if (m_calicatasEditorWindow)
        return;

    m_calicatasEditorWindow = new CalicatasEditorWindow(this);

    if (m_homeWindow)
        m_calicatasEditorWindow->setHome(m_homeWindow);

    embedWindowInHost(
        m_calicatasEditorWindow,
        ui->frameCalicataEditorHost,
        ui->lblCalicataEditorPlaceholder
        );
}

void MainWindow::ensureTaludEditorWindow()
{
    if (m_taludesEditorWindow)
        return;

    m_taludesEditorWindow = new TaludesEditorWindow(this);

    if (m_homeWindow)
        m_taludesEditorWindow->setHome(m_homeWindow);

    embedWindowInHost(
        m_taludesEditorWindow,
        ui->frameTaludEditorHost,
        ui->lblTaludEditorPlaceholder
        );
}
