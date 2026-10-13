#include "globalsearch.h"
#include <QCompleter>
#include <QDirIterator>
#include <QFileInfo>
#include <QTimer>
#include <QtConcurrent>
#include <QFutureWatcher>
#include <QAbstractItemView>
#include <QRegularExpression>
#include <QAbstractItemView>
#include <QListView>
#include <QScrollBar>
#include <QFont>

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
    const QModelIndex idx = sourceModel()->index(sourceRow, 0, sourceParent);

    const int kind = sourceModel()->data(idx, GlobalSearchModel::KindRole).toInt();
    const QString title = sourceModel()->data(idx, GlobalSearchModel::TitleRole).toString();
    const QString sub   = sourceModel()->data(idx, GlobalSearchModel::SubRole).toString();
    const QStringList keywords = sourceModel()->data(idx, GlobalSearchModel::KeywordsRole).toStringList();

    if (m_query.isEmpty()) {
        return (kind == GlobalSearchModel::Action); // solo acciones cuando está vacío
    }

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
    // Navegación principal
    m_model->addAction(
        "open_home",
        "Ir a Inicio",
        "Navegación",
        {"home", "inicio", "principal", "menu"}
        );

    m_model->addAction(
        "open_calicatas",
        "Abrir Ficha de Calicata",
        "Módulo",
        {"calicata", "calicatas", "ficha", "testificacion", "testificación", "excavacion", "excavación"}
        );

    m_model->addAction(
        "open_taludes",
        "Abrir Ficha de Talud",
        "Módulo en construcción",
        {"talud", "taludes", "ficha talud", "taludes"}
        );

    m_model->addAction(
        "open_docs",
        "Abrir Documentos",
        "Módulo",
        {"docs", "documentos", "archivos", "carpetas", "explorador", "proyectos"}
        );

    m_model->addAction(
        "open_ubi",
        "Abrir Ubicación",
        "Módulo",
        {"ubicacion", "ubicación", "gps", "mapa", "coordenadas", "utm"}
        );

    m_model->addAction(
        "open_perf",
        "Abrir Perfil",
        "Módulo",
        {"perfil", "cuenta", "usuario", "sesion", "sesión"}
        );

    // Acciones rápidas
    m_model->addAction(
        "sync",
        "Sincronizar",
        "Nube / almacenamiento",
        {"sync", "sincronizar", "nube", "supabase", "subir"}
        );
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
    if (!edit)
        return;

    // Evita conectar varias veces el mismo lineEdit
    if (edit->property("globalSearchAttached").toBool())
        return;

    edit->setProperty("globalSearchAttached", true);


    edit->setStyleSheet(R"QSS(
QLineEdit {
    background-color: #FFFFFF;
    color: #0F1F2A;
    border: 2px solid rgba(0,135,174,90);
    border-radius: 10px;
    padding: 6px 10px;
    selection-background-color: #0087AE;
    selection-color: #FFFFFF;
}

QLineEdit:focus {
    border: 2px solid #FDAC11;
    background-color: #FFFFFF;
}
)QSS");

    auto* completer = new QCompleter(m_proxy, edit);

    completer->setCaseSensitivity(Qt::CaseInsensitive);

    // El filtrado real lo hace GlobalSearchProxy.
    // Esto evita que QCompleter vuelva a filtrar por prefijo y oculte resultados por keywords.
    completer->setCompletionMode(QCompleter::UnfilteredPopupCompletion);

    completer->setMaxVisibleItems(12);
    completer->setCompletionRole(GlobalSearchModel::TitleRole);
    completer->setCompletionColumn(0);

    // ============================================================
    // Popup del buscador con paleta InGe+
    // ============================================================
    auto *popup = new QListView(edit);
    popup->setObjectName("GlobalSearchPopup");
    popup->setMouseTracking(true);
    popup->setUniformItemSizes(false);
    popup->setAlternatingRowColors(false);
    popup->setEditTriggers(QAbstractItemView::NoEditTriggers);
    popup->setSelectionBehavior(QAbstractItemView::SelectRows);
    popup->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    popup->setVerticalScrollBarPolicy(Qt::ScrollBarAsNeeded);

    QFont popupFont = popup->font();
    popupFont.setPointSize(9);
    popup->setFont(popupFont);

    popup->setStyleSheet(R"QSS(
QListView#GlobalSearchPopup {
    background-color: #FFFFFF;
    color: #0F1F2A;
    border: 2px solid #0087AE;
    border-radius: 12px;
    padding: 6px;
    outline: 0;
    selection-background-color: #0087AE;
    selection-color: #FFFFFF;
}

QListView#GlobalSearchPopup::item {
    min-height: 28px;
    padding: 7px 10px;
    border-radius: 8px;
    color: #0F1F2A;
    background: transparent;
}

QListView#GlobalSearchPopup::item:hover {
    background-color: rgba(0,135,174,25);
    color: #0F1F2A;
}

QListView#GlobalSearchPopup::item:selected {
    background-color: #0087AE;
    color: #FFFFFF;
}

QListView#GlobalSearchPopup::item:selected:active {
    background-color: #0087AE;
    color: #FFFFFF;
}

QListView#GlobalSearchPopup::item:selected:!active {
    background-color: #0087AE;
    color: #FFFFFF;
}

QScrollBar:vertical {
    background: transparent;
    width: 12px;
    margin: 4px 2px 4px 2px;
}

QScrollBar::handle:vertical {
    background: rgba(0,135,174,90);
    min-height: 26px;
    border-radius: 6px;
}

QScrollBar::handle:vertical:hover {
    background: #0087AE;
}

QScrollBar::add-line:vertical,
QScrollBar::sub-line:vertical {
    height: 0px;
}

QScrollBar::add-page:vertical,
QScrollBar::sub-page:vertical {
    background: transparent;
}
)QSS");

    completer->setPopup(popup);
    edit->setCompleter(completer);

    // Debounce para no filtrar en cada tecla inmediatamente
    auto* timer = new QTimer(edit);
    timer->setSingleShot(true);
    timer->setInterval(120);

    auto refreshPopup = [this, edit, completer]() {
        const QString q = edit->text().trimmed();

        m_proxy->setQuery(q);

        if (q.isEmpty()) {
            if (completer->popup())
                completer->popup()->hide();
            return;
        }

        if (m_proxy->rowCount() <= 0) {
            if (completer->popup())
                completer->popup()->hide();
            return;
        }

        // Evita que QCompleter aplique otro filtro por prefijo.
        completer->setCompletionPrefix(QString());
        completer->complete();
    };

    connect(edit, &QLineEdit::textChanged, edit, [timer]() {
        timer->start();
    });

    connect(timer, &QTimer::timeout, edit, refreshPopup);

    auto triggerIndex = [this, edit](const QModelIndex& idx) {
        if (!idx.isValid())
            return;

        // Leemos roles directamente del índice entregado por QCompleter.
        // Es más estable que mapToSource(), porque QCompleter puede usar un completionModel interno.
        const int kind = idx.data(GlobalSearchModel::KindRole).toInt();
        const QString payload = idx.data(GlobalSearchModel::PayloadRole).toString();

        if (payload.trimmed().isEmpty())
            return;

        edit->clear();

        if (kind == GlobalSearchModel::Action) {
            emit actionTriggered(payload);
        } else {
            emit pathTriggered(payload);
        }
    };

    connect(completer,
            QOverload<const QModelIndex&>::of(&QCompleter::activated),
            edit,
            triggerIndex);

    // Enter: ejecuta el resultado seleccionado o el primero visible
    connect(edit, &QLineEdit::returnPressed, edit, [this, edit, completer, triggerIndex]() {
        if (!edit)
            return;

        const QString q = edit->text().trimmed();
        if (q.isEmpty())
            return;

        m_proxy->setQuery(q);

        QModelIndex idx;

        if (completer->popup() && completer->popup()->isVisible()) {
            idx = completer->popup()->currentIndex();
        }

        if (!idx.isValid() && m_proxy->rowCount() > 0) {
            idx = m_proxy->index(0, 0);
        }

        triggerIndex(idx);
    });
}
