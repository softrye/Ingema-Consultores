#pragma once

#include <QDialog>
#include <QGeoCoordinate>
#include <QVector>

class QQuickWidget;
class QLineEdit;
class QTimeEdit;
class QToolButton;
class QPushButton;
class QCloseEvent;
class MapController;

class CalicataMapDialog : public QDialog
{
    Q_OBJECT

public:
    explicit CalicataMapDialog(QWidget *parent = nullptr);

    void setInitialCoordinate(const QGeoCoordinate& coord);
    void setInitialFromUtm(const QString& zoneText,
                           const QString& xText,
                           const QString& yText);

signals:
    void manualUtmChosen(const QString& zona,
                         const QString& x,
                         const QString& y,
                         const QString& altitud,
                         const QGeoCoordinate& coord);

protected:
    void closeEvent(QCloseEvent *event) override;

private slots:
    void onCoordinatePicked(const QGeoCoordinate& coord);
    void onUndo();
    void onRedo();
    void onApplyClicked();
    void onAcceptClicked();
    void onManualDragStarted(const QGeoCoordinate& coord);
    void onManualDragFinished(const QGeoCoordinate& coord);

private:
    enum class PendingPromptMode {
        ApplyOnly,
        CloseDialog
    };

    void updateFieldsFromCoordinate(const QGeoCoordinate& coord);
    void resetHistory(const QGeoCoordinate& coord);
    void pushHistory(const QGeoCoordinate& coord);
    void loadHistoryIndex(int index);
    void refreshUiState();
    void applyCurrentToExternal();
    bool askPendingChanges(PendingPromptMode mode, bool* outShouldClose = nullptr);
    bool sameCoord(const QGeoCoordinate& a, const QGeoCoordinate& b) const;

    QGeoCoordinate currentCoord() const;

    QQuickWidget* m_mapQuick = nullptr;
    MapController* m_mapController = nullptr;

    QLineEdit* m_txtZona = nullptr;
    QLineEdit* m_txtX = nullptr;
    QLineEdit* m_txtY = nullptr;
    QLineEdit* m_txtAlt = nullptr;
    QTimeEdit* m_timeHora = nullptr;

    QToolButton* m_btnUndo = nullptr;
    QToolButton* m_btnRedo = nullptr;
    QPushButton* m_btnApply = nullptr;
    QPushButton* m_btnAccept = nullptr;
    QPushButton* m_btnClose = nullptr;

    QVector<QGeoCoordinate> m_history;
    int m_historyIndex = -1;

    QGeoCoordinate m_lastAppliedCoord;
    bool m_hasPendingChanges = false;
    bool m_allowImmediateClose = false;
    bool m_dragSequenceActive = false;
    QGeoCoordinate m_dragStartCoord;
};
