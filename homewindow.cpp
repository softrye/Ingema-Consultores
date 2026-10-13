#include "homewindow.h"
#include "ui_homewindow.h"
#include "globalsearch.h"
#include "appcontext.h"
#include "authsession.h"
#include "pathscope.h"
#include "calicataseditorwindow.h"
#include "taludeseditorwindow.h"
#include "ubicacionwindow.h"
#include "perfilwindow.h"

#include "gpsmanager.h"

#include <QTimer>
#include <QApplication>
#include <QCompleter>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QFrame>
#include <QPushButton>
#include <QPropertyAnimation>
#include <QEasingCurve>
#include <QHideEvent>
#include <QAbstractButton>
#include <QLineEdit>
#include <QCompleter>
#include <QSettings>
#include <QStandardPaths>
#include <QFileDialog>
#include <QDesktopServices>
#include <QUrl>
#include <QMessageBox>
#include <QDateTime>
#include <QFile>
#include <QTextStream>
#include <QSysInfo>
#include <QCoreApplication>
#include <QDir>
#include <QGraphicsOpacityEffect>
#include <QParallelAnimationGroup>
#include <QSignalBlocker>
#include <QCloseEvent>
#include <QKeyEvent>
#include <QApplication>
#include <QMetaObject>

static constexpr bool kTaludesModuleEnabled = true;

static void showTaludesLockedMessage(QWidget *parent)
{
    QMessageBox::information(
        parent,
        QObject::tr("Módulo en construcción"),
        QObject::tr("La ficha de talud todavía se encuentra en implementación.\n\n"
                    "Por seguridad, este módulo permanecerá bloqueado hasta que esté completamente afinado.")
        );
}

HomeWindow::HomeWindow(AppContext* ctx, QWidget *parent)
    : QMainWindow(parent)
    , ui(new Ui::HomeWindow)
    , m_ctx(ctx)


{
    ui->setupUi(this);

    qApp->installEventFilter(this);

    GlobalSearch::instance()->attach(ui->lineSearch);

    setWindowIcon(QApplication::windowIcon());


    if (m_ctx && m_ctx->auth()) {
        auto* auth = m_ctx->auth();

        connect(auth, &AuthSession::userInfoChanged,
                this, &HomeWindow::refreshFromAuth);

        connect(auth, &AuthSession::loggedOut,
                this, &HomeWindow::onLoggedOut);

        // (opcional) cuando loguea, refrescas UI
        connect(auth, &AuthSession::loginOk,
                this, &HomeWindow::refreshFromAuth);
    }

    refreshFromAuth();

    // Conectar una sola vez
    if (m_ctx && m_ctx->auth()) {
        connect(m_ctx->auth(), &AuthSession::userInfoChanged,
                this, &HomeWindow::updateGreeting);

        connect(m_ctx->auth(), &AuthSession::loggedOut,
                this, &HomeWindow::updateGreeting);
    }

    // Pintar estado inicial
    updateGreeting();



    // ------------------- Global Search (barra superior) -------------------
    auto* gs = GlobalSearch::instance();

    // Helper: mostrar SOLO una ventana y ocultar las otras
    auto showOnly = [this](QMainWindow* target) {
        if (target == this) {
            if (navigateHost("showHomePage"))
                return;
        }

        if (target == ubicacionWindow) {
            if (navigateHost("showLocationPage"))
                return;
        }

        if (target == perfilWindow) {
            if (navigateHost("showProfilePage"))
                return;
        }

        if (target == calicatasEditorWindow) {
            if (navigateHost("showCalicataEditorPage"))
                return;
        }

        if (target == taludesEditorWindow) {
            if (navigateHost("showTaludEditorPage"))
                return;
        }

        // fallback antiguo
        if (target) {
            target->showMaximized();
            target->raise();
            target->activateWindow();
        }
    };

    // Root a indexar (scoped por usuario) + rebuild async
    auto refreshIndex = [this, gs](){
        const QString rootReal   = currentProjectsDir();
        const QString rootScoped = ensureUserScopedRoot(rootReal, false, false);
        gs->setRootToIndex(rootScoped);
        gs->rebuildIndexAsync();
    };

    // Index inicial
    refreshIndex();

    // Reindexar cuando logueas / deslogueas
    if (m_ctx && m_ctx->auth()) {
        auto* auth = m_ctx->auth();
        connect(auth, &AuthSession::loginOk,   this, refreshIndex);
        connect(auth, &AuthSession::loggedOut, this, refreshIndex);
    }

    // Acciones (atajos)
    connect(gs, &GlobalSearch::actionTriggered, this, [this, showOnly](const QString& id){
        if (id == "open_home") {
            showOnly(this);
        } else if (id == "open_docs") {
            showDocumentsModule();
        } else if (id == "open_ubi") {
            ensureUbicacionWindow();
            showOnly(ubicacionWindow);
        } else if (id == "open_perf") {
            ensurePerfilWindow();
            showOnly(perfilWindow);
        } else if (id == "open_calicatas") {
            ensureCalicatasEditorWindow();
            showOnly(calicatasEditorWindow);
        } else if (id == "open_taludes") {
            if (!kTaludesModuleEnabled) {
                showTaludesLockedMessage(this);
                return;
            }

            ensureTaludesEditorWindow();
            showOnly(taludesEditorWindow);
        }
    });

    // Conectar lineSearch en ventanas que YA existen
    auto hookLineSearch = [gs](QWidget* w){
        if (!w) return;
        if (auto* le = w->findChild<QLineEdit*>("lineSearch")) {
            gs->attach(le);
        }
    };

    hookLineSearch(this);

    const QIcon appIcon(":/icons/app.ico");
    this->setWindowIcon(appIcon);


    // Evitar clics "fantasma" al mostrarse
    this->setEnabled(false);

    QTimer::singleShot(200, this, [this]() {
        this->setEnabled(true);

        // Buscar botón menú por objectName (NO depende de ui->btnMenu)
        m_btnMenu = this->findChild<QAbstractButton*>("btnMenu");
        if (m_btnMenu) {
            m_btnMenu->installEventFilter(this);
        }

        // Tarjeta de calicata
        ui->cardCalicata->installEventFilter(this);
        ui->cardTalud->installEventFilter(this);

        if (!kTaludesModuleEnabled && ui->cardTalud) {
            ui->cardTalud->setToolTip(tr("Módulo en construcción"));
            ui->cardTalud->setStyleSheet(ui->cardTalud->styleSheet() +
                                         "QFrame { opacity: 0.65; }");
        }

        // Footer
        ui->btnMap->installEventFilter(this);
        ui->btnDocs->installEventFilter(this);
        ui->btnProfile->installEventFilter(this);

        // Panel opciones + overlay
        setupOptionsPanel();
    });
}

HomeWindow::~HomeWindow()
{
    qApp->removeEventFilter(this);
    delete ui;
}


void HomeWindow::setHostWindow(QMainWindow* host)
{
    m_hostWindow = host;
}

bool HomeWindow::navigateHost(const char* slotName)
{
    if (!m_hostWindow)
        return false;

    QMetaObject::invokeMethod(m_hostWindow, "showAppPage", Qt::DirectConnection);

    const bool okPage =
        QMetaObject::invokeMethod(m_hostWindow, slotName, Qt::DirectConnection);

    if (!okPage)
        return false;

    m_hostWindow->showMaximized();
    m_hostWindow->raise();
    m_hostWindow->activateWindow();

    return true;
}

bool HomeWindow::showDocumentsModule()
{
    return navigateHost("showDocumentsPage");
}

bool HomeWindow::openLoginInHost()
{
    if (!m_hostWindow)
        return false;

    const bool ok = QMetaObject::invokeMethod(m_hostWindow, "showLoginPage", Qt::DirectConnection);
    if (!ok)
        return false;

    m_hostWindow->showMaximized();
    m_hostWindow->raise();
    m_hostWindow->activateWindow();
    return true;
}

void HomeWindow::resizeEvent(QResizeEvent *event)
{
    QMainWindow::resizeEvent(event);
    repositionOptionsPanel();
}

void HomeWindow::hideEvent(QHideEvent *event)
{
    m_optionsOpen = false;

    if (m_optionsGroup) m_optionsGroup->stop();
    else if (m_optionsAnim) m_optionsAnim->stop();

    if (m_dimFx) m_dimFx->setOpacity(0.0);

    if (m_optionsPanel) {
        m_optionsPanel->hide();
        const int w = ui->centralwidget ? ui->centralwidget->width() : width();
        m_optionsPanel->move(w, 0);
    }
    if (m_dimOverlay) {
        m_dimOverlay->hide();
    }

    QMainWindow::hideEvent(event);
}

void HomeWindow::ensureTaludesEditorWindow()
{
    if (!kTaludesModuleEnabled) {
        showTaludesLockedMessage(this);
        return;
    }

    if (taludesEditorWindow)
        return;

    taludesEditorWindow = new TaludesEditorWindow(nullptr);
    taludesEditorWindow->setHome(this);
    taludesEditorWindow->setWindowIcon(this->windowIcon());

    if (auto *le = taludesEditorWindow->findChild<QLineEdit*>("lineSearch")) {
        GlobalSearch::instance()->attach(le);
    }
}

void HomeWindow::ensureCalicatasEditorWindow()
{
    if (calicatasEditorWindow) return;

    calicatasEditorWindow = new CalicatasEditorWindow(nullptr);
    calicatasEditorWindow->setHome(this);
    calicatasEditorWindow->setWindowIcon(this->windowIcon());

    if (auto *le = calicatasEditorWindow->findChild<QLineEdit*>("lineSearch"))
        GlobalSearch::instance()->attach(le);
}

void HomeWindow::ensureUbicacionWindow()
{
    if (ubicacionWindow) return;

    ubicacionWindow = new UbicacionWindow(nullptr);
    ubicacionWindow->setHome(this);
    ubicacionWindow->setWindowIcon(this->windowIcon());

    if (auto *le = ubicacionWindow->findChild<QLineEdit*>("lineSearch"))
        GlobalSearch::instance()->attach(le);
}

void HomeWindow::ensurePerfilWindow()
{
    if (perfilWindow) return;

    perfilWindow = new PerfilWindow(m_ctx, nullptr);
    perfilWindow->setHome(this);
    perfilWindow->setWindowIcon(this->windowIcon());

    if (auto *le = perfilWindow->findChild<QLineEdit*>("lineSearch"))
        GlobalSearch::instance()->attach(le);
}


// --------------------- Helpers Settings ---------------------
QString HomeWindow::defaultProjectsDir() const
{
    const QString home = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    return QDir(home).absoluteFilePath("InGePlusProyectos");
}

QString HomeWindow::currentProjectsDir() const
{
    QSettings s;
    const QString def = defaultProjectsDir();
    const QString p = s.value("projects/rootDirAbs", def).toString();
    return QDir(p).absolutePath();
}

void HomeWindow::setCurrentProjectsDir(const QString &absDir)
{
    const QString clean = QDir(absDir).absolutePath();
    QDir().mkpath(clean);

    QSettings s;
    s.setValue("projects/rootDirAbs", clean);

    const QString rootScoped = ensureUserScopedRoot(currentProjectsDir(), false, true);
    auto* gs = GlobalSearch::instance();
    gs->setRootToIndex(rootScoped);
    gs->rebuildIndexAsync();


    refreshProjectsDirUi();
}

void HomeWindow::refreshProjectsDirUi()
{
    if (!m_lblProjectsDir) return;
    const QString p = currentProjectsDir();
    m_lblProjectsDir->setText(QDir::toNativeSeparators(p));
}

bool HomeWindow::gpsAutoShareEnabled() const
{
    QSettings s;
    return s.value("gps/autoShare", false).toBool();
}

void HomeWindow::applyGpsAutoShare(bool enabled)
{
    QSettings s;
    s.setValue("gps/autoShare", enabled);

    if (enabled) GpsManager::instance()->start();
    else         GpsManager::instance()->stop();
}


// --------------------- Panel Opciones + Overlay ---------------------
void HomeWindow::setupOptionsPanel()
{
    if (m_optionsPanel)
        return;

    // ============================================================
    // Overlay oscuro con fade
    // ============================================================
    m_dimOverlay = new QWidget(ui->centralwidget);
    m_dimOverlay->setObjectName("DimOverlay");
    m_dimOverlay->setAttribute(Qt::WA_StyledBackground, true);
    m_dimOverlay->setStyleSheet("#DimOverlay { background: rgba(0,0,0,70); }");
    m_dimOverlay->hide();
    m_dimOverlay->installEventFilter(this);

    m_dimFx = new QGraphicsOpacityEffect(m_dimOverlay);
    m_dimOverlay->setGraphicsEffect(m_dimFx);
    m_dimFx->setOpacity(0.0);

    m_dimAnim = new QPropertyAnimation(m_dimFx, "opacity", this);
    m_dimAnim->setDuration(220);
    m_dimAnim->setEasingCurve(QEasingCurve::OutCubic);

    // ============================================================
    // Panel
    // ============================================================
    m_optionsPanel = new QWidget(ui->centralwidget);
    m_optionsPanel->setObjectName("OptionsPanel");
    m_optionsPanel->setFixedWidth(m_optionsWidth);
    m_optionsPanel->setStyleSheet(
        "#OptionsPanel { background:#FFFFFF; border-left:1px solid #D0D4E4; }"
        "#OptionsPanel QLabel#title { font-size:12pt; font-weight:700; color:#1B2A4E; }"
        "#OptionsPanel QLabel.section { font-size:9pt; font-weight:700; color:#7A8CA4; }"
        "#OptionsPanel QLabel.muted { font-size:8.5pt; color:#7A8CA4; }"
        "#OptionsPanel QPushButton {"
        "  text-align:left;"
        "  padding:8px 10px;"
        "  border:none;"
        "  color:#1B2A4E;"
        "  background:transparent;"
        "}"
        "#OptionsPanel QPushButton:hover { background:#E3F2FD; }"
        "#OptionsPanel QPushButton#btnClosePanel {"
        "  text-align:center;"
        "  padding:10px;"
        "  border:1px solid #D0D4E4;"
        "  border-radius:8px;"
        "  background:#F5F7FB;"
        "  color:#1B2A4E;"
        "}"
        "#OptionsPanel QPushButton#btnClosePanel:hover { background:#E3F2FD; }"
        "#OptionsPanel QPushButton#btnOpenSession {"
        "  text-align:left;"
        "  padding:8px 10px;"
        "  border:1px solid rgba(13,110,253,0.35);"
        "  border-radius:8px;"
        "  color:#0B3D91;"
        "  background:#F3F8FF;"
        "  font-weight:600;"
        "}"
        "#OptionsPanel QPushButton#btnOpenSession:hover { background:#E7F2FF; }"
        "#OptionsPanel QPushButton#btnOpenSession:disabled {"
        "  color:#B0B0B0;"
        "  border-color:#E5E5E5;"
        "  background:#F7F7F7;"
        "}"
        "#OptionsPanel QPushButton#btnLogout {"
        "  text-align:left;"
        "  padding:8px 10px;"
        "  border:1px solid #F3B2B2;"
        "  border-radius:8px;"
        "  color:#B00020;"
        "  background:#FFF5F5;"
        "}"
        "#OptionsPanel QPushButton#btnLogout:hover { background:#FFECEC; }"
        "#OptionsPanel QPushButton#btnLogout:disabled {"
        "  color:#B0B0B0;"
        "  border-color:#E5E5E5;"
        "  background:#F7F7F7;"
        "}"
        );

    auto *lay = new QVBoxLayout(m_optionsPanel);
    lay->setContentsMargins(14, 14, 14, 14);
    lay->setSpacing(8);

    auto mkLine = [this]() {
        auto *l = new QFrame(m_optionsPanel);
        l->setFrameShape(QFrame::HLine);
        l->setStyleSheet("color:#D0D4E4;");
        return l;
    };

    auto mkSection = [this](const QString &text) {
        auto *lbl = new QLabel(text, m_optionsPanel);
        lbl->setProperty("class", "section");
        lbl->setStyleSheet("font-size:9pt; font-weight:700; color:#7A8CA4;");
        return lbl;
    };

    auto *title = new QLabel(tr("Opciones"), m_optionsPanel);
    title->setObjectName("title");
    lay->addWidget(title);
    lay->addWidget(mkLine());

    // ============================================================
    // GPS
    // ============================================================
    lay->addWidget(mkSection(tr("GPS")));

    {
        auto *row = new QWidget(m_optionsPanel);
        auto *hl = new QHBoxLayout(row);
        hl->setContentsMargins(0, 0, 0, 0);
        hl->setSpacing(10);

        auto *lbl = new QLabel(tr("Compartir ubicación automática (GPS)"), row);
        lbl->setStyleSheet("color:#1B2A4E;");
        hl->addWidget(lbl);
        hl->addStretch();

        auto *btn = new QPushButton(row);
        btn->setCheckable(true);
        btn->setFixedSize(46, 22);
        btn->setText("");
        btn->setCursor(Qt::PointingHandCursor);
        btn->setStyleSheet(
            "QPushButton { border-radius:11px; background:#C7CFDA; }"
            "QPushButton:checked { background:#4CAF50; }"
            );

        m_swGps = btn;
        m_swGps->setChecked(GpsManager::instance()->isActive());

        hl->addWidget(m_swGps);
        lay->addWidget(row);

        connect(m_swGps, &QAbstractButton::toggled, this, [this](bool checked) {
            if (ubicacionWindow) {
                ubicacionWindow->setGpsAutoShare(checked);
            } else {
                applyGpsAutoShare(checked);
            }
        });

        if (ubicacionWindow) {
            connect(ubicacionWindow, &UbicacionWindow::gpsAutoShareChanged,
                    this, [this](bool on) {
                        if (!m_swGps) return;
                        QSignalBlocker b(m_swGps);
                        m_swGps->setChecked(on);
                    });
        }
    }

    lay->addWidget(mkLine());

    // ============================================================
    // Carpeta de proyectos
    // ============================================================
    lay->addWidget(mkSection(tr("Carpeta de proyectos")));

    auto *lblCur = new QLabel(tr("Carpeta actual de proyectos:"), m_optionsPanel);
    lblCur->setStyleSheet("font-size:8.5pt; color:#7A8CA4;");
    lay->addWidget(lblCur);

    m_lblProjectsDir = new QLabel(m_optionsPanel);
    m_lblProjectsDir->setWordWrap(true);
    m_lblProjectsDir->setTextInteractionFlags(Qt::TextSelectableByMouse);
    m_lblProjectsDir->setStyleSheet("font-size:8.5pt; color:#1B2A4E;");
    lay->addWidget(m_lblProjectsDir);
    refreshProjectsDirUi();

    auto *btnChangeFolder = new QPushButton(tr("Cambiar carpeta de proyectos..."), m_optionsPanel);
    auto *btnOpenFolder   = new QPushButton(tr("Abrir carpeta de proyectos"), m_optionsPanel);
    auto *btnResetFolder  = new QPushButton(tr("Restaurar ubicación por defecto"), m_optionsPanel);

    lay->addWidget(btnChangeFolder);
    lay->addWidget(btnOpenFolder);
    lay->addWidget(btnResetFolder);

    connect(btnChangeFolder, &QPushButton::clicked, this, [this]() {
        closeOptionsPanel();
        const QString cur = currentProjectsDir();
        const QString dir = QFileDialog::getExistingDirectory(
            this,
            tr("Selecciona carpeta de proyectos"),
            cur
            );
        if (dir.isEmpty()) return;
        setCurrentProjectsDir(dir);
    });

    connect(btnOpenFolder, &QPushButton::clicked, this, [this]() {
        closeOptionsPanel();
        QDesktopServices::openUrl(QUrl::fromLocalFile(currentProjectsDir()));
    });

    connect(btnResetFolder, &QPushButton::clicked, this, [this]() {
        closeOptionsPanel();
        setCurrentProjectsDir(defaultProjectsDir());
    });

    lay->addWidget(mkLine());

    // ============================================================
    // Cuenta / Soporte
    // ============================================================
    lay->addWidget(mkSection(tr("Cuenta / Soporte")));

    auto *lblSession = new QLabel(m_optionsPanel);
    lblSession->setWordWrap(true);
    lblSession->setStyleSheet("font-size:8.5pt; color:#7A8CA4;");

    bool logged = false;
    QString displayName = tr("Invitado");

    if (m_ctx && m_ctx->auth()) {
        logged = m_ctx->auth()->isLogged();
        const QString dn = m_ctx->auth()->displayName().trimmed();
        if (!dn.isEmpty()) displayName = dn;
    }

    lblSession->setText(logged
                            ? tr("Sesión iniciada: %1").arg(displayName)
                            : tr("Modo offline / sin sesión activa"));
    lay->addWidget(lblSession);

    auto *btnProfile = new QPushButton(tr("Perfil (ver/editar)"), m_optionsPanel);
    auto *btnAbout   = new QPushButton(tr("Acerca de / Versión de la app"), m_optionsPanel);
    auto *btnLog     = new QPushButton(tr("Exportar log..."), m_optionsPanel);

    lay->addWidget(btnProfile);
    lay->addWidget(btnAbout);
    lay->addWidget(btnLog);

    connect(btnProfile, &QPushButton::clicked, this, [this]() {
        closeOptionsPanel();

        if (navigateHost("showProfilePage"))
            return;

        ensurePerfilWindow();
        if (perfilWindow) {
            perfilWindow->showMaximized();
            this->hide();
        }
    });

    connect(btnAbout, &QPushButton::clicked, this, [this]() {
        closeOptionsPanel();
        QMessageBox::information(
            this,
            tr("Acerca de / Versión"),
            tr("InGe+ (AppCalicatasDemo)\n\n"
               "Versión: %1\n"
               "Qt: %2\n"
               "Sistema operativo: %3")
                .arg(QCoreApplication::applicationVersion().isEmpty()
                         ? tr("En desarrollo")
                         : QCoreApplication::applicationVersion())
                .arg(qVersion())
                .arg(QSysInfo::prettyProductName())
            );
    });

    connect(btnLog, &QPushButton::clicked, this, [this]() {
        closeOptionsPanel();

        const QString docs = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
        const QString stamp = QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss");
        const QString path = QDir(docs).absoluteFilePath(QString("InGePlus_log_%1.txt").arg(stamp));

        QFile f(path);
        if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
            QMessageBox::warning(this, tr("Error"), tr("No se pudo crear el archivo de log."));
            return;
        }

        QTextStream out(&f);
        out << "InGe+ Log\n";
        out << "Fecha: " << QDateTime::currentDateTime().toString(Qt::ISODate) << "\n";
        out << "Ventana: Home\n";
        out << "Qt: " << qVersion() << "\n";
        out << "SO: " << QSysInfo::prettyProductName() << "\n";
        out << "GPS activo: " << (GpsManager::instance()->isActive() ? "SI" : "NO") << "\n";
        out << "Carpeta proyectos: " << currentProjectsDir() << "\n";
        f.close();

        QMessageBox::information(this, tr("Log exportado"),
                                 tr("Se creó:\n%1").arg(QDir::toNativeSeparators(path)));
        QDesktopServices::openUrl(QUrl::fromLocalFile(docs));
    });

    // ============================================================
    // Parte inferior fija
    // ============================================================
    lay->addStretch();
    lay->addWidget(mkLine());

    m_btnOpenSession = new QPushButton(tr("Iniciar sesión"), m_optionsPanel);
    m_btnOpenSession->setObjectName("btnOpenSession");
    m_btnOpenSession->setCursor(Qt::PointingHandCursor);
    lay->addWidget(m_btnOpenSession);

    connect(m_btnOpenSession, &QPushButton::clicked,
            this, &HomeWindow::onOpenSessionClicked);

    m_btnLogout = new QPushButton(tr("Cerrar sesión (modo offline)"), m_optionsPanel);
    m_btnLogout->setObjectName("btnLogout");
    m_btnLogout->setCursor(Qt::PointingHandCursor);
    lay->addWidget(m_btnLogout);

    connect(m_btnLogout, &QPushButton::clicked, this, [this]() {
        requestLogout(this);
    });

    if (m_ctx && m_ctx->auth()) {
        const bool isLogged = m_ctx->auth()->isLogged();
        m_btnLogout->setEnabled(isLogged);
        m_btnOpenSession->setEnabled(!isLogged);
    }

    m_btnClosePanel = new QPushButton(tr("Cerrar"), m_optionsPanel);
    m_btnClosePanel->setObjectName("btnClosePanel");
    lay->addWidget(m_btnClosePanel);
    connect(m_btnClosePanel, &QPushButton::clicked,
            this, &HomeWindow::closeOptionsPanel);

    // ============================================================
    // Animación
    // ============================================================
    m_optionsAnim = new QPropertyAnimation(m_optionsPanel, "pos", this);
    m_optionsAnim->setDuration(220);
    m_optionsAnim->setEasingCurve(QEasingCurve::OutCubic);

    m_optionsGroup = new QParallelAnimationGroup(this);
    m_optionsGroup->addAnimation(m_optionsAnim);
    m_optionsGroup->addAnimation(m_dimAnim);

    connect(m_optionsGroup, &QParallelAnimationGroup::finished, this, [this]() {
        if (!m_optionsOpen) {
            if (m_optionsPanel) m_optionsPanel->hide();
            if (m_dimOverlay)  m_dimOverlay->hide();
        }
    });

    repositionOptionsPanel();
    m_optionsPanel->hide();
    m_dimOverlay->hide();
    if (m_dimFx) m_dimFx->setOpacity(0.0);
}

void HomeWindow::repositionOptionsPanel()
{
    const int h = ui->centralwidget ? ui->centralwidget->height() : height();
    const int w = ui->centralwidget ? ui->centralwidget->width()  : width();

    if (m_dimOverlay) {
        m_dimOverlay->setGeometry(0, 0, w, h);
    }

    if (m_optionsPanel) {
        m_optionsPanel->setFixedHeight(h);

        const int xHidden = w;
        const int xShown  = w - m_optionsPanel->width();
        m_optionsPanel->move(m_optionsOpen ? xShown : xHidden, 0);
    }
}

void HomeWindow::toggleOptionsPanel()
{
    if (m_optionsOpen) closeOptionsPanel();
    else openOptionsPanel();
}

void HomeWindow::openOptionsPanel()
{
    if (!m_optionsPanel || !m_optionsGroup) return;

    // sync UI sin disparar toggled
    if (m_swGps) {
        QSignalBlocker b(m_swGps);
        m_swGps->setChecked(GpsManager::instance()->isActive());
    }

    refreshProjectsDirUi();

    m_optionsOpen = true;
    repositionOptionsPanel();

    if (m_dimOverlay) {
        m_dimOverlay->show();
        m_dimOverlay->raise();
    }
    m_optionsPanel->show();
    m_optionsPanel->raise();

    const int w = ui->centralwidget ? ui->centralwidget->width() : width();
    const QPoint endPos(w - m_optionsPanel->width(), 0);

    m_optionsGroup->stop();

    m_optionsAnim->setStartValue(m_optionsPanel->pos());
    m_optionsAnim->setEndValue(endPos);

    m_dimAnim->setStartValue(m_dimFx ? m_dimFx->opacity() : 0.0);
    m_dimAnim->setEndValue(1.0);

    m_optionsGroup->start();
}

void HomeWindow::closeOptionsPanel()
{
    if (!m_optionsPanel || !m_optionsGroup) return;
    if (!m_optionsOpen) return;

    m_optionsOpen = false;

    const int w = ui->centralwidget ? ui->centralwidget->width() : width();
    const QPoint endPos(w, 0);

    m_optionsGroup->stop();

    m_optionsAnim->setStartValue(m_optionsPanel->pos());
    m_optionsAnim->setEndValue(endPos);

    m_dimAnim->setStartValue(m_dimFx ? m_dimFx->opacity() : 1.0);
    m_dimAnim->setEndValue(0.0);

    m_optionsGroup->start();
}


// --------------------- Event Filter ---------------------
bool HomeWindow::eventFilter(QObject *obj, QEvent *event)
{
    // ============================================================
    // ESC: abrir/cerrar panel de opciones
    // ============================================================
    if (event->type() == QEvent::KeyPress && this->isActiveWindow()) {
        auto *ke = static_cast<QKeyEvent*>(event);

        if (ke->key() == Qt::Key_Escape && ke->modifiers() == Qt::NoModifier) {

            // No interceptar ESC si hay un diálogo modal activo
            if (QApplication::activeModalWidget()) {
                return QMainWindow::eventFilter(obj, event);
            }

            toggleOptionsPanel();
            event->accept();
            return true;
        }
    }

    if (event->type() == QEvent::MouseButtonPress) {

        // Menú
        if (m_btnMenu && obj == m_btnMenu) {
            toggleOptionsPanel();
            return true;
        }

        // Click overlay => cerrar
        if (m_optionsOpen && m_dimOverlay && obj == m_dimOverlay) {
            closeOptionsPanel();
            return true;
        }

        // Navegación
        if (obj == ui->cardCalicata) {
            if (!navigateHost("showCalicataEditorPage"))
                QMessageBox::warning(this, "Navegación", "No se pudo abrir Calicatas dentro del MainWindow.");
            return true;
        }

        if (obj == ui->cardTalud) {
            if (!kTaludesModuleEnabled) {
                showTaludesLockedMessage(this);
                return true;
            }

            if (!navigateHost("showTaludEditorPage"))
                QMessageBox::warning(this, "Navegación", "No se pudo abrir Taludes dentro del MainWindow.");
            return true;
        }

        if (obj == ui->btnMap) {
            if (!navigateHost("showLocationPage"))
                QMessageBox::warning(this, "Navegación", "No se pudo abrir Ubicación dentro del MainWindow.");
            return true;
        }

        if (obj == ui->btnDocs) {
            if (!showDocumentsModule())
                QMessageBox::warning(this, "Navegación", "No se pudo abrir Documentos dentro del MainWindow.");
            return true;
        }

        if (obj == ui->btnProfile) {
            if (!navigateHost("showProfilePage"))
                QMessageBox::warning(this, "Navegación", "No se pudo abrir Perfil dentro del MainWindow.");
            return true;
        }
    }

    return QMainWindow::eventFilter(obj, event);
}

void HomeWindow::goTo(QMainWindow* w)
{
    Q_UNUSED(w);

    closeOptionsPanel();

    if (navigateHost("showHomePage"))
        return;

    QMessageBox::warning(
        this,
        "Navegación",
        "No se pudo volver a Home dentro del MainWindow."
        );
}

void HomeWindow::updateGreeting()
{
    if (!ui || !ui->lblGreeting) return; // ajusta lblGreeting si tu label tiene otro nombre

    QString name = "Invitado";
    if (m_ctx && m_ctx->auth()) {
        const QString dn = m_ctx->auth()->displayName().trimmed();
        if (!dn.isEmpty()) name = dn;
    }
    ui->lblGreeting->setText("Hola, " + name);
}


void HomeWindow::refreshFromAuth()
{
    if (!m_ctx || !m_ctx->auth()) return;
    auto* auth = m_ctx->auth();

    QString name = auth->displayName().trimmed();
    if (name.isEmpty()) name = "Invitado";

    if (ui->lblGreeting)
        ui->lblGreeting->setText("Hola, " + name);

    if (m_btnLogout)
        m_btnLogout->setEnabled(auth->isLogged());

    if (m_btnOpenSession)
        m_btnOpenSession->setEnabled(!auth->isLogged());
}



void HomeWindow::onLoggedOut()
{
    refreshFromAuth();

    if (ubicacionWin())   ubicacionWin()->hide();
    if (perfilWin())      perfilWin()->hide();
    if (taludesWin())     taludesWin()->hide();

    if (m_hostWindow) {
        QMetaObject::invokeMethod(m_hostWindow, "showAppPage", Qt::DirectConnection);
        QMetaObject::invokeMethod(m_hostWindow, "showHomePage", Qt::DirectConnection);

        m_hostWindow->showMaximized();
        m_hostWindow->raise();
        m_hostWindow->activateWindow();
        return;
    }

    this->showMaximized();
}

void HomeWindow::requestLogout(QWidget* dialogParent)
{
    if (!m_ctx || !m_ctx->auth()) return;

    auto* auth = m_ctx->auth();
    if (!auth->isLogged()) {
        // Ya estás offline, no repitas popup
        QMessageBox::information(dialogParent ? dialogParent : this,
                                 tr("Sesión"),
                                 tr("Ya estás en modo offline (sin sesión activa)."));
        return;
    }

    const auto r = QMessageBox::question(
        dialogParent ? dialogParent : this,
        tr("Cerrar sesión"),
        tr("¿Deseas cerrar sesión en este dispositivo?\n\n"
           "Podrás seguir usando la app en modo offline, pero no se sincronizará "
           "hasta volver a iniciar sesión."),
        QMessageBox::Yes | QMessageBox::No,
        QMessageBox::No
        );

    if (r != QMessageBox::Yes) return;

    // Cierra panel para que no quede overlay abierto
    closeOptionsPanel();

    // Cierre real: debe emitir loggedOut + userInfoChanged
    auth->signOut();
}


void HomeWindow::onOpenSessionClicked()
{
    if (!m_ctx || !m_ctx->auth())
        return;

    auto* auth = m_ctx->auth();

    if (auth->isLogged()) {
        QMessageBox::information(this, tr("Sesión"),
                                 tr("Ya hay una sesión activa. Cierra sesión primero."));
        return;
    }

    closeOptionsPanel();

    if (openLoginInHost())
        return;

    QWidget* mw = nullptr;
    for (QWidget* w : QApplication::topLevelWidgets()) {
        if (w && w->inherits("MainWindow")) {
            mw = w;
            break;
        }
    }

    if (!mw) {
        QMessageBox::warning(this, tr("Iniciar sesión"),
                             tr("No se encontró MainWindow.\n"
                                "Asegúrate de NO cerrarlo al loguear; usa hide()."));
        return;
    }

    QMetaObject::invokeMethod(mw, "showLoginPage", Qt::QueuedConnection);

    mw->showMaximized();
    mw->raise();
    mw->activateWindow();
    this->hide();
}

void HomeWindow::goToAny(QMainWindow* target)
{
    Q_UNUSED(target);

    closeOptionsPanel();

    if (navigateHost("showHomePage"))
        return;

    QMessageBox::warning(
        this,
        "Navegación",
        "No se pudo navegar dentro del MainWindow."
        );
}
