#include "fsutil.h"
#include <QDir>
#include <QFileInfo>
#include <QUrl>

QString FsUtil::clean(const QString& p) const {
    QString s = p.trimmed();
    if (s.startsWith("file:", Qt::CaseInsensitive)) {
        QUrl u(s);
        if (u.isValid() && u.isLocalFile())
            s = u.toLocalFile();
    }
    s = QDir::fromNativeSeparators(s);
    return QDir::cleanPath(s);
}

bool FsUtil::mkpath(const QString& absDir) const {
    const QString p = clean(absDir);
    if (p.isEmpty()) return false;
    return QDir().mkpath(p);
}

bool FsUtil::exists(const QString& absPath) const {
    return QFileInfo::exists(clean(absPath));
}

bool FsUtil::isDir(const QString& absPath) const {
    QFileInfo fi(clean(absPath));
    return fi.exists() && fi.isDir();
}

QString FsUtil::join(const QString& a, const QString& b) const {
    QDir d(clean(a));
    return QDir::cleanPath(d.filePath(b));
}
