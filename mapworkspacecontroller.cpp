#include "mapworkspacecontroller.h"

#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

namespace {

QString firstNonEmpty(const QStringList &values)
{
    for (const QString &value : values) {
        const QString trimmed = value.trimmed();
        if (!trimmed.isEmpty())
            return trimmed;
    }
    return {};
}

QString environmentValue(const char *name)
{
    return QString::fromUtf8(qgetenv(name)).trimmed();
}

} // namespace

MapWorkspaceController::MapWorkspaceController(QObject *parent)
    : QObject(parent)
{
    const QString configRoot = QStandardPaths::writableLocation(
        QStandardPaths::AppConfigLocation);
    m_configurationPath = QDir(configRoot).filePath(
        QStringLiteral("map-v2.json"));
    m_workspaceHtml = composeWorkspaceHtml();
}

QString MapWorkspaceController::workspaceHtml() const
{
    return m_workspaceHtml;
}

QString MapWorkspaceController::configurationPath() const
{
    return m_configurationPath;
}

QVariantMap MapWorkspaceController::runtimeConfiguration() const
{
    const QVariantMap external = readExternalConfiguration();

    // No se registra ninguno de estos valores. En Android la clave debe estar
    // restringida a com.ingema.ingeplus + SHA-1 y exclusivamente a las APIs
    // requeridas. El archivo externo vive fuera del repositorio.
    const QString apiKey = firstNonEmpty({
        environmentValue("INGE_GOOGLE_MAPS_API_KEY"),
        external.value(QStringLiteral("googleMapsApiKey")).toString()
    });
    const QString packageName = firstNonEmpty({
        environmentValue("INGE_ANDROID_PACKAGE"),
        external.value(QStringLiteral("androidPackage")).toString(),
        QStringLiteral("com.ingema.ingeplus")
    });
    const QString certificateSha1 = firstNonEmpty({
        environmentValue("INGE_ANDROID_CERT_SHA1"),
        external.value(QStringLiteral("androidCertSha1")).toString()
    }).remove(QLatin1Char(':')).toUpper();
    const QString cesiumBaseUrl = firstNonEmpty({
        environmentValue("INGE_CESIUM_BASE_URL"),
        external.value(QStringLiteral("cesiumBaseUrl")).toString(),
        QStringLiteral("https://cesium.com/downloads/cesiumjs/releases/1.143/Build/Cesium/")
    });

    QVariantMap result;
    result.insert(QStringLiteral("configured"), !apiKey.isEmpty());
    result.insert(QStringLiteral("googleMapsApiKey"), apiKey);
    result.insert(QStringLiteral("androidPackage"), packageName);
    result.insert(QStringLiteral("androidCertSha1"), certificateSha1);
    result.insert(QStringLiteral("cesiumBaseUrl"), cesiumBaseUrl);
    result.insert(QStringLiteral("language"),
                  firstNonEmpty({external.value(QStringLiteral("language")).toString(),
                                 QStringLiteral("es-PE")}));
    result.insert(QStringLiteral("region"),
                  firstNonEmpty({external.value(QStringLiteral("region")).toString(),
                                 QStringLiteral("PE")}));
    return result;
}

QString MapWorkspaceController::composeWorkspaceHtml() const
{
    const auto readUtf8Resource = [](const QString &path) -> QString {
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly))
            return {};
        return QString::fromUtf8(file.readAll());
    };

    QString html = readUtf8Resource(
        QStringLiteral(":/InGe/Mobile/mapv2/index.html"));
    const QString css = readUtf8Resource(
        QStringLiteral(":/InGe/Mobile/mapv2/workspace.css"));
    QString javascript = readUtf8Resource(
        QStringLiteral(":/InGe/Mobile/mapv2/workspace.js"));
    if (html.isEmpty() || css.isEmpty() || javascript.isEmpty())
        return {};

    // Android WebView rechaza en algunos dispositivos el file:// privado y no
    // navega a qrc:/. Se conservan los tres fuentes separados, pero se componen
    // en memoria para WebView::loadHtml(), sin habilitar acceso a archivos.
    javascript.replace(QStringLiteral("</script>"),
                       QStringLiteral("<\\/script>"),
                       Qt::CaseInsensitive);
    html.replace(QStringLiteral("<link rel=\"stylesheet\" href=\"workspace.css\">"),
                 QStringLiteral("<style id=\"inge-workspace-style\">\n")
                     + css + QStringLiteral("\n</style>"));
    html.replace(QStringLiteral("<script src=\"workspace.js\"></script>"),
                 QStringLiteral("<script id=\"inge-workspace-script\">\n")
                     + javascript + QStringLiteral("\n</script>"));
    return html;
}

QVariantMap MapWorkspaceController::readExternalConfiguration() const
{
    QFile file(m_configurationPath);
    if (!file.open(QIODevice::ReadOnly))
        return {};

    QJsonParseError parseError;
    const QJsonDocument document = QJsonDocument::fromJson(
        file.readAll(), &parseError);
    if (parseError.error != QJsonParseError::NoError || !document.isObject())
        return {};
    return document.object().toVariantMap();
}
