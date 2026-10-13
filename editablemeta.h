#pragma once
#include <QString>

QString loadExcelTitleFromEditableMeta(const QString& ctx);
bool saveExcelTitleToEditableMeta(const QString& ctx, const QString& title);

// --- LOGOS (por carpeta editable) ---
QString loadLogoMtcPathFromEditableMeta(const QString& ctx);
bool saveLogoMtcPathToEditableMeta(const QString& ctx, const QString& relPath);

QString loadLogoProyectoPathFromEditableMeta(const QString& ctx);
bool saveLogoProyectoPathToEditableMeta(const QString& ctx, const QString& relPath);
