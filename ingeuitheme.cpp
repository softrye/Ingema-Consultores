#include "ingeuitheme.h"

#include <QApplication>
#include <QWidget>
#include <QDialog>
#include <QMessageBox>
#include <QEvent>
#include <QDialogButtonBox>
#include <QAbstractButton>
#include <QPushButton>
#include <QStyle>

#ifdef Q_OS_WIN
#include <windows.h>
#include <dwmapi.h>
#pragma comment(lib, "dwmapi.lib")

// Si tu SDK no trae estos defines, los ponemos:
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

#ifndef DWMWA_CAPTION_COLOR
#define DWMWA_CAPTION_COLOR 35
#endif

#ifndef DWMWA_TEXT_COLOR
#define DWMWA_TEXT_COLOR 36
#endif
#endif

InGeUiTheme::InGeUiTheme(QObject* parent)
    : QObject(parent)
{
}

void InGeUiTheme::install(QApplication* app)
{
    if (!app) return;

    // 1) Añadimos nuestro QSS al existente (sin pisar lo que ya tengas)
    const QString existing = app->styleSheet();
    const QString ours     = buildDialogQss();
    app->setStyleSheet(existing + "\n\n" + ours);

    // 2) Event filter para “marcar” y pulir cada diálogo automáticamente
    app->installEventFilter(new InGeUiTheme(app));
}

bool InGeUiTheme::eventFilter(QObject* obj, QEvent* ev)
{
    if (!obj || !ev) return QObject::eventFilter(obj, ev);

    // Cuando un widget se muestra, si es QDialog/QMessageBox lo pulimos
    if (ev->type() == QEvent::Show) {
        auto* w = qobject_cast<QWidget*>(obj);
        if (!w) return QObject::eventFilter(obj, ev);

        // Ojo: QMenu también es popup, pero aquí nos enfocamos en QDialog/QMessageBox
        if (qobject_cast<QDialog*>(w) || qobject_cast<QMessageBox*>(w) || w->inherits("QDialog")) {
            polishDialog(w);
        }
    }

    // También puede pasar que winId exista recién luego:
    if (ev->type() == QEvent::WinIdChange) {
        auto* w = qobject_cast<QWidget*>(obj);
        if (w && (qobject_cast<QDialog*>(w) || qobject_cast<QMessageBox*>(w) || w->inherits("QDialog"))) {
            applyWinCaptionColorIfPossible(w);
        }
    }

    return QObject::eventFilter(obj, ev);
}

void InGeUiTheme::polishDialog(QWidget* w)
{
    if (!w) return;

    if (w->property(kPropPolished).toBool())
        return;

    w->setProperty(kPropDlg, true);
    w->setProperty(kPropPolished, true);

    // Asegura que el background del QSS se pinte
    w->setAttribute(Qt::WA_StyledBackground, true);

    // QDialog: quitar el botón ? de ayuda si apareciera
    if (auto* dlg = qobject_cast<QDialog*>(w)) {
        dlg->setWindowFlag(Qt::WindowContextHelpButtonHint, false);
    }

    // Ajustes útiles para botones en QDialogButtonBox:
    for (auto* box : w->findChildren<QDialogButtonBox*>()) {
        const auto buttons = box->buttons();
        for (auto* b : buttons) {
            if (auto* pb = qobject_cast<QPushButton*>(b)) {
                pb->setCursor(Qt::PointingHandCursor);
            }
        }

        // Si no hay default, intenta marcar uno “aceptar” como default para que agarre estilo :default
        bool hasDefault = false;
        for (auto* b : buttons) {
            if (auto* pb = qobject_cast<QPushButton*>(b)) {
                if (pb->isDefault()) { hasDefault = true; break; }
            }
        }

        if (!hasDefault) {
            if (auto* ok = box->button(QDialogButtonBox::Ok)) ok->setDefault(true);
            else if (auto* yes = box->button(QDialogButtonBox::Yes)) yes->setDefault(true);
            else if (auto* save = box->button(QDialogButtonBox::Save)) save->setDefault(true);
        }
    }

    // Re-polish para aplicar de inmediato
    w->style()->unpolish(w);
    w->style()->polish(w);
    w->update();

    // Intento: titlebar/caption en Windows
    applyWinCaptionColorIfPossible(w);
}

QString InGeUiTheme::buildDialogQss()
{
    // Paleta InGe+:
    // Navy #005282, Teal #0087AE, Accent #FDAC11
    // Dialog BG suave: #DCEEF4 (como tus screenshots)

    return QString::fromUtf8(R"QSS(
/* =========================================================
   InGe+ — Dialog Theme (solo para QDialog con property ingepDlg=true)
   ========================================================= */

QDialog[ingepDlg="true"],
QMessageBox[ingepDlg="true"] {
    background-color: #DCEEF4;
}

/* Tipografía / texto */
QDialog[ingepDlg="true"] QLabel,
QMessageBox[ingepDlg="true"] QLabel {
    color: #0F1F2A;
    font-size: 12px;
}

/* Labels de QMessageBox (Qt usa estos objectName) */
QMessageBox[ingepDlg="true"] QLabel#qt_msgbox_label,
QMessageBox[ingepDlg="true"] QLabel#qt_msgbox_informativelabel {
    color: #0F1F2A;
}

/* Inputs */
QDialog[ingepDlg="true"] QLineEdit,
QDialog[ingepDlg="true"] QTextEdit,
QDialog[ingepDlg="true"] QPlainTextEdit,
QDialog[ingepDlg="true"] QSpinBox,
QDialog[ingepDlg="true"] QDoubleSpinBox,
QDialog[ingepDlg="true"] QDateEdit,
QDialog[ingepDlg="true"] QTimeEdit,
QDialog[ingepDlg="true"] QDateTimeEdit,
QDialog[ingepDlg="true"] QComboBox {
    background: #FFFFFF;
    color: #0F1F2A;
    border: 1px solid rgba(0,82,130,70);
    border-radius: 10px;
    padding: 6px 10px;
    selection-background-color: rgba(0,135,174,60);
}

QDialog[ingepDlg="true"] QLineEdit:focus,
QDialog[ingepDlg="true"] QTextEdit:focus,
QDialog[ingepDlg="true"] QPlainTextEdit:focus,
QDialog[ingepDlg="true"] QComboBox:focus {
    border: 1px solid rgba(0,135,174,180);
}

/* Combo arrow */
QDialog[ingepDlg="true"] QComboBox::drop-down {
    border-left: 1px solid rgba(0,82,130,45);
    width: 28px;
}
QDialog[ingepDlg="true"] QComboBox::down-arrow {
    width: 10px; height: 10px;
}

/* Views (aquí se arregla tu “zona blanca/negra rara” de árboles/listas) */
QDialog[ingepDlg="true"] QTreeView,
QDialog[ingepDlg="true"] QListView,
QDialog[ingepDlg="true"] QTableView {
    background: #F9FEFF;
    alternate-background-color: #F2FAFD;
    color: #0F1F2A;

    border: 1px solid rgba(0,82,130,70);
    border-radius: 10px;
    padding: 4px;
}

QDialog[ingepDlg="true"] QTreeView::viewport,
QDialog[ingepDlg="true"] QListView::viewport,
QDialog[ingepDlg="true"] QTableView::viewport {
    background: #F9FEFF;
}

QDialog[ingepDlg="true"] QTreeView::item,
QDialog[ingepDlg="true"] QListView::item {
    padding: 6px 6px;
    border-radius: 6px;
}

QDialog[ingepDlg="true"] QTreeView::item:selected,
QDialog[ingepDlg="true"] QListView::item:selected,
QDialog[ingepDlg="true"] QTableView::item:selected {
    background: rgba(0,135,174,60);
    color: #0F1F2A;
}

/* Header de tablas / tree header: evita el header negro del CacheImagePickerDialog */
QDialog[ingepDlg="true"] QHeaderView::section {
    background: #00324E;
    color: #FFFFFF;
    padding: 6px 8px;
    border: none;
}

/* Scrollbars */
QDialog[ingepDlg="true"] QScrollBar:vertical {
    background: transparent;
    width: 10px;
    margin: 6px 2px;
}
QDialog[ingepDlg="true"] QScrollBar::handle:vertical {
    background: rgba(0,82,130,90);
    border-radius: 5px;
    min-height: 20px;
}
QDialog[ingepDlg="true"] QScrollBar::handle:vertical:hover {
    background: rgba(0,135,174,140);
}
QDialog[ingepDlg="true"] QScrollBar::add-line:vertical,
QDialog[ingepDlg="true"] QScrollBar::sub-line:vertical {
    height: 0px;
}

/* Botones */
QDialog[ingepDlg="true"] QPushButton,
QMessageBox[ingepDlg="true"] QPushButton {
    background: #FFFFFF;
    color: #005282;
    border: 1px solid rgba(0,135,174,140);
    border-radius: 10px;
    padding: 7px 14px;
}

QDialog[ingepDlg="true"] QPushButton:hover,
QMessageBox[ingepDlg="true"] QPushButton:hover {
    background: rgba(0,135,174,18);
}

QDialog[ingepDlg="true"] QPushButton:pressed,
QMessageBox[ingepDlg="true"] QPushButton:pressed {
    background: rgba(0,135,174,26);
}

/* Default button (OK / Yes / Save) => Accent */
QDialog[ingepDlg="true"] QPushButton:default,
QMessageBox[ingepDlg="true"] QPushButton:default {
    background: #FDAC11;
    color: #111111;
    border: 1px solid rgba(0,0,0,18);
    font-weight: bold;
}

QDialog[ingepDlg="true"] QPushButton:disabled,
QMessageBox[ingepDlg="true"] QPushButton:disabled {
    background: rgba(255,255,255,60);
    color: rgba(0,82,130,120);
    border: 1px solid rgba(0,82,130,40);
}

/* QDialogButtonBox spacing */
QDialog[ingepDlg="true"] QDialogButtonBox {
    padding-top: 6px;
}

/* Tooltips dentro de dialogs */
QDialog[ingepDlg="true"] QToolTip {
    background: #00324E;
    color: #FFFFFF;
    border: 1px solid rgba(255,255,255,35);
    padding: 6px;
    border-radius: 8px;
}
)QSS");
}

void InGeUiTheme::applyWinCaptionColorIfPossible(QWidget* w)
{
#ifdef Q_OS_WIN
    if (!w) return;
    if (!w->isWindow()) return;

    // Forzar winId
    HWND hwnd = reinterpret_cast<HWND>(w->winId());
    if (!hwnd) return;

    // 1) Intento: caption color azul oscuro
    // Nota: en algunos Windows esto puede ser ignorado.
    const COLORREF caption = RGB(0x00, 0x32, 0x4E); // #00324E
    const COLORREF text    = RGB(0xFF, 0xFF, 0xFF);

    HRESULT hr1 = DwmSetWindowAttribute(hwnd, DWMWA_CAPTION_COLOR, &caption, sizeof(caption));
    HRESULT hr2 = DwmSetWindowAttribute(hwnd, DWMWA_TEXT_COLOR, &text, sizeof(text));

    // 2) Fallback: dark mode caption (si el color no aplica)
    if (FAILED(hr1) || FAILED(hr2)) {
        BOOL useDark = TRUE;
        DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, &useDark, sizeof(useDark));
    }
#else
    (void)w;
#endif
}
