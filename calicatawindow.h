// calicatawindow.h
#ifndef CALICATAWINDOW_H
#define CALICATAWINDOW_H

#include <QMainWindow>
#include <QDateTime>
#include <QElapsedTimer>
#include <QGeoCoordinate>
#include <QIcon>
#include <QPixmap>
#include <QPoint>
#include <QVector>
#include <QProgressDialog>
#include <QFutureWatcher>
#include <QtConcurrent/QtConcurrent>
#include <QHash>
#include <QFileSystemWatcher>


class QVBoxLayout;
class QJsonObject;
class QMimeData;
class QTimer;
class CorteRowWidget;
class QPushButton;

QT_BEGIN_NAMESPACE
namespace Ui { class CalicataWindow; }
QT_END_NAMESPACE

class CalicataWindow : public QMainWindow
{
    Q_OBJECT

public:
    explicit CalicataWindow(QWidget *parent = nullptr);
    ~CalicataWindow() override;

    // Cargar ficha desde archivo .calicata.json
    bool cargarDesdeArchivo(const QString &filePath);

    // Para el Editor (tabs)
    QString currentFilePath() const { return m_currentFilePath; }
    bool isDirty() const { return m_dirty; }

    // Para título de pestaña (usa txtProgresiva)
    QString displayName() const;

    QString tituloTestificacion() const { return m_tituloTestificacion; }
    void setTituloTestificacion(const QString& t, bool markDirty = true);
    void applyExternalEditableTitle(const QString& t);
    void applyExternalEditableLogos(const QString& mtcRelPath,
                                    const QString& proyectoRelPath);

    void openCalicataFile(const QString& path);
    void closeTabByAbs(const QString& abs);
    QString utmZona() const;
    QString utmX() const;
    QString utmY() const;

    void applyExternalUtm(const QString& zona,
                          const QString& x,
                          const QString& y,
                          const QString& altitud = QString(),
                          bool markDirty = true);

    bool canUndo() const;
    bool canRedo() const;

public slots:
    void guardar();
    void guardarComo();
    void setAutoSaveEnabled(bool enabled);

    void undoForm();
    void redoForm();


signals:
    void displayNameChanged(const QString &name);
    void dirtyChanged(bool dirty);
    void undoAvailabilityChanged(bool enabled);
    void redoAvailabilityChanged(bool enabled);


protected:
    void closeEvent(QCloseEvent *event) override;
    void resizeEvent(QResizeEvent *event) override;

    // Drag & Drop (reordenar cortes)
    bool eventFilter(QObject *watched, QEvent *event) override;

private slots:
    // --- Botones de LOGO ---
    void on_btnLogoMTC_clicked();
    void on_btnLogoProyecto_clicked();

    // --- Botones de FOTOS (botón grande) ---
    void on_btnFoto1_clicked();
    void on_btnFoto2_clicked();
    void on_btnFoto3_clicked();

    // --- ToolPick (selector interno SOLO cache, sin estampar) ---
    void onToolPickFoto1();
    void onToolPickFoto2();
    void onToolPickFoto3();

    // --- Botón ACTUALIZAR COORDENADAS ---
    void on_btnActualizarCoordenadas_clicked();

    // --- GPS (opcional) ---
    void onGpsPositionUpdated(const QGeoCoordinate &coord,
                              double altitude,
                              const QDateTime &time);

    // --- Acciones de archivo ---
    void guardarInterno();
    void guardarComoInterno();

    void on_btnTituloCalicata_clicked();

private:
    // ============================
    // Data
    // ============================
    struct TimestampData {
        QString zona;
        QString este;
        QString norte;
        QString altitud;
        QString calicata;
        QString proyecto;
        QString fecha;
        QString hora;
    };

    // ============================
    // Imágenes (UI)
    // ============================
    void initImageButtons();
    void refreshAllButtonPixmaps();
    void setButtonPixmap(QPushButton *btn, const QPixmap &pix, bool markDirty);

    void setDefaultLogoPlaceholder(QPushButton *btn, const QIcon &ico, const QString &fallbackText);

    void cargarImagenEnBoton(QPushButton *boton,
                             const QString &tituloDialogo,
                             bool estamparDatosEnFoto);
    QPixmap generarFotoConDatos(const QPixmap &original,
                                const TimestampData &data) const;
    bool editarTimestamp(TimestampData &ioData);

    void clearFoto(int idx);
    void clearLogoMtc();
    void clearLogoProyecto();

    QString pickStartDir(bool forPhotos) const;
    bool isPathInsideEditableFotos(const QString& absPath, const QString& contextFilePath) const;

    // ============================
    // NUEVO: ToolPick interno (solo cache)
    // ============================
    QString cachedPhotosTypeFolderAbs(int idx, const QString &contextFilePath) const;
    bool pickCachedPhotoForIdx(int idx);              // abre selector interno y setea fotoX
    QString fotoRelPathForIdx(int idx) const;
    void setFotoRelPathForIdx(int idx, const QString &rel);

    // ============================
    // NUEVO: ToolPick interno para LOGOS (bloqueado a Recursos/)
    // ============================
    bool pickLogoFromResources(bool mtc);
    QString projectRootForPath(const QString &fileOrDirPath) const;
    QString resourcesRootForContext(const QString &contextFilePath) const;
    QString resolveResourceAbsPath(const QString &maybeRelPath, const QString &contextFilePath) const;

    // ============================
    // Proyecto / meta
    // ============================
    QString baseProjectsPath() const;

    QString findProjectMetaFileUp(const QString &startDir) const;
    QString readProyectoFromMetaFile(const QString &metaFilePath) const;
    QString projectNameForPath(const QString &fileOrDirPath) const;
    void ensureProyectoFromContext(const QString &preferredPath = QString());

    // ============================
    // Editable folder (cache JPG)
    // ============================
    QString findEditableMetaFileUp(const QString &startDir) const;
    QString editableRootForPath(const QString &fileOrDirPath) const;
    QString resolveImageAbsPath(const QString &maybeRelPath, const QString &contextFilePath) const;

    QString calicataStemForFile(const QString &savingFilePath) const;
    bool ensurePhotosDir(const QString &editableRoot) const;
    bool savePixmapAsJpg(const QPixmap &pix, const QString &absJpgPath, int quality = 90) const;

    bool persistImagesToCacheJpg(const QString &savingFilePath, QJsonObject &imgs) const;

    // Nombres de tus fotos:
    // 1 -> Foto_ZE_Calicata
    // 2 -> Foto_Calicata_Interior
    // 3 -> Foto_Acopios
    QString fotoPrefixForIdx(int idx) const;
    QString nextFotoPathForIdx(int idx) const;

    // Antes de escribir _001, mueve el actual _001 a _002/_003...
    bool backupIfExists(const QString& destPath) const;

    // ============================
    // JSON / Guardado completo
    // ============================
    bool guardarEnArchivo(const QString &filePath, bool interactive = true);
    void updateWindowTitle();
    void setDirtyInternal(bool dirty);

    bool guardarSiEsNecesario();
    void marcarComoModificado();

    void aplicarJsonEnUi(const QJsonObject &obj);
    void actualizarTimestampDesdeUi();

    QJsonObject buildFullJson(const QString &savingFilePath) const;
    void applyFullJson(const QJsonObject &obj, const QString &contextFilePath);

    // Base64 PNG helpers (logos custom + legacy)
    static QString pixmapToBase64Png(const QPixmap &pix);
    static QPixmap base64PngToPixmap(const QString &b64);

    // ============================
    // Cortes
    // ============================
    void attachDirtySignals(QWidget *root);

    QVector<CorteRowWidget*> cortes() const;
    void clearCortesRows();

    void setupIntervalRules(CorteRowWidget *row);
    void setupDeleteRules(CorteRowWidget *row);
    void eliminarCorte(CorteRowWidget *row);
    void renumerarCortesYIntervalos(bool markDirty);

    double parseDepth(const QString &s, bool *ok) const;
    QString fmtDepth(double v) const;

    // ============================
    // Drag & Drop cortes + AutoScroll
    // ============================
    void setupCortesDragDrop();
    CorteRowWidget* decodeDraggedRow(const QMimeData *mime) const;
    int insertIndexForDropY(int yInContainer, CorteRowWidget *dragging) const;
    void moveRowToIndex(CorteRowWidget *row, int insertAt);
    QPoint toCortesContainerPos(QObject *watched, const QPoint &pos) const;

    QPoint toScrollViewportPos(QObject *watched, const QPoint &pos) const;
    void updateAutoScrollFromViewportPos(const QPoint &posInViewport);
    void stopAutoScroll();

    // ============================
    // GPS helper
    // ============================
    void aplicarUbicacion(const QGeoCoordinate &coord,
                          double altitude,
                          const QDateTime &time);

    QString m_tituloTestificacion;
    bool m_exportingSingle = false;

    QHash<QString, int> m_tabByAbs;      // absPath -> tabIndex
    QFileSystemWatcher  m_watcher;

    void onWatchedPathChanged(const QString& path);

    QString canonicalAbs(const QString& path) const;


private:
    Ui::CalicataWindow *ui = nullptr;
    QVBoxLayout *m_layoutCortes = nullptr;

    bool m_missingOnDisk = false;

    QString m_currentFilePath;
    bool m_dirty = false;
    bool m_loading = false;
    bool m_updatingIntervals = false;

    // Botones imágenes (anti doble conexión + carpeta inicial)
    bool m_imageButtonsHooked = false;
    QIcon m_defaultLogoMtcIcon;
    QIcon m_defaultLogoProyectoIcon;

    // NUEVO: fallback text (evita botones blancos si icono falla)
    QString m_defaultLogoMtcText;
    QString m_defaultLogoProyectoText;

    QString m_lastImagePickDir;
    QElapsedTimer m_pickDebounce;

    // Timestamp
    TimestampData m_timestamp;

    // Pixmaps
    QPixmap m_logoMtcPix;
    QPixmap m_logoProyectoPix;
    QPixmap m_foto1Pix;
    QPixmap m_foto2Pix;
    QPixmap m_foto3Pix;

    // NUEVO: si el usuario eligió una foto del cache con ToolPick,
    // guardamos el path RELATIVO (editableRoot-relative) para NO re-guardar.
    QString m_foto1RelPath;
    QString m_foto2RelPath;
    QString m_foto3RelPath;

    // NUEVO: logos por ruta relativa (projectRoot-relative)
    QString m_logoMtcRelPath;
    QString m_logoProyectoRelPath;

    bool m_logoMtcIsCustom = false;
    bool m_logoProyectoIsCustom = false;

    // Auto-scroll durante drag
    QTimer *m_dragAutoScrollTimer = nullptr;
    int m_dragAutoScrollDir = 0;
    int m_dragAutoScrollSpeed = 0;
    QPoint m_lastDragPosInViewport;
    QString m_tituloCalicata;

    QString loadExcelTitleFromEditableMeta(const QString &contextPath) const;
    bool saveExcelTitleToEditableMeta(const QString &contextPath, const QString &title) const;
    QString m_baseWindowTitle;
    QTimer *m_autoSaveTimer = nullptr;
    bool m_autoSaveEnabled = false;
    int  m_autoSaveIntervalMs = 20000; // 20s
    bool m_noEditableWarnShown = false;

    QString saveGeneratedPhotoToEditableCache(QPushButton* boton,
                                              const QPixmap& pix,
                                              const QString& ctxFilePath);

    bool persistSinglePhotoToEditableJpg(int idx,
                                         const QPixmap &pix,
                                         const QString &contextFilePath,
                                         QString *outRelPath) const;

    void exportSingleJsonToExcelWithBusy(const QString& jsonPath,
                                         const QString& outXlsx);


    struct HistoryEntry {
        QByteArray json;   // snapshot completo en JSON compact
        bool dirty = false;
    };

    QVector<HistoryEntry> m_history;
    int m_historyIndex = -1;
    QTimer *m_historyTimer = nullptr;
    bool m_historyApplying = false;

    QString historyContextPath() const;
    QByteArray makeHistorySnapshot() const;
    void scheduleHistorySnapshot();
    void captureHistorySnapshot();
    void resetHistoryFromCurrentState();
    void restoreHistoryIndex(int index);
    void emitUndoRedoAvailability();


};

#endif // CALICATAWINDOW_H
