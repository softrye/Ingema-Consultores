// calicatawindow.cpp
#include "calicatawindow.h"
#include "ui_calicatawindow.h"
#include "jsonwidgetserializer.h"
#include "ingetheme.h"

#include "corterowwidget.h"
#include "timestampdialog.h"
#include "ubicacionwindow.h"        // g_ubicacionData
#include "guardarcalicatadialog.h"
#include "resourcesimagepickerdialog.h"
#include "appcontext.h"


#include <QVBoxLayout>
#include <QPushButton>
#include <QToolButton>
#include <QFileDialog>
#include <QIcon>
#include <QPainter>
#include <QDate>
#include <QTime>
#include <QStyle>
#include <QTableView>
#include <QCloseEvent>
#include <QResizeEvent>
#include <QMessageBox>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonParseError>

#include <QLineEdit>
#include <QComboBox>
#include <QDateEdit>
#include <QPlainTextEdit>
#include <QTextEdit>
#include <QCheckBox>
#include <QRadioButton>
#include <QSpinBox>
#include <QDoubleSpinBox>
#include <QDoubleValidator>
#include <QCalendarWidget>
#include <QStandardPaths>
#include <QDir>
#include <QRegularExpression>
#include <QBuffer>
#include <QLayoutItem>

#include <QLocale>
#include <QSignalBlocker>
#include <QTimer>
#include <QEvent>
#include <QtMath>

#include <QMimeData>
#include <QDragEnterEvent>
#include <QDragMoveEvent>
#include <QDropEvent>
#include <QDataStream>

#include <QScrollBar>
#include <QImage>
#include <QAbstractButton>
#include <QPointer>

// NUEVO: selector interno (tipo "Abrir") bloqueado a una carpeta
#include <QDialog>
#include <QDialogButtonBox>
#include <QFileSystemModel>
#include <QTreeView>
#include <QLabel>
#include <QHeaderView>
#include <QItemSelectionModel>
#include <QInputDialog>

#include <QHBoxLayout>
#include <QTextEdit>
#include <QSaveFile>
#include <QTextOption>


// ============================================================
// Constantes de metadata de proyecto
// ============================================================
static const char* kProjectMetaFilePrimary = ".ingep_project.json";
static const char* kProjectMetaFileLegacy  = ".ingema_project.json";

// Editable meta + folder
static const char* kEditableMetaFile     = ".ingep_editable.json";
static const char* kEditablePhotosFolder = "fotos";

// Carpeta recursos del proyecto
static const char* kProjectResourcesFolder1 = "Recursos";
static const char* kProjectResourcesFolder2 = "recursos";

// Mime para drag de cortes (misma fuente que CorteRowWidget)
static const char* kCorteRowMime = CorteRowWidget::mimeTypeCorteRow();

static constexpr double kMaxDepth     = 3.00;
static constexpr double kDepthStep    = 0.05;
static constexpr int    kDepthDecimals = 2;

// ------------------------------------------------------------
// Helpers: nombres serializables (evita qt_* internos)
// ------------------------------------------------------------
static bool isSerializableName(const QString& n)
{
    if (n.isEmpty()) return false;
    if (n.startsWith("qt_", Qt::CaseInsensitive)) return false;
    return true;
}

static QString canonicalAbs(const QString& p)
{
    QFileInfo fi(p);
    QString c = fi.canonicalFilePath();      // resuelve .., symlinks, etc.
    if (c.isEmpty()) c = fi.absoluteFilePath();
    return QDir::cleanPath(c);
}

// ------------------------------------------------------------
// Helpers: sanitize (para nombres de carpetas)
// ------------------------------------------------------------
static QString legacyGlobalRecursosDir()
{
    // LEGACY: no crear, solo usar si existe
    return QDir::cleanPath(QDir::homePath() + "/InGePlusProyectos/Recursos");
}

static QString pathKey(const QString& path)
{
    QFileInfo fi(path);
    QString abs = fi.canonicalFilePath();
    if (abs.isEmpty()) abs = fi.absoluteFilePath();

    abs = QDir::cleanPath(QDir::fromNativeSeparators(abs));

#ifdef Q_OS_WIN
    abs = abs.toLower();
#endif
    return abs;
}

static QString sanitizeFsName(QString s)
{
    s = s.trimmed();
    static const QRegularExpression invalid(R"([\/\\\:\*\?\"\<\>\|])");
    s.replace(invalid, "_");
    if (s.isEmpty()) s = "SinNombre";
    return s;
}

// ------------------------------------------------------------
// mapping de carpetas por tipo de foto
// ------------------------------------------------------------
static QString photoFolderDisplayName(int idx)
{
    switch (idx) {
    case 1: return "Fotografia_Zona_de_Ejecucion_Calicata";
    case 2: return "Fotografia_Interior_Calicata";
    case 3: return "Fotografia_Acopios";
    default: return QString("Fotografía_%1").arg(idx);
    }
}

static QProgressDialog* makeBusy(QWidget* parent, const QString& text, bool cancellable)
{
    auto *dlg = new QProgressDialog(text,
                                    cancellable ? QObject::tr("Cancelar") : QString(),
                                    0, 0, parent);     // 0..0 => indeterminado (barber pole)
    dlg->setWindowModality(Qt::ApplicationModal);
    dlg->setMinimumDuration(0);
    dlg->setAutoClose(false);
    dlg->setAutoReset(false);

    if (!cancellable) {
        dlg->setCancelButton(nullptr);
    }
    dlg->show();
    return dlg;
}


// ------------------------------------------------------------
// Dialog interno para seleccionar SOLO dentro del cache
// ------------------------------------------------------------

class MultiLineTextDialog : public QDialog
{
public:
    explicit MultiLineTextDialog(const QString& title,
                                 const QString& initialText,
                                 QWidget* parent = nullptr)
        : QDialog(parent)
    {
        setWindowTitle(title);
        setModal(true);
        resize(520, 260);

        auto *lay = new QVBoxLayout(this);

        auto *lbl = new QLabel(tr("Escribe el título (se guardará en ESTA ficha y se exportará al Excel):"), this);
        lay->addWidget(lbl);

        m_edit = new QTextEdit(this);
        m_edit->setAcceptRichText(false);
        m_edit->setPlainText(initialText);

        // ✅ Wrap al ancho del cuadro + solo scroll vertical
        m_edit->setLineWrapMode(QTextEdit::WidgetWidth);
        m_edit->setWordWrapMode(QTextOption::WrapAtWordBoundaryOrAnywhere);
        m_edit->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
        m_edit->setVerticalScrollBarPolicy(Qt::ScrollBarAsNeeded);

        lay->addWidget(m_edit, 1);


        auto *row = new QHBoxLayout();
        row->addStretch();

        auto *btnCancel = new QPushButton(tr("Cancelar"), this);
        auto *btnOk = new QPushButton(tr("OK"), this);
        btnOk->setDefault(true);

        row->addWidget(btnCancel);
        row->addWidget(btnOk);
        lay->addLayout(row);

        connect(btnCancel, &QPushButton::clicked, this, &QDialog::reject);
        connect(btnOk, &QPushButton::clicked, this, &QDialog::accept);
    }

    QString text() const { return m_edit ? m_edit->toPlainText() : QString(); }

private:
    QTextEdit* m_edit = nullptr;
};

class CacheImagePickerDialog : public QDialog
{
public:
    explicit CacheImagePickerDialog(const QString &rootDirAbs,
                                    const QString &title,
                                    QWidget *parent = nullptr)
        : QDialog(parent)
        , m_rootDir(rootDirAbs)
    {



        setWindowTitle(title);
        setModal(true);
        resize(860, 520);

        auto *lay = new QVBoxLayout(this);
        lay->setContentsMargins(10,10,10,10);
        lay->setSpacing(8);

        auto *lbl = new QLabel(tr("Selecciona una imagen guardada en el cache de la aplicación:"), this);
        lay->addWidget(lbl);

        m_model = new QFileSystemModel(this);
        m_model->setFilter(QDir::NoDotAndDotDot | QDir::AllDirs | QDir::Files);
        m_model->setNameFilterDisables(false);
        m_model->setNameFilters(QStringList() << "*.jpg" << "*.jpeg" << "*.png" << "*.bmp" << "*.webp");
        m_model->setRootPath(m_rootDir);

        m_view = new QTreeView(this);
        m_view->setModel(m_model);
        m_view->setRootIndex(m_model->index(m_rootDir));
        m_view->setSelectionMode(QAbstractItemView::SingleSelection);
        m_view->setSelectionBehavior(QAbstractItemView::SelectRows);
        m_view->setEditTriggers(QAbstractItemView::NoEditTriggers);
        m_view->setUniformRowHeights(true);
        m_view->header()->setStretchLastSection(true);
        m_view->header()->setSectionResizeMode(0, QHeaderView::Stretch);

        // Oculta columnas extra para que se parezca a un "Abrir"
        for (int c = 1; c < m_model->columnCount(); ++c)
            m_view->hideColumn(c);

        lay->addWidget(m_view, 1);

        m_preview = new QLabel(this);
        m_preview->setMinimumHeight(120);
        m_preview->setAlignment(Qt::AlignCenter);
        m_preview->setText(tr("Vista previa"));
        lay->addWidget(m_preview);

        m_buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
        lay->addWidget(m_buttons);

        m_ok = m_buttons->button(QDialogButtonBox::Ok);
        if (m_ok) m_ok->setEnabled(false);

        connect(m_buttons, &QDialogButtonBox::accepted, this, [this](){
            if (hasValidSelection())
                accept();
        });
        connect(m_buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);

        connect(m_view->selectionModel(), &QItemSelectionModel::selectionChanged, this, [this](){
            updateUiFromSelection();
        });

        connect(m_view, &QTreeView::doubleClicked, this, [this](const QModelIndex &idx){
            if (!idx.isValid()) return;
            if (!m_model->isDir(idx)) {
                m_selectedAbs = m_model->filePath(idx);
                accept();
            }
        });
    }

    QString selectedAbsPath() const { return m_selectedAbs; }

private:
    bool hasValidSelection()
    {
        const QModelIndex idx = m_view ? m_view->currentIndex() : QModelIndex();
        if (!idx.isValid() || m_model->isDir(idx)) return false;

        const QString abs = m_model->filePath(idx);
        if (!QFileInfo::exists(abs)) return false;

        m_selectedAbs = abs;
        return true;
    }


    void updateUiFromSelection()
    {
        bool okSel = false;
        QString abs;

        QModelIndex idx = m_view->currentIndex();
        if (idx.isValid() && !m_model->isDir(idx)) {
            abs = m_model->filePath(idx);
            okSel = QFileInfo::exists(abs);
        }

        if (m_ok) m_ok->setEnabled(okSel);

        if (!okSel) {
            m_preview->setText(tr("Vista previa"));
            m_preview->setPixmap(QPixmap());
            return;
        }

        QPixmap pm(abs);
        if (pm.isNull()) {
            m_preview->setText(tr("No se pudo cargar la imagen"));
            m_preview->setPixmap(QPixmap());
            return;
        }

        const QSize target(520, 160);
        m_preview->setPixmap(pm.scaled(target, Qt::KeepAspectRatio, Qt::SmoothTransformation));
        m_preview->setText("");
    }

private:
    QString m_rootDir;
    QFileSystemModel *m_model = nullptr;
    QTreeView *m_view = nullptr;
    QLabel *m_preview = nullptr;
    QDialogButtonBox *m_buttons = nullptr;
    QPushButton *m_ok = nullptr;

    QString m_selectedAbs;
};

static QString absPathPreserveCase(const QString& path)
{
    QFileInfo fi(path);
    QString abs = fi.canonicalFilePath();
    if (abs.isEmpty()) abs = fi.absoluteFilePath();

    return QDir::cleanPath(QDir::fromNativeSeparators(abs));
}

static QString openKeyForAbs(const QString& absPreserveCase)
{
    QString k = absPreserveCase;
#ifdef Q_OS_WIN
    k = k.toLower();
#endif
    return k;
}



// ------------------------------------------------------------
// EventFilter: al entrar al QLineEdit, selecciona todo
// ------------------------------------------------------------
class SelectAllOnFocusFilter : public QObject
{
public:
    explicit SelectAllOnFocusFilter(QObject *parent = nullptr) : QObject(parent) {}
protected:
    bool eventFilter(QObject *obj, QEvent *ev) override
    {
        if (ev->type() == QEvent::FocusIn) {
            if (auto *le = qobject_cast<QLineEdit*>(obj)) {
                QTimer::singleShot(0, le, [le](){ le->selectAll(); });
            }
        }
        return QObject::eventFilter(obj, ev);
    }
};


static QString normPath(const QString& p)
{
    return QDir::cleanPath(QDir::fromNativeSeparators(p));
}


static int nextIndexForPrefix(const QString& absDir, const QString& prefix)
{
    QDir dir(absDir);
    if (!dir.exists()) return 1;

    const QStringList filters = {
        QString("%1_*.jpg").arg(prefix),
        QString("%1_*.jpeg").arg(prefix),
        QString("%1_*.png").arg(prefix)
    };

    const QStringList files = dir.entryList(filters, QDir::Files, QDir::Name);

    QRegularExpression re(
        QString("^%1_(\\d+)\\.(jpg|jpeg|png)$").arg(QRegularExpression::escape(prefix)),
        QRegularExpression::CaseInsensitiveOption
        );

    int maxN = 0;
    for (const QString& fn : files) {
        auto m = re.match(fn);
        if (!m.hasMatch()) continue;
        const int n = m.captured(1).toInt();
        if (n > maxN) maxN = n;
    }
    return maxN + 1;
}

// Guarda SIEMPRE como archivo nuevo (no sobrescribe), y retorna relPath (para escribirlo al JSON)
QString CalicataWindow::saveGeneratedPhotoToEditableCache(QPushButton* boton,
                                                          const QPixmap& pix,
                                                          const QString& ctxFilePath)
{
    auto normPath = [](QString p) {
        p = QDir::fromNativeSeparators(p.trimmed());
        return p.isEmpty() ? QString() : QDir::cleanPath(p);
    };

    const QString ctx = normPath(ctxFilePath);
    const QString editableRoot = normPath(editableRootForPath(ctx));
    if (editableRoot.isEmpty() || pix.isNull())
        return QString();

    // Progresiva / carpeta de calicata
    QString prog;
    if (ui && ui->txtProgresiva) prog = ui->txtProgresiva->text().trimmed();
    if (prog.isEmpty()) prog = QFileInfo(ctx).completeBaseName();
    if (prog.isEmpty()) prog = "CALICATA";

    // Mapea botón -> subcarpeta + prefijo
    QString subFolder;
    QString prefix;

    if (ui && boton == ui->btnFoto1) {
        subFolder = "Fotografia_Zona_de_Ejecucion_Calicata";
        prefix    = "Foto_ZE_Calicata";
    } else if (ui && boton == ui->btnFoto2) {
        subFolder = "Fotografia_Interior_Calicata";
        prefix    = "Foto_Calicata_Interior";
    } else if (ui && boton == ui->btnFoto3) {
        subFolder = "Fotografia_Acopios";
        prefix    = "Foto_Acopios";
    } else {
        // No es una foto de las 3
        return QString();
    }

    QDir root(editableRoot);

    // Estructura: /Edit/fotos/<PROGRESIVA>/<SUBFOLDER>/
    const QString relDir = normPath(QString("fotos/%1/%2").arg(prog, subFolder));
    root.mkpath(relDir);

    const QString absDir = normPath(root.filePath(relDir));
    const int idx = nextIndexForPrefix(absDir, prefix);

    const QString fileName = QString("%1_%2.jpg").arg(prefix).arg(idx, 3, 10, QChar('0'));
    const QString absPath  = normPath(QDir(absDir).filePath(fileName));

    // Guardado JPG (calidad alta)
    QImage img = pix.toImage();
    if (!img.save(absPath, "JPG", 92)) {
        qWarning() << "No se pudo guardar foto cache:" << absPath;
        return QString();
    }

    const QString relPath = normPath(QDir(editableRoot).relativeFilePath(absPath));
    return relPath;
}

static QString toAbs(const QString& p) {
    if (p.trimmed().isEmpty()) return {};
    return QFileInfo(p).absoluteFilePath();
}

// ------------------------------------------------------------
// Helpers combos profundidad (0.00..1.50 paso 0.01)
// ------------------------------------------------------------
static double snapDepthToStep(double v)
{
    v = qBound(0.0, v, kMaxDepth);

    const double steps = qRound(v / kDepthStep);
    double snapped = steps * kDepthStep;

    // dejar limpio a 2 decimales
    snapped = qRound64(snapped * 100.0) / 100.0;
    return snapped;
}

static void ensureDepthItems(QComboBox *cb, bool allowEmpty)
{
    if (!cb) return;

    const QString previousText = cb->currentText().trimmed();
    const QSignalBlocker blocker(cb);

    cb->clear();

    if (allowEmpty)
        cb->addItem("");

    const int maxSteps = qRound(kMaxDepth / kDepthStep);

    for (int i = 0; i <= maxSteps; ++i) {
        const double v = i * kDepthStep;
        cb->addItem(QString::number(v, 'f', kDepthDecimals));
    }

    const int idx = cb->findText(previousText);
    if (idx >= 0) {
        cb->setCurrentIndex(idx);
    } else {
        const int zeroIdx = cb->findText("0.00");
        if (zeroIdx >= 0)
            cb->setCurrentIndex(zeroIdx);
    }
}

static void setComboTextSafe(QComboBox *cb, const QString &text)
{
    if (!cb) return;
    const QSignalBlocker b(cb);

    const int idx = cb->findText(text);
    if (idx >= 0) cb->setCurrentIndex(idx);
    else if (cb->isEditable()) cb->setEditText(text);
    else if (text.isEmpty()) {
        int e = cb->findText("");
        if (e >= 0) cb->setCurrentIndex(e);
    }
}

static QString fileStemPreserveCase(const QString& absReal)
{
    // Ej: "CT15-4+500.calicata" (si el archivo es .calicata.json)
    QString base = QFileInfo(absReal).completeBaseName();

    if (base.endsWith(".calicata", Qt::CaseInsensitive))
        base.chop(QString(".calicata").size());

    return base;
}

// ------------------------------------------------------------
// Cortes helpers
// ------------------------------------------------------------
QVector<CorteRowWidget*> CalicataWindow::cortes() const
{
    QVector<CorteRowWidget*> out;
    if (!m_layoutCortes) return out;

    for (int i = 0; i < m_layoutCortes->count(); ++i) {
        if (auto *row = qobject_cast<CorteRowWidget*>(m_layoutCortes->itemAt(i)->widget()))
            out.push_back(row);
    }
    return out;
}

double CalicataWindow::parseDepth(const QString &s, bool *ok) const
{
    QString t = s.trimmed();
    if (t.isEmpty()) { if (ok) *ok = false; return 0.0; }

    bool ok1 = false;
    double v = QLocale::c().toDouble(t, &ok1);
    if (!ok1) v = QLocale().toDouble(t, &ok1);

    if (ok) *ok = ok1;
    return v;
}

QString CalicataWindow::fmtDepth(double v) const
{
    return QString::number(v, 'f', 2);
}

// ------------------------------------------------------------
// Interval rules
// ------------------------------------------------------------
void CalicataWindow::setupIntervalRules(CorteRowWidget *row)
{
    if (!row) return;
    if (row->property("_intervalHooked").toBool()) return;
    row->setProperty("_intervalHooked", true);

    auto *de = row->editDE();
    auto *a  = row->editA();
    if (!de || !a) return;

    ensureDepthItems(de, true);
    ensureDepthItems(a,  true);

    a->setEditable(true);
    a->setInsertPolicy(QComboBox::NoInsert);
    a->setFocusPolicy(Qt::StrongFocus);
    a->setCompleter(nullptr);

    if (auto *le = a->lineEdit()) {
        le->setReadOnly(false);
        le->setAlignment(Qt::AlignCenter);
        le->setClearButtonEnabled(false);

        le->installEventFilter(new SelectAllOnFocusFilter(le));

        auto *val = new QDoubleValidator(0.0, kMaxDepth, 2, le);
        val->setNotation(QDoubleValidator::StandardNotation);
        val->setLocale(QLocale::c());
        le->setValidator(val);

        connect(le, &QLineEdit::editingFinished, this, [this](){
            if (m_loading || m_updatingIntervals) return;
            renumerarCortesYIntervalos(true);
        });
    }

    connect(a, qOverload<int>(&QComboBox::activated), this, [this](int){
        if (m_loading || m_updatingIntervals) return;
        renumerarCortesYIntervalos(true);
    });

    connect(a, qOverload<int>(&QComboBox::currentIndexChanged), this, [this, a](int){
        if (m_loading || m_updatingIntervals) return;
        if (a->isEditable() && a->lineEdit() && a->lineEdit()->hasFocus())
            return;
        renumerarCortesYIntervalos(true);
    });
}

// ------------------------------------------------------------
// Delete rules
// ------------------------------------------------------------
void CalicataWindow::setupDeleteRules(CorteRowWidget *row)
{
    if (!row) return;
    if (row->property("_deleteHooked").toBool()) return;
    row->setProperty("_deleteHooked", true);

    connect(row, &CorteRowWidget::solicitarEliminar, this, [this](CorteRowWidget *r){
        eliminarCorte(r);
    });
}

void CalicataWindow::eliminarCorte(CorteRowWidget *row)
{
    if (!row || !m_layoutCortes) return;

    auto rows = cortes();
    const int idx = rows.indexOf(row);
    if (idx < 0) return;

    if (row->hasMeaningfulData()) {
        const auto ret = QMessageBox::question(
            this,
            tr("Eliminar corte"),
            tr("¿Deseas eliminar el Corte %1?\nSe perderá toda la información registrada en este corte.")
                .arg(idx + 1),
            QMessageBox::Yes | QMessageBox::No,
            QMessageBox::No
            );
        if (ret != QMessageBox::Yes)
            return;
    }

    if (rows.size() <= 1) {
        row->clearUserData();
    } else {
        m_layoutCortes->removeWidget(row);
        row->deleteLater();
    }

    renumerarCortesYIntervalos(true);
    marcarComoModificado();
}

void CalicataWindow::renumerarCortesYIntervalos(bool markDirty)
{
    if (m_updatingIntervals) return;
    m_updatingIntervals = true;

    const bool prevLoading = m_loading;
    if (!markDirty) m_loading = true;

    auto rows = cortes();
    double prevA = 0.0;
    bool prevKnown = true;

    for (int i = 0; i < rows.size(); ++i) {
        CorteRowWidget *row = rows[i];
        row->setCorteNumero(i + 1);

        auto *de = row->editDE();
        auto *a  = row->editA();
        if (!de || !a) continue;

        setComboTextSafe(de, prevKnown ? fmtDepth(prevA) : "");

        if (!prevKnown) {
            setComboTextSafe(a, "");
            continue;
        }

        bool okA = false;
        const QString aTxt = a->currentText().trimmed();
        double aVal = parseDepth(aTxt, &okA);

        if (!okA) {
            setComboTextSafe(a, "");
            prevKnown = false;
            continue;
        }

        if (aVal > kMaxDepth)
            aVal = kMaxDepth;

        const double minA = prevA + kDepthStep;
        if (aVal < minA)
            aVal = qMin(kMaxDepth, minA);

        aVal = snapDepthToStep(aVal);
        setComboTextSafe(a, fmtDepth(aVal));

        prevA = aVal;
    }

    m_loading = prevLoading;
    m_updatingIntervals = false;

    if (markDirty) marcarComoModificado();
}

// ------------------------------------------------------------
// Drag & Drop: setup + helpers + eventFilter
// ------------------------------------------------------------
void CalicataWindow::setupCortesDragDrop()
{
    if (!ui) return;

    if (ui->scrollArea) {
        ui->scrollArea->viewport()->setAcceptDrops(true);
        ui->scrollArea->viewport()->installEventFilter(this);
    }
    if (ui->scrollAreaWidgetContents) {
        ui->scrollAreaWidgetContents->setAcceptDrops(true);
        ui->scrollAreaWidgetContents->installEventFilter(this);
    }
    if (ui->frameCortesContainer) {
        ui->frameCortesContainer->setAcceptDrops(true);
        ui->frameCortesContainer->installEventFilter(this);
    }

    if (!m_dragAutoScrollTimer) {
        m_dragAutoScrollTimer = new QTimer(this);
        m_dragAutoScrollTimer->setInterval(16);

        connect(m_dragAutoScrollTimer, &QTimer::timeout, this, [this](){
            if (!ui || !ui->scrollArea) return;
            if (m_dragAutoScrollDir == 0 || m_dragAutoScrollSpeed <= 0) return;

            QScrollBar *bar = ui->scrollArea->verticalScrollBar();
            if (!bar) return;

            const int v = bar->value();
            bar->setValue(v + (m_dragAutoScrollDir * m_dragAutoScrollSpeed));
        });
    }
}

CorteRowWidget* CalicataWindow::decodeDraggedRow(const QMimeData *mime) const
{
    if (!mime) return nullptr;
    if (!mime->hasFormat(kCorteRowMime)) return nullptr;

    const QByteArray payload = mime->data(kCorteRowMime);
    QDataStream ds(payload);
    quintptr ptr = 0;
    ds >> ptr;

    auto *row = reinterpret_cast<CorteRowWidget*>(ptr);
    if (!row) return nullptr;

    if (!m_layoutCortes) return nullptr;
    if (m_layoutCortes->indexOf(row) < 0) return nullptr;

    return row;
}

QPoint CalicataWindow::toCortesContainerPos(QObject *watched, const QPoint &pos) const
{
    if (!ui || !ui->frameCortesContainer) return pos;

    auto *w = qobject_cast<QWidget*>(watched);
    if (!w) return pos;

    const QPoint g = w->mapToGlobal(pos);
    return ui->frameCortesContainer->mapFromGlobal(g);
}

QPoint CalicataWindow::toScrollViewportPos(QObject *watched, const QPoint &pos) const
{
    if (!ui || !ui->scrollArea) return pos;

    QWidget *vp = ui->scrollArea->viewport();
    if (!vp) return pos;

    auto *w = qobject_cast<QWidget*>(watched);
    if (!w) return pos;

    const QPoint g = w->mapToGlobal(pos);
    return vp->mapFromGlobal(g);
}

void CalicataWindow::updateAutoScrollFromViewportPos(const QPoint &posInViewport)
{
    if (!ui || !ui->scrollArea) return;
    QWidget *vp = ui->scrollArea->viewport();
    if (!vp) return;

    m_lastDragPosInViewport = posInViewport;

    const int margin = 40;
    const int h = vp->height();

    int dir = 0;
    int speed = 0;

    if (posInViewport.y() < margin) {
        dir = -1;
        const int dist = (margin - posInViewport.y());
        speed = qBound(4, dist / 2, 28);
    } else if (posInViewport.y() > (h - margin)) {
        dir = +1;
        const int dist = (posInViewport.y() - (h - margin));
        speed = qBound(4, dist / 2, 28);
    } else {
        dir = 0;
        speed = 0;
    }

    m_dragAutoScrollDir = dir;
    m_dragAutoScrollSpeed = speed;

    if (dir != 0) {
        if (m_dragAutoScrollTimer && !m_dragAutoScrollTimer->isActive())
            m_dragAutoScrollTimer->start();
    } else {
        stopAutoScroll();
    }
}

void CalicataWindow::stopAutoScroll()
{
    m_dragAutoScrollDir = 0;
    m_dragAutoScrollSpeed = 0;
    if (m_dragAutoScrollTimer && m_dragAutoScrollTimer->isActive())
        m_dragAutoScrollTimer->stop();
}

int CalicataWindow::insertIndexForDropY(int yInContainer, CorteRowWidget *dragging) const
{
    auto rows = cortes();
    int insertAt = 0;

    for (auto *row : rows) {
        if (!row) continue;
        if (row == dragging) continue;

        const QRect r = row->geometry();
        const int mid = r.top() + r.height() / 2;

        if (yInContainer < mid)
            return insertAt;

        insertAt++;
    }

    return insertAt;
}

void CalicataWindow::moveRowToIndex(CorteRowWidget *row, int insertAt)
{
    if (!row || !m_layoutCortes) return;

    auto rowsNo = cortes();
    rowsNo.removeAll(row);

    if (insertAt < 0) insertAt = 0;
    if (insertAt > rowsNo.size()) insertAt = rowsNo.size();

    m_layoutCortes->removeWidget(row);
    m_layoutCortes->insertWidget(insertAt, row);
    row->show();

    m_layoutCortes->invalidate();
    if (ui && ui->frameCortesContainer) ui->frameCortesContainer->updateGeometry();
}

bool CalicataWindow::eventFilter(QObject *watched, QEvent *event)
{
    const bool isDropTarget =
        ui &&
        (watched == ui->frameCortesContainer ||
         watched == ui->scrollAreaWidgetContents ||
         (ui->scrollArea && watched == ui->scrollArea->viewport()));

    if (!isDropTarget)
        return QMainWindow::eventFilter(watched, event);

    if (event->type() == QEvent::DragEnter) {
        auto *e = static_cast<QDragEnterEvent*>(event);
        if (decodeDraggedRow(e->mimeData())) {
            e->setDropAction(Qt::MoveAction);
            e->acceptProposedAction();

#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
            const QPoint p = e->position().toPoint();
#else
            const QPoint p = e->pos();
#endif
            updateAutoScrollFromViewportPos(toScrollViewportPos(watched, p));
            return true;
        }
        return false;
    }

    if (event->type() == QEvent::DragMove) {
        auto *e = static_cast<QDragMoveEvent*>(event);
        if (decodeDraggedRow(e->mimeData())) {
#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
            const QPoint p = e->position().toPoint();
#else
            const QPoint p = e->pos();
#endif
            updateAutoScrollFromViewportPos(toScrollViewportPos(watched, p));

            e->setDropAction(Qt::MoveAction);
            e->acceptProposedAction();
            return true;
        }
        stopAutoScroll();
        return false;
    }

    if (event->type() == QEvent::DragLeave) {
        stopAutoScroll();
        return false;
    }

    if (event->type() == QEvent::Drop) {
        auto *e = static_cast<QDropEvent*>(event);
        CorteRowWidget *dragging = decodeDraggedRow(e->mimeData());
        if (!dragging) { stopAutoScroll(); return false; }

#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
        const QPoint p = e->position().toPoint();
#else
        const QPoint p = e->pos();
#endif

        stopAutoScroll();

        const QPoint pInContainer = toCortesContainerPos(watched, p);
        const int insertAt = insertIndexForDropY(pInContainer.y(), dragging);

        moveRowToIndex(dragging, insertAt);

        renumerarCortesYIntervalos(true);
        marcarComoModificado();

        e->setDropAction(Qt::MoveAction);
        e->acceptProposedAction();
        return true;
    }

    return QMainWindow::eventFilter(watched, event);
}

static QString userRootFromContextPath(const QString& fileOrDirPath, const QString& baseProjectsPath)
{
    if (fileOrDirPath.trimmed().isEmpty()) return {};

    QFileInfo info(fileOrDirPath);
    QString dirPath = info.isDir() ? info.absoluteFilePath()
                                   : info.dir().absolutePath();

    QDir d(dirPath);
    const QString base = QDir::cleanPath(QDir::fromNativeSeparators(baseProjectsPath));

    while (d.exists()) {
        QDir parent = d;
        if (!parent.cdUp()) break;

        QString parentAbs = QDir::cleanPath(QDir::fromNativeSeparators(parent.absolutePath()));
        QString curAbs    = QDir::cleanPath(QDir::fromNativeSeparators(d.absolutePath()));

#ifdef Q_OS_WIN
        parentAbs = parentAbs.toLower();
        curAbs    = curAbs.toLower();
        const QString baseCmp = base.toLower();
#else
        const QString baseCmp = base;
#endif

        // si el padre es InGePlusProyectos => el actual es el userRoot
        if (parentAbs == baseCmp)
            return curAbs;

        if (curAbs == baseCmp)
            break;

        if (!d.cdUp()) break;
    }
    return {};
}


// ------------------------------------------------------------
// Utilidades internas (aplicar ui_state)
// ------------------------------------------------------------
static bool hasCorteRowAncestor(const QObject *o)
{
    const QObject *p = o;
    while (p) {
        if (qobject_cast<const CorteRowWidget*>(p))
            return true;
        p = p->parent();
    }
    return false;
}

static void applyWidgetTree(QWidget *root, const QJsonObject &data)
{
    if (!root) return;

    if (data.contains("line_edits") && data["line_edits"].isObject()) {
        const QJsonObject m = data["line_edits"].toObject();
        for (auto it = m.begin(); it != m.end(); ++it) {
            if (!isSerializableName(it.key())) continue;
            if (auto *w = root->findChild<QLineEdit*>(it.key())) {
                if (hasCorteRowAncestor(w)) continue;
                w->setText(it.value().toString());
            }
        }
    }

    if (data.contains("plain_text_edits") && data["plain_text_edits"].isObject()) {
        const QJsonObject m = data["plain_text_edits"].toObject();
        for (auto it = m.begin(); it != m.end(); ++it) {
            if (!isSerializableName(it.key())) continue;
            if (auto *w = root->findChild<QPlainTextEdit*>(it.key())) {
                if (hasCorteRowAncestor(w)) continue;
                w->setPlainText(it.value().toString());
            }
        }
    }

    if (data.contains("text_edits") && data["text_edits"].isObject()) {
        const QJsonObject m = data["text_edits"].toObject();
        for (auto it = m.begin(); it != m.end(); ++it) {
            if (!isSerializableName(it.key())) continue;
            if (auto *w = root->findChild<QTextEdit*>(it.key())) {
                if (hasCorteRowAncestor(w)) continue;
                w->setPlainText(it.value().toString());
            }
        }
    }

    if (data.contains("combo_boxes") && data["combo_boxes"].isObject()) {
        const QJsonObject m = data["combo_boxes"].toObject();
        for (auto it = m.begin(); it != m.end(); ++it) {
            if (!isSerializableName(it.key())) continue;

            auto *w = root->findChild<QComboBox*>(it.key());
            if (!w) continue;
            if (hasCorteRowAncestor(w)) continue;

            QString txt;
            int idx = -1;

            if (it.value().isObject()) {
                const QJsonObject v = it.value().toObject();
                idx = v.value("index").toInt(-1);
                txt = v.value("text").toString();
            } else {
                txt = it.value().toString();
            }

            if (!txt.isEmpty()) {
                int f = w->findText(txt);
                if (f >= 0) { w->setCurrentIndex(f); continue; }
                if (w->isEditable()) { w->setEditText(txt); continue; }
            }

            if (idx >= 0 && idx < w->count())
                w->setCurrentIndex(idx);
        }
    }

    if (data.contains("check_boxes") && data["check_boxes"].isObject()) {
        const QJsonObject m = data["check_boxes"].toObject();
        for (auto it = m.begin(); it != m.end(); ++it) {
            if (!isSerializableName(it.key())) continue;
            if (auto *w = root->findChild<QCheckBox*>(it.key())) {
                if (hasCorteRowAncestor(w)) continue;
                w->setChecked(it.value().toBool());
            }
        }
    }

    if (data.contains("radio_buttons") && data["radio_buttons"].isObject()) {
        const QJsonObject m = data["radio_buttons"].toObject();
        for (auto it = m.begin(); it != m.end(); ++it) {
            if (!isSerializableName(it.key())) continue;
            if (auto *w = root->findChild<QRadioButton*>(it.key())) {
                if (hasCorteRowAncestor(w)) continue;
                w->setChecked(it.value().toBool());
            }
        }
    }

    if (data.contains("spin_boxes") && data["spin_boxes"].isObject()) {
        const QJsonObject m = data["spin_boxes"].toObject();
        for (auto it = m.begin(); it != m.end(); ++it) {
            if (!isSerializableName(it.key())) continue;
            if (auto *w = root->findChild<QSpinBox*>(it.key())) {
                if (hasCorteRowAncestor(w)) continue;
                w->setValue(it.value().toInt());
            }
        }
    }

    if (data.contains("double_spin_boxes") && data["double_spin_boxes"].isObject()) {
        const QJsonObject m = data["double_spin_boxes"].toObject();
        for (auto it = m.begin(); it != m.end(); ++it) {
            if (!isSerializableName(it.key())) continue;
            if (auto *w = root->findChild<QDoubleSpinBox*>(it.key())) {
                if (hasCorteRowAncestor(w)) continue;
                w->setValue(it.value().toDouble());
            }
        }
    }

    if (data.contains("date_edits") && data["date_edits"].isObject()) {
        const QJsonObject m = data["date_edits"].toObject();
        for (auto it = m.begin(); it != m.end(); ++it) {
            if (!isSerializableName(it.key())) continue;
            if (auto *w = root->findChild<QDateEdit*>(it.key())) {
                if (hasCorteRowAncestor(w)) continue;
                const QDate d = QDate::fromString(it.value().toString(), Qt::ISODate);
                if (d.isValid()) w->setDate(d);
            }
        }
    }
}

// ------------------------------------------------------------
// SUPER CARPETA (Proyecto)
// ------------------------------------------------------------
QString CalicataWindow::baseProjectsPath() const
{
    const QString homePath = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    return homePath + "/InGePlusProyectos";
}

QString CalicataWindow::findProjectMetaFileUp(const QString &startDir) const
{
    if (startDir.trimmed().isEmpty())
        return QString();

    QDir dir(startDir);
    if (!dir.exists())
        return QString();

    const QString base = QDir(baseProjectsPath()).absolutePath();

    while (true) {
        const QString candidate1 = dir.absoluteFilePath(kProjectMetaFilePrimary);
        if (QFileInfo::exists(candidate1))
            return candidate1;

        const QString candidate2 = dir.absoluteFilePath(kProjectMetaFileLegacy);
        if (QFileInfo::exists(candidate2))
            return candidate2;

        const QString current = dir.absolutePath();
        if (QDir::cleanPath(current) == QDir::cleanPath(base))
            break;

        if (!dir.cdUp())
            break;
    }

    return QString();
}

QString CalicataWindow::readProyectoFromMetaFile(const QString &metaFilePath) const
{
    if (metaFilePath.trimmed().isEmpty())
        return QString();

    QFile f(metaFilePath);
    if (!f.open(QIODevice::ReadOnly))
        return QString();

    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &err);
    f.close();

    if (err.error != QJsonParseError::NoError || !doc.isObject())
        return QString();

    const QJsonObject obj = doc.object();

    const QString projectName = obj.value("project_name").toString().trimmed();
    if (!projectName.isEmpty())
        return projectName;

    const QString tsProject = obj.value("timestamp_project").toString().trimmed();
    if (!tsProject.isEmpty())
        return tsProject;

    const QString legacyProyecto = obj.value("proyecto").toString().trimmed();
    if (!legacyProyecto.isEmpty())
        return legacyProyecto;

    return obj.value("project").toString().trimmed();
}

QString CalicataWindow::projectNameForPath(const QString &fileOrDirPath) const
{
    if (fileOrDirPath.trimmed().isEmpty())
        return QString();

    QFileInfo info(fileOrDirPath);
    QString dirPath = info.isDir() ? info.absoluteFilePath()
                                   : info.dir().absolutePath();

    const QString meta = findProjectMetaFileUp(dirPath);
    if (meta.isEmpty())
        return QString();

    return readProyectoFromMetaFile(meta);
}

void CalicataWindow::ensureProyectoFromContext(const QString &preferredPath)
{
    if (!m_timestamp.proyecto.trimmed().isEmpty())
        return;

    QString ctx = preferredPath.trimmed();
    if (ctx.isEmpty()) {
        if (!m_currentFilePath.isEmpty()) {
            ctx = m_currentFilePath;
        } else {
            const QString prop = property("calicataFilePath").toString();
            if (!prop.isEmpty())
                ctx = prop;
        }
    }

    const QString proj = projectNameForPath(ctx);
    if (!proj.isEmpty())
        m_timestamp.proyecto = proj;
}

// ------------------------------------------------------------
// NUEVO: projectRoot / recursosRoot / resolver recursos
// ------------------------------------------------------------
QString CalicataWindow::projectRootForPath(const QString &fileOrDirPath) const
{
    if (fileOrDirPath.trimmed().isEmpty())
        return QString();

    QFileInfo info(fileOrDirPath);
    QString dirPath = info.isDir() ? info.absoluteFilePath()
                                   : info.dir().absolutePath();

    const QString meta = findProjectMetaFileUp(dirPath);
    if (meta.isEmpty())
        return QString();

    return QFileInfo(meta).dir().absolutePath();
}

QString CalicataWindow::resourcesRootForContext(const QString &contextFilePath) const
{
    const QString userRoot = userRootFromContextPath(contextFilePath, baseProjectsPath());
    if (!userRoot.isEmpty()) {
        const QString p = QDir(userRoot).absoluteFilePath("Recursos"); // <USUARIO>/Recursos
        QDir().mkpath(p); // ✅ aquí sí creamos (pero dentro del usuario)
        return p;
    }

    // Fallback legacy SOLO si existe (no crear)
    const QString legacy = legacyGlobalRecursosDir();
    if (QDir(legacy).exists())
        return legacy;

    return {};
}



QString CalicataWindow::resolveResourceAbsPath(const QString &maybeRelPath,
                                               const QString &contextFilePath) const
{
    if (maybeRelPath.startsWith(":/"))   return maybeRelPath;
    if (maybeRelPath.startsWith("qrc:/")) return maybeRelPath.mid(3);

    QString rel = QDir::cleanPath(QDir::fromNativeSeparators(maybeRelPath.trimmed()));
    if (rel.isEmpty()) return QString();

    if (QDir::isAbsolutePath(rel))
        return rel;

    // --- Soportar "Recursos/..." y también solo "archivo.png"
    QString stripped = rel;
    if (stripped.startsWith("Recursos/", Qt::CaseInsensitive))
        stripped = stripped.mid(QString("Recursos/").size());
    else if (stripped.startsWith("recursos/", Qt::CaseInsensitive))
        stripped = stripped.mid(QString("recursos/").size());

    // Candidatos en orden (primero los más “correctos” para tu caso)
    QStringList candidates;

    // A) Base: .../InGePlusProyectos + "Recursos/Logo.png"  ✅ (tu captura)
    const QString base = baseProjectsPath(); // .../InGePlusProyectos
    candidates << QDir(base).absoluteFilePath(rel);

    // B) Carpeta Recursos directa: .../InGePlusProyectos/Recursos + "Logo.png"
    const QString recursosRoot = resourcesRootForContext(contextFilePath); // .../InGePlusProyectos/Recursos
    if (!recursosRoot.isEmpty()) {       // por si rel ya venía sin "Recursos/"
        candidates << QDir(recursosRoot).absoluteFilePath(stripped);  // ✅ si rel venía "Recursos/..."
    }

    // C) Proyecto (por si algún día guardas rutas relativas al proyecto)
    const QString projRoot = projectRootForPath(contextFilePath);
    if (!projRoot.isEmpty()) {
        candidates << QDir(projRoot).absoluteFilePath(rel);
        candidates << QDir(projRoot).absoluteFilePath(stripped);
    }

    // D) Editable root (por compatibilidad)
    const QString editRoot = editableRootForPath(contextFilePath);
    if (!editRoot.isEmpty()) {
        candidates << QDir(editRoot).absoluteFilePath(rel);
        candidates << QDir(editRoot).absoluteFilePath(stripped);
    }

    // E) Carpeta del archivo
    candidates << QDir(QFileInfo(contextFilePath).dir().absolutePath()).absoluteFilePath(rel);
    candidates << QDir(QFileInfo(contextFilePath).dir().absolutePath()).absoluteFilePath(stripped);

    for (QString c : candidates) {
        c = QDir::cleanPath(QDir::fromNativeSeparators(c));
        if (QFileInfo::exists(c))
            return c;
    }

    return QString();
}




bool CalicataWindow::pickLogoFromResources(bool mtc)
{
    const QString ctx = !m_currentFilePath.isEmpty()
    ? m_currentFilePath
    : m_lastImagePickDir;

    if (ctx.isEmpty()) {
        QMessageBox::warning(this, "Logo",
                             "Primero abre o guarda la calicata para definir la carpeta de contexto.");
        return false;
    }

    QString recursosAbs = resourcesRootForContext(ctx);
    if (recursosAbs.isEmpty()) {
        QMessageBox::warning(this, "Logo",
                             "No se pudo ubicar la carpeta Recursos del usuario.");
        return false;
    }


    qDebug() << "recursosAbs =" << recursosAbs;
    qDebug() << "exists =" << QDir(recursosAbs).exists();
    qDebug() << "files =" << QDir(recursosAbs).entryList(QStringList() << "*.png" << "*.jpg" << "*.jpeg" << "*.bmp" << "*.webp", QDir::Files);


    ResourcesImagePickerDialog dlg(recursosAbs,
                                   mtc ? "Seleccionar logo MTC (Recursos)"
                                       : "Seleccionar logo del Proyecto (Recursos)",
                                   this);

    if (dlg.exec() != QDialog::Accepted)
        return false;

    const QString abs = dlg.selectedAbsPath();

    if (abs.isEmpty())
        return false;

    QPixmap pix(abs);
    if (pix.isNull()) {
        QMessageBox::warning(this, "Logo", "No se pudo cargar la imagen seleccionada.");
        return false;
    }

    // guarda relpath contra el root más estable disponible
    QString rel = QDir(recursosAbs).relativeFilePath(abs);
    rel = QDir::cleanPath(QDir::fromNativeSeparators(rel));

    // debería NO empezar con ".." porque el dialog está root en recursosAbs, pero igual aseguramos
    if (!rel.isEmpty() && !rel.startsWith(".."))
        rel = QString("Recursos/%1").arg(rel);
    else
        rel = QDir::cleanPath(abs); // fallback extremo




    if (mtc) {
        m_logoMtcPix = pix;
        m_logoMtcRelPath = rel;
        m_logoMtcIsCustom = true;
        setButtonPixmap(ui->btnLogoMTC, pix, true);
    } else {
        m_logoProyectoPix = pix;
        m_logoProyectoRelPath = rel;
        m_logoProyectoIsCustom = true;
        setButtonPixmap(ui->btnLogoProyecto, pix, true);
    }

    return true;
}


// ------------------------------------------------------------
// Editable folder helpers (cache JPG)
// ------------------------------------------------------------
QString CalicataWindow::pickStartDir(bool forPhotos) const
{
    if (!m_lastImagePickDir.isEmpty() && QDir(m_lastImagePickDir).exists())
        return m_lastImagePickDir;

    QString ctx = !m_currentFilePath.isEmpty() ? m_currentFilePath : property("calicataFilePath").toString();

    const QString editableRoot = editableRootForPath(ctx);
    if (forPhotos && !editableRoot.isEmpty()) {
        const QString stem = calicataStemForFile(ctx.isEmpty() ? "CT" : ctx);
        const QString d1 = QDir(editableRoot).filePath(QString("%1/%2").arg(kEditablePhotosFolder, stem));
        if (QDir(d1).exists()) return d1;

        const QString d2 = QDir(editableRoot).filePath(kEditablePhotosFolder);
        if (QDir(d2).exists()) return d2;

        return editableRoot;
    }

    if (!ctx.isEmpty()) return QFileInfo(ctx).dir().absolutePath();
    return baseProjectsPath();
}

bool CalicataWindow::isPathInsideEditableFotos(const QString& absPath, const QString& contextFilePath) const
{
    const QString editableRoot = editableRootForPath(contextFilePath);
    if (editableRoot.isEmpty()) return false;

    const QString fotosRoot = QDir(editableRoot).absoluteFilePath(kEditablePhotosFolder);
    const QString a = QDir::cleanPath(absPath);
    const QString b = QDir::cleanPath(fotosRoot) + QDir::separator();
    return a.startsWith(b, Qt::CaseInsensitive);
}

QString CalicataWindow::findEditableMetaFileUp(const QString &startDir) const
{
    if (startDir.trimmed().isEmpty())
        return QString();

    QDir dir(startDir);
    if (!dir.exists())
        return QString();

    const QString base = QDir(baseProjectsPath()).absolutePath();

    while (true) {
        const QString candidate = dir.absoluteFilePath(kEditableMetaFile);
        if (QFileInfo::exists(candidate))
            return candidate;

        const QString current = dir.absolutePath();
        if (QDir::cleanPath(current) == QDir::cleanPath(base))
            break;

        if (!dir.cdUp())
            break;
    }

    return QString();
}

QString CalicataWindow::editableRootForPath(const QString& contextPath) const
{
    QString dirPath = QFileInfo(contextPath).isDir()
    ? contextPath
    : QFileInfo(contextPath).dir().absolutePath();

    QDir d(dirPath);
    while (d.exists()) {
        const QString meta = d.absoluteFilePath(kEditableMetaFile);
        if (QFileInfo::exists(meta))
            return d.absolutePath();

        if (!d.cdUp()) break;
    }
    return {};
}


QString CalicataWindow::loadExcelTitleFromEditableMeta(const QString& contextPath) const
{
    const QString root = editableRootForPath(contextPath);
    if (root.isEmpty()) return {};

    QFile f(QDir(root).absoluteFilePath(kEditableMetaFile));
    if (!f.open(QIODevice::ReadOnly)) return {};

    QJsonParseError pe{};
    const QJsonDocument jd = QJsonDocument::fromJson(f.readAll(), &pe);
    if (pe.error != QJsonParseError::NoError || !jd.isObject()) return {};

    return jd.object().value("excel_title").toString();
}


bool CalicataWindow::ensurePhotosDir(const QString &editableRoot) const
{
    if (editableRoot.trimmed().isEmpty())
        return false;

    QDir d(editableRoot);
    return d.mkpath(kEditablePhotosFolder);
}

QString CalicataWindow::calicataStemForFile(const QString &savingFilePath) const
{
    QString name = QFileInfo(savingFilePath).fileName();

    const QString suf = ".calicata.json";
    if (name.endsWith(suf, Qt::CaseInsensitive)) {
        name.chop(suf.size());
        return name;
    }
    return QFileInfo(savingFilePath).completeBaseName();
}

bool CalicataWindow::savePixmapAsJpg(const QPixmap &pix, const QString &absJpgPath, int quality) const
{
    if (pix.isNull() || absJpgPath.trimmed().isEmpty())
        return false;

    QImage img = pix.toImage();

    if (img.hasAlphaChannel()) {
        QImage rgb(img.size(), QImage::Format_RGB32);
        rgb.fill(Qt::white);
        QPainter p(&rgb);
        p.drawImage(0, 0, img);
        p.end();
        img = rgb;
    } else if (img.format() != QImage::Format_RGB32 && img.format() != QImage::Format_RGB888) {
        img = img.convertToFormat(QImage::Format_RGB32);
    }

    QDir().mkpath(QFileInfo(absJpgPath).dir().absolutePath());
    return img.save(absJpgPath, "JPG", quality);
}

QString CalicataWindow::resolveImageAbsPath(const QString &maybeRelPath, const QString &contextFilePath) const
{
    if (maybeRelPath.trimmed().isEmpty())
        return QString();

    QFileInfo fi(maybeRelPath);
    if (fi.isAbsolute())
        return maybeRelPath;

    const QString editableRoot = editableRootForPath(contextFilePath);
    if (!editableRoot.isEmpty()) {
        return QDir(editableRoot).absoluteFilePath(maybeRelPath);
    }

    const QString baseDir = QFileInfo(contextFilePath).dir().absolutePath();
    return QDir(baseDir).absoluteFilePath(maybeRelPath);
}


bool CalicataWindow::saveExcelTitleToEditableMeta(const QString& contextPath,
                                                  const QString& title) const
{
    const QString root = editableRootForPath(contextPath);
    if (root.isEmpty()) return false;

    const QString metaPath = QDir(root).absoluteFilePath(kEditableMetaFile);

    QJsonObject o;
    {
        QFile rf(metaPath);
        if (rf.open(QIODevice::ReadOnly)) {
            QJsonParseError pe{};
            const QJsonDocument jd = QJsonDocument::fromJson(rf.readAll(), &pe);
            if (pe.error == QJsonParseError::NoError && jd.isObject())
                o = jd.object();
        }
    }

    // asegurar campos base por si el archivo estaba incompleto
    if (!o.contains("version"))    o["version"] = 1;
    if (!o.contains("type"))       o["type"] = "editable";
    if (!o.contains("photos_dir")) o["photos_dir"] = "fotos";

    o["excel_title"] = title;

    QSaveFile sf(metaPath);
    if (!sf.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;

    sf.write(QJsonDocument(o).toJson(QJsonDocument::Indented));
    return sf.commit();
}


// ------------------------------------------------------------
// NUEVO: helpers ToolPick cache-only
// ------------------------------------------------------------
QString CalicataWindow::cachedPhotosTypeFolderAbs(int idx, const QString &contextFilePath) const
{
    const QString editableRoot = editableRootForPath(contextFilePath);
    if (editableRoot.isEmpty()) return QString();

    const QString stem = calicataStemForFile(contextFilePath.isEmpty() ? "CT" : contextFilePath);
    const QString folder = sanitizeFsName(photoFolderDisplayName(idx));

    return QDir(editableRoot).absoluteFilePath(
        QString("%1/%2/%3").arg(kEditablePhotosFolder, stem, folder)
        );
}

QString CalicataWindow::fotoRelPathForIdx(int idx) const
{
    if (idx == 1) return m_foto1RelPath;
    if (idx == 2) return m_foto2RelPath;
    if (idx == 3) return m_foto3RelPath;
    return QString();
}

void CalicataWindow::setFotoRelPathForIdx(int idx, const QString &rel)
{
    if (idx == 1) m_foto1RelPath = rel;
    if (idx == 2) m_foto2RelPath = rel;
    if (idx == 3) m_foto3RelPath = rel;
}

bool CalicataWindow::pickCachedPhotoForIdx(int idx)
{
    QString ctx = !m_currentFilePath.isEmpty() ? m_currentFilePath : property("calicataFilePath").toString();
    if (ctx.trimmed().isEmpty()) {
        QMessageBox::information(this, tr("Sin contexto"),
                                 tr("Aún no hay una ficha cargada/activa.\n"
                                    "Guarda o abre una ficha antes de seleccionar fotos desde cache."));
        return false;
    }

    const QString editableRoot = editableRootForPath(ctx);
    if (editableRoot.isEmpty()) {
        QMessageBox::information(this, tr("Carpeta editable no encontrada"),
                                 tr("No se encontró una carpeta editable (.ingep_editable.json).\n"
                                    "El ToolPick solo puede seleccionar imágenes del cache interno."));
        return false;
    }

    const QString folderAbs = cachedPhotosTypeFolderAbs(idx, ctx);
    if (folderAbs.isEmpty() || !QDir(folderAbs).exists()) {
        QMessageBox::information(this, tr("Sin fotos en cache"),
                                 tr("No existe la carpeta de fotos en cache para este tipo.\n"
                                    "Primero genera/guarda fotos con el botón grande (cámara) para que aparezcan aquí."));
        return false;
    }

    CacheImagePickerDialog dlg(folderAbs,
                               tr("Seleccionar imagen del cache"),
                               this);

    if (dlg.exec() != QDialog::Accepted)
        return false;

    const QString abs = dlg.selectedAbsPath().trimmed();
    if (abs.isEmpty() || !QFileInfo::exists(abs))
        return false;

    // --- Seguridad: debe estar dentro del cache (folderAbs) ---
    QString selectedAbs = QDir::fromNativeSeparators(abs);

    if (QDir::isRelativePath(selectedAbs)) {
        selectedAbs = QDir(folderAbs).absoluteFilePath(selectedAbs);
        selectedAbs = QDir::fromNativeSeparators(selectedAbs);
    }

    QString cacheAbs = QDir::fromNativeSeparators(QFileInfo(folderAbs).absoluteFilePath());

    selectedAbs = QDir::cleanPath(selectedAbs);
    cacheAbs    = QDir::cleanPath(cacheAbs);

#ifdef Q_OS_WIN
    selectedAbs = selectedAbs.toLower();
    cacheAbs    = cacheAbs.toLower();
#endif

    if (!cacheAbs.endsWith('/')) cacheAbs += '/';
    if (!selectedAbs.startsWith(cacheAbs)) {
        QMessageBox::warning(this, tr("Selección inválida"),
                             tr("La imagen seleccionada no está dentro del cache de fotos de la aplicación."));
        return false;
    }

    QPixmap pix(abs);
    if (pix.isNull()) {
        QMessageBox::warning(this, tr("Error"),
                             tr("No se pudo cargar la imagen seleccionada."));
        return false;
    }

    // Guardar relpath (editableRoot-relative) para NO re-guardar en el save
    const QString rel = QDir(editableRoot).relativeFilePath(abs);

    if (idx == 1) m_foto1Pix = pix;
    if (idx == 2) m_foto2Pix = pix;
    if (idx == 3) m_foto3Pix = pix;

    setFotoRelPathForIdx(idx, QDir::cleanPath(rel));

    refreshAllButtonPixmaps();
    marcarComoModificado();
    return true;
}

// Renombra el archivo actual _001 a _002, _003, ... antes de escribir el nuevo _001
bool CalicataWindow::backupIfExists(const QString& destPath) const
{
    if (!QFileInfo::exists(destPath)) return true;

    QFileInfo fi(destPath);
    const QString dir = fi.absolutePath();
    const QString ext = fi.suffix();
    const QString base = fi.completeBaseName();

    QRegularExpression re(R"((.*)_([0-9]{3})$)");
    QRegularExpressionMatch m = re.match(base);

    QString prefix = base;
    int cur = 1;
    if (m.hasMatch()) {
        prefix = m.captured(1);
        cur = m.captured(2).toInt();
    }

    int n = qMax(2, cur + 1);
    QString backupPath;

    for (; n < 1000; ++n) {
        const QString num = QString::number(n).rightJustified(3, '0');
        backupPath = QDir(dir).filePath(QString("%1_%2.%3").arg(prefix, num, ext));
        if (!QFileInfo::exists(backupPath))
            break;
    }

    if (backupPath.isEmpty())
        return false;

    if (QFile::rename(destPath, backupPath)) return true;

    if (QFile::copy(destPath, backupPath)) {
        QFile::remove(destPath);
        return true;
    }

    return false;
}

QString CalicataWindow::fotoPrefixForIdx(int idx) const
{
    switch (idx) {
    case 1: return "Foto_ZE_Calicata";
    case 2: return "Foto_Calicata_Interior";
    case 3: return "Foto_Acopios";
    default: return QString("Foto_%1").arg(idx);
    }
}

// Devuelve el path ABS al archivo principal _001 para idx
QString CalicataWindow::nextFotoPathForIdx(int idx) const
{
    QString ctx = !m_currentFilePath.isEmpty() ? m_currentFilePath : property("calicataFilePath").toString();
    const QString editableRoot = editableRootForPath(ctx);
    if (editableRoot.isEmpty()) return QString();

    const QString stem = calicataStemForFile(ctx.isEmpty() ? "CT" : ctx);
    const QString folder = sanitizeFsName(photoFolderDisplayName(idx));
    const QString prefix = fotoPrefixForIdx(idx);

    QDir d(editableRoot);
    const QString rel = QString("%1/%2/%3/%4_001.jpg")
                            .arg(kEditablePhotosFolder, stem, folder, prefix);
    return d.absoluteFilePath(rel);
}

// ✅ Guarda fotos:
// - si fotoXRelPath existe (ToolPick), solo referencia fotoX_path (NO re-guardar)
// - si no hay relPath, guarda pixmap en _001 (con backup)
bool CalicataWindow::persistImagesToCacheJpg(const QString &savingFilePath, QJsonObject &imgs) const
{
    const QString editableRoot = editableRootForPath(savingFilePath);
    if (editableRoot.isEmpty())
        return false;

    if (!ensurePhotosDir(editableRoot))
        return false;

    const QString stem = calicataStemForFile(savingFilePath);

    const QString baseRel = QString("%1/%2").arg(kEditablePhotosFolder, stem);
    QDir d(editableRoot);
    if (!d.mkpath(baseRel))
        return false;

    auto writeOne = [&](int idx, const QString &keyBase, const QPixmap &pix, const QString &pickedRel) -> bool {

        // 1) Si viene de ToolPick y el archivo existe, NO re-guardar
        if (!pickedRel.trimmed().isEmpty()) {
            const QString relClean = QDir::cleanPath(pickedRel);
            const QString absPicked = d.absoluteFilePath(relClean);

            const QString folder = sanitizeFsName(photoFolderDisplayName(idx));
            QString expectedPrefix = QDir::cleanPath(QString("%1/%2/%3").arg(kEditablePhotosFolder, stem, folder));
            expectedPrefix = QDir::fromNativeSeparators(expectedPrefix);
            if (!expectedPrefix.endsWith('/')) expectedPrefix += '/';

            QString relNorm = QDir::fromNativeSeparators(QDir::cleanPath(relClean));
#ifdef Q_OS_WIN
            relNorm = relNorm.toLower();
            expectedPrefix = expectedPrefix.toLower();
#endif

            if (QFileInfo::exists(absPicked) && relNorm.startsWith(expectedPrefix)) {
                imgs[keyBase + "_path"] = relClean;
                return true;
            }
            // Si no cumple, cae al modo "guardar _001"
        }

        // 2) Si no hay pix, limpia path
        if (pix.isNull()) {
            imgs[keyBase + "_path"] = QString();
            return true;
        }

        // 3) Guardar a _001 con backups
        const QString folder = sanitizeFsName(photoFolderDisplayName(idx));
        const QString prefix = fotoPrefixForIdx(idx);

        const QString typeRel = QString("%1/%2").arg(baseRel, folder);
        if (!d.mkpath(typeRel))
            return false;

        const QString rel = QString("%1/%2_001.jpg").arg(typeRel, prefix);
        const QString abs = d.absoluteFilePath(rel);

        if (!backupIfExists(abs))
            return false;

        if (!savePixmapAsJpg(pix, abs, 90))
            return false;

        imgs[keyBase + "_path"] = rel;
        return true;
    };

    imgs["storage"] = "editable_jpg_v2";
    imgs["photos_dir"] = QString(kEditablePhotosFolder);
    imgs["photos_ct"] = stem;

    if (!writeOne(1, "foto1", m_foto1Pix, m_foto1RelPath)) return false;
    if (!writeOne(2, "foto2", m_foto2Pix, m_foto2RelPath)) return false;
    if (!writeOne(3, "foto3", m_foto3Pix, m_foto3RelPath)) return false;

    return true;
}

// ------------------------------------------------------------
// Icon tint helpers (para ToolButtons)
// ------------------------------------------------------------
static QIcon tintedIcon(const QIcon& base, const QColor& color, const QSize& size)
{
    const QSize useSize = (size.isValid() ? size : QSize(16,16));
    QPixmap pm = base.pixmap(useSize, QIcon::Normal, QIcon::Off);
    if (pm.isNull())
        return base;

    QImage img = pm.toImage().convertToFormat(QImage::Format_ARGB32_Premultiplied);
    QPainter p(&img);
    p.setCompositionMode(QPainter::CompositionMode_SourceIn);
    p.fillRect(img.rect(), color);
    p.end();

    return QIcon(QPixmap::fromImage(img));
}

class IconHoverTintFilter : public QObject
{
public:
    IconHoverTintFilter(QAbstractButton* btn,
                        const QIcon& base,
                        const QSize& size,
                        const QColor& normal,
                        const QColor& hover,
                        const QColor& pressed = QColor())
        : QObject(btn),
        m_btn(btn),
        m_base(base),
        m_size(size),
        m_normal(normal),
        m_hover(hover),
        m_pressed(pressed.isValid() ? pressed : hover)
    {
        apply(m_normal);
    }

protected:
    bool eventFilter(QObject* obj, QEvent* ev) override
    {
        if (obj != m_btn || !m_btn)
            return false;

        switch (ev->type()) {
        case QEvent::Enter:
            apply(m_hover);
            break;
        case QEvent::Leave:
            apply(m_normal);
            break;
        case QEvent::MouseButtonPress:
            apply(m_pressed);
            break;
        case QEvent::MouseButtonRelease:
            apply(m_btn->underMouse() ? m_hover : m_normal);
            break;
        default:
            break;
        }
        return false;
    }

private:
    void apply(const QColor& c)
    {
        if (!m_btn) return;
        m_btn->setIcon(tintedIcon(m_base, c, m_size));
        m_btn->setIconSize(m_size);
    }

    QPointer<QAbstractButton> m_btn;
    QIcon  m_base;
    QSize  m_size;
    QColor m_normal;
    QColor m_hover;
    QColor m_pressed;
};

class PhotoPlaceholderStateFilter : public QObject
{
public:
    PhotoPlaceholderStateFilter(QPushButton* btn,
                                const QIcon& darkIcon,
                                const QIcon& whiteIcon,
                                const QSize& size)
        : QObject(btn),
        m_btn(btn),
        m_darkIcon(darkIcon),
        m_whiteIcon(whiteIcon),
        m_size(size)
    {
        applyDark();
    }

protected:
    bool eventFilter(QObject* obj, QEvent* ev) override
    {
        if (obj != m_btn || !m_btn)
            return false;

        if (!m_btn->property("_isPhotoPlaceholder").toBool())
            return false;

        switch (ev->type()) {
        case QEvent::Enter:
            applyDark();
            break;

        case QEvent::Leave:
            m_pressed = false;
            applyDark();
            break;

        case QEvent::MouseButtonPress:
            m_pressed = true;
            applyWhite();
            break;

        case QEvent::MouseButtonRelease:
            m_pressed = false;
            applyDark();
            break;

        default:
            break;
        }

        return false;
    }

private:
    void applyDark()
    {
        if (!m_btn) return;
        m_btn->setIcon(m_darkIcon);
        m_btn->setIconSize(m_size);
        m_btn->setText("");
    }

    void applyWhite()
    {
        if (!m_btn) return;
        m_btn->setIcon(m_whiteIcon);
        m_btn->setIconSize(m_size);
        m_btn->setText("");
    }

    QPointer<QPushButton> m_btn;
    QIcon m_darkIcon;
    QIcon m_whiteIcon;
    QSize m_size;
    bool m_pressed = false;
};
// ------------------------------------------------------------
// Pintar pixmap en botón
// ------------------------------------------------------------
void CalicataWindow::setButtonPixmap(QPushButton *btn, const QPixmap &pix, bool markDirty)
{
    if (!btn) return;

    if (pix.isNull()) {
        if (markDirty) marcarComoModificado();
        return;
    }

    QSize target = btn->size() - QSize(8, 8);
    if (target.width() <= 0) target.setWidth(1);
    if (target.height() <= 0) target.setHeight(1);

    QPixmap scaled = pix.scaled(target, Qt::KeepAspectRatio, Qt::SmoothTransformation);

    btn->setProperty("_isPhotoPlaceholder", false);
    btn->setIcon(QIcon(scaled));
    btn->setIconSize(target);
    btn->setText(QString());

    if (markDirty) marcarComoModificado();
}
void CalicataWindow::setDefaultLogoPlaceholder(QPushButton *btn, const QIcon &ico, const QString &fallbackText)
{
    if (!btn) return;

    QSize target = btn->size() - QSize(8, 8);
    if (target.width() <= 0) target.setWidth(1);
    if (target.height() <= 0) target.setHeight(1);

    if (!ico.isNull()) {
        btn->setIcon(ico);
        btn->setIconSize(target);
        btn->setText("");
    } else {
        btn->setIcon(QIcon());
        btn->setText(fallbackText);
    }
}

static void setPhotoPlaceholder(QPushButton* btn)
{
    if (!btn) return;

    QIcon camDark(":/icons/images/camera_thin_dark.svg");
    QIcon camWhite(":/icons/images/camera_thin_white.svg");

    if (camDark.isNull()) {
        btn->setIcon(QIcon());
        btn->setText("");
        return;
    }

    QSize sz = btn->iconSize();
    if (!sz.isValid() || sz.width() <= 0 || sz.height() <= 0)
        sz = QSize(180, 180);

    btn->setProperty("_isPhotoPlaceholder", true);
    btn->setIcon(camDark);
    btn->setIconSize(sz);
    btn->setText("");

    // instalar filtro solo una vez
    if (!btn->property("_photoStateFilterInstalled").toBool()) {
        btn->setProperty("_photoStateFilterInstalled", true);
        btn->installEventFilter(
            new PhotoPlaceholderStateFilter(
                btn,
                camDark,
                camWhite.isNull() ? camDark : camWhite,
                sz
                )
            );
    }
}

void CalicataWindow::refreshAllButtonPixmaps()
{
    if (!ui) return;

    // ✅ Logo MTC: si hay pix, se muestra, si no, placeholder
    if (!m_logoMtcPix.isNull()) {
        setButtonPixmap(ui->btnLogoMTC, m_logoMtcPix, false);
    } else {
        setDefaultLogoPlaceholder(ui->btnLogoMTC, m_defaultLogoMtcIcon, m_defaultLogoMtcText);
    }

    // ✅ Logo Proyecto
    if (!m_logoProyectoPix.isNull()) {
        setButtonPixmap(ui->btnLogoProyecto, m_logoProyectoPix, false);
    } else {
        setDefaultLogoPlaceholder(ui->btnLogoProyecto, m_defaultLogoProyectoIcon, m_defaultLogoProyectoText);
    }

    // Fotos igual que ya lo tienes
    if (!m_foto1Pix.isNull()) setButtonPixmap(ui->btnFoto1, m_foto1Pix, false);
    else setPhotoPlaceholder(ui->btnFoto1);

    if (!m_foto2Pix.isNull()) setButtonPixmap(ui->btnFoto2, m_foto2Pix, false);
    else setPhotoPlaceholder(ui->btnFoto2);

    if (!m_foto3Pix.isNull()) setButtonPixmap(ui->btnFoto3, m_foto3Pix, false);
    else setPhotoPlaceholder(ui->btnFoto3);
}


static const QDate kEmptyUiDate(1900, 1, 1);

static bool hasRealDate(const QDateEdit *de)
{
    if (!de) return false;
    const QDate d = de->date();
    return d.isValid() && d != de->minimumDate();
}

static void normalizeDateEditState(QDateEdit *de)
{
    if (!de) return;

    const QDate d = de->date();
    if (!d.isValid() || d < de->minimumDate() || d > de->maximumDate()) {
        de->setDate(de->minimumDate()); // queda visualmente como 00/00/0000
    }
}

class DateEditPopupTodayFilter : public QObject
{
public:
    explicit DateEditPopupTodayFilter(QDateEdit *owner)
        : QObject(owner), m_de(owner) {}

protected:
    bool eventFilter(QObject *obj, QEvent *ev) override
    {
        if (obj != m_de || !m_de)
            return QObject::eventFilter(obj, ev);

        switch (ev->type()) {
        case QEvent::MouseButtonPress:
        case QEvent::KeyPress:
        case QEvent::FocusIn:
            if (m_de->calendarPopup() && !hasRealDate(m_de)) {
                QTimer::singleShot(0, m_de, [this]() {
                    if (!m_de || !m_de->calendarWidget()) return;

                    const QDate today = QDate::currentDate();
                    m_de->calendarWidget()->setCurrentPage(today.year(), today.month());
                    // No hacemos setDate(today), porque NO queremos elegir hoy automáticamente.
                });
            }
            break;
        default:
            break;
        }

        return QObject::eventFilter(obj, ev);
    }

private:
    QPointer<QDateEdit> m_de;
};

static void setupStandardDateEdit(QDateEdit *de)
{
    if (!de) return;

    de->setDisplayFormat("dd/MM/yyyy");
    de->setCalendarPopup(true);
    de->setAlignment(Qt::AlignCenter);

    // Fecha centinela para mostrar “vacío”
    de->setMinimumDate(kEmptyUiDate);
    de->setMaximumDate(QDate(2100, 12, 31));
    de->setSpecialValueText("00/00/0000");
    de->setDate(kEmptyUiDate);

    QCalendarWidget *cal = de->calendarWidget();
    if (!cal) {
        cal = new QCalendarWidget(de);
        de->setCalendarWidget(cal);
    }

    cal->setVerticalHeaderFormat(QCalendarWidget::NoVerticalHeader);
    cal->setHorizontalHeaderFormat(QCalendarWidget::ShortDayNames);
    cal->setGridVisible(false);
    cal->setFirstDayOfWeek(Qt::Monday);

    // Opcional: fuerza locale español
    cal->setLocale(QLocale(QLocale::Spanish, QLocale::Peru));

    // IMPORTANTE: darle más ancho al popup
    cal->setMinimumWidth(300);

    if (auto *view = cal->findChild<QTableView*>()) {
        if (auto *hh = view->horizontalHeader()) {
            hh->setSectionResizeMode(QHeaderView::Stretch);
            hh->setMinimumSectionSize(32);
            hh->setDefaultAlignment(Qt::AlignCenter);
            hh->setHighlightSections(false);
        }

        if (auto *vh = view->verticalHeader()) {
            vh->setVisible(false);
        }
    }

    if (!de->property("_popupTodayHooked").toBool()) {
        de->setProperty("_popupTodayHooked", true);
        de->installEventFilter(new DateEditPopupTodayFilter(de));
    }
}


static void ensureValidDateOrToday(QDateEdit *de)
{
    if (!de) return;

    const QDate d = de->date();
    if (!d.isValid() || d.year() < 2000) {
        de->setDate(QDate::currentDate());
    }
}


// ------------------------------------------------------------
// initImageButtons
// ------------------------------------------------------------
void CalicataWindow::initImageButtons()
{
    if (!ui) return;

    if (!m_imageButtonsHooked) {
        m_imageButtonsHooked = true;

        m_defaultLogoMtcIcon      = ui->btnLogoMTC->icon();
        m_defaultLogoProyectoIcon = ui->btnLogoProyecto->icon();

        // NUEVO: guardar textos por defecto
        m_defaultLogoMtcText      = ui->btnLogoMTC->text();
        m_defaultLogoProyectoText = ui->btnLogoProyecto->text();

        const auto UC = Qt::UniqueConnection;

        // ToolPick: selector interno (cache-only)
        if (ui->toolFoto1Pick)  connect(ui->toolFoto1Pick,  &QToolButton::clicked, this, &CalicataWindow::onToolPickFoto1, UC);
        if (ui->toolFoto2Pick)  connect(ui->toolFoto2Pick,  &QToolButton::clicked, this, &CalicataWindow::onToolPickFoto2, UC);
        if (ui->toolFoto3Pick)  connect(ui->toolFoto3Pick,  &QToolButton::clicked, this, &CalicataWindow::onToolPickFoto3, UC);

        // Clear fotos (lambda -> SIN UniqueConnection)
        if (ui->toolFoto1Clear) connect(ui->toolFoto1Clear, &QToolButton::clicked, this, [this]{ clearFoto(1); });
        if (ui->toolFoto2Clear) connect(ui->toolFoto2Clear, &QToolButton::clicked, this, [this]{ clearFoto(2); });
        if (ui->toolFoto3Clear) connect(ui->toolFoto3Clear, &QToolButton::clicked, this, [this]{ clearFoto(3); });

        // Clear logos
        if (ui->toolMTCClear) connect(ui->toolMTCClear, &QToolButton::clicked, this, &CalicataWindow::clearLogoMtc, UC);
        if (ui->toolLPClear)  connect(ui->toolLPClear,  &QToolButton::clicked, this, &CalicataWindow::clearLogoProyecto, UC);
    }

    refreshAllButtonPixmaps();
}

// ------------------------------------------------------------
// Constructor / Destructor
// ------------------------------------------------------------
CalicataWindow::CalicataWindow(QWidget *parent)
    : QMainWindow(parent)
    , ui(new Ui::CalicataWindow)
{
    ui->setupUi(this);

    // --- DateEdit estándar InGe+ ---
    setupStandardDateEdit(ui->dateEdit);
    setupStandardDateEdit(ui->dateEdit_2);

    connect(&m_watcher, &QFileSystemWatcher::fileChanged,
            this, &CalicataWindow::onWatchedPathChanged);

    connect(&m_watcher, &QFileSystemWatcher::directoryChanged,
            this, &CalicataWindow::onWatchedPathChanged);

    auto lay = qobject_cast<QVBoxLayout*>(ui->frameCortesContainer->layout());
    if (!lay) {
        lay = new QVBoxLayout(ui->frameCortesContainer);
        lay->setAlignment(Qt::AlignTop);
    }
    lay->setSpacing(10);
    lay->setContentsMargins(8, 8, 8, 8);

    if (auto layR = ui->frameRight->layout()) {
        layR->setContentsMargins(8, 8, 8, 8);
        layR->setSpacing(10);
    }

    auto setPick = [&](QToolButton* b){
        if (!b) return;
        QIcon base = style()->standardIcon(QStyle::SP_DialogOpenButton);
        b->setIcon(tintedIcon(base, QColor("#6a6a6a"), QSize(16,16)));
        b->setIconSize(QSize(16,16));
        b->installEventFilter(new IconHoverTintFilter(
            b, base, QSize(16,16),
            QColor("#6a6a6a"),
            QColor("#111111"),
            QColor("#ffffff")
            ));
    };

    auto setClear = [&](QToolButton* b){
        if (!b) return;
        QIcon base = style()->standardIcon(QStyle::SP_TitleBarCloseButton);
        b->setIcon(tintedIcon(base, QColor("#555555"), QSize(16,16)));
        b->setIconSize(QSize(16,16));
        b->installEventFilter(new IconHoverTintFilter(
            b, base, QSize(16,16),
            QColor("#555555"),
            QColor("#c62828"),
            QColor("#ffffff")
            ));
    };

    setPick(ui->toolFoto1Pick);  setClear(ui->toolFoto1Clear);
    setPick(ui->toolFoto2Pick);  setClear(ui->toolFoto2Clear);
    setPick(ui->toolFoto3Pick);  setClear(ui->toolFoto3Clear);
    setClear(ui->toolMTCClear);
    setClear(ui->toolLPClear);

    setupCortesDragDrop();

    m_layoutCortes = qobject_cast<QVBoxLayout*>(ui->frameCortesContainer->layout());
    Q_ASSERT(m_layoutCortes);

    auto *filaInicial = new CorteRowWidget(ui->frameCortesContainer);
    m_layoutCortes->addWidget(filaInicial);

    setupIntervalRules(filaInicial);
    setupDeleteRules(filaInicial);

    renumerarCortesYIntervalos(false);

    connect(ui->btnAgregarCorte, &QPushButton::clicked, this, [this]() {

        auto rows = cortes();
        if (!rows.isEmpty()) {
            auto *lastACombo = rows.last()->editA();
            const QString lastATxt = lastACombo ? lastACombo->currentText().trimmed() : QString();

            if (lastATxt.isEmpty()) {
                QMessageBox::information(this, tr("Falta completar intervalo"),
                                         tr("Primero selecciona o escribe el valor 'A' del último corte antes de agregar uno nuevo."));
                return;
            }

            bool okLast = false;
            double lastA = parseDepth(lastATxt, &okLast);
            if (okLast && lastA >= kMaxDepth - 0.0001) {
                QMessageBox::information(this, tr("Máxima profundidad"),
                                         tr("Ya se alcanzó %1 m.\n"
                                            "Si necesitas más cortes, reduce el valor 'A' del último corte.")
                                             .arg(QString::number(kMaxDepth, 'f', 2)));
                return;
            }
        }

        auto *nuevaFila = new CorteRowWidget(ui->frameCortesContainer);
        m_layoutCortes->addWidget(nuevaFila);

        setupIntervalRules(nuevaFila);
        setupDeleteRules(nuevaFila);
        attachDirtySignals(nuevaFila);

        renumerarCortesYIntervalos(true);
        marcarComoModificado();
    });

    m_currentFilePath.clear();
    m_dirty = false;
    m_baseWindowTitle = tr("Ficha de Calicata");
    updateWindowTitle();

    // Timer de auto-guardado (opcional)
    if (!m_autoSaveTimer) {
        m_autoSaveTimer = new QTimer(this);
        m_autoSaveTimer->setInterval(m_autoSaveIntervalMs);
        connect(m_autoSaveTimer, &QTimer::timeout, this, [this](){
            if (!m_autoSaveEnabled) return;
            if (m_loading) return;
            if (!m_dirty) return;
            if (m_currentFilePath.isEmpty()) return;
            guardarEnArchivo(m_currentFilePath, /*interactive=*/false);
        });
    }

    if (!m_historyTimer) {
        m_historyTimer = new QTimer(this);
        m_historyTimer->setSingleShot(true);
        m_historyTimer->setInterval(350); // agrupa cambios cercanos
        connect(m_historyTimer, &QTimer::timeout, this, [this]() {
            captureHistorySnapshot();
        });
    }

    if (ui->txtProgresiva) {
        connect(ui->txtProgresiva, &QLineEdit::textChanged, this, [this](const QString &t){
            if (m_loading) return;
            m_timestamp.calicata = t;
            marcarComoModificado();
        });
    }

    attachDirtySignals(this);
    attachDirtySignals(filaInicial);

    actualizarTimestampDesdeUi();
    ensureProyectoFromContext();

    initImageButtons();
    resetHistoryFromCurrentState();
}

CalicataWindow::~CalicataWindow()
{
    delete ui;
}

QString CalicataWindow::displayName() const
{
    // Si ya hay archivo, el displayName debe ser el nombre real del archivo (sin .calicata.json)
    if (!m_currentFilePath.trimmed().isEmpty()) {
        const QString stem = calicataStemForFile(m_currentFilePath);
        if (!stem.trimmed().isEmpty())
            return stem;
        return QFileInfo(m_currentFilePath).fileName();
    }

    // Si aún no existe archivo, mostramos algo útil (sin “acoplar” al nombre del archivo)
    const QString p = (ui && ui->txtProgresiva) ? ui->txtProgresiva->text().trimmed() : QString();
    return p.isEmpty() ? tr("Sin guardar") : p;
}

QString CalicataWindow::historyContextPath() const
{
    if (!m_currentFilePath.isEmpty())
        return m_currentFilePath;

    const QString prop = property("calicataFilePath").toString().trimmed();
    if (!prop.isEmpty())
        return prop;

    return baseProjectsPath();
}

QByteArray CalicataWindow::makeHistorySnapshot() const
{
    const QString ctx = historyContextPath();
    const QJsonObject root = buildFullJson(ctx);
    return QJsonDocument(root).toJson(QJsonDocument::Compact);
}

bool CalicataWindow::canUndo() const
{
    return m_historyIndex > 0;
}

bool CalicataWindow::canRedo() const
{
    return m_historyIndex >= 0 && m_historyIndex < (m_history.size() - 1);
}

void CalicataWindow::emitUndoRedoAvailability()
{
    emit undoAvailabilityChanged(canUndo());
    emit redoAvailabilityChanged(canRedo());
}

void CalicataWindow::scheduleHistorySnapshot()
{
    if (m_loading || m_historyApplying)
        return;

    if (!m_historyTimer)
        return;

    m_historyTimer->start();
}

void CalicataWindow::captureHistorySnapshot()
{
    if (m_loading || m_historyApplying)
        return;

    if (m_historyTimer && m_historyTimer->isActive())
        m_historyTimer->stop();

    const QByteArray snap = makeHistorySnapshot();
    if (snap.isEmpty())
        return;

    // Si el estado actual ya es igual al snapshot actual, solo actualiza dirty
    if (m_historyIndex >= 0 && m_historyIndex < m_history.size()) {
        HistoryEntry &cur = m_history[m_historyIndex];
        if (cur.json == snap) {
            cur.dirty = m_dirty;
            emitUndoRedoAvailability();
            return;
        }
    }

    // Si hubo undo y luego editaste, corta la rama redo
    while (m_history.size() - 1 > m_historyIndex)
        m_history.removeLast();

    HistoryEntry e;
    e.json = snap;
    e.dirty = m_dirty;

    m_history.push_back(e);
    m_historyIndex = m_history.size() - 1;

    emitUndoRedoAvailability();
}

void CalicataWindow::resetHistoryFromCurrentState()
{
    m_history.clear();
    m_historyIndex = -1;

    HistoryEntry e;
    e.json = makeHistorySnapshot();
    e.dirty = m_dirty;

    if (!e.json.isEmpty()) {
        m_history.push_back(e);
        m_historyIndex = 0;
    }

    emitUndoRedoAvailability();
}

void CalicataWindow::restoreHistoryIndex(int index)
{
    if (index < 0 || index >= m_history.size())
        return;

    QJsonParseError err{};
    const QJsonDocument doc = QJsonDocument::fromJson(m_history[index].json, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject())
        return;

    m_historyApplying = true;
    const bool prevLoading = m_loading;
    m_loading = true;

    applyFullJson(doc.object(), historyContextPath());

    m_loading = prevLoading;
    m_historyApplying = false;

    m_historyIndex = index;
    setDirtyInternal(m_history[index].dirty);

    refreshAllButtonPixmaps();
    emit displayNameChanged(displayName());
    emitUndoRedoAvailability();
}

void CalicataWindow::undoForm()
{
    if (canUndo())
        restoreHistoryIndex(m_historyIndex - 1);
}

void CalicataWindow::redoForm()
{
    if (canRedo())
        restoreHistoryIndex(m_historyIndex + 1);
}

QString CalicataWindow::utmZona() const
{
    return (ui && ui->txtZona) ? ui->txtZona->text().trimmed() : QString();
}

QString CalicataWindow::utmX() const
{
    return (ui && ui->txtUTMX) ? ui->txtUTMX->text().trimmed() : QString();
}

QString CalicataWindow::utmY() const
{
    return (ui && ui->txtUTMY) ? ui->txtUTMY->text().trimmed() : QString();
}

void CalicataWindow::applyExternalUtm(const QString& zona,
                                      const QString& x,
                                      const QString& y,
                                      const QString& altitud,
                                      bool markDirty)
{
    if (!ui) return;

    // Evita que attachDirtySignals dispare varias veces mientras escribimos
    QSignalBlocker b1(ui->txtZona);
    QSignalBlocker b2(ui->txtUTMX);
    QSignalBlocker b3(ui->txtUTMY);

    if (ui->txtZona) ui->txtZona->setText(zona.trimmed());
    if (ui->txtUTMX) ui->txtUTMX->setText(x.trimmed());
    if (ui->txtUTMY) ui->txtUTMY->setText(y.trimmed());

    // Mantener sincronizado el estado global de ubicación
    g_ubicacionData.sistemaCoord = "UTM";
    g_ubicacionData.zona = zona.trimmed();
    g_ubicacionData.x = x.trimmed();
    g_ubicacionData.y = y.trimmed();

    if (!altitud.trimmed().isEmpty())
        g_ubicacionData.altitud = altitud.trimmed();

    g_ubicacionData.hora = QTime::currentTime().toString("HH:mm:ss");

    actualizarTimestampDesdeUi();

    if (markDirty)
        marcarComoModificado();
}

// ------------------------------------------------------------
// ToolPick slots (cache-only)
// ------------------------------------------------------------
void CalicataWindow::onToolPickFoto1() { pickCachedPhotoForIdx(1); }
void CalicataWindow::onToolPickFoto2() { pickCachedPhotoForIdx(2); }
void CalicataWindow::onToolPickFoto3() { pickCachedPhotoForIdx(3); }

// ------------------------------------------------------------
// Dirty tracking automático
// ------------------------------------------------------------
void CalicataWindow::attachDirtySignals(QWidget *root)
{
    if (!root) return;

    auto hook = [this](QObject *obj){
        if (!obj) return false;
        if (obj->property("_dirtyHooked").toBool())
            return false;
        obj->setProperty("_dirtyHooked", true);
        return true;
    };

    for (auto *w : root->findChildren<QLineEdit*>()) {
        if (!isSerializableName(w->objectName())) continue;
        if (!hook(w)) continue;
        connect(w, &QLineEdit::textChanged, this, [this](){ marcarComoModificado(); });
    }
    for (auto *w : root->findChildren<QPlainTextEdit*>()) {
        if (!isSerializableName(w->objectName())) continue;
        if (!hook(w)) continue;
        connect(w, &QPlainTextEdit::textChanged, this, [this](){ marcarComoModificado(); });
    }
    for (auto *w : root->findChildren<QTextEdit*>()) {
        if (!isSerializableName(w->objectName())) continue;
        if (!hook(w)) continue;
        connect(w, &QTextEdit::textChanged, this, [this](){ marcarComoModificado(); });
    }
    for (auto *w : root->findChildren<QComboBox*>()) {
        if (!isSerializableName(w->objectName())) continue;
        if (!hook(w)) continue;
        connect(w, &QComboBox::currentTextChanged, this, [this](){ marcarComoModificado(); });
    }
    for (auto *w : root->findChildren<QCheckBox*>()) {
        if (!isSerializableName(w->objectName())) continue;
        if (!hook(w)) continue;
        connect(w, &QCheckBox::toggled, this, [this](){ marcarComoModificado(); });
    }
    for (auto *w : root->findChildren<QRadioButton*>()) {
        if (!isSerializableName(w->objectName())) continue;
        if (!hook(w)) continue;
        connect(w, &QRadioButton::toggled, this, [this](){ marcarComoModificado(); });
    }
    for (auto *w : root->findChildren<QSpinBox*>()) {
        if (!isSerializableName(w->objectName())) continue;
        if (!hook(w)) continue;
        connect(w, qOverload<int>(&QSpinBox::valueChanged), this, [this](){ marcarComoModificado(); });
    }
    for (auto *w : root->findChildren<QDoubleSpinBox*>()) {
        if (!isSerializableName(w->objectName())) continue;
        if (!hook(w)) continue;
        connect(w, qOverload<double>(&QDoubleSpinBox::valueChanged), this, [this](){ marcarComoModificado(); });
    }
    for (auto *w : root->findChildren<QDateEdit*>()) {
        if (!isSerializableName(w->objectName())) continue;
        if (!hook(w)) continue;
        connect(w, &QDateEdit::dateChanged, this, [this](){ marcarComoModificado(); });
    }
}



bool CalicataWindow::persistSinglePhotoToEditableJpg(int idx,
                                                     const QPixmap &pix,
                                                     const QString &contextFilePath,
                                                     QString *outRelPath) const
{
    if (pix.isNull()) return false;

    const QString editableRoot = editableRootForPath(contextFilePath);
    if (editableRoot.isEmpty()) return false;

    if (!ensurePhotosDir(editableRoot)) return false;

    const QString stem = calicataStemForFile(contextFilePath);

    const QString baseRel = QString("%1/%2").arg(kEditablePhotosFolder, stem);
    QDir d(editableRoot);
    if (!d.mkpath(baseRel)) return false;

    const QString folder = sanitizeFsName(photoFolderDisplayName(idx));
    const QString prefix = fotoPrefixForIdx(idx);

    const QString typeRel = QString("%1/%2").arg(baseRel, folder);
    if (!d.mkpath(typeRel)) return false;

    const QString rel = QString("%1/%2_001.jpg").arg(typeRel, prefix);
    const QString abs = d.absoluteFilePath(rel);

    // Empuja _001-> _002 -> _003...
    if (!backupIfExists(abs)) return false;

    if (!savePixmapAsJpg(pix, abs, 90)) return false;

    if (outRelPath) *outRelPath = QDir::cleanPath(QDir::fromNativeSeparators(rel));
    return true;
}



// ------------------------------------------------------------
// Timestamp base desde UI  (IMPORTANTE: no borra proyecto)
// ------------------------------------------------------------
void CalicataWindow::actualizarTimestampDesdeUi()
{
    if (!ui) return;

    QString proyecto = m_timestamp.proyecto;
    if (proyecto.trimmed().isEmpty()) {
        QString ctx;
        if (!m_currentFilePath.isEmpty()) ctx = m_currentFilePath;
        else ctx = property("calicataFilePath").toString();

        const QString inferred = projectNameForPath(ctx);
        if (!inferred.isEmpty())
            proyecto = inferred;
    }

    m_timestamp.zona     = ui->txtZona       ? ui->txtZona->text()       : QString();
    m_timestamp.este     = ui->txtUTMX       ? ui->txtUTMX->text()       : QString();
    m_timestamp.norte    = ui->txtUTMY       ? ui->txtUTMY->text()       : QString();
    m_timestamp.altitud  = g_ubicacionData.altitud;

    m_timestamp.calicata = ui->txtProgresiva ? ui->txtProgresiva->text() : QString();
    m_timestamp.proyecto = proyecto;

    QDate f = QDate::currentDate();
    if (ui->dateEdit && hasRealDate(ui->dateEdit)) {
        f = ui->dateEdit->date();
    }
    m_timestamp.fecha = f.toString("dd/MM/yy");

    if (!g_ubicacionData.hora.isEmpty())
        m_timestamp.hora = g_ubicacionData.hora;
    else
        m_timestamp.hora = QTime::currentTime().toString("HH:mm:ss");
}

// ------------------------------------------------------------
// Base64 PNG helpers (para logos custom + legacy)
// ------------------------------------------------------------
QString CalicataWindow::pixmapToBase64Png(const QPixmap &pix)
{
    if (pix.isNull()) return QString();
    QByteArray bytes;
    QBuffer buf(&bytes);
    buf.open(QIODevice::WriteOnly);
    pix.save(&buf, "PNG");
    return QString::fromLatin1(bytes.toBase64());
}

QPixmap CalicataWindow::base64PngToPixmap(const QString &b64)
{
    if (b64.trimmed().isEmpty()) return QPixmap();
    const QByteArray bytes = QByteArray::fromBase64(b64.toLatin1());
    QPixmap pix;
    pix.loadFromData(bytes, "PNG");
    return pix;
}

// ------------------------------------------------------------
// Diálogo timestamp
// ------------------------------------------------------------
bool CalicataWindow::editarTimestamp(TimestampData &ioData)
{
    if (ioData.proyecto.trimmed().isEmpty()) {
        ensureProyectoFromContext();
        ioData.proyecto = m_timestamp.proyecto;
    }

    TimestampDialog dlg(this);

    QString horaInicial = !g_ubicacionData.hora.isEmpty()
                              ? g_ubicacionData.hora
                              : QTime::currentTime().toString("HH:mm:ss");

    dlg.setZona(ioData.zona);
    dlg.setEste(ioData.este);
    dlg.setNorte(ioData.norte);
    dlg.setAltitud(ioData.altitud);

    dlg.setCalicata(ioData.calicata);
    dlg.setProyecto(ioData.proyecto);
    dlg.setFecha(ioData.fecha);
    dlg.setHora(horaInicial);

    if (dlg.exec() != QDialog::Accepted)
        return false;

    ioData.zona     = dlg.zona();
    ioData.este     = dlg.este();
    ioData.norte    = dlg.norte();
    ioData.altitud  = dlg.altitud();
    ioData.calicata = dlg.calicata();
    ioData.proyecto = dlg.proyecto();
    ioData.fecha    = dlg.fecha();
    ioData.hora     = dlg.hora();

    return true;
}

QPixmap CalicataWindow::generarFotoConDatos(const QPixmap &original,
                                            const TimestampData &data) const
{
    if (original.isNull())
        return original;

    QPixmap result = original;
    QPainter p(&result);

    p.setRenderHint(QPainter::Antialiasing, true);
    p.setRenderHint(QPainter::TextAntialiasing, true);
    p.setRenderHint(QPainter::SmoothPixmapTransform, true);

    const int w = result.width();
    const int h = result.height();

    // ============================================================
    // 1) LOGO DEL PROYECTO — esquina superior izquierda
    // ============================================================
    if (!m_logoProyectoPix.isNull()) {
        const int logoMargin = qMax(12, w / 60);

        // Tamaño proporcional al ancho de la foto.
        // Ajusta estos valores si lo quieres más grande o más pequeño.
        const int logoMaxW = qMax(90, w / 5);
        const int logoMaxH = qMax(50, h / 7);

        QPixmap logo = m_logoProyectoPix.scaled(
            logoMaxW,
            logoMaxH,
            Qt::KeepAspectRatio,
            Qt::SmoothTransformation
            );

        // Opcional: fondo blanco translúcido para que el logo se lea mejor
        const int pad = qMax(4, w / 250);
        QRect bgRect(
            logoMargin - pad,
            logoMargin - pad,
            logo.width() + pad * 2,
            logo.height() + pad * 2
            );

        p.setPen(Qt::NoPen);
        p.setBrush(QColor(255, 255, 255, 180));
        p.drawRoundedRect(bgRect, pad * 2, pad * 2);

        p.drawPixmap(logoMargin, logoMargin, logo);
    }

    // ============================================================
    // 2) TEXTO TIMESTAMP — esquina inferior derecha
    // ============================================================

    const int fontSize = qMax(10, h / 32);

    QFont font;
    font.setFamily("Arial");
    font.setPointSize(fontSize);
    font.setBold(false);
    p.setFont(font);

    auto clean = [](QString s) {
        return s.trimmed();
    };

    auto withSuffixIfMissing = [](QString value, const QString &suffix) {
        value = value.trimmed();

        if (value.isEmpty())
            return QString();

        // Evita duplicar si el usuario ya escribió el sufijo manualmente
        if (value.endsWith(suffix, Qt::CaseInsensitive))
            return value;

        return value + " " + suffix;
    };

    QString zona    = clean(data.zona);
    QString este    = clean(data.este);
    QString norte   = clean(data.norte);
    QString altitud = clean(data.altitud);

    QStringList lineas;

    // Ejemplo requerido:
    // ZONA 18 200240 E 9206408 N
    if (!zona.isEmpty() || !este.isEmpty() || !norte.isEmpty()) {
        QString lineaCoord;

        if (!zona.isEmpty())
            lineaCoord += QString("ZONA %1").arg(zona);

        if (!este.isEmpty()) {
            if (!lineaCoord.isEmpty()) lineaCoord += " ";
            lineaCoord += withSuffixIfMissing(este, "E");
        }

        if (!norte.isEmpty()) {
            if (!lineaCoord.isEmpty()) lineaCoord += " ";
            lineaCoord += withSuffixIfMissing(norte, "N");
        }

        lineas << lineaCoord;
    }

    // Ejemplo requerido:
    // Altitud: 220 m.s.n.m
    if (!altitud.isEmpty()) {
        QString altTxt = altitud;

        // Evita duplicar si ya viene como "220 m.s.n.m" o "220 m.s.n.m."
        if (!altTxt.contains("m.s.n.m", Qt::CaseInsensitive))
            altTxt += " m.s.n.m";

        lineas << QString("Altitud: %1").arg(altTxt);
    }

    // Ejemplo:
    // CA_SCPT_01_PUENTE LECHEMAYO
    if (!data.calicata.trimmed().isEmpty() || !data.proyecto.trimmed().isEmpty()) {
        QString calicata = data.calicata.trimmed();
        QString proyecto = data.proyecto.trimmed();

        if (!calicata.isEmpty() && !proyecto.isEmpty())
            lineas << QString("%1  %2").arg(calicata, proyecto);
        else if (!calicata.isEmpty())
            lineas << calicata;
        else
            lineas << proyecto;
    }

    // Ejemplo:
    // 04/05/26  16:25:37
    if (!data.fecha.trimmed().isEmpty() || !data.hora.trimmed().isEmpty()) {
        QString fecha = data.fecha.trimmed();
        QString hora  = data.hora.trimmed();

        if (!fecha.isEmpty() && !hora.isEmpty())
            lineas << QString("%1  %2").arg(fecha, hora);
        else if (!fecha.isEmpty())
            lineas << fecha;
        else
            lineas << hora;
    }

    const int margin = qMax(fontSize, w / 80);
    int y = h - margin;

    for (int i = lineas.size() - 1; i >= 0; --i) {
        const QString txt = lineas.at(i);
        if (txt.trimmed().isEmpty())
            continue;

        QSize sz = p.fontMetrics().size(Qt::TextSingleLine, txt);

        QRect rect(
            w - margin - sz.width(),
            y - sz.height(),
            sz.width(),
            sz.height()
            );

        // Sombra negra para lectura
        p.setPen(QColor(0, 0, 0, 190));
        p.drawText(rect.translated(2, 2), Qt::AlignLeft | Qt::AlignVCenter, txt);

        // Texto blanco
        p.setPen(Qt::white);
        p.drawText(rect, Qt::AlignLeft | Qt::AlignVCenter, txt);

        y -= sz.height() + 6;
    }

    p.end();

    return result;
}

void CalicataWindow::cargarImagenEnBoton(QPushButton *boton,
                                         const QString &tituloDialogo,
                                         bool estamparDatosEnFoto)
{
    if (!boton) return;

    if (m_pickDebounce.isValid() && m_pickDebounce.elapsed() < 250)
        return;
    m_pickDebounce.restart();

    const bool isPhotoBtn = (ui && (boton == ui->btnFoto1 || boton == ui->btnFoto2 || boton == ui->btnFoto3));

    // ------------------------------------------------------------
    // BLOQUEO: no permitir crear fotos si la ficha aún no está guardada
    // ------------------------------------------------------------
    if (isPhotoBtn) {
        const QString ctx = !m_currentFilePath.isEmpty()
        ? m_currentFilePath
        : property("calicataFilePath").toString().trimmed();

        if (ctx.isEmpty() || m_currentFilePath.isEmpty()) {
            QMessageBox::information(
                this,
                tr("Foto"),
                tr("Primero guarda la calicata antes de agregar fotografías.\n\n"
                   "Las fotos se guardan en la carpeta editable de la ficha; "
                   "si la ficha aún no tiene archivo, no se puede definir una ruta segura.")
                );
            return;
        }

        const QString editableRoot = editableRootForPath(ctx);
        if (editableRoot.isEmpty()) {
            QMessageBox::information(
                this,
                tr("Foto"),
                tr("No se encontró la carpeta editable de esta ficha.\n\n"
                   "Guarda o abre una calicata dentro de una carpeta editable "
                   "antes de agregar fotografías.")
                );
            return;
        }
    }

    const QString startDir = pickStartDir(isPhotoBtn);

    QFileDialog dlg(this, tituloDialogo, startDir, tr("Imágenes (*.png *.jpg *.jpeg *.bmp *.webp)"));
    dlg.setFileMode(QFileDialog::ExistingFile);

    if (dlg.exec() != QDialog::Accepted)
        return;

    const QString filePath = dlg.selectedFiles().value(0);
    if (filePath.isEmpty()) return;

    m_lastImagePickDir = QFileInfo(filePath).dir().absolutePath();

    QPixmap pix(filePath);
    if (pix.isNull()) return;

    const QString ctx = !m_currentFilePath.isEmpty()
                            ? m_currentFilePath
                            : property("calicataFilePath").toString();

    auto normRel = [](QString s) {
        s = s.trimmed();
        if (s.isEmpty()) return QString();
        return QDir::cleanPath(QDir::fromNativeSeparators(s));
    };

    // Si el usuario elige una foto YA dentro de /Edit/fotos/... -> no estampar y mantener path
    bool doStamp = estamparDatosEnFoto;
    QString pickedRelInsideEditable;

    if (isPhotoBtn && doStamp && isPathInsideEditableFotos(QFileInfo(filePath).absoluteFilePath(), ctx)) {
        doStamp = false;

        const QString editableRoot = editableRootForPath(ctx);
        if (!editableRoot.isEmpty()) {
            QDir rd(editableRoot);
            const QString rel = normRel(rd.relativeFilePath(QFileInfo(filePath).absoluteFilePath()));
            if (!rel.startsWith(".."))
                pickedRelInsideEditable = rel;
        }
    }

    // Generar (estampar)
    if (doStamp) {
        ensureProyectoFromContext();

        TimestampData tmp = m_timestamp;

        if (ui->txtProgresiva && !ui->txtProgresiva->text().isEmpty())
            tmp.calicata = ui->txtProgresiva->text();

        if (ui->dateEdit && hasRealDate(ui->dateEdit))
            tmp.fecha = ui->dateEdit->date().toString("dd/MM/yy");
        else
            tmp.fecha = QDate::currentDate().toString("dd/MM/yy");

        if (tmp.hora.isEmpty())
            tmp.hora = QTime::currentTime().toString("HH:mm:ss");

        if (!editarTimestamp(tmp))
            return;

        m_timestamp = tmp;
        pix = generarFotoConDatos(pix, m_timestamp);
    }

    // Asignar pix + paths
    if (boton == ui->btnLogoMTC) {
        m_logoMtcPix = pix;
        m_logoMtcIsCustom = true;
        m_logoMtcRelPath.clear();
    } else if (boton == ui->btnLogoProyecto) {
        m_logoProyectoPix = pix;
        m_logoProyectoIsCustom = true;
        m_logoProyectoRelPath.clear();
    } else if (boton == ui->btnFoto1) {
        m_foto1Pix = pix;
        m_foto1RelPath = pickedRelInsideEditable;
    } else if (boton == ui->btnFoto2) {
        m_foto2Pix = pix;
        m_foto2RelPath = pickedRelInsideEditable;
    } else if (boton == ui->btnFoto3) {
        m_foto3Pix = pix;
        m_foto3RelPath = pickedRelInsideEditable;
    }

    // ✅ AUTO-GUARDAR: solo cuando se GENERÓ/ESTAMPÓ una foto (doStamp==true)
    if (isPhotoBtn && doStamp && !ctx.isEmpty()) {
        int idx = 0;
        if (boton == ui->btnFoto1) idx = 1;
        else if (boton == ui->btnFoto2) idx = 2;
        else if (boton == ui->btnFoto3) idx = 3;

        if (idx != 0) {
            QString outRel;
            if (persistSinglePhotoToEditableJpg(idx, pix, ctx, &outRel) && !outRel.isEmpty()) {
                if (idx == 1) m_foto1RelPath = outRel;
                if (idx == 2) m_foto2RelPath = outRel;
                if (idx == 3) m_foto3RelPath = outRel;
            }
        }
    }

    setButtonPixmap(boton, pix, true);
}





// ------------------------------------------------------------
// Slots LOGOS y FOTOS (botón grande)
// ------------------------------------------------------------
void CalicataWindow::on_btnLogoMTC_clicked()
{
    pickLogoFromResources(true);   // si cancela, no hace nada
}

void CalicataWindow::on_btnLogoProyecto_clicked()
{
    pickLogoFromResources(false);  // si cancela, no hace nada
}


void CalicataWindow::on_btnFoto1_clicked()
{
    cargarImagenEnBoton(ui->btnFoto1, tr("Seleccionar Foto 1 (panorámica)"), true);
}

void CalicataWindow::on_btnFoto2_clicked()
{
    cargarImagenEnBoton(ui->btnFoto2, tr("Seleccionar Foto 2 (interior calicata)"), true);
}

void CalicataWindow::on_btnFoto3_clicked()
{
    cargarImagenEnBoton(ui->btnFoto3, tr("Seleccionar Foto 3 (acopios)"), true);
}

// ------------------------------------------------------------
// Clear logos/fotos
// ------------------------------------------------------------
void CalicataWindow::clearLogoMtc()
{
    m_logoMtcIsCustom = false;
    m_logoMtcPix = QPixmap();
    m_logoMtcRelPath.clear();

    if (ui && ui->btnLogoMTC) {
        setDefaultLogoPlaceholder(ui->btnLogoMTC, m_defaultLogoMtcIcon, m_defaultLogoMtcText);
    }

    marcarComoModificado();
}

void CalicataWindow::clearLogoProyecto()
{
    m_logoProyectoIsCustom = false;
    m_logoProyectoPix = QPixmap();
    m_logoProyectoRelPath.clear();

    if (ui && ui->btnLogoProyecto) {
        setDefaultLogoPlaceholder(ui->btnLogoProyecto, m_defaultLogoProyectoIcon, m_defaultLogoProyectoText);
    }

    marcarComoModificado();
}

void CalicataWindow::clearFoto(int idx)
{
    if (idx == 1) { m_foto1Pix = QPixmap(); m_foto1RelPath.clear(); }
    if (idx == 2) { m_foto2Pix = QPixmap(); m_foto2RelPath.clear(); }
    if (idx == 3) { m_foto3Pix = QPixmap(); m_foto3RelPath.clear(); }

    refreshAllButtonPixmaps();
    marcarComoModificado();
}

// ------------------------------------------------------------
// ✅ Actualizar coordenadas (CON ADVERTENCIA)
// ------------------------------------------------------------
void CalicataWindow::on_btnActualizarCoordenadas_clicked()
{
    const QString newZona = g_ubicacionData.zona.trimmed();
    const QString newX    = g_ubicacionData.x.trimmed();
    const QString newY    = g_ubicacionData.y.trimmed();

    if (newZona.isEmpty() && newX.isEmpty() && newY.isEmpty()) {
        QMessageBox::information(
            this,
            tr("Sin coordenadas"),
            tr("No hay coordenadas nuevas disponibles para actualizar.\n"
               "Primero captura/actualiza la ubicación.")
            );
        return;
    }

    const QString curZona = (ui->txtZona ? ui->txtZona->text().trimmed() : QString());
    const QString curX    = (ui->txtUTMX ? ui->txtUTMX->text().trimmed() : QString());
    const QString curY    = (ui->txtUTMY ? ui->txtUTMY->text().trimmed() : QString());

    const bool hasCurrent = (!curZona.isEmpty() || !curX.isEmpty() || !curY.isEmpty());
    const bool differs    = (curZona != newZona) || (curX != newX) || (curY != newY);

    if (hasCurrent && differs) {
        const auto ret = QMessageBox::warning(
            this,
            tr("Actualizar coordenadas"),
            tr("Se reemplazarán las coordenadas actuales:\n"
               "Zona: %1\nX UTM: %2\nY UTM: %3\n\n"
               "Por las nuevas:\n"
               "Zona: %4\nX UTM: %5\nY UTM: %6\n\n"
               "¿Deseas continuar?")
                .arg(curZona, curX, curY, newZona, newX, newY),
            QMessageBox::Yes | QMessageBox::No,
            QMessageBox::No
            );

        if (ret != QMessageBox::Yes)
            return;
    }

    if (ui->txtZona) ui->txtZona->setText(newZona);
    if (ui->txtUTMX) ui->txtUTMX->setText(newX);
    if (ui->txtUTMY) ui->txtUTMY->setText(newY);

    m_timestamp.zona    = newZona;
    m_timestamp.este    = newX;
    m_timestamp.norte   = newY;
    m_timestamp.altitud = g_ubicacionData.altitud;

    if (!g_ubicacionData.hora.isEmpty())
        m_timestamp.hora = g_ubicacionData.hora;

    marcarComoModificado();
}

void CalicataWindow::aplicarUbicacion(const QGeoCoordinate &coord,
                                      double altitude,
                                      const QDateTime &time)
{
    Q_UNUSED(altitude);
    Q_UNUSED(time);

    if (ui->txtUTMX) ui->txtUTMX->setText(QString::number(coord.longitude(), 'f', 6));
    if (ui->txtUTMY) ui->txtUTMY->setText(QString::number(coord.latitude(), 'f', 6));
    if (ui->txtZona && ui->txtZona->text().isEmpty())
        ui->txtZona->setText("18L");

    actualizarTimestampDesdeUi();
    marcarComoModificado();
}

void CalicataWindow::onGpsPositionUpdated(const QGeoCoordinate &coord,
                                          double altitude,
                                          const QDateTime &time)
{
    aplicarUbicacion(coord, altitude, time);
}

// ------------------------------------------------------------
// Dirty / cierre
// ------------------------------------------------------------
void CalicataWindow::marcarComoModificado()
{
    if (m_loading || m_historyApplying)
        return;

    if (!m_dirty)
        setDirtyInternal(true);

    scheduleHistorySnapshot();
}


bool CalicataWindow::guardarSiEsNecesario()
{
    if (!m_dirty)
        return true;

    const QString name = !m_currentFilePath.isEmpty()
                             ? QFileInfo(m_currentFilePath).fileName()
                             : tr("Ficha sin nombre");

    QMessageBox msg(this);
    msg.setIcon(QMessageBox::Warning);
    msg.setWindowTitle(tr("Cambios sin guardar"));
    msg.setText(tr("¿Deseas guardar los cambios en \"%1\"?").arg(name));
    msg.setInformativeText(tr("Si no guardas, se perderán los cambios."));

    msg.setStandardButtons(QMessageBox::Save | QMessageBox::Discard | QMessageBox::Cancel);
    msg.setDefaultButton(QMessageBox::Save);
    msg.setEscapeButton(QMessageBox::Cancel);

    const int ret = msg.exec();

    if (ret == QMessageBox::Cancel)
        return false;

    if (ret == QMessageBox::Discard)
        return true;

    // Save
    if (m_currentFilePath.isEmpty()) {
        guardarComo();
        return !m_currentFilePath.isEmpty() && !m_dirty;
    }

    return guardarEnArchivo(m_currentFilePath);
}


// ------------------------------------------------------------
// JSON header (compatibilidad)
// ------------------------------------------------------------
void CalicataWindow::aplicarJsonEnUi(const QJsonObject &obj)
{
    if (ui->txtSupervisor) ui->txtSupervisor->setText(obj.value("supervisor").toString());
    if (ui->txtMaquina)    ui->txtMaquina->setText(obj.value("maquina").toString());
    if (ui->comboLadoVia)  ui->comboLadoVia->setCurrentText(obj.value("lado_via").toString());

    if (ui->txtUTMX)       ui->txtUTMX->setText(obj.value("utm_x").toString());
    if (ui->txtUTMY)       ui->txtUTMY->setText(obj.value("utm_y").toString());
    if (ui->txtZona)       ui->txtZona->setText(obj.value("zona").toString());
    if (ui->txtProgresiva) ui->txtProgresiva->setText(obj.value("progresiva").toString());

    if (ui->dateEdit) {
        const QDate d = QDate::fromString(obj.value("fecha_inicio").toString(), Qt::ISODate);
        if (d.isValid()) ui->dateEdit->setDate(d);
        else             ui->dateEdit->setDate(ui->dateEdit->minimumDate());
    }

    if (ui->dateEdit_2) {
        const QDate d2 = QDate::fromString(obj.value("fecha_fin").toString(), Qt::ISODate);
        if (d2.isValid()) ui->dateEdit_2->setDate(d2);
        else              ui->dateEdit_2->setDate(ui->dateEdit_2->minimumDate());
    }

    normalizeDateEditState(ui->dateEdit);
    normalizeDateEditState(ui->dateEdit_2);

    actualizarTimestampDesdeUi();
}

// ------------------------------------------------------------
// JSON completo (✅ fotos cache; ✅ logos por path o base64)
// ------------------------------------------------------------
QJsonObject CalicataWindow::buildFullJson(const QString &savingFilePath) const
{
    QJsonObject obj;
    obj["version"] = 3;

    // --- Captura valores una sola vez ---
    const QString supervisor = ui->txtSupervisor ? ui->txtSupervisor->text() : "";
    const QString maquina    = ui->txtMaquina    ? ui->txtMaquina->text()    : "";
    const QString ladoVia    = ui->comboLadoVia  ? ui->comboLadoVia->currentText() : "";

    const QString utmX       = ui->txtUTMX       ? ui->txtUTMX->text()       : "";
    const QString utmY       = ui->txtUTMY       ? ui->txtUTMY->text()       : "";
    const QString zona       = ui->txtZona       ? ui->txtZona->text()       : "";

    const QString progresiva = ui->txtProgresiva ? ui->txtProgresiva->text() : "";

    auto dateToIsoOrEmpty = [](QDateEdit *de) -> QString {
        if (!de) return QString();
        const QDate d = de->date();
        if (!d.isValid() || d == de->minimumDate())
            return QString();
        return d.toString(Qt::ISODate);
    };

    const QString fechaInicio = dateToIsoOrEmpty(ui->dateEdit);
    const QString fechaFin    = dateToIsoOrEmpty(ui->dateEdit_2);

    const QString excelTitle = !m_tituloTestificacion.trimmed().isEmpty()
                                   ? m_tituloTestificacion.trimmed()
                                   : loadExcelTitleFromEditableMeta(savingFilePath).trimmed();




    // --- Mantengo tus campos planos (por compatibilidad) ---
    obj["supervisor"] = supervisor;
    obj["maquina"]    = maquina;
    obj["lado_via"]   = ladoVia;

    obj["utm_x"]      = utmX;
    obj["utm_y"]      = utmY;
    obj["zona"]       = zona;

    obj["progresiva"] = progresiva;
    if (!fechaInicio.isEmpty()) obj["fecha_inicio"] = fechaInicio;
    if (!fechaFin.isEmpty())    obj["fecha_fin"]    = fechaFin;

    obj["excel_title"] = excelTitle;

    // --- header para ExcelExporter ---
    {
        QJsonObject header;
        header["supervisor"]  = supervisor;
        header["maquina"]     = maquina;
        header["lado_via"]    = ladoVia;

        header["utm_x"]       = utmX;
        header["utm_y"]       = utmY;
        header["zona"]        = zona;

        header["pk"]          = progresiva;
        header["calicata"]    = progresiva;

        header["fecha_inicio"] = fechaInicio;
        header["fecha_fin"]    = fechaFin;
        header["excel_title"] = excelTitle;


        obj["header"] = header;
    }

    // --- timestamp ---
    {
        QJsonObject ts;
        ts["zona"]     = m_timestamp.zona;
        ts["este"]     = m_timestamp.este;
        ts["norte"]    = m_timestamp.norte;
        ts["altitud"]  = m_timestamp.altitud;
        ts["calicata"] = m_timestamp.calicata;
        ts["proyecto"] = m_timestamp.proyecto;
        ts["fecha"]    = m_timestamp.fecha;
        ts["hora"]     = m_timestamp.hora;
        obj["timestamp"] = ts;
    }

    // --- ui_state ---
    {
        QJsonObject state;
        QJsonObject lineEdits, plainEdits, textEdits, combos, checks, radios, spins, dspins, dates;

        for (auto *w : this->findChildren<QLineEdit*>()) {
            if (!w) continue;
            if (hasCorteRowAncestor(w)) continue;
            const QString n = w->objectName();
            if (!isSerializableName(n)) continue;
            lineEdits[n] = w->text();
        }

        for (auto *w : this->findChildren<QPlainTextEdit*>()) {
            if (!w) continue;
            if (hasCorteRowAncestor(w)) continue;
            const QString n = w->objectName();
            if (!isSerializableName(n)) continue;
            plainEdits[n] = w->toPlainText();
        }

        for (auto *w : this->findChildren<QTextEdit*>()) {
            if (!w) continue;
            if (hasCorteRowAncestor(w)) continue;
            const QString n = w->objectName();
            if (!isSerializableName(n)) continue;
            textEdits[n] = w->toPlainText();
        }

        for (auto *w : this->findChildren<QComboBox*>()) {
            if (!w) continue;
            if (hasCorteRowAncestor(w)) continue;
            const QString n = w->objectName();
            if (!isSerializableName(n)) continue;

            QJsonObject v;
            v["index"] = w->currentIndex();
            v["text"]  = w->currentText();
            combos[n] = v;
        }

        for (auto *w : this->findChildren<QCheckBox*>()) {
            if (!w) continue;
            if (hasCorteRowAncestor(w)) continue;
            const QString n = w->objectName();
            if (!isSerializableName(n)) continue;
            checks[n] = w->isChecked();
        }

        for (auto *w : this->findChildren<QRadioButton*>()) {
            if (!w) continue;
            if (hasCorteRowAncestor(w)) continue;
            const QString n = w->objectName();
            if (!isSerializableName(n)) continue;
            radios[n] = w->isChecked();
        }

        for (auto *w : this->findChildren<QSpinBox*>()) {
            if (!w) continue;
            if (hasCorteRowAncestor(w)) continue;
            const QString n = w->objectName();
            if (!isSerializableName(n)) continue;
            spins[n] = w->value();
        }

        for (auto *w : this->findChildren<QDoubleSpinBox*>()) {
            if (!w) continue;
            if (hasCorteRowAncestor(w)) continue;
            const QString n = w->objectName();
            if (!isSerializableName(n)) continue;
            dspins[n] = w->value();
        }

        for (auto *w : this->findChildren<QDateEdit*>()) {
            if (!w) continue;
            if (hasCorteRowAncestor(w)) continue;
            const QString n = w->objectName();
            if (!isSerializableName(n)) continue;
            dates[n] = w->date().toString(Qt::ISODate);
        }

        state["line_edits"] = lineEdits;
        state["plain_text_edits"] = plainEdits;
        state["text_edits"] = textEdits;
        state["combo_boxes"] = combos;
        state["check_boxes"] = checks;
        state["radio_buttons"] = radios;
        state["spin_boxes"] = spins;
        state["double_spin_boxes"] = dspins;
        state["date_edits"] = dates;

        obj["ui_state"] = state;
    }

    // --- cortes ---
    {
        QJsonArray arr;
        if (m_layoutCortes) {
            for (int i = 0; i < m_layoutCortes->count(); ++i) {
                QWidget *w = m_layoutCortes->itemAt(i)->widget();
                auto *row = qobject_cast<CorteRowWidget*>(w);
                if (!row) continue;

                arr.append(JsonWidgetSerializer::serialize(row));
            }
        }
        obj["cortes"] = arr;
    }

    // --- images ---
    {
        QJsonObject imgs;

        // Logos: preferimos PATH y fallback a base64 si no hay path
        auto storeLogo = [&](const QString &keyBase, bool isCustom, const QPixmap &pix, const QString &relPath){
            imgs[keyBase + "_custom"] = isCustom;

            if (!isCustom) {
                imgs[keyBase] = QString();
                imgs[keyBase + "_path"] = QString();
                return;
            }

            const QString rp = QDir::cleanPath(QDir::fromNativeSeparators(relPath.trimmed()));
            if (!rp.isEmpty()) {
                imgs[keyBase + "_path"] = rp;
                imgs[keyBase] = QString(); // no embebemos si hay path
            } else {
                imgs[keyBase + "_path"] = QString();
                imgs[keyBase] = pix.isNull() ? QString() : pixmapToBase64Png(pix);
            }
        };

        storeLogo("logo_mtc",      m_logoMtcIsCustom,      m_logoMtcPix,      m_logoMtcRelPath);
        storeLogo("logo_proyecto", m_logoProyectoIsCustom, m_logoProyectoPix, m_logoProyectoRelPath);

        // Fotos: NO guardar/copiar aquí. Solo escribir path si ya existe.
        auto storePhoto = [&](int idx, const QPixmap &pix, const QString &relPath){
            const QString key = QString("foto%1").arg(idx);
            const QString rp = QDir::cleanPath(QDir::fromNativeSeparators(relPath.trimmed()));

            if (!rp.isEmpty()) {
                imgs[key + "_path"] = rp;
                imgs[key] = QString(); // no embebemos si hay path
            } else {
                imgs[key + "_path"] = QString();
                imgs[key] = pix.isNull() ? QString() : pixmapToBase64Png(pix);
            }
        };

        storePhoto(1, m_foto1Pix, m_foto1RelPath);
        storePhoto(2, m_foto2Pix, m_foto2RelPath);
        storePhoto(3, m_foto3Pix, m_foto3RelPath);

        // Indicativo (opcional pero útil)
        imgs["storage"] = "mixed_paths_or_embedded";

        obj["images"] = imgs;
    }


    // --- Observaciones ---
    obj["observaciones"] = ui->txtObservaciones ? ui->txtObservaciones->toPlainText() : "";

    return obj;
}

void CalicataWindow::clearCortesRows()
{
    if (!m_layoutCortes) return;

    while (m_layoutCortes->count() > 0) {
        QLayoutItem *it = m_layoutCortes->takeAt(0);
        if (!it) break;
        if (QWidget *w = it->widget())
            w->deleteLater();
        delete it;
    }
}

void CalicataWindow::applyFullJson(const QJsonObject &obj, const QString &contextFilePath)
{
    aplicarJsonEnUi(obj);

    if (obj.contains("ui_state") && obj["ui_state"].isObject()) {
        applyWidgetTree(this, obj["ui_state"].toObject());
    }

    normalizeDateEditState(ui->dateEdit);
    normalizeDateEditState(ui->dateEdit_2);

    m_logoMtcIsCustom = false;
    m_logoProyectoIsCustom = false;

    // Reset relpaths
    m_foto1RelPath.clear();
    m_foto2RelPath.clear();
    m_foto3RelPath.clear();

    // Reset logo relpaths
    m_logoMtcRelPath.clear();
    m_logoProyectoRelPath.clear();

    if (obj.contains("images") && obj["images"].isObject()) {
        const QJsonObject imgs = obj["images"].toObject();

        auto tryLoadRel = [&](const QString &rel) -> QPixmap {
            if (rel.trimmed().isEmpty()) return QPixmap();
            const QString abs = resolveImageAbsPath(rel, contextFilePath);
            if (!QFileInfo::exists(abs)) return QPixmap();
            return QPixmap(abs);
        };

        auto loadPhotoSmart = [&](int idx, const QString &keyBase, QString *outRelUsed) -> QPixmap {
            if (outRelUsed) outRelUsed->clear();

            const QString rel = imgs.value(keyBase + "_path").toString().trimmed();
            QPixmap p = tryLoadRel(rel);
            if (!p.isNull()) { if (outRelUsed) *outRelUsed = rel; return p; }

            const QString stem = calicataStemForFile(contextFilePath);
            const QString folder = sanitizeFsName(photoFolderDisplayName(idx));
            const QString prefix = fotoPrefixForIdx(idx);

            const QString rel2 = QString("%1/%2/%3/%4_001.jpg").arg(kEditablePhotosFolder, stem, folder, prefix);
            p = tryLoadRel(rel2);
            if (!p.isNull()) { if (outRelUsed) *outRelUsed = rel2; return p; }

            const QString rel3 = QString("%1/%2/%3.jpg").arg(kEditablePhotosFolder, stem, keyBase);
            p = tryLoadRel(rel3);
            if (!p.isNull()) { if (outRelUsed) *outRelUsed = rel3; return p; }

            const QString rel4 = QString("%1/%2_%3.jpg").arg(kEditablePhotosFolder, stem, keyBase);
            p = tryLoadRel(rel4);
            if (!p.isNull()) { if (outRelUsed) *outRelUsed = rel4; return p; }

            return QPixmap();
        };

        // LOGOS: primero por path, luego fallback base64 (legacy)
        auto loadLogoSmart = [&](const QString &keyBase, bool *outCustom, QString *outRelPath) -> QPixmap {
            if (outRelPath) outRelPath->clear();

            const QString rel = imgs.value(keyBase + "_path").toString().trimmed();
            if (!rel.isEmpty()) {
                const QString abs = resolveResourceAbsPath(rel, contextFilePath);
                if (QFileInfo::exists(abs)) {
                    QPixmap p(abs);
                    if (!p.isNull()) {
                        if (outRelPath) *outRelPath = rel;
                        if (outCustom) *outCustom = true;
                        return p;
                    }
                }
            }

            const QString b64 = imgs.value(keyBase).toString().trimmed();
            if (!b64.isEmpty()) {
                if (outCustom) *outCustom = true;
                return base64PngToPixmap(b64);
            }

            if (outCustom) *outCustom = imgs.value(keyBase + "_custom").toBool(false);
            return QPixmap();
        };

        m_logoMtcPix = loadLogoSmart("logo_mtc", &m_logoMtcIsCustom, &m_logoMtcRelPath);
        m_logoProyectoPix = loadLogoSmart("logo_proyecto", &m_logoProyectoIsCustom, &m_logoProyectoRelPath);

        // FOTOS
        const QString storage = imgs.value("storage").toString();
        const bool hasPaths =
            imgs.contains("foto1_path") || imgs.contains("foto2_path") || imgs.contains("foto3_path");

        const bool storageEditable = storage.isEmpty() || storage.startsWith("editable_jpg");

        if (storageEditable || hasPaths) {
            QString r1, r2, r3;
            m_foto1Pix = loadPhotoSmart(1, "foto1", &r1);
            m_foto2Pix = loadPhotoSmart(2, "foto2", &r2);
            m_foto3Pix = loadPhotoSmart(3, "foto3", &r3);

            // mantener relPaths si existen (para no re-guardar)
            m_foto1RelPath = r1.trimmed();
            m_foto2RelPath = r2.trimmed();
            m_foto3RelPath = r3.trimmed();
        } else {
            m_foto1Pix = base64PngToPixmap(imgs.value("foto1").toString());
            m_foto2Pix = base64PngToPixmap(imgs.value("foto2").toString());
            m_foto3Pix = base64PngToPixmap(imgs.value("foto3").toString());
        }

        refreshAllButtonPixmaps();
        QTimer::singleShot(0, this, [this](){ refreshAllButtonPixmaps(); });
    } else {
        refreshAllButtonPixmaps();
    }

    // ✅ CORTES
    if (obj.contains("cortes") && obj["cortes"].isArray()) {
        const QJsonArray arr = obj["cortes"].toArray();

        clearCortesRows();

        if (arr.isEmpty()) {
            auto *row = new CorteRowWidget(ui->frameCortesContainer);
            m_layoutCortes->addWidget(row);

            setupIntervalRules(row);
            setupDeleteRules(row);
            attachDirtySignals(row);
        } else {
            for (const QJsonValue &v : arr) {
                if (!v.isObject()) continue;

                auto *row = new CorteRowWidget(ui->frameCortesContainer);
                m_layoutCortes->addWidget(row);

                setupIntervalRules(row);
                setupDeleteRules(row);

                JsonWidgetSerializer::apply(row, v.toObject());

                attachDirtySignals(row);
            }
        }

        renumerarCortesYIntervalos(false);
    }

    if (obj.contains("timestamp") && obj["timestamp"].isObject()) {
        const QJsonObject ts = obj["timestamp"].toObject();
        m_timestamp.zona     = ts.value("zona").toString(m_timestamp.zona);
        m_timestamp.este     = ts.value("este").toString(m_timestamp.este);
        m_timestamp.norte    = ts.value("norte").toString(m_timestamp.norte);
        m_timestamp.altitud  = ts.value("altitud").toString(m_timestamp.altitud);
        m_timestamp.calicata = ts.value("calicata").toString(m_timestamp.calicata);
        m_timestamp.proyecto = ts.value("proyecto").toString(m_timestamp.proyecto);
        m_timestamp.fecha    = ts.value("fecha").toString(m_timestamp.fecha);
        m_timestamp.hora     = ts.value("hora").toString(m_timestamp.hora);
    }

    {
        QString t = obj.value("excel_title").toString().trimmed();
        if (t.isEmpty())
            t = loadExcelTitleFromEditableMeta(contextFilePath).trimmed();

        m_tituloTestificacion = t;

        if (ui && ui->btnTituloCalicata) {
            ui->btnTituloCalicata->setToolTip(m_tituloTestificacion);
            ui->btnTituloCalicata->setText(m_tituloTestificacion.isEmpty()
                                               ? tr("Título\nCalicata")
                                               : tr("Título ✓"));
        }
    }

}

// ------------------------------------------------------------
// Guardar / Guardar Como
// ------------------------------------------------------------
bool CalicataWindow::guardarEnArchivo(const QString &filePath, bool interactive)
{
    if (filePath.isEmpty())
        return false;

    // Usaremos targetPath (por si se renombra en "Guardar")
    QString targetPath = normPath(filePath);

    auto samePath = [](QString a, QString b){
        a = normPath(a); b = normPath(b);
#ifdef Q_OS_WIN
        a = a.toLower(); b = b.toLower();
#endif
        return a == b;
    };

    // =========================================================
    // ✅ Renombrado SOLO en Guardar (no en autosave)
    // =========================================================
    if (interactive && !m_currentFilePath.isEmpty() && samePath(targetPath, m_currentFilePath)) {
        const QString prog = (ui && ui->txtProgresiva) ? ui->txtProgresiva->text().trimmed() : QString();
        const QString desiredStem = sanitizeFsName(prog);

        if (!desiredStem.isEmpty()) {
            const QString curStem = calicataStemForFile(m_currentFilePath);
            if (!curStem.isEmpty() && desiredStem != curStem) {

                const QString desiredFileName = desiredStem + ".calicata.json";
                const QString dirAbs = QFileInfo(m_currentFilePath).dir().absolutePath();
                const QString desiredAbs = normPath(QDir(dirAbs).absoluteFilePath(desiredFileName));

                if (!samePath(desiredAbs, m_currentFilePath)) {

                    QMessageBox box(this);
                    box.setIcon(QMessageBox::Question);
                    box.setWindowTitle(tr("Renombrar archivo"));
                    box.setText(tr("La Progresiva cambió, pero el archivo se llama diferente."));
                    box.setInformativeText(
                        tr("Archivo actual:\n%1\n\nProgresiva (deseada):\n%2\n\n¿Deseas renombrar el archivo para que coincida?")
                            .arg(QFileInfo(m_currentFilePath).fileName(), desiredFileName)
                        );

                    QPushButton* btnRename = box.addButton(tr("Renombrar archivo"), QMessageBox::AcceptRole);
                    QPushButton* btnKeep   = box.addButton(tr("Mantener nombre"), QMessageBox::DestructiveRole);
                    QPushButton* btnCancel = box.addButton(tr("Cancelar"), QMessageBox::RejectRole);
                    box.setDefaultButton(btnRename);
                    box.setEscapeButton(btnCancel);

                    box.exec();

                    if (box.clickedButton() == btnCancel) {
                        return false;
                    }

                    if (box.clickedButton() == btnRename) {
                        // si ya existe el destino, preguntar si sobrescribir
                        if (QFileInfo::exists(desiredAbs)) {
                            const auto ow = QMessageBox::warning(
                                this,
                                tr("Ya existe"),
                                tr("Ya existe un archivo llamado:\n%1\n\n¿Deseas sobrescribirlo?")
                                    .arg(QFileInfo(desiredAbs).fileName()),
                                QMessageBox::Yes | QMessageBox::No,
                                QMessageBox::No
                                );
                            if (ow != QMessageBox::Yes) {
                                // si no quiere sobrescribir, cae a "mantener nombre"
                            } else {
                                QFile::remove(desiredAbs);
                            }
                        }

                        // Renombrar el archivo actual -> desiredAbs
                        bool renamed = QFile::rename(m_currentFilePath, desiredAbs);
                        if (!renamed) {
                            // fallback copy+remove
                            if (QFile::copy(m_currentFilePath, desiredAbs)) {
                                QFile::remove(m_currentFilePath);
                                renamed = true;
                            }
                        }

                        if (!renamed) {
                            QMessageBox::warning(
                                this,
                                tr("No se pudo renombrar"),
                                tr("No se pudo renombrar el archivo.\nSe guardará manteniendo el nombre actual.")
                                );
                            // mantener targetPath como estaba
                        } else {
                            targetPath = desiredAbs;
                        }
                    }
                }
            }
        }
    }

    // ✅ normaliza porcentajes antes de serializar (evita errores por Ctrl+S / export)
    if (interactive) {
        for (auto *r : cortes()) {
            if (r) r->normalizePercentFields();
        }
    }

    ensureProyectoFromContext(filePath);
    actualizarTimestampDesdeUi();

    const QJsonObject root = buildFullJson(filePath);
    const QJsonDocument doc(root);
    const QByteArray data = doc.toJson(QJsonDocument::Indented);

    QFile file(targetPath);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        if (interactive) {
            QMessageBox::warning(this, tr("Error al guardar"),
                                 tr("No se pudo abrir el archivo para escritura:\n%1")
                                     .arg(file.errorString()));
        }
        return false;
    }

    file.write(data);
    file.close();

    // Sync paths desde JSON
    if (root.contains("images") && root.value("images").isObject()) {
        const QJsonObject imgs = root.value("images").toObject();

        auto norm = [](QString s) {
            s = s.trimmed();
            return s.isEmpty() ? QString() : QDir::cleanPath(QDir::fromNativeSeparators(s));
        };

        const QString p1 = norm(imgs.value("foto1_path").toString());
        const QString p2 = norm(imgs.value("foto2_path").toString());
        const QString p3 = norm(imgs.value("foto3_path").toString());

        if (!p1.isEmpty()) m_foto1RelPath = p1;
        if (!p2.isEmpty()) m_foto2RelPath = p2;
        if (!p3.isEmpty()) m_foto3RelPath = p3;

        const QString lm = norm(imgs.value("logo_mtc_path").toString());
        const QString lp = norm(imgs.value("logo_proyecto_path").toString());
        if (!lm.isEmpty()) m_logoMtcRelPath = lm;
        if (!lp.isEmpty()) m_logoProyectoRelPath = lp;
    }

    if (interactive && !m_noEditableWarnShown && editableRootForPath(filePath).isEmpty()) {
        m_noEditableWarnShown = true;
        QMessageBox::information(
            this,
            tr("Carpeta editable no encontrada"),
            tr("No se encontró una carpeta marcada como editable (.ingep_editable.json).\n"
               "Las imágenes se guardaron embebidas en el JSON (modo compatible).\n\n"
               "Recomendación: marca una carpeta como editable dentro del proyecto para guardar fotos como JPG en /fotos.")
            );
    }

    m_currentFilePath = targetPath;
    this->setProperty("calicataFilePath", QDir::cleanPath(QDir::fromNativeSeparators(targetPath)));

    m_baseWindowTitle = tr("Ficha de Calicata (%1)").arg(QFileInfo(targetPath).fileName());
    setDirtyInternal(false);

    captureHistorySnapshot();
    // ✅ Ahora sí, avisamos al editor que el nombre visible cambió (por path real)
    emit displayNameChanged(displayName());

    return true;

}




void CalicataWindow::guardarInterno()
{
    if (!m_currentFilePath.isEmpty())
        guardarEnArchivo(m_currentFilePath);
    else
        guardarComoInterno();  // ✅
}

void CalicataWindow::guardarComoInterno()
{
    const QString basePath = baseProjectsPath();

    QString suggestedName;
    if (ui->txtProgresiva && !ui->txtProgresiva->text().isEmpty())
        suggestedName = ui->txtProgresiva->text();
    else
        suggestedName = "calicata";

    GuardarCalicataDialog dlg(basePath, suggestedName, this);
    if (dlg.exec() != QDialog::Accepted)
        return;

    QString folder   = dlg.selectedFolder();
    QString fileName = dlg.fileName().trimmed();

    // ✅ IMPORTANTÍSIMO: desde aquí ya sabemos el folder real => úsalo como contexto
    this->setProperty("calicataFilePath", folder);

    // ✅ Precargar título automático SI aún no hay uno en memoria
    if (m_tituloTestificacion.trimmed().isEmpty()) {
        const QString autoTitle = loadExcelTitleFromEditableMeta(folder).trimmed();
        if (!autoTitle.isEmpty()) {
            m_tituloTestificacion = autoTitle;

            if (ui && ui->btnTituloCalicata) {
                ui->btnTituloCalicata->setToolTip(m_tituloTestificacion);
                ui->btnTituloCalicata->setText(tr("Título ✓"));
            }
        } else {
            // si no hay meta editable, deja el botón “vacío”
            if (ui && ui->btnTituloCalicata) {
                ui->btnTituloCalicata->setToolTip(QString());
                ui->btnTituloCalicata->setText(tr("Título\nCalicata"));
            }
        }
    }



    if (fileName.isEmpty()) {
        QMessageBox::warning(this, tr("Nombre de archivo vacío"),
                             tr("Debes indicar un nombre para la ficha."));
        return;
    }

    static const QRegularExpression invalid(R"([\/\\\:\*\?\"\<\>\|])");
    fileName.replace(invalid, "_");

    QDir dir(folder);
    QString fullPath = dir.absoluteFilePath(fileName);
    if (!fullPath.endsWith(".calicata.json", Qt::CaseInsensitive))
        fullPath += ".calicata.json";

    // ✅ AQUÍ:
    this->setProperty("calicataFilePath", normPath(fullPath));

    if (QFileInfo::exists(fullPath)) {
        auto ret = QMessageBox::question(
            this,
            tr("Sobrescribir archivo"),
            tr("Ya existe una ficha con ese nombre.\n¿Deseas sobrescribirla?"),
            QMessageBox::Yes | QMessageBox::No,
            QMessageBox::No
            );
        if (ret != QMessageBox::Yes)
            return;
    }

    ensureProyectoFromContext(folder);
    guardarEnArchivo(fullPath);
}

// ------------------------------------------------------------
// Cargar desde archivo
// ------------------------------------------------------------
bool CalicataWindow::cargarDesdeArchivo(const QString &filePath)
{
    const QString absReal = absPathPreserveCase(filePath);   // tu helper
    const QString key     = openKeyForAbs(absReal);          // tu helper (para comparar)

    QFile file(absReal);
    if (!file.open(QIODevice::ReadOnly)) {
        QMessageBox::warning(this, tr("Error al abrir"),
                             tr("No se pudo abrir el archivo:\n%1")
                                 .arg(file.errorString()));
        return false;
    }

    const QByteArray data = file.readAll();
    file.close();

    QJsonParseError err;
    const QJsonDocument doc = QJsonDocument::fromJson(data, &err);
    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        QMessageBox::warning(this, tr("Error"),
                             tr("El archivo no contiene un JSON válido:\n%1")
                                 .arg(err.errorString()));
        return false;
    }

    // ✅ ruta real (para UI y títulos)
    m_currentFilePath = absReal;
    setProperty("calicataFilePath", absReal);

    // ✅ clave para detectar duplicados en el editor
    setProperty("_openKey", key);

    // --- reseteos ---
    m_logoMtcPix = QPixmap();
    m_logoProyectoPix = QPixmap();
    m_foto1Pix = QPixmap();
    m_foto2Pix = QPixmap();
    m_foto3Pix = QPixmap();
    m_logoMtcIsCustom = false;
    m_logoProyectoIsCustom = false;

    m_foto1RelPath.clear();
    m_foto2RelPath.clear();
    m_foto3RelPath.clear();
    m_logoMtcRelPath.clear();
    m_logoProyectoRelPath.clear();

    // ✅ carga JSON
    m_loading = true;
    applyFullJson(doc.object(), absReal);
    m_loading = false;

    ensureProyectoFromContext(absReal);

    m_baseWindowTitle = tr("Ficha de Calicata (%1)").arg(QFileInfo(absReal).fileName());
    setDirtyInternal(false);

    refreshAllButtonPixmaps();

    // =========================================================
    // ✅ Fix de CASE: si prog == fileStem ignorando mayúsculas,
    //    entonces iguala el texto al case del archivo SIN dirty.
    // =========================================================
    if (ui && ui->txtProgresiva) {
        const QString fileStem = fileStemPreserveCase(absReal);
        const QString prog     = ui->txtProgresiva->text().trimmed();

        if (!fileStem.isEmpty()) {

            // si prog vacío -> rellena sin ensuciar
            if (prog.isEmpty()) {
                m_loading = true;
                ui->txtProgresiva->setText(fileStem);
                m_loading = false;
                m_timestamp.calicata = fileStem;
            }
            // si solo cambia el case -> corrige sin ensuciar
            else if (prog.compare(fileStem, Qt::CaseInsensitive) == 0 && prog != fileStem) {
                m_loading = true;
                ui->txtProgresiva->setText(fileStem);
                m_loading = false;
                m_timestamp.calicata = fileStem;
            }
            // si realmente es distinto -> ahí sí tu diálogo (opcional)
            else if (prog.compare(fileStem, Qt::CaseInsensitive) != 0) {
                // tu diálogo mismatch si lo quieres mantener...
            }
        }
    }

    emit displayNameChanged(displayName());
    resetHistoryFromCurrentState();
    return true;
}


// ------------------------------------------------------------
// Close / Resize
// ------------------------------------------------------------
void CalicataWindow::closeEvent(QCloseEvent *event)
{
    if (guardarSiEsNecesario())
        event->accept();
    else
        event->ignore();
}

void CalicataWindow::resizeEvent(QResizeEvent *event)
{
    QMainWindow::resizeEvent(event);
    refreshAllButtonPixmaps();
}

// ------------------------------------------------------------
// API pública para el Editor
// ------------------------------------------------------------
void CalicataWindow::guardar()
{
    guardarInterno();

    QString p = !m_currentFilePath.isEmpty()
                    ? m_currentFilePath
                    : property("calicataFilePath").toString();

    const QString abs = QFileInfo(p).absoluteFilePath();
    if (!abs.isEmpty()) {
        if (auto *ctx = AppContext::instance())
            ctx->notifyLocalFileModified(abs);
    }
}

void CalicataWindow::guardarComo()
{
    guardarComoInterno();

    QString p = !m_currentFilePath.isEmpty()
                    ? m_currentFilePath
                    : property("calicataFilePath").toString();

    const QString abs = QFileInfo(p).absoluteFilePath();
    if (!abs.isEmpty()) {
        if (auto *ctx = AppContext::instance())
            ctx->notifyLocalFileModified(abs);
    }
}



void CalicataWindow::on_btnTituloCalicata_clicked()
{
    const QString ctx = !m_currentFilePath.isEmpty()
    ? m_currentFilePath
    : property("calicataFilePath").toString();

    if (ctx.trimmed().isEmpty()) {
        QMessageBox::information(this, tr("Sin contexto"),
                                 tr("Primero abre o guarda una ficha para poder editar el título."));
        return;
    }

    // Precargar con lo último guardado en .ingep_editable.json (solo lectura, NO escribimos)
    const QString lastSaved = loadExcelTitleFromEditableMeta(ctx).trimmed();

    const QString initial = !m_tituloTestificacion.trimmed().isEmpty()
                                ? m_tituloTestificacion.trimmed()
                                : lastSaved;

    MultiLineTextDialog dlg(tr("Título de la testificación"), initial, this);
    if (dlg.exec() != QDialog::Accepted)
        return;

    const QString newTitle = dlg.text().trimmed();
    const QString oldTitle = m_tituloTestificacion;

    if (newTitle != oldTitle) {
        m_tituloTestificacion = newTitle;
        marcarComoModificado();
    }
    // UI del botón
    if (ui && ui->btnTituloCalicata) {
        ui->btnTituloCalicata->setToolTip(m_tituloTestificacion);
        ui->btnTituloCalicata->setText(m_tituloTestificacion.isEmpty()
                                           ? tr("Título\nCalicata")
                                           : tr("Título ✓"));
    }

    // IMPORTANTE:
    // Aquí NO llamamos a saveExcelTitleToEditableMeta(...),
    // porque eso cambiaría el título GLOBAL de la carpeta editable.
}



void CalicataWindow::updateWindowTitle()
{
    QString base = m_tituloTestificacion.trimmed();
    if (base.isEmpty()) base = tr("Calicata");
    QMainWindow::setWindowTitle(m_dirty ? (base + "*") : base);
}




void CalicataWindow::setDirtyInternal(bool dirty)
{
    if (m_dirty == dirty) return;
    m_dirty = dirty;
    updateWindowTitle();
    emit dirtyChanged(m_dirty);
}

void CalicataWindow::setAutoSaveEnabled(bool enabled)
{
    m_autoSaveEnabled = enabled;
    if (!m_autoSaveTimer) return;

    if (m_autoSaveEnabled) m_autoSaveTimer->start();
    else m_autoSaveTimer->stop();
}


void CalicataWindow::setTituloTestificacion(const QString &t, bool markDirty)
{
    const QString nt = t.trimmed();
    if (m_tituloTestificacion == nt)
        return;

    m_tituloTestificacion = nt;

    if (ui && ui->btnTituloCalicata) {
        ui->btnTituloCalicata->setToolTip(m_tituloTestificacion);
        ui->btnTituloCalicata->setText(m_tituloTestificacion.isEmpty()
                                           ? tr("Título")
                                           : tr("Título ✓"));
    }

    if (markDirty) {
        setDirtyInternal(true);
    }

    updateWindowTitle(); // ✅
}

void CalicataWindow::applyExternalEditableTitle(const QString& t)
{
    const QString nt = t.trimmed();
    if (nt.isEmpty()) return;
    if (nt == m_tituloTestificacion) return;

    m_tituloTestificacion = nt;

    // Refrescar UI del botón, igual que haces en on_btnTituloCalicata_clicked
    if (ui && ui->btnTituloCalicata) {
        ui->btnTituloCalicata->setToolTip(m_tituloTestificacion);
        ui->btnTituloCalicata->setText(m_tituloTestificacion.isEmpty()
                                           ? tr("Título\nCalicata")
                                           : tr("Título ✓"));
    }

    // OJO: NO llamamos setDirtyInternal(true)
    // porque esto ya fue guardado y solo sincronizamos memoria/UI.
}


void CalicataWindow::applyExternalEditableLogos(const QString& mtcRelPath,
                                                const QString& proyectoRelPath)
{
    const QString ctx = !m_currentFilePath.isEmpty()
    ? m_currentFilePath
    : property("calicataFilePath").toString();

    auto clean = [](QString s){
        s = s.trimmed();
        return s.isEmpty() ? QString() : QDir::cleanPath(QDir::fromNativeSeparators(s));
    };

    const QString mtc = clean(mtcRelPath);
    const QString pro = clean(proyectoRelPath);

    auto loadLogo = [&](const QString& rel)->QPixmap{
        if (rel.isEmpty()) return QPixmap();
        const QString abs = resolveResourceAbsPath(rel, ctx);
        if (!QFileInfo::exists(abs)) return QPixmap();
        return QPixmap(abs);
    };

    // ✅ Solo aplicar shared si el usuario NO ha hecho override
    if (!m_logoMtcIsCustom) {
        if (mtc.isEmpty()) {
            m_logoMtcRelPath.clear();
            m_logoMtcPix = QPixmap();
        } else {
            QPixmap p = loadLogo(mtc);
            if (!p.isNull()) {
                m_logoMtcRelPath = mtc;
                m_logoMtcPix = p;
                // ❌ NO pongas m_logoMtcIsCustom=true aquí
            }
        }
    }

    if (!m_logoProyectoIsCustom) {
        if (pro.isEmpty()) {
            m_logoProyectoRelPath.clear();
            m_logoProyectoPix = QPixmap();
        } else {
            QPixmap p = loadLogo(pro);
            if (!p.isNull()) {
                m_logoProyectoRelPath = pro;
                m_logoProyectoPix = p;
                // ❌ NO pongas m_logoProyectoIsCustom=true aquí
            }
        }
    }

    refreshAllButtonPixmaps(); // NO dirty
}

void CalicataWindow::exportSingleJsonToExcelWithBusy(const QString& jsonPath, const QString& outXlsx)
{
    if (m_exportingSingle) return;
    m_exportingSingle = true;

    QProgressDialog *busy = makeBusy(this, tr("Exportando a Excel..."), /*cancellable=*/false);

    auto *watcher = new QFutureWatcher<QString>(this);

    connect(watcher, &QFutureWatcher<QString>::finished, this, [=]() {
        busy->close();
        busy->deleteLater();

        const QString err = watcher->result(); // "" si OK
        watcher->deleteLater();

        m_exportingSingle = false;

        if (!err.isEmpty()) {
            QMessageBox::warning(this, tr("Error"), err);
        } else {
            QMessageBox::information(this, tr("Listo"),
                                     tr("Excel exportado en:\n%1").arg(outXlsx));
        }
    });

    // Ejecuta el trabajo pesado fuera del hilo UI
    watcher->setFuture(QtConcurrent::run([=]() -> QString {
        // ✅ aquí llamas tu export real (la que hoy haces en modo bloqueante)
        // Ejemplo:
        // bool ok = CalicataExcelExporter::exportOne(jsonPath, outXlsx);
        // return ok ? QString() : "No se pudo exportar.";

        const bool ok = /*TU_EXPORT_AQUI*/ true;

        return ok ? QString() : QObject::tr("No se pudo exportar a Excel.");
    }));
}

QString CalicataWindow::canonicalAbs(const QString& path) const
{
    QFileInfo fi(path);
    QString abs = fi.canonicalFilePath();
    if (abs.isEmpty())
        abs = fi.absoluteFilePath();
    return QDir::cleanPath(abs);
}

void CalicataWindow::openCalicataFile(const QString& path)
{
    const QString abs = canonicalAbs(path);
    if (abs.isEmpty()) return;

    // Si ya es el mismo archivo, solo enfoca
    if (m_currentFilePath == abs) {
        this->raise();
        this->activateWindow();
        return;
    }

    // Si había otro archivo abierto, lo desregistras primero
    if (!m_currentFilePath.isEmpty()) {
        if (auto ctx = AppContext::instance())
            ctx->unregisterOpenFile(m_currentFilePath);
    }

    m_currentFilePath = abs;
    m_missingOnDisk = false;

    // Registrar en AppContext para controlar el archivo abierto.
    if (auto ctx = AppContext::instance())
        ctx->registerOpenFile(m_currentFilePath);

    // Watcher: limpia y vuelve a observar archivo + carpeta contenedora
    // (fileChanged a veces “se cae” en Windows, por eso limpiamos y re-agregamos)
    if (!m_watcher.files().isEmpty())       m_watcher.removePaths(m_watcher.files());
    if (!m_watcher.directories().isEmpty()) m_watcher.removePaths(m_watcher.directories());

    m_watcher.addPath(m_currentFilePath);
    m_watcher.addPath(QFileInfo(m_currentFilePath).absolutePath());

    // TODO: aquí llama TU función real de “cargar archivo”
    // Ejemplos (ajusta a tu código):
    // cargarDesdeArchivo(m_currentFilePath);
    // abrirArchivo(m_currentFilePath);
    // loadJson(m_currentFilePath);

    this->raise();
    this->activateWindow();
}

void CalicataWindow::closeTabByAbs(const QString& abs)
{
    // Compatibilidad: si alguien llama "closeTabByAbs" desde código viejo,
    // cerramos este editor solo si corresponde al archivo actual.
    const QString a = canonicalAbs(abs);
    if (a.isEmpty()) return;

    if (m_currentFilePath == a) {
        if (auto ctx = AppContext::instance())
            ctx->unregisterOpenFile(m_currentFilePath);

        m_currentFilePath.clear();
        m_missingOnDisk = false;

        if (!m_watcher.files().isEmpty())       m_watcher.removePaths(m_watcher.files());
        if (!m_watcher.directories().isEmpty()) m_watcher.removePaths(m_watcher.directories());

        this->close();
    }
}

void CalicataWindow::onWatchedPathChanged(const QString&)
{
    if (m_currentFilePath.isEmpty()) return;

    const bool exists = QFileInfo::exists(m_currentFilePath);
    if (exists) {
        // En Windows, luego de fileChanged a veces se deja de observar;
        // re-agrega para seguir vigilando.
        if (!m_watcher.files().contains(m_currentFilePath))
            m_watcher.addPath(m_currentFilePath);
        return;
    }

    if (!m_missingOnDisk) {
        m_missingOnDisk = true;

        QMessageBox::warning(this, tr("Archivo eliminado"),
                             tr("El archivo que estabas editando fue eliminado o movido.\n"
                                "Usa \"Guardar como...\" para guardarlo en otra ubicación."));
    }
}
