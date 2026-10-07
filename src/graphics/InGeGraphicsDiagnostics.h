#pragma once

#include <QString>
#include <QtQuick/QSGRendererInterface>

class QQuickWindow;

class InGeGraphicsDiagnostics final
{
public:
    struct RuntimeSnapshot {
        QSGRendererInterface::GraphicsApi graphicsApi = QSGRendererInterface::Unknown;
        QString graphicsApiName;
        QString gpuName;
        bool vulkanAvailable = false;
        bool qtRendererUsesVulkan = false;
    };

    static RuntimeSnapshot inspect(QQuickWindow *window);
    static QString graphicsApiName(QSGRendererInterface::GraphicsApi api);
    static void logOnce(const RuntimeSnapshot &snapshot);
};
