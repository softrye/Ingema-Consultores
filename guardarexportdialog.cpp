#include "guardarexportdialog.h"

#include <QFileSystemModel>
#include <QTreeView>
#include <QLineEdit>
#include <QPushButton>
#include <QHBoxLayout>
#include <QVBoxLayout>
#include <QLabel>
#include <QDir>
#include <QFileInfo>
#include <QMessageBox>

GuardarExportDialog::GuardarExportDialog(const QString& rootDir,
                                         const QString& initialDir,
                                         const QString& defaultFileName,
                                         const QString& extension,
                                         QWidget* parent)
    : QDialog(parent),
    m_rootDir(rootDir),
    m_extension(extension)
{
    setWindowTitle("Guardar exportación");
    setModal(true);
    resize(760, 480);

    m_model = new QFileSystemModel(this);
    m_model->setFilter(QDir::AllDirs | QDir::NoDotAndDotDot);
    m_model->setRootPath(rootDir);

    m_tree = new QTreeView(this);
    m_tree->setModel(m_model);
    m_tree->setRootIndex(m_model->index(rootDir));
    m_tree->setHeaderHidden(true);
    m_tree->setColumnHidden(1, true);
    m_tree->setColumnHidden(2, true);
    m_tree->setColumnHidden(3, true);

    // Selección inicial
    QModelIndex idxInit = m_model->index(initialDir);
    if (idxInit.isValid()) {
        m_tree->expand(idxInit);
        m_tree->setCurrentIndex(idxInit);
        m_tree->scrollTo(idxInit);
    }

    auto *lbl = new QLabel("Selecciona la carpeta destino y escribe el nombre de archivo:", this);

    m_file = new QLineEdit(this);
    m_file->setText(defaultFileName);

    auto *btnOk = new QPushButton("OK", this);
    auto *btnCancel = new QPushButton("Cancel", this);

    connect(btnOk, &QPushButton::clicked, this, &GuardarExportDialog::onOkClicked);
    connect(btnCancel, &QPushButton::clicked, this, &QDialog::reject);

    auto *btnRow = new QHBoxLayout();
    btnRow->addStretch();
    btnRow->addWidget(btnOk);
    btnRow->addWidget(btnCancel);

    auto *mainLay = new QVBoxLayout(this);
    mainLay->addWidget(lbl);
    mainLay->addWidget(m_tree, 1);
    mainLay->addWidget(new QLabel("Nombre de archivo:", this));
    mainLay->addWidget(m_file);
    mainLay->addLayout(btnRow);
}

QString GuardarExportDialog::currentSelectedDir() const
{
    QModelIndex idx = m_tree->currentIndex();
    if (!idx.isValid())
        return m_rootDir;

    QString path = m_model->filePath(idx);
    if (path.isEmpty())
        return m_rootDir;

    return path;
}

void GuardarExportDialog::onOkClicked()
{
    QString dirPath = currentSelectedDir();
    QString name = m_file->text().trimmed();

    if (name.isEmpty()) {
        QMessageBox::warning(this, "Guardar", "Escribe un nombre de archivo.");
        return;
    }

    if (!m_extension.isEmpty() && !name.endsWith(m_extension, Qt::CaseInsensitive))
        name += m_extension;

    QDir().mkpath(dirPath);

    m_selectedPath = QDir(dirPath).filePath(name);
    accept();
}
