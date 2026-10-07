#include "perfilwindow.h"
#include "ui_perfilwindow.h"
#include "appcontext.h"
#include "authsession.h"
#include "globalsearch.h"
#include "homewindow.h"
#include "ubicacionwindow.h"
#include "toggleswitch.h"
#include "gpsmanager.h"

#include <QApplication>
#include <QTimer>
#include <QWidget>
#include <QLabel>
#include <QPushButton>
#include <QPropertyAnimation>
#include <QEasingCurve>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QFrame>
#include <QImage>
#include <QKeyEvent>
#include <QApplication>
#include <QSettings>
#include <QStandardPaths>
#include <QFileDialog>
#include <QDesktopServices>
#include <QUrl>
#include <QMessageBox>
#include <QAbstractButton>
#include <QMetaObject>
#include <QDateTime>
#include <QFile>
#include <QTextStream>
#include <QSysInfo>
#include <QSignalBlocker>
#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QMouseEvent>
#include <QLineEdit>
#include <QPixmap>
#include <QImageReader>
#include <QCloseEvent>
#include <QTimer>
// ✅ NUEVO
#include <QGraphicsOpacityEffect>
#include <QParallelAnimationGroup>

// -------------------- SETTINGS --------------------
static const char* kSettingsOrg = "INGEPLUS";
static const char* kSettingsApp = "AppCalicatasDemo";
static const char* kKeyProjectsRoot = "paths/projects_root";

// (solo para “vacío ignorando Recursos”)
static const char* kResourcesFolderName = "Recursos";

static const char* kKeyProfileName      = "profile/name";
static const char* kKeyProfileEmail     = "profile/email";
static const char* kKeyProfilePhone     = "profile/phone";
static const char* kKeyProfileAvatar    = "profile/avatarPath";
static const char* kDefaultAvatarRes = ":/images/default_avatar_men.png";
// o si quieres el otro:
// static const char* kDefaultAvatarRes = ":/images/default_avatar_women.png";
static HomeWindow* resolveHome(QWidget* self)
{
    if (!self) return nullptr;

    if (auto* h = qobject_cast<HomeWindow*>(self->parentWidget()))
        return h;

    if (auto* h = qobject_cast<HomeWindow*>(self->parent()))
        return h;

    // fallback: buscar un HomeWindow existente en ventanas top-level
    const auto tops = QApplication::topLevelWidgets();
    for (QWidget* w : tops) {
        if (auto* h = qobject_cast<HomeWindow*>(w))
            return h;
    }
    return nullptr;
}

static void splitNombreApellido(const QString& full, QString* nombre, QString* apellido)
{
    QStringList parts = full.simplified().split(' ', Qt::SkipEmptyParts);
    if (parts.isEmpty()) { *nombre = ""; *apellido = ""; return; }
    if (parts.size() == 1) { *nombre = parts[0]; *apellido = ""; return; }
    *apellido = parts.takeLast();
    *nombre = parts.join(' ');
}


void PerfilWindow::clearProfileUiForOffline(bool clearSettings)
{
    if (ui->txtName)  ui->txtName->clear();
    if (ui->txtEmail) ui->txtEmail->clear();
    if (ui->txtPhone) ui->txtPhone->clear();

    // Opcional: volver al avatar default solo visualmente
    setAvatarPath(QString()); // vacío => default

    // Opcional: si quieres BORRAR también lo guardado localmente:
    if (clearSettings) {
        QSettings s(kSettingsOrg, kSettingsApp);
        s.remove(kKeyProfileName);
        s.remove(kKeyProfileEmail);
        s.remove(kKeyProfilePhone);
        s.remove(kKeyProfileAvatar);
    }
}


PerfilWindow::PerfilWindow(QWidget* parent)
    : PerfilWindow(nullptr, parent)   // delega
{}


PerfilWindow::PerfilWindow(AppContext* ctx, QWidget* parent)
    : QMainWindow(parent)
    , ui(new Ui::PerfilWindow)
    , m_ctx(ctx)
{
    ui->setupUi(this);

    qApp->installEventFilter(this);

    GlobalSearch::instance()->attach(ui->lineSearch);

    setWindowIcon(QApplication::windowIcon());


    if (ui->btnOpenSesion) {
        ui->btnOpenSesion->setCursor(Qt::PointingHandCursor);
        connect(ui->btnOpenSesion, &QPushButton::clicked,
                this, &PerfilWindow::onOpenSessionClicked);
    }


    // --- Cerrar sesión (botón en la UI) ---
    if (ui->btnCloseSesion) {
        ui->btnCloseSesion->setCursor(Qt::PointingHandCursor);

        // Estilo "danger" suave (no rompe tu paleta azul)
        ui->btnCloseSesion->setStyleSheet(R"(
            QPushButton#btnCloseSesion {
                background: #FFFFFF;
                color: #C62828;
                border: 1px solid rgba(198,40,40,0.35);
                border-radius: 10px;
                padding: 10px 14px;
                font-weight: 600;
            }
            QPushButton#btnCloseSesion:hover {
                background: rgba(198,40,40,0.08);
            }
            QPushButton#btnCloseSesion:pressed {
                background: rgba(198,40,40,0.14);
            }
            QPushButton#btnCloseSesion:disabled {
                color: rgba(198,40,40,0.35);
                border-color: rgba(198,40,40,0.18);
                background: #F7F8FA;
            }
        )");

        connect(ui->btnCloseSesion, &QPushButton::clicked,
                this, &PerfilWindow::onLogoutClicked);
    }


    if (m_ctx && m_ctx->auth()) {
        connect(m_ctx->auth(), &AuthSession::profileUpdatedOk, this, [this](){
            QMessageBox::information(this, tr("Perfil"), tr("Perfil actualizado en la nube ✅"));
        });
        connect(m_ctx->auth(), &AuthSession::profileUpdatedFail, this, [this](const QString& msg){
            QMessageBox::warning(this, tr("Perfil"), tr("No se pudo actualizar en la nube:\n%1").arg(msg));
        });
    }


    this->setWindowState(Qt::WindowMaximized);

    if (m_ctx && m_ctx->auth()) {
        connect(m_ctx->auth(), &AuthSession::userInfoChanged,
                this, &PerfilWindow::refreshFromAuth);

        connect(m_ctx->auth(), &AuthSession::loggedOut,
                this, &PerfilWindow::refreshFromAuth);
    }

    loadProfileFromSettings();

    refreshFromAuth();

    this->setWindowState(Qt::WindowMaximized);


    // Base path desde settings.
    const QString saved = loadProjectsRootFromSettings();
    m_basePath = saved.isEmpty() ? defaultBasePath() : saved;
    QDir().mkpath(m_basePath);

    // Panel opciones (+ overlay con fade)
    setupOptionsPanel();
    refreshFromAuth();

    // Evitar clics “fantasma” al mostrarse + instalar filtros
    this->setEnabled(false);
    QTimer::singleShot(200, this, [this]() {
        this->setEnabled(true);

        // Botón menú
        if (ui->btnMenu) {
            ui->btnMenu->installEventFilter(this);
        }

        // Footer navegación
        if (ui->btnHome)    ui->btnHome->installEventFilter(this);
        if (ui->btnMap)     ui->btnMap->installEventFilter(this);
        if (ui->btnDocs)    ui->btnDocs->installEventFilter(this);
        if (ui->btnProfile) ui->btnProfile->installEventFilter(this);

        // ---- PERFIL: cargar y conectar UI ----
        loadProfileFromSettings();

        // Ajusta estos objectName en tu .ui (o cámbialos aquí):
        // QLineEdit: txtName, txtEmail, txtPhone
        // QLabel:    lblAvatar
        // QPushButton: btnSaveProfile, btnChangeAvatar

        if (auto *btnSave = this->findChild<QAbstractButton*>("btnSaveProfile")) {
            connect(btnSave, &QAbstractButton::clicked, this, [this](){
                saveProfileToSettings();

                if (m_ctx && m_ctx->auth()) {

                    const QString full = ui->txtName->text().trimmed();
                    QString nombre, apellido;
                    splitNombreApellido(full, &nombre, &apellido);

                    const QString phone = ui->txtPhone->text().trimmed();

                    m_ctx->auth()->updateUserProfile(nombre, apellido, phone);
                }

                // ✅ IMPORTANTE: este mensaje mejor quítalo si ya usas profileUpdatedOk/Fail
                // QMessageBox::information(this, tr("Perfil"), tr("Datos guardados correctamente."));
            });
        }



        if (auto *btnAvatar = this->findChild<QAbstractButton*>("btnChangeAvatar")) {
            connect(btnAvatar, &QAbstractButton::clicked, this, [this](){
                chooseAvatar();
            });
        }

        if (auto *btnReset = this->findChild<QAbstractButton*>("btnResetAvatar")) {
            connect(btnReset, &QAbstractButton::clicked, this, [this](){
                resetAvatarToDefault();
                QMessageBox::information(this, tr("Avatar"), tr("Avatar restablecido al predeterminado."));
            });
        }
    });

}

PerfilWindow::~PerfilWindow()
{
    qApp->removeEventFilter(this);
    delete ui;
}

// ------------------------------------------------------------------
// Settings helpers
// ------------------------------------------------------------------
QString PerfilWindow::defaultBasePath() const
{
    const QString homePath = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    return QDir::cleanPath(homePath + "/InGePlusProyectos");
}

QString PerfilWindow::loadProjectsRootFromSettings() const
{
    QSettings s(kSettingsOrg, kSettingsApp);
    return s.value(kKeyProjectsRoot, "").toString().trimmed();
}

void PerfilWindow::saveProjectsRootToSettings(const QString &path) const
{
    QSettings s(kSettingsOrg, kSettingsApp);
    s.setValue(kKeyProjectsRoot, QDir::cleanPath(path));
}

void PerfilWindow::setupOptionsPanel()
{
    if (m_optionsPanel)
        return;

    QWidget *base = ui->centralwidget ? ui->centralwidget : this;

    // ============================================================
    // Overlay oscuro con fade
    // ============================================================
    m_dimOverlay = new QWidget(base);
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
    m_optionsPanel = new QWidget(base);
    m_optionsPanel->setObjectName("OptionsPanel");
    m_optionsPanel->setFixedWidth(m_optionsWidth);
    m_optionsPanel->setStyleSheet(
        "#OptionsPanel { background:#FFFFFF; border-left:1px solid #D0D4E4; }"
        "#OptionsPanel QLabel#title { font-size:12pt; font-weight:700; color:#1B2A4E; }"
        "#OptionsPanel QLabel.section { font-size:9pt; font-weight:700; color:#7A8CA4; }"
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
        "#OptionsPanel QPushButton#btnOpenSessionOpt {"
        "  text-align:left;"
        "  padding:8px 10px;"
        "  border:1px solid rgba(13,110,253,0.35);"
        "  border-radius:8px;"
        "  color:#0B3D91;"
        "  background:#F3F8FF;"
        "  font-weight:600;"
        "}"
        "#OptionsPanel QPushButton#btnOpenSessionOpt:hover { background:#E7F2FF; }"
        "#OptionsPanel QPushButton#btnOpenSessionOpt:disabled {"
        "  color:#B0B0B0;"
        "  border-color:#E5E5E5;"
        "  background:#F7F7F7;"
        "}"
        "#OptionsPanel QPushButton#btnLogoutOpt {"
        "  text-align:left;"
        "  padding:8px 10px;"
        "  border:1px solid #F3B2B2;"
        "  border-radius:8px;"
        "  color:#B00020;"
        "  background:#FFF5F5;"
        "}"
        "#OptionsPanel QPushButton#btnLogoutOpt:hover { background:#FFECEC; }"
        "#OptionsPanel QPushButton#btnLogoutOpt:disabled {"
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
        auto *row = new QHBoxLayout();
        row->setContentsMargins(0, 0, 0, 0);
        row->setSpacing(10);

        auto *gpsText = new QLabel(tr("Compartir ubicación automática (GPS)"), m_optionsPanel);
        gpsText->setStyleSheet("color:#1B2A4E;");
        row->addWidget(gpsText);
        row->addStretch();

        m_swShareGps = new ToggleSwitch(m_optionsPanel);
        {
            QSignalBlocker b(m_swShareGps);
            m_swShareGps->setChecked(GpsManager::instance()->isActive());
        }

        row->addWidget(m_swShareGps);
        lay->addLayout(row);

        connect(m_swShareGps, &ToggleSwitch::toggled, this, [](bool on) {
            if (on) GpsManager::instance()->start();
            else    GpsManager::instance()->stop();

            QSettings s;
            s.setValue("gps_enabled", on);
            s.setValue("gps/autoShare", on);
        });
    }

    lay->addWidget(mkLine());

    // ============================================================
    // Carpeta de proyectos
    // ============================================================
    lay->addWidget(mkSection(tr("Carpeta de proyectos")));

    auto *lblCur = new QLabel(tr("Carpeta actual de proyectos:"), m_optionsPanel);
    lblCur->setStyleSheet("font-size:8.5pt; color:#7A8CA4;");
    lay->addWidget(lblCur);

    m_lblBasePath = new QLabel("-", m_optionsPanel);
    m_lblBasePath->setWordWrap(true);
    m_lblBasePath->setTextInteractionFlags(Qt::TextSelectableByMouse);
    m_lblBasePath->setStyleSheet("font-size:8.5pt; color:#1B2A4E;");
    lay->addWidget(m_lblBasePath);

    m_btnChangeFolder = new QPushButton(tr("Cambiar carpeta de proyectos..."), m_optionsPanel);
    m_btnOpenFolder = new QPushButton(tr("Abrir carpeta de proyectos"), m_optionsPanel);
    m_btnDefaultFolder = new QPushButton(tr("Restaurar ubicación por defecto"), m_optionsPanel);

    lay->addWidget(m_btnChangeFolder);
    lay->addWidget(m_btnOpenFolder);
    lay->addWidget(m_btnDefaultFolder);

    connect(m_btnChangeFolder, &QPushButton::clicked,
            this, &PerfilWindow::actionChangeProjectsFolder);

    connect(m_btnOpenFolder, &QPushButton::clicked,
            this, &PerfilWindow::actionOpenProjectsFolder);

    connect(m_btnDefaultFolder, &QPushButton::clicked,
            this, &PerfilWindow::actionRestoreDefaultProjectsFolder);

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

    AuthSession *auth = nullptr;
    if (m_ctx && m_ctx->auth())
        auth = m_ctx->auth();
    else if (m_home && m_home->ctx() && m_home->ctx()->auth())
        auth = m_home->ctx()->auth();

    if (auth) {
        logged = auth->isLogged();
        const QString dn = auth->displayName().trimmed();
        if (!dn.isEmpty()) displayName = dn;
    }

    lblSession->setText(logged
                            ? tr("Sesión iniciada: %1").arg(displayName)
                            : tr("Modo offline / sin sesión activa"));
    lay->addWidget(lblSession);

    m_btnAbout = new QPushButton(tr("Acerca de / Versión de la app"), m_optionsPanel);
    m_btnExportLog = new QPushButton(tr("Exportar log..."), m_optionsPanel);

    lay->addWidget(m_btnAbout);
    lay->addWidget(m_btnExportLog);

    connect(m_btnAbout, &QPushButton::clicked, this, [this]() {
        closeOptionsPanel();
        QMessageBox::information(
            this,
            tr("Acerca de / Versión"),
            tr("InGe+ (AppCalicatasDemo)\n\n"
               "Ventana: Perfil\n"
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

    connect(m_btnExportLog, &QPushButton::clicked,
            this, &PerfilWindow::actionExportLog);

    // ============================================================
    // Parte inferior fija
    // ============================================================
    lay->addStretch();
    lay->addWidget(mkLine());

    m_btnOpenSessionOpt = new QPushButton(tr("Iniciar sesión"), m_optionsPanel);
    m_btnOpenSessionOpt->setObjectName("btnOpenSessionOpt");
    m_btnOpenSessionOpt->setCursor(Qt::PointingHandCursor);
    lay->addWidget(m_btnOpenSessionOpt);

    connect(m_btnOpenSessionOpt, &QPushButton::clicked,
            this, &PerfilWindow::onOpenSessionClicked);

    m_btnLogoutOpt = new QPushButton(tr("Cerrar sesión (modo offline)"), m_optionsPanel);
    m_btnLogoutOpt->setObjectName("btnLogoutOpt");
    m_btnLogoutOpt->setCursor(Qt::PointingHandCursor);
    lay->addWidget(m_btnLogoutOpt);

    connect(m_btnLogoutOpt, &QPushButton::clicked,
            this, &PerfilWindow::onLogoutFromOptions);

    if (m_btnOpenSessionOpt)
        m_btnOpenSessionOpt->setEnabled(!logged);
    if (m_btnLogoutOpt)
        m_btnLogoutOpt->setEnabled(logged);

    m_btnClosePanel = new QPushButton(tr("Cerrar"), m_optionsPanel);
    m_btnClosePanel->setObjectName("btnClosePanel");
    lay->addWidget(m_btnClosePanel);

    connect(m_btnClosePanel, &QPushButton::clicked,
            this, &PerfilWindow::closeOptionsPanel);

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

    updateOptionsPanelBasePath();
    repositionOptionsPanel();

    m_optionsPanel->hide();
    m_dimOverlay->hide();
    if (m_dimFx) m_dimFx->setOpacity(0.0);
}




void PerfilWindow::updateOptionsPanelBasePath()
{
    if (m_lblBasePath)
        m_lblBasePath->setText(QDir::toNativeSeparators(m_basePath));

    if (m_swShareGps) {
        QSignalBlocker b(m_swShareGps);
        m_swShareGps->setChecked(GpsManager::instance()->isActive());
    }
}

void PerfilWindow::repositionOptionsPanel()
{
    const int h = ui->centralwidget ? ui->centralwidget->height() : height();
    const int w = ui->centralwidget ? ui->centralwidget->width()  : width();

    // Overlay cubre todo
    if (m_dimOverlay) {
        m_dimOverlay->setGeometry(0, 0, w, h);
    }

    // Panel a la derecha
    if (!m_optionsPanel) return;

    m_optionsPanel->setFixedHeight(h);

    const int y = 0;
    const int xHidden = w;
    const int xShown  = w - m_optionsPanel->width();

    m_optionsPanel->move(m_optionsOpen ? xShown : xHidden, y);
}

void PerfilWindow::toggleOptionsPanel()
{
    if (m_optionsOpen) closeOptionsPanel();
    else openOptionsPanel();
}

void PerfilWindow::openOptionsPanel()
{
    if (!m_optionsPanel || !m_optionsGroup) return;

    updateOptionsPanelBasePath();

    m_optionsOpen = true;
    repositionOptionsPanel();

    // ✅ Mostrar overlay (bloquea el fondo) ANTES, con opacidad animada
    if (m_dimOverlay) {
        m_dimOverlay->show();
        m_dimOverlay->raise();
    }

    // Panel encima del overlay
    m_optionsPanel->show();
    m_optionsPanel->raise();

    const int w = ui->centralwidget ? ui->centralwidget->width() : width();
    const QPoint endPos(w - m_optionsPanel->width(), 0);

    m_optionsGroup->stop();

    // Slide: desde la pos actual a la visible
    m_optionsAnim->setStartValue(m_optionsPanel->pos());
    m_optionsAnim->setEndValue(endPos);

    // Fade: desde opacidad actual a 1
    m_dimAnim->setStartValue(m_dimFx ? m_dimFx->opacity() : 0.0);
    m_dimAnim->setEndValue(1.0);

    m_optionsGroup->start();
}

void PerfilWindow::closeOptionsPanel()
{
    if (!m_optionsPanel || !m_optionsGroup) return;
    if (!m_optionsOpen) return;

    m_optionsOpen = false;

    const int w = ui->centralwidget ? ui->centralwidget->width() : width();
    const QPoint endPos(w, 0);

    m_optionsGroup->stop();

    // Slide: hacia afuera
    m_optionsAnim->setStartValue(m_optionsPanel->pos());
    m_optionsAnim->setEndValue(endPos);

    // Fade: a transparente
    m_dimAnim->setStartValue(m_dimFx ? m_dimFx->opacity() : 1.0);
    m_dimAnim->setEndValue(0.0);

    // ✅ NO ocultar aquí, se oculta en finished()
    m_optionsGroup->start();
}

// ------------------------------------------------------------------
// Resize
// ------------------------------------------------------------------
void PerfilWindow::resizeEvent(QResizeEvent *event)
{
    QMainWindow::resizeEvent(event);
    repositionOptionsPanel();
    refreshAvatarPreview();
}

// ------------------------------------------------------------------
// Cambiar/abrir/restaurar carpeta de proyectos
// ------------------------------------------------------------------
bool PerfilWindow::directoryLooksEmpty(const QString &path, bool ignoreResourcesFolder) const
{
    QDir d(path);
    if (!d.exists()) return true;

    QFileInfoList entries = d.entryInfoList(QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot | QDir::Hidden);
    if (!ignoreResourcesFolder)
        return entries.isEmpty();

    for (const QFileInfo &fi : entries) {
        if (fi.isDir() && fi.fileName() == kResourcesFolderName)
            continue;
        return false;
    }
    return true;
}

bool PerfilWindow::copyDirRecursively(const QString &srcPath, const QString &dstPath)
{
    QDir srcDir(srcPath);
    if (!srcDir.exists())
        return false;

    QDir dstDir(dstPath);
    if (!dstDir.exists()) {
        if (!dstDir.mkpath("."))
            return false;
    }

    QFileInfoList files = srcDir.entryInfoList(QDir::Files | QDir::Hidden);
    for (const QFileInfo &fi : files) {
        const QString srcFile = fi.absoluteFilePath();
        const QString dstFile = dstDir.absoluteFilePath(fi.fileName());
        QFile::remove(dstFile);
        if (!QFile::copy(srcFile, dstFile))
            return false;
    }

    QFileInfoList dirs = srcDir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot | QDir::Hidden);
    for (const QFileInfo &di : dirs) {
        const QString srcSub = di.absoluteFilePath();
        const QString dstSub = dstDir.absoluteFilePath(di.fileName());
        if (!copyDirRecursively(srcSub, dstSub))
            return false;
    }

    return true;
}

bool PerfilWindow::setProjectsRoot(const QString &newBasePath, bool moveExistingData, QString *outError)
{
    const QString oldBase = QDir::cleanPath(m_basePath);
    QString newBase = QDir::cleanPath(newBasePath);

    if (newBase.isEmpty()) {
        if (outError) *outError = tr("Ruta inválida.");
        return false;
    }

    if (QDir::cleanPath(newBase) == QDir::cleanPath(oldBase))
        return true;

    // Evitar mover dentro de sí mismo
    if (moveExistingData) {
        const QString nb = QDir::cleanPath(newBase);
        const QString ob = QDir::cleanPath(oldBase);
        if (nb.startsWith(ob + QDir::separator())) {
            if (outError) *outError = tr("No puedes mover la carpeta dentro de sí misma.");
            return false;
        }
    }

    QDir().mkpath(newBase);

    if (moveExistingData) {
        if (!directoryLooksEmpty(newBase, true)) {
            if (outError) *outError = tr("La carpeta destino no está vacía.");
            return false;
        }

        if (!copyDirRecursively(oldBase, newBase)) {
            if (outError) *outError = tr("No se pudo copiar la carpeta actual al nuevo destino.");
            return false;
        }

        QDir(oldBase).removeRecursively();
    }

    m_basePath = newBase;
    saveProjectsRootToSettings(m_basePath);
    QDir().mkpath(m_basePath);

    updateOptionsPanelBasePath();
    return true;
}

void PerfilWindow::actionChangeProjectsFolder()
{
    const QString start = QFileInfo(m_basePath).dir().absolutePath();

    QString picked = QFileDialog::getExistingDirectory(
        this,
        tr("Selecciona una carpeta (se creará/usará 'InGePlusProyectos' dentro)"),
        start
        );
    if (picked.trimmed().isEmpty())
        return;

    picked = QDir::cleanPath(picked);

    QString newBase = picked;
    if (QFileInfo(picked).fileName().toLower() != QString("InGePlusProyectos").toLower()) {
        newBase = QDir(picked).absoluteFilePath("InGePlusProyectos");
    }

    if (QDir::cleanPath(newBase) == QDir::cleanPath(m_basePath))
        return;

    QMessageBox box(this);
    box.setWindowTitle(tr("Cambiar carpeta de proyectos"));
    box.setText(tr("¿Qué deseas hacer con los datos actuales?"));
    box.setInformativeText(tr("• Mover: copia todo al nuevo lugar y elimina la carpeta antigua.\n"
                              "• Solo cambiar: no mueve nada, solo apunta al nuevo lugar."));
    QPushButton *btnMove   = box.addButton(tr("Mover"), QMessageBox::AcceptRole);
    QPushButton *btnOnly   = box.addButton(tr("Solo cambiar"), QMessageBox::ActionRole);
    QPushButton *btnCancel = box.addButton(tr("Cancelar"), QMessageBox::RejectRole);
    box.setDefaultButton(btnMove);
    box.exec();

    if (box.clickedButton() == btnCancel)
        return;

    const bool moveData = (box.clickedButton() == btnMove);

    QString err;
    if (!setProjectsRoot(newBase, moveData, &err)) {
        QMessageBox::warning(this, tr("No se pudo cambiar"), err);
        return;
    }

    QMessageBox::information(this, tr("Listo"),
                             tr("Carpeta de proyectos actualizada."));
}

void PerfilWindow::actionOpenProjectsFolder()
{
    QDesktopServices::openUrl(QUrl::fromLocalFile(m_basePath));
}

void PerfilWindow::actionRestoreDefaultProjectsFolder()
{
    const QString def = defaultBasePath();
    if (QDir::cleanPath(def) == QDir::cleanPath(m_basePath))
        return;

    QMessageBox box(this);
    box.setWindowTitle(tr("Restaurar ubicación por defecto"));
    box.setText(tr("¿Deseas volver a la ubicación por defecto?"));
    box.setInformativeText(tr("También puedes mover los datos actuales al lugar por defecto."));
    QPushButton *btnMove   = box.addButton(tr("Mover"), QMessageBox::AcceptRole);
    QPushButton *btnOnly   = box.addButton(tr("Solo cambiar"), QMessageBox::ActionRole);
    QPushButton *btnCancel = box.addButton(tr("Cancelar"), QMessageBox::RejectRole);
    box.setDefaultButton(btnMove);
    box.exec();

    if (box.clickedButton() == btnCancel)
        return;

    const bool moveData = (box.clickedButton() == btnMove);

    QString err;
    if (!setProjectsRoot(def, moveData, &err)) {
        QMessageBox::warning(this, tr("No se pudo restaurar"), err);
        return;
    }
}

// ------------------------------------------------------------------
// About / Export log
// ------------------------------------------------------------------
void PerfilWindow::actionAbout()
{
    QMessageBox::information(
        this,
        tr("Acerca de"),
        tr("InGe+ (AppCalicatasDemo)\n"
           "Pantalla de perfil + configuración.\n\n"
           "Qt: %1\nSO: %2")
            .arg(qVersion(), QSysInfo::prettyProductName())
        );
}

void PerfilWindow::actionExportLog()
{
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
    out << "Qt: " << qVersion() << "\n";
    out << "SO: " << QSysInfo::prettyProductName() << "\n";
    out << "Ventana: Perfil\n";
    out << "Carpeta proyectos: " << m_basePath << "\n";
    out << "\n";
    f.close();

    QMessageBox::information(this, tr("Log exportado"),
                             tr("Se creó:\n%1").arg(QDir::toNativeSeparators(path)));

    QDesktopServices::openUrl(QUrl::fromLocalFile(docs));
}

void PerfilWindow::goTo(QMainWindow* w)
{
    if (!w) return;
    closeOptionsPanel();
    w->showMaximized();
    w->raise();
    w->activateWindow();
    this->hide();
}

// ------------------------------------------------------------------
// Event Filter: overlay + menú + footer navegación
// ------------------------------------------------------------------
bool PerfilWindow::eventFilter(QObject *obj, QEvent *event)
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

        if (obj == m_dimOverlay) {
            if (m_optionsOpen) closeOptionsPanel();
            return true;
        }

        if (ui->btnMenu && obj == ui->btnMenu) {
            toggleOptionsPanel();
            return true;
        }

        if (obj == ui->btnHome) {
            if (!m_home) return false;
            goTo(m_home);
            return true;
        }

        if (obj == ui->btnMap) {
            if (!m_home) return false;
            m_home->ensureUbicacionWindow();
            goTo(m_home->ubicacionWin());
            return true;
        }

        if (obj == ui->btnDocs) {
            if (!m_home) return false;
            m_home->showDocumentsModule();
            return true;
        }

        if (obj == ui->btnProfile) {
            return true; // ya estás aquí
        }
    }

    return QMainWindow::eventFilter(obj, event);
}

QString PerfilWindow::avatarStorageDir() const
{
    // Guardar avatar en un lugar estable (no depende de m_basePath)
    const QString base = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    const QString dir  = QDir(base).absoluteFilePath("profile");
    QDir().mkpath(dir);
    return dir;
}

QString PerfilWindow::importAvatarToStorage(const QString &srcPath) const
{
    if (srcPath.trimmed().isEmpty() || !QFileInfo::exists(srcPath))
        return QString();

    QImageReader reader(srcPath);
    reader.setAutoTransform(true);
    QImage img = reader.read();
    if (img.isNull())
        return QString();

    const QString dst = QDir(avatarStorageDir()).absoluteFilePath("avatar.png");
    QFile::remove(dst);

    if (!img.save(dst, "PNG"))
        return QString();

    return dst;
}

QString PerfilWindow::defaultAvatarResourcePath() const
{
    return QString::fromLatin1(kDefaultAvatarRes);
}



void PerfilWindow::setAvatarPath(const QString &path)
{
    m_profileAvatarPath = path.trimmed();

    // Ruta efectiva: si está vacío => default del QRC
    QString effective = m_profileAvatarPath;
    if (effective.isEmpty())
        effective = defaultAvatarResourcePath();

    QPixmap pm(effective); // funciona con ":/..." y con rutas normales

    // fallback al default sí o sí
    if (pm.isNull() && effective != defaultAvatarResourcePath())
        pm = QPixmap(defaultAvatarResourcePath());

    m_avatarOriginal = pm;          // ✅ cache para reescalar en resize
    refreshAvatarPreview();         // ✅ pinta y escala según el QLabel
}




void PerfilWindow::loadProfileFromSettings()
{
    QSettings s(kSettingsOrg, kSettingsApp);

    m_profileName       = s.value(kKeyProfileName,  "").toString().trimmed();
    m_profileEmail      = s.value(kKeyProfileEmail, "").toString().trimmed();
    m_profilePhone      = s.value(kKeyProfilePhone, "").toString().trimmed();
    m_profileAvatarPath = s.value(kKeyProfileAvatar,"").toString().trimmed(); // vacío => default

    // ✅ FALLBACK A AUTH si settings está vacío
    if (m_ctx && m_ctx->auth()) {
        auto* auth = m_ctx->auth();
        if (m_profileName.isEmpty())  m_profileName  = auth->displayName().trimmed();
        if (m_profileEmail.isEmpty()) m_profileEmail = auth->email().trimmed();
        if (m_profilePhone.isEmpty()) m_profilePhone = auth->phone().trimmed(); // <-- NUEVO
    }


    if (ui->txtName)  ui->txtName->setText(m_profileName);
    if (ui->txtEmail) ui->txtEmail->setText(m_profileEmail);
    if (ui->txtPhone) ui->txtPhone->setText(m_profilePhone);

    setAvatarPath(m_profileAvatarPath); // si vacío, muestra default
}



void PerfilWindow::saveProfileToSettings()
{
    if (auto *le = this->findChild<QLineEdit*>("txtName"))  m_profileName  = le->text().trimmed();
    if (auto *le = this->findChild<QLineEdit*>("txtEmail")) m_profileEmail = le->text().trimmed();
    if (auto *le = this->findChild<QLineEdit*>("txtPhone")) m_profilePhone = le->text().trimmed();

    QSettings s(kSettingsOrg, kSettingsApp);
    s.setValue(kKeyProfileName,  m_profileName);
    s.setValue(kKeyProfileEmail, m_profileEmail);
    s.setValue(kKeyProfilePhone, m_profilePhone);

    // Guardamos vacío cuando es default (más limpio)
    const QString toStore = m_profileAvatarPath.isEmpty() ? QString() : m_profileAvatarPath;
    s.setValue(kKeyProfileAvatar, toStore);
}



void PerfilWindow::chooseAvatar()
{
    const QString src = QFileDialog::getOpenFileName(
        this,
        tr("Seleccionar avatar"),
        QStandardPaths::writableLocation(QStandardPaths::PicturesLocation),
        tr("Imágenes (*.png *.jpg *.jpeg *.bmp)")
        );
    if (src.isEmpty()) return;

    const QString stored = importAvatarToStorage(src);
    if (stored.isEmpty()) {
        QMessageBox::warning(this, tr("Avatar"), tr("No se pudo guardar el avatar."));
        return;
    }

    setAvatarPath(stored);
    saveProfileToSettings();
}


QString PerfilWindow::defaultAvatarResource() const
{
    // Ajusta si quieres usar women como default:
    return QStringLiteral(":/images/default_avatar_men.png");
}

void PerfilWindow::refreshAvatarPreview()
{
    auto *lbl = this->findChild<QLabel*>("lblAvatar");
    if (!lbl) return;

    lbl->setAlignment(Qt::AlignCenter);
    lbl->setScaledContents(false);

    if (m_avatarOriginal.isNull()) {
        lbl->clear();
        return;
    }

    const QSize target = lbl->size();
    if (target.width() < 2 || target.height() < 2) return;

    lbl->setPixmap(m_avatarOriginal.scaled(target, Qt::KeepAspectRatio, Qt::SmoothTransformation));
}


void PerfilWindow::resetAvatarToDefault()
{
    // Si el avatar actual es un archivo (no QRC) y está en nuestro storage, lo borramos
    if (!m_profileAvatarPath.isEmpty() && !m_profileAvatarPath.startsWith(":/")) {
        QFileInfo fi(m_profileAvatarPath);
        if (fi.exists()) {
            const QString storage = QDir(avatarStorageDir()).absolutePath();
            if (QDir(fi.absolutePath()).absolutePath() == storage) {
                QFile::remove(fi.absoluteFilePath());
            }
        }
    }

    // Guardamos vacío => significa "usar default"
    m_profileAvatarPath.clear();
    setAvatarPath(QString());     // mostrará el default
    saveProfileToSettings();
}

void PerfilWindow::closeEvent(QCloseEvent *e)
{
    QMainWindow::closeEvent(e); // comportamiento normal
}


void PerfilWindow::refreshFromAuth()
{
    if (!m_ctx || !m_ctx->auth()) return;
    auto* auth = m_ctx->auth();

    const bool logged = auth->isLogged();

    // Botones sesión
    if (ui->btnCloseSesion) ui->btnCloseSesion->setEnabled(logged);
    if (ui->btnOpenSesion)  ui->btnOpenSesion->setEnabled(!logged);

    if (m_btnOpenSessionOpt) {
        m_btnOpenSessionOpt->setVisible(!logged);
        m_btnOpenSessionOpt->setEnabled(!logged);
    }
    if (m_btnLogoutOpt) {
        m_btnLogoutOpt->setVisible(logged);
        m_btnLogoutOpt->setEnabled(logged);
    }

    // ---- OFFLINE: limpiar y salir ----
    if (!logged) {
        if (ui->lblGreeting) ui->lblGreeting->setText("Hola, Invitado");

        // Limpia SOLO UI (no borra settings). Si quisieras borrar settings: true
        clearProfileUiForOffline(false);
        return;
    }

    // ---- LOGGED IN: muestra datos ----
    QString dn = auth->displayName().trimmed();
    if (dn.isEmpty()) dn = "Usuario";

    if (ui->lblGreeting)
        ui->lblGreeting->setText("Hola, " + dn);

    // Rellenar solo si está vacío
    if (ui->txtName && ui->txtName->text().trimmed().isEmpty())
        ui->txtName->setText(dn);

    const QString em = auth->email().trimmed();
    if (ui->txtEmail && ui->txtEmail->text().trimmed().isEmpty())
        ui->txtEmail->setText(em);

    const QString ph = auth->phone().trimmed();
    if (ui->txtPhone && ui->txtPhone->text().trimmed().isEmpty() && !ph.isEmpty())
        ui->txtPhone->setText(ph);
}


void PerfilWindow::onLogoutClicked()
{
    if (!m_home) return;

    closeOptionsPanel();
    m_home->requestLogout(this);
}

void PerfilWindow::onLogoutFromOptions()
{
    if (!m_home) return;

    closeOptionsPanel();
    m_home->requestLogout(this);
}
void PerfilWindow::onOpenSessionClicked()
{
    if (!m_ctx || !m_ctx->auth()) return;
    auto* auth = m_ctx->auth();

    if (auth->isLogged()) {
        QMessageBox::information(this, tr("Sesión"),
                                 tr("Ya hay una sesión activa. Cierra sesión primero."));
        return;
    }

    closeOptionsPanel();

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

