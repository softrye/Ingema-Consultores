#include "renditionuicontroller.h"

#include "renditioncontract.h"
#include "renditionfeatures.h"
#include "renditionmoney.h"
#include "renditionvalidation.h"

#include <QDate>
#include <QFileInfo>
#include <QJsonDocument>
#include <QLocale>
#include <QMimeDatabase>
#include <QUuid>

namespace {
QString text(const QVariantMap &row, const char *camel, const char *snake = nullptr)
{
    const QVariant direct = row.value(QLatin1String(camel));
    if (direct.isValid() && !direct.isNull() && !direct.toString().isEmpty())
        return direct.toString();
    return snake ? row.value(QLatin1String(snake)).toString() : QString();
}

// Valor numérico de un mapa JSON como texto decimal exacto (nunca 0 por ausencia).
QString decimalText(const QVariant &value)
{
    if (!value.isValid() || value.isNull())
        return {};
    return value.toString().trimmed().replace(QLatin1Char(','), QLatin1Char('.'));
}

QString groupedCents(qint64 cents)
{
    const bool negative = cents < 0;
    const qint64 magnitude = negative ? -cents : cents;
    QString integer = QString::number(magnitude / 100);
    for (int i = integer.size() - 3; i > 0; i -= 3)
        integer.insert(i, QLatin1Char(','));
    return (negative ? QStringLiteral("-") : QString()) + integer + QLatin1Char('.')
        + QStringLiteral("%1").arg(magnitude % 100, 2, 10, QLatin1Char('0'));
}

QString currencyPrefix(const QString &currency)
{
    return currency == QLatin1String("USD") ? QStringLiteral("US$ ") : QStringLiteral("S/ ");
}
} // namespace

RenditionUiController::RenditionUiController(QObject *bridge, QObject *parent)
    : QObject(parent), m_bridge(bridge)
{
    if (m_bridge)
        connect(m_bridge, SIGNAL(eventReady(QString)), this, SLOT(handleEvent(QString)));
}

QStringList RenditionUiController::pendingKeys() const
{
    QStringList keys;
    for (const auto &pending : m_pending)
        if (!pending.key.isEmpty() && !keys.contains(pending.key))
            keys.append(pending.key);
    return keys;
}

bool RenditionUiController::aiEnabled() const { return RenditionFeatures::aiEnabled; }

QString RenditionUiController::send(const QString &operation, const QVariantMap &arguments,
                                    const QString &key)
{
    if (!m_bridge || operation.isEmpty() || (!key.isEmpty() && isPending(key)))
        return {};
    const QString requestId = newId();
    m_pending.insert(requestId, {operation, key});
    const QVariantMap command{{QStringLiteral("requestId"), requestId},
                              {QStringLiteral("operation"), operation},
                              {QStringLiteral("arguments"), arguments}};
    const QString json = QString::fromUtf8(
        QJsonDocument::fromVariant(command).toJson(QJsonDocument::Compact));
    if (!QMetaObject::invokeMethod(m_bridge, "submit", Q_ARG(QString, json))) {
        m_pending.remove(requestId);
        return {};
    }
    if (!key.isEmpty())
        emit pendingChanged();
    return requestId;
}

bool RenditionUiController::isPending(const QString &key) const
{
    for (const auto &pending : m_pending)
        if (pending.key == key)
            return true;
    return false;
}

QString RenditionUiController::newId() const
{
    return QUuid::createUuid().toString(QUuid::WithoutBraces);
}

void RenditionUiController::handleEvent(const QString &eventJson)
{
    const QVariantMap event = QJsonDocument::fromJson(eventJson.toUtf8()).toVariant().toMap();
    const QString type = event.value(QStringLiteral("type")).toString();
    if (type == QLatin1String("state")) {
        m_state = event;
        m_ready = true;
        emit stateChanged();
        return;
    }
    if (type == QLatin1String("commandResult")) {
        const QString requestId = event.value(QStringLiteral("requestId")).toString();
        const bool ok = event.value(QStringLiteral("ok")).toBool();
        const auto found = m_pending.constFind(requestId);
        if (requestId.isEmpty() || found == m_pending.cend()) {
            // Respuesta sin solicitud viva: nunca se entrega a otro formulario.
            if (!ok)
                emit bridgeError(event.value(QStringLiteral("code")).toString(),
                                 event.value(QStringLiteral("message")).toString());
            return;
        }
        const Pending pending = found.value();
        m_pending.erase(found);
        if (!pending.key.isEmpty())
            emit pendingChanged();
        emit finished(requestId, pending.operation, pending.key, ok,
                      event.value(QStringLiteral("result")).toMap(),
                      event.value(QStringLiteral("code")).toString(),
                      event.value(QStringLiteral("message")).toString());
        return;
    }
    if (type == QLatin1String("receivedReset")) {
        // Cambio de cuenta: el bridge ya respondió ACCOUNT_CHANGED a lo pendiente.
        m_state.clear();
        m_ready = false;
        emit stateChanged();
    }
    emit bridgeEvent(type, event);
}

bool RenditionUiController::canEdit(const QVariantMap &rendition) const
{
    return !rendition.isEmpty() && RenditionContract::canEditWorkingCopy(rendition);
}

QString RenditionUiController::headerError(const QVariantMap &header) const
{
    return RenditionValidation::header(
        header.value(QStringLiteral("periodStart")).toString(),
        header.value(QStringLiteral("periodEnd")).toString(),
        header.value(QStringLiteral("projectIds")).toList(),
        header.value(QStringLiteral("primaryProjectId")).toString(),
        header.value(QStringLiteral("documentParentNodeId")).toString(),
        header.value(QStringLiteral("spaceId")).toString());
}

QString RenditionUiController::expenseError(const QVariantMap &rendition,
                                            const QVariantMap &expense) const
{
    QVariantMap row = expense;
    row.insert(QStringLiteral("amount"), decimalText(expense.value(QStringLiteral("amount"))));
    return RenditionValidation::expense(rendition, row);
}

QString RenditionUiController::amountError(const QString &amount) const
{
    const auto cents = RenditionMoney::cents(decimalText(amount));
    if (!cents)
        return QStringLiteral("Ingresa un importe numérico (por ejemplo 125.50).");
    if (*cents <= 0)
        return QStringLiteral("El importe debe ser mayor que cero.");
    if (*cents > 99999999999999LL)
        return QStringLiteral("El importe supera el límite admitido.");
    return {};
}

QString RenditionUiController::formatMoney(const QVariant &amount, const QString &currency) const
{
    const auto cents = RenditionMoney::cents(decimalText(amount));
    return cents ? currencyPrefix(currency) + groupedCents(*cents) : QStringLiteral("—");
}

QString RenditionUiController::formatCents(const QVariant &cents, const QString &currency) const
{
    if (!cents.isValid() || cents.isNull())
        return QStringLiteral("—");
    return currencyPrefix(currency) + groupedCents(cents.toLongLong());
}

QVariantMap RenditionUiController::totals(const QVariantList &expenses) const
{
    qint64 pen = 0, usd = 0, validatedPen = 0, validatedUsd = 0;
    int count = 0, pending = 0, observed = 0, validated = 0;
    for (const auto &value : expenses) {
        const auto row = value.toMap();
        if (row.value(QStringLiteral("archived")).toBool())
            continue;
        const auto cents = RenditionMoney::cents(decimalText(row.value(QStringLiteral("amount"))));
        if (!cents)
            return {{QStringLiteral("error"), QStringLiteral("INVALID_AMOUNT")}};
        ++count;
        const bool isUsd = text(row, "currencyCode", "currency_code") == QLatin1String("USD");
        (isUsd ? usd : pen) += *cents;
        const QString review = text(row, "reviewStatus", "review_status").toUpper();
        if (review == QLatin1String("VALIDADO") || review == QLatin1String("APROBADO")) {
            ++validated;
            (isUsd ? validatedUsd : validatedPen) += *cents;
        } else if (review == QLatin1String("OBSERVADO")) {
            ++observed;
        } else {
            ++pending;
        }
    }
    return {{QStringLiteral("count"), count}, {QStringLiteral("pending"), pending},
            {QStringLiteral("observed"), observed}, {QStringLiteral("validated"), validated},
            {QStringLiteral("penCents"), pen}, {QStringLiteral("usdCents"), usd},
            {QStringLiteral("validatedPenCents"), validatedPen},
            {QStringLiteral("validatedUsdCents"), validatedUsd}};
}

QVariantMap RenditionUiController::fundBalance(const QVariantMap &rendition) const
{
    const QVariantMap funding = rendition.value(QStringLiteral("funding")).toMap();
    if (funding.value(QStringLiteral("enabled")).toBool() != true)
        return {{QStringLiteral("enabled"), false}};
    const QVariantMap rate = rendition.value(QStringLiteral("exchangeRate")).toMap();
    const auto fundPen = RenditionMoney::cents(decimalText(funding.value(QStringLiteral("pen"))));
    const auto fundUsd = RenditionMoney::cents(decimalText(funding.value(QStringLiteral("usd"))));
    const auto spentPen = RenditionMoney::cents(decimalText(rendition.value(QStringLiteral("totalPen"), 0)));
    const auto spentUsd = RenditionMoney::cents(decimalText(rendition.value(QStringLiteral("totalUsd"), 0)));
    if (!fundPen || !fundUsd || !spentPen || !spentUsd)
        return {{QStringLiteral("enabled"), true}, {QStringLiteral("error"), QStringLiteral("INVALID_AMOUNT")}};
    const QString rateText = decimalText(rate.value(QStringLiteral("rate")));
    std::optional<qint64> micro;
    if (!rateText.isEmpty()) {
        micro = RenditionMoney::scaled(rateText, 6);
        if (!micro || *micro <= 0)
            return {{QStringLiteral("enabled"), true}, {QStringLiteral("error"), QStringLiteral("INVALID_EXCHANGE_RATE")}};
    }
    QVariantMap result{{QStringLiteral("enabled"), true},
                       {QStringLiteral("fundPenCents"), *fundPen}, {QStringLiteral("fundUsdCents"), *fundUsd},
                       {QStringLiteral("hasRate"), micro.has_value()}};
#if defined(__SIZEOF_INT128__)
    const auto balance = RenditionMoney::commonFund(*fundPen, *fundUsd, *spentPen, *spentUsd, micro);
    // Saldo no determinable (p. ej. sin tipo de cambio con saldos mixtos): null, nunca 0.
    result.insert(QStringLiteral("penCents"), balance.pen ? QVariant(*balance.pen) : QVariant());
    result.insert(QStringLiteral("usdCents"), balance.usd ? QVariant(*balance.usd) : QVariant());
#endif
    return result;
}

QString RenditionUiController::fundingError(const QVariantMap &values) const
{
    if (values.value(QStringLiteral("enabled")).toBool() != true)
        return {};
    for (const char *currency : {"pen", "usd"}) {
        const auto cents = RenditionMoney::cents(decimalText(values.value(QLatin1String(currency))));
        if (!cents)
            return QStringLiteral("Fondo %1 no válido.").arg(QString::fromLatin1(currency).toUpper());
        if (*cents < 0)
            return QStringLiteral("El fondo no puede ser negativo.");
    }
    return {};
}

QString RenditionUiController::rateError(const QString &rate) const
{
    const auto micro = RenditionMoney::scaled(decimalText(rate), 6);
    if (!micro)
        return QStringLiteral("Tipo de cambio no válido.");
    if (*micro <= 0 || *micro > 999999000000LL)
        return QStringLiteral("Tipo de cambio fuera de rango.");
    return {};
}

QVariantList RenditionUiController::catalog(const QString &kind) const
{
    QVariantList result;
    const QString wanted = kind.toUpper();
    for (const auto &value : m_state.value(QStringLiteral("catalogs")).toList()) {
        const auto row = value.toMap();
        QString type = text(row, "catalogType", "catalog_type");
        if (type.isEmpty())
            type = row.value(QStringLiteral("type")).toString();
        if (type.toUpper().contains(wanted))
            result.append(row);
    }
    return result;
}

QVariantMap RenditionUiController::project(const QString &id) const
{
    for (const auto &value : m_state.value(QStringLiteral("projects")).toList()) {
        const auto row = value.toMap();
        if (text(row, "id", "project_id") == id)
            return row;
    }
    return {};
}

QString RenditionUiController::projectLabel(const QString &id) const
{
    const auto row = project(id);
    if (row.isEmpty())
        return id.isEmpty() ? QStringLiteral("Sin proyecto") : QStringLiteral("Proyecto no disponible");
    const QString code = text(row, "code", "project_code");
    const QString name = text(row, "name", "project_name");
    if (!code.isEmpty() && !name.isEmpty())
        return code + QStringLiteral(" · ") + name;
    return name.isEmpty() ? code : name;
}

QVariantList RenditionUiController::filterRenditions(const QString &query, const QString &status,
                                                     const QString &projectId) const
{
    QVariantList result;
    const QString needle = query.trimmed().toCaseFolded();
    for (const auto &value : m_state.value(QStringLiteral("renditions")).toList()) {
        const auto row = value.toMap();
        if (!status.isEmpty() && row.value(QStringLiteral("status")).toString() != status)
            continue;
        if (!projectId.isEmpty() && !row.value(QStringLiteral("projectIds")).toList().contains(projectId))
            continue;
        if (!needle.isEmpty()) {
            const QString haystack = QStringList{
                text(row, "visibleCode", "visible_code"), row.value(QStringLiteral("status")).toString(),
                row.value(QStringLiteral("periodStart")).toString(), row.value(QStringLiteral("periodEnd")).toString(),
                projectLabel(row.value(QStringLiteral("primaryProjectId")).toString()),
                text(row, "primaryProjectName", "primary_project_name")}.join(QLatin1Char(' ')).toCaseFolded();
            if (!haystack.contains(needle))
                continue;
        }
        result.append(row);
    }
    return result;
}

QString RenditionUiController::syncLabel(const QString &syncState) const
{
    static const QHash<QString, QString> labels{
        {QStringLiteral("LOCAL_ONLY"), QStringLiteral("Guardado local")},
        {QStringLiteral("PENDING_CREATE"), QStringLiteral("Pendiente de sincronizar")},
        {QStringLiteral("PENDING_UPDATE"), QStringLiteral("Pendiente de sincronizar")},
        {QStringLiteral("SYNCING"), QStringLiteral("Sincronizando")},
        {QStringLiteral("SYNCED"), QStringLiteral("Sincronizado con el servidor")},
        {QStringLiteral("CONFLICT"), QStringLiteral("Conflicto")},
        {QStringLiteral("NEEDS_RECONCILIATION"), QStringLiteral("Por confirmar con el servidor")},
        {QStringLiteral("ERROR"), QStringLiteral("Error de sincronización")}};
    return labels.value(syncState.toUpper(), syncState.isEmpty() ? QStringLiteral("Sin estado") : syncState);
}

QString RenditionUiController::statusLabel(const QString &status) const
{
    static const QHash<QString, QString> labels{
        {QStringLiteral("BORRADOR"), QStringLiteral("Borrador")},
        {QStringLiteral("OBSERVADO"), QStringLiteral("Observada")},
        {QStringLiteral("EN_REVISION"), QStringLiteral("En revisión")},
        {QStringLiteral("APROBADO"), QStringLiteral("Aprobada")},
        {QStringLiteral("PRESENTADA"), QStringLiteral("Presentada")}};
    return labels.value(status.toUpper(), status);
}

QString RenditionUiController::errorText(const QString &code, const QString &message) const
{
    static const QHash<QString, QString> known{
        {QStringLiteral("QUOTE_ORIGIN_NOT_CONFIGURED"),
         QStringLiteral("La cotización automática BCRP/SBS no está configurada en este equipo. "
                        "Registra el tipo de cambio manualmente; se conserva el valor guardado.")},
        {QStringLiteral("AI_DISABLED"),
         QStringLiteral("El análisis automático está desactivado. Completa los campos manualmente.")},
        {QStringLiteral("ACCOUNT_CHANGED"), QStringLiteral("La cuenta cambió; vuelve a abrir la consulta.")}};
    if (known.contains(code))
        return known.value(code);
    const QString upper = code.toUpper();
    if (upper.contains(QStringLiteral("NETWORK")) || upper.contains(QStringLiteral("TIMEOUT")))
        return QStringLiteral("Sin conexión con el servidor. Los cambios quedan guardados en el equipo y se reintentarán.");
    if (upper.contains(QStringLiteral("401")) || upper.contains(QStringLiteral("AUTH")))
        return QStringLiteral("La sesión expiró. Vuelve a iniciar sesión para sincronizar.");
    if (upper.contains(QStringLiteral("403")) || upper.contains(QStringLiteral("PERMISSION"))
        || upper.contains(QStringLiteral("FORBIDDEN")))
        return QStringLiteral("No tienes permiso para esta operación.");
    if (!message.trimmed().isEmpty())
        return message.trimmed();
    return code.isEmpty() ? QStringLiteral("No se pudo completar la operación.") : code;
}

QVariantMap RenditionUiController::describeLocalFile(const QUrl &url) const
{
    const QString path = url.isLocalFile() ? url.toLocalFile() : url.toString();
    const QFileInfo info(path);
    QString name = info.fileName();
    if (name.isEmpty() || name.contains(QLatin1Char('%')))
        name = QUrl::fromPercentEncoding(url.fileName().toUtf8());
    const QMimeDatabase mimes;
    QString mime = mimes.mimeTypeForFile(path).name();
    if (mime == QLatin1String("application/octet-stream") && !name.isEmpty())
        mime = mimes.mimeTypeForFile(name, QMimeDatabase::MatchExtension).name();
    const QStringList allowed{QStringLiteral("image/jpeg"), QStringLiteral("image/png"),
                              QStringLiteral("image/webp"), QStringLiteral("application/pdf")};
    QString error;
    if (!info.exists() || info.size() <= 0)
        error = QStringLiteral("No se pudo leer el archivo seleccionado.");
    else if (info.size() > 20LL * 1024LL * 1024LL)
        error = QStringLiteral("El sustento supera 20 MiB.");
    else if (!allowed.contains(mime))
        error = QStringLiteral("Formato no admitido: usa JPG, PNG, WEBP o PDF.");
    return {{QStringLiteral("localUri"), url.isLocalFile() ? path : url.toString()},
            {QStringLiteral("fileName"), name}, {QStringLiteral("mimeType"), mime},
            {QStringLiteral("sizeBytes"), info.exists() ? info.size() : 0},
            {QStringLiteral("error"), error}};
}

QString RenditionUiController::today() const
{
    return QDate::currentDate().toString(Qt::ISODate);
}

bool RenditionUiController::validDate(const QString &value) const
{
    return RenditionValidation::date(value);
}
