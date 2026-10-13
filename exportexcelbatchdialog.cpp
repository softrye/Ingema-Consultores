#include "exportexcelbatchdialog.h"
#include "selectfolderdialog.h"
#include "pathscope.h"
#include "ingetheme.h"


#include <QHBoxLayout>
#include <QVBoxLayout>
#include <QGroupBox>
#include <QSplitter>
#include <QHeaderView>
#include <QTableWidget>
#include <QTableWidgetItem>
#include <QAbstractItemView>
#include <QPushButton>
#include <QLineEdit>
#include <QRadioButton>
#include <QCheckBox>
#include <QLabel>
#include <QFileInfo>
#include <QDir>
#include <QMessageBox>
#include <QProgressDialog>
#include <QStandardPaths>
#include <QSet>

#include <algorithm>

// ✅ Reutiliza TU selector tipo árbol para archivos (multi selección)
#include "guardarcalicatadialog.h"

// ✅ Tu exportador actual
#include "calicataexcelexporter.h"

ExportExcelBatchDialog::ExportExcelBatchDialog(const QString& projectsRoot, QWidget *parent)
    : QDialog(parent)
    , m_projectsRoot(QDir::cleanPath(QDir::fromNativeSeparators(projectsRoot)))
{
    setWindowTitle(tr("Exportar Excel (masivo)"));
    setModal(true);
    resize(980, 560);

    auto *root = new QVBoxLayout(this);
    root->setContentsMargins(12,12,12,12);
    root->setSpacing(10);

    auto *split = new QSplitter(Qt::Horizontal, this);
    root->addWidget(split, 1);

    // ---------------- LEFT: lista ----------------
    auto *left = new QWidget(this);
    auto *leftLay = new QVBoxLayout(left);
    leftLay->setContentsMargins(0,0,0,0);
    leftLay->setSpacing(8);

    m_table = new QTableWidget(0, 3, this);
    m_table->setHorizontalHeaderLabels({tr("Archivo (.calicata.json)"), tr("Salida (.xlsx)"), tr("Estado")});
    m_table->horizontalHeader()->setStretchLastSection(false);
    m_table->horizontalHeader()->setSectionResizeMode(0, QHeaderView::Stretch);
    m_table->horizontalHeader()->setSectionResizeMode(1, QHeaderView::Stretch);
    m_table->horizontalHeader()->setSectionResizeMode(2, QHeaderView::ResizeToContents);
    m_table->setSelectionBehavior(QAbstractItemView::SelectRows);
    m_table->setSelectionMode(QAbstractItemView::ExtendedSelection);
    m_table->setEditTriggers(QAbstractItemView::NoEditTriggers);
    leftLay->addWidget(m_table, 1);


    auto *btnRow = new QHBoxLayout();
    m_btnAdd = new QPushButton(tr("Agregar..."), this);
    m_btnRemove = new QPushButton(tr("Quitar"), this);
    m_btnClear = new QPushButton(tr("Limpiar"), this);
    btnRow->addWidget(m_btnAdd);
    btnRow->addWidget(m_btnRemove);
    btnRow->addWidget(m_btnClear);
    btnRow->addStretch(1);
    leftLay->addLayout(btnRow);

    split->addWidget(left);

    // ---------------- RIGHT: opciones ----------------
    auto *right = new QWidget(this);
    auto *rightLay = new QVBoxLayout(right);
    rightLay->setContentsMargins(0,0,0,0);
    rightLay->setSpacing(10);

    // Destino
    auto *gbDest = new QGroupBox(tr("Destino"), this);
    auto *destLay = new QVBoxLayout(gbDest);

    m_rbSameFolder = new QRadioButton(tr("Mismo folder del JSON"), this);
    m_rbExcelSubfolder = new QRadioButton(tr("Carpeta \"EXCEL\" junto al JSON (crear si no existe)"), this);
    m_rbOneFolder = new QRadioButton(tr("Un solo folder para todos:"), this);

    m_rbExcelSubfolder->setChecked(true);

    destLay->addWidget(m_rbSameFolder);
    destLay->addWidget(m_rbExcelSubfolder);
    destLay->addWidget(m_rbOneFolder);

    auto *outRow = new QHBoxLayout();
    m_editOutDir = new QLineEdit(this);
    m_btnBrowse = new QPushButton(tr("Examinar..."), this);

    // 🔒 Para que sea “interno” de verdad: que NO puedan tipear rutas externas
    m_editOutDir->setReadOnly(true);

    m_editOutDir->setEnabled(false);
    m_btnBrowse->setEnabled(false);

    outRow->addWidget(m_editOutDir, 1);
    outRow->addWidget(m_btnBrowse);
    destLay->addLayout(outRow);

    rightLay->addWidget(gbDest);

    // Nombres
    auto *gbName = new QGroupBox(tr("Nombre de archivo"), this);
    auto *nameLay = new QVBoxLayout(gbName);

    auto *rowP = new QHBoxLayout();
    rowP->addWidget(new QLabel(tr("Prefijo:"), this));
    m_editPrefix = new QLineEdit(this);
    rowP->addWidget(m_editPrefix, 1);
    nameLay->addLayout(rowP);

    auto *rowS = new QHBoxLayout();
    rowS->addWidget(new QLabel(tr("Sufijo:"), this));
    m_editSuffix = new QLineEdit(this);
    rowS->addWidget(m_editSuffix, 1);
    nameLay->addLayout(rowS);

    rightLay->addWidget(gbName);

    // Opciones
    auto *gbOpt = new QGroupBox(tr("Opciones"), this);
    auto *optLay = new QVBoxLayout(gbOpt);
    m_chkOverwrite = new QCheckBox(tr("Sobrescribir si ya existe"), this);
    optLay->addWidget(m_chkOverwrite);
    rightLay->addWidget(gbOpt);

    rightLay->addStretch(1);

    split->addWidget(right);
    split->setStretchFactor(0, 3);
    split->setStretchFactor(1, 2);

    // Bottom buttons
    auto *bottom = new QHBoxLayout();
    bottom->addStretch(1);
    m_btnExport = new QPushButton(tr("Exportar"), this);
    m_btnCancel = new QPushButton(tr("Cancelar"), this);
    bottom->addWidget(m_btnExport);
    bottom->addWidget(m_btnCancel);
    root->addLayout(bottom);

    // Signals
    connect(m_btnAdd, &QPushButton::clicked, this, &ExportExcelBatchDialog::addFiles);
    connect(m_btnRemove, &QPushButton::clicked, this, &ExportExcelBatchDialog::removeSelected);
    connect(m_btnClear, &QPushButton::clicked, this, &ExportExcelBatchDialog::clearAll);

    // ✅ AHORA “Examinar…” usa selector interno
    connect(m_btnBrowse, &QPushButton::clicked, this, &ExportExcelBatchDialog::browseOutDir);

    connect(m_btnExport, &QPushButton::clicked, this, &ExportExcelBatchDialog::doExport);
    connect(m_btnCancel, &QPushButton::clicked, this, &QDialog::reject);

    auto onDestChanged = [this](){
        bool one = m_rbOneFolder->isChecked();
        m_editOutDir->setEnabled(one);
        m_btnBrowse->setEnabled(one);
        syncOutPathsColumn();
    };
    connect(m_rbSameFolder, &QRadioButton::toggled, this, onDestChanged);
    connect(m_rbExcelSubfolder, &QRadioButton::toggled, this, onDestChanged);
    connect(m_rbOneFolder, &QRadioButton::toggled, this, onDestChanged);

    connect(m_editPrefix, &QLineEdit::textChanged, this, &ExportExcelBatchDialog::syncOutPathsColumn);
    connect(m_editSuffix, &QLineEdit::textChanged, this, &ExportExcelBatchDialog::syncOutPathsColumn);
}

ExportExcelBatchDialog::DestMode ExportExcelBatchDialog::currentDestMode() const
{
    if (m_rbSameFolder->isChecked()) return DestMode::SameFolder;
    if (m_rbExcelSubfolder->isChecked()) return DestMode::ExcelSubfolder;
    return DestMode::OneFolder;
}

QString ExportExcelBatchDialog::calicatasRootDirForJson(const QString& jsonPath)
{
    QDir d = QFileInfo(jsonPath).absoluteDir(); // .../Calicatas/Edit
    if (d.dirName().compare("Edit", Qt::CaseInsensitive) == 0)
        d.cdUp(); // .../Calicatas
    return d.absolutePath();
}

QString ExportExcelBatchDialog::normalizedBaseName(const QString& jsonPath) const
{
    QFileInfo fi(jsonPath);
    QString bn = fi.completeBaseName(); // "CT-0+000.calicata" (porque la extensión final es .json)

    // Para que el excel quede como "CT-0+000.xlsx" (sin ".calicata")
    const QString suffix = ".calicata";
    if (bn.endsWith(suffix, Qt::CaseInsensitive))
        bn.chop(suffix.size());

    return bn;
}

QString ExportExcelBatchDialog::computeOutPath(const QString& jsonPath) const
{
    const QString base = normalizedBaseName(jsonPath);
    const QString outName = m_editPrefix->text() + base + m_editSuffix->text() + ".xlsx";

    QFileInfo fi(jsonPath);

    switch (currentDestMode()) {
    case DestMode::SameFolder:
        return QDir(fi.dir().absolutePath()).filePath(outName);

    case DestMode::ExcelSubfolder: {
        const QString calRoot = calicatasRootDirForJson(jsonPath); // .../Calicatas
        return QDir(QDir(calRoot).filePath("EXCEL")).filePath(outName);
    }

    case DestMode::OneFolder: {
        const QString outDir = m_editOutDir->text().trimmed();
        if (outDir.isEmpty()) return QString();
        return QDir(outDir).filePath(outName);
    }
    }

    return QString();
}

void ExportExcelBatchDialog::setRowStatus(int row, const QString& status)
{
    if (row < 0 || row >= m_table->rowCount()) return;
    auto *it = m_table->item(row, 2);
    if (!it) {
        it = new QTableWidgetItem();
        m_table->setItem(row, 2, it);
    }
    it->setText(status);
}

void ExportExcelBatchDialog::syncOutPathsColumn()
{
    for (int r = 0; r < m_table->rowCount(); ++r) {
        auto *it0 = m_table->item(r, 0);
        auto *it1 = m_table->item(r, 1);
        if (!it0 || !it1) continue;

        const QString jsonPath = it0->data(Qt::UserRole).toString();
        it1->setText(computeOutPath(jsonPath));
    }
}

void ExportExcelBatchDialog::addFiles()
{
    // Usa tu diálogo tipo árbol con multi selección
    GuardarCalicataDialog dlg(m_projectsRoot, "", this);
    dlg.setMode(GuardarCalicataDialog::Mode::Open);

    if (dlg.exec() != QDialog::Accepted)
        return;

    const QStringList files = dlg.selectedFilePaths();
    if (files.isEmpty()) return;

    // Deduplicar
    QSet<QString> existing;
    for (int r = 0; r < m_table->rowCount(); ++r) {
        auto *it = m_table->item(r, 0);
        if (it) existing.insert(it->data(Qt::UserRole).toString());
    }

    for (const QString& f : files) {
        if (existing.contains(f)) continue;
        existing.insert(f);

        int row = m_table->rowCount();
        m_table->insertRow(row);

        QFileInfo fi(f);

        auto *it0 = new QTableWidgetItem(fi.fileName());
        it0->setData(Qt::UserRole, f);

        auto *it1 = new QTableWidgetItem(computeOutPath(f));
        auto *it2 = new QTableWidgetItem(tr("Pendiente"));

        m_table->setItem(row, 0, it0);
        m_table->setItem(row, 1, it1);
        m_table->setItem(row, 2, it2);
    }
}

void ExportExcelBatchDialog::removeSelected()
{
    auto rows = m_table->selectionModel()->selectedRows();
    std::sort(rows.begin(), rows.end(), [](const QModelIndex& a, const QModelIndex& b){
        return a.row() > b.row();
    });
    for (const QModelIndex& idx : rows)
        m_table->removeRow(idx.row());
}

void ExportExcelBatchDialog::clearAll()
{
    m_table->setRowCount(0);
}

void ExportExcelBatchDialog::browseOutDir()
{
    // Root “seguro”
    QString root = m_projectsRoot.trimmed();
    if (root.isEmpty()) {
        root = QStandardPaths::writableLocation(QStandardPaths::HomeLocation)
        + "/InGePlusProyectos";
    }

    const QString current = m_editOutDir ? m_editOutDir->text().trimmed() : QString();

    SelectFolderDialog dlg(root, current, this);
    if (dlg.exec() != QDialog::Accepted)
        return;

    const QString sel = dlg.selectedDir().trimmed();
    if (sel.isEmpty())
        return;

#ifdef Q_OS_WIN
    const Qt::CaseSensitivity cs = Qt::CaseInsensitive;
#else
    const Qt::CaseSensitivity cs = Qt::CaseSensitive;
#endif

    // 🔒 Seguridad: solo permitir dentro del root
    const QString normRoot = QDir::cleanPath(QDir::fromNativeSeparators(root));
    const QString normSel  = QDir::cleanPath(QDir::fromNativeSeparators(sel));

    if (!normSel.startsWith(normRoot + "/", cs) && normSel != normRoot) {
        QMessageBox::warning(this, tr("Carpeta no permitida"),
                             tr("Por seguridad, solo puedes elegir una carpeta dentro de:\n%1").arg(root));
        return;
    }

    m_editOutDir->setText(sel);
    syncOutPathsColumn();
}

bool ExportExcelBatchDialog::exportOneJsonToExcel(const QString& jsonPath,
                                                  const QString& outXlsx,
                                                  QString* err)
{
    return CalicataExcelExporter::exportFromCalicataFile(jsonPath, outXlsx, err);
}

void ExportExcelBatchDialog::doExport()
{
    if (m_table->rowCount() == 0) {
        QMessageBox::warning(this, tr("Exportar"), tr("Agrega al menos un archivo."));
        return;
    }

    if (currentDestMode() == DestMode::OneFolder) {
        const QString outDir = m_editOutDir->text().trimmed();
        if (outDir.isEmpty()) {
            QMessageBox::warning(this, tr("Exportar"), tr("Elige la carpeta de salida."));
            return;
        }
        if (!QDir(outDir).exists()) {
            QMessageBox::warning(this, tr("Exportar"), tr("La carpeta de salida no existe."));
            return;
        }
    }

    QProgressDialog prog(tr("Exportando a Excel..."), tr("Cancelar"),
                         0, m_table->rowCount(), this);
    prog.setWindowModality(Qt::ApplicationModal);
    prog.setMinimumDuration(0);

    int ok = 0, fail = 0;

    for (int r = 0; r < m_table->rowCount(); ++r) {
        prog.setValue(r);
        if (prog.wasCanceled())
            break;

        auto *it0 = m_table->item(r, 0);
        auto *it1 = m_table->item(r, 1);
        if (!it0 || !it1) { ++fail; continue; }

        const QString jsonPath = it0->data(Qt::UserRole).toString();
        const QString outXlsx = it1->text().trimmed();

        if (outXlsx.isEmpty()) {
            setRowStatus(r, tr("Error: salida vacía"));
            ++fail;
            continue;
        }

        QFileInfo outFi(outXlsx);
        QDir outDir(outFi.dir());

        // crear carpeta si hace falta (sobre todo en modo EXCEL subfolder)
        if (!outDir.exists()) {
            if (!QDir().mkpath(outDir.absolutePath())) {
                setRowStatus(r, tr("Error: no se pudo crear carpeta"));
                ++fail;
                continue;
            }
        }

        if (QFileInfo::exists(outXlsx) && !m_chkOverwrite->isChecked()) {
            setRowStatus(r, tr("Saltado: ya existe"));
            continue;
        }

        QString err;
        setRowStatus(r, tr("Exportando..."));

        const bool success = exportOneJsonToExcel(jsonPath, outXlsx, &err);
        if (success) {
            setRowStatus(r, tr("OK"));
            ++ok;
        } else {
            setRowStatus(r, tr("ERROR"));
            ++fail;
            m_table->item(r, 2)->setToolTip(err);
        }
    }

    prog.setValue(m_table->rowCount());

    QMessageBox::information(this, tr("Exportar"),
                             tr("Listo.\nOK: %1\nErrores: %2").arg(ok).arg(fail));
}
