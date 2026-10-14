#pragma once

#include "renditionfeatures.h"

#include <QJsonDocument>
#include <QSet>
#include <QString>
#include <QVariantMap>

// Puerto desacoplado para que, en el futuro, InGe IA solicite operaciones de
// Rendiciones. NO está conectado: ningún componente lo implementa ni lo
// registra, y no existe proveedor IA, clave ni endpoint asociado.
//
// Contrato: el asistente nunca escribe en Supabase ni en el almacén local. Sólo
// puede pedir comandos YA existentes de RenditionFlutterBridge::submit, que
// conservan outbox, request_id, CAS y los permisos efectivos del servidor
// (can_edit_content). Las escrituras exigen confirmación explícita del usuario.
struct RenditionAssistantRequest {
    QString requestId;
    QString operation;
    QVariantMap arguments;
    bool userConfirmed = false;
};

class RenditionAssistantPort
{
public:
    virtual ~RenditionAssistantPort() = default;
    virtual bool available() const = 0;
    virtual void request(const RenditionAssistantRequest &request) = 0;
};

namespace RenditionAssistantPolicy {

inline const QSet<QString> &readOperations()
{
    static const QSet<QString> operations{
        QStringLiteral("refresh"), QStringLiteral("select"),
        QStringLiteral("receivedList"), QStringLiteral("receivedQuery"),
        QStringLiteral("receivedNotes"), QStringLiteral("receivedActivity"),
        QStringLiteral("exchangeQuote")};
    return operations;
}

inline const QSet<QString> &writeOperations()
{
    static const QSet<QString> operations{
        QStringLiteral("create"), QStringLiteral("update"),
        QStringLiteral("saveExpense"), QStringLiteral("saveFinancial"),
        QStringLiteral("present")};
    return operations;
}

// Código de rechazo; vacío = permitido.
inline QString rejection(const RenditionAssistantRequest &request,
                         bool aiEnabled = RenditionFeatures::aiEnabled)
{
    if (!aiEnabled)
        return QString::fromLatin1(RenditionFeatures::aiDisabledCode);
    if (request.requestId.trimmed().isEmpty())
        return QStringLiteral("REQUEST_ID_REQUIRED");
    if (readOperations().contains(request.operation))
        return {};
    if (!writeOperations().contains(request.operation))
        return QStringLiteral("OPERATION_NOT_ALLOWED");
    if (!request.userConfirmed)
        return QStringLiteral("USER_CONFIRMATION_REQUIRED");
    return {};
}

// JSON para RenditionFlutterBridge::submit; vacío cuando se rechaza.
inline QString bridgeCommand(const RenditionAssistantRequest &request,
                             bool aiEnabled = RenditionFeatures::aiEnabled)
{
    if (!rejection(request, aiEnabled).isEmpty())
        return {};
    const QVariantMap command{{QStringLiteral("requestId"), request.requestId},
                              {QStringLiteral("operation"), request.operation},
                              {QStringLiteral("arguments"), request.arguments}};
    return QString::fromUtf8(QJsonDocument::fromVariant(command).toJson(QJsonDocument::Compact));
}

} // namespace RenditionAssistantPolicy
