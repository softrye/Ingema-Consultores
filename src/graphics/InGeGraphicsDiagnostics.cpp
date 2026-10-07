#include "InGeGraphicsDiagnostics.h"

#include <QDebug>
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <QQuickWindow>

#ifdef Q_OS_ANDROID
#include <vulkan/vulkan.h>
#include <vector>
#endif

namespace {
#ifdef Q_OS_ANDROID
bool inspectAndroidVulkan(QString *gpuName)
{
    VkApplicationInfo appInfo{};
    appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    appInfo.pApplicationName = "InGe+";
    appInfo.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.pEngineName = "InGeGraphicsDiagnostics";
    appInfo.engineVersion = VK_MAKE_VERSION(1, 0, 0);
    appInfo.apiVersion = VK_API_VERSION_1_0;

    VkInstanceCreateInfo createInfo{};
    createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    createInfo.pApplicationInfo = &appInfo;

    VkInstance instance = VK_NULL_HANDLE;
    if (vkCreateInstance(&createInfo, nullptr, &instance) != VK_SUCCESS
        || instance == VK_NULL_HANDLE) {
        return false;
    }

    uint32_t count = 0;
    VkResult result = vkEnumeratePhysicalDevices(instance, &count, nullptr);
    if (result != VK_SUCCESS || count == 0) {
        vkDestroyInstance(instance, nullptr);
        return false;
    }

    std::vector<VkPhysicalDevice> devices(count);
    result = vkEnumeratePhysicalDevices(instance, &count, devices.data());
    if (result == VK_SUCCESS && count > 0 && gpuName && gpuName->isEmpty()) {
        VkPhysicalDeviceProperties properties{};
        vkGetPhysicalDeviceProperties(devices.front(), &properties);
        *gpuName = QString::fromUtf8(properties.deviceName);
    }

    vkDestroyInstance(instance, nullptr);
    return result == VK_SUCCESS && count > 0;
}
#endif

QString inspectOpenGlRenderer()
{
    QOpenGLContext *context = QOpenGLContext::currentContext();
    if (!context || !context->functions())
        return {};

    const GLubyte *renderer = context->functions()->glGetString(GL_RENDERER);
    return renderer ? QString::fromLatin1(reinterpret_cast<const char *>(renderer))
                    : QString();
}
}

InGeGraphicsDiagnostics::RuntimeSnapshot InGeGraphicsDiagnostics::inspect(QQuickWindow *window)
{
    RuntimeSnapshot snapshot;
    if (!window || !window->rendererInterface())
        return snapshot;

    QSGRendererInterface *renderer = window->rendererInterface();
    snapshot.graphicsApi = renderer->graphicsApi();
    snapshot.graphicsApiName = graphicsApiName(snapshot.graphicsApi);
    snapshot.qtRendererUsesVulkan = snapshot.graphicsApi == QSGRendererInterface::Vulkan;

    if (snapshot.graphicsApi == QSGRendererInterface::OpenGL)
        snapshot.gpuName = inspectOpenGlRenderer();

#ifdef Q_OS_ANDROID
    // "Vulkan available" means hardware/runtime capability, not that Qt Quick
    // selected Vulkan as its own scene graph backend. Flutter/Impeller and
    // the direct Earth host may use Vulkan while Qt Quick intentionally uses
    // OpenGL. Probe the Android Vulkan runtime independently.
    snapshot.vulkanAvailable = inspectAndroidVulkan(&snapshot.gpuName);

    if (snapshot.qtRendererUsesVulkan && snapshot.gpuName.isEmpty()) {
        void *resource = renderer->getResource(
            window, QSGRendererInterface::PhysicalDeviceResource);
        auto *physicalDevice = static_cast<VkPhysicalDevice *>(resource);
        if (physicalDevice && *physicalDevice != VK_NULL_HANDLE) {
            VkPhysicalDeviceProperties properties{};
            vkGetPhysicalDeviceProperties(*physicalDevice, &properties);
            snapshot.gpuName = QString::fromUtf8(properties.deviceName);
        }
    }
#else
    snapshot.vulkanAvailable = snapshot.qtRendererUsesVulkan;
#endif

    if (snapshot.gpuName.isEmpty())
        snapshot.gpuName = QStringLiteral("UNAVAILABLE");
    return snapshot;
}

QString InGeGraphicsDiagnostics::graphicsApiName(QSGRendererInterface::GraphicsApi api)
{
    switch (api) {
    case QSGRendererInterface::Vulkan:
        return QStringLiteral("Vulkan");
    case QSGRendererInterface::OpenGL:
        return QStringLiteral("OpenGL");
    case QSGRendererInterface::Direct3D11:
        return QStringLiteral("Direct3D 11");
    case QSGRendererInterface::Direct3D12:
        return QStringLiteral("Direct3D 12");
    case QSGRendererInterface::Metal:
        return QStringLiteral("Metal");
    case QSGRendererInterface::Software:
        return QStringLiteral("Software");
    case QSGRendererInterface::Null:
        return QStringLiteral("Null");
    case QSGRendererInterface::Unknown:
    default:
        return QStringLiteral("Unknown");
    }
}

void InGeGraphicsDiagnostics::logOnce(const RuntimeSnapshot &snapshot)
{
    static bool logged = false;
    if (logged)
        return;
    logged = true;

    qInfo().noquote()
        << "INGE_GRAPHICS\n"
        << "Qt Graphics API:" << snapshot.graphicsApiName << "\n"
        << "GPU:" << snapshot.gpuName << "\n"
        << "Qt renderer uses Vulkan:"
        << (snapshot.qtRendererUsesVulkan ? "YES" : "NO") << "\n"
        << "Vulkan hardware/runtime available:"
        << (snapshot.vulkanAvailable ? "YES" : "NO");
}
