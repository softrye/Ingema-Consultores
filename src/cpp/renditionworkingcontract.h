#pragma once
// Contrato Working Document de Rendiciones (rendition_cloud_working_rows_v01).
// Fuente canónica: supabase/migrations/20261012214152_rendition_cloud_working_rows_v01.sql
// y src/lib/renditions/renditionWorkingService.ts (Web, SHA ab1e1aba, PR #6).
//
// Sólo funciones puras: nombres RPC, argumentos y validación idéntica a la del
// servidor, normalización de respuestas y clasificación de errores. No hace red,
// no guarda nada y no decide autorización: la autoridad es siempre el servidor.
// Disponible en InGePlus-Dev (verificado por catálogo 16/10/2026); un entorno sin
// el contrato responde PGRST202 y se clasifica como CONTRACT_REQUIRED (sin escrituras).
#include <QHash>
#include <QJsonDocument>
#include <QRegularExpression>
#include <QStringList>
#include <QUuid>
#include <QVariantList>
#include <QVariantMap>

namespace RenditionWorkingContract {

// RPC exactas (no inventar otras).
inline constexpr const char *GetSheet = "get_rendition_working_sheet_v01";
inline constexpr const char *ListRows = "list_rendition_working_rows_v01";
inline constexpr const char *SaveRow = "save_rendition_working_row_v01";
inline constexpr const char *ArchiveRow = "archive_rendition_working_row_v01";
inline constexpr const char *ReserveFile = "reserve_rendition_working_file_v01";
inline constexpr const char *ConfirmFile = "confirm_rendition_working_file_v01";
inline constexpr const char *GetFile = "get_rendition_working_file_v01";
inline constexpr const char *PromoteRow = "promote_rendition_working_row_v01";

inline constexpr qint64 MaxPayloadBytes = 262144;
inline constexpr qint64 MaxFileBytes = 20971520;
inline constexpr int MaxSources = 100;
inline constexpr int MaxFieldLength = 8000;

// Campos del formulario: los 13 deben existir como texto en form y baseline.
inline const QStringList &formFields()
{
    static const QStringList fields{
        QStringLiteral("projectId"), QStringLiteral("expenseDate"), QStringLiteral("categoryCode"),
        QStringLiteral("concept"), QStringLiteral("beneficiary"), QStringLiteral("paymentMethodCode"),
        QStringLiteral("paymentMethodDetail"), QStringLiteral("supportTypeCode"),
        QStringLiteral("supportNumber"), QStringLiteral("supportDetail"),
        QStringLiteral("currencyCode"), QStringLiteral("amount"), QStringLiteral("justification")};
    return fields;
}

// UUID canónico en minúsculas (el SQL usa ^[0-9a-f]{8}-...$).
inline bool canonicalUuid(const QVariant &value)
{
    static const QRegularExpression pattern(QStringLiteral(
        "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"));
    return value.typeId() == QMetaType::QString && pattern.match(value.toString()).hasMatch();
}
inline QString newUuid() { return QUuid::createUuid().toString(QUuid::WithoutBraces).toLower(); }

inline bool isText(const QVariant &value) { return value.typeId() == QMetaType::QString; }
inline bool isNumber(const QVariant &value)
{
    switch (value.typeId()) {
    case QMetaType::Int: case QMetaType::UInt: case QMetaType::LongLong:
    case QMetaType::ULongLong: case QMetaType::Double:
        return true;
    default:
        return false;
    }
}

// Un formulario completo en texto (vacío permitido: la fila puede estar incompleta).
inline QVariantMap formFrom(const QVariantMap &source)
{
    QVariantMap form;
    for (const QString &field : formFields())
        form.insert(field, source.value(field).toString());
    return form;
}

inline QString validateForm(const QVariant &value)
{
    if (value.typeId() != QMetaType::QVariantMap) return QStringLiteral("form");
    const QVariantMap form = value.toMap();
    for (auto it = form.cbegin(); it != form.cend(); ++it)
        if (!formFields().contains(it.key())) return QStringLiteral("form.") + it.key();
    for (const QString &field : formFields()) {
        const QVariant v = form.value(field);
        if (!isText(v)) return QStringLiteral("form.") + field;
        if (v.toString().size() > MaxFieldLength) return QStringLiteral("form.") + field;
    }
    return {};
}

// Metadatos de un sustento: nunca URLs, rutas ni bytes. uploadRequestId = id del archivo.
inline QString validateSource(const QVariant &value)
{
    static const QStringList keys{QStringLiteral("id"), QStringLiteral("name"), QStringLiteral("size"),
        QStringLiteral("lastModified"), QStringLiteral("type"), QStringLiteral("uploadRequestId"),
        QStringLiteral("contentHash")};
    static const QRegularExpression hash(QStringLiteral("^[a-f0-9]{64}$"));
    if (value.typeId() != QMetaType::QVariantMap) return QStringLiteral("source");
    const QVariantMap s = value.toMap();
    for (auto it = s.cbegin(); it != s.cend(); ++it)
        if (!keys.contains(it.key())) return QStringLiteral("source.") + it.key();
    const QString id = s.value(QStringLiteral("id")).toString();
    const QString name = s.value(QStringLiteral("name")).toString();
    if (!isText(s.value(QStringLiteral("id"))) || id.size() < 1 || id.size() > 160) return QStringLiteral("source.id");
    if (!isText(s.value(QStringLiteral("name"))) || name.size() < 1 || name.size() > 255) return QStringLiteral("source.name");
    if (!isNumber(s.value(QStringLiteral("size")))) return QStringLiteral("source.size");
    if (!isNumber(s.value(QStringLiteral("lastModified")))) return QStringLiteral("source.lastModified");
    if (!isText(s.value(QStringLiteral("type")))) return QStringLiteral("source.type");
    if (!canonicalUuid(s.value(QStringLiteral("uploadRequestId")))) return QStringLiteral("source.uploadRequestId");
    if (s.contains(QStringLiteral("contentHash")) && !hash.match(s.value(QStringLiteral("contentHash")).toString()).hasMatch())
        return QStringLiteral("source.contentHash");
    return {};
}

// Réplica de las comprobaciones de save_rendition_working_row_v01. Vacío = válido.
inline QString validatePayload(const QVariantMap &payload)
{
    static const QStringList keys{QStringLiteral("form"), QStringLiteral("baseline"),
        QStringLiteral("sources"), QStringLiteral("proposalId"), QStringLiteral("requestId")};
    for (auto it = payload.cbegin(); it != payload.cend(); ++it)
        if (!keys.contains(it.key())) return QStringLiteral("payload.") + it.key();
    if (QJsonDocument::fromVariant(payload).toJson(QJsonDocument::Compact).size() > MaxPayloadBytes)
        return QStringLiteral("payload.size");
    if (!canonicalUuid(payload.value(QStringLiteral("requestId")))) return QStringLiteral("payload.requestId");
    QString error = validateForm(payload.value(QStringLiteral("form")));
    if (!error.isEmpty()) return error;
    error = validateForm(payload.value(QStringLiteral("baseline")));
    if (!error.isEmpty()) return error.replace(0, 4, QStringLiteral("baseline"));
    const QVariant sources = payload.value(QStringLiteral("sources"));
    if (sources.typeId() != QMetaType::QVariantList || sources.toList().size() > MaxSources)
        return QStringLiteral("payload.sources");
    for (const QVariant &source : sources.toList()) {
        error = validateSource(source);
        if (!error.isEmpty()) return error;
    }
    return {};
}

// requestId del payload = identidad financiera del gasto (create_my_rendition_expense_v02):
// se genera una vez por fila y nunca cambia, para que la promoción no duplique gastos.
inline QVariantMap payload(const QVariantMap &form, const QVariantMap &baseline,
                           const QVariantList &sources, const QString &expenseRequestId,
                           const QString &proposalId = {})
{
    return {{QStringLiteral("form"), formFrom(form)},
            {QStringLiteral("baseline"), formFrom(baseline)},
            {QStringLiteral("sources"), sources},
            {QStringLiteral("proposalId"), proposalId.isEmpty() ? QVariant() : QVariant(proposalId)},
            {QStringLiteral("requestId"), expenseRequestId}};
}

inline QVariant nullableUuid(const QString &value)
{
    return value.isEmpty() ? QVariant() : QVariant(value);
}
inline QVariant nullableVersion(qint64 value)
{
    return value > 0 ? QVariant(value) : QVariant();
}

// p_expected_version: 0 crea la fila; >0 exige la versión actual (CAS).
// p_request_id: identidad del INTENTO de guardado (estable entre reintentos, ver IntentLedger).
inline QVariantMap saveArguments(const QString &renditionId, const QString &workingId,
                                 qint64 expectedVersion, const QString &saveRequestId,
                                 const QVariantMap &payload, const QString &expenseId = {},
                                 qint64 expenseRowVersion = 0)
{
    return {{QStringLiteral("p_rendition_id"), renditionId},
            {QStringLiteral("p_working_id"), workingId},
            {QStringLiteral("p_expected_version"), expectedVersion},
            {QStringLiteral("p_request_id"), saveRequestId},
            {QStringLiteral("p_payload"), payload},
            {QStringLiteral("p_expense_id"), nullableUuid(expenseId)},
            {QStringLiteral("p_expense_row_version"), expenseId.isEmpty() ? QVariant() : QVariant(expenseRowVersion)}};
}
inline QString validateSave(const QVariantMap &args)
{
    if (!canonicalUuid(args.value(QStringLiteral("p_rendition_id")))) return QStringLiteral("p_rendition_id");
    if (!canonicalUuid(args.value(QStringLiteral("p_working_id")))) return QStringLiteral("p_working_id");
    if (!canonicalUuid(args.value(QStringLiteral("p_request_id")))) return QStringLiteral("p_request_id");
    if (args.value(QStringLiteral("p_expected_version")).toLongLong() < 0) return QStringLiteral("p_expected_version");
    const QVariant expense = args.value(QStringLiteral("p_expense_id"));
    if (!expense.isNull() && (!canonicalUuid(expense) || args.value(QStringLiteral("p_expense_row_version")).toLongLong() < 1))
        return QStringLiteral("p_expense_id");
    return validatePayload(args.value(QStringLiteral("p_payload")).toMap());
}

inline QVariantMap archiveArguments(const QString &workingId, qint64 expectedVersion)
{
    return {{QStringLiteral("p_working_id"), workingId}, {QStringLiteral("p_expected_version"), expectedVersion}};
}

inline QVariantMap promoteArguments(const QString &workingId, qint64 expectedVersion,
                                    qint64 expectedRenditionVersion)
{
    return {{QStringLiteral("p_working_id"), workingId},
            {QStringLiteral("p_expected_version"), expectedVersion},
            {QStringLiteral("p_expected_rendition_version"), expectedRenditionVersion}};
}

// La reserva debe coincidir EXACTAMENTE con el sustento guardado en el payload.
inline QVariantMap reserveArguments(const QString &workingId, const QVariantMap &source)
{
    const QString type = source.value(QStringLiteral("type")).toString();
    return {{QStringLiteral("p_working_id"), workingId},
            {QStringLiteral("p_file_id"), source.value(QStringLiteral("uploadRequestId")).toString()},
            {QStringLiteral("p_source_id"), source.value(QStringLiteral("id")).toString()},
            {QStringLiteral("p_file_name"), source.value(QStringLiteral("name")).toString()},
            {QStringLiteral("p_mime_type"), type.isEmpty() ? QStringLiteral("application/octet-stream") : type},
            {QStringLiteral("p_size_bytes"), source.value(QStringLiteral("size")).toLongLong()},
            {QStringLiteral("p_last_modified"), source.value(QStringLiteral("lastModified")).toLongLong()}};
}
inline QString validateReserve(const QVariantMap &args)
{
    static const QRegularExpression mime(QStringLiteral("^[a-z0-9][a-z0-9.+-]*/[a-z0-9][a-z0-9.+-]*$"));
    static const QRegularExpression forbidden(QStringLiteral("[\\\\/\\x00-\\x1f\\x7f]"));
    const QString name = args.value(QStringLiteral("p_file_name")).toString();
    const QString source = args.value(QStringLiteral("p_source_id")).toString();
    const qint64 size = args.value(QStringLiteral("p_size_bytes")).toLongLong();
    if (!canonicalUuid(args.value(QStringLiteral("p_working_id")))) return QStringLiteral("p_working_id");
    if (!canonicalUuid(args.value(QStringLiteral("p_file_id")))) return QStringLiteral("p_file_id");
    if (source.isEmpty() || source.size() > 160) return QStringLiteral("p_source_id");
    if (name.trimmed().isEmpty() || name.trimmed().size() > 255 || forbidden.match(name).hasMatch()) return QStringLiteral("p_file_name");
    if (!mime.match(args.value(QStringLiteral("p_mime_type")).toString()).hasMatch()) return QStringLiteral("p_mime_type");
    if (size < 1 || size > MaxFileBytes) return QStringLiteral("p_size_bytes");
    if (args.value(QStringLiteral("p_last_modified")).toLongLong() < 0) return QStringLiteral("p_last_modified");
    return {};
}

// Ruta que asigna el servidor: renditions/<rendición>/expenses/<working>/attachments/<archivo>.
// Se usa sólo para comprobar la respuesta; nunca se fabrica ni se guarda como URL.
inline bool reservedPathValid(const QVariantMap &reserved, const QString &renditionId,
                              const QString &workingId)
{
    const QString id = reserved.value(QStringLiteral("id")).toString();
    return reserved.value(QStringLiteral("storage_path")).toString()
        == QStringLiteral("renditions/%1/expenses/%2/attachments/%3").arg(renditionId, workingId, id);
}

// --------------------------------------------------------------- Respuestas
struct Record {
    QString id, renditionId, kind, state, expenseId, updatedAt;
    qint64 rowVersion = 0;
    qint64 expenseRowVersion = 0;
    QVariantMap form, baseline;
    QVariantList sources;
    QString expenseRequestId;
    QStringList readySourceIds;   // sustentos con bytes confirmados en servidor
    QString error;                // vacío = registro válido
    bool active() const { return error.isEmpty() && state == QLatin1String("ACTIVE"); }
};

// Réplica de normalize() Web: rechaza respuestas fuera de contrato en vez de adivinar.
inline Record normalize(const QVariant &value, const QString &renditionId)
{
    Record r;
    const QVariantMap data = value.toMap();
    const QVariantMap payload = data.value(QStringLiteral("payload")).toMap();
    r.id = data.value(QStringLiteral("id")).toString();
    r.renditionId = data.value(QStringLiteral("rendition_id")).toString();
    r.kind = data.value(QStringLiteral("kind")).toString();
    r.state = data.value(QStringLiteral("state")).toString();
    r.rowVersion = data.value(QStringLiteral("row_version")).toLongLong();
    r.updatedAt = data.value(QStringLiteral("updated_at")).toString();
    const QVariant expense = data.value(QStringLiteral("expense_id"));
    r.expenseId = expense.isNull() ? QString() : expense.toString();
    const QVariant expenseVersion = data.value(QStringLiteral("expense_row_version"));
    r.expenseRowVersion = expenseVersion.isNull() ? 0 : expenseVersion.toLongLong();
    r.form = payload.value(QStringLiteral("form")).toMap();
    r.baseline = payload.value(QStringLiteral("baseline")).toMap();
    r.sources = payload.value(QStringLiteral("sources")).toList();
    r.expenseRequestId = payload.value(QStringLiteral("requestId")).toString();
    if (value.typeId() != QMetaType::QVariantMap || !canonicalUuid(r.id) || r.renditionId != renditionId
        || (r.kind != QLatin1String("NEW") && r.kind != QLatin1String("EDIT"))
        || !QStringList{QStringLiteral("ACTIVE"), QStringLiteral("PROMOTED"), QStringLiteral("ARCHIVED")}.contains(r.state)
        || r.rowVersion < 1 || !validateForm(payload.value(QStringLiteral("form"))).isEmpty()
        || !validateForm(payload.value(QStringLiteral("baseline"))).isEmpty()
        || data.value(QStringLiteral("files")).typeId() != QMetaType::QVariantList) {
        r.error = QStringLiteral("RENDITION_INVALID_RESPONSE");
        return r;
    }
    for (const QVariant &f : data.value(QStringLiteral("files")).toList()) {
        const QVariantMap file = f.toMap();
        if (file.value(QStringLiteral("status")).toString() != QLatin1String("READY")) continue;
        const QString sourceId = file.value(QStringLiteral("source_id")).toString();
        for (const QVariant &s : r.sources) {
            const QVariantMap source = s.toMap();
            if (source.value(QStringLiteral("id")).toString() == sourceId
                && source.value(QStringLiteral("uploadRequestId")).toString() == file.value(QStringLiteral("id")).toString()) {
                r.readySourceIds.append(sourceId);
                break;
            }
        }
    }
    return r;
}

// Sustentos que existen sólo como metadatos (bytes nunca subidos): no se pueden recrear.
inline QStringList missingSources(const Record &record)
{
    QStringList missing;
    for (const QVariant &s : record.sources) {
        const QString id = s.toMap().value(QStringLiteral("id")).toString();
        if (!record.readySourceIds.contains(id)) missing.append(id);
    }
    return missing;
}

// ------------------------------------------------------------- Idempotencia
// Mismo intento (misma fila, payload, CAS y base) => mismo p_request_id en cada reintento,
// también tras perder la respuesta. Cambiar cualquier dato crea un intento nuevo.
class IntentLedger {
public:
    QString requestIdFor(const QVariantMap &args)
    {
        const QString row = args.value(QStringLiteral("p_working_id")).toString();
        QVariantMap identity = args;
        identity.remove(QStringLiteral("p_request_id"));
        const QByteArray signature = QJsonDocument::fromVariant(identity).toJson(QJsonDocument::Compact);
        auto it = m_intents.find(row);
        if (it == m_intents.end() || it->signature != signature)
            it = m_intents.insert(row, {signature, newUuid()});
        return it->requestId;
    }
    void acknowledge(const QString &workingId) { m_intents.remove(workingId); }
    void clear() { m_intents.clear(); }   // cambio de cuenta o de rendición
private:
    struct Intent { QByteArray signature; QString requestId; };
    QHash<QString, Intent> m_intents;
};

// ---------------------------------------------------------------- Errores
// PGRST202 = la RPC no existe en este entorno: se desactiva el guardado en nube y
// la fila sigue local. Nunca se reintenta como si fuera un fallo de red.
inline QString classify(const QString &code)
{
    if (code == QLatin1String("PGRST202")) return QStringLiteral("CONTRACT_REQUIRED");
    return code;
}
inline bool conflict(const QString &code)
{
    return code == QLatin1String("RENDITION_WORKING_CONFLICT")
        || code == QLatin1String("RENDITION_EXPENSE_VERSION_CONFLICT")
        || code == QLatin1String("RENDITION_WORKING_IDEMPOTENCY_CONFLICT");
}
// Errores definitivos: no se reintentan desde el outbox (requieren al usuario).
inline bool permanent(const QString &code)
{
    return conflict(code) || code == QLatin1String("CONTRACT_REQUIRED") || code == QLatin1String("PGRST202")
        || code == QLatin1String("RENDITION_WORKING_INVALID") || code == QLatin1String("RENDITION_WORKING_INVALID_FILE")
        || code == QLatin1String("RENDITION_NOT_EDITABLE") || code == QLatin1String("RENDITION_NOT_FOUND_OR_FORBIDDEN");
}

inline QString message(const QString &code)
{
    static const QHash<QString, QString> texts{
        {QStringLiteral("CONTRACT_REQUIRED"),
         QStringLiteral("El guardado de filas incompletas en el servidor no está disponible en este entorno. Tus cambios se conservan en el equipo.")},
        {QStringLiteral("RENDITION_WORKING_CONFLICT"),
         QStringLiteral("Esta fila cambió en otra sesión. Tus cambios se conservaron; revisa la versión del servidor antes de continuar.")},
        {QStringLiteral("RENDITION_EXPENSE_VERSION_CONFLICT"),
         QStringLiteral("El gasto original cambió en otra sesión. Tus cambios se conservaron; revisa la versión actual antes de continuar.")},
        {QStringLiteral("RENDITION_WORKING_IDEMPOTENCY_CONFLICT"),
         QStringLiteral("Un reintento no coincide con el guardado original. Tus cambios se conservaron; vuelve a abrir la fila.")},
        {QStringLiteral("RENDITION_WORKING_FILES_PENDING"),
         QStringLiteral("La fila está en el servidor; faltan sustentos por cargar o volver a adjuntar.")},
        {QStringLiteral("RENDITION_WORKING_ROWS_PENDING"),
         QStringLiteral("Hay filas de gasto sin terminar en esta rendición. Complétalas o descártalas antes de presentar.")},
        {QStringLiteral("RENDITION_WORKING_INVALID"),
         QStringLiteral("La copia de trabajo no cumple el formato del servidor. Tus cambios se conservan.")},
        {QStringLiteral("RENDITION_WORKING_INVALID_FILE"),
         QStringLiteral("El sustento no coincide con el registrado o su reserva expiró. Vuelve a adjuntarlo.")},
        {QStringLiteral("RENDITION_ATTACHMENT_OBJECT_MISSING"),
         QStringLiteral("El archivo del sustento aún no está en el servidor.")}};
    // Sin classify(): PGRST202 sólo significa CONTRACT_REQUIRED dentro del servicio Working.
    return texts.value(code);
}

} // namespace RenditionWorkingContract
