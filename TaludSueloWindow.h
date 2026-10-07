#pragma once

#include "taludformbase.h"
#include <QImage>

QT_BEGIN_NAMESPACE
namespace Ui { class TaludSueloWindow; }
QT_END_NAMESPACE

class QCheckBox;
class QLineEdit;
class QDoubleSpinBox;
class QLabel;
class QObject;
class QEvent;
class QResizeEvent;

class TaludSueloWindow : public TaludFormBase
{
    Q_OBJECT

public:
    explicit TaludSueloWindow(QWidget *parent = nullptr);
    ~TaludSueloWindow() override;

    TaludType taludType() const override;
    QString displayName() const override;
    bool cargarDesdeArchivo(const QString& filePath) override;
    bool guardar() override;
    bool guardarComo() override;

protected:
    bool eventFilter(QObject* watched, QEvent* event) override;
    void resizeEvent(QResizeEvent* event) override;

private:
    void setupCheckboxRules();
    void setupExclusiveNullablePair(QCheckBox* a, QCheckBox* b);
    void setupExclusiveNullableGroup(const QList<QCheckBox*>& boxes);

    void setupInputRules();
    void setupIntegerField(QLineEdit* edit, int min, int max);
    void setupRegexField(QLineEdit* edit, const QString& pattern);
    void setupMeasureSpin(QDoubleSpinBox* spin,
                          double min,
                          double max,
                          const QString& suffix,
                          int decimals = 2);

    // ===== módulo de dibujo / preview =====
    void setupPaintPreview();
    void openPaintDialog();
    void updatePaintPreview();
    bool saveProfilePreviewToFile();

private:
    Ui::TaludSueloWindow *ui = nullptr;

    QLabel* m_profilePreview = nullptr;
    QImage  m_profileImage;
    QString m_profileImagePath;
};