#include "selectfolderdialog.h"
#include "pathscope.h"


#include <QFileSystemModel>
#include <QTreeView>
#include <QPushButton>
#include <QHBoxLayout>
#include <QVBoxLayout>
#include <QLabel>
#include <QDir>
#include <QFileInfo>
#include <QMessageBox>
#include <QInputDialog>

SelectFolderDialog::SelectFolderDialog(const QString& rootDir,
                                       const QString& initialDir,
                                       QWidget* parent)
    : QDialog(parent)
{
    setWindowTitle(tr("Elegir carpeta de salida"));
    setModal(true);
    resize(760, 480);

    // 1) Normaliza root recibido
    m_rootDir = QDir::cleanPath(QDir::fromNativeSeparators(rootDir));

    // 2) ✅ Aplica scoping SOLO si hay sesión
    m_rootDir = ensureUserScopedRoot(m_rootDir);

    // 3) Asegura existencia (si el root no existe, el modelo puede verse vacío)
    QDir().mkpath(m_rootDir);

    // 4) Modelo
    m_model = new QFileSystemModel(this);
    m_model->setFilter(QDir::AllDirs | QDir::NoDotAndDotDot);
    m_model->setRootPath(m_rootDir);

    // 5) Vista
    m_tree = new QTreeView(this);
    m_tree->setModel(m_model);
    m_tree->setRootIndex(m_model->index(m_rootDir));
    m_tree->setHeaderHidden(true);
    m_tree->setColumnHidden(1, true);
    m_tree->setColumnHidden(2, true);
    m_tree->setColumnHidden(3, true);

    // 6) Selección inicial (si no es válida -> root)
    QString init = QDir::cleanPath(QDir::fromNativeSeparators(initialDir));
    if (init.isEmpty() || !QFileInfo::exists(init) || !isUnderRoot(init))
        init = m_rootDir;

    QModelIndex idxInit = m_model->index(init);
    if (idxInit.isValid()) {
        m_tree->expand(idxInit);
        m_tree->setCurrentIndex(idxInit);
        m_tree->scrollTo(idxInit);
    }

    auto *lbl = new QLabel(tr("Selecciona la carpeta destino:"), this);

    auto *btnNewFolder = new QPushButton(tr("Crear carpeta"), this);
    auto *btnOk = new QPushButton(tr("Seleccionar"), this);
    auto *btnCancel = new QPushButton(tr("Cancelar"), this);

    connect(btnNewFolder, &QPushButton::clicked, this, &SelectFolderDialog::onNewFolderClicked);
    connect(btnOk, &QPushButton::clicked, this, &SelectFolderDialog::onOkClicked);
    connect(btnCancel, &QPushButton::clicked, this, &QDialog::reject);

    auto *btnRow = new QHBoxLayout();
    btnRow->addWidget(btnNewFolder);
    btnRow->addStretch();
    btnRow->addWidget(btnOk);
    btnRow->addWidget(btnCancel);

    auto *mainLay = new QVBoxLayout(this);
    mainLay->addWidget(lbl);
    mainLay->addWidget(m_tree, 1);
    mainLay->addLayout(btnRow);
}


QString SelectFolderDialog::currentSelectedDir() const
{
    QModelIndex idx = m_tree->currentIndex();
    if (!idx.isValid())
        return m_rootDir;

    QString path = QDir::cleanPath(QDir::fromNativeSeparators(m_model->filePath(idx)));
    if (path.isEmpty())
        return m_rootDir;

    return path;
}

bool SelectFolderDialog::isUnderRoot(const QString& absPath) const
{
    QString p = QDir::cleanPath(QDir::fromNativeSeparators(absPath));
    QString r = QDir::cleanPath(QDir::fromNativeSeparators(m_rootDir));
    if (!r.endsWith('/')) r += '/';

#ifdef Q_OS_WIN
    return p.toLower().startsWith(r.toLower());
#else
    return p.startsWith(r);
#endif
}

void SelectFolderDialog::onOkClicked()
{
    const QString dirPath = currentSelectedDir();

    if (!isUnderRoot(dirPath)) {
        QMessageBox::warning(this, tr("Carpeta inválida"),
                             tr("La carpeta seleccionada debe estar dentro de:\n%1").arg(m_rootDir));
        return;
    }

    QDir().mkpath(dirPath);
    m_selectedDir = dirPath;
    accept();
}

void SelectFolderDialog::onNewFolderClicked()
{
    const QString baseDir = currentSelectedDir();
    if (!isUnderRoot(baseDir))
        return;

    bool ok = false;
    const QString name = QInputDialog::getText(this, tr("Crear carpeta"),
                                               tr("Nombre de la carpeta:"), QLineEdit::Normal,
                                               QString(), &ok).trimmed();
    if (!ok || name.isEmpty())
        return;

    QDir d(baseDir);
    if (!d.mkdir(name)) {
        QMessageBox::warning(this, tr("No se pudo crear"),
                             tr("No se pudo crear la carpeta:\n%1").arg(d.filePath(name)));
        return;
    }

    // refrescar y seleccionar
    const QString created = QDir::cleanPath(d.filePath(name));
    QModelIndex idx = m_model->index(created);
    if (idx.isValid()) {
        m_tree->expand(m_model->index(baseDir));
        m_tree->setCurrentIndex(idx);
        m_tree->scrollTo(idx);
    }
}
