#pragma once

#include <QDialog>
#include <QFileSystemModel>
#include <QTreeView>
#include <QLabel>
#include <QDialogButtonBox>
#include <QVBoxLayout>
#include <QPushButton>
#include <QDir>
#include <QFileInfo>

class ResourcesImagePickerDialog : public QDialog
{
public:
    explicit ResourcesImagePickerDialog(const QString &rootDirAbs,
                                        const QString &title,
                                        QWidget *parent = nullptr)
        : QDialog(parent)
        , m_rootDir(QDir::cleanPath(rootDirAbs))
    {
        setWindowTitle(title);
        setModal(true);
        resize(860, 520);

        if (!QDir(m_rootDir).exists()) {
            QDir().mkpath(m_rootDir);
        }

        auto *lay = new QVBoxLayout(this);
        lay->setContentsMargins(10,10,10,10);
        lay->setSpacing(8);

        auto *lbl = new QLabel(tr("Selecciona un logo dentro de la carpeta Recursos:"), this);
        lay->addWidget(lbl);

        m_model = new QFileSystemModel(this);
        m_model->setReadOnly(true);
        m_model->setFilter(QDir::NoDotAndDotDot | QDir::AllDirs | QDir::Files);
        m_model->setNameFilterDisables(false);
        m_model->setNameFilters(QStringList() << "*.png" << "*.jpg" << "*.jpeg" << "*.bmp" << "*.webp");

        const QModelIndex rootIdx = m_model->setRootPath(m_rootDir);

        m_view = new QTreeView(this);
        m_view->setModel(m_model);
        m_view->setRootIndex(rootIdx);
        m_view->setSelectionMode(QAbstractItemView::SingleSelection);
        m_view->setSelectionBehavior(QAbstractItemView::SelectRows);
        m_view->setEditTriggers(QAbstractItemView::NoEditTriggers);
        m_view->setUniformRowHeights(true);
        m_view->setRootIsDecorated(false);
        m_view->setHeaderHidden(true);

        for (int c = 1; c < m_model->columnCount(); ++c)
            m_view->hideColumn(c);

        lay->addWidget(m_view, 1);

        m_preview = new QLabel(this);
        m_preview->setMinimumHeight(140);
        m_preview->setAlignment(Qt::AlignCenter);
        m_preview->setText(tr("Vista previa"));
        lay->addWidget(m_preview);

        m_buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
        lay->addWidget(m_buttons);

        m_ok = m_buttons->button(QDialogButtonBox::Ok);
        if (m_ok) m_ok->setEnabled(false);

        connect(m_buttons, &QDialogButtonBox::accepted, this, [this](){
            if (hasValidSelection())
                accept();
        });
        connect(m_buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);

        connect(m_view->selectionModel(), &QItemSelectionModel::selectionChanged, this, [this](){
            updateUiFromSelection();
        });

        connect(m_view, &QTreeView::doubleClicked, this, [this](const QModelIndex &idx){
            if (!idx.isValid()) return;
            if (!m_model->isDir(idx)) {
                m_selectedAbs = m_model->filePath(idx);
                accept();
            }
        });
    }

    QString selectedAbsPath() const { return m_selectedAbs; }

private:
    bool hasValidSelection()
    {
        const QModelIndex idx = m_view ? m_view->currentIndex() : QModelIndex();
        if (!idx.isValid() || m_model->isDir(idx)) return false;

        m_selectedAbs = m_model->filePath(idx);
        return QFileInfo::exists(m_selectedAbs);
    }

    void updateUiFromSelection()
    {
        const QModelIndex idx = m_view->currentIndex();
        if (!idx.isValid() || m_model->isDir(idx)) {
            m_selectedAbs.clear();
            m_preview->setText(tr("Vista previa"));
            if (m_ok) m_ok->setEnabled(false);
            return;
        }

        m_selectedAbs = m_model->filePath(idx);

        QPixmap pix(m_selectedAbs);
        if (!pix.isNull()) {
            m_preview->setPixmap(pix.scaled(m_preview->size(), Qt::KeepAspectRatio, Qt::SmoothTransformation));
            m_preview->setText("");
        } else {
            m_preview->setText(tr("No se pudo cargar la imagen"));
        }

        if (m_ok) m_ok->setEnabled(true);
    }

private:
    QString m_rootDir;
    QFileSystemModel *m_model = nullptr;
    QTreeView *m_view = nullptr;
    QLabel *m_preview = nullptr;
    QDialogButtonBox *m_buttons = nullptr;
    QPushButton *m_ok = nullptr;
    QString m_selectedAbs;
    QString m_selectedAbsPath;
};
