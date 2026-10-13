#include "taludeseditorwindow.h"
#include "ui_taludeseditorwindow.h"

#include "taludformbase.h"
#include "TaludSueloWindow.h"
#include "TaludRocaWindow.h"
#include "gpsmanager.h"
#include "ubicacionwindow.h"
#include "homewindow.h"
#include "appcontext.h"

#include <QApplication>
#include <QPainter>
#include <QTabWidget>
#include <QTabBar>
#include <QToolButton>
#include <QHBoxLayout>
#include <QFileInfo>
#include <QStandardPaths>
#include <QDir>
#include <QCloseEvent>
#include <QMessageBox>
#include <QAbstractButton>
#include <QPushButton>
#include <QMenu>
#include <QSettings>
#include <QSignalBlocker>
#include <QShowEvent>
#include <QMovie>
#include <QIcon>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QFile>
#include <QFileDialog>
#include <QDateTime>

// ------------------------------------------------------------
// Helpers de path / keys
// ------------------------------------------------------------
static QString cleanPath2(QString p)
{
    p = p.trimmed();
    if (p.isEmpty()) return {};
    return QDir::cleanPath(QDir::fromNativeSeparators(p));
}

static QString absPathPreserveCase(const QString& p)
{
    QString abs = QDir::cleanPath(QDir::fromNativeSeparators(QFileInfo(p).absoluteFilePath()));

#ifdef Q_OS_WIN
    QFileInfo fi(abs);
    QDir dir(fi.absolutePath());
    const QString wanted = fi.fileName();

    const QFileInfoList list = dir.entryInfoList(QDir::Files | QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QFileInfo& e : list) {
        if (e.fileName().compare(wanted, Qt::CaseInsensitive) == 0) {
            return QDir::cleanPath(dir.absoluteFilePath(e.fileName()));
        }
    }
#endif

    return abs;
}

static QString openKeyForAbs(const QString& abs)
{
    QString k = QDir::cleanPath(QDir::fromNativeSeparators(abs));
#ifdef Q_OS_WIN
    k = k.toLower();
#endif
    return k;
}

TaludesEditorWindow::TaludesEditorWindow(QWidget *parent)
    : QMainWindow(parent)
    , ui(new Ui::TaludesEditorWindow)
{
    ui->setupUi(this);

    setObjectName("TaludesEditorWindow");
    setWindowIcon(QApplication::windowIcon());

    m_baseTitle = tr("Editor de Taludes");
    updateEditorTitle();

    // --- Tabs ---
    ui->tabWidgetTaludes->clear();
    ui->tabWidgetTaludes->setDocumentMode(true);
    ui->tabWidgetTaludes->setMovable(true);
    ui->tabWidgetTaludes->setTabsClosable(true);
    ui->tabWidgetTaludes->tabBar()->setExpanding(false);

    connect(ui->tabWidgetTaludes, &QTabWidget::tabCloseRequested,
            this, &TaludesEditorWindow::onTabCloseRequested);

    connect(ui->tabWidgetTaludes, &QTabWidget::currentChanged,
            this, &TaludesEditorWindow::onCurrentTabChanged);

    // ---- Corner buttons ----
    auto *corner = new QWidget(this);
    auto *lay = new QHBoxLayout(corner);
    lay->setContentsMargins(0,0,0,0);
    lay->setSpacing(6);

    auto mkBtn = [corner](const QString &txt){
        auto *b = new QToolButton(corner);
        b->setText(txt);
        b->setAutoRaise(true);
        b->setCursor(Qt::PointingHandCursor);
        return b;
    };

    auto *btnPlus = mkBtn("+");
    auto *btnAbrir = mkBtn("Abrir");
    m_btnGuardar = mkBtn("Guardar");
    m_btnGuardarComo = mkBtn("Guardar como…");

    m_btnAutoSave = mkBtn("Auto-guardar");
    m_btnAutoSave->setCheckable(true);
    m_btnAutoSave->setChecked(false);
    m_btnAutoSave->setToolTip(tr("Auto-guardar cada ~20s (solo si la ficha ya tiene archivo)"));

    m_btnGps = mkBtn("GPS");
    m_btnGps->setCheckable(true);
    m_btnGps->setToolTip(tr("Activar/desactivar GPS automático"));
    m_btnGps->setIconSize(QSize(18, 18));
    m_btnGps->setToolButtonStyle(Qt::ToolButtonTextBesideIcon);

    m_btnExport = mkBtn("Exportar Excel");
    auto *btnSalir = mkBtn("Salir");

    btnPlus->setToolTip(tr("Nueva ficha de talud"));

    lay->addWidget(btnPlus);
    lay->addWidget(m_btnGps);
    lay->addWidget(btnAbrir);
    lay->addWidget(m_btnGuardar);
    lay->addWidget(m_btnGuardarComo);
    lay->addWidget(m_btnAutoSave);
    lay->addWidget(m_btnExport);
    lay->addWidget(btnSalir);

    corner->setObjectName("editorCornerBar");

    btnPlus->setObjectName("tbNuevo");
    btnAbrir->setObjectName("tbAbrir");
    m_btnGuardar->setObjectName("tbGuardar");
    m_btnGuardarComo->setObjectName("tbGuardarComo");
    m_btnAutoSave->setObjectName("tbAutoSave");
    m_btnGps->setObjectName("tbGps");
    m_btnExport->setObjectName("tbExport");
    btnSalir->setObjectName("tbSalir");

    ui->tabWidgetTaludes->setCornerWidget(corner, Qt::TopRightCorner);

    // --- Conexiones principales ---
    connect(btnAbrir, &QToolButton::clicked, this, &TaludesEditorWindow::onAbrir);
    connect(m_btnGuardar, &QToolButton::clicked, this, &TaludesEditorWindow::onGuardar);
    connect(m_btnGuardarComo, &QToolButton::clicked, this, &TaludesEditorWindow::onGuardarComo);
    connect(m_btnAutoSave, &QToolButton::toggled, this, &TaludesEditorWindow::onAutoSaveToggled);
    connect(m_btnExport, &QToolButton::clicked, this, &TaludesEditorWindow::onExportExcel);
    connect(btnSalir, &QToolButton::clicked, this, &TaludesEditorWindow::onVolver);

    // botón + con menú: Suelo / Roca
    auto *menuNuevo = new QMenu(btnPlus);
    auto *aNuevoSuelo = menuNuevo->addAction(tr("Nueva ficha de Talud Suelo"));
    auto *aNuevoRoca  = menuNuevo->addAction(tr("Nueva ficha de Talud Roca"));

    connect(aNuevoSuelo, &QAction::triggered, this, &TaludesEditorWindow::onNuevoTabSuelo);
    connect(aNuevoRoca,  &QAction::triggered, this, &TaludesEditorWindow::onNuevoTabRoca);

    btnPlus->setMenu(menuNuevo);
    btnPlus->setPopupMode(QToolButton::MenuButtonPopup);
    connect(btnPlus, &QToolButton::clicked, btnPlus, &QToolButton::showMenu);

    // GPS
    connect(m_btnGps, &QToolButton::toggled, this, &TaludesEditorWindow::onGpsToggled);

    {
        QSettings s;
        const bool on = s.value("gps/autoShare", false).toBool();
        QSignalBlocker b(m_btnGps);
        m_btnGps->setChecked(on);
        m_gpsOn = on;
    }

    m_gpsBtnInactiveIcon = QIcon(":/icons/images/GPS_Inactivo.png");

    if (!m_gpsBtnMovie) {
        m_gpsBtnMovie = new QMovie(":/icons/images/GPS_Activo.gif", QByteArray(), this);
        m_gpsBtnMovie->setCacheMode(QMovie::CacheAll);
        m_gpsBtnMovie->setScaledSize(m_btnGps->iconSize());

        connect(m_gpsBtnMovie, &QMovie::frameChanged, this, [this](int){
            if (!m_btnGps || !m_btnGps->isChecked() || !m_gpsBtnMovie) return;

            QPixmap pm = m_gpsBtnMovie->currentPixmap();
            if (pm.isNull()) return;

            const QSize iconSz = m_btnGps->iconSize();
            pm = pm.scaled(iconSz, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
            m_btnGps->setIcon(QIcon(pm));
            m_btnGps->update();
        });
    }

    // mismo look del editor de calicatas, adaptado al objectName nuevo
    this->setStyleSheet(R"QSS(
QMainWindow#TaludesEditorWindow,
QMainWindow#TaludesEditorWindow QWidget#centralwidget {
    background-color: #041823;
}

QMainWindow#TaludesEditorWindow QTabWidget::pane {
    border: 1px solid rgba(255,255,255,18);
    border-radius: 12px;
    background: rgba(0,0,0,16);
    padding: 10px;
    top: -1px;
}

QMainWindow#TaludesEditorWindow QTabBar {
    background: transparent;
}

QMainWindow#TaludesEditorWindow QTabBar::tab {
    background: rgba(255,255,255,10);
    color: rgba(255,255,255,230);
    border: 1px solid rgba(255,255,255,22);
    border-bottom: none;
    border-top-left-radius: 10px;
    border-top-right-radius: 10px;
    padding: 6px 10px;
    margin-right: 6px;
}

QMainWindow#TaludesEditorWindow QTabBar::tab:hover {
    background: rgba(255,255,255,16);
}

QMainWindow#TaludesEditorWindow QTabBar::tab:selected {
    background: #0087AE;
    border: 1px solid rgba(255,255,255,26);
    border-bottom: none;
    color: #FFFFFF;
}

QWidget#editorCornerBar {
    background: transparent;
}

QWidget#editorCornerBar QToolButton {
    background: rgba(255,255,255,10);
    color: #FFFFFF;
    border: 1px solid rgba(255,255,255,35);
    border-radius: 10px;
    padding: 6px 10px;
}

QWidget#editorCornerBar QToolButton#tbNuevo {
    background: #FDAC11;
    border: 1px solid rgba(255,255,255,45);
    color: #FFFFFF;
    font-weight: bold;
}
QWidget#editorCornerBar QToolButton#tbNuevo:hover { background: #FFB52B; }
QWidget#editorCornerBar QToolButton#tbNuevo:pressed { background: #E59A00; }

QWidget#editorCornerBar QToolButton:hover {
    background: rgba(255,255,255,18);
}

QWidget#editorCornerBar QToolButton:pressed {
    background: rgba(0,0,0,12);
}

QWidget#editorCornerBar QToolButton:checked {
    background: rgba(111,192,74,22);
    border: 1px solid rgba(111,192,74,160);
}

QWidget#editorCornerBar QToolButton#tbSalir {
    background: rgba(0,0,0,14);
    border: 1px solid rgba(255,255,255,28);
}
QWidget#editorCornerBar QToolButton#tbSalir:hover {
    background: rgba(0,0,0,22);
}

QWidget#editorCornerBar QToolButton:disabled {
    background: rgba(255,255,255,6);
    border: 1px solid rgba(255,255,255,14);
    color: rgba(255,255,255,90);
}

QMainWindow#TaludesEditorWindow QMenu {
    background-color: #005282;
    border: 1px solid rgba(255,255,255,28);
    border-radius: 12px;
    padding: 4px;
}

QMainWindow#TaludesEditorWindow QMenu::item {
    color: #FFFFFF;
    padding: 6px 10px;
    border-radius: 8px;
}

QMainWindow#TaludesEditorWindow QMenu::item:selected {
    background: #FFFFFF;
    color: #0F1F2A;
}

QMainWindow#TaludesEditorWindow QMenu::separator {
    height: 1px;
    background: rgba(255,255,255,18);
    margin: 4px 6px;
}
)QSS");

    setGpsButtonVisual(m_gpsOn);

    crearTabPorDefecto();
    updateActionsForCurrent();
}

TaludesEditorWindow::~TaludesEditorWindow()
{
    delete ui;
}

QString TaludesEditorWindow::baseProjectsPath() const
{
    const QString homePath = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    return homePath + "/InGePlusProyectos";
}

void TaludesEditorWindow::crearTabPorDefecto()
{
    m_docCounterSuelo = 1;
    addNewSueloTab();
    m_docCounterSuelo = 2;
}

void TaludesEditorWindow::addNewSueloTab()
{
    const QString title = QString("Talud Suelo %1").arg(m_docCounterSuelo++);
    auto *w = new TaludSueloWindow(ui->tabWidgetTaludes);
    addNewTab(w, title);
}

void TaludesEditorWindow::addNewRocaTab()
{
    const QString title = QString("Talud Roca %1").arg(m_docCounterRoca++);
    auto *w = new TaludRocaWindow(ui->tabWidgetTaludes);
    addNewTab(w, title);
}

void TaludesEditorWindow::addNewTab(TaludFormBase *w, const QString &title)
{
    if (!w) return;

    const QString tabTitle = title.trimmed().isEmpty() ? tr("Talud") : title.trimmed();

    w->setProperty("_tabBaseTitle", tabTitle);
    w->setProperty("taludFilePath", baseProjectsPath());

    hookTaludSignals(w);

    const int idx = ui->tabWidgetTaludes->addTab(w, tabTitle);
    ui->tabWidgetTaludes->setCurrentIndex(idx);

    updateTabTitleFor(w);
    updateActionsForCurrent();
    updateEditorTitle();
}

void TaludesEditorWindow::onNuevoTabSuelo()
{
    addNewSueloTab();
}

void TaludesEditorWindow::onNuevoTabRoca()
{
    addNewRocaTab();
}

TaludFormBase* TaludesEditorWindow::currentTalud() const
{
    return qobject_cast<TaludFormBase*>(ui->tabWidgetTaludes->currentWidget());
}

void TaludesEditorWindow::hookTaludSignals(TaludFormBase *w)
{
    if (!w) return;

    if (m_btnAutoSave)
        w->setAutoSaveEnabled(m_btnAutoSave->isChecked());

    connect(w, &TaludFormBase::displayNameChanged, this, [this, w](){
        updateTabTitleFor(w);
    });

    connect(w, &TaludFormBase::dirtyChanged, this, [this, w](bool){
        updateTabTitleFor(w);
        updateActionsForCurrent();
        updateEditorTitle();
    });
}

void TaludesEditorWindow::updateTabTitleFor(TaludFormBase *w)
{
    if (!w) return;
    const int idx = ui->tabWidgetTaludes->indexOf(w);
    if (idx < 0) return;

    QString base;
    QString fp = w->currentFilePath();
    if (fp.isEmpty())
        fp = w->property("taludFilePath").toString();

    if (!fp.isEmpty() && QFileInfo(fp).isFile()) {
        base = QFileInfo(fp).completeBaseName();

        if (base.endsWith(".taludsuelo", Qt::CaseInsensitive))
            base.chop(QString(".taludsuelo").size());
        else if (base.endsWith(".taludroca", Qt::CaseInsensitive))
            base.chop(QString(".taludroca").size());
    } else {
        base = w->displayName().trimmed();
    }

    if (base.isEmpty())
        base = w->property("_tabBaseTitle").toString().trimmed();
    if (base.isEmpty())
        base = tr("Talud");

    if (w->property("_externalConflict").toBool())
        base += " ⚠";

    if (w->isDirty())
        base += " *";

    ui->tabWidgetTaludes->setTabText(idx, base);
}

bool TaludesEditorWindow::isFileAlreadyOpen(const QString &filePath, int *outIndex) const
{
    const QString absRealWanted = absPathPreserveCase(filePath);
    const QString keyWanted     = openKeyForAbs(absRealWanted);

    for (int i = 0; i < ui->tabWidgetTaludes->count(); ++i) {
        auto *tw = qobject_cast<TaludFormBase*>(ui->tabWidgetTaludes->widget(i));
        if (!tw) continue;

        QString k = tw->property("_openKey").toString();
        if (k.isEmpty()) {
            QString fp = tw->currentFilePath();
            if (fp.isEmpty()) fp = tw->property("taludFilePath").toString();
            if (!fp.isEmpty())
                k = openKeyForAbs(absPathPreserveCase(fp));
        }

        if (!k.isEmpty() && k == keyWanted) {
            if (outIndex) *outIndex = i;
            return true;
        }
    }
    return false;
}

QString TaludesEditorWindow::detectFormTypeFromJson(const QString& filePath) const
{
    QFile f(filePath);
    if (!f.open(QIODevice::ReadOnly))
        return {};

    QJsonParseError pe{};
    const QJsonDocument jd = QJsonDocument::fromJson(f.readAll(), &pe);
    if (pe.error != QJsonParseError::NoError || !jd.isObject())
        return {};

    return jd.object().value("form_type").toString().trimmed().toLower();
}

TaludFormBase* TaludesEditorWindow::createTaludFromFileType(const QString& filePath) const
{
    const QString type = detectFormTypeFromJson(filePath);

    if (type == "talud_suelo")
        return new TaludSueloWindow(ui->tabWidgetTaludes);

    if (type == "talud_roca")
        return new TaludRocaWindow(ui->tabWidgetTaludes);

    return nullptr;
}

void TaludesEditorWindow::openFile(const QString &filePath)
{
    if (filePath.trimmed().isEmpty())
        return;

    const QString absReal = absPathPreserveCase(filePath);
    const QString key     = openKeyForAbs(absReal);

    int existingIdx = -1;
    if (isFileAlreadyOpen(absReal, &existingIdx)) {
        ui->tabWidgetTaludes->setCurrentIndex(existingIdx);
        return;
    }

    // reusar tab único vacío y limpio
    if (ui->tabWidgetTaludes->count() == 1) {
        if (auto *tw = currentTalud()) {
            const QString ctxProp = tw->property("taludFilePath").toString();
            const bool noFileYet =
                tw->currentFilePath().isEmpty() &&
                (ctxProp.isEmpty() || QFileInfo(ctxProp).isDir());

            if (noFileYet && !tw->isDirty()) {
                tw->setProperty("taludFilePath", absReal);

                if (!tw->cargarDesdeArchivo(absReal)) {
                    tw->setProperty("taludFilePath", QString());
                    return;
                }

                watchTaludFile(tw, absReal);

                if (auto ctx = AppContext::instance())
                    ctx->registerOpenFile(key);

                updateTabTitleFor(tw);
                updateActionsForCurrent();
                updateEditorTitle();
                return;
            }
        }
    }

    TaludFormBase *w = createTaludFromFileType(absReal);
    if (!w) {
        QMessageBox::warning(this, tr("Abrir"),
                             tr("No se pudo identificar el tipo de ficha de talud.\n"
                                "Verifica que el JSON tenga 'form_type' válido."));
        return;
    }

    w->setProperty("taludFilePath", absReal);
    hookTaludSignals(w);

    if (!w->cargarDesdeArchivo(absReal)) {
        w->deleteLater();
        return;
    }

    watchTaludFile(w, absReal);

    const int idx = ui->tabWidgetTaludes->addTab(w, QFileInfo(absReal).completeBaseName());
    ui->tabWidgetTaludes->setCurrentIndex(idx);

    if (auto ctx = AppContext::instance())
        ctx->registerOpenFile(key);

    updateTabTitleFor(w);
    updateActionsForCurrent();
    updateEditorTitle();
}

void TaludesEditorWindow::onAbrir()
{
    const QString basePath = baseProjectsPath();
    QDir().mkpath(basePath);

    const QStringList files = QFileDialog::getOpenFileNames(
        this,
        tr("Abrir fichas de talud"),
        basePath,
        tr("Fichas de Talud (*.taludsuelo.json *.taludroca.json *.json)")
        );

    for (const QString& fp : files)
        openFile(fp);
}

void TaludesEditorWindow::onGuardar()
{
    auto *w = currentTalud();
    if (!w) return;

    if (!w->isDirty()) {
        updateActionsForCurrent();
        return;
    }

    if (!w->guardar())
        return;

    const QString p = w->currentFilePath();
    if (!p.isEmpty())
        w->setProperty("taludFilePath", QFileInfo(p).absoluteFilePath());

    refreshLastMTime(w);
    updateTabTitleFor(w);
    updateActionsForCurrent();
    updateEditorTitle();
}

void TaludesEditorWindow::onGuardarComo()
{
    auto *w = currentTalud();
    if (!w) return;

    if (!w->guardarComo())
        return;

    const QString p = w->currentFilePath();
    if (!p.isEmpty())
        w->setProperty("taludFilePath", QFileInfo(p).absoluteFilePath());

    updateTabTitleFor(w);
    updateActionsForCurrent();
    updateEditorTitle();

    refreshLastMTime(w);

    const QString newAbs = absPathPreserveCase(w->currentFilePath());
    if (!newAbs.isEmpty()) {
        unwatchTaludFile(w);
        watchTaludFile(w, newAbs);
    }
}

void TaludesEditorWindow::onTabCloseRequested(int index)
{
    auto *tw = qobject_cast<TaludFormBase*>(ui->tabWidgetTaludes->widget(index));
    if (!tw) return;

    QString key = tw->property("_openKey").toString();

    if (key.isEmpty()) {
        QString p = tw->currentFilePath();
        if (p.isEmpty()) p = tw->property("taludFilePath").toString();
        key = openKeyForAbs(absPathPreserveCase(p));
    }

    if (!tw->close())
        return;

    if (!key.isEmpty()) {
        if (auto ctx = AppContext::instance())
            ctx->unregisterOpenFile(key);
    }

    unwatchTaludFile(tw);

    ui->tabWidgetTaludes->removeTab(index);
    tw->deleteLater();

    if (ui->tabWidgetTaludes->count() == 0)
        crearTabPorDefecto();

    updateActionsForCurrent();
    updateEditorTitle();
}

void TaludesEditorWindow::closeEvent(QCloseEvent *event)
{
    if (anyDirtyTabs()) {
        const auto r = QMessageBox::question(
            this,
            tr("Cerrar editor"),
            tr("Hay fichas de talud con cambios sin guardar.\n¿Deseas cerrar igualmente?"),
            QMessageBox::Yes | QMessageBox::No,
            QMessageBox::No
            );

        if (r != QMessageBox::Yes) {
            event->ignore();
            return;
        }
    }

    QMainWindow::closeEvent(event);
}

void TaludesEditorWindow::onVolver()
{
    if (m_home) {
        m_home->showMaximized();
        m_home->raise();
        m_home->activateWindow();
        this->hide();
    } else {
        this->hide();
    }
}

void TaludesEditorWindow::onExportExcel()
{
    auto *w = currentTalud();
    if (!w) {
        QMessageBox::warning(this, tr("Exportar"), tr("No hay ninguna ficha de talud abierta."));
        return;
    }

    QMessageBox::information(
        this,
        tr("Exportar Excel"),
        tr("La exportación Excel de Talud todavía no está conectada.\n"
           "Primero armemos el flujo del editor y luego enchufamos el exporter.")
        );
}

void TaludesEditorWindow::onCurrentTabChanged(int)
{
    updateActionsForCurrent();
}

void TaludesEditorWindow::onAutoSaveToggled(bool enabled)
{
    for (int i = 0; i < ui->tabWidgetTaludes->count(); ++i) {
        auto *tw = qobject_cast<TaludFormBase*>(ui->tabWidgetTaludes->widget(i));
        if (tw) tw->setAutoSaveEnabled(enabled);
    }
}

void TaludesEditorWindow::updateActionsForCurrent()
{
    auto *tw = currentTalud();
    const bool has = (tw != nullptr);

    if (m_btnGuardar)
        m_btnGuardar->setEnabled(has && tw->isDirty());

    if (m_btnGuardarComo)
        m_btnGuardarComo->setEnabled(has);

    if (m_btnExport)
        m_btnExport->setEnabled(has);
}

bool TaludesEditorWindow::anyDirtyTabs() const
{
    for (int i = 0; i < ui->tabWidgetTaludes->count(); ++i) {
        auto *tw = qobject_cast<TaludFormBase*>(ui->tabWidgetTaludes->widget(i));
        if (tw && tw->isDirty())
            return true;
    }
    return false;
}

void TaludesEditorWindow::updateEditorTitle()
{
    const bool dirty = anyDirtyTabs();
    setWindowTitle(dirty ? (m_baseTitle + " *") : m_baseTitle);
}

void TaludesEditorWindow::onGpsToggled(bool on)
{
    m_gpsOn = on;
    setGpsButtonVisual(on);

    if (m_home && m_home->ubicacionWin()) {
        m_home->ubicacionWin()->setGpsAutoShare(on);
        return;
    }

    QSettings s;
    s.setValue("gps/autoShare", on);
    s.setValue("gps_enabled", on);

    if (on) GpsManager::instance()->start();
    else    GpsManager::instance()->stop();
}

void TaludesEditorWindow::showEvent(QShowEvent *event)
{
    QMainWindow::showEvent(event);

    if (ui->tabWidgetTaludes->count() == 0)
        crearTabPorDefecto();

    ensureGpsLink();
}

void TaludesEditorWindow::ensureGpsLink()
{
    if (m_gpsLinked || !m_btnGps) return;
    m_gpsLinked = true;

    const bool on = GpsManager::instance()->isActive();

    {
        QSignalBlocker b(m_btnGps);
        m_btnGps->setChecked(on);
    }

    if (m_home && m_home->ubicacionWin()) {
        connect(m_home->ubicacionWin(), &UbicacionWindow::gpsAutoShareChanged,
                this, [this](bool on){
                    if (!m_btnGps) return;
                    QSignalBlocker b(m_btnGps);
                    m_btnGps->setChecked(on);
                    m_gpsOn = on;
                    setGpsButtonVisual(on);
                });
    }

    m_gpsOn = on;
    setGpsButtonVisual(on);
}

void TaludesEditorWindow::setGpsButtonVisual(bool on)
{
    if (!m_btnGps) return;

    const QSize iconSz = m_btnGps->iconSize().isValid()
                             ? m_btnGps->iconSize()
                             : QSize(26, 26);

    if (m_gpsBtnMovie)
        m_gpsBtnMovie->setScaledSize(iconSz);

    if (on) {
        m_btnGps->setText("GPS");

        if (m_gpsBtnMovie && m_gpsBtnMovie->isValid()) {
            if (m_gpsBtnMovie->state() != QMovie::Running)
                m_gpsBtnMovie->start();

            QPixmap pm = m_gpsBtnMovie->currentPixmap();
            if (!pm.isNull()) {
                pm = pm.scaled(iconSz, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
                m_btnGps->setIcon(QIcon(pm));
            }
        }
    } else {
        if (m_gpsBtnMovie) m_gpsBtnMovie->stop();
        m_btnGps->setText("GPS");

        const int inner = qRound(iconSz.width() * 0.40);

        QPixmap src = m_gpsBtnInactiveIcon.pixmap(64, 64);
        QPixmap scaled = src.scaled(inner, inner, Qt::KeepAspectRatio, Qt::SmoothTransformation);

        QPixmap canvas(iconSz);
        canvas.fill(Qt::transparent);

        QPainter p(&canvas);
        p.setRenderHint(QPainter::SmoothPixmapTransform, true);
        const int x = (iconSz.width()  - scaled.width())  / 2;
        const int y = (iconSz.height() - scaled.height()) / 2;
        p.drawPixmap(x, y, scaled);

        m_btnGps->setIcon(QIcon(canvas));
    }

    m_btnGps->update();
}

void TaludesEditorWindow::ensureWatcher()
{
    if (m_fsWatcher) return;
    m_fsWatcher = new QFileSystemWatcher(this);
    connect(m_fsWatcher, &QFileSystemWatcher::fileChanged,
            this, &TaludesEditorWindow::onWatchedFileChanged);
}

void TaludesEditorWindow::refreshLastMTime(TaludFormBase* w)
{
    if (!w) return;

    QString p = w->property("_openPath").toString();
    if (p.isEmpty()) p = w->currentFilePath();
    if (p.isEmpty()) return;

    w->setProperty("_lastMtime", QFileInfo(p).lastModified());
    w->setProperty("_externalConflict", false);
}

void TaludesEditorWindow::watchTaludFile(TaludFormBase* w, const QString& absReal)
{
    if (!w || absReal.isEmpty()) return;

    ensureWatcher();

    const QString key = openKeyForAbs(absReal);
    w->setProperty("_openKey", key);
    w->setProperty("_openPath", absReal);

    m_tabByKey[key] = w;

    if (!m_fsWatcher->files().contains(absReal))
        m_fsWatcher->addPath(absReal);

    refreshLastMTime(w);
}

void TaludesEditorWindow::unwatchTaludFile(TaludFormBase* w)
{
    if (!w || !m_fsWatcher) return;

    const QString key  = w->property("_openKey").toString();
    const QString path = w->property("_openPath").toString();

    if (!path.isEmpty())
        m_fsWatcher->removePath(path);

    if (!key.isEmpty())
        m_tabByKey.remove(key);

    w->setProperty("_openKey", QString());
    w->setProperty("_openPath", QString());
}

void TaludesEditorWindow::onWatchedFileChanged(const QString& path)
{
    const QString absReal = absPathPreserveCase(path);
    const QString key     = openKeyForAbs(absReal);

    TaludFormBase* w = m_tabByKey.value(key, nullptr);
    if (!w) return;

    if (QFileInfo::exists(absReal) && m_fsWatcher && !m_fsWatcher->files().contains(absReal))
        m_fsWatcher->addPath(absReal);

    const QDateTime now  = QFileInfo(absReal).lastModified();
    const QDateTime last = w->property("_lastMtime").toDateTime();

    if (now.isValid() && last.isValid() && now <= last.addMSecs(80))
        return;

    if (!w->isDirty()) {
        if (w->cargarDesdeArchivo(absReal)) {
            refreshLastMTime(w);
            updateTabTitleFor(w);
            updateEditorTitle();
        }
        return;
    }

    if (!w->property("_externalConflict").toBool()) {
        w->setProperty("_externalConflict", true);

        QMessageBox msg(this);
        msg.setIcon(QMessageBox::Warning);
        msg.setWindowTitle(tr("Conflicto detectado"));
        msg.setText(tr("El archivo fue modificado fuera de la aplicación."));
        msg.setInformativeText(tr("Esta ficha tiene cambios sin guardar.\n¿Qué deseas hacer?"));

        auto* bReload = msg.addButton(tr("Recargar (pierdo mis cambios)"), QMessageBox::DestructiveRole);
        auto* bKeep   = msg.addButton(tr("Mantener mis cambios"), QMessageBox::AcceptRole);
        auto* bSaveAs = msg.addButton(tr("Guardar como…"), QMessageBox::ActionRole);
        msg.addButton(QMessageBox::Cancel);

        msg.exec();
        auto* clicked = msg.clickedButton();

        if (clicked == bReload) {
            w->cargarDesdeArchivo(absReal);
            refreshLastMTime(w);
        } else if (clicked == bSaveAs) {
            if (w->guardarComo()) {
                const QString newPath = absPathPreserveCase(w->currentFilePath());
                if (!newPath.isEmpty() && openKeyForAbs(newPath) != key) {
                    unwatchTaludFile(w);
                    watchTaludFile(w, newPath);
                } else {
                    refreshLastMTime(w);
                }
            }
        } else if (clicked == bKeep) {
            // mantener cambios
        } else {
            // cancel
        }

        updateTabTitleFor(w);
        updateEditorTitle();
    }
}
