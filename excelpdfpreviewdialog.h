#pragma once

#include <QDialog>
#include <QMap>
#include <QString>
#include <QToolButton>
#include <QSpinBox>
#include <QLabel>
#include <QHBoxLayout>


class QPdfDocument;
class QPdfView;
class QComboBox;
class QToolButton;
class QSlider;
class QLabel;

class ExcelPdfPreviewDialog : public QDialog
{
    Q_OBJECT
public:
    explicit ExcelPdfPreviewDialog(const QMap<QString, QString>& sheetPdf, QWidget *parent = nullptr);
    void setSinglePdfMode(bool on);


protected:
    bool eventFilter(QObject *obj, QEvent *ev) override;
    void keyPressEvent(QKeyEvent *e) override;
    void keyReleaseEvent(QKeyEvent *e) override;

private:
    void buildUi();
    void loadCurrentSheet();

    void applyZoomModeToWidth();
    void applyZoomModeFitPage();
    void setZoomPercent(int pct, bool userAction);

    void zoomIn();
    void zoomOut();
    void zoomReset100();

    void setHandTool(bool on);

    // --- UI páginas ---
    QWidget*     m_pageBar = nullptr;
    QToolButton* m_btnPrevPage = nullptr;
    QToolButton* m_btnNextPage = nullptr;
    QSpinBox*    m_pageSpin = nullptr;      // 1..N
    QLabel*      m_pageTotalLbl = nullptr;  // "/ N"

    bool m_updatingPageUi = false;

private:
    QMap<QString, QString> m_sheetPdf;

    QPdfDocument *m_doc = nullptr;
    QPdfView     *m_view = nullptr;

    QComboBox    *m_combo = nullptr;

    QToolButton  *m_btnFitPage = nullptr;
    QToolButton  *m_btnFitWidth = nullptr;
    QToolButton  *m_btnReset = nullptr;
    QToolButton  *m_btnMinus = nullptr;
    QToolButton  *m_btnPlus  = nullptr;
    QToolButton  *m_btnHand  = nullptr;

    QSlider      *m_zoomSlider = nullptr;
    QLabel       *m_zoomLabel  = nullptr;

    bool   m_handTool = false;
    bool   m_spaceDown = false;

    bool   m_panning = false;
    QPoint m_lastPanPos;

    bool m_userTouchedZoom = false;
    int  m_userZoomPct = 100;

    void setupPageUi(QHBoxLayout* topRow); // crea controles y los mete en la barra
    void refreshPageUi();                  // actualiza rango/visibilidad
    void setPageIndex(int page0);          // 0-based
    int  currentPageIndex() const;
};
