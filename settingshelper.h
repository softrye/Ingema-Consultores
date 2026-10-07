#pragma once

#include <QSettings>
#include <QString>

inline QSettings appSettings()
{
    return QSettings(QStringLiteral("InGePlus"), QStringLiteral("InGePlusMobile"));
}
