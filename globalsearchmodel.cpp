#include "globalsearchmodel.h"
#include <QCompleter>
#include <QDirIterator>
#include <QFileInfo>
#include <QTimer>
#include <QtConcurrent>
#include <QFutureWatcher>

static const int kMaxResults = 20000; // tope de index (ajústalo)

GlobalSearchModel::GlobalSearchModel(QObject* parent) : QAbstractListModel(parent) {}

int GlobalSearchModel::rowCount(const QModelIndex& parent) const
{
    if (parent.isValid()) return 0;
    return m_items.size();
}

QVariant GlobalSearchModel::data(const QModelIndex& index, int role) const
{
    if (!index.isValid() || index.row() < 0 || index.row() >= m_items.size()) return {};
    const auto& it = m_items[index.row()];

    switch (role) {
    case Qt::DisplayRole:
    case TitleRole:   return it.title;
    case SubRole:     return it.sub;
    case KindRole:    return it.kind;
    case PayloadRole: return it.payload;
    case KeywordsRole:return it.keywords;
    default:          return {};
    }
}

QHash<int, QByteArray> GlobalSearchModel::roleNames() const
{
    return {
        {TitleRole, "title"},
        {SubRole, "sub"},
        {KindRole, "kind"},
        {PayloadRole, "payload"},
        {KeywordsRole, "keywords"}
    };
}

void GlobalSearchModel::clear()
{
    beginResetModel();
    m_items.clear();
    endResetModel();
}

void GlobalSearchModel::addAction(const QString& id, const QString& title, const QString& sub, const QStringList& keywords)
{
    beginInsertRows(QModelIndex(), m_items.size(), m_items.size());
    Item it;
    it.kind = Action;
    it.title = title;
    it.sub = sub;
    it.payload = id;
    it.keywords = keywords;
    m_items.push_back(it);
    endInsertRows();
}

void GlobalSearchModel::addPath(int kind, const QString& title, const QString& sub, const QString& fullPath)
{
    beginInsertRows(QModelIndex(), m_items.size(), m_items.size());
    Item it;
    it.kind = kind;
    it.title = title;
    it.sub = sub;
    it.payload = fullPath;
    m_items.push_back(it);
    endInsertRows();
}

// ---------------- Proxy ----------------

GlobalSearchProxy::GlobalSearchProxy(QObject* parent) : QSortFilterProxyModel(parent)
{
    setFilterCaseSensitivity(Qt::CaseInsensitive);
    setDynamicSortFilter(true);
}

QString GlobalSearchProxy::norm(QString s)
{
    s = s.toLower().trimmed();
    return s;
}

void GlobalSearchProxy::setQuery(const QString& q)
{
    m_query = norm(q);
    invalidateFilter();
    sort(0);
}

int GlobalSearchProxy::scoreFor(const QString& title, const QString& sub, const QStringList& keywords) const
{
    const QString t = norm(title);
    const QString s = norm(sub);

    if (m_query.isEmpty()) return 0;

    int score = 0;

    // match fuerte por inicio
    if (t.startsWith(m_query)) score += 120;
    else if (t.contains(m_query)) score += 80;

    // match por subtexto (ruta)
    if (s.contains(m_query)) score += 35;

    // keywords/alias
    for (const auto& k : keywords) {
        const QString kk = norm(k);
        if (kk.startsWith(m_query)) score += 60;
        else if (kk.contains(m_query)) score += 30;
    }

    // bonus si coincide con una "palabra" (separadores comunes)
    const auto parts = t.split(QRegularExpression("[\\s\\-_.]+"), Qt::SkipEmptyParts);
    for (const auto& p : parts)
        if (p.startsWith(m_query)) score += 30;

    return score;
}

bool GlobalSearchProxy::filterAcceptsRow(int sourceRow, const QModelIndex& sourceParent) const
{
    if (m_query.isEmpty()) return false; // si quieres “mostrar acciones por defecto”, cambia esto a true
    const QModelIndex idx = sourceModel()->index(sourceRow, 0, sourceParent);

    const QString title = sourceModel()->data(idx, GlobalSearchModel::TitleRole).toString();
    const QString sub   = sourceModel()->data(idx, GlobalSearchModel::SubRole).toString();
    const QStringList keywords = sourceModel()->data(idx, GlobalSearchModel::KeywordsRole).toStringList();

    return scoreFor(title, sub, keywords) > 0;
}

bool GlobalSearchProxy::lessThan(const QModelIndex& left, const QModelIndex& right) const
{
    const auto tl = sourceModel()->data(left,  GlobalSearchModel::TitleRole).toString();
    const auto sl = sourceModel()->data(left,  GlobalSearchModel::SubRole).toString();
    const auto kl = sourceModel()->data(left,  GlobalSearchModel::KeywordsRole).toStringList();

    const auto tr = sourceModel()->data(right, GlobalSearchModel::TitleRole).toString();
    const auto sr = sourceModel()->data(right, GlobalSearchModel::SubRole).toString();
    const auto kr = sourceModel()->data(right, GlobalSearchModel::KeywordsRole).toStringList();

    return scoreFor(tl, sl, kl) > scoreFor(tr, sr, kr);
}

// ---------------- GlobalSearch ----------------

GlobalSearch* GlobalSearch::instance()
{
    static GlobalSearch g;
    return &g;
}

GlobalSearch::GlobalSearch(QObject* parent) : QObject(parent)
{
    m_model = new GlobalSearchModel(this);
    m_proxy = new GlobalSearchProxy(this);
    m_proxy->setSourceModel(m_model);

    addDefaultActions();
}

void GlobalSearch::setRootToIndex(const QString& root)
{
    m_root = root;
}

void GlobalSearch::addDefaultActions()
{
    // Accesos directos (ajusta ids como tú quieras)
    m_model->addAction("open_home", "Ir a Inicio", "Navegación", {"home","inicio"});
    m_model->addAction("open_docs", "Abrir Documentos", "Módulo", {"docs","documentos","archivos"});
    m_model->addAction("open_ubi",  "Abrir Ubicación", "Módulo", {"ubicacion","gps","mapa"});
    m_model->addAction("open_perf", "Abrir Perfil", "Módulo", {"perfil","cuenta","sesion"});
    m_model->addAction("sync",      "Sincronizar", "Nube / almacenamiento", {"sync","sincronizar","nube"});
}

void GlobalSearch::rebuildIndexAsync()
{
    if (m_root.trimmed().isEmpty()) return;

    // Limpia SOLO paths (pero conserva acciones)
    // Para simplificar: reiniciamos todo y re-agregamos acciones.
    m_model->clear();
    addDefaultActions();

    const QString root = m_root;

    auto* watcher = new QFutureWatcher<void>(this);
    connect(watcher, &QFutureWatcher<void>::finished, this, [watcher]{
        watcher->deleteLater();
    });

    watcher->setFuture(QtConcurrent::run([this, root]{
        indexFiles(root);
    }));
}

void GlobalSearch::indexFiles(const QString& root)
{
    QDirIterator it(root,
                    QDir::Dirs | QDir::Files | QDir::NoDotAndDotDot,
                    QDirIterator::Subdirectories);

    int count = 0;
    while (it.hasNext() && count < kMaxResults) {
        it.next();
        const QFileInfo fi = it.fileInfo();

        // Puedes saltarte carpetas pesadas si quieres (build, .git, etc.)
        const QString abs = fi.absoluteFilePath();
        if (abs.contains("/build/", Qt::CaseInsensitive) || abs.contains("\\build\\", Qt::CaseInsensitive))
            continue;

        const QString title = fi.fileName();
        const QString sub   = fi.absoluteFilePath();

        // Filtra por tipos más útiles (opcional)
        if (fi.isFile()) {
            const QString ext = fi.suffix().toLower();
            // si quieres TODO, comenta este if:
            if (!(ext == "pdf" || ext == "xlsx" || ext == "xls" || ext == "jpg" || ext == "jpeg" || ext == "png" || ext == "json"))
                continue;

            QMetaObject::invokeMethod(m_model, [this, title, sub]{
                m_model->addPath(GlobalSearchModel::File, title, sub, sub);
            }, Qt::QueuedConnection);
        } else if (fi.isDir()) {
            QMetaObject::invokeMethod(m_model, [this, title, sub]{
                m_model->addPath(GlobalSearchModel::Folder, title, sub, sub);
            }, Qt::QueuedConnection);
        }

        ++count;
    }
}

void GlobalSearch::attach(QLineEdit* edit)
{
    if (!edit) return;

    auto* completer = new QCompleter(m_proxy, edit);
    completer->setCaseSensitivity(Qt::CaseInsensitive);
    completer->setCompletionMode(QCompleter::PopupCompletion);
    completer->setMaxVisibleItems(12);
    edit->setCompleter(completer);

    // debounce para no filtrar 1000 veces por segundo
    auto* t = new QTimer(edit);
    t->setSingleShot(true);
    t->setInterval(120);

    QObject::connect(edit, &QLineEdit::textEdited, edit, [this, t](const QString&){
        t->start();
    });

    QObject::connect(t, &QTimer::timeout, edit, [this, edit](){
        m_proxy->setQuery(edit->text());
        if (!edit->text().trimmed().isEmpty())
            edit->completer()->complete();
    });

    QObject::connect(completer, QOverload<const QModelIndex&>::of(&QCompleter::activated),
                     edit, [this](const QModelIndex& proxyIdx){
                         if (!proxyIdx.isValid()) return;

                         const QModelIndex srcIdx = m_proxy->mapToSource(proxyIdx);
                         const int kind = m_model->data(srcIdx, GlobalSearchModel::KindRole).toInt();
                         const QString payload = m_model->data(srcIdx, GlobalSearchModel::PayloadRole).toString();

                         if (kind == GlobalSearchModel::Action) {
                             emit actionTriggered(payload);
                         } else {
                             emit pathTriggered(payload); // archivo o carpeta
                         }
                     });
}
