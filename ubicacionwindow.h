#ifndef UBICACIONWINDOW_H
#define UBICACIONWINDOW_H

#include <QMainWindow>
#include <QEvent>
#include <QTimer>
#include <QShowEvent>
#include <QResizeEvent>
#include <QGeoCoordinate>
#include <QDateTime>
#include <QQuickWidget>
#include <QQmlContext>
#include "MapController.h"
#include <QQuickWidget>
#include <QMovie>
#include <QPixmap>
#pragma once

#include "gpsmanager.h"

QT_BEGIN_NAMESPACE
namespace Ui { class UbicacionWindow; }
QT_END_NAMESPACE

// Datos globales de ubicación
struct UbicacionData {
    QString sistemaCoord;
    QString zona;
    QString x;
    QString y;
    QString altitud;
    QString hora;
};

extern UbicacionData g_ubicacionData;

class QWidget;
class QLabel;
class ToggleSwitch;
class QPushButton;
class QPropertyAnimation;
class QAbstractButton;
class QGraphicsOpacityEffect;
class QParallelAnimationGroup;
class QHideEvent;
class MapController;
class HomeWindow;
class AppContext;      // ✅ forward declare (opcional, pero útil)
class AuthSession;

class UbicacionWindow : public QMainWindow
{
    Q_OBJECT

public:
    explicit UbicacionWindow(QWidget *parent = nullptr);
    ~UbicacionWindow() override;
    void setHome(HomeWindow* h);

protected:
    bool eventFilter(QObject *obj, QEvent *event) override;
    void showEvent(QShowEvent *event) override;
    void resizeEvent(QResizeEvent *event) override;
    void hideEvent(QHideEvent *event) override;
    void closeEvent(QCloseEvent *e) override;


private slots:
    void updateGreeting();
    void on_chkGpsActivo_toggled(bool checked);
    void onGpsPositionUpdated(const QGeoCoordinate &coord,
                              double altitude,
                              const QDateTime &time);

    void actualizarHoraLocal();
    void syncUiToGlobal();

    // Panel opciones
    void toggleOptionsPanel();
    void openOptionsPanel();
    void closeOptionsPanel();

    // Acciones del panel
    void actionChangeProjectsFolder();
    void actionOpenProjectsFolder();
    void actionRestoreDefaultLocation();
    void actionOpenProfileFromMenu();
    void actionAbout();
    void actionExportLog();

private:
    Ui::UbicacionWindow *ui = nullptr;
    QTimer m_timerHora;

    void syncUiFromGlobal();

    // ---- GPS helpers ----
    void setGpsActiveInternal(bool on, QObject *origin);
    void syncGpsUiFromManager();

    // ---- Panel opciones ----
    void setupOptionsPanel();
    void repositionOptionsPanel();

    QString defaultProjectsPath() const;
    QString projectsBasePath() const;
    void setProjectsBasePath(const QString &path);
    void refreshProjectsPathLabel();

    QQuickWidget* m_mapQuick = nullptr;
    MapController* m_mapController = nullptr;
    void setupMapWidget();

    void setGpsFieldsReadOnly(bool ro);
    QPushButton* m_btnOpenSession = nullptr;
    QPushButton* m_btnLogout = nullptr;


private:
    // Botón menú (lo buscamos por objectName "btnMenu" sin romper compile si no existe en el .ui)
    // ---- Panel opciones ----
    QAbstractButton *m_btnMenu = nullptr;

    QWidget *m_optionsPanel = nullptr;
    QPropertyAnimation *m_optionsAnim = nullptr;
    bool m_optionsVisible = false;
    int  m_optionsWidth = 320;

    // ✅ NUEVO: overlay oscuro (dimming)
    QWidget *m_dimOverlay = nullptr;
    QGraphicsOpacityEffect *m_dimFx = nullptr;
    QPropertyAnimation *m_dimAnim = nullptr;
    QParallelAnimationGroup *m_optionsGroup = nullptr;

    QLabel *m_lblBasePath = nullptr;
    ToggleSwitch *m_swGpsMenu = nullptr;

    QPushButton *m_btnClosePanel = nullptr;

    void updateGpsIndicator(bool on);

    QMovie *m_gpsMovie = nullptr;
    QPixmap m_gpsInactive;
    HomeWindow* m_home = nullptr;
    void goTo(QMainWindow* w);

    void setupMapResizeGrip();
    void repositionMapResizeGrip();
    void applyMapHeight(int h);

    QWidget* m_mapResizeGrip = nullptr;
    bool m_mapResizeDragging = false;
    QPoint m_mapResizeStartGlobal;
    int m_mapResizeStartHeight = 0;

    const int m_mapMinHeight = 260;
    const int m_mapMaxHeight = 780;


public slots:
    void setGpsActive(bool on);        // <- esta firma DEBE existir
    void setGpsAutoShare(bool on);     // si la usas desde el editor
    bool isGpsActive() const;
    void onOpenSessionClicked();
    void applyExternalManualCoordinate(const QGeoCoordinate& coord);

signals:
    void gpsActiveChanged(bool on);
    void gpsAutoShareChanged(bool on);
};

#endif // UBICACIONWINDOW_H
