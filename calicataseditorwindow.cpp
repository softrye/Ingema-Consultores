#include "calicataexcelexporter.h"
#include "calicataseditorwindow.h"
#include "ui_calicataseditorwindow.h"
#include "guardarexportdialog.h"
#include "exportexcelbatchdialog.h"
#include "gpsmanager.h"
#include "ubicacionwindow.h"
#include "calicatawindow.h"
#include "guardarcalicatadialog.h"
#include "homewindow.h"
#include "editablemeta.h"
#include "appcontext.h"
#include "calicatamapdialog.h"

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
#include <QMessageBox>
#include <QMenu>
#include <QAction>
#include <QApplication>
#include <QSettings>
#include <QSignalBlocker>
#include <QShowEvent>
#include <QMovie>
#include <QIcon>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonParseError>
#include <QFile>
#include <QStyle>


static QString calicatasRootDirForJson(const QString& jsonPath)
{
    QDir d = QFileInfo(jsonPath).absoluteDir(); // .../Calicatas/Edit
    if (d.dirName().compare("Edit", Qt::CaseInsensitive) == 0)
        d.cdUp(); // .../Calicatas
    return d.absolutePath();
}

static QString suggestedExcelDirForJson(const QString& jsonPath)
{
    QDir d(calicatasRootDirForJson(jsonPath));
    d.mkpath("EXCEL");
    return d.filePath("EXCEL");
}

static QString suggestedExcelFileNameForJson(const QString& jsonPath)
{
    QString base = QFileInfo(jsonPath).completeBaseName();
    if (base.endsWith(".calicata", Qt::CaseInsensitive))
        base.chop(QString(".calicata").size());
    return base + ".xlsx";
}


static const char* kEditableMetaFile = ".ingep_editable.json";

struct EditableMetaInfo {
    QString editableRootAbs;     // carpeta donde está el .ingep_editable.json
    QString excelTitle;          // excel_title
    QString logoMtcRelOrAbs;     // logo mtc (rel o abs)
    QString logoProyectoRelOrAbs;// logo proyecto (rel o abs)
};

static QString cleanPath2(QString p)
{
    p = p.trimmed();
    if (p.isEmpty()) return {};
    return QDir::cleanPath(QDir::fromNativeSeparators(p));
}

static EditableMetaInfo readEditableMetaUp(const QString& contextFileOrDir)
{
    EditableMetaInfo out;

    if (contextFileOrDir.trimmed().isEmpty())
        return out;

    QFileInfo fi(contextFileOrDir);
    QString dirPath = fi.isDir() ? fi.absoluteFilePath() : fi.absolutePath();
    dirPath = cleanPath2(dirPath);

    const QString baseProjects =
        cleanPath2(QStandardPaths::writableLocation(QStandardPaths::HomeLocation) + "/InGePlusProyectos");

    QDir d(dirPath);
    while (d.exists()) {
        const QString metaPath = d.absoluteFilePath(kEditableMetaFile);
        if (QFileInfo::exists(metaPath)) {
            out.editableRootAbs = cleanPath2(d.absolutePath());

            QFile f(metaPath);
            if (!f.open(QIODevice::ReadOnly))
                return out;

            QJsonParseError pe{};
            const QJsonDocument jd = QJsonDocument::fromJson(f.readAll(), &pe);
            if (pe.error != QJsonParseError::NoError || !jd.isObject())
                return out;

            const QJsonObject o = jd.object();

            out.excelTitle = o.value("excel_title").toString().trimmed();

            auto pickFirst = [&](const QStringList& keys)->QString {
                for (const QString& k : keys) {
                    const QString v = o.value(k).toString().trimmed();
                    if (!v.isEmpty()) return v;
                }
                return {};
            };

            // ✅ soporta varias llaves posibles (por si tu meta usa otro nombre)
            out.logoMtcRelOrAbs = pickFirst({
                "logo_mtc_path", "logo_mtc", "mtc_logo_path", "mtc_logo",
                "logoMtcPath", "logoMtc", "logo_mtc_rel"
            });

            out.logoProyectoRelOrAbs = pickFirst({
                "logo_proyecto_path", "logo_proyecto", "proyecto_logo_path", "proyecto_logo",
                "logoProyectoPath", "logoProyecto", "logo_proyecto_rel"
            });

            out.logoMtcRelOrAbs      = cleanPath2(out.logoMtcRelOrAbs);
            out.logoProyectoRelOrAbs = cleanPath2(out.logoProyectoRelOrAbs);

            return out;
        }

        const QString cur = cleanPath2(d.absolutePath());
        if (!baseProjects.isEmpty() && cur == baseProjects)
            break;

        if (!d.cdUp())
            break;
    }

    return out;
}


static QString pathKey(const QString& path)
{
    QFileInfo fi(path);
    QString abs = fi.canonicalFilePath();
    if (abs.isEmpty()) abs = fi.absoluteFilePath();

    abs = QDir::cleanPath(QDir::fromNativeSeparators(abs));

#ifdef Q_OS_WIN
    abs = abs.toLower(); // clave para evitar duplicados por mayúsculas/minúsculas
#endif
    return abs;
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
            return QDir::cleanPath(dir.absoluteFilePath(e.fileName())); // devuelve con el case real
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

static QIcon makeToolbarIcon(const QIcon& base, const QSize& size, const QColor& color)
{
    if (base.isNull())
        return QIcon();

    QPixmap src = base.pixmap(size);
    if (src.isNull())
        return QIcon();

    QImage img = src.toImage().convertToFormat(QImage::Format_ARGB32_Premultiplied);

    QPainter p(&img);
    p.setCompositionMode(QPainter::CompositionMode_SourceIn);
    p.fillRect(img.rect(), color);
    p.end();

    return QIcon(QPixmap::fromImage(img));
}

CalicatasEditorWindow::CalicatasEditorWindow(QWidget *parent)
    : QMainWindow(parent)
    , ui(new Ui::CalicatasEditorWindow)
{
    ui->setupUi(this);

    setWindowIcon(QApplication::windowIcon());

    m_baseTitle = tr("Editor de Calicatas");
    updateEditorTitle();

    // --- Tabs ---
    ui->tabWidgetCalicatas->clear();
    ui->tabWidgetCalicatas->setDocumentMode(true);
    ui->tabWidgetCalicatas->setMovable(true);
    ui->tabWidgetCalicatas->setTabsClosable(true);
    ui->tabWidgetCalicatas->tabBar()->setExpanding(false);

    connect(ui->tabWidgetCalicatas, &QTabWidget::tabCloseRequested,
            this, &CalicatasEditorWindow::onTabCloseRequested);

    connect(ui->tabWidgetCalicatas, &QTabWidget::currentChanged,
            this, &CalicatasEditorWindow::onCurrentTabChanged);

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

    auto *btnPlus    = mkBtn("+");

    QIcon undoBase = QIcon::fromTheme("edit-undo");
    if (undoBase.isNull())
        undoBase = style()->standardIcon(QStyle::SP_ArrowBack);

    QIcon redoBase = QIcon::fromTheme("edit-redo");
    if (redoBase.isNull())
        redoBase = style()->standardIcon(QStyle::SP_ArrowForward);

    const QSize undoRedoIconSize(18, 18);
    const QColor undoRedoColor("#F4F7FB");

    QIcon undoIcon = makeToolbarIcon(undoBase, undoRedoIconSize, undoRedoColor);
    QIcon redoIcon = makeToolbarIcon(redoBase, undoRedoIconSize, undoRedoColor);

    m_btnUndo = mkBtn("Deshacer");
    m_btnUndo->setIcon(undoIcon);
    m_btnUndo->setIconSize(undoRedoIconSize);
    m_btnUndo->setToolButtonStyle(Qt::ToolButtonTextBesideIcon);
    m_btnUndo->setToolTip(tr("Deshacer cambios de la ficha (Ctrl+Z)"));

    m_btnRedo = mkBtn("Rehacer");
    m_btnRedo->setIcon(redoIcon);
    m_btnRedo->setIconSize(undoRedoIconSize);
    m_btnRedo->setToolButtonStyle(Qt::ToolButtonTextBesideIcon);
    m_btnRedo->setToolTip(tr("Rehacer cambios de la ficha (Ctrl+Y / Ctrl+Shift+Z)"));

    m_btnUndo->setObjectName("tbUndo");
    m_btnRedo->setObjectName("tbRedo");

    auto *btnAbrir   = mkBtn("Abrir");
    m_btnGuardar     = mkBtn("Guardar");
    m_btnGuardarComo = mkBtn("Guardar como…");

    m_btnAutoSave = mkBtn("Auto-guardar");
    m_btnAutoSave->setCheckable(true);
    m_btnAutoSave->setChecked(false);
    m_btnAutoSave->setToolTip(tr("Auto-guardar cada ~20s (solo si la ficha ya tiene archivo)"));

    // ✅ Crear GPS AQUÍ (antes NO existe)
    m_btnGps = mkBtn("GPS");
    m_btnGps->setCheckable(true);
    m_btnGps->setToolTip(tr("Activar/desactivar GPS automático"));
    m_btnGps->setIconSize(QSize(18, 18)); // <- ON se verá más grande
    m_btnGps->setToolButtonStyle(Qt::ToolButtonTextBesideIcon);

    m_gpsMenu = new QMenu(m_btnGps);

    m_actGpsToggle = m_gpsMenu->addAction(tr("Activar GPS automático"));
    m_actGpsToggle->setCheckable(true);

    m_actShowMap = m_gpsMenu->addAction(tr("Mostrar mapa interactivo"));

    m_btnGps->setMenu(m_gpsMenu);
    m_btnGps->setPopupMode(QToolButton::MenuButtonPopup);

    connect(m_actGpsToggle, &QAction::triggered, this, [this](bool on){
        if (!m_btnGps) return;
        m_btnGps->setChecked(on); // esto dispara onGpsToggled()
    });

    connect(m_actShowMap, &QAction::triggered,
            this, &CalicatasEditorWindow::onShowInteractiveMap);

    auto *btnSalir = mkBtn("Salir");
    m_btnExport    = mkBtn("Exportar Excel");

    btnPlus->setToolTip(tr("Nueva calicata"));

    lay->addWidget(btnPlus);
    lay->addWidget(m_btnUndo);
    lay->addWidget(m_btnRedo);
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


    ui->tabWidgetCalicatas->setCornerWidget(corner, Qt::TopRightCorner);

    // --- Conexiones ---
    connect(btnPlus, &QToolButton::clicked, this, &CalicatasEditorWindow::onNuevoTab);
    connect(m_btnUndo, &QToolButton::clicked, this, &CalicatasEditorWindow::onUndoCurrent);
    connect(m_btnRedo, &QToolButton::clicked, this, &CalicatasEditorWindow::onRedoCurrent);
    connect(btnAbrir, &QToolButton::clicked, this, &CalicatasEditorWindow::onAbrir);
    connect(m_btnGuardar, &QToolButton::clicked, this, &CalicatasEditorWindow::onGuardar);
    connect(m_btnGuardarComo, &QToolButton::clicked, this, &CalicatasEditorWindow::onGuardarComo);
    connect(m_btnAutoSave, &QToolButton::toggled, this, &CalicatasEditorWindow::onAutoSaveToggled);
    connect(btnSalir, &QToolButton::clicked, this, &CalicatasEditorWindow::onVolver);

    auto *actUndo = new QAction(this);
    actUndo->setShortcut(QKeySequence::Undo); // Ctrl+Z
    actUndo->setShortcutContext(Qt::ApplicationShortcut);
    addAction(actUndo);
    connect(actUndo, &QAction::triggered, this, &CalicatasEditorWindow::onUndoCurrent);

    auto *actRedoY = new QAction(this);
    actRedoY->setShortcut(QKeySequence(QStringLiteral("Ctrl+Y")));
    actRedoY->setShortcutContext(Qt::ApplicationShortcut);
    addAction(actRedoY);
    connect(actRedoY, &QAction::triggered, this, &CalicatasEditorWindow::onRedoCurrent);

    auto *actRedoShiftZ = new QAction(this);
    actRedoShiftZ->setShortcut(QKeySequence(QStringLiteral("Ctrl+Shift+Z")));
    actRedoShiftZ->setShortcutContext(Qt::ApplicationShortcut);
    addAction(actRedoShiftZ);
    connect(actRedoShiftZ, &QAction::triggered, this, &CalicatasEditorWindow::onRedoCurrent);


    // Menú export
    auto *menuExport = new QMenu(m_btnExport);
    auto *aExportOne  = menuExport->addAction(tr("Exportar Excel (esta ficha)"));
    auto *aExportMany = menuExport->addAction(tr("Exportar Excel (masivo)"));
    connect(aExportOne,  &QAction::triggered, this, &CalicatasEditorWindow::onExportExcel);
    connect(aExportMany, &QAction::triggered, this, &CalicatasEditorWindow::onExportExcelBatch);

    m_btnExport->setMenu(menuExport);
    m_btnExport->setPopupMode(QToolButton::MenuButtonPopup);
    connect(m_btnExport, &QToolButton::clicked, m_btnExport, &QToolButton::showMenu);

    // ✅ GPS: conectar toggle del botón UNA sola vez
    connect(m_btnGps, &QToolButton::toggled, this, &CalicatasEditorWindow::onGpsToggled);

    // ✅ Estado visual inicial (solo UI)
    {
        QSettings s;
        const bool on = s.value("gps/autoShare", false).toBool();

        QSignalBlocker b1(m_btnGps);
        m_btnGps->setChecked(on);

        if (m_actGpsToggle) {
            QSignalBlocker b2(m_actGpsToggle);
            m_actGpsToggle->setChecked(on);
        }

        if (m_actShowMap)
            m_actShowMap->setEnabled(!on);

        m_gpsOn = on;
    }

    m_gpsBtnInactiveIcon = QIcon(":/icons/images/GPS_Inactivo.png");

    // ✅ Crear movie UNA sola vez
    if (!m_gpsBtnMovie) {
        m_gpsBtnMovie = new QMovie(":/icons/images/GPS_Activo.gif", QByteArray(), this);
        m_gpsBtnMovie->setCacheMode(QMovie::CacheAll);

        // El movie debe “producir” frames del tamaño del icono del botón
        m_gpsBtnMovie->setScaledSize(m_btnGps->iconSize());

        connect(m_gpsBtnMovie, &QMovie::frameChanged, this, [this](int){
            if (!m_btnGps || !m_btnGps->isChecked() || !m_gpsBtnMovie) return;

            QPixmap pm = m_gpsBtnMovie->currentPixmap();
            if (pm.isNull()) return;

            const QSize iconSz = m_btnGps->iconSize();

            // ✅ ON: llenar TODO el cuadro (0 padding)
            pm = pm.scaled(iconSz, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
            m_btnGps->setIcon(QIcon(pm));
            m_btnGps->update();
        });
    }

    this->setStyleSheet(R"QSS(
/* =========================================================
   CalicatasEditorWindow — Look & Feel InGe+
   (solo afecta editor + tabbar + corner buttons)
   ========================================================= */

QMainWindow#CalicatasEditorWindow,
QMainWindow#CalicatasEditorWindow QWidget#centralwidget {
    background-color: #041823; /* más oscuro que CalicataWindow */
}

/* Pane del tabwidget (borde suave tipo “browser”) */
QMainWindow#CalicatasEditorWindow QTabWidget::pane {
    border: 1px solid rgba(255,255,255,18);
    border-radius: 12px;

    background: rgba(0,0,0,16);  /* marco sutil */
    padding: 10px;               /* separa el contenido del borde */
    top: -1px;
}


/* Tab bar */
QMainWindow#CalicatasEditorWindow QTabBar {
    background: transparent;
}

QMainWindow#CalicatasEditorWindow QTabBar::tab {
    background: rgba(255,255,255,10);
    color: rgba(255,255,255,230);

    border: 1px solid rgba(255,255,255,22);
    border-bottom: none;

    border-top-left-radius: 10px;
    border-top-right-radius: 10px;

    padding: 6px 10px;
    margin-right: 6px;
}

QMainWindow#CalicatasEditorWindow QTabBar::tab:hover {
    background: rgba(255,255,255,16);
}

QMainWindow#CalicatasEditorWindow QTabBar::tab:selected {
    background: #0087AE;
    border: 1px solid rgba(255,255,255,26);
    border-bottom: none;
    color: #FFFFFF;
}

/* Corner bar (tus botones) */
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

/* --- Exportar Excel: split button (MenuButtonPopup) --- */
QWidget#editorCornerBar QToolButton#tbExport {
    padding-right: 28px; /* deja espacio real para la flecha */
}

/* La zona derecha (donde vive la flecha) */
QWidget#editorCornerBar QToolButton#tbExport::menu-button {
    subcontrol-origin: padding;
    subcontrol-position: right center;

    width: 22px;
    background: rgba(255,255,255,10);
    border-left: 1px solid rgba(255,255,255,28);

    border-top-right-radius: 10px;
    border-bottom-right-radius: 10px;
}

/* --- GPS: split button --- */
QWidget#editorCornerBar QToolButton#tbGps {
    padding-right: 28px;
}

QWidget#editorCornerBar QToolButton#tbGps::menu-button {
    subcontrol-origin: padding;
    subcontrol-position: right center;

    width: 22px;
    background: rgba(255,255,255,10);
    border-left: 1px solid rgba(255,255,255,28);

    border-top-right-radius: 10px;
    border-bottom-right-radius: 10px;
}

QWidget#editorCornerBar QToolButton#tbGps::menu-button:hover {
    background: rgba(255,255,255,18);
}

QWidget#editorCornerBar QToolButton#tbGps::menu-button:pressed {
    background: rgba(0,0,0,12);
}

QWidget#editorCornerBar QToolButton#tbGps::menu-indicator {
    image: url(:/icons/images/chevron_down_white.png);
    subcontrol-origin: padding;
    subcontrol-position: right 8px center;
    width: 10px;
    height: 10px;
}

QWidget#editorCornerBar QToolButton#tbUndo,
QWidget#editorCornerBar QToolButton#tbRedo {
    background: rgba(255,255,255,16);
    border: 1px solid rgba(255,255,255,46);
    padding: 6px 12px;
    font-weight: 600;
    min-width: 86px;
}

QWidget#editorCornerBar QToolButton#tbUndo:hover,
QWidget#editorCornerBar QToolButton#tbRedo:hover {
    background: rgba(255,255,255,24);
}

/* Hover/pressed SOLO de la zona derecha */
QWidget#editorCornerBar QToolButton#tbExport::menu-button:hover {
    background: rgba(255,255,255,18);
}
QWidget#editorCornerBar QToolButton#tbExport::menu-button:pressed {
    background: rgba(0,0,0,12);
}

/* Flecha (menu indicator). Opción A: forzar tamaño/posición y dejar que Qt la dibuje */
QWidget#editorCornerBar QToolButton#tbExport::menu-indicator {
    image: url(:/icons/images/chevron_down_white.png);
    subcontrol-origin: padding;
    subcontrol-position: right 8px center;
    width: 10px;
    height: 10px;
}



QWidget#editorCornerBar QToolButton:hover {
    background: rgba(255,255,255,18);
}

QWidget#editorCornerBar QToolButton:pressed {
    background: rgba(0,0,0,12);
}

/* Estados toggle (GPS / Auto-guardar) */
QWidget#editorCornerBar QToolButton:checked {
    background: rgba(111,192,74,22);
    border: 1px solid rgba(111,192,74,160);
}

/* Botón + (nuevo) como CTA naranja */
QWidget#editorCornerBar QToolButton#tbNuevo {
    background: #FDAC11;
    border: 1px solid rgba(255,255,255,45);
    color: #FFFFFF;
    font-weight: bold;
}
QWidget#editorCornerBar QToolButton#tbNuevo:hover { background: #FFB52B; }
QWidget#editorCornerBar QToolButton#tbNuevo:pressed { background: #E59A00; }

/* Salir un poco más “serio” */
QWidget#editorCornerBar QToolButton#tbSalir {
    background: rgba(0,0,0,14);
    border: 1px solid rgba(255,255,255,28);
}
QWidget#editorCornerBar QToolButton#tbSalir:hover {
    background: rgba(0,0,0,22);
}

/* Deshabilitados */
QWidget#editorCornerBar QToolButton:disabled {
    background: rgba(255,255,255,6);
    border: 1px solid rgba(255,255,255,14);
    color: rgba(255,255,255,90);
}

/* Menús (Exportar Excel) */
QMainWindow#CalicatasEditorWindow QMenu {
    background-color: #005282;
    border: 1px solid rgba(255,255,255,28);
    border-radius: 12px;
    padding: 4px;
}

QMainWindow#CalicatasEditorWindow QMenu::item {
    color: #FFFFFF;
    padding: 6px 10px;
    border-radius: 8px;
}

QMainWindow#CalicatasEditorWindow QMenu::item:selected {
    background: #FFFFFF;
    color: #0F1F2A;
}

QMainWindow#CalicatasEditorWindow QMenu::separator {
    height: 1px;
    background: rgba(255,255,255,18);
    margin: 4px 6px;
}
)QSS");


    setGpsButtonVisual(m_gpsOn);


    crearTabPorDefecto();
    updateActionsForCurrent();
}



CalicatasEditorWindow::~CalicatasEditorWindow()
{
    delete ui;
}

QString CalicatasEditorWindow::baseProjectsPath() const
{
    const QString homePath = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    return homePath + "/InGePlusProyectos";
}

void CalicatasEditorWindow::crearTabPorDefecto()
{
    m_docCounter = 1;
    addNewTab("Calicata 1");
    m_docCounter = 2;
}

void CalicatasEditorWindow::hookCalicataSignals(CalicataWindow *w)
{
    if (!w) return;

    // Propaga el auto-save actual del editor
    if (m_btnAutoSave)
        w->setAutoSaveEnabled(m_btnAutoSave->isChecked());

    connect(w, &CalicataWindow::displayNameChanged, this, [this, w](){
        updateTabTitleFor(w);
    });

    // NUEVO: cuando cambia dirty -> asterisco + botones + título editor
    connect(w, &CalicataWindow::dirtyChanged, this, [this, w](bool){
        updateTabTitleFor(w);
        updateActionsForCurrent();
        updateUndoRedoForCurrent();
        updateEditorTitle();
    });

    connect(w, &CalicataWindow::undoAvailabilityChanged, this, [this, w](bool){
        if (currentCalicata() == w)
            updateUndoRedoForCurrent();
    });

    connect(w, &CalicataWindow::redoAvailabilityChanged, this, [this, w](bool){
        if (currentCalicata() == w)
            updateUndoRedoForCurrent();
    });
}

void CalicatasEditorWindow::updateTabTitleFor(CalicataWindow *w)
{
    if (!w) return;
    const int idx = ui->tabWidgetCalicatas->indexOf(w);
    if (idx < 0) return;

    QString base;

    // 1) Si hay archivo real -> usa nombre del archivo (preserva mayúsculas)
    QString fp = w->currentFilePath();
    if (fp.isEmpty())
        fp = w->property("calicataFilePath").toString();

    if (!fp.isEmpty() && QFileInfo(fp).isFile()) {
        base = QFileInfo(fp).completeBaseName();
        if (base.endsWith(".calicata", Qt::CaseInsensitive))
            base.chop(QString(".calicata").size());
    } else {
        // 2) Si no hay archivo aún -> usa displayName()
        base = w->displayName().trimmed();
    }

    if (base.isEmpty())
        base = w->property("_tabBaseTitle").toString().trimmed();
    if (base.isEmpty())
        base = tr("Calicata");

    if (w->property("_externalConflict").toBool())
        base += " ⚠";


    if (w->isDirty())
        base += " *";

    ui->tabWidgetCalicatas->setTabText(idx, base);
}


void CalicatasEditorWindow::addNewTab(const QString &title)
{
    QString tabTitle = title.trimmed();
    if (tabTitle.isEmpty())
        tabTitle = QString("Calicata %1").arg(m_docCounter++);

    auto *w = new CalicataWindow(ui->tabWidgetCalicatas);

    // Base title para tabs nuevos sin nombre/archivo
    w->setProperty("_tabBaseTitle", tabTitle);

    // Contexto base (sirve para inferencias si aún no existe archivo)
    w->setProperty("calicataFilePath", baseProjectsPath());

    hookCalicataSignals(w);

    const int idx = ui->tabWidgetCalicatas->addTab(w, tabTitle);
    ui->tabWidgetCalicatas->setCurrentIndex(idx);

    updateTabTitleFor(w);
    updateActionsForCurrent();
    updateEditorTitle();
}

void CalicatasEditorWindow::addNewTab()
{
    addNewTab(QString());
}

void CalicatasEditorWindow::onNuevoTab()
{
    addNewTab();
}

CalicataWindow* CalicatasEditorWindow::currentCalicata() const
{
    return qobject_cast<CalicataWindow*>(ui->tabWidgetCalicatas->currentWidget());
}

bool CalicatasEditorWindow::isFileAlreadyOpen(const QString &filePath, int *outIndex) const
{
    const QString absRealWanted = absPathPreserveCase(filePath);
    const QString keyWanted     = openKeyForAbs(absRealWanted);

    for (int i = 0; i < ui->tabWidgetCalicatas->count(); ++i) {
        auto *cw = qobject_cast<CalicataWindow*>(ui->tabWidgetCalicatas->widget(i));
        if (!cw) continue;

        QString k = cw->property("_openKey").toString();

        if (k.isEmpty()) {
            QString fp = cw->currentFilePath();
            if (fp.isEmpty()) fp = cw->property("calicataFilePath").toString();
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


void CalicatasEditorWindow::openFile(const QString &filePath)
{
    if (filePath.trimmed().isEmpty())
        return;

    const QString absReal = absPathPreserveCase(filePath);
    const QString key     = openKeyForAbs(absReal);   // ✅ MISMA key que usa isFileAlreadyOpen()

    int existingIdx = -1;
    if (isFileAlreadyOpen(absReal, &existingIdx)) {
        ui->tabWidgetCalicatas->setCurrentIndex(existingIdx);
        return;
    }

    auto applyFromMeta = [&](CalicataWindow* cw, const QString& fileAbsPath)
    {
        if (!cw) return;
        const EditableMetaInfo meta = readEditableMetaUp(QFileInfo(fileAbsPath).absolutePath());
        if (!meta.excelTitle.isEmpty() && cw->tituloTestificacion().trimmed().isEmpty())
            cw->setTituloTestificacion(meta.excelTitle, /*markDirty=*/false);
        if (!meta.logoMtcRelOrAbs.isEmpty() || !meta.logoProyectoRelOrAbs.isEmpty())
            cw->applyExternalEditableLogos(meta.logoMtcRelOrAbs, meta.logoProyectoRelOrAbs);
    };

    // Reusar tab único vacío y limpio
    if (ui->tabWidgetCalicatas->count() == 1) {
        if (auto *cw = currentCalicata()) {
            const QString ctxProp = cw->property("calicataFilePath").toString();
            const bool noFileYet =
                cw->currentFilePath().isEmpty() &&
                (ctxProp.isEmpty() || QFileInfo(ctxProp).isDir());

            if (noFileYet && !cw->isDirty()) {
                cw->setProperty("calicataFilePath", absReal);

                if (!cw->cargarDesdeArchivo(absReal)) {
                    cw->setProperty("calicataFilePath", QString());
                    return;
                }

                watchCalicataFile(cw, absReal);  // ✅ watcher SIEMPRE
                applyFromMeta(cw, absReal);

                if (auto ctx = AppContext::instance())
                    ctx->registerOpenFile(key);  // ✅ usa key, no path

                updateTabTitleFor(cw);
                updateActionsForCurrent();
                updateEditorTitle();
                return;
            }
        }
    }

    // Crear tab nuevo
    auto *w = new CalicataWindow(ui->tabWidgetCalicatas);
    w->setProperty("calicataFilePath", absReal);

    hookCalicataSignals(w);

    if (!w->cargarDesdeArchivo(absReal)) {
        w->deleteLater();
        return;
    }

    watchCalicataFile(w, absReal);   // ✅ watcher también aquí
    applyFromMeta(w, absReal);

    const int idx = ui->tabWidgetCalicatas->addTab(w, QFileInfo(absReal).completeBaseName());
    ui->tabWidgetCalicatas->setCurrentIndex(idx);     // ✅

    if (auto ctx = AppContext::instance())
        ctx->registerOpenFile(key);  // ✅ consistente

    updateTabTitleFor(w);
    updateActionsForCurrent();
    updateEditorTitle();
}



void CalicatasEditorWindow::onAbrir()
{
    const QString basePath = baseProjectsPath();
    QDir().mkpath(basePath);

    GuardarCalicataDialog dlg(basePath, QString(), this);
    dlg.setMode(GuardarCalicataDialog::Mode::Open);

    if (dlg.exec() != QDialog::Accepted)
        return;

    // ✅ NUEVO: abrir múltiples
    QStringList files = dlg.selectedFilePaths();

    // fallback por si no seleccionó varios y tu diálogo viejo solo devuelve 1
    if (files.isEmpty()) {
        const QString one = dlg.selectedFilePath();
        if (!one.isEmpty()) files << one;
    }

    for (const QString& fp : files)
        openFile(fp);
}


void CalicatasEditorWindow::onGuardar()
{
    auto *w = currentCalicata();
    if (!w) return;

    // Guardar solo si hay cambios
    if (!w->isDirty()) {
        updateActionsForCurrent();
        return;
    }

    w->guardar();

    const QString p = w->currentFilePath();
    if (!p.isEmpty())
        w->setProperty("calicataFilePath", QFileInfo(p).absoluteFilePath());

    refreshLastMTime(w); // ✅
    updateTabTitleFor(w);
    updateActionsForCurrent();
    updateEditorTitle();
}

void CalicatasEditorWindow::onGuardarComo()
{
    auto *w = currentCalicata();
    if (!w) return;

    w->guardarComo();

    const QString p = w->currentFilePath();
    if (!p.isEmpty())
        w->setProperty("calicataFilePath", QFileInfo(p).absoluteFilePath());

    updateTabTitleFor(w);
    updateActionsForCurrent();
    updateEditorTitle();

    refreshLastMTime(w);

    const QString newAbs = absPathPreserveCase(w->currentFilePath());
    if (!newAbs.isEmpty()) {
        unwatchCalicataFile(w);
        watchCalicataFile(w, newAbs);
    }

}

void CalicatasEditorWindow::onTabCloseRequested(int index)
{
    auto *cw = qobject_cast<CalicataWindow*>(ui->tabWidgetCalicatas->widget(index));
    if (!cw) return;

    // 1) Captura la llave ANTES de cerrar
    QString key = cw->property("_openKey").toString();
    QString p   = cw->property("_openPath").toString();

    // Fallback por si una tab vieja no tiene property
    if (key.isEmpty()) {
        QString p = cw->currentFilePath();
        if (p.isEmpty()) p = cw->property("calicataFilePath").toString();
        key = openKeyForAbs(absPathPreserveCase(p));
    }

    // 2) Si el usuario cancela cierre (por dirty), no hacemos nada
    if (!cw->close())
        return;

    // 3) Ya cerró: desregistrar en AppContext
    if (!key.isEmpty()) {
        if (auto ctx = AppContext::instance())
            ctx->unregisterOpenFile(key);
        cw->setProperty("_openAbsPath", QString());
    }
    unwatchCalicataFile(cw);

    // 4) remover tab y destruir widget
    ui->tabWidgetCalicatas->removeTab(index);
    cw->deleteLater();

    if (ui->tabWidgetCalicatas->count() == 0)
        crearTabPorDefecto();

    updateActionsForCurrent();
    updateEditorTitle();
}

void CalicatasEditorWindow::closeEvent(QCloseEvent *event)
{
    // Opcional pero recomendable: advertir si hay cambios sin guardar
    if (anyDirtyTabs()) {
        const auto r = QMessageBox::question(
            this,
            tr("Cerrar editor"),
            tr("Hay calicatas con cambios sin guardar.\n¿Deseas cerrar igualmente?"),
            QMessageBox::Yes | QMessageBox::No,
            QMessageBox::No
            );

        if (r != QMessageBox::Yes) {
            event->ignore();
            return;
        }
    }

    // ✅ comportamiento normal: se cierra/oculta la ventana, sin volver a Home
    QMainWindow::closeEvent(event);
}



void CalicatasEditorWindow::onVolver()
{
    // ✅ usa m_home (no parent())
    if (m_home) {
        m_home->showMaximized();
        m_home->raise();
        m_home->activateWindow();
        this->hide();
    } else {
        // fallback: si por alguna razón no hay home, al menos no “mueras” raro
        this->hide();
    }
}


void CalicatasEditorWindow::onExportExcel()
{
    auto *cal = currentCalicata();
    if (!cal) {
        QMessageBox::warning(this, tr("Exportar"), tr("No hay ninguna calicata abierta."));
        return;
    }

    // ------------------------------------------------------------
    // 1) Si está dirty, ofrecer guardar antes de exportar
    // ------------------------------------------------------------
    if (cal->isDirty()) {
        if (cal->currentFilePath().isEmpty())
            cal->guardarComo();
        else
            cal->guardar();

        if (cal->isDirty() || cal->currentFilePath().isEmpty()) {
            QMessageBox::warning(this,
                                 tr("Exportar Excel"),
                                 tr("No se pudo guardar la ficha antes de exportar."));
            return;
        }
    }

    // ------------------------------------------------------------
    // 2) Export requiere archivo real. Si no existe, forzar Guardar Como
    // ------------------------------------------------------------
    if (cal->currentFilePath().isEmpty()) {
        cal->guardarComo();
        if (cal->currentFilePath().isEmpty())
            return;
    }

    const QString jsonPath = cal->currentFilePath();
    if (jsonPath.isEmpty() || !QFileInfo::exists(jsonPath)) {
        QMessageBox::warning(this, tr("Exportar"), tr("Esta calicata aún no tiene archivo guardado."));
        return;
    }

    // ------------------------------------------------------------
    // 3) Aplicar título desde ingep_editable.json (SIN marcar dirty)
    //    Esto asegura que exportes con el título correcto incluso para archivos antiguos.
    // ------------------------------------------------------------
    const QString ctx = QFileInfo(jsonPath).absolutePath();
    if (!ctx.isEmpty()) {
        const EditableMetaInfo meta = readEditableMetaUp(ctx);
        if (!meta.excelTitle.isEmpty() && cal->tituloTestificacion().trimmed().isEmpty()) {
            cal->setTituloTestificacion(meta.excelTitle, /*markDirty=*/false);
        }
        if (!meta.logoMtcRelOrAbs.isEmpty() || !meta.logoProyectoRelOrAbs.isEmpty()) {
            cal->applyExternalEditableLogos(meta.logoMtcRelOrAbs, meta.logoProyectoRelOrAbs);
        }

    }


    // ------------------------------------------------------------
    // 4) Elegir nombre/ruta de salida
    // ------------------------------------------------------------
    const QString dir = suggestedExcelDirForJson(jsonPath);
    const QString defaultName = suggestedExcelFileNameForJson(jsonPath);

    GuardarExportDialog dlg(
        calicatasRootDirForJson(jsonPath),
        dir,
        defaultName,
        ".xlsx",
        this
        );

    if (dlg.exec() != QDialog::Accepted)
        return;

    const QString outPath = dlg.selectedFilePath();

    // Confirmar overwrite si ya existe
    if (QFileInfo::exists(outPath)) {
        const auto ret = QMessageBox::question(
            this,
            tr("Sobrescribir Excel"),
            tr("Ya existe un archivo con ese nombre.\n¿Deseas sobrescribirlo?"),
            QMessageBox::Yes | QMessageBox::No,
            QMessageBox::No
            );
        if (ret != QMessageBox::Yes)
            return;
    }

    // ------------------------------------------------------------
    // 5) Guardar estado actual antes de exportar
    // ------------------------------------------------------------
    if (cal->isDirty()) {
        cal->guardar();

        if (cal->isDirty() || cal->currentFilePath().isEmpty()) {
            QMessageBox::warning(this,
                                 tr("Exportar Excel"),
                                 tr("No se pudo guardar la ficha antes de exportar."));
            return;
        }
    }

    // Importante: después de guardar, volver a tomar la ruta actual.
    // Puede cambiar si el usuario guardó como o si hubo renombrado.
    const QString jsonPathFinal = cal->currentFilePath();

    if (jsonPathFinal.isEmpty() || !QFileInfo::exists(jsonPathFinal)) {
        QMessageBox::warning(this,
                             tr("Exportar"),
                             tr("Esta calicata aún no tiene archivo guardado."));
        return;
    }

    // ------------------------------------------------------------
    // 6) Exportar
    // ------------------------------------------------------------
    QString err;
    if (!CalicataExcelExporter::exportFromCalicataFile(jsonPathFinal, outPath, &err)) {
        QMessageBox::warning(this, tr("Error"), err);
        return;
    }

    QMessageBox::information(this, tr("Listo"), tr("Excel exportado en:\n%1").arg(outPath));
}



void CalicatasEditorWindow::onCurrentTabChanged(int)
{
    updateActionsForCurrent();

    if (m_mapDialog)
        pushCurrentCalicataToMapDialog();
}

void CalicatasEditorWindow::onAutoSaveToggled(bool enabled)
{
    // Aplica a TODAS las pestañas
    for (int i = 0; i < ui->tabWidgetCalicatas->count(); ++i) {
        auto *cw = qobject_cast<CalicataWindow*>(ui->tabWidgetCalicatas->widget(i));
        if (cw) cw->setAutoSaveEnabled(enabled);
    }
}

void CalicatasEditorWindow::updateActionsForCurrent()
{
    auto *cw = currentCalicata();
    const bool has = (cw != nullptr);

    if (m_btnGuardar)
        m_btnGuardar->setEnabled(has && cw->isDirty());

    if (m_btnGuardarComo)
        m_btnGuardarComo->setEnabled(has);

    if (m_btnExport)
        m_btnExport->setEnabled(has);

    if (m_btnUndo)
        m_btnUndo->setEnabled(has && cw->canUndo());

    if (m_btnRedo)
        m_btnRedo->setEnabled(has && cw->canRedo());
}

bool CalicatasEditorWindow::anyDirtyTabs() const
{
    for (int i = 0; i < ui->tabWidgetCalicatas->count(); ++i) {
        auto *cw = qobject_cast<CalicataWindow*>(ui->tabWidgetCalicatas->widget(i));
        if (cw && cw->isDirty())
            return true;
    }
    return false;
}

void CalicatasEditorWindow::updateEditorTitle()
{
    const bool dirty = anyDirtyTabs();
    setWindowTitle(dirty ? (m_baseTitle + " *") : m_baseTitle);
}


void CalicatasEditorWindow::onExternalEditableTitleChanged(const QString& editableFolderAbs,
                                                           const QString& newTitle)
{
    const QString nt = newTitle.trimmed();
    if (nt.isEmpty()) return;

    QString folder = QDir::cleanPath(QDir::fromNativeSeparators(editableFolderAbs));
    QString prefix = folder;
    if (!prefix.endsWith('/')) prefix += '/';

#ifdef Q_OS_WIN
    const Qt::CaseSensitivity cs = Qt::CaseInsensitive;
#else
    const Qt::CaseSensitivity cs = Qt::CaseSensitive;
#endif

    // OJO: usa TU tabwidget real (en tu screenshot es tabWidgetCalicatas)
    for (int i = 0; i < ui->tabWidgetCalicatas->count(); ++i) {
        QWidget *w = ui->tabWidgetCalicatas->widget(i);
        if (!w) continue;

        CalicataWindow *cw = qobject_cast<CalicataWindow*>(w);
        if (!cw) cw = w->findChild<CalicataWindow*>();
        if (!cw) continue;

        QString fp = cw->currentFilePath();
        if (fp.isEmpty())
            fp = cw->property("calicataFilePath").toString();

        fp = QDir::cleanPath(QDir::fromNativeSeparators(fp));
        if (fp.isEmpty()) continue;

        const bool under = fp.startsWith(prefix, cs);
        if (!under) continue;

        // ✅ actualiza en memoria/UI sin reabrir
        cw->applyExternalEditableTitle(nt);  // ✅ no ensucia, y actualiza UI del botón como tú lo definiste

        // si tu tab depende de displayName, refresca tab
        updateTabTitleFor(cw);
    }

    updateEditorTitle();
}


void CalicatasEditorWindow::onExportExcelBatch()
{
    const QString basePath = baseProjectsPath();
    QDir().mkpath(basePath);

    ExportExcelBatchDialog dlg(basePath, this);
    dlg.exec();
}

void CalicatasEditorWindow::onExternalEditableLogosChanged(const QString& editableFolderAbs,
                                                           const QString& mtcRel,
                                                           const QString& proyectoRel)
{
    QString folder = QDir::cleanPath(QDir::fromNativeSeparators(editableFolderAbs));
    QString prefix = folder;
    if (!prefix.endsWith('/')) prefix += '/';

#ifdef Q_OS_WIN
    const Qt::CaseSensitivity cs = Qt::CaseInsensitive;
#else
    const Qt::CaseSensitivity cs = Qt::CaseSensitive;
#endif

    for (int i = 0; i < ui->tabWidgetCalicatas->count(); ++i) {
        QWidget* w = ui->tabWidgetCalicatas->widget(i);
        if (!w) continue;

        CalicataWindow* cw = qobject_cast<CalicataWindow*>(w);
        if (!cw) cw = w->findChild<CalicataWindow*>();
        if (!cw) continue;

        QString fp = cw->currentFilePath();
        if (fp.isEmpty())
            fp = cw->property("calicataFilePath").toString();

        fp = QDir::cleanPath(QDir::fromNativeSeparators(fp));
        if (fp.isEmpty()) continue;

        if (!fp.startsWith(prefix, cs)) continue;

        cw->applyExternalEditableLogos(mtcRel, proyectoRel);
    }
}


void CalicatasEditorWindow::onGpsToggled(bool on)
{
    if (on && m_mapDialog) {
        m_mapDialog->close();
        m_mapDialog = nullptr;
    }

    syncGpsMenuState(on);

    // 1) Preferible: mandar al origen
    if (m_home && m_home->ubicacionWin()) {
        m_home->ubicacionWin()->setGpsAutoShare(on);
        return;
    }

    // 2) Fallback
    QSettings s;
    s.setValue("gps/autoShare", on);
    s.setValue("gps_enabled", on);

    if (on) GpsManager::instance()->start();
    else    GpsManager::instance()->stop();
}

void CalicatasEditorWindow::showEvent(QShowEvent *event)
{
    QMainWindow::showEvent(event);

    // ✅ Por si vienes de una versión donde se quedaron sin tabs
    if (ui->tabWidgetCalicatas->count() == 0)
        crearTabPorDefecto();

    ensureGpsLink();
}

void CalicatasEditorWindow::ensureGpsLink()
{
    if (m_gpsLinked || !m_btnGps) return;
    m_gpsLinked = true;

    const bool on = GpsManager::instance()->isActive();
    syncGpsMenuState(on);

    if (m_home && m_home->ubicacionWin()) {
        connect(m_home->ubicacionWin(), &UbicacionWindow::gpsAutoShareChanged,
                this, [this](bool on){
                    if (on && m_mapDialog) {
                        m_mapDialog->close();
                        m_mapDialog = nullptr;
                    }
                    syncGpsMenuState(on);
                });
    }


    m_gpsOn = on;
    setGpsButtonVisual(on);
}




void CalicatasEditorWindow::setGpsButtonVisual(bool on)
{
    if (!m_btnGps) return;

    const QSize iconSz = m_btnGps->iconSize().isValid()
                             ? m_btnGps->iconSize()
                             : QSize(26, 26);

    // Mantén el movie alineado al tamaño actual del icono
    if (m_gpsBtnMovie)
        m_gpsBtnMovie->setScaledSize(iconSz);

    if (on) {
        m_btnGps->setText("GPS");

        if (m_gpsBtnMovie && m_gpsBtnMovie->isValid()) {
            if (m_gpsBtnMovie->state() != QMovie::Running)
                m_gpsBtnMovie->start();

            // ✅ pinta un frame inicial ya escalado (por si aún no se disparó frameChanged)
            QPixmap pm = m_gpsBtnMovie->currentPixmap();
            if (!pm.isNull()) {
                pm = pm.scaled(iconSz, Qt::IgnoreAspectRatio, Qt::SmoothTransformation);
                m_btnGps->setIcon(QIcon(pm));
            }
        }

    } else {
        if (m_gpsBtnMovie) m_gpsBtnMovie->stop();
        m_btnGps->setText("GPS");

        // ✅ OFF: más pequeño (padding visual)
        const int inner = qRound(iconSz.width() * 0.40); // 0.60 = más padding, 0.70 = menos

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

void CalicatasEditorWindow::ensureWatcher()
{
    if (m_fsWatcher) return;
    m_fsWatcher = new QFileSystemWatcher(this);
    connect(m_fsWatcher, &QFileSystemWatcher::fileChanged,
            this, &CalicatasEditorWindow::onWatchedFileChanged);
}

void CalicatasEditorWindow::refreshLastMTime(CalicataWindow* cw)
{
    if (!cw) return;
    QString p = cw->property("_openPath").toString();
    if (p.isEmpty()) p = cw->currentFilePath();
    if (p.isEmpty()) return;

    cw->setProperty("_lastMtime", QFileInfo(p).lastModified());
    cw->setProperty("_externalConflict", false);
}

void CalicatasEditorWindow::watchCalicataFile(CalicataWindow* cw, const QString& absReal)
{
    if (!cw || absReal.isEmpty()) return;

    ensureWatcher();

    const QString key = openKeyForAbs(absReal);
    cw->setProperty("_openKey", key);
    cw->setProperty("_openPath", absReal);

    m_tabByKey[key] = cw;

    // ojo: en Windows, si el archivo se reemplaza (save-atómico), el watcher se “desengancha”.
    // igual lo re-enganchamos en el slot.
    if (!m_fsWatcher->files().contains(absReal))
        m_fsWatcher->addPath(absReal);

    refreshLastMTime(cw);
}

void CalicatasEditorWindow::unwatchCalicataFile(CalicataWindow* cw)
{
    if (!cw || !m_fsWatcher) return;

    const QString key  = cw->property("_openKey").toString();
    const QString path = cw->property("_openPath").toString();

    if (!path.isEmpty())
        m_fsWatcher->removePath(path);

    if (!key.isEmpty())
        m_tabByKey.remove(key);

    cw->setProperty("_openKey", QString());
    cw->setProperty("_openPath", QString());
}

void CalicatasEditorWindow::onWatchedFileChanged(const QString& path)
{
    const QString absReal = absPathPreserveCase(path);
    const QString key     = openKeyForAbs(absReal);

    CalicataWindow* cw = m_tabByKey.value(key, nullptr);
    if (!cw) return;

    // Re-enganchar watcher (Windows puede soltarlo tras cambios)
    if (QFileInfo::exists(absReal) && m_fsWatcher && !m_fsWatcher->files().contains(absReal))
        m_fsWatcher->addPath(absReal);

    const QDateTime now  = QFileInfo(absReal).lastModified();
    const QDateTime last = cw->property("_lastMtime").toDateTime();

    // Ignorar eventos “propios” muy cercanos (tolerancia)
    if (now.isValid() && last.isValid() && now <= last.addMSecs(80))
        return;

    // Si NO hay cambios locales, recarga automático
    if (!cw->isDirty()) {
        if (cw->cargarDesdeArchivo(absReal)) {
            refreshLastMTime(cw);
            updateTabTitleFor(cw);
            updateEditorTitle();
        }
        return;
    }

    // Si hay cambios locales: conflicto
    if (!cw->property("_externalConflict").toBool()) {
        cw->setProperty("_externalConflict", true);

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
            cw->cargarDesdeArchivo(absReal);
            refreshLastMTime(cw);
        } else if (clicked == bSaveAs) {
            cw->guardarComo();
            // si cambió de path, re-watch al nuevo:
            const QString newPath = absPathPreserveCase(cw->currentFilePath());
            if (!newPath.isEmpty() && openKeyForAbs(newPath) != key) {
                unwatchCalicataFile(cw);
                watchCalicataFile(cw, newPath);
            } else {
                refreshLastMTime(cw);
            }
        } else if (clicked == bKeep) {
            // mantener -> dejamos _externalConflict=true
        } else {
            // Cancel -> dejamos flag para no spamear
        }

        updateTabTitleFor(cw);
        updateEditorTitle();
    }
}

void CalicatasEditorWindow::syncGpsMenuState(bool on)
{
    if (m_btnGps) {
        QSignalBlocker b(m_btnGps);
        m_btnGps->setChecked(on);
    }

    if (m_actGpsToggle) {
        QSignalBlocker b(m_actGpsToggle);
        m_actGpsToggle->setChecked(on);
    }

    if (m_actShowMap)
        m_actShowMap->setEnabled(!on);

    m_gpsOn = on;
    setGpsButtonVisual(on);
}

void CalicatasEditorWindow::onShowInteractiveMap()
{
    if (m_btnGps && m_btnGps->isChecked()) {
        QMessageBox::information(this,
                                 tr("Mapa interactivo"),
                                 tr("El mapa interactivo manual solo está disponible con el GPS desactivado."));
        return;
    }

    if (m_mapDialog) {
        m_mapDialog->show();
        m_mapDialog->raise();
        m_mapDialog->activateWindow();
        pushCurrentCalicataToMapDialog();
        return;
    }

    m_mapDialog = new CalicataMapDialog(this);

    connect(m_mapDialog, &CalicataMapDialog::manualUtmChosen,
            this,
            [this](const QString& zona,
                   const QString& x,
                   const QString& y,
                   const QString& alt,
                   const QGeoCoordinate& coord)
            {
                applyDialogUtmToCurrentCalicata(zona, x, y, alt);

                if (m_home && m_home->ubicacionWin())
                    m_home->ubicacionWin()->applyExternalManualCoordinate(coord);
            });

    connect(m_mapDialog.data(), &QObject::destroyed, this, [this](){
        m_mapDialog = nullptr;
    });

    pushCurrentCalicataToMapDialog();

    m_mapDialog->show();
    m_mapDialog->raise();
    m_mapDialog->activateWindow();
}

void CalicatasEditorWindow::pushCurrentCalicataToMapDialog()
{
    if (!m_mapDialog)
        return;

    auto *cw = currentCalicata();
    if (!cw)
        return;

    // Estas 3 funciones se agregan en CalicataWindow (abajo te las dejo)
    m_mapDialog->setInitialFromUtm(
        cw->utmZona(),
        cw->utmX(),
        cw->utmY()
        );
}

void CalicatasEditorWindow::applyDialogUtmToCurrentCalicata(const QString& zona,
                                                            const QString& x,
                                                            const QString& y,
                                                            const QString& alt)
{
    auto *cw = currentCalicata();
    if (!cw)
        return;

    // Esta función también se agrega en CalicataWindow
    cw->applyExternalUtm(zona, x, y, alt, /*markDirty=*/true);

    updateActionsForCurrent();
    updateEditorTitle();
}

void CalicatasEditorWindow::onUndoCurrent()
{
    if (!isActiveWindow())
        return;

    auto *cw = currentCalicata();
    if (!cw)
        return;

    cw->undoForm();
    updateActionsForCurrent();
    updateUndoRedoForCurrent();
}

void CalicatasEditorWindow::onRedoCurrent()
{
    if (!isActiveWindow())
        return;

    auto *cw = currentCalicata();
    if (!cw)
        return;

    cw->redoForm();
    updateActionsForCurrent();
    updateUndoRedoForCurrent();
}

void CalicatasEditorWindow::updateUndoRedoForCurrent()
{
    auto *cw = currentCalicata();
    const bool has = (cw != nullptr);

    if (m_btnUndo)
        m_btnUndo->setEnabled(has && cw->canUndo());

    if (m_btnRedo)
        m_btnRedo->setEnabled(has && cw->canRedo());
}
