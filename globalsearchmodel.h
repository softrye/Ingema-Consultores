#pragma once
#include <QObject>
#include <QAbstractListModel>
#include <QSortFilterProxyModel>
#include <QPointer>
#include <QLineEdit>
#include <QIcon>

class GlobalSearchModel : public QAbstractListModel
{
    Q_OBJECT
public:
    enum Kind { Action = 0, File = 1, Folder = 2 };
    enum Roles {
        TitleRole = Qt::UserRole + 1,
        SubRole,
        KindRole,
        PayloadRole,
        KeywordsRole
    };

    explicit GlobalSearchModel(QObject* parent=nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void clear();
    void addAction(const QString& id, const QString& title, const QString& sub, const QStringList& keywords);
    void addPath(int kind, const QString& title, const QString& sub, const QString& fullPath);

private:
    struct Item {
        int kind = File;
        QString title;
        QString sub;
        QString payload;      // id (action) o path (file/folder)
        QStringList keywords; // para buscar por alias
    };
    QVector<Item> m_items;
};

class GlobalSearchProxy : public QSortFilterProxyModel
{
    Q_OBJECT
public:
    explicit GlobalSearchProxy(QObject* parent=nullptr);

    void setQuery(const QString& q);

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex& sourceParent) const override;
    bool lessThan(const QModelIndex& left, const QModelIndex& right) const override;

private:
    QString m_query;

    int scoreFor(const QString& title, const QString& sub, const QStringList& keywords) const;
    static QString norm(QString s);
};

class GlobalSearch : public QObject
{
    Q_OBJECT
public:
    static GlobalSearch* instance();

    void setRootToIndex(const QString& root);
    void registerDefaultActions(); // opcional
    void attach(QLineEdit* edit);

signals:
    void actionTriggered(const QString& actionId);
    void pathTriggered(const QString& path);

public slots:
    void rebuildIndexAsync();

private:
    explicit GlobalSearch(QObject* parent=nullptr);

    QString m_root;
    GlobalSearchModel* m_model = nullptr;
    GlobalSearchProxy* m_proxy = nullptr;

    void addDefaultActions();
    void indexFiles(const QString& root);
};
