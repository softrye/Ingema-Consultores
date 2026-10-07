#pragma once
#include <QString>

QString ensureUserScopedRoot(const QString& rootMaybeGlobal,
                             bool allowGlobalWhenNoSession = false,
                             bool ensureResourcesFolder = true);

void ensureDefaultResourcesIn(const QString& userRoot,
                              const QString& resourcesFolderName = "Recursos",
                              const QString& qrcDefaultsDir = ":/default_resources");
