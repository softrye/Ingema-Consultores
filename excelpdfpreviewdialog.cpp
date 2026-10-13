#include "excelpdfpreviewdialog.h"
#include "ingetheme.h"

#include <QPdfDocument>
#include <QPdfView>
#include <QPdfPageNavigator>
#include <QShortcut>
#include <QSpinBox>
#include <QPointF>

#include <QComboBox>
#include <QToolButton>
#include <QSlider>
#include <QLabel>

#include <QVBoxLayout>
#include <QHBoxLayout>

#include <QScrollBar>
#include <QMouseEvent>
#include <QWheelEvent>
#include <QKeyEvent>

#include <QApplication>
#include <QGuiApplication>
#include <QScreen>
#include <QMessageBox>
#include <QSignalBlocker>

static int clampInt(int v, int lo, int hi) { return (v < lo) ? lo : (v > hi) ? hi : v; }

ExcelPdfPreviewDialog::ExcelPdfPreviewDialog(const QMap<QString, QString>& sheetPdf, QWidget *parent)
    : QDialog(parent), m_sheetPdf(sheetPdf)
{
    setWindowTitle(tr("Vista previa (Excel \u2192 PDF)"));
    setModal(true);

    // permitir maximizar/restaurar + grip
    setWindowFlag(Qt::WindowMaximizeButtonHint, true);
    setWindowFlag(Qt::WindowMinimizeButtonHint, true);
    setSizeGripEnabled(true);

    // tamaño inicial grande (por si no maximizas desde afuera)
    if (QScreen *s = QGuiApplication::primaryScreen()) {
        const QRect r = s->availableGeometry();
        resize(int(r.width() * 0.92), int(r.height() * 0.88));
    }

    buildUi();

    // llenar combo
    for (auto it = m_sheetPdf.begin(); it != m_sheetPdf.end(); ++it)
        m_combo->addItem(it.key());

    if (m_combo->count() > 0)
        m_combo->setCurrentIndex(0);

    loadCurrentSheet();
    applyZoomModeToWidth();
}

void ExcelPdfPreviewDialog::buildUi()
{
    m_doc  = new QPdfDocument(this);
    m_view = new QPdfView(this);
    m_view->setDocument(m_doc);

    // toolbar top
    m_combo = new QComboBox(this);
    m_combo->setMinimumWidth(220);

    m_btnFitPage = new QToolButton(this);
    m_btnFitPage->setText(tr("Fit pág"));

    m_btnFitWidth = new QToolButton(this);
    m_btnFitWidth->setText(tr("Fit ancho"));

    m_btnReset = new QToolButton(this);
    m_btnReset->setText("100%");

    m_btnMinus = new QToolButton(this);
    m_btnMinus->setText("-");

    m_btnPlus = new QToolButton(this);
    m_btnPlus->setText("+");

    m_btnHand = new QToolButton(this);
    m_btnHand->setText(tr("Mano"));
    m_btnHand->setCheckable(true);

    m_zoomSlider = new QSlider(Qt::Horizontal, this);
    m_zoomSlider->setRange(10, 400);
    m_zoomSlider->setValue(100);
    m_zoomSlider->setFixedWidth(180);

    m_zoomLabel = new QLabel("100%", this);
    m_zoomLabel->setMinimumWidth(50);

    auto *top = new QHBoxLayout;
    top->addWidget(m_combo);
    top->addSpacing(10);
    top->addWidget(m_btnFitPage);
    top->addWidget(m_btnFitWidth);
    top->addWidget(m_btnReset);
    top->addSpacing(10);
    top->addWidget(m_btnMinus);
    top->addWidget(m_btnPlus);
    top->addWidget(m_btnHand);
    top->addSpacing(10);
    top->addWidget(m_zoomSlider);
    top->addWidget(m_zoomLabel);
    setupPageUi(top);
    top->addStretch(1);

    auto *root = new QVBoxLayout(this);
    root->addLayout(top);
    root->addWidget(m_view, 1);
    setLayout(root);

    // eventos para zoom/pan
    m_view->viewport()->installEventFilter(this);
    this->installEventFilter(this);
    m_view->setFocusPolicy(Qt::StrongFocus);

    // conexiones
    connect(m_combo, &QComboBox::currentIndexChanged, this, [this](){
        loadCurrentSheet();

        // mantener zoom como el usuario lo dejó
        if (m_userTouchedZoom) {
            setZoomPercent(m_userZoomPct, false);
        } else {
            applyZoomModeToWidth();
        }
    });

    connect(m_btnFitWidth, &QToolButton::clicked, this, [this](){ applyZoomModeToWidth(); });
    connect(m_btnFitPage,  &QToolButton::clicked, this, [this](){ applyZoomModeFitPage(); });
    connect(m_btnReset,    &QToolButton::clicked, this, [this](){ zoomReset100(); });
    connect(m_btnPlus,     &QToolButton::clicked, this, [this](){ zoomIn(); });
    connect(m_btnMinus,    &QToolButton::clicked, this, [this](){ zoomOut(); });

    connect(m_btnHand, &QToolButton::toggled, this, [this](bool on){
        setHandTool(on);
    });

    connect(m_zoomSlider, &QSlider::valueChanged, this, [this](int v){
        setZoomPercent(v, true);
    });

    if (auto nav = m_view->pageNavigator()) {
        connect(nav, &QPdfPageNavigator::currentPageChanged,
                this, [this](int){ refreshPageUi(); });
    }

}

void ExcelPdfPreviewDialog::loadCurrentSheet()
{
    const QString sheet = m_combo->currentText();
    const QString pdfPath = m_sheetPdf.value(sheet);

    if (pdfPath.isEmpty()) return;

    const auto err = m_doc->load(pdfPath);
    if (err != QPdfDocument::Error::None || m_doc->status() != QPdfDocument::Status::Ready) {
        QMessageBox::warning(this, tr("PDF"),
                             tr("No se pudo abrir el PDF:\n%1").arg(pdfPath));

    return;
    }
    setPageIndex(0);
    refreshPageUi();

}

void ExcelPdfPreviewDialog::applyZoomModeToWidth()
{
    m_userTouchedZoom = false;
    m_view->setZoomMode(QPdfView::ZoomMode::FitToWidth);
    // UI: mostramos el último zoom “real” (no perfecto en modo auto, pero suficiente)
    m_zoomLabel->setText(tr("Auto"));
}

void ExcelPdfPreviewDialog::applyZoomModeFitPage()
{
    m_userTouchedZoom = false;
    m_view->setZoomMode(QPdfView::ZoomMode::FitInView);
    m_zoomLabel->setText(tr("Auto"));
}

void ExcelPdfPreviewDialog::setZoomPercent(int pct, bool userAction)
{
    pct = clampInt(pct, 10, 400);

    if (userAction) {
        m_userTouchedZoom = true;
        m_userZoomPct = pct;
    }

    // modo custom + factor
    m_view->setZoomMode(QPdfView::ZoomMode::Custom);
    m_view->setZoomFactor(pct / 100.0);

    m_zoomLabel->setText(QString::number(pct) + "%");

    // evita “rebote” si el slider viene de otro lado
    if (m_zoomSlider->value() != pct) {
        const QSignalBlocker b(m_zoomSlider);
        m_zoomSlider->setValue(pct);
    }
}

void ExcelPdfPreviewDialog::zoomIn()
{
    const int cur = m_userTouchedZoom ? m_userZoomPct : int(m_view->zoomFactor() * 100.0 + 0.5);
    setZoomPercent(cur + 10, true);
}

void ExcelPdfPreviewDialog::zoomOut()
{
    const int cur = m_userTouchedZoom ? m_userZoomPct : int(m_view->zoomFactor() * 100.0 + 0.5);
    setZoomPercent(cur - 10, true);
}

void ExcelPdfPreviewDialog::zoomReset100()
{
    setZoomPercent(100, true);
}

void ExcelPdfPreviewDialog::setHandTool(bool on)
{
    m_handTool = on;
    if (!m_panning) {
        m_view->viewport()->setCursor(on ? Qt::OpenHandCursor : Qt::ArrowCursor);
    }
}

void ExcelPdfPreviewDialog::keyPressEvent(QKeyEvent *e)
{
    if (e->key() == Qt::Key_Space && !e->isAutoRepeat()) {
        m_spaceDown = true;
        if (!m_panning && !m_handTool)
            m_view->viewport()->setCursor(Qt::OpenHandCursor);
    }
    QDialog::keyPressEvent(e);
}

void ExcelPdfPreviewDialog::keyReleaseEvent(QKeyEvent *e)
{
    if (e->key() == Qt::Key_Space && !e->isAutoRepeat()) {
        m_spaceDown = false;
        if (!m_panning && !m_handTool)
            m_view->viewport()->setCursor(Qt::ArrowCursor);
    }
    QDialog::keyReleaseEvent(e);
}

bool ExcelPdfPreviewDialog::eventFilter(QObject *obj, QEvent *ev)
{
    // --- WHEEL ---
    if (obj == m_view->viewport() && ev->type() == QEvent::Wheel) {
        auto *we = static_cast<QWheelEvent*>(ev);

        // Algunas laptops/touchpads dan pixelDelta, otras angleDelta
        int dy = we->angleDelta().y();
        if (dy == 0) dy = we->pixelDelta().y();

        // CTRL + rueda = ZOOM
        if (we->modifiers().testFlag(Qt::ControlModifier)) {
            const int cur = m_userTouchedZoom
                                ? m_userZoomPct
                                : int(m_view->zoomFactor() * 100.0 + 0.5);

            setZoomPercent(cur + (dy > 0 ? 10 : -10), true);
            return true; // consumimos el evento (no scrollea)
        }

        // ALT + rueda = cambiar página (opcional)
        if (we->modifiers().testFlag(Qt::AltModifier)) {
            setPageIndex(currentPageIndex() + (dy < 0 ? 1 : -1));
            return true;
        }

        // rueda normal -> que QPdfView haga scroll normal
        return false;
    }

    // --- PAN (arrastre) ---
    if (obj == m_view->viewport()) {
        if (ev->type() == QEvent::MouseButtonPress) {
            auto *me = static_cast<QMouseEvent*>(ev);

            const bool allowLeft = (me->button() == Qt::LeftButton) && (m_handTool || m_spaceDown);
            const bool allowMid  = (me->button() == Qt::MiddleButton);

            if (allowLeft || allowMid) {
                m_panning = true;
                m_lastPanPos = me->pos();
                m_view->viewport()->setCursor(Qt::ClosedHandCursor);
                return true;
            }
        }
        else if (ev->type() == QEvent::MouseMove) {
            if (m_panning) {
                auto *me = static_cast<QMouseEvent*>(ev);
                const QPoint p = me->pos();
                const QPoint d = p - m_lastPanPos;
                m_lastPanPos = p;

                if (auto *hs = m_view->horizontalScrollBar())
                    hs->setValue(hs->value() - d.x());
                if (auto *vs = m_view->verticalScrollBar())
                    vs->setValue(vs->value() - d.y());

                return true;
            }
        }
        else if (ev->type() == QEvent::MouseButtonRelease) {
            auto *me = static_cast<QMouseEvent*>(ev);
            if (m_panning && (me->button() == Qt::LeftButton || me->button() == Qt::MiddleButton)) {
                m_panning = false;
                if (m_handTool || m_spaceDown)
                    m_view->viewport()->setCursor(Qt::OpenHandCursor);
                else
                    m_view->viewport()->setCursor(Qt::ArrowCursor);
                return true;
            }
        }
    }

    return QDialog::eventFilter(obj, ev);
}


void ExcelPdfPreviewDialog::setSinglePdfMode(bool on)
{
    if (m_combo) m_combo->setVisible(!on);   // si quieres, también puedes ocultar botones “hoja”
}

void ExcelPdfPreviewDialog::setupPageUi(QHBoxLayout* topRow)
{
    m_pageBar = new QWidget(this);
    auto* l = new QHBoxLayout(m_pageBar);
    l->setContentsMargins(0,0,0,0);
    l->setSpacing(6);

    m_btnPrevPage = new QToolButton(m_pageBar);
    m_btnPrevPage->setText("◀");
    m_btnPrevPage->setToolTip(tr("Página anterior (PgUp)"));

    m_btnNextPage = new QToolButton(m_pageBar);
    m_btnNextPage->setText("▶");
    m_btnNextPage->setToolTip(tr("Página siguiente (PgDn)"));

    m_pageSpin = new QSpinBox(m_pageBar);
    m_pageSpin->setMinimum(1);
    m_pageSpin->setMaximum(1);
    m_pageSpin->setValue(1);
    m_pageSpin->setFixedWidth(70);
    m_pageSpin->setToolTip(tr("Ir a página"));

    m_pageTotalLbl = new QLabel("/ 1", m_pageBar);

    l->addWidget(m_btnPrevPage);
    l->addWidget(m_btnNextPage);
    l->addSpacing(6);
    l->addWidget(m_pageSpin);
    l->addWidget(m_pageTotalLbl);

    topRow->addWidget(m_pageBar);

    // ---- Conexiones ----
    connect(m_btnPrevPage, &QToolButton::clicked, this, [this]{
        setPageIndex(currentPageIndex() - 1);
    });
    connect(m_btnNextPage, &QToolButton::clicked, this, [this]{
        setPageIndex(currentPageIndex() + 1);
    });
    connect(m_pageSpin, QOverload<int>::of(&QSpinBox::valueChanged), this, [this](int v){
        if (m_updatingPageUi) return;
        setPageIndex(v - 1);
    });

    // Atajos (opcional pero recomendado)
    (void) new QShortcut(QKeySequence(Qt::Key_PageUp),   this, [this]{ setPageIndex(currentPageIndex()-1); });
    (void) new QShortcut(QKeySequence(Qt::Key_PageDown), this, [this]{ setPageIndex(currentPageIndex()+1); });
    (void) new QShortcut(QKeySequence(Qt::Key_Home),     this, [this]{ setPageIndex(0); });
    (void) new QShortcut(QKeySequence(Qt::Key_End),      this, [this]{ setPageIndex(999999); });
}

int ExcelPdfPreviewDialog::currentPageIndex() const
{
    if (!m_view || !m_view->pageNavigator()) return 0;
    return m_view->pageNavigator()->currentPage();
}

void ExcelPdfPreviewDialog::setPageIndex(int page0)
{
    if (!m_doc || !m_view || !m_view->pageNavigator()) return;

    const int n = m_doc->pageCount();
    if (n <= 0) return;

    page0 = qBound(0, page0, n - 1);
    m_view->pageNavigator()->jump(page0, {}); // salta a esa página

    refreshPageUi();
}

void ExcelPdfPreviewDialog::refreshPageUi()
{
    if (!m_doc) return;
    if (!m_pageBar) return;
    const int n = m_doc->pageCount();
    const bool show = (n > 1);  // si quieres ocultarlo cuando solo hay 1 página
    m_pageBar->setVisible(show);

    m_updatingPageUi = true;
    m_pageSpin->setRange(1, qMax(1, n));
    m_pageTotalLbl->setText(QString("/ %1").arg(qMax(1, n)));

    const int cur0 = currentPageIndex();
    m_pageSpin->setValue(qBound(1, cur0 + 1, qMax(1, n)));

    m_btnPrevPage->setEnabled(cur0 > 0);
    m_btnNextPage->setEnabled(cur0 + 1 < n);
    m_updatingPageUi = false;
}
