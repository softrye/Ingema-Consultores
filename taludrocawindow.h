#pragma once

#include "taludformbase.h"

QT_BEGIN_NAMESPACE
namespace Ui { class TaludRocaWindow; }
QT_END_NAMESPACE

class TaludRocaWindow : public TaludFormBase
{
    Q_OBJECT

public:
    explicit TaludRocaWindow(QWidget *parent = nullptr);
    ~TaludRocaWindow() override;

    TaludType taludType() const override;
    QString displayName() const override;
    bool cargarDesdeArchivo(const QString& filePath) override;
    bool guardar() override;
    bool guardarComo() override;

private:
    Ui::TaludRocaWindow *ui = nullptr;
};
