#pragma once
#include <QObject>
#include <QString>

class FsUtil : public QObject {
    Q_OBJECT
public:
    explicit FsUtil(QObject* parent=nullptr) : QObject(parent) {}

    Q_INVOKABLE bool mkpath(const QString& absDir) const;
    Q_INVOKABLE bool exists(const QString& absPath) const;
    Q_INVOKABLE bool isDir(const QString& absPath) const;
    Q_INVOKABLE QString join(const QString& a, const QString& b) const;
    // FsUtil.h
    Q_INVOKABLE QString clean(const QString& p) const;
};
