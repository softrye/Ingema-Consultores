#include "corterowwidget.h"
#include "ui_corterowwidget.h"
#include "jsonwidgetserializer.h"

#include <QComboBox>
#include <QToolButton>
#include <QLineEdit>
#include <QTextEdit>

#include <QMouseEvent>
#include <QEvent>
#include <QApplication>

#include <QDrag>
#include <QMimeData>
#include <QDataStream>

#include <QAbstractItemView>
#include <QListView>
#include <QFontMetrics>
#include <QSignalBlocker>
#include <QRegularExpression>
#include <QRegularExpressionValidator>
#include <QLocale>
#include <QtMath>
#include <QTimer>



static inline bool notEmpty(const QString &s)
{
    return !s.trimmed().isEmpty();
}

// ------------------------------------------------------------
// asegurar items + popup ancho (para que no se vea "M...o")
// ------------------------------------------------------------
void CorteRowWidget::ensureComboItems(QComboBox *cb, const QStringList &items, bool allowEmpty)
{
    if (!cb) return;

    // Si el .ui ya tiene items, no los tocamos, pero sí afinamos el popup
    if (cb->count() > 0) {
        tuneComboPopup(cb);
        return;
    }

    const QSignalBlocker b(cb);

    if (allowEmpty)
        cb->addItem("");

    for (const QString &it : items)
        cb->addItem(it);

    tuneComboPopup(cb);
}

void CorteRowWidget::tuneComboPopup(QComboBox *cb)
{
    if (!cb) return;

    QAbstractItemView *v = cb->view();
    if (!v) return;

    // evita el “...” (si el view es QListView)
    if (auto *lv = qobject_cast<QListView*>(v)) {
        lv->setTextElideMode(Qt::ElideNone);
        lv->setUniformItemSizes(true);
    }

    int maxW = 0;
    QFontMetrics fm(v->font());
    for (int i = 0; i < cb->count(); ++i) {
        const QString t = cb->itemText(i);
#if QT_VERSION >= QT_VERSION_CHECK(5, 11, 0)
        maxW = qMax(maxW, fm.horizontalAdvance(t));
#else
        maxW = qMax(maxW, fm.width(t));
#endif
    }

    // margen extra + scrollbar
    const int extra = 48;
    const int minW = qMax(140, maxW + extra);

    v->setMinimumWidth(minW);
    cb->setMaxVisibleItems(12);
}

namespace {


static constexpr double kDepthMaxMeters  = 3.00;
static constexpr double kDepthStepMeters = 0.05;
static constexpr int kDepthDecimals = 2;

static QStringList buildDepthItems(double maxValue, double step, int decimals)
{
    QStringList out;

    if (step <= 0.0 || maxValue < 0.0)
        return out;

    const double factor = qPow(10.0, decimals);
    const int count = qRound(maxValue / step);

    out.reserve(count + 1);
    for (int i = 0; i <= count; ++i) {
        double v = i * step;
        v = qRound64(v * factor) / factor;
        out << QString::number(v, 'f', decimals);
    }

    return out;
}

static void resetDepthCombo(QComboBox *cb,
                            double maxValue,
                            double step,
                            int decimals,
                            bool allowEmpty = true)
{
    if (!cb)
        return;

    const QSignalBlocker b(cb);
    const QString prevText = cb->currentText().trimmed();

    cb->clear();
    cb->setEditable(false);

    if (allowEmpty)
        cb->addItem("");

    cb->addItems(buildDepthItems(maxValue, step, decimals));

    const int idxPrev = cb->findText(prevText);
    if (idxPrev >= 0) {
        cb->setCurrentIndex(idxPrev);
    } else if (allowEmpty) {
        cb->setCurrentIndex(0);
    } else {
        cb->setCurrentIndex(cb->count() > 0 ? 0 : -1);
    }
}


// Selecciona todo al entrar (igual que tu otro filtro, pero local aquí)
class SelectAllOnFocusFilter2 : public QObject
{
public:
    explicit SelectAllOnFocusFilter2(QObject *parent=nullptr) : QObject(parent) {}
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

// Normaliza texto -> "NNN(.d..)%"
static void normalizePercentLineEdit(QLineEdit *le)
{
    if (!le) return;

    const int decimals = le->property("_pctDecimals").toInt(); // 0/1/2
    QString t = le->text().trimmed();
    if (t.isEmpty()) return;

    // quitar % y espacios
    t.remove('%');
    t = t.trimmed();

    // si quedó "48." o "48," -> "48"
    if (t.endsWith('.') || t.endsWith(',')) t.chop(1);

    // aceptar coma o punto
    t.replace(',', '.');

    bool ok = false;
    double v = QLocale::c().toDouble(t, &ok);
    if (!ok) v = QLocale().toDouble(t, &ok);

    if (!ok) {
        le->clear();
        return;
    }

    // clamp típico de porcentaje
    v = qBound(0.0, v, 100.0);

    // redondeo a N decimales
    const double p = qPow(10.0, decimals);
    v = qRound64(v * p) / p;

    le->setText(QString::number(v, 'f', decimals) + "%");
}

static void setupPercentLineEdit(QLineEdit *le, int decimals)
{
    if (!le) return;

    le->setProperty("_pctDecimals", decimals);
    le->setAlignment(Qt::AlignCenter);
    le->setClearButtonEnabled(false);

    // Validator: 0-3 dígitos + opcional separador + hasta N decimales + opcional %
    // (dejo % opcional para que si cargan datos viejos con %, no moleste)
    const QString pattern =
        QString(R"(^\s*\d{0,3}([\,\.]\d{0,%1})?\s*\%?\s*$)").arg(decimals);

    auto *val = new QRegularExpressionValidator(QRegularExpression(pattern), le);
    le->setValidator(val);

    le->installEventFilter(new SelectAllOnFocusFilter2(le));

    QObject::connect(le, &QLineEdit::editingFinished, le, [le](){
        normalizePercentLineEdit(le);
    });

    // Si ya viene con valor (por ejemplo al cargar), lo normaliza una vez
    // sin depender de que el usuario haga focus.
    {
        const QSignalBlocker b(le);
        normalizePercentLineEdit(le);
    }
}

} // namespace



CorteRowWidget::CorteRowWidget(QWidget *parent)
    : QWidget(parent), ui(new Ui::CorteRowWidget)
{
    ui->setupUi(this);

    // -------------------------
    // Profundidades DE / A
    // -------------------------
    resetDepthCombo(ui->txtDE, kDepthMaxMeters, kDepthStepMeters, kDepthDecimals, true);
    resetDepthCombo(ui->txtA,  kDepthMaxMeters, kDepthStepMeters, kDepthDecimals, true);

    // % automáticos (granulometría + humedad)
    setupPercentLineEdit(ui->txtGranuloMax,    0); // 100%
    setupPercentLineEdit(ui->txtGranulo2mm,    1); // 48.1%
    setupPercentLineEdit(ui->txtGranulo0_4mm,  1); // 31.5%
    setupPercentLineEdit(ui->txtGranulo0_08mm, 1); // 15.8%
    setupPercentLineEdit(ui->txtHumedad,       2); // 3.80%


    setAttribute(Qt::WA_StyledBackground, true);

    // -------------------------
    // Poblar combos (Humedad / Excavabilidad / Estabilidad)
    // -------------------------
    ensureComboItems(ui->cbHumedad,
                     { "Seco", "Bajo", "Medio", "Agua" },
                     /*allowEmpty*/ true);

    ensureComboItems(ui->cbExcavabilidad,
                     { "Rend. bajo", "Rend. medio", "Rend. alto", "Rend. muy alto" },
                     /*allowEmpty*/ true);

    ensureComboItems(ui->cbEstabilidad,
                     { "Baja", "Media", "Alta", "Muy Alta" },
                     /*allowEmpty*/ true);

    // -------------------------
    // Botón eliminar (X)
    // -------------------------
    if (ui->btnEliminarCorte) {
        ui->btnEliminarCorte->setText(QStringLiteral("✕"));
        ui->btnEliminarCorte->setToolTip(tr("Eliminar este corte"));
        ui->btnEliminarCorte->setAutoRaise(true);
        ui->btnEliminarCorte->setFocusPolicy(Qt::NoFocus);
        ui->btnEliminarCorte->setCursor(Qt::PointingHandCursor);
        ui->btnEliminarCorte->setFixedSize(18, 18);
        connect(ui->btnEliminarCorte, &QToolButton::clicked, this, [this]{
            emit solicitarEliminar(this);
        });
    }

    // -------------------------
    // Drag handle (header)
    // -------------------------
    if (auto *h = dragHandle()) {
        h->setCursor(Qt::OpenHandCursor);
        h->installEventFilter(this);

        // Si la X está dentro del header visualmente, que se note clickable
        if (ui->btnEliminarCorte)
            ui->btnEliminarCorte->setCursor(Qt::PointingHandCursor);
    }

    // Título inicial
    setCorteNumero(m_numero);
}

CorteRowWidget::~CorteRowWidget()
{
    delete ui;
}

void CorteRowWidget::setCorteNumero(int n)
{
    m_numero = n;
    if (ui->lblCorteTitulo)
        ui->lblCorteTitulo->setText(tr("Corte %1").arg(n));
}

int CorteRowWidget::corteNumero() const
{
    return m_numero;
}

QComboBox* CorteRowWidget::editDE() const
{
    return ui->txtDE;
}

QComboBox* CorteRowWidget::editA() const
{
    return ui->txtA;
}

QToolButton* CorteRowWidget::deleteButton() const
{
    return ui->btnEliminarCorte;
}

QJsonObject CorteRowWidget::toJson() const
{
    JsonWidgetSerializer::Options opt; // por defecto incluye todo
    return JsonWidgetSerializer::serialize(this, opt);
}

bool CorteRowWidget::hasMeaningfulData() const
{
    // OJO: NO contamos txtDE porque lo controla CalicataWindow.
    // Sí contamos txtA porque define el intervalo.
    if (ui->txtA && notEmpty(ui->txtA->currentText())) return true;

    if (ui->cbHumedad && notEmpty(ui->cbHumedad->currentText())) return true;
    if (ui->cbExcavabilidad && notEmpty(ui->cbExcavabilidad->currentText())) return true;
    if (ui->cbEstabilidad && notEmpty(ui->cbEstabilidad->currentText())) return true;

    if (ui->txtDescripcion && notEmpty(ui->txtDescripcion->toPlainText())) return true;

    if (ui->txtTipo && notEmpty(ui->txtTipo->text())) return true;
    if (ui->txtSUCS && notEmpty(ui->txtSUCS->text())) return true;
    if (ui->txtAASHTO && notEmpty(ui->txtAASHTO->text())) return true;

    if (ui->txtGranuloMax && notEmpty(ui->txtGranuloMax->text())) return true;
    if (ui->txtGranulo2mm && notEmpty(ui->txtGranulo2mm->text())) return true;
    if (ui->txtGranulo0_4mm && notEmpty(ui->txtGranulo0_4mm->text())) return true;
    if (ui->txtGranulo0_08mm && notEmpty(ui->txtGranulo0_08mm->text())) return true;

    if (ui->txtWL && notEmpty(ui->txtWL->text())) return true;
    if (ui->txtLP && notEmpty(ui->txtLP->text())) return true;
    if (ui->txtHumedad && notEmpty(ui->txtHumedad->text())) return true;

    return false;
}

void CorteRowWidget::clearUserData()
{
    // Limpia todo menos txtDE (porque lo calcula CalicataWindow)
    if (ui->txtA) {
        const QSignalBlocker b(ui->txtA);

        const int idxEmpty = ui->txtA->findText("");
        if (idxEmpty >= 0) {
            ui->txtA->setCurrentIndex(idxEmpty);
        } else {
            if (ui->txtA->isEditable()) ui->txtA->setEditText(QString());
            else ui->txtA->setCurrentIndex(-1);
        }
    }

    auto clearCombo = [](QComboBox *cb){
        if (!cb) return;
        const QSignalBlocker b(cb);
        const int idxEmpty = cb->findText("");
        if (idxEmpty >= 0) cb->setCurrentIndex(idxEmpty);
        else if (cb->count() > 0) cb->setCurrentIndex(0);
        else cb->setCurrentIndex(-1);
    };

    clearCombo(ui->cbHumedad);
    clearCombo(ui->cbExcavabilidad);
    clearCombo(ui->cbEstabilidad);

    if (ui->txtDescripcion) ui->txtDescripcion->clear();

    if (ui->txtTipo) ui->txtTipo->clear();
    if (ui->txtSUCS) ui->txtSUCS->clear();
    if (ui->txtAASHTO) ui->txtAASHTO->clear();

    if (ui->txtGranuloMax) ui->txtGranuloMax->clear();
    if (ui->txtGranulo2mm) ui->txtGranulo2mm->clear();
    if (ui->txtGranulo0_4mm) ui->txtGranulo0_4mm->clear();
    if (ui->txtGranulo0_08mm) ui->txtGranulo0_08mm->clear();

    if (ui->txtWL) ui->txtWL->clear();
    if (ui->txtLP) ui->txtLP->clear();
    if (ui->txtHumedad) ui->txtHumedad->clear();
}

void CorteRowWidget::fromJson(const QJsonObject& obj)
{
    // Para evitar cascadas raras mientras se aplican valores
    const QSignalBlocker blocker(this);

    JsonWidgetSerializer::Options opt;
    JsonWidgetSerializer::apply(this, obj, opt);

    // Si tienes campos derivados (DE, profundidad, etc.), recalcula aquí.
    // Ejemplos (ajusta a tus métodos reales):
    // recalcularDE();
    // actualizarUI();
}

// -------------------------------------------
// DRAG: handle (headerBar) o lblCorteTitulo
// -------------------------------------------
QWidget* CorteRowWidget::dragHandle() const
{
    if (m_cachedHandle)
        return m_cachedHandle;

    // Si existe un widget en el .ui con objectName "headerBar", úsalo.
    if (auto *hb = this->findChild<QWidget*>("headerBar")) {
        m_cachedHandle = hb;
        return m_cachedHandle;
    }

    // Fallback seguro: el label del título
    m_cachedHandle = ui->lblCorteTitulo;
    return m_cachedHandle;
}

bool CorteRowWidget::eventFilter(QObject *obj, QEvent *ev)
{
    QWidget *h = dragHandle();
    if (!h || obj != h)
        return QWidget::eventFilter(obj, ev);

    switch (ev->type()) {
    case QEvent::MouseButtonPress: {
        auto *me = static_cast<QMouseEvent*>(ev);
        if (me->button() == Qt::LeftButton) {
            m_pressPosInHandle = me->pos(); // coords del HANDLE
            h->setCursor(Qt::ClosedHandCursor);
        }
        return false;
    }
    case QEvent::MouseButtonRelease: {
        h->setCursor(Qt::OpenHandCursor);
        return false;
    }
    case QEvent::MouseMove: {
        auto *me = static_cast<QMouseEvent*>(ev);
        if (!(me->buttons() & Qt::LeftButton))
            return false;

        if ((me->pos() - m_pressPosInHandle).manhattanLength() < QApplication::startDragDistance())
            return false;

        // hotSpot = donde presionaste (PRESS), convertido a coords del ROW
        const QPoint hotSpotInRow = h->mapTo(this, m_pressPosInHandle);
        startDrag(hotSpotInRow);

        h->setCursor(Qt::OpenHandCursor);
        return true;
    }
    default:
        break;
    }

    return QWidget::eventFilter(obj, ev);
}

void CorteRowWidget::startDrag(const QPoint &hotSpotInRow)
{
    auto *drag = new QDrag(this);
    auto *mime = new QMimeData;

    QByteArray payload;
    {
        QDataStream ds(&payload, QIODevice::WriteOnly);
        ds << quintptr(this); // válido solo dentro del mismo proceso
    }

    mime->setData(CorteRowWidget::mimeTypeCorteRow(), payload);
    drag->setMimeData(mime);

    // Pixmap “snapshot” del row
    QPixmap pm = this->grab();
    drag->setPixmap(pm);

    // Hotspot en coords lógicas del pixmap
    drag->setHotSpot(hotSpotInRow);

    drag->exec(Qt::MoveAction, Qt::MoveAction);
}

void CorteRowWidget::normalizePercentFields()
{
    normalizePercentLineEdit(ui->txtGranuloMax);
    normalizePercentLineEdit(ui->txtGranulo2mm);
    normalizePercentLineEdit(ui->txtGranulo0_4mm);
    normalizePercentLineEdit(ui->txtGranulo0_08mm);
    normalizePercentLineEdit(ui->txtHumedad);
}
