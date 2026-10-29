#include "guardarcalicatadialog.h"
#include "pathscope.h"
#include "ingetheme.h"

#include <QTreeView>
#include <QFileSystemModel>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QDialogButtonBox>
#include <QDir>
#include <QPushButton>
#include <QFileInfo>
#include <QMessageBox>

#include <QSettings>
#include <QScrollBar>
#include <QItemSelectionModel>
#include <QTimer>

GuardarCalicataDialog::GuardarCalicataDialog(const QString &basePath,
                                             const QString &defaultFileName,
                                             QWidget *parent)
    : QDialog(parent)
    , m_basePath(QDir::cleanPath(QDir::fromNativeSeparators(basePath)))
{

    setWindowTitle(tr("Guardar ficha de calicata"));
    resize(750, 450);

    auto *mainLayout = new QVBoxLayout(this);

    m_lblHelp = new QLabel(this);
    m_lblHelp->setWordWrap(true);
    mainLayout->addWidget(m_lblHelp);

    m_model = new QFileSystemModel(this);

    m_tree = new QTreeView(this);
    m_tree->setModel(m_model);
    m_tree->setHeaderHidden(true);
    m_tree->setSelectionMode(QAbstractItemView::SingleSelection);
    m_tree->setEditTriggers(QAbstractItemView::NoEditTriggers);
    m_tree->setExpandsOnDoubleClick(true);
    m_tree->setAlternatingRowColors(true);
    m_tree->setUniformRowHeights(true);
    m_tree->setIndentation(18);


    m_basePath = ensureUserScopedRoot(m_basePath);

    mainLayout->addWidget(m_tree, 1);

    // Nombre de archivo (solo Save)
    auto *fileLayout = new QHBoxLayout();
    auto *lblFile = new QLabel(tr("Nombre de archivo:"), this);
    m_editFileName = new QLineEdit(this);
    if (!defaultFileName.isEmpty())
        m_editFileName->setText(defaultFileName);

    fileLayout->addWidget(lblFile);
    fileLayout->addWidget(m_editFileName, 1);
    mainLayout->addLayout(fileLayout);

    // Botones
    auto *buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel,
                                         Qt::Horizontal, this);

    m_btnOk = buttons->button(QDialogButtonBox::Ok);

    // ✅ IMPORTANTE:
    // NO conectes a QDialog::reject porque saltas tu override.
    connect(buttons, &QDialogButtonBox::accepted, this, &GuardarCalicataDialog::onAccept);
    connect(buttons, &QDialogButtonBox::rejected, this, [this](){ this->reject(); });

    mainLayout->addWidget(buttons);

    connect(m_tree, &QTreeView::clicked, this, &GuardarCalicataDialog::onTreeClicked);
    connect(m_tree, &QTreeView::doubleClicked, this, &GuardarCalicataDialog::onTreeDoubleClicked);

    connect(m_tree, &QTreeView::expanded, this, &GuardarCalicataDialog::onExpanded);
    connect(m_tree, &QTreeView::collapsed, this, &GuardarCalicataDialog::onCollapsed);

    connect(m_editFileName, &QLineEdit::textChanged, this, [this](){
        updateOkButtonState();
        scheduleSaveUiState(); // ✅ si cambia nombre, también guarda estado (por consistencia)
    });

    // Modo default: Save
    setMode(Mode::Save);

    updateOkButtonState();
}

GuardarCalicataDialog::~GuardarCalicataDialog() = default;

void GuardarCalicataDialog::setMode(Mode mode)
{
    m_mode = mode;
    m_selectedPath.clear();

    const bool isSave = (m_mode == Mode::Save);
    m_editFileName->setVisible(isSave);

    if (m_lblHelp) {
        if (isSave) {
            setWindowTitle(tr("Guardar ficha de calicata"));
            m_lblHelp->setText(tr("Selecciona la carpeta del proyecto donde guardar la ficha\n"
                                  "y escribe un nombre de archivo:"));
        } else {
            setWindowTitle(tr("Abrir ficha de calicata"));
            m_lblHelp->setText(tr("Selecciona una o varias fichas .calicata.json y presiona OK,\n"
                                  "o abre con doble click."));
        }
    }

    // selección multi solo en Open
    if (m_tree) {
        m_tree->setSelectionMode(isSave ? QAbstractItemView::SingleSelection
                                        : QAbstractItemView::ExtendedSelection);
    }

    rebuildModel();
    scheduleRestoreUiState();
    updateOkButtonState();
}

void GuardarCalicataDialog::rebuildModel()
{
    if (!m_model || !m_tree) return;

    QDir().mkpath(m_basePath);

    if (m_mode == Mode::Save) {
        m_model->setFilter(QDir::AllDirs | QDir::NoDotAndDotDot);
        m_model->setNameFilters({});
        m_model->setNameFilterDisables(true);
    } else {
        m_model->setFilter(QDir::AllDirs | QDir::Files | QDir::NoDotAndDotDot);
        m_model->setNameFilters(QStringList() << "*.calicata.json");
        m_model->setNameFilterDisables(false);
    }

    m_model->setRootPath(m_basePath);
    m_tree->setRootIndex(m_model->index(m_basePath));

    for (int c = 1; c < m_model->columnCount(); ++c)
        m_tree->hideColumn(c);

    // ✅ OJO: el selectionModel se recrea cuando se cambia el model/root,
    // así que conecta aquí (otra vez) para guardar estado en vivo.
    if (m_tree->selectionModel()) {
        connect(m_tree->selectionModel(), &QItemSelectionModel::currentChanged,
                this, [this](const QModelIndex&, const QModelIndex&){
                    if (m_restoring) return;
                    updateOkButtonState();
                    scheduleSaveUiState();
                });

        connect(m_tree->selectionModel(), &QItemSelectionModel::selectionChanged,
                this, [this](){
                    if (m_restoring) return;
                    updateOkButtonState();
                    scheduleSaveUiState();
                });
    }

    if (m_tree->verticalScrollBar()) {
        connect(m_tree->verticalScrollBar(), &QScrollBar::valueChanged,
                this, [this](int){
                    if (m_restoring) return;
                    scheduleSaveUiState();
                });
    }
}

QString GuardarCalicataDialog::selectedFolder() const
{
    QModelIndex idx = m_tree->currentIndex();
    if (!idx.isValid()) return m_basePath;

    QString path = m_model->filePath(idx);
    if (path.isEmpty()) return m_basePath;

    QFileInfo fi(path);
    if (fi.isDir()) return fi.absoluteFilePath();
    return fi.absolutePath();
}

QString GuardarCalicataDialog::fileName() const
{
    return m_editFileName ? m_editFileName->text().trimmed() : QString();
}

QString GuardarCalicataDialog::selectedFilePath() const
{
    return m_selectedPath;
}

QStringList GuardarCalicataDialog::selectedFilePaths() const
{
    QStringList out;
    if (!m_tree || !m_model || !m_tree->selectionModel()) return out;

    const QModelIndexList rows = m_tree->selectionModel()->selectedRows();
    for (const QModelIndex& idx : rows) {
        const QFileInfo fi = m_model->fileInfo(idx);
        if (fi.isFile())
            out << fi.absoluteFilePath();
    }
    out.removeDuplicates();
    return out;
}

QString GuardarCalicataDialog::selectedBaseName() const
{
    if (m_selectedPath.isEmpty()) return QString();
    return QFileInfo(m_selectedPath).completeBaseName();
}

void GuardarCalicataDialog::onTreeClicked(const QModelIndex &index)
{
    const QString path = m_model->filePath(index);

    if (m_mode == Mode::Open) {
        if (QFileInfo(path).isFile())
            m_selectedPath = path;     // compat: último click file
        else
            m_selectedPath.clear();
    }

    updateOkButtonState();
    scheduleSaveUiState();
}

void GuardarCalicataDialog::onTreeDoubleClicked(const QModelIndex& idx)
{
    if (!idx.isValid() || !m_model || !m_tree) return;

    const QFileInfo info = m_model->fileInfo(idx);

    if (info.isDir()) {
        m_tree->setExpanded(idx, !m_tree->isExpanded(idx));
        // expanded/collapsed ya llaman scheduleSaveUiState
        return;
    }

    if (m_mode == Mode::Open) {
        // asegura selección
        if (m_tree->selectionModel()) {
            m_tree->selectionModel()->select(idx,
                                             QItemSelectionModel::ClearAndSelect | QItemSelectionModel::Rows);
        }

        // compat: primer seleccionado
        m_selectedPath = info.absoluteFilePath();
        accept(); // llama override accept() => guarda estado
        return;
    }
}

void GuardarCalicataDialog::updateOkButtonState()
{
    if (!m_btnOk) return;

    if (m_mode == Mode::Save) {
        m_btnOk->setEnabled(!fileName().isEmpty());
    } else {
        const QStringList paths = selectedFilePaths();
        m_btnOk->setEnabled(!paths.isEmpty());
        if (!paths.isEmpty())
            m_selectedPath = paths.first(); // compat
    }
}

void GuardarCalicataDialog::onAccept()
{
    if (m_mode == Mode::Open) {
        const QStringList paths = selectedFilePaths();
        if (paths.isEmpty()) {
            QMessageBox::warning(this, tr("Abrir"), tr("Selecciona uno o más archivos válidos."));
            return;
        }
        m_selectedPath = paths.first(); // compat
    } else {
        if (fileName().isEmpty()) {
            QMessageBox::warning(this, tr("Guardar"), tr("Debes escribir un nombre de archivo."));
            return;
        }
    }

    accept(); // override accept() guarda estado
}

void GuardarCalicataDialog::onExpanded(const QModelIndex& idx)
{
    if (m_restoring || !m_model) return;
    const QFileInfo fi = m_model->fileInfo(idx);
    if (fi.isDir()) {
        m_expandedAbs.insert(fi.absoluteFilePath());
        scheduleSaveUiState();
    }
}

void GuardarCalicataDialog::onCollapsed(const QModelIndex& idx)
{
    if (m_restoring || !m_model) return;
    const QFileInfo fi = m_model->fileInfo(idx);
    if (fi.isDir()) {
        m_expandedAbs.remove(fi.absoluteFilePath());
        scheduleSaveUiState();
    }
}

QString GuardarCalicataDialog::settingsGroup() const
{
    return (m_mode == Mode::Open)
    ? "GuardarCalicataDialog/Open"
    : "GuardarCalicataDialog/Save";
}

void GuardarCalicataDialog::scheduleRestoreUiState()
{
    if (m_restoreScheduled) return;
    m_restoreScheduled = true;

    QTimer::singleShot(0, this, [this](){
        m_restoreScheduled = false;
        restoreUiState();
    });
}

void GuardarCalicataDialog::restoreUiState()
{
    if (!m_tree || !m_model) return;

    m_restoring = true;

    QSettings s;
    s.beginGroup(settingsGroup());

    const QStringList expanded = s.value("expandedAbs").toStringList();
    const QString currentAbs   = s.value("currentAbs").toString();
    const int scrollV          = s.value("scrollV", 0).toInt();

    s.endGroup();

    // limpiar set y reconstruirlo desde settings
    m_expandedAbs.clear();

    // ✅ expandir cadena completa (para que funcione aunque los padres estén colapsados)
    for (const QString& abs : expanded) {
        expandPathChainAndRemember(abs);
    }

    // seleccionar lo guardado (si existía)
    if (!currentAbs.isEmpty()) {
        const QFileInfo fi(currentAbs);
        const QString target = fi.isDir() ? fi.absoluteFilePath() : fi.absolutePath();
        expandPathChainAndRemember(target);

        const QModelIndex ix = m_model->index(currentAbs);
        if (ix.isValid()) {
            m_tree->setCurrentIndex(ix);
            m_tree->scrollTo(ix, QAbstractItemView::PositionAtCenter);
        }
    }

    if (m_tree->verticalScrollBar())
        m_tree->verticalScrollBar()->setValue(scrollV);

    m_restoring = false;

    updateOkButtonState();
}

void GuardarCalicataDialog::scheduleSaveUiState()
{
    if (m_saveScheduled) return;
    m_saveScheduled = true;

    // debounce suave para no escribir QSettings a cada evento
    QTimer::singleShot(150, this, [this](){
        m_saveScheduled = false;
        saveUiState();
    });
}

void GuardarCalicataDialog::saveUiState() const
{
    if (!m_tree || !m_model) return;

    QString currentAbs;
    const QModelIndex cur = m_tree->currentIndex();
    if (cur.isValid())
        currentAbs = m_model->fileInfo(cur).absoluteFilePath();

    const int scrollV = m_tree->verticalScrollBar()
                            ? m_tree->verticalScrollBar()->value()
                            : 0;

    QSettings s;
    s.beginGroup(settingsGroup());
    s.setValue("expandedAbs", QStringList(m_expandedAbs.begin(), m_expandedAbs.end()));
    s.setValue("currentAbs", currentAbs);
    s.setValue("scrollV", scrollV);
    s.endGroup();
}

void GuardarCalicataDialog::expandPathChainAndRemember(const QString &absPath)
{
    if (!m_tree || !m_model) return;

    QString base = QDir::cleanPath(QDir::fromNativeSeparators(m_basePath));
    QString p = QDir::cleanPath(QDir::fromNativeSeparators(absPath));
    if (p.isEmpty()) return;

    // si es archivo, usamos su carpeta
    QFileInfo fi(p);
    if (fi.exists() && fi.isFile())
        p = fi.absolutePath();

    // solo si está dentro del base
#ifdef Q_OS_WIN
    const Qt::CaseSensitivity cs = Qt::CaseInsensitive;
#else
    const Qt::CaseSensitivity cs = Qt::CaseSensitive;
#endif
    if (!p.startsWith(base, cs)) return;

    // construir cadena desde base -> p
    QStringList chain;
    QString cur = p;

    while (!cur.isEmpty() && cur.startsWith(base, cs)) {
        chain.prepend(cur);
        QString parent = QFileInfo(cur).dir().absolutePath();
        if (parent == cur) break;
        if (QDir::cleanPath(parent) == base) {
            // incluir base si quieres, pero root ya está visible
            break;
        }
        cur = parent;
    }

    for (const QString& dirPath : chain) {
        const QModelIndex ix = m_model->index(dirPath);
        if (ix.isValid()) {
            m_tree->setExpanded(ix, true);
            m_expandedAbs.insert(QFileInfo(dirPath).absoluteFilePath());
        }
    }
}

void GuardarCalicataDialog::accept()
{
    saveUiState();          // ✅ siempre guarda al cerrar
    QDialog::accept();
}

void GuardarCalicataDialog::reject()
{
    saveUiState();          // ✅ ahora Cancel sí guarda (porque ya no llamamos QDialog::reject directo)
    QDialog::reject();
}
