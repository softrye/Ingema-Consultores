#include "calicatamapdialog.h"
#include "mapcontroller.h"
#include "gpsmanager.h"

#include <QQuickWidget>
#include <QQmlContext>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QGridLayout>
#include <QLabel>
#include <QLineEdit>
#include <QTimeEdit>
#include <QToolButton>
#include <QPushButton>
#include <QShortcut>
#include <QMessageBox>
#include <QCloseEvent>
#include <QTime>
#include <QGeoCoordinate>
#include <QAction>
#include <QStyle>
#include <QApplication>

namespace {

static QString noDecimals(double v)
{
    return QString::number(static_cast<qlonglong>(v));
}

static bool parseZoneText(const QString& text, int& zone, QChar& band)
{
    const QString t = text.trimmed().toUpper();
    if (t.size() < 2)
        return false;

    QString digits;
    for (int i = 0; i < t.size(); ++i) {
        if (t[i].isDigit()) {
            digits += t[i];
        } else {
            zone = digits.toInt();
            band = t[i];
            return (zone >= 1 && zone <= 60 && band.isLetter());
        }
    }
    return false;
}

static bool parseDoubleLoose(QString s, double& out)
{
    s = s.trimmed();
    s.replace(",", ".");
    bool ok = false;
    out = s.toDouble(&ok);
    return ok;
}

} // namespace

CalicataMapDialog::CalicataMapDialog(QWidget *parent)
    : QDialog(parent)
{
    setWindowTitle(tr("Mapa interactivo de coordenadas"));
    setModal(false);
    setAttribute(Qt::WA_DeleteOnClose, true);
    resize(760, 620);

    auto *rootLay = new QVBoxLayout(this);
    rootLay->setContentsMargins(10, 10, 10, 10);
    rootLay->setSpacing(8);

    auto *topRow = new QHBoxLayout();
    auto *title = new QLabel(tr("Vista interactiva de coordenadas"), this);
    title->setStyleSheet("font-weight:700; font-size:12pt; color:#1B2A4E;");

    QIcon undoIcon = QIcon::fromTheme("edit-undo");
    if (undoIcon.isNull())
        undoIcon = style()->standardIcon(QStyle::SP_ArrowBack);

    QIcon redoIcon = QIcon::fromTheme("edit-redo");
    if (redoIcon.isNull())
        redoIcon = style()->standardIcon(QStyle::SP_ArrowForward);

    m_btnUndo = new QToolButton(this);
    m_btnUndo->setText(tr("Deshacer"));
    m_btnUndo->setIcon(undoIcon);
    m_btnUndo->setToolButtonStyle(Qt::ToolButtonTextBesideIcon);
    m_btnUndo->setToolTip(tr("Deshacer (Ctrl+Z)"));
    m_btnUndo->setCursor(Qt::PointingHandCursor);
    m_btnUndo->setAutoRaise(false);
    m_btnUndo->setMinimumHeight(30);
    m_btnUndo->setMinimumWidth(105);
    m_btnUndo->setIconSize(QSize(16, 16));

    m_btnRedo = new QToolButton(this);
    m_btnRedo->setText(tr("Rehacer"));
    m_btnRedo->setIcon(redoIcon);
    m_btnRedo->setToolButtonStyle(Qt::ToolButtonTextBesideIcon);
    m_btnRedo->setToolTip(tr("Rehacer (Ctrl+Y / Ctrl+Shift+Z)"));
    m_btnRedo->setCursor(Qt::PointingHandCursor);
    m_btnRedo->setAutoRaise(false);
    m_btnRedo->setMinimumHeight(30);
    m_btnRedo->setMinimumWidth(105);
    m_btnRedo->setIconSize(QSize(16, 16));

    const QString historyBtnQss =
        "QToolButton {"
        "  background: #FFFFFF;"
        "  color: #12324A;"
        "  border: 1px solid #A9C7DA;"
        "  border-radius: 8px;"
        "  padding: 6px 10px;"
        "  font-weight: 600;"
        "}"
        "QToolButton:hover {"
        "  background: #F3FAFF;"
        "  border: 1px solid #6FAFD0;"
        "}"
        "QToolButton:pressed {"
        "  background: #E7F3FB;"
        "}"
        "QToolButton:disabled {"
        "  background: #F3F3F3;"
        "  color: #9A9A9A;"
        "  border: 1px solid #D7D7D7;"
        "}";

    m_btnUndo->setStyleSheet(historyBtnQss);
    m_btnRedo->setStyleSheet(historyBtnQss);

    topRow->addWidget(title);
    topRow->addStretch();
    topRow->addWidget(m_btnUndo);
    topRow->addWidget(m_btnRedo);

    rootLay->addLayout(topRow);

    m_mapQuick = new QQuickWidget(this);
    m_mapQuick->setResizeMode(QQuickWidget::SizeRootObjectToView);
    m_mapQuick->setMinimumHeight(340);
    rootLay->addWidget(m_mapQuick, 1);

    auto *grid = new QGridLayout();
    grid->setHorizontalSpacing(8);
    grid->setVerticalSpacing(6);

    auto mkRO = [this]() -> QLineEdit* {
        auto *e = new QLineEdit(this);
        e->setReadOnly(true);
        e->setAlignment(Qt::AlignLeft | Qt::AlignVCenter);
        return e;
    };

    int r = 0;
    grid->addWidget(new QLabel(tr("Sistema"), this), r, 0);
    auto *txtSistema = mkRO();
    txtSistema->setText("UTM");
    grid->addWidget(txtSistema, r, 1);

    ++r;
    grid->addWidget(new QLabel(tr("Zona"), this), r, 0);
    m_txtZona = mkRO();
    grid->addWidget(m_txtZona, r, 1);

    ++r;
    grid->addWidget(new QLabel(tr("Coordenada X"), this), r, 0);
    m_txtX = mkRO();
    grid->addWidget(m_txtX, r, 1);

    ++r;
    grid->addWidget(new QLabel(tr("Coordenada Y"), this), r, 0);
    m_txtY = mkRO();
    grid->addWidget(m_txtY, r, 1);

    ++r;
    grid->addWidget(new QLabel(tr("Altitud"), this), r, 0);
    m_txtAlt = mkRO();
    m_txtAlt->setText("N/D");
    grid->addWidget(m_txtAlt, r, 1);

    ++r;
    grid->addWidget(new QLabel(tr("Hora"), this), r, 0);
    m_timeHora = new QTimeEdit(this);
    m_timeHora->setDisplayFormat("HH:mm:ss");
    m_timeHora->setReadOnly(true);
    m_timeHora->setTime(QTime::currentTime());
    grid->addWidget(m_timeHora, r, 1);

    rootLay->addLayout(grid);

    auto *bottomRow = new QHBoxLayout();
    bottomRow->addStretch();

    m_btnApply = new QPushButton(tr("Aplicar"), this);
    m_btnAccept = new QPushButton(tr("Aceptar"), this);
    m_btnClose = new QPushButton(tr("Cerrar"), this);

    bottomRow->addWidget(m_btnApply);
    bottomRow->addWidget(m_btnAccept);
    bottomRow->addWidget(m_btnClose);

    rootLay->addLayout(bottomRow);

    m_mapController = new MapController(this);
    m_mapController->setGpsActive(false);
    m_mapController->setFollowGps(false);

    connect(m_mapController, &MapController::coordinatePicked,
            this, &CalicataMapDialog::onCoordinatePicked);

    connect(m_mapController, &MapController::manualDragStarted,
            this, &CalicataMapDialog::onManualDragStarted);

    connect(m_mapController, &MapController::manualDragFinished,
            this, &CalicataMapDialog::onManualDragFinished);

    m_mapQuick->rootContext()->setContextProperty("mapController", m_mapController);
    m_mapQuick->setSource(QUrl(QStringLiteral("qrc:/qml/MapWidget.qml")));

    connect(m_btnUndo, &QToolButton::clicked, this, &CalicataMapDialog::onUndo);
    connect(m_btnRedo, &QToolButton::clicked, this, &CalicataMapDialog::onRedo);
    connect(m_btnApply, &QPushButton::clicked, this, &CalicataMapDialog::onApplyClicked);
    connect(m_btnAccept, &QPushButton::clicked, this, &CalicataMapDialog::onAcceptClicked);
    connect(m_btnClose, &QPushButton::clicked, this, &QDialog::close);

    auto *actUndo = new QAction(this);
    actUndo->setShortcut(QKeySequence::Undo); // Ctrl+Z
    actUndo->setShortcutContext(Qt::WidgetWithChildrenShortcut);
    this->addAction(actUndo);
    connect(actUndo, &QAction::triggered, this, &CalicataMapDialog::onUndo);

    auto *actRedoY = new QAction(this);
    actRedoY->setShortcut(QKeySequence(QStringLiteral("Ctrl+Y")));
    actRedoY->setShortcutContext(Qt::WidgetWithChildrenShortcut);
    this->addAction(actRedoY);
    connect(actRedoY, &QAction::triggered, this, &CalicataMapDialog::onRedo);

    auto *actRedoShiftZ = new QAction(this);
    actRedoShiftZ->setShortcut(QKeySequence(QStringLiteral("Ctrl+Shift+Z")));
    actRedoShiftZ->setShortcutContext(Qt::WidgetWithChildrenShortcut);
    this->addAction(actRedoShiftZ);
    connect(actRedoShiftZ, &QAction::triggered, this, &CalicataMapDialog::onRedo);

    refreshUiState();
}

bool CalicataMapDialog::sameCoord(const QGeoCoordinate& a, const QGeoCoordinate& b) const
{
    if (!a.isValid() && !b.isValid()) return true;
    if (!a.isValid() || !b.isValid()) return false;
    return a.distanceTo(b) < 0.01; // 1 cm aprox
}

QGeoCoordinate CalicataMapDialog::currentCoord() const
{
    return m_mapController ? m_mapController->coordinate() : QGeoCoordinate();
}

void CalicataMapDialog::setInitialCoordinate(const QGeoCoordinate& coord)
{
    if (!coord.isValid() || !m_mapController)
        return;

    m_mapController->setGpsActive(false);
    m_mapController->setFollowGps(false);
    m_mapController->setCoordinate(coord);

    updateFieldsFromCoordinate(coord);
    resetHistory(coord);
}

void CalicataMapDialog::setInitialFromUtm(const QString& zoneText,
                                          const QString& xText,
                                          const QString& yText)
{
    int zone = 0;
    QChar band;
    double x = 0.0;
    double y = 0.0;

    if (!parseZoneText(zoneText, zone, band))
        return;
    if (!parseDoubleLoose(xText, x))
        return;
    if (!parseDoubleLoose(yText, y))
        return;

    GpsManager::UTMCoord utm;
    utm.zone = zone;
    utm.band = band;
    utm.easting = x;
    utm.northing = y;

    QGeoCoordinate coord;
    if (GpsManager::fromUTM(utm, coord))
        setInitialCoordinate(coord);
}

void CalicataMapDialog::updateFieldsFromCoordinate(const QGeoCoordinate& coord)
{
    if (!coord.isValid())
        return;

    GpsManager::UTMCoord utm;
    if (!GpsManager::toUTM(coord, utm))
        return;

    if (m_txtZona)
        m_txtZona->setText(QString("%1%2").arg(utm.zone).arg(utm.band));
    if (m_txtX)
        m_txtX->setText(noDecimals(utm.easting));
    if (m_txtY)
        m_txtY->setText(noDecimals(utm.northing));
    if (m_txtAlt)
        m_txtAlt->setText("N/D");
    if (m_timeHora)
        m_timeHora->setTime(QTime::currentTime());
}

void CalicataMapDialog::resetHistory(const QGeoCoordinate& coord)
{
    m_history.clear();

    if (coord.isValid()) {
        m_history.append(coord);
        m_historyIndex = 0;
        m_lastAppliedCoord = coord;
    } else {
        m_historyIndex = -1;
        m_lastAppliedCoord = QGeoCoordinate();
    }

    m_hasPendingChanges = false;
    refreshUiState();
}

void CalicataMapDialog::pushHistory(const QGeoCoordinate& coord)
{
    if (!coord.isValid())
        return;

    if (m_historyIndex >= 0 && m_historyIndex < m_history.size()) {
        if (sameCoord(m_history[m_historyIndex], coord)) {
            updateFieldsFromCoordinate(coord);
            m_hasPendingChanges = !sameCoord(coord, m_lastAppliedCoord);
            refreshUiState();
            return;
        }
    }

    while (m_history.size() - 1 > m_historyIndex)
        m_history.removeLast();

    m_history.append(coord);
    m_historyIndex = m_history.size() - 1;

    updateFieldsFromCoordinate(coord);
    m_hasPendingChanges = !sameCoord(coord, m_lastAppliedCoord);
    refreshUiState();
}

void CalicataMapDialog::loadHistoryIndex(int index)
{
    if (index < 0 || index >= m_history.size())
        return;
    if (!m_mapController)
        return;

    m_historyIndex = index;
    const QGeoCoordinate coord = m_history[index];

    m_mapController->setGpsActive(false);
    m_mapController->setFollowGps(false);
    m_mapController->setCoordinate(coord);

    updateFieldsFromCoordinate(coord);
    m_hasPendingChanges = !sameCoord(coord, m_lastAppliedCoord);
    refreshUiState();
}

void CalicataMapDialog::refreshUiState()
{
    if (m_btnUndo)
        m_btnUndo->setEnabled(m_historyIndex > 0);

    if (m_btnRedo)
        m_btnRedo->setEnabled(m_historyIndex >= 0 && m_historyIndex < (m_history.size() - 1));

    if (m_btnApply)
        m_btnApply->setEnabled(m_hasPendingChanges);
}

void CalicataMapDialog::onCoordinatePicked(const QGeoCoordinate& coord)
{
    if (!coord.isValid())
        return;

    // Durante el drag: solo actualizar vista, NO historial
    if (m_dragSequenceActive) {
        updateFieldsFromCoordinate(coord);
        m_hasPendingChanges = !sameCoord(coord, m_lastAppliedCoord);
        refreshUiState();
        return;
    }

    // Click/doble click o cambio puntual: sí guardar historial
    pushHistory(coord);
}

void CalicataMapDialog::onUndo()
{
    if (m_historyIndex > 0)
        loadHistoryIndex(m_historyIndex - 1);
}

void CalicataMapDialog::onRedo()
{
    if (m_historyIndex >= 0 && m_historyIndex < (m_history.size() - 1))
        loadHistoryIndex(m_historyIndex + 1);
}

void CalicataMapDialog::applyCurrentToExternal()
{
    const QGeoCoordinate coord = currentCoord();
    if (!coord.isValid())
        return;

    updateFieldsFromCoordinate(coord);

    emit manualUtmChosen(
        m_txtZona ? m_txtZona->text() : QString(),
        m_txtX ? m_txtX->text() : QString(),
        m_txtY ? m_txtY->text() : QString(),
        m_txtAlt ? m_txtAlt->text() : QString(),
        coord
        );

    m_lastAppliedCoord = coord;
    m_hasPendingChanges = false;
    refreshUiState();
}

bool CalicataMapDialog::askPendingChanges(PendingPromptMode mode, bool* outShouldClose)
{
    if (outShouldClose)
        *outShouldClose = false;

    if (!m_hasPendingChanges)
        return true;

    QMessageBox msg(this);
    msg.setIcon(QMessageBox::Question);
    msg.setWindowTitle(tr("Cambiar coordenadas"));

    if (mode == PendingPromptMode::ApplyOnly) {
        msg.setText(tr("Se detectaron nuevas coordenadas en la vista previa."));
        msg.setInformativeText(tr("¿Deseas aplicarlas a la ficha actual?"));
    } else {
        msg.setText(tr("Hay nuevas coordenadas sin aplicar."));
        msg.setInformativeText(tr("¿Deseas aplicarlas a la ficha actual antes de cerrar?"));
    }

    auto *btnYes = msg.addButton(tr("Sí"), QMessageBox::YesRole);
    auto *btnNo = msg.addButton(tr("No"), QMessageBox::NoRole);
    auto *btnCancel = msg.addButton(tr("Cancelar"), QMessageBox::RejectRole);

    msg.exec();

    if (msg.clickedButton() == btnYes) {
        applyCurrentToExternal();
        if (outShouldClose)
            *outShouldClose = (mode == PendingPromptMode::CloseDialog);
        return true;
    }

    if (msg.clickedButton() == btnNo) {
        if (mode == PendingPromptMode::CloseDialog) {
            if (outShouldClose)
                *outShouldClose = true;
            return true;
        }
        return false;
    }

    Q_UNUSED(btnCancel);
    return false;
}

void CalicataMapDialog::onApplyClicked()
{
    bool shouldClose = false;
    if (askPendingChanges(PendingPromptMode::ApplyOnly, &shouldClose)) {
        Q_UNUSED(shouldClose);
    }
}

void CalicataMapDialog::onAcceptClicked()
{
    bool shouldClose = false;
    if (!m_hasPendingChanges) {
        m_allowImmediateClose = true;
        accept();
        return;
    }

    if (askPendingChanges(PendingPromptMode::CloseDialog, &shouldClose) && shouldClose) {
        m_allowImmediateClose = true;
        accept();
    }
}

void CalicataMapDialog::closeEvent(QCloseEvent *event)
{
    if (m_allowImmediateClose) {
        event->accept();
        return;
    }

    if (!m_hasPendingChanges) {
        event->accept();
        return;
    }

    bool shouldClose = false;
    if (askPendingChanges(PendingPromptMode::CloseDialog, &shouldClose) && shouldClose) {
        event->accept();
    } else {
        event->ignore();
    }
}


void CalicataMapDialog::onManualDragStarted(const QGeoCoordinate& coord)
{
    m_dragSequenceActive = true;
    m_dragStartCoord = coord;
}

void CalicataMapDialog::onManualDragFinished(const QGeoCoordinate& coord)
{
    const QGeoCoordinate finalCoord = coord.isValid() ? coord : currentCoord();
    const bool moved = !sameCoord(m_dragStartCoord, finalCoord);

    m_dragSequenceActive = false;

    if (!finalCoord.isValid()) {
        refreshUiState();
        return;
    }

    // Si realmente cambió, guardar SOLO la posición final
    if (moved) {
        pushHistory(finalCoord);
        return;
    }

    // Si no cambió, solo refrescar
    updateFieldsFromCoordinate(finalCoord);
    m_hasPendingChanges = !sameCoord(finalCoord, m_lastAppliedCoord);
    refreshUiState();
}
