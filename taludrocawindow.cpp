#include "taludrocawindow.h"
#include "ui_TaludRocaWindow.h"

#include <QFileInfo>
#include <QMessageBox>

TaludRocaWindow::TaludRocaWindow(QWidget *parent)
    : TaludFormBase(parent)
    , ui(new Ui::TaludRocaWindow)
{
    ui->setupUi(this);

    setObjectName("TaludRocaWindow");
    setBaseWindowTitle(tr("Ficha de Talud - Roca"));
    updateWindowTitleWithDirtyMark();
}

TaludRocaWindow::~TaludRocaWindow()
{
    delete ui;
}

TaludFormBase::TaludType TaludRocaWindow::taludType() const
{
    return TaludType::Roca;
}

QString TaludRocaWindow::displayName() const
{
    if (!currentFilePath().trimmed().isEmpty())
        return QFileInfo(currentFilePath()).completeBaseName();

    return tr("Talud Roca");
}

bool TaludRocaWindow::cargarDesdeArchivo(const QString& filePath)
{
    if (filePath.trimmed().isEmpty())
        return false;

    // Temporal: solo registra ruta y estado limpio.
    setCurrentFilePathInternal(filePath);
    setDirtyInternal(false);
    notifyDisplayNameChanged();
    updateWindowTitleWithDirtyMark();

    return true;
}

bool TaludRocaWindow::guardar()
{
    // Temporal: aún sin lógica real de serialización.
    if (currentFilePath().trimmed().isEmpty())
        return guardarComo();

    setDirtyInternal(false);
    updateWindowTitleWithDirtyMark();
    return true;
}

bool TaludRocaWindow::guardarComo()
{
    QMessageBox::information(this,
                             tr("Guardar como"),
                             tr("Talud Roca: guardado aún no implementado."));
    return false;
}
