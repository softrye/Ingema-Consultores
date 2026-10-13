#pragma once
#include <QApplication>
#include <QWidget>
#include <QColor>

namespace IngeTheme {

void apply(QApplication& app);
QString qss();

// Llamable manualmente (si quieres) y usado por el auto-polish:
void polishDialog(QWidget* w);

#ifdef Q_OS_WIN
bool setNativeTitleBarColors(QWidget* w,
                             const QColor& captionColor = QColor("#003A5E"),
                             const QColor& textColor    = QColor("#FFFFFF"));
#endif

} // namespace IngeTheme
