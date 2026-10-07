// perfilwindow.h
#ifndef PERFILWINDOW_H
#define PERFILWINDOW_H

#include <QMainWindow>
#include <QResizeEvent>
#include <QEvent>
#include <QString>
#include <QPixmap>
#include <QPointer>

QT_BEGIN_NAMESPACE
namespace Ui { class PerfilWindow; }
QT_END_NAMESPACE

class QWidget;
class QLabel;
class QPushButton;
class QPropertyAnimation;
class ToggleSwitch;
class HomeWindow;
class AppContext;
class QGraphicsOpacityEffect;
class QParallelAnimationGroup;

class PerfilWindow : public QMainWindow
{
    Q_OBJECT

public:
    void setHome(HomeWindow *h) { m_home = h; }
    explicit PerfilWindow(AppContext* ctx, QWidget* parent = nullptr);
    explicit PerfilWindow(QWidget* parent = nullptr); // delega al de arriba
    ~PerfilWindow() override;

protected:
    void resizeEvent(QResizeEvent *event) override;
    bool eventFilter(QObject *obj, QEvent *event) override;
    void closeEvent(QCloseEvent *e) override;

private:
    // ----- Panel Opciones -----
    void setupOptionsPanel();
    void repositionOptionsPanel();
    void updateOptionsPanelBasePath();

    void toggleOptionsPanel();
    void openOptionsPanel();
    void closeOptionsPanel();

    // ----- Settings / paths -----
    QString defaultBasePath() const;
    QString loadProjectsRootFromSettings() const;
    void saveProjectsRootToSettings(const QString &path) const;

    bool directoryLooksEmpty(const QString &path, bool ignoreResourcesFolder) const;
    bool copyDirRecursively(const QString &srcPath, const QString &dstPath);
    bool setProjectsRoot(const QString &newBasePath, bool moveExistingData, QString *outError);

    // ----- Acciones -----
    void actionChangeProjectsFolder();
    void actionOpenProjectsFolder();
    void actionRestoreDefaultProjectsFolder();

    void actionAbout();
    void actionExportLog();

    void loadProfileFromSettings();
    void saveProfileToSettings();
    void chooseAvatar();
    void setAvatarPath(const QString &absPath);

    QString avatarStorageDir() const;
    QString importAvatarToStorage(const QString &srcPath) const;


    QString defaultAvatarResource() const;

    void refreshAvatarPreview();   // re-escala al tamaño actual del QLabel

    QPixmap m_avatarOriginal;      // cache para reescalar en resize


    // cache (opcional pero útil)
    QString m_profileName;
    QString m_profileEmail;
    QString m_profilePhone;
    QString m_profileAvatarPath;

    // Avatar (QRC + archivo)
    QString defaultAvatarResourcePath() const;
    void resetAvatarToDefault();

    void clearProfileUiForOffline(bool clearSettings);
    void goTo(QMainWindow* w);

private:
    Ui::PerfilWindow *ui = nullptr;

    // Ventana / data
    QString m_basePath;

    // ✅ Overlay gris (dimming) + FADE
    QWidget *m_dimOverlay = nullptr;
    QGraphicsOpacityEffect *m_dimFx = nullptr;
    QPropertyAnimation *m_dimAnim = nullptr;

    // Panel opciones
    QWidget *m_optionsPanel = nullptr;
    QPropertyAnimation *m_optionsAnim = nullptr;

    // ✅ Grupo para animar slide + fade sincronizados
    QParallelAnimationGroup *m_optionsGroup = nullptr;

    bool m_optionsOpen = false;
    int m_optionsWidth = 360;

    // Widgets dentro del panel
    ToggleSwitch *m_swShareGps = nullptr;

    QLabel *m_lblBasePath = nullptr;
    QPushButton *m_btnChangeFolder = nullptr;
    QPushButton *m_btnOpenFolder = nullptr;
    QPushButton *m_btnDefaultFolder = nullptr;

    QPushButton *m_btnAbout = nullptr;
    QPushButton *m_btnExportLog = nullptr;
    QPushButton *m_btnClosePanel = nullptr;
    QPointer<HomeWindow> m_home;
    AppContext* m_ctx = nullptr;

    QPushButton* m_btnLogoutOpt = nullptr;

    QPushButton* m_btnOpenSessionOpt = nullptr;

private slots:
    void refreshFromAuth();
    void onLogoutClicked();
    void onLogoutFromOptions();
    void onOpenSessionClicked();
};

#endif // PERFILWINDOW_H
