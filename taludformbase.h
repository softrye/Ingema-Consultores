#pragma once

#include <QMainWindow>
#include <QString>

class QTimer;

class TaludFormBase : public QMainWindow
{
    Q_OBJECT
public:
    enum class TaludType {
        Suelo,
        Roca
    };

    explicit TaludFormBase(QWidget *parent = nullptr);
    ~TaludFormBase() override;

    // ------------------------------------------------------------
    // Contrato común para cualquier ficha de talud
    // ------------------------------------------------------------
    virtual TaludType taludType() const = 0;

    virtual QString displayName() const = 0;
    virtual bool cargarDesdeArchivo(const QString& filePath) = 0;
    virtual bool guardar() = 0;
    virtual bool guardarComo() = 0;

    // ------------------------------------------------------------
    // Estado común
    // ------------------------------------------------------------
    QString currentFilePath() const;
    bool isDirty() const;

    bool autoSaveEnabled() const;
    int autoSaveIntervalMs() const;

    void setAutoSaveEnabled(bool enabled);
    void setAutoSaveIntervalMs(int ms);

signals:
    void displayNameChanged();
    void dirtyChanged(bool dirty);
    void currentFilePathChanged(const QString& filePath);
    void autoSaveEnabledChanged(bool enabled);

protected:
    // ------------------------------------------------------------
    // Helpers para clases hijas
    // ------------------------------------------------------------
    void setCurrentFilePathInternal(const QString& filePath);
    void clearCurrentFilePathInternal();

    void setDirtyInternal(bool dirty);
    void markDirty();

    void setBaseWindowTitle(const QString& title);
    QString baseWindowTitle() const;

    void notifyDisplayNameChanged();
    void updateWindowTitleWithDirtyMark();

    // Auto-save por defecto: si está habilitado, hay dirty y existe ruta,
    // llama a guardar(). La hija puede override si necesita algo especial.
    virtual void onAutoSaveTimeout();

private:
    QString m_currentFilePath;
    bool m_dirty = false;

    bool m_autoSaveEnabled = false;
    int m_autoSaveIntervalMs = 20000;

    QString m_baseWindowTitle;
    QTimer* m_autoSaveTimer = nullptr;
};
