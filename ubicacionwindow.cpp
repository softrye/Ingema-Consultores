#include "ubicacionwindow.h"
#include "ui_ubicacionwindow.h"
#include "globalsearch.h"
#include "homewindow.h"
#include "appcontext.h"
#include "authsession.h"
#include "perfilwindow.h"
#include "toggleswitch.h"

#include <QLineEdit>
#include <QTimeEdit>
#include <QComboBox>
#include <QTime>
#include <QCheckBox>
#include <QDebug>

#include <QAbstractButton>
#include <QWidget>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QFrame>
#include <QPushButton>
#include <QPropertyAnimation>
#include <QEasingCurve>
#include <QSignalBlocker>
#include <QPainter>
#include <QKeyEvent>
#include <QApplication>
#include <QSettings>
#include <QStandardPaths>
#include <QDir>
#include <QFileDialog>
#include <QDesktopServices>
#include <QUrl>
#include <QMessageBox>
#include <QFile>
#include <QTextStream>
#include <QGraphicsOpacityEffect>
#include <QParallelAnimationGroup>
#include <QHideEvent>
#include <QQuickWidget>
#include <QQmlContext>
#include <QMouseEvent>
#include <QApplication>

namespace {

QString utmNoDecimals(double value)
{
    // Elimina decimales sin redondear.
    return QString::number(qRound64(value));
}

void applyUtmToUi(Ui::UbicacionWindow *ui, const QGeoCoordinate &coord)
{
    if (!ui || !coord.isValid())
        return;

    GpsManager::UTMCoord utm;
    if (!GpsManager::toUTM(coord, utm))
        return;

    if (ui->cboSistemaCoord) {
        QSignalBlocker blocker(ui->cboSistemaCoord);
        ui->cboSistemaCoord->setCurrentText("UTM");
    }

    if (ui->txtZona)
        ui->txtZona->setText(QString("%1%2").arg(utm.zone).arg(utm.band));

    if (ui->txtX)
        ui->txtX->setText(utmNoDecimals(utm.easting));

    if (ui->txtY)
        ui->txtY->setText(utmNoDecimals(utm.northing));
}

} // namespace

#if defined(Q_OS_ANDROID) && QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
#include <QPermissions>
#include <QLocationPermission>
#endif

static QPixmap centeredPixmap(const QPixmap& src, int outPx, int inPx)
{
    QPixmap canvas(outPx, outPx);
    canvas.fill(Qt::transparent);

    QPixmap scaled = src.scaled(inPx, inPx, Qt::KeepAspectRatio, Qt::SmoothTransformation);

    QPainter p(&canvas);
    p.setRenderHint(QPainter::SmoothPixmapTransform, true);
    const int x = (outPx - scaled.width()) / 2;
    const int y = (outPx - scaled.height()) / 2;
    p.drawPixmap(x, y, scaled);

    return canvas;
}


UbicacionData g_ubicacionData;

UbicacionWindow::UbicacionWindow(QWidget *parent)
    : QMainWindow(parent)
    , ui(new Ui::UbicacionWindow)
{
    ui->setupUi(this);

    qApp->installEventFilter(this);

    GlobalSearch::instance()->attach(ui->lineSearch);

    setWindowIcon(QApplication::windowIcon());

    // Tamaños: OUT = tamaño del label, IN = tamaño real del icono dentro (con “padding”)
    constexpr int OUT    = 24;
    constexpr int IN_ON  = 33;  // antes 18
    constexpr int IN_OFF = 9;


    m_gpsMovie = new QMovie(":/icons/images/GPS_Activo.gif", QByteArray(), this);
    m_gpsMovie->setCacheMode(QMovie::CacheAll);
    m_gpsMovie->setScaledSize(QSize(IN_ON, IN_ON));

    QPixmap rawInactive(":/icons/images/GPS_Inactivo.png");
    m_gpsInactive = centeredPixmap(rawInactive, OUT, IN_OFF);

    ui->lblGpsToggle->setFixedSize(OUT, OUT);
    ui->lblGpsToggle->setScaledContents(false);
    ui->lblGpsToggle->setAlignment(Qt::AlignCenter);

    // ✅ quitar borde “delatador”
    ui->lblGpsToggle->setFrameShape(QFrame::NoFrame);
    ui->lblGpsToggle->setLineWidth(0);
    ui->lblGpsToggle->setStyleSheet(
        "QLabel#lblGpsToggle { background: transparent; border: 0px; padding: 0px; margin: 0px; }"
        );



    // Estado inicial (si tu checkbox es chkGpsActivo)
    updateGpsIndicator(ui->chkGpsActivo->isChecked());



    setupMapWidget();
    setupMapResizeGrip();

    this->setWindowState(Qt::WindowMaximized);

    // Footer
    ui->btnHome->installEventFilter(this);
    ui->btnMap->installEventFilter(this);
    ui->btnDocs->installEventFilter(this);
    ui->btnProfile->installEventFilter(this);



    // Buscar botón menú por objectName (no rompe si no existe)
    m_btnMenu = this->findChild<QAbstractButton*>("btnMenu");
    if (m_btnMenu)
        m_btnMenu->installEventFilter(this);

    // Panel opciones
    setupOptionsPanel();

    // GpsManager
    connect(GpsManager::instance(), &GpsManager::positionUpdated,
            this, &UbicacionWindow::onGpsPositionUpdated);

    connect(ui->chkGpsActivo, &QCheckBox::toggled,
            this, &UbicacionWindow::on_chkGpsActivo_toggled);

    auto alignLeft = [](QLineEdit *le) {
        if (le) le->setAlignment(Qt::AlignLeft | Qt::AlignVCenter);
    };
    alignLeft(ui->txtZona);
    alignLeft(ui->txtX);
    alignLeft(ui->txtY);
    alignLeft(ui->txtAltitud);

    if (ui->timeHora)
        ui->timeHora->setAlignment(Qt::AlignLeft | Qt::AlignVCenter);

    // Datos previos
    syncUiFromGlobal();

    // Timer de hora local
    connect(&m_timerHora, &QTimer::timeout,
            this, &UbicacionWindow::actualizarHoraLocal);
    m_timerHora.start(1000);

    // Sync inicial global
    syncUiToGlobal();

    // Actualizar global cuando el usuario edita algo
    if (ui->cboSistemaCoord)
        connect(ui->cboSistemaCoord, &QComboBox::currentTextChanged,
                this, &UbicacionWindow::syncUiToGlobal);
    if (ui->txtZona)
        connect(ui->txtZona, &QLineEdit::textChanged,
                this, &UbicacionWindow::syncUiToGlobal);
    if (ui->txtX)
        connect(ui->txtX, &QLineEdit::textChanged,
                this, &UbicacionWindow::syncUiToGlobal);
    if (ui->txtY)
        connect(ui->txtY, &QLineEdit::textChanged,
                this, &UbicacionWindow::syncUiToGlobal);
    if (ui->txtAltitud)
        connect(ui->txtAltitud, &QLineEdit::textChanged,
                this, &UbicacionWindow::syncUiToGlobal);
    if (ui->timeHora)
        connect(ui->timeHora, &QTimeEdit::timeChanged,
                this, &UbicacionWindow::syncUiToGlobal);

    // Alinear checkbox UI con el estado real del manager
    syncGpsUiFromManager();

    // ---- AUTO-ON según preferencia guardada ----
    QSettings s;

#ifdef Q_OS_ANDROID
    bool wantOn = s.value("gps_enabled", true).toBool();   // móvil ON por defecto
#else
    bool wantOn = false;                                   // desktop SIEMPRE OFF
    s.setValue("gps_enabled", false);
    s.setValue("gps/autoShare", false);
#endif

    setGpsActiveInternal(wantOn, nullptr);



}

UbicacionWindow::~UbicacionWindow()
{
    qApp->removeEventFilter(this);

    delete ui;
}

void UbicacionWindow::showEvent(QShowEvent *event)
{
    QMainWindow::showEvent(event);
    syncUiFromGlobal();
    syncGpsUiFromManager();
    refreshProjectsPathLabel();
    updateGreeting();
}

void UbicacionWindow::resizeEvent(QResizeEvent *event)
{
    QMainWindow::resizeEvent(event);
    repositionOptionsPanel();
    repositionMapResizeGrip();
}

void UbicacionWindow::goTo(QMainWindow* w)
{
    if (!w) return;
    closeOptionsPanel();
    w->showMaximized();
    w->raise();
    w->activateWindow();
    this->hide();
}

// -------- Navegación footer + menú ----------
bool UbicacionWindow::eventFilter(QObject *obj, QEvent *event)
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

    // Reposicionar el grip cuando frameMapa cambie de tamaño
    if (obj == ui->frameMapa && event->type() == QEvent::Resize) {
        repositionMapResizeGrip();
        return false;
    }

    // Drag del grip del mapa
    if (obj == m_mapResizeGrip) {
        switch (event->type()) {
        case QEvent::MouseButtonPress: {
            auto *me = static_cast<QMouseEvent*>(event);
            if (me->button() == Qt::LeftButton) {
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
                m_mapResizeStartGlobal = me->globalPosition().toPoint();
#else
                m_mapResizeStartGlobal = me->globalPos();
#endif
                m_mapResizeStartHeight = ui->frameMapa ? ui->frameMapa->height() : 0;
                m_mapResizeDragging = true;
                return true;
            }
            break;
        }
        case QEvent::MouseMove: {
            if (!m_mapResizeDragging)
                break;

            auto *me = static_cast<QMouseEvent*>(event);
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
            const QPoint nowGlobal = me->globalPosition().toPoint();
#else
            const QPoint nowGlobal = me->globalPos();
#endif
            const int dy = nowGlobal.y() - m_mapResizeStartGlobal.y();
            applyMapHeight(m_mapResizeStartHeight + dy);
            return true;
        }
        case QEvent::MouseButtonRelease: {
            if (m_mapResizeDragging) {
                m_mapResizeDragging = false;

                QSettings s;
                if (ui->frameMapa)
                    s.setValue("ubicacion/mapHeight", ui->frameMapa->height());

                return true;
            }
            break;
        }
        default:
            break;
        }
    }
    if (event->type() == QEvent::MouseButtonPress) {

        if (m_btnMenu && obj == m_btnMenu) {
            toggleOptionsPanel();
            return true;
        }

        if (m_optionsVisible && m_dimOverlay && obj == m_dimOverlay) {
            closeOptionsPanel();
            return true;
        }

        if (obj == ui->btnHome) {
            if (!m_home) return false;
            goTo(m_home);
            return true;
        }

        if (obj == ui->btnDocs) {
            if (!m_home) return false;
            m_home->showDocumentsModule();
            return true;
        }

        if (obj == ui->btnProfile) {
            if (!m_home) return false;
            m_home->ensurePerfilWindow();
            goTo(m_home->perfilWin());
            return true;
        }

        if (obj == ui->btnMap) {
            return true; // ya estás aquí
        }
    }

    return QMainWindow::eventFilter(obj, event);
}



void UbicacionWindow::setGpsActiveInternal(bool on, QObject *origin)
{
    if (ui->chkGpsActivo && origin != ui->chkGpsActivo) {
        QSignalBlocker b(ui->chkGpsActivo);
        ui->chkGpsActivo->setChecked(on);
    }
    if (m_swGpsMenu && origin != m_swGpsMenu) {
        QSignalBlocker b(m_swGpsMenu);
        m_swGpsMenu->setChecked(on);
    }

    updateGpsIndicator(on);
    setGpsFieldsReadOnly(on);

    if (m_mapController) {
        m_mapController->setGpsActive(on);

        // Cuando el GPS se prende, vuelve a modo original de seguimiento.
        // Cuando se apaga, se habilita el modo manual.
        m_mapController->setFollowGps(on);
    }

    QSettings s;
    s.setValue("gps_enabled", on);
    s.setValue("gps/autoShare", on);

    if (on) {
        if (!GpsManager::instance()->isActive())
            GpsManager::instance()->start();
    } else {
        if (GpsManager::instance()->isActive())
            GpsManager::instance()->stop();
    }

    emit gpsAutoShareChanged(on);
}



void UbicacionWindow::syncGpsUiFromManager()
{
    const bool on = GpsManager::instance()->isActive();

    if (ui->chkGpsActivo) {
        QSignalBlocker b(ui->chkGpsActivo);
        ui->chkGpsActivo->setChecked(on);
    }
    if (m_swGpsMenu) {
        QSignalBlocker b(m_swGpsMenu);
        m_swGpsMenu->setChecked(on);
    }

    updateGpsIndicator(on);
    setGpsFieldsReadOnly(on);

    if (m_mapController)
        m_mapController->setGpsActive(on);
}

// -------- GPS ON/OFF (UI principal) ----------
void UbicacionWindow::on_chkGpsActivo_toggled(bool checked)
{
    setGpsActiveInternal(checked, ui->chkGpsActivo);
}


void UbicacionWindow::actualizarHoraLocal()
{
    if (!ui->timeHora) return;

    ui->timeHora->setTime(QTime::currentTime());   // siempre
    syncUiToGlobal();                               // si quieres mantener g_ubicacionData.hora al día
}

void UbicacionWindow::syncUiToGlobal()
{
    g_ubicacionData.sistemaCoord = ui->cboSistemaCoord
                                       ? ui->cboSistemaCoord->currentText() : QString();
    g_ubicacionData.zona    = ui->txtZona    ? ui->txtZona->text()    : QString();
    g_ubicacionData.x       = ui->txtX       ? ui->txtX->text()       : QString();
    g_ubicacionData.y       = ui->txtY       ? ui->txtY->text()       : QString();
    g_ubicacionData.altitud = ui->txtAltitud ? ui->txtAltitud->text() : QString();

    if (ui->timeHora)
        g_ubicacionData.hora = ui->timeHora->time().toString("HH:mm:ss");
    else
        g_ubicacionData.hora.clear();
}

void UbicacionWindow::syncUiFromGlobal()
{
    if (ui->cboSistemaCoord && !g_ubicacionData.sistemaCoord.isEmpty())
        ui->cboSistemaCoord->setCurrentText(g_ubicacionData.sistemaCoord);
    if (ui->txtZona && !g_ubicacionData.zona.isEmpty())
        ui->txtZona->setText(g_ubicacionData.zona);
    if (ui->txtX && !g_ubicacionData.x.isEmpty())
        ui->txtX->setText(g_ubicacionData.x);
    if (ui->txtY && !g_ubicacionData.y.isEmpty())
        ui->txtY->setText(g_ubicacionData.y);
    if (ui->txtAltitud && !g_ubicacionData.altitud.isEmpty())
        ui->txtAltitud->setText(g_ubicacionData.altitud);

    if (ui->timeHora) {
        if (!g_ubicacionData.hora.isEmpty()) {
            QTime t = QTime::fromString(g_ubicacionData.hora, "HH:mm:ss");
            ui->timeHora->setTime(t.isValid() ? t : QTime::currentTime());
        } else {
            ui->timeHora->setTime(QTime::currentTime());
        }
    }
}

void UbicacionWindow::onGpsPositionUpdated(const QGeoCoordinate &coord,
                                           double altitude,
                                           const QDateTime &time)
{
    Q_UNUSED(time);

    if (m_mapController)
        m_mapController->setCoordinate(coord);

    applyUtmToUi(ui, coord);

    if (ui->txtAltitud) {
        if (qIsFinite(altitude))
            ui->txtAltitud->setText(QString::number(altitude, 'f', 1));
        else
            ui->txtAltitud->setText("N/D");
    }

    syncUiToGlobal();
}


// ===== Panel Opciones =====
QString UbicacionWindow::defaultProjectsPath() const
{
    const QString homePath = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    return homePath + "/InGePlusProyectos";
}

QString UbicacionWindow::projectsBasePath() const
{
    QSettings s;
    const QString p = s.value("projects_base_path").toString().trimmed();
    return p.isEmpty() ? defaultProjectsPath() : p;
}

void UbicacionWindow::setProjectsBasePath(const QString &path)
{
    QSettings s;
    s.setValue("projects_base_path", QDir::cleanPath(path));
}

void UbicacionWindow::refreshProjectsPathLabel()
{
    if (!m_lblBasePath) return;
    m_lblBasePath->setText(projectsBasePath());
}

void UbicacionWindow::setupOptionsPanel()
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
        auto *row = new QHBoxLayout();
        row->setContentsMargins(0, 0, 0, 0);
        row->setSpacing(10);

        auto *gpsText = new QLabel(tr("Compartir ubicación automática (GPS)"), m_optionsPanel);
        gpsText->setStyleSheet("color:#1B2A4E;");
        row->addWidget(gpsText);
        row->addStretch();

        m_swGpsMenu = new ToggleSwitch(m_optionsPanel);
        m_swGpsMenu->setChecked(GpsManager::instance()->isActive());
        row->addWidget(m_swGpsMenu);

        lay->addLayout(row);

        connect(m_swGpsMenu, &ToggleSwitch::toggled, this, [this](bool on) {
            setGpsActiveInternal(on, m_swGpsMenu);
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
    refreshProjectsPathLabel();

    auto *btnChangeFolder = new QPushButton(tr("Cambiar carpeta de proyectos..."), m_optionsPanel);
    auto *btnOpenFolder   = new QPushButton(tr("Abrir carpeta de proyectos"), m_optionsPanel);
    auto *btnResetFolder  = new QPushButton(tr("Restaurar ubicación por defecto"), m_optionsPanel);

    lay->addWidget(btnChangeFolder);
    lay->addWidget(btnOpenFolder);
    lay->addWidget(btnResetFolder);

    connect(btnChangeFolder, &QPushButton::clicked,
            this, &UbicacionWindow::actionChangeProjectsFolder);

    connect(btnOpenFolder, &QPushButton::clicked,
            this, &UbicacionWindow::actionOpenProjectsFolder);

    connect(btnResetFolder, &QPushButton::clicked, this, [this]() {
        setProjectsBasePath(defaultProjectsPath());
        refreshProjectsPathLabel();
        QMessageBox::information(
            this,
            tr("Carpeta restaurada"),
            tr("Se restauró la carpeta de proyectos por defecto.")
            );
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

    if (m_home && m_home->ctx() && m_home->ctx()->auth()) {
        logged = m_home->ctx()->auth()->isLogged();
        const QString dn = m_home->ctx()->auth()->displayName().trimmed();
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

    connect(btnProfile, &QPushButton::clicked,
            this, &UbicacionWindow::actionOpenProfileFromMenu);

    connect(btnAbout, &QPushButton::clicked, this, [this]() {
        closeOptionsPanel();
        QMessageBox::information(
            this,
            tr("Acerca de / Versión"),
            tr("InGe+ (AppCalicatasDemo)\n\n"
               "Ventana: Ubicación\n"
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

    connect(btnLog, &QPushButton::clicked,
            this, &UbicacionWindow::actionExportLog);

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
            this, &UbicacionWindow::onOpenSessionClicked);

    m_btnLogout = new QPushButton(tr("Cerrar sesión (modo offline)"), m_optionsPanel);
    m_btnLogout->setObjectName("btnLogout");
    m_btnLogout->setCursor(Qt::PointingHandCursor);
    lay->addWidget(m_btnLogout);

    connect(m_btnLogout, &QPushButton::clicked, this, [this]() {
        closeOptionsPanel();
        if (m_home)
            m_home->requestLogout(this);
    });

    {
        bool isLogged = false;
        if (m_home && m_home->ctx() && m_home->ctx()->auth())
            isLogged = m_home->ctx()->auth()->isLogged();

        if (m_btnLogout)      m_btnLogout->setEnabled(isLogged);
        if (m_btnOpenSession) m_btnOpenSession->setEnabled(!isLogged);
    }

    m_btnClosePanel = new QPushButton(tr("Cerrar"), m_optionsPanel);
    m_btnClosePanel->setObjectName("btnClosePanel");
    lay->addWidget(m_btnClosePanel);
    connect(m_btnClosePanel, &QPushButton::clicked,
            this, &UbicacionWindow::closeOptionsPanel);

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
        if (!m_optionsVisible) {
            if (m_optionsPanel) m_optionsPanel->hide();
            if (m_dimOverlay)  m_dimOverlay->hide();
        }
    });

    repositionOptionsPanel();
    m_optionsPanel->hide();
    m_dimOverlay->hide();
    if (m_dimFx) m_dimFx->setOpacity(0.0);
}



void UbicacionWindow::repositionOptionsPanel()
{
    QWidget *base = ui->centralwidget ? ui->centralwidget : this;

    const int h = base->height();
    const int w = base->width();

    if (m_dimOverlay) {
        m_dimOverlay->setGeometry(0, 0, w, h);
    }

    if (m_optionsPanel) {
        m_optionsPanel->setFixedHeight(h);

        const int xHidden = w;
        const int xShown  = w - m_optionsPanel->width();
        m_optionsPanel->move(m_optionsVisible ? xShown : xHidden, 0);
    }
}


void UbicacionWindow::toggleOptionsPanel()
{
    if (m_optionsVisible) closeOptionsPanel();
    else openOptionsPanel();
}

void UbicacionWindow::openOptionsPanel()
{
    updateGreeting();

    if (!m_optionsPanel || !m_optionsGroup) return;

    refreshProjectsPathLabel();
    syncGpsUiFromManager();

    m_optionsVisible = true;
    repositionOptionsPanel();

    QWidget *base = ui->centralwidget ? ui->centralwidget : this;
    const int w = base->width();

    if (m_dimOverlay) {
        m_dimOverlay->show();
        m_dimOverlay->raise();
    }

    m_optionsPanel->show();
    m_optionsPanel->raise();

    const QPoint endPos(w - m_optionsPanel->width(), 0);

    m_optionsGroup->stop();

    // Slide: desde pos actual a visible
    m_optionsAnim->setStartValue(m_optionsPanel->pos());
    m_optionsAnim->setEndValue(endPos);

    // Fade: desde opacidad actual a 1
    m_dimAnim->setStartValue(m_dimFx ? m_dimFx->opacity() : 0.0);
    m_dimAnim->setEndValue(1.0);

    m_optionsGroup->start();
}


void UbicacionWindow::closeOptionsPanel()
{
    if (!m_optionsPanel || !m_optionsGroup) return;
    if (!m_optionsVisible) return;

    m_optionsVisible = false;

    QWidget *base = ui->centralwidget ? ui->centralwidget : this;
    const int w = base->width();

    const QPoint endPos(w, 0);

    m_optionsGroup->stop();

    // Slide: hacia afuera
    m_optionsAnim->setStartValue(m_optionsPanel->pos());
    m_optionsAnim->setEndValue(endPos);

    // Fade: a transparente
    m_dimAnim->setStartValue(m_dimFx ? m_dimFx->opacity() : 1.0);
    m_dimAnim->setEndValue(0.0);

    m_optionsGroup->start();
}

void UbicacionWindow::hideEvent(QHideEvent *event)
{
    m_optionsVisible = false;

    if (m_optionsGroup) m_optionsGroup->stop();
    else if (m_optionsAnim) m_optionsAnim->stop();

    if (m_dimFx) m_dimFx->setOpacity(0.0);

    QWidget *base = ui->centralwidget ? ui->centralwidget : this;
    const int w = base->width();

    if (m_optionsPanel) {
        m_optionsPanel->hide();
        m_optionsPanel->move(w, 0);
    }
    if (m_dimOverlay) {
        m_dimOverlay->hide();
    }

    QMainWindow::hideEvent(event);
}


// ===== Acciones del panel =====
void UbicacionWindow::actionChangeProjectsFolder()
{
    const QString cur = projectsBasePath();
    const QString dir = QFileDialog::getExistingDirectory(
        this,
        tr("Selecciona la carpeta de proyectos"),
        cur
        );
    if (dir.trimmed().isEmpty())
        return;

    QDir().mkpath(dir);
    setProjectsBasePath(dir);
    refreshProjectsPathLabel();

    QMessageBox::information(this, tr("Carpeta actualizada"),
                             tr("Se guardó la nueva carpeta de proyectos."));
}

void UbicacionWindow::actionOpenProjectsFolder()
{
    const QString p = projectsBasePath();
    QDesktopServices::openUrl(QUrl::fromLocalFile(p));
}

void UbicacionWindow::actionRestoreDefaultLocation()
{
    setGpsActiveInternal(false, nullptr);

    if (m_mapController) {
        m_mapController->setCoordinate(QGeoCoordinate());
        m_mapController->setFollowGps(false);
        m_mapController->setGpsActive(false);
    }

    g_ubicacionData = UbicacionData{};
    syncUiFromGlobal();
    syncUiToGlobal();

    QMessageBox::information(this, tr("Ubicación restaurada"),
                             tr("Se apagó el GPS y se restauró la ubicación por defecto."));
}

void UbicacionWindow::actionOpenProfileFromMenu()
{
    if (!m_home) return;

    m_home->ensurePerfilWindow();
    goTo(m_home->perfilWin());
}

void UbicacionWindow::actionAbout()
{
    QMessageBox::information(this, tr("Acerca de"),
                             tr("InGe+ / AppCalicatas\n"
                                "Captura de fichas geotécnicas (JSON) + exportación a Excel\n"
                                "y soporte de coordenadas/GPS."));
}

void UbicacionWindow::actionExportLog()
{
    const QString file = QFileDialog::getSaveFileName(
        this, tr("Guardar log"),
        QDir::home().absoluteFilePath("ingeplus_log.txt"),
        tr("Text (*.txt)")
        );
    if (file.isEmpty()) return;

    QFile f(file);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate | QIODevice::Text)) {
        QMessageBox::warning(this, tr("Error"), tr("No se pudo escribir el archivo."));
        return;
    }

    QTextStream out(&f);
    out << "=== InGe+ Log ===\n";
    out << "Hora: " << QDateTime::currentDateTime().toString(Qt::ISODate) << "\n";
    out << "GPS activo: " << (GpsManager::instance()->isActive() ? "SI" : "NO") << "\n\n";
    out << "Ubicación global:\n";
    out << "  Sistema: " << g_ubicacionData.sistemaCoord << "\n";
    out << "  Zona:    " << g_ubicacionData.zona << "\n";
    out << "  X:       " << g_ubicacionData.x << "\n";
    out << "  Y:       " << g_ubicacionData.y << "\n";
    out << "  Altitud: " << g_ubicacionData.altitud << "\n";
    out << "  Hora:    " << g_ubicacionData.hora << "\n";
    out << "\nCarpeta de proyectos:\n  " << projectsBasePath() << "\n";
    f.close();

    QMessageBox::information(this, tr("Listo"), tr("Log exportado correctamente."));
}

void UbicacionWindow::setupMapWidget()
{
    QWidget* container = ui->mapContainer;
    if (!container) {
        qDebug() << "[UbicacionWindow] ERROR: ui->mapContainer es null. Revisa el objectName en el .ui";
        return;
    }

    if (!container->layout()) {
        auto *lay = new QVBoxLayout(container);
        lay->setContentsMargins(0,0,0,0);
        lay->setSpacing(0);
    } else {
        container->layout()->setContentsMargins(0,0,0,0);
        container->layout()->setSpacing(0);
    }

    if (!m_mapQuick) {
        m_mapQuick = new QQuickWidget(container);
        m_mapQuick->setResizeMode(QQuickWidget::SizeRootObjectToView);
        m_mapQuick->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);
        container->layout()->addWidget(m_mapQuick);

        connect(m_mapQuick, &QQuickWidget::statusChanged,
                this,
                [this](QQuickWidget::Status st){
                    if (st == QQuickWidget::Error) {
                        qDebug() << "[Map] status = Error";
                        for (const auto &e : m_mapQuick->errors())
                            qDebug() << "[Map QML Error]" << e.toString();
                    }
                });
    }

    if (!m_mapController) {
        m_mapController = new MapController(this);

        // Coordenada manual seleccionada desde el mapa
        connect(m_mapController, &MapController::coordinatePicked,
                this,
                [this](const QGeoCoordinate &coord){
                    if (!coord.isValid())
                        return;

                    applyUtmToUi(ui, coord);

                    if (ui->txtAltitud)
                        ui->txtAltitud->setText("N/D");

                    syncUiToGlobal();
                });
    }

    m_mapController->setGpsActive(ui->chkGpsActivo && ui->chkGpsActivo->isChecked());
    m_mapController->setFollowGps(ui->chkGpsActivo && ui->chkGpsActivo->isChecked());

    m_mapQuick->rootContext()->setContextProperty("mapController", m_mapController);
    m_mapQuick->setSource(QUrl(QStringLiteral("qrc:/qml/MapWidget.qml")));
}

void UbicacionWindow::setGpsFieldsReadOnly(bool ro)
{
    if (ui->txtZona)    ui->txtZona->setReadOnly(ro);
    if (ui->txtX)       ui->txtX->setReadOnly(ro);
    if (ui->txtY)       ui->txtY->setReadOnly(ro);
    if (ui->txtAltitud) ui->txtAltitud->setReadOnly(ro);

    // Si GPS manda siempre UTM, mejor bloquear el combo mientras esté ON
    if (ui->cboSistemaCoord) ui->cboSistemaCoord->setEnabled(!ro);
}

void UbicacionWindow::setGpsAutoShare(bool on)
{
    setGpsActiveInternal(on, nullptr);
}

void UbicacionWindow::updateGpsIndicator(bool on)
{
    if (on) {
        ui->lblGpsToggle->setMovie(m_gpsMovie);
        if (m_gpsMovie->state() != QMovie::Running)
            m_gpsMovie->start();
    } else {
        if (m_gpsMovie) m_gpsMovie->stop();
        ui->lblGpsToggle->setMovie(nullptr);
        ui->lblGpsToggle->setPixmap(m_gpsInactive);  // <- ya viene escalado
    }
}




bool UbicacionWindow::isGpsActive() const
{
    return ui->chkGpsActivo->isChecked();
}
void UbicacionWindow::setGpsActive(bool on)
{
    setGpsActiveInternal(on, nullptr);
}

void UbicacionWindow::closeEvent(QCloseEvent *e)
{
    QMainWindow::closeEvent(e); // comportamiento normal
}

void UbicacionWindow::setHome(HomeWindow* h)
{
    m_home = h;

    // Conectar a auth cuando Home ya existe
    if (m_home && m_home->ctx() && m_home->ctx()->auth()) {
        auto* auth = m_home->ctx()->auth();

        connect(auth, &AuthSession::userInfoChanged,
                this, &UbicacionWindow::updateGreeting,
                Qt::UniqueConnection);

        connect(auth, &AuthSession::loggedOut,
                this, &UbicacionWindow::updateGreeting,
                Qt::UniqueConnection);
    }

    updateGreeting(); // pinta el estado actual
}

void UbicacionWindow::updateGreeting()
{
    if (!ui || !ui->lblGreeting) return;

    QString name = "Invitado";

    if (m_home && m_home->ctx() && m_home->ctx()->auth()) {
        const QString dn = m_home->ctx()->auth()->displayName().trimmed();
        if (!dn.isEmpty()) name = dn;
    }

    ui->lblGreeting->setText("Hola, " + name);

    // ✅ Habilitar/deshabilitar botón de logout según sesión
    if (m_btnLogout) {
        bool logged = false;
        if (m_home && m_home->ctx() && m_home->ctx()->auth())
            logged = m_home->ctx()->auth()->isLogged();
        m_btnLogout->setEnabled(logged);
    }

    // ✅ Habilitar/deshabilitar botones según sesión
    bool logged = false;
    if (m_home && m_home->ctx() && m_home->ctx()->auth())
        logged = m_home->ctx()->auth()->isLogged();

    if (m_btnLogout)      m_btnLogout->setEnabled(logged);
    if (m_btnOpenSession) m_btnOpenSession->setEnabled(!logged);


}

void UbicacionWindow::onOpenSessionClicked()
{
    // Solo si tenemos auth
    if (!m_home || !m_home->ctx() || !m_home->ctx()->auth())
        return;

    auto* auth = m_home->ctx()->auth();

    // Seguridad: si hay sesión, no abras login
    if (auth->isLogged()) {
        QMessageBox::information(this, tr("Sesión"),
                                 tr("Ya hay una sesión activa. Cierra sesión primero."));
        return;
    }

    closeOptionsPanel();

    QWidget* mw = nullptr;
    for (QWidget* w : QApplication::topLevelWidgets()) {
        if (w && w->inherits("MainWindow")) { mw = w; break; }
    }

    if (!mw) {
        QMessageBox::warning(this, tr("Iniciar sesión"),
                             tr("No se encontró MainWindow.\n"
                                "Asegúrate de NO cerrarlo al loguear; usa hide()."));
        return;
    }

    // Forzar página login
    QMetaObject::invokeMethod(mw, "showLoginPage", Qt::QueuedConnection);

    mw->showMaximized();
    mw->raise();
    mw->activateWindow();

    this->hide();
}

void UbicacionWindow::setupMapResizeGrip()
{
    if (!ui->frameMapa || m_mapResizeGrip)
        return;

    auto *grip = new QLabel(ui->frameMapa);
    grip->setObjectName("mapResizeGrip");
    grip->setFixedSize(18, 18);
    grip->setCursor(Qt::SizeFDiagCursor);
    static_cast<QLabel*>(grip)->setText("◢");
    static_cast<QLabel*>(grip)->setAlignment(Qt::AlignCenter);
    grip->setStyleSheet(
        "QLabel#mapResizeGrip {"
        "   background: rgba(255,255,255,0.75);"
        "   border: 1px solid #C2CEE8;"
        "   border-radius: 4px;"
        "   color: #7A8CA4;"
        "   font-size: 10pt;"
        "}"
        "QLabel#mapResizeGrip:hover {"
        "   background: #FFFFFF;"
        "   color: #0B74D1;"
        "   border: 1px solid #0B74D1;"
        "}"
        );

    m_mapResizeGrip = grip;

    m_mapResizeGrip->installEventFilter(this);
    ui->frameMapa->installEventFilter(this);

    QSettings s;
    const int savedHeight = s.value("ubicacion/mapHeight",
                                    qMax(m_mapMinHeight, ui->frameMapa->height())).toInt();

    applyMapHeight(savedHeight);
    repositionMapResizeGrip();
    m_mapResizeGrip->raise();
}

void UbicacionWindow::repositionMapResizeGrip()
{
    if (!ui->frameMapa || !m_mapResizeGrip)
        return;

    const int marginRight = 6;
    const int marginBottom = 4;

    const int x = ui->frameMapa->width()  - m_mapResizeGrip->width()  - marginRight;
    const int y = ui->frameMapa->height() - m_mapResizeGrip->height() - marginBottom;

    m_mapResizeGrip->move(qMax(0, x), qMax(0, y));
    m_mapResizeGrip->raise();
}

void UbicacionWindow::applyMapHeight(int h)
{
    if (!ui->frameMapa)
        return;

    const int clamped = qBound(m_mapMinHeight, h, m_mapMaxHeight);

    ui->frameMapa->setFixedHeight(clamped);

    // opcional: aseguras que el contenedor del mapa nunca quede demasiado chico
    if (ui->mapContainer) {
        const int titleZone = 42; // aprox: título + márgenes internos
        ui->mapContainer->setMinimumHeight(qMax(180, clamped - titleZone));
    }

    repositionMapResizeGrip();
}

void UbicacionWindow::applyExternalManualCoordinate(const QGeoCoordinate& coord)
{
    if (!coord.isValid())
        return;

    if (isGpsActive())
        return; // si GPS está activo, no permitimos modo manual externo

    if (m_mapController) {
        m_mapController->setGpsActive(false);
        m_mapController->setFollowGps(false);
        m_mapController->setCoordinate(coord);
    }

    applyUtmToUi(ui, coord);

    if (ui->txtAltitud)
        ui->txtAltitud->setText("N/D");

    syncUiToGlobal();
}
