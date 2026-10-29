#include "ingetheme.h"

#include <QApplication>
#include <QPalette>
#include <QColor>
#include <QDialog>
#include <QEvent>
#include <QAbstractItemView>
#include <QMainWindow>
#include <QProxyStyle>
#include <QStyleFactory>
#include <QPainter>
#include <QPainterPath>



#ifdef Q_OS_WIN
#include <windows.h>
#include <dwmapi.h>
// MSVC:
#pragma comment(lib, "dwmapi.lib")
#endif

namespace IngeTheme {

static QPalette makePalette()
{
    QPalette p;

    const QColor navy   ("#005282");
    const QColor teal   ("#0087AE");
    const QColor accent ("#FDAC11");
    const QColor surface("#D9EDF3");
    const QColor base   ("#FFFFFF");
    const QColor text   ("#0F1F2A");
    const QColor white  ("#FFFFFF");

    p.setColor(QPalette::Window, surface);
    p.setColor(QPalette::WindowText, text);
    p.setColor(QPalette::Base, base);
    p.setColor(QPalette::AlternateBase, QColor("#CCE7EF"));
    p.setColor(QPalette::Text, text);
    p.setColor(QPalette::Button, base);
    p.setColor(QPalette::ButtonText, text);

    p.setColor(QPalette::Highlight, teal);
    p.setColor(QPalette::HighlightedText, white);

    p.setColor(QPalette::Link, teal);

    p.setColor(QPalette::ToolTipBase, QColor("#CCE7EF"));  // celeste claro
    p.setColor(QPalette::ToolTipText, QColor("#005282"));  // azul oscuro

    Q_UNUSED(accent);
    return p;
}

QString qss()
{
    return QString::fromUtf8(R"QSS(
* { outline: 0; }

/* ---------- Tooltips (nubes de descripción) ---------- */
QToolTip {
    background-color: #CCE7EF;          /* celeste claro */
    color: #005282;                     /* texto azul oscuro */
    border: 1px solid #005282;          /* borde azul oscuro */
    padding: 6px 8px;
    border-radius: 10px;
}


/* ---------- DateEdit / Calendar (InGe+) ---------- */
QDateEdit, QTimeEdit, QDateTimeEdit {
    background-color: #FFFFFF;
    color: #0F1F2A;
    border: 1px solid rgba(0,135,174,90);
    border-radius: 10px;
    padding: 4px 8px;
    selection-background-color: #0087AE;
    selection-color: #FFFFFF;
}

QDateEdit:focus, QTimeEdit:focus, QDateTimeEdit:focus {
    border: 2px solid rgba(0,135,174,180);
}

/* Flecha del DateEdit */
QDateEdit::drop-down {
    subcontrol-origin: padding;
    subcontrol-position: top right;
    width: 20px;
    border: none;
    background: transparent;
}

/* Popup general */
QCalendarWidget {
    background-color: #FFFFFF;
    color: #0F1F2A;
    border: 1px solid rgba(0,135,174,90);
    border-radius: 12px;
    min-width: 300px;
}

/* Barra superior del calendario */
QCalendarWidget QWidget#qt_calendar_navigationbar {
    background-color: #005282;
    color: #FFFFFF;
    border-top-left-radius: 12px;
    border-top-right-radius: 12px;
}

/* Flechas / mes / año */
QCalendarWidget QToolButton {
    background: transparent;
    color: #FFFFFF;
    border: none;
    padding: 4px 8px;
    font-weight: 700;
    border-radius: 8px;
}

QCalendarWidget QToolButton:hover {
    background-color: rgba(255,255,255,35);
}

QCalendarWidget QToolButton:pressed {
    background-color: rgba(255,255,255,55);
}

/* Año / controles internos */
QCalendarWidget QSpinBox,
QCalendarWidget QComboBox {
    background-color: #FFFFFF;
    color: #0F1F2A;
    border: 1px solid rgba(0,135,174,70);
    border-radius: 8px;
    padding: 2px 6px;
}

/* Tabla real de días: este es el fix principal del fondo negro */
QCalendarWidget QTableView {
    background-color: #FFFFFF;
    alternate-background-color: #F4FBFD;
    color: #0F1F2A;
    outline: 0;
    border: none;
    selection-background-color: #0087AE;
    selection-color: #FFFFFF;
    gridline-color: rgba(0,135,174,35);
}

/* Celdas de días */
QCalendarWidget QTableView::item {
    background: #FFFFFF;
    color: #0F1F2A;
    padding: 4px;
}

QCalendarWidget QTableView::item:hover {
    background: rgba(0,135,174,25);
    color: #0F1F2A;
}

QCalendarWidget QTableView::item:selected {
    background: #0087AE;
    color: #FFFFFF;
}

/* Días fuera del mes / deshabilitados */
QCalendarWidget QTableView::item:disabled {
    color: #9DBBC7;
    background: #FFFFFF;
}

/* Encabezado dom lun mar... */
QCalendarWidget QHeaderView::section {
    background-color: #D9EDF3;
    color: #005282;
    border: none;
    padding: 2px 0px;
    font-weight: 600;
    min-width: 30px;
}

/* ---------- Menús ---------- */
QMenu {
    background-color: #005282;
    color: #FFFFFF;
    border: 1px solid rgba(255,255,255,28);
    border-radius: 12px;
    padding: 4px;
}
QMenu::item {
    color: #FFFFFF;
    padding: 7px 12px;
    border-radius: 8px;
}
QMenu::item:selected {
    background: #FFFFFF;
    color: #0F1F2A;
}

/* ---- QMenu: items deshabilitados (visibles como “apagados”) ---- */
QMenu::item:disabled {
    color: rgba(255,255,255,110);          /* texto más tenue */
    background: transparent;
}

QMenu::item:disabled:selected,
QMenu::item:disabled:hover {
    background: transparent;               /* que NO se ponga blanco */
    color: rgba(255,255,255,110);
}


QMenu::separator {
    height: 1px;
    background: rgba(255,255,255,18);
    margin: 4px 6px;
}

/* ---------- Dialogs ---------- */
/* Nota: la titlebar del SO NO se puede con QSS. (La cambiamos con DWM en Windows) */
QDialog, QMessageBox, QInputDialog {
    background-color: #D9EDF3;
    color: #0F1F2A;
}

QDialog QLabel, QInputDialog QLabel, QMessageBox QLabel {
    color: #005282;
    font-weight: 600;
}

QLabel#qt_msgbox_label {
    color: #0F1F2A;
    font-weight: 600;
}

/* Inputs */
QDialog QLineEdit,
QDialog QTextEdit,
QDialog QPlainTextEdit,
QDialog QSpinBox,
QDialog QDoubleSpinBox,
QDialog QDateEdit,
QDialog QTimeEdit,
QDialog QDateTimeEdit,
QDialog QComboBox {
    background-color: #FFFFFF;
    color: #0F1F2A;
    border: 1px solid rgba(0,135,174,70);
    border-radius: 10px;
    padding: 6px 8px;
}
QDialog QLineEdit:focus,
QDialog QTextEdit:focus,
QDialog QPlainTextEdit:focus,
QDialog QSpinBox:focus,
QDialog QDoubleSpinBox:focus,
QDialog QDateEdit:focus,
QDialog QTimeEdit:focus,
QDialog QDateTimeEdit:focus,
QDialog QComboBox:focus {
    border: 2px solid rgba(0,135,174,180);
}

/* ✅ LISTAS/ÁRBOLES/TABLAS en dialogs (arregla “espacios blancos raros” y consistencia) */
/* ✅ LISTAS/ÁRBOLES/TABLAS en dialogs: todo blanco, con borde y hover */
QDialog QAbstractScrollArea {
    background-color: #FFFFFF;
    border: 1px solid rgba(0,135,174,70);
    border-radius: 10px;
}
QDialog QAbstractScrollArea::viewport {
    background-color: #FFFFFF;   /* ✅ evita que se vea el celeste del dialog detrás */
    border-radius: 10px;
}

/* ItemViews (QTreeView/QListView/QTableView) */
QDialog QAbstractItemView {
    background-color: #FFFFFF;
    alternate-background-color: #FFFFFF; /* ✅ sin zebra */
    color: #0F1F2A;
    selection-background-color: #0087AE;
    selection-color: #FFFFFF;
}

QDialog QAbstractItemView::item {
    padding: 6px 8px;
    background: transparent;
    color: #0F1F2A;
}

QDialog QAbstractItemView::item:hover {
    background-color: rgba(0,135,174,10); /* ✅ hover suave */
}

QDialog QAbstractItemView::item:selected {
    background-color: #0087AE;           /* ✅ “pressed” = seleccionado */
    color: #FFFFFF;
}

QDialog QAbstractItemView::item {
    padding: 6px 8px;
}
QDialog QHeaderView::section {
    background: #005282;
    color: #FFFFFF;
    padding: 6px 8px;
    border: none;
}

/* Combo popup dentro de dialogs */
QDialog QComboBoxPrivateContainer {
    background-color: #005282;
    border: 1px solid rgba(255,255,255,28);
    border-radius: 12px;
    padding: 4px;
}
QDialog QComboBoxPrivateContainer QAbstractItemView {
    background-color: #005282;
    border: none;
    color: #FFFFFF;
    border-radius: 10px;
}
QDialog QComboBoxPrivateContainer QAbstractItemView::item {
    padding: 6px 10px;
    color: #FFFFFF;
    background: transparent;
}
QDialog QComboBoxPrivateContainer QAbstractItemView::item:hover {
    background-color: #FFFFFF;
    color: #0F1F2A;
}
QDialog QComboBoxPrivateContainer QAbstractItemView::item:selected {
    background-color: rgba(255,255,255,220);
    color: #0F1F2A;
}

/* Botones */
QDialog QPushButton, QMessageBox QPushButton, QInputDialog QPushButton {
    background-color: #FFFFFF;
    color: #005282;
    border: 1px solid rgba(0,135,174,70);
    border-radius: 12px;
    padding: 8px 14px;
    font-weight: 700;
}
QDialog QPushButton:hover, QMessageBox QPushButton:hover, QInputDialog QPushButton:hover {
    background-color: rgba(0,135,174,6);
}
QDialog QPushButton:pressed, QMessageBox QPushButton:pressed, QInputDialog QPushButton:pressed {
    background-color: rgba(0,135,174,10);
}

/* Default -> naranja */
QDialog QPushButton:default,
QMessageBox QPushButton:default,
QInputDialog QPushButton:default {
    background-color: #FDAC11;
    color: #FFFFFF;
    border: 1px solid rgba(255,255,255,45);
}
QDialog QPushButton:default:hover,
QMessageBox QPushButton:default:hover,
QInputDialog QPushButton:default:hover {
    background-color: #FFB52B;
}
QDialog QPushButton:default:pressed,
QMessageBox QPushButton:default:pressed,
QInputDialog QPushButton:default:pressed {
    background-color: #E59A00;
}

/* Scrollbars en dialogs */
QDialog QScrollBar:vertical {
    background: transparent;
    width: 12px;
    margin: 0px;
}
QDialog QScrollBar::handle:vertical {
    background: rgba(0,135,174,55);
    min-height: 26px;
    border-radius: 6px;
}
QDialog QScrollBar::handle:vertical:hover { background: #0087AE; }
QDialog QScrollBar::add-line:vertical, QDialog QScrollBar::sub-line:vertical { height: 0px; }
)QSS");
}

#ifdef Q_OS_WIN
bool setNativeTitleBarColors(QWidget* w, const QColor& captionColor, const QColor& textColor)
{
    if (!w) return false;

    // fuerza handle nativo si aún no existe:
    w->winId();
    HWND hwnd = reinterpret_cast<HWND>(w->winId());
    if (!hwnd) return false;

    auto setAttr = [&](DWORD attr, const void* val, DWORD size) -> bool {
        return SUCCEEDED(DwmSetWindowAttribute(hwnd, attr, val, size));
    };

    const DWORD DWMWA_CAPTION_COLOR = 35;
    const DWORD DWMWA_TEXT_COLOR    = 36;
    const DWORD DWMWA_USE_IMMERSIVE_DARK_MODE_20 = 20;
    const DWORD DWMWA_USE_IMMERSIVE_DARK_MODE_19 = 19;

    COLORREF cap = RGB(captionColor.red(), captionColor.green(), captionColor.blue());
    setAttr(DWMWA_CAPTION_COLOR, &cap, sizeof(cap));

    COLORREF txt = RGB(textColor.red(), textColor.green(), textColor.blue());
    setAttr(DWMWA_TEXT_COLOR, &txt, sizeof(txt));

    // intenta modo oscuro de titlebar (no siempre aplica, pero ayuda a iconos/contraste)
    BOOL dark = TRUE;
    if (!setAttr(DWMWA_USE_IMMERSIVE_DARK_MODE_20, &dark, sizeof(dark))) {
        setAttr(DWMWA_USE_IMMERSIVE_DARK_MODE_19, &dark, sizeof(dark));
    }

    return true;
}
#endif

void polishDialog(QWidget* w)
{
    if (!w) return;

    // marca para no repetir:
    if (w->property("_inge_polished").toBool())
        return;
    w->setProperty("_inge_polished", true);

    // ✅ fuerza “sin zebra” en TODOS los item views del dialog
    const auto views = w->findChildren<QAbstractItemView*>();
    for (auto *v : views) {
        v->setAlternatingRowColors(false);
    }


    // asegura que el background de QSS se pinte bien
    w->setAttribute(Qt::WA_StyledBackground, true);

    // quita el botón de ayuda (?) típico
    if (auto dlg = qobject_cast<QDialog*>(w)) {
        dlg->setWindowFlag(Qt::WindowContextHelpButtonHint, false);
    }

    if (auto dlg = qobject_cast<QDialog*>(w)) {
        dlg->setStyleSheet(IngeTheme::qss());
    }


#ifdef Q_OS_WIN
    // ✅ “pestaña blanca” (titlebar nativa) -> azul oscuro
    setNativeTitleBarColors(w, QColor("#003A5E"), QColor("#FFFFFF"));
#endif
}


class IngeProxyStyle final : public QProxyStyle
{
public:
    IngeProxyStyle() : QProxyStyle(QStyleFactory::create("Fusion")) {}

    int pixelMetric(PixelMetric metric, const QStyleOption *opt, const QWidget *w) const override {
        if (metric == PM_IndicatorWidth || metric == PM_IndicatorHeight)
            return 16; // un poco más grande y visible
        return QProxyStyle::pixelMetric(metric, opt, w);
    }

    void drawPrimitive(PrimitiveElement element,
                       const QStyleOption *option,
                       QPainter *p,
                       const QWidget *widget) const override
    {
        if (element == PE_IndicatorItemViewItemCheck) {
            QRect r = option->rect;
            int s = qMin(r.width(), r.height());
            QRect box(r.left(), r.top(), s, s);
            box.adjust(0, 0, -1, -1);

            QColor border("#0087AE");   // teal
            QColor fill("#FFFFFF");
            QColor mark("#FFFFFF");

            const bool enabled = option->state & State_Enabled;
            const bool on      = option->state & State_On;
            const bool mixed   = option->state & State_NoChange;

            if (!enabled) {
                border = QColor(0,0,0,60);
                fill   = QColor("#F3F3F3");
                mark   = QColor(0,0,0,90);
            } else if (on) {
                fill = QColor("#0087AE");
            } else if (mixed) {
                fill = QColor("#FDAC11");
            }

            p->save();
            p->setRenderHint(QPainter::Antialiasing, true);

            p->setPen(QPen(border, 1.6));
            p->setBrush(fill);
            p->drawRoundedRect(box, 3, 3);

            // “check” / “menos” (indeterminado)
            p->setPen(QPen(mark, 2.2, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));

            if (mixed) {
                p->drawLine(QPointF(box.left() + box.width()*0.25, box.center().y()),
                            QPointF(box.right() - box.width()*0.25, box.center().y()));
            } else if (on) {
                QPainterPath path;
                path.moveTo(box.left() + box.width()*0.22, box.top() + box.height()*0.55);
                path.lineTo(box.left() + box.width()*0.43, box.top() + box.height()*0.72);
                path.lineTo(box.left() + box.width()*0.78, box.top() + box.height()*0.28);
                p->drawPath(path);
            }

            p->restore();
            return;
        }

        QProxyStyle::drawPrimitive(element, option, p, widget);
    }
};


// Auto-aplica el polish a cualquier QDialog que aparezca
class AutoPolishFilter : public QObject
{
public:
    using QObject::QObject;

protected:
    bool eventFilter(QObject* obj, QEvent* ev) override
    {
        if (ev->type() == QEvent::Show) {
            QWidget* w = qobject_cast<QWidget*>(obj);
            if (!w) return QObject::eventFilter(obj, ev);

            // Solo dialogs (QMessageBox, QInputDialog, etc. también son QDialog)
            if (qobject_cast<QDialog*>(w) || qobject_cast<QMainWindow*>(w)) {
                polishDialog(w);
            }
        }
        return QObject::eventFilter(obj, ev);
    }
};

static AutoPolishFilter* g_filter = nullptr;

void apply(QApplication& app)
{
    app.setStyle(new IngeProxyStyle());
    app.setPalette(makePalette());
    app.setStyleSheet(qss());

    if (!g_filter) {
        g_filter = new AutoPolishFilter(&app);
        app.installEventFilter(g_filter);
    }
}





} // namespace IngeTheme
