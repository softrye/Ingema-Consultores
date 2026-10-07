// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include <QStringList>
#include <QVariantMap>
namespace NothingFiles {
bool inside(const QString &root, const QString &path, bool allowRoot = false);
bool validName(const QString &name);
QVariantMap item(const QString &path);
QVariantMap scan(const QString &root, const QString &folder, const QString &route, const QString &category);
QVariantMap operate(const QString &root, const QString &folder, const QString &op,
                    const QStringList &paths, const QString &argument);
}
