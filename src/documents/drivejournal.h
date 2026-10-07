#pragma once
#include <QSaveFile>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QVariantMap>
#include <QVariantList>
#include <QDir>
#include <QStandardPaths>
#include <QUuid>

// Three-way state and durable outbox, partitioned by authenticated account.
// Version conflicts remain visible and require an explicit user decision.
class DriveJournal {
public:
    QString path;
    QVariantMap trees;
    QVariantList outbox;
    bool load(const QString &user) {
        path.clear(); trees.clear(); outbox.clear();
        if (QUuid(user).isNull()) return user.isEmpty();
        const auto dir=QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)+"/inge-drive/"+user;
        if (!QDir().mkpath(dir)) return false;
        path=dir+"/journal.json";
        QFile file(path);
        if (!file.exists()) return true;
        if (!file.open(QIODevice::ReadOnly)) return false;
        QJsonParseError error;
        const auto document=QJsonDocument::fromJson(file.readAll(),&error);
        if (error.error!=QJsonParseError::NoError || !document.isObject()) { path.clear(); return false; }
        const auto state=document.toVariant().toMap();
        if(state.value("schema").toInt()!=2) { path.clear(); return false; }
        trees=state.value("trees").toMap(); outbox=state.value("outbox").toList(); return true;
    }
    bool save() const {
        if(path.isEmpty()) return false;
        QSaveFile file(path);
        const auto bytes=QJsonDocument::fromVariant(QVariantMap{{"schema",2},{"trees",trees},{"outbox",outbox}}).toJson(QJsonDocument::Compact);
        return file.open(QIODevice::WriteOnly) && file.write(bytes)==bytes.size() && file.commit();
    }
    QVariantList local(const QString &key) const { return trees.value(key).toMap().value("local").toList(); }
    bool remember(const QString &key,const QVariantList &remote) {
        const auto previous=trees;
        trees[key]=QVariantMap{{"remote",remote},{"synced",remote},{"local",remote}};
        if (save()) return true;
        trees=previous; return false;
    }
    bool enqueue(const QVariantMap &operation,const QString &key,const QVariantList &visible) {
        const auto previous=trees;
        auto tree=trees.value(key).toMap(); tree["local"]=visible; trees[key]=tree;
        outbox.append(operation);
        if (save()) return true;
        outbox.removeLast(); trees=previous; return false;
    }
};
