#include "calicatadocument.h"
#include <QScopedValueRollback>
#include "appcontext.h"
#include "authsession.h"
#include "calicatavalidation.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QSaveFile>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QStandardPaths>
#include <QImageReader>
#include <QPainter>
#include <QDateTime>
#include <QDebug>
#include <QJSValue>
#include <QJsonValue>
#include <QRegularExpression>
#include <QStringList>
#include <QUuid>
#include <QSettings>
#include <QSet>
#include <QtMath>
#include <QPointer>
#include <QThreadPool>
#include <QCoreApplication>
#include <QFont>
#include <QFontMetricsF>
#include <QColor>
#include <QDate>
#include <QPainterPath>
#include <QPolygonF>
#include <QTransform>
#include <QtAlgorithms>
#include <algorithm>
#ifdef Q_OS_ANDROID
#  include <QJniObject>
#  include <QJniEnvironment>
#endif

namespace {

// Web ROAD_SIDE_OPTIONS (sheetPresentation.ts), stored in `calicatas.location`.
const QStringList &roadSideOptions()
{
    static const QStringList options = {
        QStringLiteral("Derecho"), QStringLiteral("Izquierdo"), QStringLiteral("Ambos"),
        QStringLiteral("Eje de vía"), QStringLiteral("Berma derecha"),
        QStringLiteral("Berma izquierda"), QStringLiteral("Fuera de vía")
    };
    return options;
}

// "18", "18L" or "18 L" -> 18; anything outside 1..60 -> 0.
int utmZoneNumber(const QString &text)
{
    static const QRegularExpression pattern(QStringLiteral("^(\\d{1,2})(?:\\s*[C-HJ-NP-X])?$"),
                                            QRegularExpression::CaseInsensitiveOption);
    const QRegularExpressionMatch match = pattern.match(text.trimmed());
    if (!match.hasMatch()) return 0;
    const int zone = match.captured(1).toInt();
    return zone >= 1 && zone <= 60 ? zone : 0;
}

QString utmBandForLatitude(const QVariant &latitudeValue)
{
    bool ok = false;
    const double latitude = latitudeValue.toString().toDouble(&ok);
    if (!ok || !qIsFinite(latitude) || latitude < -80.0 || latitude > 84.0) return {};
    static const QString bands = QStringLiteral("CDEFGHJKLMNPQRSTUVWX");
    const int index = qMin(int(bands.size()) - 1, int((latitude + 80.0) / 8.0));
    return bands.mid(index, 1);
}

QVariantMap canonicalHeader(QVariantMap header) {
    const QRegularExpression decimal(QStringLiteral("^[+-]?(?:[0-9]+(?:[.,][0-9]*)?|[.,][0-9]+)$"));
    const auto normalizeDecimal = [&](const QString &key) {
        if (!header.contains(key)) return;
        QString text = header.value(key).toString().trimmed();
        if (decimal.match(text).hasMatch()) header[key] = text.replace(',', '.');
    };
    for (const auto &key : {QStringLiteral("utm_x"), QStringLiteral("utm_y"), QStringLiteral("utm_z"),
                            QStringLiteral("altitud"), QStringLiteral("water_table_depth"),
                            QStringLiteral("groundwater_depth_m"), QStringLiteral("easting"),
                            QStringLiteral("northing"), QStringLiteral("altitude_m"),
                            QStringLiteral("depth_m"), QStringLiteral("final_depth_m"),
                            QStringLiteral("requested_depth_m"), QStringLiteral("width_m"),
                            QStringLiteral("length_m")})
        normalizeDecimal(key);

    // Canonical Web <-> Android aliases. Web field names are authoritative for
    // remote sync; legacy aliases remain so the current QML and XLSX keep working.
    const auto bridge = [&](const QString &canonical, const QString &legacy) {
        if (!header.contains(canonical) && header.contains(legacy))
            header[canonical] = header.value(legacy);
        if (!header.contains(legacy) && header.contains(canonical))
            header[legacy] = header.value(canonical);
    };
    bridge(QStringLiteral("code"), QStringLiteral("codigo"));
    bridge(QStringLiteral("progresiva"), QStringLiteral("pk"));
    bridge(QStringLiteral("easting"), QStringLiteral("utm_x"));
    bridge(QStringLiteral("northing"), QStringLiteral("utm_y"));
    bridge(QStringLiteral("altitude_m"), QStringLiteral("utm_z"));
    bridge(QStringLiteral("machine"), QStringLiteral("maquina"));
    bridge(QStringLiteral("start_date"), QStringLiteral("fecha_inicio"));
    bridge(QStringLiteral("end_date"), QStringLiteral("fecha_fin"));
    bridge(QStringLiteral("depth_m"), QStringLiteral("final_depth_m"));
    bridge(QStringLiteral("groundwater_depth_m"), QStringLiteral("water_table_depth"));
    // `description` is Web's "Título de la ficha / testificación". The Android
    // technical description (`technical_description`) is no longer bridged into
    // it; existing values of either key are kept exactly as they are.

    // `location` is the road side (Web "Lado de la vía"), mirrored locally as
    // `lado_via`. Older Android builds wrote "Ubicación / Tramo" into
    // `location`; that value still lives in `ubicacion`, so it is recognised
    // and replaced by the road side. Any other historical value is kept.
    {
        const QString tramo = header.value(QStringLiteral("ubicacion"),
                                           header.value(QStringLiteral("tramo"))).toString().trimmed();
        const bool hasLocation = header.contains(QStringLiteral("location"));
        const bool hasSide = header.contains(QStringLiteral("lado_via"));
        if (hasLocation || hasSide) {
            QString side = header.value(QStringLiteral("location")).toString().trimmed();
            if (!side.isEmpty() && !tramo.isEmpty() && side == tramo
                && !roadSideOptions().contains(side, Qt::CaseInsensitive))
                side.clear();
            if (side.isEmpty())
                side = header.value(QStringLiteral("lado_via")).toString().trimmed();
            for (const QString &option : roadSideOptions()) {
                if (side.compare(option, Qt::CaseInsensitive) == 0) { side = option; break; }
            }
            header[QStringLiteral("location")] = side;
            header[QStringLiteral("lado_via")] = side;
        }
    }

    // `utm_zone` is the numeric WGS84 zone (1..60). `zona` keeps Android's
    // band ("18L") for display and UTM->geographic conversion. Local edits
    // write `zona`; values that cannot be read as a zone stay in `zona`.
    {
        const QString zonaText = header.value(QStringLiteral("zona")).toString().trimmed().toUpper();
        const int zone = zonaText.isEmpty()
            ? utmZoneNumber(header.value(QStringLiteral("utm_zone")).toString())
            : utmZoneNumber(zonaText);
        if (zone > 0) {
            header[QStringLiteral("utm_zone")] = zone;
            if (zonaText.isEmpty()) {
                const QString band = utmBandForLatitude(header.value(QStringLiteral("latitude")));
                header[QStringLiteral("zona")] = QString::number(zone) + band;
            }
        } else if (header.contains(QStringLiteral("utm_zone")) || header.contains(QStringLiteral("zona"))) {
            header[QStringLiteral("utm_zone")] = QVariant();
        }
    }

    if (header.contains(QStringLiteral("code")))
        header[QStringLiteral("calicata")] = header.value(QStringLiteral("code"));
    else if (header.contains(QStringLiteral("calicata"))) {
        header[QStringLiteral("code")] = header.value(QStringLiteral("calicata"));
        header[QStringLiteral("codigo")] = header.value(QStringLiteral("calicata"));
    }
    if (header.contains(QStringLiteral("altitude_m")))
        header[QStringLiteral("altitud")] = header.value(QStringLiteral("altitude_m"));

    static const QSet<QString> statuses = {
        QStringLiteral("BORRADOR"), QStringLiteral("EN_REVISION"),
        QStringLiteral("OBSERVADO"), QStringLiteral("REVISADO"),
        QStringLiteral("APROBADO"), QStringLiteral("EXPORTADO"),
        QStringLiteral("ARCHIVADO")
    };
    QString status = header.value(QStringLiteral("status"), QStringLiteral("BORRADOR"))
        .toString().trimmed().toUpper();
    if (!statuses.contains(status)) status = QStringLiteral("BORRADOR");
    header[QStringLiteral("status")] = status;

    if (!header.contains(QStringLiteral("projectId")) && header.contains(QStringLiteral("project_id")))
        header[QStringLiteral("projectId")] = header.value(QStringLiteral("project_id"));
    if (header.contains(QStringLiteral("projectId")))
        header[QStringLiteral("project_id")] = header.value(QStringLiteral("projectId"));
    // projectName/projectCode/projectId identifican el espacio de trabajo
    // (destino de almacenamiento). El nombre contractual del proyecto es
    // project_full_name y nunca se deriva de la carpeta ni la alimenta.
    if (!header.contains(QStringLiteral("projectName")) && header.contains(QStringLiteral("project_name")))
        header[QStringLiteral("projectName")] = header.value(QStringLiteral("project_name"));
    if (!header.contains(QStringLiteral("projectCode")))
        header[QStringLiteral("projectCode")] = header.value(QStringLiteral("project_code"));

    if (!header.contains(QStringLiteral("water_table_status"))) {
        const auto water = header.value(QStringLiteral("water_table_present"),
                                        header.value(QStringLiteral("waterTablePresent")));
        const auto text = water.toString().trimmed().toUpper();
        header[QStringLiteral("water_table_status")] = text == QLatin1String("TRUE") || text == QLatin1String("1") || text == QLatin1String("ENCONTRADO")
            ? QStringLiteral("ENCONTRADO") : text == QLatin1String("FALSE") || text == QLatin1String("0") || text == QLatin1String("NO_ENCONTRADO")
            ? QStringLiteral("NO_ENCONTRADO") : QStringLiteral("NO_EVALUADO");
    }
    header[QStringLiteral("water_table_present")] =
        header.value(QStringLiteral("water_table_status")) == QLatin1String("ENCONTRADO");
    if (header.value(QStringLiteral("water_table_status")).toString() != QLatin1String("ENCONTRADO")) {
        header[QStringLiteral("groundwater_depth_m")] = QVariant();
        header[QStringLiteral("water_table_depth")] = QVariant();
    }

    if (header.contains(QStringLiteral("project_full_name")))
        header.insert(QStringLiteral("excel_title"), header.value(QStringLiteral("project_full_name")));
    else if (header.contains(QStringLiteral("excel_title")))
        header.insert(QStringLiteral("project_full_name"), header.value(QStringLiteral("excel_title")));

    for (const auto &key : {QStringLiteral("fecha_inicio"), QStringLiteral("fecha_fin"),
                            QStringLiteral("start_date"), QStringLiteral("end_date")})
        if (header.value(key).toString() == QLatin1String("00/00/0000")) header.insert(key, QString());

    if (!header.contains(QStringLiteral("remoteCalicataId")) && header.contains(QStringLiteral("remote_calicata_id")))
        header[QStringLiteral("remoteCalicataId")] = header.value(QStringLiteral("remote_calicata_id"));
    if (header.contains(QStringLiteral("remoteCalicataId")))
        header[QStringLiteral("remote_calicata_id")] = header.value(QStringLiteral("remoteCalicataId"));
    if (!header.contains(QStringLiteral("remoteRowVersion")) && header.contains(QStringLiteral("row_version")))
        header[QStringLiteral("remoteRowVersion")] = header.value(QStringLiteral("row_version"));
    if (header.contains(QStringLiteral("remoteRowVersion")))
        header[QStringLiteral("row_version")] = header.value(QStringLiteral("remoteRowVersion"));

    // A persisted SYNCING means the process died mid-request: nothing was
    // confirmed, so the mirror is PENDING again.
    static const QSet<QString> syncStates = {
        QStringLiteral("LOCAL"), QStringLiteral("PENDING"), QStringLiteral("SYNCED"),
        QStringLiteral("CONFLICT")
    };
    const bool hasRemote = !QUuid(header.value(QStringLiteral("remoteCalicataId")).toString()).isNull();
    const QString syncState = header.value(QStringLiteral("sync_state")).toString().trimmed().toUpper();
    header[QStringLiteral("sync_state")] = syncStates.contains(syncState)
        ? syncState : (hasRemote ? QStringLiteral("PENDING") : QStringLiteral("LOCAL"));
    return header;
}

// Lifecycle shared with Web's calicata_status. ARCHIVADO is lateral and is
// left only through an explicit restore.
QStringList statusTransitionsFrom(const QString &status)
{
    if (status == QLatin1String("ARCHIVADO")) return {};
    QStringList next;
    if (status == QLatin1String("BORRADOR") || status == QLatin1String("OBSERVADO"))
        next << QStringLiteral("EN_REVISION");
    else if (status == QLatin1String("EN_REVISION"))
        next << QStringLiteral("OBSERVADO") << QStringLiteral("REVISADO");
    else if (status == QLatin1String("REVISADO"))
        next << QStringLiteral("OBSERVADO") << QStringLiteral("APROBADO");
    else if (status == QLatin1String("APROBADO"))
        next << QStringLiteral("EXPORTADO");
    next << QStringLiteral("ARCHIVADO");
    return next;
}

QString cleanPathJoin(const QString& a, const QString& b) {
    QDir d(a);
    return QDir::cleanPath(d.filePath(b));
}

QString ensureCalicataExt(QString name) {
    name = name.trimmed();
    if (name.isEmpty()) return {};
    const QString low = name.toLower();
    if (low.endsWith(".calicata.json")) return name;
    if (low.endsWith(".json")) name.chop(5);
    if (name.toLower().endsWith(".calicata")) name.chop(8);
    return name + ".calicata.json";
}

bool toPureVariant(const QVariant &value,
                   QVariant *pureValue,
                   QString *error,
                   const QString &path,
                   int depth = 0)
{
    if (!pureValue)
        return false;
    if (depth > 64) {
        if (error)
            *error = QStringLiteral("%1 excede la profundidad máxima").arg(path);
        return false;
    }

    if (!value.isValid() || value.isNull()) {
        *pureValue = QVariant();
        return true;
    }

    const QMetaType metaType = value.metaType();
    if (metaType.flags().testFlag(QMetaType::PointerToQObject)) {
        if (error) {
            *error = QStringLiteral("%1 contiene un puntero QObject (%2)")
                         .arg(path, QString::fromLatin1(metaType.name()));
        }
        return false;
    }

    if (metaType == QMetaType::fromType<QJSValue>()) {
        const QJSValue jsValue = value.value<QJSValue>();
        if (jsValue.isQObject() || jsValue.isCallable()) {
            if (error)
                *error = QStringLiteral("%1 contiene un QJSValue vivo").arg(path);
            return false;
        }

        const QVariant converted = jsValue.toVariant();
        if (converted.metaType() == metaType) {
            if (error)
                *error = QStringLiteral("%1 no pudo convertirse desde QJSValue").arg(path);
            return false;
        }
        return toPureVariant(converted, pureValue, error, path, depth + 1);
    }

    if (metaType.id() == QMetaType::QVariantMap) {
        QVariantMap pureMap;
        const QVariantMap sourceMap = value.toMap();
        for (auto it = sourceMap.cbegin(); it != sourceMap.cend(); ++it) {
            QVariant child;
            if (!toPureVariant(it.value(), &child, error,
                               path + QLatin1Char('.') + it.key(), depth + 1)) {
                return false;
            }
            pureMap.insert(it.key(), child);
        }
        *pureValue = pureMap;
        return true;
    }

    if (metaType.id() == QMetaType::QVariantHash) {
        QVariantMap pureMap;
        const QVariantHash sourceHash = value.toHash();
        for (auto it = sourceHash.cbegin(); it != sourceHash.cend(); ++it) {
            QVariant child;
            if (!toPureVariant(it.value(), &child, error,
                               path + QLatin1Char('.') + it.key(), depth + 1)) {
                return false;
            }
            pureMap.insert(it.key(), child);
        }
        *pureValue = pureMap;
        return true;
    }

    if (metaType.id() == QMetaType::QStringList) {
        QVariantList pureList;
        const QStringList sourceList = value.toStringList();
        pureList.reserve(sourceList.size());
        for (const QString &item : sourceList)
            pureList.append(item);
        *pureValue = pureList;
        return true;
    }

    if (metaType.id() == QMetaType::QVariantList) {
        QVariantList pureList;
        const QVariantList sourceList = value.toList();
        pureList.reserve(sourceList.size());
        for (qsizetype i = 0; i < sourceList.size(); ++i) {
            QVariant child;
            if (!toPureVariant(sourceList.at(i), &child, error,
                               QStringLiteral("%1[%2]").arg(path).arg(i), depth + 1)) {
                return false;
            }
            pureList.append(child);
        }
        *pureValue = pureList;
        return true;
    }

    const QJsonValue jsonValue = QJsonValue::fromVariant(value);
    if (jsonValue.isUndefined()) {
        if (error) {
            *error = QStringLiteral("%1 usa un tipo no serializable (%2)")
                         .arg(path, QString::fromLatin1(metaType.name()));
        }
        return false;
    }

    *pureValue = jsonValue.toVariant();
    return true;
}

bool toPureMap(const QVariantMap &value,
               QVariantMap *pureMap,
               QString *error,
               const QString &propertyName)
{
    QVariant pure;
    if (!toPureVariant(value, &pure, error, propertyName))
        return false;
    if (pure.metaType().id() != QMetaType::QVariantMap) {
        if (error)
            *error = QStringLiteral("%1 no es un QVariantMap puro").arg(propertyName);
        return false;
    }
    *pureMap = pure.toMap();
    return true;
}

} // namespace

CalicataDocument::CalicataDocument(QObject *parent)
    : QObject(parent),
      m_instanceId(QUuid::createUuid().toString(QUuid::WithoutBraces)),
      m_photoDraftId(QUuid::createUuid().toString(QUuid::WithoutBraces))
{
    m_header = canonicalHeader(activeProject());
    m_header["calicataId"] = m_instanceId;
    stampLocalAuthorship();
}

void CalicataDocument::stampLocalAuthorship()
{
    // Provisional local authorship for offline work. The server's
    // created_by / created_at replace these on the first confirmed sync.
    auto *ctx = appContext();
    if (ctx && ctx->auth() && ctx->auth()->logged()
        && m_header.value(QStringLiteral("created_by")).toString().isEmpty())
        m_header[QStringLiteral("created_by")] = ctx->auth()->userId();
    if (m_header.value(QStringLiteral("created_at")).toString().isEmpty())
        m_header[QStringLiteral("local_created_at")] =
            QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
}

QString CalicataDocument::status() const
{
    return m_header.value(QStringLiteral("status"), QStringLiteral("BORRADOR")).toString();
}

QString CalicataDocument::syncState() const
{
    return m_header.value(QStringLiteral("sync_state"), QStringLiteral("LOCAL")).toString();
}

void CalicataDocument::setSyncState(const QString &state)
{
    if (m_closed) return;
    const QString next = state.trimmed().toUpper();
    static const QSet<QString> valid = {
        QStringLiteral("LOCAL"), QStringLiteral("PENDING"), QStringLiteral("SYNCING"),
        QStringLiteral("SYNCED"), QStringLiteral("CONFLICT")
    };
    if (!valid.contains(next) || syncState() == next) return;
    if (next == QLatin1String("SYNCING")) m_changedWhileSyncing = false;
    m_header[QStringLiteral("sync_state")] = next;
    emit dataChanged();
    // Persist without touching the dirty flag semantics of user edits.
    const bool wasDirty = m_dirty;
    if (saveDraft() && wasDirty) setDirty(true);
}

QStringList CalicataDocument::allowedStatusTransitions() const
{
    return m_closed ? QStringList{} : statusTransitionsFrom(status());
}

QString CalicataDocument::restoreTargetStatus() const
{
    static const QSet<QString> restorable = {
        QStringLiteral("BORRADOR"), QStringLiteral("EN_REVISION"), QStringLiteral("OBSERVADO"),
        QStringLiteral("REVISADO"), QStringLiteral("APROBADO"), QStringLiteral("EXPORTADO")
    };
    const QString from = m_header.value(QStringLiteral("archived_from_status")).toString();
    return restorable.contains(from) ? from : QStringLiteral("BORRADOR");
}

bool CalicataDocument::restoreFromArchive()
{
    if (m_closed || status() != QLatin1String("ARCHIVADO")) {
        setErrorString(QStringLiteral("La calicata no está archivada."));
        return false;
    }
    const auto before = m_header;
    m_header[QStringLiteral("status")] = restoreTargetStatus();
    m_header.remove(QStringLiteral("archived_from_status"));
    m_header[QStringLiteral("local_status_changed_at")] =
        QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
    markDirty();
    if (!saveDraft()) { m_header = before; emit dataChanged(); return false; }
    emit dataChanged();
    clearError();
    return true;
}

// Proyecto inicial de una ficha NUEVA (constructor y resetNew): el proyecto
// principal de la cuenta con la misma regla que el perfil de cuenta
// (AuthSession.assignedProjects[0], lista de proyectos accesibles que entrega el
// servidor). Nunca el último proyecto usado en otra ficha: ese estado global
// ("calicatas/activeProject") provocaba que "Nueva calicata" heredara el
// proyecto de la ficha anterior. Sin proyecto accesible: vacío (sin seleccionar).
// Las fichas abiertas/descargadas/duplicadas conservan su propio header.
QVariantMap CalicataDocument::activeProject() const
{
    auto *ctx = appContext();
    if (!ctx || !ctx->auth() || !ctx->auth()->logged()) return {};
    const QVariantList projects = ctx->auth()->assignedProjects();
    if (projects.isEmpty()) return {};
    const QVariantMap principal = projects.first().toMap();
    const QUuid id(principal.value(QStringLiteral("id")).toString());
    if (id.isNull()) return {};
    QVariantMap selection;
    selection[QStringLiteral("projectId")] = id.toString(QUuid::WithoutBraces);
    selection[QStringLiteral("projectCode")] = principal.value(QStringLiteral("code"));
    selection[QStringLiteral("projectName")] = principal.value(QStringLiteral("name"));
    return selection;
}

bool CalicataDocument::selectProject(const QVariantMap &project)
{
    const QUuid id(project.value("projectId", project.value("id")).toString());
    if (m_closed || id.isNull()) {
        setErrorString(QStringLiteral("Selecciona un proyecto válido."));
        return false;
    }
    // A calicata confirmed by the server belongs to its project for good
    // (calicata.project_id); it can never be re-parented from Android.
    const QUuid currentProject(m_header.value(QStringLiteral("projectId")).toString());
    const bool hasRemoteIdentity = !QUuid(m_header.value(QStringLiteral("remoteCalicataId")).toString()).isNull();
    if (hasRemoteIdentity && !currentProject.isNull() && currentProject != id) {
        setErrorString(QStringLiteral("Esta calicata ya pertenece a otro proyecto en InGe+ y no puede moverse. "
                                      "Crea una nueva ficha en el proyecto elegido."));
        return false;
    }

    const QVariantMap before = m_header;
    auto header = m_header;
    QVariantMap selection;
    selection["projectId"] = id.toString(QUuid::WithoutBraces);
    selection["projectCode"] = project.value("projectCode", project.value("project_code", project.value("code")));
    selection["projectName"] = project.value("projectName", project.value("project_name", project.value("name")));
    // project_full_name (nombre contractual, dato de la ficha) no se toca: la
    // carpeta/espacio elegido solo define dónde se guarda la calicata.
    selection["documentSpaceId"] = project.value("spaceId", project.value("space_id"));
    selection["documentParentNodeId"] = project.value("documentParentNodeId");
    selection["projectFolderPath"] = project.value("folderPath");
    for (auto it = selection.cbegin(); it != selection.cend(); ++it)
        header[it.key()] = it.value();

    setHeader(header);
    if (!saveDraft()) {
        m_header = before;
        updateDisplayName();
        emit dataChanged();
        return false;
    }

    // El proyecto elegido pertenece solo a ESTA ficha: no se guarda como
    // proyecto global/último usado ni cambia el proyecto principal de la cuenta.
    clearError();
    return true;
}

bool CalicataDocument::transitionStatus(const QString &next)
{
    const auto previous = status();
    const bool allowed = statusTransitionsFrom(previous).contains(next);
    if (m_closed || !allowed) {
        setErrorString(QStringLiteral("El cambio de estado no está permitido."));
        return false;
    }
    if (next == "APROBADO" || next == "EXPORTADO" || next == "EN_REVISION") {
        for (const auto &value : validationIssues(buildFullJson())) {
            const auto issue = value.toMap();
            if (issue.value("severity") == "WARNING") continue;
            setErrorString(issue.value("message").toString());
            return false;
        }
    }
    const auto before = m_header;
    m_header["status"] = next;
    if (next == "ARCHIVADO")
        m_header["archived_from_status"] = previous;
    // updated_at belongs to the server (set_updated_at trigger); the device
    // clock only records when the local transition happened.
    m_header["local_status_changed_at"] = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
    markDirty();
    if (!saveDraft()) { m_header = before; emit dataChanged(); return false; }
    emit dataChanged();
    return true;
}

QVariantList CalicataDocument::validationIssues(const QVariantMap &state) const
{
    auto checked = state;
    QVariantMap available;
    for (int i = 1; i <= 3; ++i)
        available[QString::number(i)] = !cachedPhotoUrl(i).isEmpty();
    checked["photoAvailability"] = available;
    return CalicataValidation::issues(checked);
}

void CalicataDocument::setErrorString(const QString &value)
{
    if (m_errorString == value) return;
    m_errorString = value;
    emit errorStringChanged();
}

void CalicataDocument::clearError() { setErrorString(QString()); }

CalicataDocument::~CalicataDocument()
{
    if (!m_closed) {
        const QString abs = absPathFromUrl(m_fileUrl);
        if (!abs.isEmpty() && appContext())
            appContext()->unregisterOpenFile(abs);
    }
    cleanupDraftPhotos();
}

void CalicataDocument::prepareForClose()
{
    if (m_closed)
        return;

    m_closed = true;

    const QString abs = absPathFromUrl(m_fileUrl);
    if (!abs.isEmpty() && appContext())
        appContext()->unregisterOpenFile(abs);

    cleanupDraftPhotos();
    emit closedChanged();
}

bool CalicataDocument::isInsideDir(const QString& absFile, const QString& absDir) const
{
    QString f = QDir::cleanPath(absFile);
    QString d = QDir::cleanPath(absDir);
#ifdef Q_OS_WIN
    f = f.toLower();
    d = d.toLower();
#endif
    if (!d.endsWith('/')) d += '/';
    return (f == QDir::cleanPath(absDir)) || f.startsWith(d);
}

bool CalicataDocument::hasSavedFile() const
{
    return !absPathFromUrl(m_fileUrl).isEmpty();
}

void CalicataDocument::setProjectsFolderLabel(const QString& v)
{
    if (m_closed) return;
    const QString nv = v.trimmed().isEmpty() ? "InGePlusProyectos" : v.trimmed();
    if (nv == m_projectsFolderLabel) return;
    m_projectsFolderLabel = nv;
    emit projectsFolderLabelChanged();
}

void CalicataDocument::setHeader(const QVariantMap& v)
{
    if (m_closed) return;
    QVariantMap pure;
    QString error;
    if (!toPureMap(v, &pure, &error, QStringLiteral("header"))) {
        qWarning().noquote() << "[InGe+ M09] header rechazado:" << error;
        return;
    }
    pure = canonicalHeader(pure);
    pure["calicataId"] = m_instanceId;
    // Lifecycle, cloud identity and sync state are owned by transitionStatus /
    // applyCloudSync / setSyncState, never by a stale copy of the header.
    for (const char *owned : {"status", "sync_state", "archived_from_status", "created_by",
                              "remoteCalicataId", "remote_calicata_id", "remoteRowVersion",
                              "row_version"}) {
        const QString key = QString::fromLatin1(owned);
        if (m_header.contains(key)) pure[key] = m_header.value(key);
        else pure.remove(key);
    }
    if (!pure.contains("status")) pure["status"] = QStringLiteral("BORRADOR");
    if (m_header == pure) return;
    m_header = pure;
    updateDisplayName();
    markDirty();
    emit dataChanged();
}

bool CalicataDocument::checkpointCloudRevision(const QString &projectId, const QString &remoteId, qint64 revision)
{
    if (m_closed || revision < 1 || QUuid(remoteId).isNull()
        || QUuid(projectId) != QUuid(m_header.value(QStringLiteral("projectId")).toString())) return false;
    QScopedValueRollback<bool> applying(m_applyingCloudState, true);
    m_header[QStringLiteral("remoteCalicataId")] = remoteId;
    m_header[QStringLiteral("remote_calicata_id")] = remoteId;
    m_header[QStringLiteral("remoteRowVersion")] = revision;
    m_header[QStringLiteral("row_version")] = revision;
    // Recovery must retry from the last confirmed revision, never restore a
    // dead SYNCING operation after process termination. No form reconstruction.
    const QString state = syncState();
    m_header[QStringLiteral("sync_state")] = QStringLiteral("PENDING");
    const bool saved = saveDraft();
    m_header[QStringLiteral("sync_state")] = state;
    return saved;
}

bool CalicataDocument::applyLiveHeaderField(const QString &key, const QVariant &value)
{
    // Only header values the form does not keep in its own fields; identity,
    // project, lifecycle and cloud bookkeeping are never live-writable.
    static const QStringList allowed{QStringLiteral("title"), QStringLiteral("description")};
    if (m_closed || !allowed.contains(key)) return false;
    const int type = value.typeId();
    if (value.isValid() && !value.isNull() && type != QMetaType::QString && type != QMetaType::Double
        && type != QMetaType::Int && type != QMetaType::LongLong && type != QMetaType::Bool) return false;
    const QVariant normalized = value.isValid() && !value.isNull() ? value : QVariant(QString());
    if (normalized.typeId() == QMetaType::QString && normalized.toString().size() > 4000) return false;
    if (m_header.value(key) == normalized) return true;
    QScopedValueRollback<bool> applying(m_applyingCloudState, true);
    m_header[key] = normalized;
    updateDisplayName();
    emit dataChanged();
    return true;
}

void CalicataDocument::applyRemoteSnapshot(const QVariantMap &remoteRoot, const QVariantList &cortes)
{
    if (m_closed) return;
    const QString projectId = remoteRoot.value(QStringLiteral("project_id")).toString();
    if (projectId.isEmpty() || (!m_header.value(QStringLiteral("remoteCalicataId")).toString().isEmpty()
        && QUuid(projectId) != QUuid(m_header.value(QStringLiteral("projectId")).toString()))) {
        setErrorString(QStringLiteral("La ficha remota no corresponde al proyecto del documento."));
        return;
    }
    m_changedWhileSyncing = false;
    m_header[QStringLiteral("projectId")] = projectId;
    // Hydrate = estado del servidor, no edición del usuario: aplicado y
    // persistido localmente, la ficha queda limpia (Al día) y sin autosave.
    if (applyCloudSync(remoteRoot, cortes, true))
        setDirty(false);
}

bool CalicataDocument::applyCloudSync(const QVariantMap &remoteRoot, const QVariantList &syncedCortes, bool fullSnapshot)
{
    if (m_closed) return false;
    QScopedValueRollback<bool> applying(m_applyingCloudState, true);
    const bool editedMeanwhile = m_changedWhileSyncing;

    const QString remoteProjectId = remoteRoot.value(QStringLiteral("project_id"),
                                      remoteRoot.value(QStringLiteral("projectId"))).toString().trimmed();
    const QString localProjectId = m_header.value(QStringLiteral("projectId")).toString().trimmed();
    if (!remoteProjectId.isEmpty() && !localProjectId.isEmpty()
        && QUuid(remoteProjectId) != QUuid(localProjectId)) {
        setErrorString(QStringLiteral("El servidor devolvió una calicata de otro proyecto."));
        return false;
    }

    // Validate the server strata BEFORE touching the header: an invalid row must
    // not leave a half-applied state (new revision with the previous strata).
    const bool replaceCortes = !editedMeanwhile && (fullSnapshot || !syncedCortes.isEmpty() || m_cortes.isEmpty());
    QVariantList pureRows;
    if (replaceCortes) {
        pureRows.reserve(syncedCortes.size());
        for (qsizetype i = 0; i < syncedCortes.size(); ++i) {
            QVariant pure;
            QString error;
            if (!toPureVariant(syncedCortes.at(i), &pure, &error,
                               QStringLiteral("cloud.cortes[%1]").arg(i))
                || pure.metaType().id() != QMetaType::QVariantMap) {
                setErrorString(error.isEmpty()
                    ? QStringLiteral("El servidor devolvió un estrato inválido.") : error);
                return false;
            }
            pureRows.append(pure.toMap());
        }
    }

    QVariantMap merged = m_header;
    for (const char *key : {"projectCode", "projectName"}) {
        const QString k = QString::fromLatin1(key);
        if (remoteRoot.contains(k)) merged[k] = remoteRoot.value(k);
    }
    // El nombre del espacio remoto (projectName) es destino, no contenido: el
    // nombre contractual local (project_full_name) se conserva.
    const QString remoteId = remoteRoot.value(QStringLiteral("remoteCalicataId"),
                             remoteRoot.value(QStringLiteral("id"))).toString().trimmed();
    if (!QUuid(remoteId).isNull()) {
        merged[QStringLiteral("remoteCalicataId")] = QUuid(remoteId).toString(QUuid::WithoutBraces);
        merged[QStringLiteral("remote_calicata_id")] = merged.value(QStringLiteral("remoteCalicataId"));
    }
    const qlonglong rowVersion = remoteRoot.value(QStringLiteral("row_version"),
                                 remoteRoot.value(QStringLiteral("remoteRowVersion"))).toLongLong();
    if (rowVersion > 0) {
        merged[QStringLiteral("remoteRowVersion")] = rowVersion;
        merged[QStringLiteral("row_version")] = rowVersion;
    }

    // Adopt authoritative Web root values without replacing Android-only metadata.
    for (const QString &key : {
             QStringLiteral("project_id"), QStringLiteral("code"), QStringLiteral("title"),
             QStringLiteral("location"), QStringLiteral("progresiva"), QStringLiteral("easting"),
             QStringLiteral("northing"), QStringLiteral("altitude_m"), QStringLiteral("depth_m"),
             QStringLiteral("groundwater_depth_m"), QStringLiteral("utm_zone"),
             QStringLiteral("supervisor"), QStringLiteral("machine"), QStringLiteral("start_date"),
             QStringLiteral("end_date"), QStringLiteral("description"), QStringLiteral("status"),
             QStringLiteral("created_by"), QStringLiteral("created_at"), QStringLiteral("updated_at"),
             // Hora de la ficha y metadato de la cota (cross-device, 20261007181000).
             QStringLiteral("start_time"), QStringLiteral("altitude_source"), QStringLiteral("altitude_mode"),
             QStringLiteral("altitude_confidence"), QStringLiteral("altitude_accuracy_m"),
             QStringLiteral("altitude_vertical_reference"), QStringLiteral("altitude_resolved_at"),
             QStringLiteral("altitude_evidence")}) {
        if (remoteRoot.contains(key)) merged[key] = remoteRoot.value(key);
    }

    // P4/P5 round trip Web -> Android: the UI reads the legacy aliases, and the
    // canonicalizer only fills them when missing, so a value the server
    // confirmed must refresh them explicitly (otherwise Android keeps showing
    // the previous E/N/progresiva/etc.).
    const struct AliasKey { const char *canonical; const char *legacy; } aliases[] = {
        {"code", "codigo"}, {"code", "calicata"}, {"progresiva", "pk"}, {"easting", "utm_x"},
        {"northing", "utm_y"}, {"altitude_m", "utm_z"}, {"altitude_m", "altitud"},
        {"machine", "maquina"}, {"start_date", "fecha_inicio"}, {"end_date", "fecha_fin"},
        {"groundwater_depth_m", "water_table_depth"}, {"location", "lado_via"}, {"start_time", "hora_inicio"}
    };
    for (const AliasKey &alias : aliases) {
        const QString canonical = QString::fromLatin1(alias.canonical);
        if (!remoteRoot.contains(canonical)) continue;
        const QVariant value = remoteRoot.value(canonical);
        merged[QString::fromLatin1(alias.legacy)] = value.isNull() ? QVariant(QString()) : value;
    }
    // A position moved on Web: WGS84 UTM is canonical, so the local
    // geographic copy is recomputed from it instead of pointing elsewhere.
    if ((remoteRoot.contains(QStringLiteral("easting")) && remoteRoot.value(QStringLiteral("easting")) != m_header.value(QStringLiteral("easting")))
        || (remoteRoot.contains(QStringLiteral("northing")) && remoteRoot.value(QStringLiteral("northing")) != m_header.value(QStringLiteral("northing")))) {
        merged.remove(QStringLiteral("latitude"));
        merged.remove(QStringLiteral("longitude"));
        merged[QStringLiteral("datum")] = QStringLiteral("WGS84");
        merged[QStringLiteral("coordinate_source")] = QStringLiteral("WEB");
    }

    // Smart Document materialization belongs to the project workspace, but it is
    // not the project identity. Keep these values only as canonical document
    // routing metadata so portable/XLSX publication can follow the same project.
    const struct SmartKey { const char *remote; const char *local; } smartKeys[] = {
        {"document_node_id", "documentNodeId"},
        {"space_id", "documentSpaceId"},
        {"parent_node_id", "documentParentNodeId"},
        {"node_version", "documentNodeVersion"},
        {"name", "documentName"},
        {"lifecycle", "documentLifecycle"}
    };
    for (const SmartKey &key : smartKeys) {
        if (remoteRoot.contains(QString::fromLatin1(key.remote)))
            merged[QString::fromLatin1(key.local)] = remoteRoot.value(QString::fromLatin1(key.remote));
    }

    if (!editedMeanwhile && remoteRoot.contains(QStringLiteral("observations")))
        m_observaciones = remoteRoot.value(QStringLiteral("observations")).toString();

    // P3: deletions the server confirmed leave the pending list (tombstones).
    if (remoteRoot.contains(QStringLiteral("deleted_remote_strata_confirmed"))) {
        const QVariantList confirmed = remoteRoot.value(QStringLiteral("deleted_remote_strata_confirmed")).toList();
        QVariantList pending;
        for (const QVariant &value : merged.value(QStringLiteral("deleted_remote_strata")).toList())
            if (!confirmed.contains(value)) pending << value;
        if (pending.isEmpty()) merged.remove(QStringLiteral("deleted_remote_strata"));
        else merged[QStringLiteral("deleted_remote_strata")] = pending;
    }

    // The cloud zone is numeric. A local `zona` with the same number keeps its
    // band; a different number replaces it and keeps the band letter, which
    // depends on latitude, not on the zone. A NULL zone leaves `zona` alone.
    if (remoteRoot.contains(QStringLiteral("utm_zone"))) {
        const int remoteZone = utmZoneNumber(remoteRoot.value(QStringLiteral("utm_zone")).toString());
        const QString localZona = m_header.value(QStringLiteral("zona")).toString().trimmed().toUpper();
        if (remoteZone > 0 && utmZoneNumber(localZona) != remoteZone) {
            static const QRegularExpression bandPattern(QStringLiteral("([C-HJ-NP-X])$"));
            const QRegularExpressionMatch band = bandPattern.match(localZona);
            merged[QStringLiteral("zona")] = QString::number(remoteZone)
                + (band.hasMatch() ? band.captured(1) : utmBandForLatitude(merged.value(QStringLiteral("latitude"))));
        }
    }

    // Web stores groundwater as a nullable depth. When a remote row carries a
    // real depth, reconstruct Android's richer local state explicitly so the
    // canonicalizer does not erase the value as NO_EVALUADO. A remote NULL
    // cannot distinguish NO_EVALUADO from NO_ENCONTRADO, so a fresh remote load
    // conservatively uses NO_EVALUADO.
    if (remoteRoot.contains(QStringLiteral("groundwater_depth_m"))) {
        const QVariant water = remoteRoot.value(QStringLiteral("groundwater_depth_m"));
        bool okWater = false;
        const double waterDepth = water.toDouble(&okWater);
        if (water.isValid() && !water.isNull() && okWater && qIsFinite(waterDepth))
            merged[QStringLiteral("water_table_status")] = QStringLiteral("ENCONTRADO");
        else if (remoteRoot.contains(QStringLiteral("id")))
            merged[QStringLiteral("water_table_status")] = QStringLiteral("NO_EVALUADO");
    }

    // Archive is soft: remember what to restore to. Any other confirmed status
    // clears that memory.
    const QString incomingStatus = remoteRoot.value(QStringLiteral("status")).toString().trimmed().toUpper();
    if (incomingStatus == QLatin1String("ARCHIVADO") && status() != QLatin1String("ARCHIVADO"))
        merged[QStringLiteral("archived_from_status")] = status();
    else if (!incomingStatus.isEmpty() && incomingStatus != QLatin1String("ARCHIVADO"))
        merged.remove(QStringLiteral("archived_from_status"));

    // The server confirmed this state. Edits made while the request was in
    // flight are not part of it and keep the mirror PENDING.
    merged[QStringLiteral("sync_state")] = m_changedWhileSyncing
        ? QStringLiteral("PENDING") : QStringLiteral("SYNCED");
    m_changedWhileSyncing = false;

    if (editedMeanwhile) {
        // Acknowledgements advance the baseline without replacing edits made
        // while the network operation was running.
        const QVariantMap confirmed = merged;
        merged = m_header;
        for (const char *key : {"remoteCalicataId", "remote_calicata_id", "remoteRowVersion", "row_version",
                               "created_by", "created_at", "updated_at", "documentNodeId", "documentSpaceId",
                               "documentParentNodeId", "documentNodeVersion", "documentName", "documentLifecycle",
                               "smart_document_result_code", "deleted_remote_strata"}) {
            const QString k = QString::fromLatin1(key);
            if (confirmed.contains(k)) merged[k] = confirmed.value(k);
        }
        merged[QStringLiteral("sync_state")] = QStringLiteral("PENDING");
    }
    merged = canonicalHeader(merged);
    merged[QStringLiteral("calicataId")] = m_instanceId; // local tab identity, never remote id
    m_header = merged;

    if (replaceCortes)
        m_cortes = pureRows;

    updateDisplayName();
    emit dataChanged();
    if (!saveDraft()) {
        // Remote commit succeeded. Keep the document dirty so the next checkpoint
        // retries local persistence instead of pretending everything is clean.
        setDirty(true);
        return false;
    }
    clearError();
    return true;
}

void CalicataDocument::setUiState(const QVariantMap& v)
{
    if (m_closed) return;
    QVariantMap pure;
    QString error;
    if (!toPureMap(v, &pure, &error, QStringLiteral("uiState"))) {
        qWarning().noquote() << "[InGe+ M09] uiState rechazado:" << error;
        return;
    }
    if (m_uiState == pure) return;
    m_uiState = pure;
    markDirty();
    emit dataChanged();
}

void CalicataDocument::setCortes(const QVariantList& v)
{
    if (m_closed) return;

    QVariantList pureRows;
    pureRows.reserve(v.size());
    for (qsizetype i = 0; i < v.size(); ++i) {
        QVariant pureRow;
        QString error;
        const QString path = QStringLiteral("cortes[%1]").arg(i);
        if (!toPureVariant(v.at(i), &pureRow, &error, path)
            || pureRow.metaType().id() != QMetaType::QVariantMap) {
            if (error.isEmpty())
                error = path + QStringLiteral(" no es convertible a QVariantMap");
            qWarning().noquote() << "[InGe+ M09] cortes rechazados:" << error;
            return;
        }
        pureRows.append(pureRow.toMap());
    }

    if (m_cortes == pureRows) return;
    m_cortes = pureRows;
    markDirty();
    emit dataChanged();
}

void CalicataDocument::setObservaciones(const QString& v)
{
    if (m_closed || m_observaciones == v) return;
    m_observaciones = v;
    markDirty();
    emit dataChanged();
}

void CalicataDocument::setTimestamp(const QVariantMap& v)
{
    if (m_closed) return;
    QVariantMap pure;
    QString error;
    if (!toPureMap(v, &pure, &error, QStringLiteral("timestamp"))) {
        qWarning().noquote() << "[InGe+ M09] timestamp rechazado:" << error;
        return;
    }
    if (m_timestamp == pure) return;
    m_timestamp = pure;
    markDirty();
    emit dataChanged();
}

void CalicataDocument::setImages(const QVariantMap& v)
{
    if (m_closed) return;
    QVariantMap pure;
    QString error;
    if (!toPureMap(v, &pure, &error, QStringLiteral("images"))) {
        qWarning().noquote() << "[InGe+ M09] images rechazado:" << error;
        return;
    }
    if (m_images == pure) return;
    m_images = pure;
    markDirty();
    emit dataChanged();
}

void CalicataDocument::markDirty()
{
    if (m_closed || m_applyingCloudState) return;
    // Any content change after a confirmed sync leaves the cloud mirror behind.
    const QString sync = syncState();
    const bool fellBehind = sync == QLatin1String("SYNCED");
    if (fellBehind)
        m_header[QStringLiteral("sync_state")] = QStringLiteral("PENDING");
    else if (sync == QLatin1String("SYNCING"))
        m_changedWhileSyncing = true;
    setDirty(true);
    // Emitted after dirty=true so observers never re-import the form from it.
    if (fellBehind)
        emit dataChanged();
}

void CalicataDocument::setDirty(bool v)
{
    if (m_closed) return;
    if (m_dirty == v) return;
    m_dirty = v;
    emit dirtyChanged();
}

QString CalicataDocument::absPathFromUrl(const QUrl& url) const
{
    if (!url.isValid()) return {};
    if (url.isLocalFile()) return QDir::cleanPath(url.toLocalFile());
    return {}; // no escribible
}

QUrl CalicataDocument::urlFromAbs(const QString& abs) const
{
    if (abs.isEmpty()) return {};
    return QUrl::fromLocalFile(abs);
}

QString CalicataDocument::defaultUserRootDir() const
{
    const QString docs = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    QString root = cleanPathJoin(docs, m_projectsFolderLabel);
    QDir().mkpath(root);

    AuthSession* a = appContext() ? appContext()->auth() : nullptr;
    if (a && a->logged()) {
        const QString userFolder = a->localUserFolderName();
        root = cleanPathJoin(root, userFolder);
        QDir().mkpath(root);
    }
    return root;
}

QString CalicataDocument::defaultEditablesDir() const
{
    QString d = cleanPathJoin(defaultUserRootDir(), "Editables");
    QDir().mkpath(d);
    return d;
}

bool CalicataDocument::load(const QUrl& url)
{
    if (m_closed) return false;
    const QString abs = absPathFromUrl(url);
    if (abs.isEmpty()) return false;

    if (appContext()) {
        if (appContext()->isOpenFile(abs))
            return false;
    }

    QFile f(abs);
    if (!f.open(QIODevice::ReadOnly)) return false;

    const QByteArray raw = f.readAll();
    f.close();

    QJsonParseError pe{};
    const QJsonDocument doc = QJsonDocument::fromJson(raw, &pe);
    if (pe.error != QJsonParseError::NoError || !doc.isObject()) return false;

    const QVariantMap root = doc.object().toVariantMap();
    if (!applyFullJson(root)) return false;

    cleanupDraftPhotos();

    if (appContext()) appContext()->registerOpenFile(abs);

    m_fileUrl = url;
    emit fileUrlChanged();

    m_loadedFromDisk = true;
    // Adopt legacy discovered files into the persistent model once the base is known.
    for (int i = 1; i <= 3; ++i) {
        const QString key = QString("foto%1_path").arg(i);
        if (!m_images.contains(key)) {
            const auto image = cachedPhotoUrl(i);
            if (!image.isEmpty()) m_images[key] = relFromAbsInBase(image.toLocalFile());
        }
    }
    emit dataChanged();
    updateDisplayName();
    setDirty(false);

    // P0: si existe un draft mas reciente de esta misma instancia,
    // recuperarlo despues de establecer fileUrl.
    restoreDraftIfNewer();
    return true;
}

bool CalicataDocument::save()
{
    if (m_closed) return false;
    const QString abs = absPathFromUrl(m_fileUrl);
    if (abs.isEmpty()) return false;

    QDir().mkpath(QFileInfo(abs).absolutePath());

    // ✅ al guardar, crea estructura de fotos de esta ficha
    ensurePhotosFolderStructure();

    const QVariantMap root = buildFullJson();
    const QJsonDocument doc(QJsonObject::fromVariantMap(root));
    const QByteArray raw = doc.toJson(QJsonDocument::Indented);

    QSaveFile sf(abs);
    if (!sf.open(QIODevice::WriteOnly)) return false;
    if (sf.write(raw) != raw.size() || !sf.commit()) {
        setErrorString(sf.errorString());
        return false;
    }
    clearError();

    setDirty(false);
    // P0: un commit confirmado exitoso invalida cualquier draft pendiente.
    clearDraft();

    if (appContext())
        appContext()->notifyLocalFileModified(abs);

    updateDisplayName();
    return true;
}

bool CalicataDocument::saveAsDefaultLocation(const QString& stem)
{
    if (m_closed) return false;
    QString s = stem.trimmed();
    if (s.isEmpty()) s = "Calicata";
    s.replace(QRegularExpression(QStringLiteral(R"([^A-Za-z0-9._-]+)")), QStringLiteral("_"));

    QString dir = defaultEditablesDir();
    const QString projectId = QUuid(m_header.value("projectId").toString()).toString(QUuid::WithoutBraces);
    if (!projectId.isEmpty()) {
        dir = cleanPathJoin(dir, projectId);
        QDir().mkpath(dir);
    }
    const QString abs = cleanPathJoin(dir, s + "_" + m_instanceId + ".calicata.json");
    const QUrl target = QUrl::fromLocalFile(abs);

    // P0 autosave: el primer guardado de un scratch debe usar el flujo SaveAs
    // real para migrar tambien las fotos del staging privado al editable.
    if (absPathFromUrl(m_fileUrl) == QDir::cleanPath(abs))
        return save();

    return saveAs(target, true, true);
}

QVariantMap CalicataDocument::portableState(const QString &resourcesBase)
{
    auto state = buildFullJson();
    QVariantMap assets;
    const QStringList keys = {"foto1_path", "foto2_path", "foto3_path", "logo_mtc_path", "logo_proyecto_path"};
    for (const auto &key : keys) {
        QString path = m_images.value(key).toString();
        if (path.isEmpty() || path.startsWith("qrc:/") || path.startsWith(":")) continue;
        const QUrl url(path);
        if (url.isLocalFile()) path = url.toLocalFile();
        if (QDir::isRelativePath(path)) {
            const auto nearDocument = QDir(baseDirAbs()).filePath(path);
            path = QFileInfo::exists(nearDocument) ? nearDocument : QDir(resourcesBase).filePath(path);
        }
        QFile file(path);
        if (!file.open(QIODevice::ReadOnly)) {
            setErrorString(QStringLiteral("No se pudo preparar el recurso %1 para subir la ficha.").arg(key));
            return {};
        }
        assets[key] = QString::fromLatin1(file.readAll().toBase64());
    }
    state["embedded_resources"] = assets;
    state.remove("photos_cache");
    return state;
}

QVariantMap CalicataDocument::buildFullJson() const
{
    QVariantMap root = m_extraRoot;
    root["schema"] = "inge_calicata";
    root["version"] = 1;
    root["saved_at_utc"] = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);

    root["header"] = m_header;
    root["ui_state"] = m_uiState;
    root["cortes"] = m_cortes;
    root["observaciones"] = m_observaciones;
    {
        QVariantMap ts = m_timestamp;
        const QString contractual = m_header.value(QStringLiteral("project_full_name")).toString().trimmed();
        if (!contractual.isEmpty() && ts.value("proyecto").toString().isEmpty())
            ts["proyecto"] = contractual;
        root["timestamp"] = ts;
    }
    root["images"] = m_images;
    
    root["instance_id"] = m_instanceId;
    root["photo_draft_id"] = m_photoDraftId;

    QVariantMap photos;
    for (int i=1;i<=3;i++) {
        QUrl u = cachedPhotoUrl(i);
        if (u.isValid())
            photos[QString("foto%1").arg(i)] = u.toString();
    }
    root["photos_cache"] = photos;

    return root;
}

bool CalicataDocument::applyFullJson(const QVariantMap& root)
{
    // Portable online edits retain the original images, independently of the
    // source phone's private paths. Materialize before changing the document.
    auto restoredImages = root.value("images").toMap();
    const auto assets = root.value("embedded_resources").toMap();
    const QStringList keys = {"foto1_path", "foto2_path", "foto3_path", "logo_mtc_path", "logo_proyecto_path"};
    for (auto it = assets.cbegin(); it != assets.cend(); ++it) {
        if (!keys.contains(it.key())) continue;
        const auto bytes = QByteArray::fromBase64(it.value().toString().toLatin1(), QByteArray::AbortOnBase64DecodingErrors);
        if (bytes.isEmpty() || QImage::fromData(bytes).isNull()) {
            setErrorString(QStringLiteral("Recurso de imagen inválido: %1").arg(it.key()));
            return false;
        }
        const auto dir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/calicata-imports";
        if (!QDir().mkpath(dir)) return false;
        const auto path = dir + '/' + QUuid::createUuid().toString(QUuid::WithoutBraces) + ".img";
        QSaveFile file(path);
        if (!file.open(QIODevice::WriteOnly) || file.write(bytes) != bytes.size() || !file.commit()) {
            setErrorString(QStringLiteral("No se pudo recuperar la imagen %1").arg(it.key()));
            return false;
        }
        restoredImages[it.key()] = QUrl::fromLocalFile(path).toString();
    }
    m_extraRoot = root;
    m_extraRoot.remove("embedded_resources");
    const QUuid photoId(root.value("photo_draft_id").toString());
    if (!photoId.isNull()) m_photoDraftId = photoId.toString(QUuid::WithoutBraces);
    m_header = canonicalHeader(root.value("header").toMap());
    m_uiState = root.value("ui_state").toMap();
    m_cortes = root.value("cortes").toList();
    m_observaciones = root.value("observaciones").toString();

    m_timestamp = root.value("timestamp").toMap();
    m_images = restoredImages;
    
    {
        // Legacy files may carry their stable UUID only in the header.
        const QString rawId = root.value("instance_id").toString().trimmed();
        const QUuid restoredUuid = QUuid(rawId).isNull()
            ? QUuid(m_header.value("calicataId").toString()) : QUuid(rawId);
        if (!restoredUuid.isNull()) {
            const QString restoredId = restoredUuid.toString(QUuid::WithoutBraces);
            if (restoredId != m_instanceId) {
                m_instanceId = restoredId;
                emit instanceIdChanged();
            }
        }
    }

    m_header["calicataId"] = m_instanceId;

    updateDisplayName();
    emit dataChanged();
    return true;
}

bool CalicataDocument::backupIfExists(const QString& destPath) const
{
    if (!QFileInfo::exists(destPath)) return true;

    QFileInfo fi(destPath);
    const QString dir  = fi.absolutePath();
    const QString ext  = fi.suffix();
    const QString base = fi.completeBaseName();

    QRegularExpression re(R"((.*)_([0-9]{3})$)");
    QRegularExpressionMatch m = re.match(base);

    QString prefix = base;
    int cur = 1;
    if (m.hasMatch()) {
        prefix = m.captured(1);
        cur    = m.captured(2).toInt();
    }

    for (int n = qMax(2, cur + 1); n < 1000; ++n) {
        const QString num = QString::number(n).rightJustified(3, '0');
        const QString backupPath = QDir(dir).filePath(QString("%1_%2.%3").arg(prefix, num, ext));
        if (!QFileInfo::exists(backupPath)) {
            if (QFile::rename(destPath, backupPath)) return true;
            if (QFile::copy(destPath, backupPath)) { QFile::remove(destPath); return true; }
            return false;
        }
    }
    return false;
}

QString CalicataDocument::calicataStem() const
{
    const QString code = m_header.value("codigo").toString().trimmed();
    if (!code.isEmpty()) return code;

    const QString legacyCalicata = m_header.value("calicata").toString().trimmed();
    if (!legacyCalicata.isEmpty()) return legacyCalicata;

    const QString legacyPk = m_header.value("pk").toString().trimmed();
    if (!legacyPk.isEmpty()) return legacyPk;

    const QString legacyProgress = m_header.value("progresiva").toString().trimmed();
    if (!legacyProgress.isEmpty()) return legacyProgress;

    const QString n = m_header.value("nombre").toString().trimmed();
    if (!n.isEmpty()) return n;

    const QString abs = absPathFromUrl(m_fileUrl);
    if (!abs.isEmpty()) {
        QString base = QFileInfo(abs).completeBaseName(); // X.calicata
        if (base.endsWith(".calicata")) base.chop(QString(".calicata").size());
        if (!base.isEmpty()) return base;
    }

    return "Calicata";
}

QString CalicataDocument::baseDirAbs() const
{
    // ✅ IMPORTANTÍSIMO:
    // Si NO está guardado, NO hay base para resolver RELs ni cache => evita “fantasmas”
    const QString abs = absPathFromUrl(m_fileUrl);
    if (abs.isEmpty()) return {};
    return QFileInfo(abs).absolutePath();
}

QString CalicataDocument::photoTypeFolderName(int idx) const
{
    switch (idx) {
    case 1: return "Fotografia_Zona_de_Ejecucion_Calicata";
    case 2: return "Fotografia_Interior_Calicata";
    case 3: return "Fotografia_Acopios";
    default: return QString("Fotografia_%1").arg(idx);
    }
}

QString CalicataDocument::photoPrefixForIdx(int idx) const
{
    switch (idx) {
    case 1: return "Foto_ZE_Calicata";
    case 2: return "Foto_Calicata_Interior";
    case 3: return "Foto_Acopios";
    default: return QString("Foto_%1").arg(idx);
    }
}

QString CalicataDocument::draftPhotosRootAbs() const
{
    // Draft photos are user data, not an evictable cache.
    QString cache = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    if (cache.isEmpty() || m_photoDraftId.isEmpty())
        return {};

    return cleanPathJoin(cache, "calicata_photo_drafts/" + m_photoDraftId);
}

QString CalicataDocument::cachedPhotosTypeFolderAbs(int idx) const
{
    const QString base = baseDirAbs();
    if (!base.isEmpty())
        return cleanPathJoin(base, "fotos/" + calicataStem() + "/" + photoTypeFolderName(idx));

    const QString draftRoot = draftPhotosRootAbs();
    if (draftRoot.isEmpty()) return {};
    return cleanPathJoin(draftRoot, photoTypeFolderName(idx));
}

QString CalicataDocument::photoAbsPath001(int idx) const
{
    const QString folder = cachedPhotosTypeFolderAbs(idx);
    if (folder.isEmpty()) return {};
    return cleanPathJoin(folder, photoPrefixForIdx(idx) + "_001.jpg");
}

void CalicataDocument::ensurePhotosFolderStructure() const
{
    // Guardada: base/fotos/<stem>/<tipo>. Borrador: cache/<id>/<tipo>.
    for (int i=1;i<=3;i++) {
        const QString d = cachedPhotosTypeFolderAbs(i);
        if (!d.isEmpty()) QDir().mkpath(d);
    }
}

void CalicataDocument::cleanupDraftPhotos()
{
    // These files can still be referenced by saved documents and recovery drafts.
    // Deletion requires a reference-aware collector; navigation is not ownership proof.
}

QUrl CalicataDocument::cachedPhotosFolderUrl(int idx) const
{
    if (idx < 1 || idx > 3) return {};
    ensurePhotosFolderStructure();

    const QString folder = cachedPhotosTypeFolderAbs(idx);
    if (folder.isEmpty()) return {};
    return QUrl::fromLocalFile(folder);
}

QString CalicataDocument::resolveMaybeRelToAbs(const QString& pathOrUrl) const
{
    const QString s = pathOrUrl.trimmed();
    if (s.isEmpty()) return {};

    if (s.startsWith("file:", Qt::CaseInsensitive)) {
        const QUrl u(s);
        if (u.isLocalFile()) return QDir::cleanPath(u.toLocalFile());
    }

    if (QDir::isAbsolutePath(s))
        return QDir::cleanPath(s);

    const QString base = baseDirAbs();
    if (base.isEmpty()) return {};
    return cleanPathJoin(base, QDir::cleanPath(s));
}

QString CalicataDocument::relFromAbsInBase(const QString& abs) const
{
    const QString base = baseDirAbs();
    if (base.isEmpty()) return {}; // sin base => no guardes rel
    QDir d(base);
    QString rel = d.relativeFilePath(abs);
    rel = QDir::cleanPath(rel);
    rel.replace("\\", "/");
    return rel;
}

QUrl CalicataDocument::cachedPhotoUrl(int idx) const
{
    if (idx < 1 || idx > 3) return {};

    const QString key = QString("foto%1_path").arg(idx);

    // Si la key existe, respeta lo que diga (incluye vacío)
    if (m_images.contains(key)) {
        const QString val = m_images.value(key).toString().trimmed();
        if (val.isEmpty()) return {};
        const QString abs = resolveMaybeRelToAbs(val);
        if (!abs.isEmpty() && QFileInfo::exists(abs))
            return QUrl::fromLocalFile(abs);
        return {};
    }

    // ✅ NUEVO: si NO fue cargado de disco, NO hagas fallback (evita “fantasmas”)
    if (!m_loadedFromDisk) return {};

    // Compat: si fue cargado de disco (viejo) y existe _001, muéstralo
    if (!hasSavedFile()) return {};
    const QString p = photoAbsPath001(idx);
    if (!p.isEmpty() && QFile::exists(p)) return QUrl::fromLocalFile(p);
    return {};
}

QImage CalicataDocument::readImageFromUrl(const QUrl& url) const
{
    if (!url.isValid()) return {};

    if (url.isLocalFile()) {
        QImageReader r(url.toLocalFile());
        r.setAutoTransform(true);
        return r.read();
    }

    QFile f(url.toString());
    if (!f.open(QIODevice::ReadOnly))
        return {};

    QImageReader r(&f);
    r.setAutoTransform(true);
    return r.read();
}

QString CalicataDocument::findProjectMetaAbs(const QString& startDirAbs) const
{
    QString cur = QDir::cleanPath(startDirAbs);
    if (cur.isEmpty()) return {};

    // sube hasta raíz
    while (true) {
        const QString a = cleanPathJoin(cur, "ingep_project.json");
        const QString b = cleanPathJoin(cur, ".ingep_project.json");

        if (QFileInfo::exists(a)) return a;
        if (QFileInfo::exists(b)) return b;

        QDir d(cur);
        if (!d.cdUp()) break;
        const QString up = QDir::cleanPath(d.absolutePath());
        if (up == cur) break;
        cur = up;
    }
    return {};
}

QString CalicataDocument::inferProjectNameFromPath() const
{
    const QString base = baseDirAbs();
    if (base.isEmpty()) return {};

    const QString metaAbs = findProjectMetaAbs(base);
    if (metaAbs.isEmpty()) return {};

    QFile f(metaAbs);
    if (!f.open(QIODevice::ReadOnly)) return {};

    QJsonParseError pe{};
    const QJsonDocument jd = QJsonDocument::fromJson(f.readAll(), &pe);
    f.close();
    if (pe.error != QJsonParseError::NoError || !jd.isObject()) return {};

    const QVariantMap m = jd.object().toVariantMap();

    // Nombre contractual si el modelo de Proyecto ya lo proporciona.
    QString name;
    if (m.contains("fullName")) name = m.value("fullName").toString();
    else if (m.contains("nombreCompleto")) name = m.value("nombreCompleto").toString();
    else if (m.contains("projectName")) name = m.value("projectName").toString();
    else if (m.contains("name")) name = m.value("name").toString();
    else if (m.contains("nombre")) name = m.value("nombre").toString();
    else if (m.contains("proyecto")) name = m.value("proyecto").toString();

    return name.trimmed();
}

// Un solo renderer de fotografías: el de la derivada del editor (definido más abajo).
namespace {
QImage paintPhotoDerivative(const QImage &originalInput, const QVariantMap &edit, const QImage &logo);
}

// Receta inicial de una foto recién incorporada: "con datos" = rótulo de la ficha con
// los valores por defecto del editor; "sin datos" = misma foto sin rótulo. Se guarda
// como foto<n>_edit, de modo que el editor reabre exactamente lo que se guardó.
namespace {
// EXIF mínimo (APP1/TIFF) de la fotografía ORIGINAL: fecha/hora de captura y
// posición/altitud GPS de la propia foto. Solo lectura, con límites de bytes.
struct ExifReader {
    QByteArray t; bool le = true;
    bool ok(int off, int n) const { return off >= 0 && n >= 0 && off + n <= t.size(); }
    quint32 u16(int off) const {
        if (!ok(off, 2)) return 0;
        const uchar a = uchar(t[off]), b = uchar(t[off + 1]);
        return le ? quint32(a | (b << 8)) : quint32((a << 8) | b);
    }
    quint32 u32(int off) const { return le ? (u16(off) | (u16(off + 2) << 16)) : ((u16(off) << 16) | u16(off + 2)); }
    double rational(int off) const {
        const quint32 den = u32(off + 4);
        return ok(off, 8) && den != 0 ? double(u32(off)) / double(den) : qQNaN();
    }
    // Entradas de un IFD: tag → desplazamiento del campo valor/offset.
    QHash<quint32, int> ifd(int off) const {
        QHash<quint32, int> out;
        const int count = int(u16(off));
        for (int i = 0; i < count && i < 512; ++i) {
            const int e = off + 2 + i * 12;
            if (!ok(e, 12)) break;
            out.insert(u16(e), e + 8);
        }
        return out;
    }
};

QVariantMap readPhotoExif(const QString &path)
{
    QVariantMap out;
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return out;
    const QByteArray head = file.read(256 * 1024);
    if (head.size() < 4 || uchar(head[0]) != 0xFF || uchar(head[1]) != 0xD8) return out;
    int pos = 2;
    ExifReader r;
    while (pos + 4 <= head.size() && uchar(head[pos]) == 0xFF) {
        const uchar marker = uchar(head[pos + 1]);
        const int len = (uchar(head[pos + 2]) << 8) | uchar(head[pos + 3]);
        if (len < 2 || marker == 0xDA) break;
        if (marker == 0xE1 && head.mid(pos + 4, 6) == QByteArray("Exif\0\0", 6)) {
            r.t = head.mid(pos + 10, len - 8);
            break;
        }
        pos += 2 + len;
    }
    if (r.t.size() < 8) return out;
    r.le = r.t.startsWith("II");
    const QHash<quint32, int> ifd0 = r.ifd(int(r.u32(4)));
    if (ifd0.contains(0x8769)) {
        const QHash<quint32, int> exif = r.ifd(int(r.u32(ifd0.value(0x8769))));
        for (const quint32 tag : {quint32(0x9003), quint32(0x9004)}) {
            if (!exif.contains(tag)) continue;
            const int at = int(r.u32(exif.value(tag)));
            if (!r.ok(at, 19)) continue;
            const QDateTime when = QDateTime::fromString(QString::fromLatin1(r.t.mid(at, 19)),
                                                         QStringLiteral("yyyy:MM:dd HH:mm:ss"));
            if (when.isValid()) { out[QStringLiteral("captured_at")] = when.toString(QStringLiteral("yyyy-MM-ddTHH:mm:ss")); break; }
        }
    }
    if (ifd0.contains(0x8825)) {
        const QHash<quint32, int> gps = r.ifd(int(r.u32(ifd0.value(0x8825))));
        const auto dms = [&](quint32 tag, quint32 refTag, char negative) {
            if (!gps.contains(tag)) return qQNaN();
            const int at = int(r.u32(gps.value(tag)));
            const double v = r.rational(at) + r.rational(at + 8) / 60.0 + r.rational(at + 16) / 3600.0;
            const bool neg = gps.contains(refTag) && r.ok(gps.value(refTag), 1) && r.t[gps.value(refTag)] == negative;
            return neg ? -v : v;
        };
        const double lat = dms(0x0002, 0x0001, 'S'), lon = dms(0x0004, 0x0003, 'W');
        if (std::isfinite(lat) && std::isfinite(lon) && qAbs(lat) <= 90 && qAbs(lon) <= 180 && !(lat == 0 && lon == 0)) {
            out[QStringLiteral("latitude")] = lat;
            out[QStringLiteral("longitude")] = lon;
        }
        if (gps.contains(0x0006)) {
            double alt = r.rational(int(r.u32(gps.value(0x0006))));
            if (gps.contains(0x0005) && r.ok(gps.value(0x0005), 1) && uchar(r.t[gps.value(0x0005)]) == 1) alt = -alt;
            if (std::isfinite(alt) && alt > -500 && alt < 9000) out[QStringLiteral("altitude")] = alt;
        }
    }
    return out;
}

// Metadatos PROPIOS de la foto en su captura: EXIF si existe; si no, la hora en
// que la app recibió la foto (momento de la captura en la app), nunca la hora
// de una composición posterior.
QVariantMap photoCaptureMeta(const QString &originalPath, const QDateTime &receivedAt)
{
    QVariantMap capture = readPhotoExif(originalPath);
    // Hora del sistema fijada UNA vez para esta foto: es la hora del rótulo
    // cuando la ficha no tiene hora manual. Regenerar no la cambia.
    capture[QStringLiteral("system_time")] = receivedAt.toString(QStringLiteral("HH:mm:ss"));
    capture[QStringLiteral("system_at")] = receivedAt.toString(QStringLiteral("yyyy-MM-ddTHH:mm:ss"));
    if (capture.value(QStringLiteral("captured_at")).toString().isEmpty()) {
        capture[QStringLiteral("captured_at")] = receivedAt.toString(QStringLiteral("yyyy-MM-ddTHH:mm:ss"));
        capture[QStringLiteral("captured_source")] = QStringLiteral("APP");
    } else {
        capture[QStringLiteral("captured_source")] = QStringLiteral("EXIF");
    }
    return capture;
}

// Posición del dispositivo en el momento de la captura (solo si la app ya tenía
// un fix fresco; nunca se enciende el GPS para esto). Se acepta únicamente si
// el archivo acaba de crearse (cámara) y completa lo que el EXIF no trae.
void mergeCaptureLocation(QVariantMap &capture, const QVariantMap &location, const QString &sourcePath)
{
    if (location.isEmpty()) return;
    const QFileInfo info(sourcePath);
    const QDateTime now = QDateTime::currentDateTime();
    if (!info.exists() || qAbs(info.lastModified().secsTo(now)) > 180) return;
    const qint64 fixMs = location.value(QStringLiteral("timestampMs")).toLongLong();
    if (fixMs <= 0 || qAbs(QDateTime::currentMSecsSinceEpoch() - fixMs) > 120000) return;
    bool okAlt = false, okLat = false, okLon = false;
    const double alt = location.value(QStringLiteral("altitude")).toDouble(&okAlt);
    const double lat = location.value(QStringLiteral("latitude")).toDouble(&okLat);
    const double lon = location.value(QStringLiteral("longitude")).toDouble(&okLon);
    if (!capture.contains(QStringLiteral("altitude")) && okAlt && std::isfinite(alt) && alt > -500 && alt < 9000) {
        capture[QStringLiteral("altitude")] = alt;
        capture[QStringLiteral("altitude_source")] = QStringLiteral("DEVICE");
    }
    if (!capture.contains(QStringLiteral("latitude")) && okLat && okLon && std::isfinite(lat) && std::isfinite(lon)
        && qAbs(lat) <= 90 && qAbs(lon) <= 180) {
        capture[QStringLiteral("latitude")] = lat;
        capture[QStringLiteral("longitude")] = lon;
    }
}

// Hora manual de la ficha (header.hora_inicio, opcional): "HH:mm:ss" o "HH:mm".
QTime sheetTime(const QVariantMap &header)
{
    const QString text = header.value(QStringLiteral("hora_inicio")).toString().trimmed();
    QTime time = QTime::fromString(text, QStringLiteral("HH:mm:ss"));
    if (!time.isValid()) time = QTime::fromString(text, QStringLiteral("HH:mm"));
    return time;
}

// Hora de respaldo de UNA foto: la del sistema fijada al recibirla. Fotos
// anteriores sin ese dato: la hora en que la app la recibió (captured APP).
QString photoSystemTime(const QVariantMap &capture)
{
    const QString fixed = capture.value(QStringLiteral("system_time")).toString().trimmed();
    if (QTime::fromString(fixed, QStringLiteral("HH:mm:ss")).isValid()) return fixed;
    if (capture.value(QStringLiteral("captured_source")).toString() == QLatin1String("APP")) {
        const QDateTime received = QDateTime::fromString(capture.value(QStringLiteral("captured_at")).toString(), Qt::ISODate);
        if (received.isValid()) return received.toString(QStringLiteral("HH:mm:ss"));
    }
    return {};
}

// Fecha y hora DOCUMENTALES del rótulo de la foto:
//   fecha = fecha de la ficha (fecha_inicio); sin fecha en la ficha, la de captura;
//   hora  = hora manual de la ficha (hora_inicio) si existe; si no, la hora del
//           sistema fijada para ESTA foto (system_time), nunca la de una regeneración.
// El EXIF (captured_at) se conserva como metadato y no manda sobre la ficha.
// Sin altitud de la foto la línea de altitud queda vacía (no se usa la cota).
void applyPhotoCapture(QVariantMap &meta, const QVariantMap &capture, const QVariantMap &header)
{
    const QDate sheetDate = QDate::fromString(
        header.value(QStringLiteral("fecha_inicio"), header.value(QStringLiteral("start_date"))).toString().trimmed().left(10),
        QStringLiteral("yyyy-MM-dd"));
    const QDateTime when = QDateTime::fromString(capture.value(QStringLiteral("captured_at")).toString(), Qt::ISODate);
    meta[QStringLiteral("date")] = sheetDate.isValid() ? sheetDate.toString(QStringLiteral("dd/MM/yyyy"))
        : when.isValid() ? when.toString(QStringLiteral("dd/MM/yyyy")) : QString();
    const QTime manual = sheetTime(header);
    meta[QStringLiteral("time")] = manual.isValid() ? manual.toString(QStringLiteral("HH:mm:ss")) : photoSystemTime(capture);
    meta[QStringLiteral("time_source")] = manual.isValid() ? QStringLiteral("SHEET") : QStringLiteral("PHOTO_SYSTEM");
    // Altitud propia de la captura (EXIF/GPS, normalmente elipsoidal): solo
    // metadato; el rótulo usa la cota de la ficha (photoSheetMetadata).
    bool okAlt = false;
    const double alt = capture.value(QStringLiteral("altitude")).toDouble(&okAlt);
    if (okAlt && std::isfinite(alt)) meta[QStringLiteral("photo_altitude")] = QString::number(qRound(alt));
    // Posición propia de la foto: se conserva como metadato, pero el rótulo
    // muestra las coordenadas de la calicata (así lo hace C-AA-01).
    bool okLat = false, okLon = false;
    const double lat = capture.value(QStringLiteral("latitude")).toDouble(&okLat);
    const double lon = capture.value(QStringLiteral("longitude")).toDouble(&okLon);
    if (okLat && okLon) {
        meta[QStringLiteral("photo_latitude")] = QString::number(lat, 'f', 7);
        meta[QStringLiteral("photo_longitude")] = QString::number(lon, 'f', 7);
    }
}
} // namespace

QVariantMap CalicataDocument::defaultPhotoEdit(bool withData) const
{
    QVariantMap edit;
    edit[QStringLiteral("withMetadata")] = withData;
    if (withData) edit[QStringLiteral("metadata")] = photoSheetMetadata();
    edit[QStringLiteral("logo")] = QVariantMap{{QStringLiteral("enabled"), false}, {QStringLiteral("source"), QStringLiteral("PROJECT")}};
    return edit;
}

QUrl CalicataDocument::persistStampedPhotoToCache(int idx, const QUrl& sourceImageUrl)
{
    return persistPhoto(idx, sourceImageUrl, true);
}

bool CalicataDocument::commitPhotoImages(const QVariantMap &images)
{
    const auto previous = m_images;
    markDirty(); // Observers must never see a changed image in a clean document.
    m_images = images;
    if (!saveDraft()) {
        m_images = previous;
        // Keep dirty/error visible; neither the old JSON nor its image was replaced.
        emit dataChanged();
        return false;
    }
    emit dataChanged();
    return true;
}

QUrl CalicataDocument::persistPhoto(int idx, const QUrl& sourceImageUrl, bool withStamp)
{
    if (m_closed || idx < 1 || idx > 3) return {};
    // Ruta rápida (cámara / galería = archivo local): en el hilo de UI solo se valida la
    // cabecera y se copia el original byte a byte. Decodificar la foto completa, pintar el
    // rótulo y codificar el JPEG (segundos en gama media) va al pool, como la derivada del
    // editor; el commit local ocurre después en el hilo principal y se avisa con
    // photoPersisted(). El valor devuelto (no vacío) solo significa "aceptada".
    if (sourceImageUrl.isLocalFile()) {
        const QFileInfo sourceInfo(sourceImageUrl.toLocalFile());
        QImageReader probe(sourceInfo.absoluteFilePath());
        const QString folder = cachedPhotosTypeFolderAbs(idx);
        if (!probe.canRead()) {
            setErrorString(QStringLiteral("La imagen seleccionada no es válida."));
            return {};
        }
        if (folder.isEmpty() || !QDir().mkpath(folder)) {
            setErrorString(QStringLiteral("No se pudo preparar el almacenamiento de fotografías."));
            return {};
        }
        const QString suffix = sourceInfo.suffix().toLower();
        const QString ext = (suffix == QLatin1String("png") || suffix == QLatin1String("webp")) ? suffix : QStringLiteral("jpg");
        const QString originalPath = cleanPathJoin(folder, photoPrefixForIdx(idx) + QStringLiteral("_original_")
                                                   + QUuid::createUuid().toString(QUuid::WithoutBraces) + QLatin1Char('.') + ext);
        if (QFile::copy(sourceInfo.absoluteFilePath(), originalPath)) {
            const QString path = cleanPathJoin(folder, photoPrefixForIdx(idx) + "_"
                + QUuid::createUuid().toString(QUuid::WithoutBraces) + ".jpg");
            QVariantMap capture = photoCaptureMeta(originalPath, QDateTime::currentDateTime());
            mergeCaptureLocation(capture, m_nextCaptureLocation, sourceInfo.absoluteFilePath());
            m_nextCaptureLocation.clear();
            QVariantMap initialEdit = defaultPhotoEdit(withStamp);
            if (withStamp) {
                QVariantMap meta = initialEdit.value(QStringLiteral("metadata")).toMap();
                applyPhotoCapture(meta, capture, m_header);
                initialEdit[QStringLiteral("metadata")] = meta;
            }
            const int token = ++m_photoPersistSerial;
            m_photoPersistLatest[idx] = token;
            QPointer<CalicataDocument> self(this);
            QThreadPool::globalInstance()->start([self, idx, token, withStamp, initialEdit, originalPath, path, capture]() {
                QImageReader reader(originalPath);
                reader.setAutoTransform(true);   // EXIF orientation; original bytes untouched
                const QImage source = reader.read();
                QString error;
                if (source.isNull()) {
                    error = QStringLiteral("La imagen seleccionada no es válida.");
                } else {
                    const QImage image = withStamp ? paintPhotoDerivative(source, initialEdit, QImage()) : source;
                    QSaveFile output(path);
                    if (image.isNull() || !output.open(QIODevice::WriteOnly) || !image.save(&output, "JPG", 90) || !output.commit())
                        error = QStringLiteral("No se pudo guardar la fotografía.");
                }
                QMetaObject::invokeMethod(QCoreApplication::instance(), [self, idx, token, initialEdit, originalPath, path, error, capture]() {
                    // Documento cerrado o reemplazado por otra importación del mismo slot:
                    // este resultado ya no es el vigente; no se toca la ficha.
                    if (!self || self->m_closed || self->m_photoPersistLatest.value(idx) != token) {
                        QFile::remove(path);
                        QFile::remove(originalPath);
                        return;
                    }
                    self->m_photoPersistLatest.remove(idx);
                    if (!error.isEmpty()) {
                        QFile::remove(originalPath);
                        self->setErrorString(error);
                        emit self->photoPersisted(idx, QUrl(), error);
                        return;
                    }
                    const bool saved = self->hasSavedFile();
                    auto images = self->m_images;
                    images["storage"] = saved ? "editable_jpg_v2" : "editable_jpg_v2_pending";
                    images[QString("foto%1_path").arg(idx)] = saved ? self->relFromAbsInBase(path) : path;
                    images[QString("foto%1_original_path").arg(idx)] = saved ? self->relFromAbsInBase(originalPath) : originalPath;
                    images[QString("foto%1_edit").arg(idx)] = initialEdit;
                    images[QString("foto%1_capture").arg(idx)] = capture;
                    images[QString("foto%1_active_local_version").arg(idx)] = QString();
                    images[QString("foto%1_sync").arg(idx)] = QStringLiteral("PENDING");
                    images[QString("foto%1_pending_op").arg(idx)] = QStringLiteral("PUBLISH");
                    images[QString("foto%1_new_original").arg(idx)] = true;
                    if (!self->commitPhotoImages(images)) {
                        emit self->photoPersisted(idx, QUrl(), self->errorString());
                        return;
                    }
                    if (appContext()) appContext()->notifyLocalFileModified(path);
                    emit self->photoPersisted(idx, self->cachedPhotoUrl(idx), QString());
                }, Qt::QueuedConnection);
            });
            return QUrl::fromLocalFile(originalPath);
        }
        // Sin copia del original: ruta síncrona de siempre (abajo).
    }
    const QImage source = readImageFromUrl(sourceImageUrl);
    if (source.isNull()) {
        setErrorString(QStringLiteral("La imagen seleccionada no es válida."));
        return {};
    }
    // "Con datos" usa el MISMO pipeline que la vista previa y la derivada del editor.
    const QVariantMap initialEdit = defaultPhotoEdit(withStamp);
    const QImage image = withStamp ? paintPhotoDerivative(source, initialEdit, QImage()) : source;
    if (image.isNull()) return {};
    const QString folder = cachedPhotosTypeFolderAbs(idx);
    if (folder.isEmpty() || !QDir().mkpath(folder)) {
        setErrorString(QStringLiteral("No se pudo preparar el almacenamiento de fotografías."));
        return {};
    }
    // P1: the selected file is kept byte for byte as the immutable original.
    // foto<n>_path stays the publishable image (stamped or not) for existing
    // consumers; a stamp is never burnt into the only copy.
    QString originalPath;
    if (sourceImageUrl.isLocalFile()) {
        const QFileInfo sourceInfo(sourceImageUrl.toLocalFile());
        const QString suffix = sourceInfo.suffix().toLower();
        const QString ext = (suffix == QLatin1String("png") || suffix == QLatin1String("webp")) ? suffix : QStringLiteral("jpg");
        originalPath = cleanPathJoin(folder, photoPrefixForIdx(idx) + QStringLiteral("_original_")
                                     + QUuid::createUuid().toString(QUuid::WithoutBraces) + QLatin1Char('.') + ext);
        if (!QFile::copy(sourceInfo.absoluteFilePath(), originalPath)) originalPath.clear();
    }
    // Immutable file per replacement: even a failed JSON commit preserves oldPhoto.
    const QString path = cleanPathJoin(folder, photoPrefixForIdx(idx) + "_"
        + QUuid::createUuid().toString(QUuid::WithoutBraces) + ".jpg");
    QSaveFile output(path);
    if (!output.open(QIODevice::WriteOnly) || !image.save(&output, "JPG", 90) || !output.commit()) {
        setErrorString(QStringLiteral("No se pudo guardar la fotografía: ") + output.errorString());
        return {};
    }
    auto images = m_images;
    images["storage"] = hasSavedFile() ? "editable_jpg_v2" : "editable_jpg_v2_pending";
    images[QString("foto%1_path").arg(idx)] = hasSavedFile() ? relFromAbsInBase(path) : path;
    const QString originalStored = originalPath.isEmpty() ? path : originalPath;
    images[QString("foto%1_original_path").arg(idx)] = hasSavedFile() ? relFromAbsInBase(originalStored) : originalStored;
    // A new original starts a new slot history; previous versions stay listed.
    // The recipe that produced foto<n>_path (with/without data) is the editor's start.
    images[QString("foto%1_edit").arg(idx)] = initialEdit;
    QVariantMap syncCapture = photoCaptureMeta(originalStored, QDateTime::currentDateTime());
    if (sourceImageUrl.isLocalFile())
        mergeCaptureLocation(syncCapture, m_nextCaptureLocation, sourceImageUrl.toLocalFile());
    m_nextCaptureLocation.clear();
    images[QString("foto%1_capture").arg(idx)] = syncCapture;
    images[QString("foto%1_active_local_version").arg(idx)] = QString();
    images[QString("foto%1_sync").arg(idx)] = QStringLiteral("PENDING");
    images[QString("foto%1_pending_op").arg(idx)] = QStringLiteral("PUBLISH");
    images[QString("foto%1_new_original").arg(idx)] = true;
    if (!commitPhotoImages(images)) return {};
    if (appContext()) appContext()->notifyLocalFileModified(path);
    // Mismo aviso que la ruta asíncrona: QML encola la publicación en un solo lugar.
    QPointer<CalicataDocument> self(this);
    QMetaObject::invokeMethod(this, [self, idx]() {
        if (self && !self->m_closed) emit self->photoPersisted(idx, self->cachedPhotoUrl(idx), QString());
    }, Qt::QueuedConnection);
    return cachedPhotoUrl(idx);
}

bool CalicataDocument::setPhotoFromCache(int idx, const QUrl& cachedFileUrl)
{
    return !persistPhoto(idx, cachedFileUrl, false).isEmpty();
}

bool CalicataDocument::copyPhotosFrom(CalicataDocument *source)
{
    if (m_closed) return false;
    if (!source || source == this || source->closed() || hasSavedFile())
        return false;

    bool copiedAny = false;
    QVariantMap im = m_images;
    ensurePhotosFolderStructure();

    for (int idx = 1; idx <= 3; ++idx) {
        const QUrl sourceUrl = source->cachedPhotoUrl(idx);
        if (!sourceUrl.isValid() || !sourceUrl.isLocalFile())
            continue;

        const QString src = QDir::cleanPath(sourceUrl.toLocalFile());
        const QString dst = photoAbsPath001(idx);
        if (src.isEmpty() || dst.isEmpty() || !QFileInfo::exists(src))
            continue;

        QDir().mkpath(QFileInfo(dst).absolutePath());
        QFile::remove(dst);
        if (!QFile::copy(src, dst))
            continue;

        im[QString("foto%1_path").arg(idx)] = QDir::cleanPath(dst);
        copiedAny = true;
    }

    if (copiedAny) {
        im["storage"] = "editable_jpg_v2_pending";
        m_images = im;
        emit dataChanged();
        markDirty();
    }
    return copiedAny;
}

void CalicataDocument::clearPhoto(int idx)
{
    if (m_closed) return;
    if (idx < 1 || idx > 3) return;

    QVariantMap im = m_images;
    im["storage"] = hasSavedFile() ? "editable_jpg_v2" : "editable_jpg_v2_pending";
    im[QString("foto%1_path").arg(idx)] = QString();
    commitPhotoImages(im); // Only explicit deletion changes the slot; retain file for older saves.

}

void CalicataDocument::updateDisplayName()
{
    QString n = calicataStem();
    if (n.isEmpty()) n = "Calicata";
    if (m_displayName == n) return;
    m_displayName = n;
    emit displayNameChanged();
}

void CalicataDocument::resetNew()
{
    if (m_closed) return;
    const QString oldAbs = absPathFromUrl(m_fileUrl);
    if (!oldAbs.isEmpty() && appContext())
        appContext()->unregisterOpenFile(oldAbs);

    m_fileUrl = QUrl();
    emit fileUrlChanged();

    cleanupDraftPhotos();

    m_instanceId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    m_photoDraftId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    emit instanceIdChanged();
    m_header = canonicalHeader(activeProject());
    m_header["calicataId"] = m_instanceId;
    m_changedWhileSyncing = false;
    stampLocalAuthorship();
    m_extraRoot.clear();
    m_uiState.clear();
    m_cortes.clear();
    m_observaciones.clear();
    m_timestamp.clear();
    m_images.clear();

    m_loadedFromDisk = false;   // ✅ importante
    updateDisplayName();
    setDirty(false);
    emit dataChanged();
}

bool CalicataDocument::saveAs(const QUrl& url, bool overwrite, bool copyPhotos)
{
    if (m_closed) return false;
    if (!url.isValid() || !url.isLocalFile()) return false;

    QString abs = QDir::cleanPath(url.toLocalFile());
    if (abs.isEmpty()) return false;

    QFileInfo fi(abs);
    const QString fixedName = ensureCalicataExt(fi.fileName());
    abs = QDir(fi.absolutePath()).absoluteFilePath(fixedName);
    abs = QDir::cleanPath(abs);

    if (QFileInfo::exists(abs) && !overwrite) return false;
    if (appContext() && appContext()->isOpenFile(abs)) return false;

    // recopila fotos actuales (ABS) antes de cambiar base
    QString oldFotoAbs[4];
    for (int i=1;i<=3;i++) {
        QUrl u = cachedPhotoUrl(i);
        if (u.isValid() && u.isLocalFile())
            oldFotoAbs[i] = QDir::cleanPath(u.toLocalFile());
    }

    const QUrl oldFileUrl = m_fileUrl;
    const QVariantMap oldImages = m_images;
    const QString oldAbsFile = absPathFromUrl(m_fileUrl);
    if (!oldAbsFile.isEmpty() && appContext())
        appContext()->unregisterOpenFile(oldAbsFile);

    m_fileUrl = QUrl::fromLocalFile(abs);
    emit fileUrlChanged();

    if (appContext())
        appContext()->registerOpenFile(abs);

    // ahora sí existe baseDirAbs()
    ensurePhotosFolderStructure();

    QStringList copiedDestinations;
    bool photosCopied = true;
    if (copyPhotos) {
        for (int i=1;i<=3;i++) {
            const QString src = oldFotoAbs[i];
            if (src.isEmpty() || !QFileInfo::exists(src)) continue;

            const QString dst = photoAbsPath001(i);
            if (dst.isEmpty()) {
                photosCopied = false;
                break;
            }

            QDir().mkpath(QFileInfo(dst).absolutePath());
            if (!backupIfExists(dst)) {
                photosCopied = false;
                break;
            }

            if (src != dst) {
                QFile::remove(dst);
                if (!QFile::copy(src, dst)) {
                    photosCopied = false;
                    break;
                }
                copiedDestinations.append(dst);
            }

            QVariantMap im = m_images;
            im["storage"] = "editable_jpg_v2";
            im[QString("foto%1_path").arg(i)] = relFromAbsInBase(dst);
            m_images = im;
        }
        if (photosCopied)
            emit dataChanged();
    }

    if (!photosCopied) {
        for (const QString &path : copiedDestinations)
            QFile::remove(path);
        if (appContext())
            appContext()->unregisterOpenFile(abs);
        m_fileUrl = oldFileUrl;
        m_images = oldImages;
        if (!oldAbsFile.isEmpty() && appContext())
            appContext()->registerOpenFile(oldAbsFile);
        emit fileUrlChanged();
        emit dataChanged();
        updateDisplayName();
        return false;
    }

    // este documento ya es “nuevo”, no necesariamente cargado de disco
    // mantenemos m_loadedFromDisk como estaba (si era true, ok; si era false, ok)

    updateDisplayName();
    const bool saved = save();
    if (saved) {
        cleanupDraftPhotos();
    } else {
        for (const QString &path : copiedDestinations)
            QFile::remove(path);
        if (appContext())
            appContext()->unregisterOpenFile(abs);
        m_fileUrl = oldFileUrl;
        m_images = oldImages;
        if (!oldAbsFile.isEmpty() && appContext())
            appContext()->registerOpenFile(oldAbsFile);
        emit fileUrlChanged();
        emit dataChanged();
        updateDisplayName();
    }
    return saved;
}

QString CalicataDocument::inferredProjectName() const
{
    // Ya no se infiere desde la carpeta: el nombre del proyecto es un dato
    // manual/importado de la ficha (header.project_full_name).
    return m_header.value(QStringLiteral("project_full_name")).toString().trimmed();
}

// --- NEW DRAFT IMPLEMENTATIONS ---

QString CalicataDocument::getDraftId() const
{
    return m_instanceId;
}

QString CalicataDocument::getDraftPath() const
{
    // P0: registro persistente central por usuario. Una ficha sin fileUrl
    // sigue siendo descubrible despues de recrear el proceso.
    const QString base = defaultUserRootDir();
    if (base.isEmpty() || getDraftId().isEmpty()) return {};
    return cleanPathJoin(base, ".drafts/" + getDraftId() + ".json");
}

bool CalicataDocument::writeDraftJson(const QString& path)
{
    if (path.isEmpty()) return false;
    QDir().mkpath(QFileInfo(path).absolutePath());

    for (int i = 1; i <= 3; ++i) {
        const auto key = QString("foto%1_path").arg(i);
        if (!m_images.value(key).toString().isEmpty() && cachedPhotoUrl(i).isEmpty()) {
            setErrorString(QStringLiteral("No se encuentra la fotografía %1; el borrador anterior se conserva.").arg(i));
            return false;
        }
    }

    // Migrate old cache references by copying, keeping the old file intact.
    // Commit the JSON only after every referenced photo is durable.
    if (!hasSavedFile()) {
        QVariantMap images = m_images;
        for (int i = 1; i <= 3; ++i) {
            const QString key = QStringLiteral("foto%1_path").arg(i);
            if (images.value(key).toString().isEmpty()) continue;
            const QString source = cachedPhotoUrl(i).toLocalFile();
            const QString folder = cachedPhotosTypeFolderAbs(i);
            const QString destination = isInsideDir(source, folder) ? source
                : cleanPathJoin(folder, photoPrefixForIdx(i) + "_"
                    + QUuid::createUuid().toString(QUuid::WithoutBraces) + ".jpg");
            if (source.isEmpty() || destination.isEmpty()) {
                setErrorString(QStringLiteral("No se encuentra la fotografía %1 del borrador.").arg(i));
                return false;
            }
            if (QDir::cleanPath(source) != QDir::cleanPath(destination)) {
                QDir().mkpath(QFileInfo(destination).absolutePath());
                QFile input(source);
                QSaveFile output(destination);
                if (!input.open(QIODevice::ReadOnly) || !output.open(QIODevice::WriteOnly)) {
                    setErrorString(QStringLiteral("No se pudo conservar la fotografía %1.").arg(i));
                    return false;
                }
                const QByteArray bytes = input.readAll();
                if (input.error() != QFileDevice::NoError || output.write(bytes) != bytes.size() || !output.commit()) {
                    setErrorString(QStringLiteral("Falló la copia de la fotografía %1.").arg(i));
                    return false;
                }
            }
            images[key] = destination;
        }
        m_images = images;
    }

    QVariantMap root = buildFullJson();
    root["instance_id"] = m_instanceId;
    root["draft_file_url"] = m_fileUrl.toString();
    root["draft_saved_at_utc"] = QDateTime::currentDateTimeUtc().toString(Qt::ISODate);

    const QJsonDocument doc(QJsonObject::fromVariantMap(root));
    const QByteArray raw = doc.toJson(QJsonDocument::Indented);

    QSaveFile sf(path);
    if (!sf.open(QIODevice::WriteOnly)) {
        setErrorString(sf.errorString());
        return false;
    }
    if (sf.write(raw) != raw.size()) {
        setErrorString(sf.errorString());
        sf.cancelWriting();
        return false;
    }
    if (!sf.commit()) {
        setErrorString(sf.errorString());
        return false;
    }
    clearError();
    setDirty(false);
    return true;
}

bool CalicataDocument::saveDraft()
{
    if (m_closed || m_instanceId.isEmpty()) return false;
    const QString path = getDraftPath();
    if (path.isEmpty()) return false;
    return writeDraftJson(path);
}

void CalicataDocument::clearDraft()
{
    const QString path = getDraftPath();
    if (!path.isEmpty() && QFileInfo::exists(path))
        QFile::remove(path);
}

bool CalicataDocument::restoreDraftIfNewer()
{
    const QString path = getDraftPath();
    if (path.isEmpty() || !QFileInfo::exists(path)) return false;

    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) return false;

    QJsonParseError pe{};
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &pe);
    f.close();
    if (pe.error != QJsonParseError::NoError || !doc.isObject())
        return false;

    const QVariantMap root = doc.object().toVariantMap();
    const QString storedRawId = root.value("instance_id").toString().trimmed();
    const QUuid storedUuid(storedRawId);
    if (storedUuid.isNull()) return false;
    const QString storedId = storedUuid.toString(QUuid::WithoutBraces);
    if (storedId != m_instanceId)
        return false;

    const QFileInfo draftInfo(path);
    if (hasSavedFile()) {
        const QString abs = absPathFromUrl(m_fileUrl);
        if (!abs.isEmpty() && QFileInfo::exists(abs)) {
            const QFileInfo confirmedInfo(abs);
            if (draftInfo.lastModified() <= confirmedInfo.lastModified())
                return false;
        }
    }

    if (!applyFullJson(root))
        return false;

    setDirty(true);
    return true;
}

QVariantList CalicataDocument::listDrafts() const
{
    return scanDrafts(false);
}

// includeArchived=false is draft recovery: only drafts newer than their
// confirmed file, archived ones hidden. includeArchived=true is the local
// mirror of every calicata, used for project listings and code uniqueness.
QVariantList CalicataDocument::scanDrafts(bool includeArchived) const
{
    QVariantList out;
    const QString base = defaultUserRootDir();
    if (base.isEmpty()) return out;

    QDir dir(cleanPathJoin(base, ".drafts"));
    if (!dir.exists()) return out;

    const QFileInfoList files = dir.entryInfoList(
        QStringList() << "*.json",
        QDir::Files | QDir::Readable,
        QDir::Time);

    for (const QFileInfo &info : files) {
        QFile f(info.absoluteFilePath());
        if (!f.open(QIODevice::ReadOnly)) continue;

        QJsonParseError pe{};
        const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &pe);
        f.close();
        if (pe.error != QJsonParseError::NoError || !doc.isObject())
            continue;

        const QVariantMap root = doc.object().toVariantMap();
        const QString rawId = root.value("instance_id").toString().trimmed();
        const QUuid uuid(rawId);
        if (uuid.isNull()) continue;
        const QString id = uuid.toString(QUuid::WithoutBraces);
        if (QFileInfo(info.fileName()).completeBaseName() != id)
            continue;

        const QString fileUrlString = root.value("draft_file_url").toString();
        if (!includeArchived && !fileUrlString.isEmpty()) {
            const QUrl confirmedUrl(fileUrlString);
            const QString confirmedAbs = absPathFromUrl(confirmedUrl);
            if (!confirmedAbs.isEmpty() && QFileInfo::exists(confirmedAbs)) {
                const QFileInfo confirmedInfo(confirmedAbs);
                if (info.lastModified() <= confirmedInfo.lastModified())
                    continue;
                if (appContext() && appContext()->isOpenFile(confirmedAbs))
                    continue;
            }
        }

        const QVariantMap header = root.value("header").toMap();
        const QString status = header.value("status", QStringLiteral("BORRADOR")).toString();
        if (!includeArchived && status == QLatin1String("ARCHIVADO")) continue;
        QString title = header.value("codigo").toString().trimmed();
        if (title.isEmpty()) title = header.value("calicata").toString().trimmed();
        if (title.isEmpty()) title = header.value("pk").toString().trimmed();
        if (title.isEmpty()) title = header.value("progresiva").toString().trimmed();
        if (title.isEmpty()) title = QStringLiteral("Borrador recuperado");

        QVariantMap item;
        item["instanceId"] = id;
        item["title"] = title;
        item["fileUrl"] = fileUrlString;
        item["projectId"] = header.value("projectId", header.value("project_id"));
        item["projectCode"] = header.value("projectCode", header.value("project_code"));
        item["projectName"] = header.value("projectName");
        item["projectFullName"] = header.value("project_full_name");
        item["remoteCalicataId"] = header.value("remoteCalicataId", header.value("remote_calicata_id"));
        item["code"] = header.value("code", header.value("codigo")).toString().trimmed();
        item["status"] = status;
        item["syncState"] = header.value("sync_state");
        item["lastModifiedMs"] = info.lastModified().toMSecsSinceEpoch();
        out.append(item);
    }

    return out;
}

QVariantList CalicataDocument::listProjectDrafts(const QString &projectId, bool includeArchived) const
{
    const QUuid requested(projectId.trimmed());
    if (requested.isNull()) return {};
    QVariantList filtered;
    for (const QVariant &value : scanDrafts(includeArchived)) {
        const QVariantMap item = value.toMap();
        if (QUuid(item.value(QStringLiteral("projectId")).toString()) == requested)
            filtered.append(item);
    }
    return filtered;
}

QVariantList CalicataDocument::listDraftsForProject(const QString &projectId) const
{
    const QUuid requested(projectId.trimmed());
    if (requested.isNull()) return {};
    QVariantList filtered;
    for (const QVariant &value : listDrafts()) {
        const QVariantMap item = value.toMap();
        if (QUuid(item.value(QStringLiteral("projectId")).toString()) == requested)
            filtered.append(item);
    }
    return filtered;
}

bool CalicataDocument::loadDraftById(const QString& draftId)
{
    if (m_closed) return false;

    const QUuid uuid(draftId.trimmed());
    if (uuid.isNull()) return false;
    const QString normalizedId = uuid.toString(QUuid::WithoutBraces);

    const QString base = defaultUserRootDir();
    if (base.isEmpty()) return false;
    const QString path = cleanPathJoin(base, ".drafts/" + normalizedId + ".json");
    if (!QFileInfo::exists(path)) return false;

    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) return false;

    QJsonParseError pe{};
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll(), &pe);
    f.close();
    if (pe.error != QJsonParseError::NoError || !doc.isObject())
        return false;

    const QVariantMap root = doc.object().toVariantMap();
    const QString storedRawId = root.value("instance_id").toString().trimmed();
    const QUuid storedUuid(storedRawId);
    if (storedUuid.isNull()) return false;
    const QString storedId = storedUuid.toString(QUuid::WithoutBraces);
    if (storedId != normalizedId)
        return false;

    const QString fileUrlString = root.value("draft_file_url").toString();
    QUrl confirmedUrl;
    QString confirmedAbs;
    if (!fileUrlString.isEmpty()) {
        confirmedUrl = QUrl(fileUrlString);
        confirmedAbs = absPathFromUrl(confirmedUrl);
        if (!confirmedAbs.isEmpty() && QFileInfo::exists(confirmedAbs)) {
            const QFileInfo draftInfo(path);
            const QFileInfo confirmedInfo(confirmedAbs);
            if (draftInfo.lastModified() <= confirmedInfo.lastModified())
                return false;
            if (appContext() && appContext()->isOpenFile(confirmedAbs))
                return false;
        }
    }

    if (!applyFullJson(root))
        return false;

    if (!confirmedAbs.isEmpty() && QFileInfo::exists(confirmedAbs)) {
        m_fileUrl = confirmedUrl;
        m_loadedFromDisk = true;
        if (appContext())
            appContext()->registerOpenFile(confirmedAbs);
    } else {
        m_fileUrl = QUrl();
        m_loadedFromDisk = false;
    }
    emit fileUrlChanged();

    updateDisplayName();
    setDirty(true);
    return true;
}

// ===================== Fotografías avanzadas (P1) =====================
// Contract mirrored from InGe+ Web photoDerivative.ts / photoOverlayStyle.ts:
// the original is immutable, every derivative is a new file painted from it.
namespace {

constexpr int kPhotoMinOutputEdge = 1400;   // PHOTO_MIN_OUTPUT_EDGE

QString photoFontFamily(const QString &fontId)
{
    if (fontId == QLatin1String("serif")) return QStringLiteral("serif");
    if (fontId == QLatin1String("mono")) return QStringLiteral("monospace");
    if (fontId == QLatin1String("condensed")) return QStringLiteral("sans-serif-condensed");
    return QStringLiteral("sans-serif");
}

// Posición libre (arrastre sobre la vista previa): centro normalizado [x, y] sobre la
// imagen final; tiene prioridad sobre el ancla 3x3 y siempre queda dentro del marco.
bool placePhotoOverlayFree(const QSize &size, qreal blockWidth, qreal blockHeight, qreal margin,
                           const QVariant &pos, QPointF *topLeft)
{
    const QVariantList p = pos.toList();
    if (p.size() != 2) return false;
    bool okX = false, okY = false;
    const qreal nx = p.at(0).toDouble(&okX), ny = p.at(1).toDouble(&okY);
    if (!okX || !okY || !qIsFinite(nx) || !qIsFinite(ny)) return false;
    qreal left = qBound<qreal>(0.0, nx, 1.0) * size.width() - blockWidth / 2.0;
    qreal top = qBound<qreal>(0.0, ny, 1.0) * size.height() - blockHeight / 2.0;
    left = qMin(qMax(left, margin), qMax(margin, size.width() - margin - blockWidth));
    top = qMin(qMax(top, margin), qMax(margin, size.height() - margin - blockHeight));
    *topLeft = QPointF(left, top);
    return true;
}

QPointF placePhotoOverlayBlock(const QSize &size, qreal blockWidth, qreal blockHeight, qreal margin,
                               const QString &anchor, qreal offsetXPct, qreal offsetYPct)
{
    const QStringList parts = anchor.split(QLatin1Char('-'));
    const QString vertical = parts.value(0, QStringLiteral("bottom"));
    const QString horizontal = parts.value(1, QStringLiteral("right"));
    qreal left = horizontal == QLatin1String("left") ? margin
        : horizontal == QLatin1String("center") ? (size.width() - blockWidth) / 2.0
        : size.width() - margin - blockWidth;
    qreal top = vertical == QLatin1String("top") ? margin
        : vertical == QLatin1String("middle") ? (size.height() - blockHeight) / 2.0
        : size.height() - margin - blockHeight;
    left += qBound<qreal>(-45, offsetXPct, 45) / 100.0 * size.width();
    top -= qBound<qreal>(-45, offsetYPct, 45) / 100.0 * size.height();   // cartesian Y, as Web
    left = qMin(qMax(left, margin), qMax(margin, size.width() - margin - blockWidth));
    top = qMin(qMax(top, margin), qMax(margin, size.height() - margin - blockHeight));
    return {left, top};
}

// Lines of the Web derivative (PHOTO_FIELDS), in the same order.
QString photoDmsText(double value, bool latitude)
{
    const QChar hemisphere = latitude ? (value < 0 ? QLatin1Char('S') : QLatin1Char('N'))
                                      : (value < 0 ? QLatin1Char('O') : QLatin1Char('E'));
    value = qAbs(value);
    int degrees = int(value);
    const double minutesFull = (value - degrees) * 60.0;
    int minutes = int(minutesFull);
    double seconds = (minutesFull - minutes) * 60.0;
    if (seconds >= 59.995) { seconds = 0; ++minutes; }
    if (minutes >= 60) { minutes = 0; ++degrees; }
    return QStringLiteral("%1°%2'%3\" %4").arg(degrees).arg(minutes, 2, 10, QLatin1Char('0'))
        .arg(seconds, 5, 'f', 2, QLatin1Char('0')).arg(hemisphere);
}

QStringList photoOverlayLines(const QVariantMap &edit)
{
    if (!edit.value(QStringLiteral("withMetadata"), true).toBool()) return {};
    const QVariantMap fields = edit.value(QStringLiteral("fields")).toMap();
    const QVariantMap meta = edit.value(QStringLiteral("metadata")).toMap();
    const QString format = edit.value(QStringLiteral("style")).toMap().value(QStringLiteral("coordFormat"), QStringLiteral("utm")).toString();
    const auto on = [&](const char *key, bool byDefault = true) { return fields.value(QLatin1String(key), byDefault).toBool(); };
    const auto text = [&](const char *key) { return meta.value(QLatin1String(key)).toString().trimmed(); };
    QStringList lines;
    bool okLat = false, okLon = false;
    const double lat = text("latitude").toDouble(&okLat);
    const double lon = text("longitude").toDouble(&okLon);
    const bool geographic = format != QLatin1String("utm") && okLat && okLon && qIsFinite(lat) && qIsFinite(lon)
        && qAbs(lat) <= 90.0 && qAbs(lon) <= 180.0;
    const bool coordinates = on("zone") || on("easting") || on("northing");
    if (geographic && coordinates) {
        // Coordenadas reales de la ficha (nunca inventadas): WGS84 decimal o GMS.
        if (format == QLatin1String("dms")) {
            lines << QStringLiteral("WGS84 (GMS)")
                  << QStringLiteral("Lat: %1").arg(photoDmsText(lat, true))
                  << QStringLiteral("Lon: %1").arg(photoDmsText(lon, false));
        } else {
            lines << QStringLiteral("WGS84 (decimal)")
                  << QStringLiteral("Lat: %1°").arg(lat, 0, 'f', 6)
                  << QStringLiteral("Lon: %1°").arg(lon, 0, 'f', 6);
        }
    } else {
        // Formato de la ficha oficial C-AA-01 (una línea): "ZONA 18 661263 E 8561516 N".
        // Coordenadas de la CALICATA (en C-AA-01 son idénticas en todas sus fotos).
        QStringList utm;
        if (on("zone") && !text("zone").isEmpty()) utm << QStringLiteral("ZONA ") + text("zone");
        if (on("easting") && !text("easting").isEmpty()) utm << text("easting") + QStringLiteral(" E");
        if (on("northing") && !text("northing").isEmpty()) utm << text("northing") + QStringLiteral(" N");
        if (!utm.isEmpty()) lines << utm.join(QLatin1Char(' '));
    }
    // "Altitud: 706 m.s.n.m" — cota de la calicata (manual o elevación del terreno).
    if (on("altitude") && !text("altitude").isEmpty())
        lines << (text("altitude_source") == QLatin1String("GPS_ELIPSOIDAL")
                  ? QStringLiteral("Altitud GPS: %1 m (elipsoidal)").arg(text("altitude"))
                  : QStringLiteral("Altitud: %1 m.s.n.m").arg(text("altitude")));
    // "C-AA-01  Proyecto Lechemayo": código tal como está registrado + nombre corto.
    QStringList identity;
    if (on("calicata") && !text("calicata").isEmpty()) identity << text("calicata");
    if (on("project") && !text("project").isEmpty()) identity << text("project");
    if (!identity.isEmpty()) lines << identity.join(QStringLiteral("  "));
    // "14/05/26  11:02:46": fecha/hora de captura de la foto.
    QStringList when;
    if (on("date") && !text("date").isEmpty()) {
        const QDate date = QDate::fromString(text("date"), QStringLiteral("dd/MM/yyyy"));
        when << (date.isValid() ? date.toString(QStringLiteral("dd/MM/yy")) : text("date"));
    }
    if (on("time") && !text("time").isEmpty()) when << text("time");
    if (!when.isEmpty()) lines << when.join(QStringLiteral("  "));
    const struct { const char *key; const char *label; const char *suffix; bool byDefault; } extra[] = {
        {"depth", "Profundidad", " m", false}, {"category", "Categoría", "", false}, {"user", "Responsable", "", false}
    };
    for (const auto &row : extra) {
        if (!on(row.key, row.byDefault) || text(row.key).isEmpty()) continue;
        lines << QStringLiteral("%1: %2%3").arg(QLatin1String(row.label), text(row.key), QLatin1String(row.suffix));
    }
    return lines;
}

// Curva tonal: interpolación cúbica monótona (Fritsch–Carlson) -> LUT de 256 valores.
bool photoCurveLut(const QVariantList &points, QVector<int> *lut)
{
    QVector<QPointF> pts;
    for (const QVariant &value : points) {
        const QVariantList pt = value.toList();
        if (pt.size() < 2) continue;
        pts << QPointF(qBound(0.0, pt.at(0).toDouble(), 1.0), qBound(0.0, pt.at(1).toDouble(), 1.0));
    }
    std::sort(pts.begin(), pts.end(), [](const QPointF &l, const QPointF &r) { return l.x() < r.x(); });
    QVector<QPointF> clean;
    for (const QPointF &pt : pts)
        if (clean.isEmpty() || pt.x() - clean.last().x() > 1e-4) clean << pt;
    if (clean.isEmpty() || clean.first().x() > 1e-4) clean.prepend(QPointF(0, clean.isEmpty() ? 0 : clean.first().y() * 0));
    if (clean.last().x() < 1.0 - 1e-4) clean << QPointF(1, 1);
    const int n = clean.size();
    if (n < 2) return false;
    QVector<double> dx(n - 1), m(n - 1), t(n);
    for (int i = 0; i < n - 1; ++i) {
        dx[i] = clean[i + 1].x() - clean[i].x();
        m[i] = (clean[i + 1].y() - clean[i].y()) / dx[i];
    }
    t[0] = m[0];
    t[n - 1] = m[n - 2];
    for (int i = 1; i < n - 1; ++i) t[i] = (m[i - 1] * m[i] <= 0) ? 0 : (m[i - 1] + m[i]) / 2.0;
    for (int i = 0; i < n - 1; ++i) {
        if (qFuzzyIsNull(m[i])) { t[i] = 0; t[i + 1] = 0; continue; }
        const double a = t[i] / m[i], b = t[i + 1] / m[i], s = a * a + b * b;
        if (s > 9.0) { const double tau = 3.0 / qSqrt(s); t[i] = tau * a * m[i]; t[i + 1] = tau * b * m[i]; }
    }
    bool active = false;
    lut->resize(256);
    int k = 0;
    for (int v = 0; v < 256; ++v) {
        const double x = v / 255.0;
        while (k < n - 2 && x > clean[k + 1].x()) ++k;
        const double h = dx[k], u = qBound(0.0, (x - clean[k].x()) / h, 1.0);
        const double h00 = 2 * u * u * u - 3 * u * u + 1, h10 = u * u * u - 2 * u * u + u;
        const double h01 = -2 * u * u * u + 3 * u * u, h11 = u * u * u - u * u;
        const double y = h00 * clean[k].y() + h10 * h * t[k] + h01 * clean[k + 1].y() + h11 * h * t[k + 1];
        (*lut)[v] = qBound(0, qRound(y * 255.0), 255);
        if (qAbs((*lut)[v] - v) > 0) active = true;
    }
    return active;
}

// Contraste local (claridad: radio grande; nitidez: radio pequeño) por máscara de desenfoque.
void photoLocalContrast(QImage &target, int divisor, double amount)
{
    if (qFuzzyIsNull(amount) || target.isNull()) return;
    const QImage blur = target.scaled(qMax(1, target.width() / divisor), qMax(1, target.height() / divisor),
                                      Qt::IgnoreAspectRatio, Qt::SmoothTransformation)
                            .scaled(target.size(), Qt::IgnoreAspectRatio, Qt::SmoothTransformation)
                            .convertToFormat(QImage::Format_RGB32);
    for (int y = 0; y < target.height(); ++y) {
        const QRgb *soft = reinterpret_cast<const QRgb *>(blur.constScanLine(y));
        QRgb *line = reinterpret_cast<QRgb *>(target.scanLine(y));
        for (int x = 0; x < target.width(); ++x) {
            const int r = qRed(line[x]), g = qGreen(line[x]), b = qBlue(line[x]);
            line[x] = qRgb(qBound(0, qRound(r + amount * (r - qRed(soft[x]))), 255),
                           qBound(0, qRound(g + amount * (g - qGreen(soft[x]))), 255),
                           qBound(0, qRound(b + amount * (b - qBlue(soft[x]))), 255));
        }
    }
}

// Herramientas de imagen del editor. Orden: 90° → espejo → rotación fina (auto-recorte)
// → perspectiva (4 puntos) → recorte libre (o relación de aspecto) → tono/color
// (exposición, brillo, contraste, luces, sombras, temperatura, tinte, saturación,
// preset con intensidad, curva) → claridad → nitidez → viñeta → resolución.
// Solo afecta a la DERIVADA: la original nunca se modifica.
QImage applyPhotoImageEdit(const QImage &source, const QVariantMap &image)
{
    if (image.isEmpty() || source.isNull()) return source;
    const auto num = [&image](const char *key, double lo, double hi, double fallback = 0.0) {
        return qBound(lo, image.value(QLatin1String(key), fallback).toDouble(), hi);
    };
    QImage img = source.convertToFormat(QImage::Format_RGB32);

    const int rotation = ((qRound(image.value(QStringLiteral("rotation")).toDouble() / 90.0) * 90) % 360 + 360) % 360;
    if (rotation != 0) img = img.transformed(QTransform().rotate(rotation), Qt::SmoothTransformation);
    const bool flipH = image.value(QStringLiteral("flipH")).toBool();
    const bool flipV = image.value(QStringLiteral("flipV")).toBool();
    if (flipH || flipV) img = img.transformed(QTransform().scale(flipH ? -1 : 1, flipV ? -1 : 1));

    const double angle = num("angle", -45, 45);
    if (qAbs(angle) > 0.01) {
        const int w = img.width(), h = img.height();
        const double rad = qDegreesToRadians(qAbs(angle));
        const double c = qCos(rad), s = qSin(rad);
        const double scale = qMin(w / (w * c + h * s), h / (w * s + h * c));
        const QImage rotated = img.transformed(QTransform().rotate(angle), Qt::SmoothTransformation);
        const int cw = qMax(1, int(w * scale)), ch = qMax(1, int(h * scale));
        img = rotated.copy((rotated.width() - cw) / 2, (rotated.height() - ch) / 2, cw, ch).convertToFormat(QImage::Format_RGB32);
    }

    const QVariantList quad = image.value(QStringLiteral("perspective")).toList();
    if (quad.size() == 4) {
        const QPointF corners[4] = {QPointF(0, 0), QPointF(1, 0), QPointF(1, 1), QPointF(0, 1)};
        QPolygonF from;
        bool identity = true;
        for (int i = 0; i < 4; ++i) {
            const QVariantList pt = quad.at(i).toList();
            const double x = qBound(0.0, pt.value(0).toDouble(), 1.0), y = qBound(0.0, pt.value(1).toDouble(), 1.0);
            if (qAbs(x - corners[i].x()) > 0.001 || qAbs(y - corners[i].y()) > 0.001) identity = false;
            from << QPointF(x * img.width(), y * img.height());
        }
        QPolygonF to;
        to << QPointF(0, 0) << QPointF(img.width(), 0) << QPointF(img.width(), img.height()) << QPointF(0, img.height());
        QTransform warp;
        if (!identity && QTransform::quadToQuad(from, to, warp)) {
            QImage out(img.size(), QImage::Format_RGB32);
            out.fill(Qt::black);
            QPainter pp(&out);
            pp.setRenderHint(QPainter::SmoothPixmapTransform);
            pp.setTransform(warp);
            pp.drawImage(0, 0, img);
            pp.end();
            img = out;
        }
    }

    const QVariantMap crop = image.value(QStringLiteral("crop")).toMap();
    if (!crop.isEmpty()) {
        const double cx = qBound(0.0, crop.value(QStringLiteral("x")).toDouble(), 0.95);
        const double cy = qBound(0.0, crop.value(QStringLiteral("y")).toDouble(), 0.95);
        const double cw = qBound(0.05, crop.value(QStringLiteral("w"), 1.0).toDouble(), 1.0 - cx);
        const double ch = qBound(0.05, crop.value(QStringLiteral("h"), 1.0).toDouble(), 1.0 - cy);
        const QRect r(qRound(cx * img.width()), qRound(cy * img.height()),
                      qMax(1, qRound(cw * img.width())), qMax(1, qRound(ch * img.height())));
        img = img.copy(r.intersected(img.rect()));
    } else {
        const QString aspect = image.value(QStringLiteral("aspect")).toString();
        const double ratio = aspect == QLatin1String("1:1") ? 1.0 : aspect == QLatin1String("4:3") ? 4.0 / 3.0
                           : aspect == QLatin1String("16:9") ? 16.0 / 9.0 : 0.0;
        if (ratio > 0 && img.width() > 0 && img.height() > 0) {
            const double target = img.width() >= img.height() ? ratio : 1.0 / ratio;
            const double current = double(img.width()) / img.height();
            QRect r = img.rect();
            if (current > target) { const int w = qMax(1, qRound(img.height() * target)); r = QRect((img.width() - w) / 2, 0, w, img.height()); }
            else if (current < target) { const int h = qMax(1, qRound(img.width() / target)); r = QRect(0, (img.height() - h) / 2, img.width(), h); }
            img = img.copy(r);
        }
    }

    double exposure = num("exposure", -100, 100), brightness = num("brightness", -100, 100);
    double contrast = num("contrast", -100, 100), highlights = num("highlights", -100, 100);
    double shadows = num("shadows", -100, 100), warmth = num("warmth", -100, 100), tint = num("tint", -100, 100);
    double saturation = num("saturation", -100, 100), clarity = num("clarity", -100, 100), sharpness = num("sharpness", 0, 100);
    // Presets = combinaciones reales de parámetros, escaladas por su intensidad.
    const QString preset = image.value(QStringLiteral("preset")).toString();
    const double pk = num("presetIntensity", 0, 100, 100) / 100.0;
    struct Delta { double exposure, contrast, highlights, shadows, warmth, saturation, clarity, sharpness; };
    Delta delta{0, 0, 0, 0, 0, 0, 0, 0};
    if (preset == QLatin1String("natural")) delta = {0, 6, -4, 6, 2, 8, 6, 5};
    else if (preset == QLatin1String("contrast")) delta = {0, 25, -10, -10, 0, 10, 10, 5};
    else if (preset == QLatin1String("vivid")) delta = {0, 12, -6, 4, 0, 30, 6, 5};
    else if (preset == QLatin1String("documentary")) delta = {0, 10, -8, 8, 6, -15, 12, 15};
    else if (preset == QLatin1String("technical") || preset == QLatin1String("work")) delta = {5, 15, -12, 12, 0, -25, 15, 25};
    else if (preset == QLatin1String("bw")) delta = {0, 15, 0, 0, 0, -100, 8, 10};
    exposure = qBound(-100.0, exposure + delta.exposure * pk, 100.0);
    contrast = qBound(-100.0, contrast + delta.contrast * pk, 100.0);
    highlights = qBound(-100.0, highlights + delta.highlights * pk, 100.0);
    shadows = qBound(-100.0, shadows + delta.shadows * pk, 100.0);
    warmth = qBound(-100.0, warmth + delta.warmth * pk, 100.0);
    saturation = qBound(-100.0, saturation + delta.saturation * pk, 100.0);
    clarity = qBound(-100.0, clarity + delta.clarity * pk, 100.0);
    sharpness = qBound(0.0, sharpness + delta.sharpness * pk, 100.0);

    QVector<int> lut;
    const bool curveActive = photoCurveLut(image.value(QStringLiteral("curve")).toList(), &lut);
    if (exposure || brightness || contrast || highlights || shadows || warmth || tint || saturation || curveActive) {
        const double mul = qPow(2.0, exposure / 100.0);
        const double cf = 1.0 + contrast / 100.0;
        const double sf = 1.0 + saturation / 100.0;
        for (int y = 0; y < img.height(); ++y) {
            QRgb *line = reinterpret_cast<QRgb *>(img.scanLine(y));
            for (int x = 0; x < img.width(); ++x) {
                double r = qRed(line[x]) / 255.0 * mul, g = qGreen(line[x]) / 255.0 * mul, b = qBlue(line[x]) / 255.0 * mul;
                r += brightness / 200.0; g += brightness / 200.0; b += brightness / 200.0;
                r = (r - 0.5) * cf + 0.5; g = (g - 0.5) * cf + 0.5; b = (b - 0.5) * cf + 0.5;
                r += warmth / 100.0 * 0.08; b -= warmth / 100.0 * 0.08;
                g += tint / 100.0 * 0.06; r -= tint / 100.0 * 0.03; b -= tint / 100.0 * 0.03;
                const double l = qBound(0.0, 0.299 * r + 0.587 * g + 0.114 * b, 1.0);
                const double tone = shadows / 100.0 * 0.35 * (1.0 - l) * (1.0 - l) + highlights / 100.0 * 0.35 * l * l;
                r += tone; g += tone; b += tone;
                const double l2 = 0.299 * r + 0.587 * g + 0.114 * b;
                r = l2 + (r - l2) * sf; g = l2 + (g - l2) * sf; b = l2 + (b - l2) * sf;
                int R = qBound(0, qRound(r * 255.0), 255), G = qBound(0, qRound(g * 255.0), 255), B = qBound(0, qRound(b * 255.0), 255);
                if (curveActive) { R = lut[R]; G = lut[G]; B = lut[B]; }
                line[x] = qRgb(R, G, B);
            }
        }
    }
    photoLocalContrast(img, 16, clarity / 100.0 * 0.6);
    photoLocalContrast(img, 2, sharpness / 100.0 * 1.2);

    const double vignette = num("vignette", -100, 100);
    if (qAbs(vignette) > 0.5) {
        const double size = num("vignetteSize", 0, 100, 50) / 100.0;
        const double softness = num("vignetteSoftness", 0, 100, 50) / 100.0;
        const double cx = num("vignetteX", 0, 1, 0.5) * img.width();
        const double cy = num("vignetteY", 0, 1, 0.5) * img.height();
        const double inner = 0.2 + size * 0.6, feather = 0.05 + softness * 0.7;
        const double halfDiag = qSqrt(double(img.width()) * img.width() + double(img.height()) * img.height()) / 2.0;
        for (int y = 0; y < img.height(); ++y) {
            QRgb *line = reinterpret_cast<QRgb *>(img.scanLine(y));
            for (int x = 0; x < img.width(); ++x) {
                const double dist = qSqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) / halfDiag;
                const double t = qBound(0.0, (dist - inner) / feather, 1.0);
                const double smooth = t * t * (3 - 2 * t);
                const double f = 1.0 - vignette / 100.0 * smooth * 0.85;
                line[x] = qRgb(qBound(0, qRound(qRed(line[x]) * f), 255), qBound(0, qRound(qGreen(line[x]) * f), 255),
                               qBound(0, qRound(qBlue(line[x]) * f), 255));
            }
        }
    }

    const QString resolution = image.value(QStringLiteral("resolution")).toString();
    const int maxEdge = resolution == QLatin1String("normal") ? 1600 : resolution == QLatin1String("high") ? 2560 : 0;
    if (maxEdge > 0 && qMax(img.width(), img.height()) > maxEdge)
        img = img.scaled(maxEdge, maxEdge, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    return img;
}

QImage paintPhotoDerivative(const QImage &originalInput, const QVariantMap &edit, const QImage &logo)
{
    const QImage original = applyPhotoImageEdit(originalInput, edit.value(QStringLiteral("image")).toMap());
    const QVariantMap style = edit.value(QStringLiteral("style")).toMap();
    QSize size = original.size();
    const int longest = qMax(size.width(), size.height());
    if (style.value(QStringLiteral("enlargeSmall"), true).toBool() && longest > 0 && longest < kPhotoMinOutputEdge)
        size = (QSizeF(size) * (qreal(kPhotoMinOutputEdge) / longest)).toSize();

    QImage out(size, QImage::Format_RGB32);
    QPainter p(&out);
    p.setRenderHints(QPainter::Antialiasing | QPainter::TextAntialiasing | QPainter::SmoothPixmapTransform);
    p.drawImage(QRect(QPoint(0, 0), size), original);

    const int shortEdge = qMin(size.width(), size.height());
    // Anotaciones a mano alzada (coordenadas normalizadas sobre la imagen final).
    for (const QVariant &value : edit.value(QStringLiteral("annotations")).toList()) {
        const QVariantMap stroke = value.toMap();
        const QVariantList pts = stroke.value(QStringLiteral("points")).toList();
        if (pts.size() < 2) continue;
        QColor strokeColor(stroke.value(QStringLiteral("color"), QStringLiteral("#ff3b30")).toString());
        if (!strokeColor.isValid()) strokeColor = QColor(QStringLiteral("#ff3b30"));
        const bool marker = stroke.value(QStringLiteral("tool")).toString() == QLatin1String("marker");
        if (marker) strokeColor.setAlpha(110);
        const double width = qBound(0.1, stroke.value(QStringLiteral("width"), 0.8).toDouble(), 6.0) * shortEdge / 100.0 * (marker ? 2.5 : 1.0);
        QPainterPath path;
        for (int i = 0; i < pts.size(); ++i) {
            const QVariantList pt = pts.at(i).toList();
            const QPointF q(pt.value(0).toDouble() * size.width(), pt.value(1).toDouble() * size.height());
            if (i == 0) path.moveTo(q); else path.lineTo(q);
        }
        p.setPen(QPen(strokeColor, qMax(1.0, width), Qt::SolidLine, marker ? Qt::SquareCap : Qt::RoundCap, Qt::RoundJoin));
        p.setBrush(Qt::NoBrush);
        p.drawPath(path);
    }
    const qreal sizePct = qBound<qreal>(2, style.value(QStringLiteral("sizePct"), 4).toReal(), 10);
    const int fontSize = qMax(10, qRound(shortEdge * sizePct / 100.0));
    const int padding = qMax(6, qRound(shortEdge / 45.0));
    const int margin = padding;

    const QStringList rawLines = photoOverlayLines(edit);
    if (!rawLines.isEmpty()) {
        QFont font(photoFontFamily(style.value(QStringLiteral("fontId")).toString()));
        font.setPixelSize(fontSize);
        font.setBold(style.value(QStringLiteral("bold")).toBool());
        p.setFont(font);
        const QFontMetricsF fm(font);
        const qreal maxWidth = size.width() * 0.9 - (padding + margin) * 2;
        // Wrap por palabras con un máximo de 2 líneas por dato: ninguna cadena
        // destruye la composición (la elipsis es solo de presentación; el dato
        // persistido no cambia). Palabras más anchas que la línea se cortan.
        QStringList lines;
        for (const QString &line : rawLines) {
            QStringList wrapped;
            QString current;
            for (const QString &word : line.split(QLatin1Char(' '), Qt::SkipEmptyParts)) {
                const QString candidate = current.isEmpty() ? word : current + QLatin1Char(' ') + word;
                if (current.isEmpty() || fm.horizontalAdvance(candidate) <= maxWidth) { current = candidate; continue; }
                wrapped << current;
                current = word;
            }
            if (!current.isEmpty()) wrapped << current;
            if (wrapped.size() > 2) {
                wrapped = wrapped.mid(0, 2);
                wrapped[1] = fm.elidedText(wrapped[1] + QStringLiteral(" …"), Qt::ElideRight, maxWidth);
            }
            for (QString &part : wrapped)
                if (fm.horizontalAdvance(part) > maxWidth) part = fm.elidedText(part, Qt::ElideRight, maxWidth);
            lines << wrapped;
        }
        qreal textWidth = 0;
        for (const QString &line : lines) textWidth = qMax(textWidth, fm.horizontalAdvance(line));
        const qreal lineHeight = fontSize * 1.4;
        const qreal blockHeight = lines.size() * lineHeight + padding * 2;
        const qreal blockWidth = qMin<qreal>(size.width() - margin * 2, textWidth + padding * 2);
        const QString anchor = style.value(QStringLiteral("anchor"), QStringLiteral("bottom-right")).toString();
        QPointF topLeft;
        if (!placePhotoOverlayFree(size, blockWidth, blockHeight, margin, style.value(QStringLiteral("labelPos")), &topLeft))
            topLeft = placePhotoOverlayBlock(size, blockWidth, blockHeight, margin, anchor,
                                             style.value(QStringLiteral("offsetXPct")).toReal(),
                                             style.value(QStringLiteral("offsetYPct")).toReal());
        const QString backdrop = style.value(QStringLiteral("backdrop"), QStringLiteral("shadow")).toString();
        if (backdrop == QLatin1String("panel"))
            p.fillRect(QRectF(topLeft, QSizeF(blockWidth, blockHeight)), QColor(2, 6, 23, 140));
        const QString horizontal = anchor.section(QLatin1Char('-'), 1, 1);
        const int align = horizontal == QLatin1String("left") ? Qt::AlignLeft
            : horizontal == QLatin1String("center") ? Qt::AlignHCenter : Qt::AlignRight;
        QColor color(style.value(QStringLiteral("color"), QStringLiteral("#ffffff")).toString());
        if (!color.isValid()) color = Qt::white;
        const qreal shadowOffset = qMax<qreal>(1.0, fontSize / 24.0);
        for (int i = 0; i < lines.size(); ++i) {
            const QRectF rect(topLeft.x() + padding, topLeft.y() + padding + i * lineHeight,
                              blockWidth - padding * 2, lineHeight);
            if (backdrop == QLatin1String("shadow")) {
                p.setPen(QColor(0, 0, 0, 217));
                p.drawText(rect.translated(shadowOffset, shadowOffset), align | Qt::AlignTop, lines.at(i));
            }
            p.setPen(color);
            p.drawText(rect, align | Qt::AlignTop, lines.at(i));
        }
    }

    // Marca de agua personalizada (texto de la ficha por defecto; opacidad, tamaño, posición o mosaico).
    const QVariantMap watermark = edit.value(QStringLiteral("watermark")).toMap();
    const QString watermarkText = watermark.value(QStringLiteral("text")).toString().trimmed();
    if (watermark.value(QStringLiteral("enabled")).toBool() && !watermarkText.isEmpty()) {
        QFont wf(photoFontFamily(style.value(QStringLiteral("fontId")).toString()));
        wf.setPixelSize(qMax(10, qRound(shortEdge * qBound(2.0, watermark.value(QStringLiteral("sizePct"), 6).toDouble(), 20.0) / 100.0)));
        wf.setBold(true);
        p.save();
        p.setFont(wf);
        p.setOpacity(qBound(0.05, watermark.value(QStringLiteral("opacityPct"), 30).toDouble() / 100.0, 1.0));
        QColor wc(watermark.value(QStringLiteral("color"), QStringLiteral("#ffffff")).toString());
        p.setPen(wc.isValid() ? wc : QColor(Qt::white));
        const QFontMetricsF wfm(wf);
        const qreal tw = wfm.horizontalAdvance(watermarkText), th = wfm.height();
        if (watermark.value(QStringLiteral("tiled")).toBool()) {
            p.translate(size.width() / 2.0, size.height() / 2.0);
            p.rotate(-30);
            const qreal diag = qSqrt(qreal(size.width()) * size.width() + qreal(size.height()) * size.height());
            for (qreal yy = -diag / 2; yy < diag / 2; yy += th * 3.0)
                for (qreal xx = -diag / 2; xx < diag / 2; xx += tw * 1.6)
                    p.drawText(QPointF(xx, yy), watermarkText);
        } else {
            QPointF at;
            if (!placePhotoOverlayFree(size, tw, th, margin, watermark.value(QStringLiteral("pos")), &at))
                at = placePhotoOverlayBlock(size, tw, th, margin,
                                            watermark.value(QStringLiteral("anchor"), QStringLiteral("middle-center")).toString(), 0, 0);
            p.drawText(QRectF(at, QSizeF(tw, th)), Qt::AlignCenter, watermarkText);
        }
        p.restore();
    }

    if (!logo.isNull() && logo.width() > 0 && logo.height() > 0) {
        const qreal logoScale = qBound<qreal>(40, style.value(QStringLiteral("logoScalePct"), 100).toReal(), 300);
        const qreal logoMargin = margin + shortEdge * qBound<qreal>(0, style.value(QStringLiteral("logoMarginPct"), 0).toReal(), 15) / 100.0;
        const qreal base = qMin<qreal>(qMin<qreal>(size.width() * 0.22 / logo.width(),
                                                   size.height() * 0.12 / logo.height()), 1.0);
        const qreal room = qMin<qreal>((size.width() - logoMargin * 2.0) / logo.width(),
                                       (size.height() - logoMargin * 2.0) / logo.height());
        const qreal scale = qMin<qreal>(base * logoScale / 100.0, room);
        const QSizeF logoSize(logo.width() * scale, logo.height() * scale);   // aspect ratio preserved
        QPointF at;
        if (!placePhotoOverlayFree(size, logoSize.width(), logoSize.height(), logoMargin, style.value(QStringLiteral("logoPos")), &at))
            at = placePhotoOverlayBlock(size, logoSize.width(), logoSize.height(), logoMargin,
                                        style.value(QStringLiteral("logoAnchor"), QStringLiteral("top-left")).toString(), 0, 0);
        p.save();
        p.setOpacity(qBound<qreal>(0.1, style.value(QStringLiteral("logoOpacityPct"), 100).toReal() / 100.0, 1.0));
        p.drawImage(QRectF(at, logoSize), logo);
        p.restore();
    }
    p.end();
    return out;
}

QString photoSlotKey(int idx, const QString &suffix)
{
    return QStringLiteral("foto%1_%2").arg(idx).arg(suffix);
}

} // namespace

QString CalicataDocument::photoCategoryCode(int idx) const
{
    // Web CALICATA_MEDIA_PHOTO_CATEGORIES, same order as the Android slots.
    switch (idx) {
    case 1: return QStringLiteral("EXECUTION");
    case 2: return QStringLiteral("INTERIOR");
    case 3: return QStringLiteral("STOCKPILES");
    default: return {};
    }
}

QUrl CalicataDocument::originalPhotoUrl(int idx) const
{
    if (idx < 1 || idx > 3) return {};
    QString path = m_images.value(photoSlotKey(idx, QStringLiteral("original_path"))).toString();
    // Legacy slot: the only file it has is its original.
    if (path.isEmpty()) path = m_images.value(photoSlotKey(idx, QStringLiteral("path"))).toString();
    const QString abs = resolveMaybeRelToAbs(path);
    return abs.isEmpty() || !QFileInfo::exists(abs) ? QUrl() : QUrl::fromLocalFile(abs);
}

QVariantMap CalicataDocument::photoSlot(int idx) const
{
    QVariantMap slot;
    if (idx < 1 || idx > 3) return slot;
    const auto key = [idx](const char *suffix) { return photoSlotKey(idx, QLatin1String(suffix)); };
    slot[QStringLiteral("index")] = idx;
    slot[QStringLiteral("categoryCode")] = photoCategoryCode(idx);
    slot[QStringLiteral("originalUrl")] = originalPhotoUrl(idx);
    slot[QStringLiteral("derivedUrl")] = cachedPhotoUrl(idx);
    slot[QStringLiteral("edit")] = m_images.value(key("edit")).toMap();
    slot[QStringLiteral("activeVersionId")] = m_images.value(key("active_local_version"));
    slot[QStringLiteral("syncState")] = m_images.value(key("sync"), QStringLiteral("LOCAL"));
    slot[QStringLiteral("syncError")] = m_images.value(key("sync_error"));
    slot[QStringLiteral("mediaId")] = m_images.value(key("media_id"));
    slot[QStringLiteral("cloudActiveVersionId")] = m_images.value(key("cloud_active_version_id"));
    slot[QStringLiteral("capture")] = m_images.value(key("capture")).toMap();
    QVariantList versions;
    for (const QVariant &value : m_images.value(key("versions")).toList()) {
        QVariantMap version = value.toMap();
        const QString abs = resolveMaybeRelToAbs(version.value(QStringLiteral("derived_path")).toString());
        version[QStringLiteral("url")] = abs.isEmpty() ? QUrl() : QUrl::fromLocalFile(abs);
        versions << version;
    }
    slot[QStringLiteral("versions")] = versions;
    return slot;
}

// Web CalicataPhotos: "Descargar versión anotada" guarda el derivado ya
// publicado (foto%1_path) y "Descargar original" el original intacto; nada se
// vuelve a pintar. Nombre como Web: "<etiqueta>-anotada.jpg" / nombre original.
QString CalicataDocument::savePhotoToGallery(int idx, bool annotated)
{
    if (m_closed || idx < 1 || idx > 3) return QStringLiteral("La fotografía no está disponible.");
    const QString original = originalPhotoUrl(idx).toLocalFile();
    const QString derived = cachedPhotoUrl(idx).toLocalFile();
    if (original.isEmpty()) return QStringLiteral("Esta posición no tiene fotografía.");
    if (annotated && (derived.isEmpty() || QFileInfo(derived).canonicalFilePath() == QFileInfo(original).canonicalFilePath()))
        return QStringLiteral("Esta fotografía no tiene versión anotada guardada.");
    static const QStringList labels = {QStringLiteral("Zona de ejecución"), QStringLiteral("Interior de calicata"),
                                       QStringLiteral("Acopios")};
    const QString path = annotated ? derived : original;
    const QString suffix = QFileInfo(path).suffix().toLower();
    const QString mime = suffix == QLatin1String("png") ? QStringLiteral("image/png")
                       : suffix == QLatin1String("webp") ? QStringLiteral("image/webp") : QStringLiteral("image/jpeg");
    const QString name = annotated ? labels.at(idx - 1) + QStringLiteral("-anotada.jpg") : QFileInfo(original).fileName();
#ifdef Q_OS_ANDROID
    const auto context = QNativeInterface::QAndroidApplication::context();
    const auto result = QJniObject::callStaticObjectMethod("com/ingema/ingeplus/NothingFileBridge", "saveToPictures",
        "(Landroid/content/Context;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;",
        context.object(), QJniObject::fromString(path).object<jstring>(),
        QJniObject::fromString(name).object<jstring>(), QJniObject::fromString(mime).object<jstring>());
    QJniEnvironment env;
    if (env->ExceptionCheck()) { env->ExceptionClear(); return QStringLiteral("Android no pudo guardar la imagen."); }
    if (!result.isValid()) return QStringLiteral("Android no respondió al guardar la imagen.");
    const QString error = result.toString();
    qInfo().noquote() << "INGE_CALICATA_PHOTO_SAVED slot=" << idx << "annotated=" << annotated << "ok=" << error.isEmpty();
    return error;
#else
    const QString folder = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation) + QStringLiteral("/InGePlus");
    if (!QDir().mkpath(folder)) return QStringLiteral("No se pudo crear la carpeta de imágenes.");
    QString target = QDir(folder).filePath(name);
    for (int n = 1; QFileInfo::exists(target); ++n)
        target = QDir(folder).filePath(QFileInfo(name).completeBaseName() + QStringLiteral(" (%1).").arg(n) + QFileInfo(name).suffix());
    Q_UNUSED(mime);
    return QFile::copy(path, target) ? QString() : QStringLiteral("No se pudo guardar la imagen.");
#endif
}

// Live values of the ficha for the overlay ("Actualizar desde la ficha").
QVariantMap CalicataDocument::photoMetadata(int idx) const
{
    QVariantMap meta = photoSheetMetadata();
    if (idx >= 1 && idx <= 3)
        applyPhotoCapture(meta, m_images.value(photoSlotKey(idx, QStringLiteral("capture"))).toMap(), m_header);
    return meta;
}

// Fija (una sola vez) la hora de respaldo de una foto que aún no la tiene
// (fotos anteriores a este cambio): la primera determinación queda guardada
// y las regeneraciones posteriores la conservan.
bool CalicataDocument::ensurePhotoSystemTime(int idx)
{
    if (m_closed || idx < 1 || idx > 3 || originalPhotoUrl(idx).isEmpty()) return false;
    const QString key = photoSlotKey(idx, QStringLiteral("capture"));
    QVariantMap capture = m_images.value(key).toMap();
    if (QTime::fromString(capture.value(QStringLiteral("system_time")).toString(), QStringLiteral("HH:mm:ss")).isValid())
        return true;
    const QString legacy = photoSystemTime(capture);   // hora APP ya registrada, si existe
    const QDateTime now = QDateTime::currentDateTime();
    capture[QStringLiteral("system_time")] = legacy.isEmpty() ? now.toString(QStringLiteral("HH:mm:ss")) : legacy;
    capture[QStringLiteral("system_at")] = now.toString(QStringLiteral("yyyy-MM-ddTHH:mm:ss"));
    QVariantMap images = m_images;
    images[key] = capture;
    return commitPhotoImages(images);
}

QVariantMap CalicataDocument::photoSheetMetadata() const
{
    const auto text = [this](std::initializer_list<const char *> keys) {
        for (const char *key : keys) {
            const QString value = m_header.value(QLatin1String(key)).toString().trimmed();
            if (!value.isEmpty()) return value;
        }
        return QString();
    };
    QVariantMap meta;
    meta[QStringLiteral("zone")] = text({"zona", "utm_zone"});
    meta[QStringLiteral("easting")] = text({"utm_x", "easting"});
    meta[QStringLiteral("northing")] = text({"utm_y", "northing"});
    // Altitud del rótulo = cota de la calicata (manual o elevación del terreno),
    // la misma para todas sus fotos (como C-AA-01). Su origen define la etiqueta:
    // una altura GPS elipsoidal nunca se rotula como m.s.n.m.
    {
        const QString z = text({"utm_z", "altitud", "altitude_m"});
        bool numeric = false;
        const double value = z.toDouble(&numeric);
        meta[QStringLiteral("altitude")] = numeric && std::isfinite(value) ? QString::number(qRound(value)) : z;
        meta[QStringLiteral("altitude_source")] = text({"altitude_source"});
    }
    meta[QStringLiteral("calicata")] = text({"code", "codigo", "calicata"});
    // Rótulo de fotos = projects.name (contrato Web, CalicataPhotos: misma
    // fuente que la ficha y la exportación). Sin proyecto asignado, el nombre
    // antiguo guardado en la ficha se conserva como rótulo.
    meta[QStringLiteral("project")] = m_header.value(QStringLiteral("projectId")).toString().trimmed().isEmpty()
        ? text({"project_full_name", "excel_title", "project_short_name"})
        : text({"projectName", "project_name"});
    // Fecha/hora: fecha de la ficha + hora manual o de la foto (photoMetadata);
    // nunca la fecha/hora actual del sistema al regenerar.
    meta[QStringLiteral("date")] = QString();
    meta[QStringLiteral("time")] = QString();
    meta[QStringLiteral("latitude")] = text({"latitude", "lat", "latitud"});
    meta[QStringLiteral("longitude")] = text({"longitude", "lon", "lng", "longitud"});
    meta[QStringLiteral("depth")] = text({"depth_m", "profundidad", "depth"});
    meta[QStringLiteral("user")] = text({"supervisor", "responsable"});
    return meta;
}

// Vista previa del editor: el MISMO pipeline que la derivada final (applyPhotoImageEdit
// + paintPhotoDerivative) a ~1280 px, en segundo plano. Una sola en curso por slot; la
// última petición gana (coalescida). Nunca crea versiones ni toca la original.
int CalicataDocument::requestPhotoPreview(int idx, const QVariantMap &editIn, const QString &stage)
{
    if (m_closed || idx < 1 || idx > 3 || originalPhotoUrl(idx).isEmpty()) return 0;
    const int token = ++m_photoPreviewSerial;
    m_photoPreviewLatest[idx] = token;
    QVariantMap edit = editIn;
    QVariantMap image = edit.value(QStringLiteral("image")).toMap();
    QVariantMap style = edit.value(QStringLiteral("style")).toMap();
    style[QStringLiteral("enlargeSmall")] = false;
    image[QStringLiteral("resolution")] = QStringLiteral("max");
    // Etapas para las herramientas interactivas: "annotate" (sin anotaciones),
    // "geometry" (antes del recorte y sin capas) y "source" (además sin perspectiva).
    if (stage != QLatin1String("result")) {
        edit[QStringLiteral("annotations")] = QVariantList();
        if (stage != QLatin1String("annotate")) {
            image.remove(QStringLiteral("crop"));
            image.remove(QStringLiteral("aspect"));
            edit[QStringLiteral("withMetadata")] = false;
            QVariantMap logo = edit.value(QStringLiteral("logo")).toMap();
            logo[QStringLiteral("enabled")] = false;
            edit[QStringLiteral("logo")] = logo;
            QVariantMap watermark = edit.value(QStringLiteral("watermark")).toMap();
            watermark[QStringLiteral("enabled")] = false;
            edit[QStringLiteral("watermark")] = watermark;
        }
        if (stage == QLatin1String("source")) image.remove(QStringLiteral("perspective"));
    }
    edit[QStringLiteral("image")] = image;
    edit[QStringLiteral("style")] = style;
    if (m_photoPreviewRunning.contains(idx)) {
        m_photoPreviewPending[idx] = edit;
        m_photoPreviewPendingToken[idx] = token;
        return token;
    }
    launchPhotoPreview(idx, token, edit);
    return token;
}

void CalicataDocument::launchPhotoPreview(int idx, int token, const QVariantMap &edit)
{
    const QVariantMap logoEdit = edit.value(QStringLiteral("logo")).toMap();
    const bool logoWanted = logoEdit.value(QStringLiteral("enabled")).toBool();
    const QString logoPath = logoWanted ? photoLogoPath(logoEdit.value(QStringLiteral("source")).toString()) : QString();
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation) + QStringLiteral("/photo-preview");
    QDir().mkpath(dir);
    const QString outPath = QDir(dir).filePath(QStringLiteral("%1_%2_%3.jpg").arg(m_instanceId.left(8)).arg(idx).arg(token));
    const QString originalAbs = originalPhotoUrl(idx).toLocalFile();
    m_photoPreviewRunning.insert(idx);
    QPointer<CalicataDocument> self(this);
    QThreadPool::globalInstance()->start([self, idx, token, edit, originalAbs, logoWanted, logoPath, outPath]() {
        QImageReader reader(originalAbs);
        reader.setAutoTransform(true);
        const QSize full = reader.size();
        if (full.isValid() && qMax(full.width(), full.height()) > 1280)
            reader.setScaledSize(full.scaled(1280, 1280, Qt::KeepAspectRatio));
        const QImage original = reader.read();
        QImage logo;
        if (!logoPath.isEmpty()) { QImageReader logoReader(logoPath); logoReader.setAutoTransform(true); logo = logoReader.read(); }
        // El logo pedido y no legible se informa (no se oculta): la publicación lo rechaza.
        const QString warning = logoWanted && logo.isNull()
                ? QStringLiteral("El logo seleccionado no está disponible en este dispositivo.") : QString();
        QString error;
        if (original.isNull()) error = QStringLiteral("No se pudo leer la fotografía original.");
        else if (!paintPhotoDerivative(original, edit, logo).save(outPath, "JPG", 85))
            error = QStringLiteral("No se pudo generar la vista previa.");
        QMetaObject::invokeMethod(QCoreApplication::instance(), [self, idx, token, outPath, error, warning]() {
            if (!self) { QFile::remove(outPath); return; }
            self->m_photoPreviewRunning.remove(idx);
            const bool latest = !self->m_closed && self->m_photoPreviewLatest.value(idx) == token;
            if (latest && error.isEmpty()) {
                const QString previous = self->m_photoPreviewPath.value(idx);
                if (!previous.isEmpty() && previous != outPath) QFile::remove(previous);
                self->m_photoPreviewPath[idx] = outPath;
                emit self->photoPreviewReady(idx, token, QUrl::fromLocalFile(outPath), warning);
            } else {
                QFile::remove(outPath);
                if (latest) emit self->photoPreviewReady(idx, token, QUrl(), error);
            }
            if (!self->m_closed && self->m_photoPreviewPending.contains(idx)) {
                const QVariantMap next = self->m_photoPreviewPending.take(idx);
                self->launchPhotoPreview(idx, self->m_photoPreviewPendingToken.take(idx), next);
            }
        });
    });
}

// Balance de blancos automático (mundo gris sobre la original reducida): devuelve la
// temperatura y el tinte que neutralizan la dominante, en la escala del pipeline.
// Resolución única del logo de la ficha (misma regla que la UI _resolvedLogo y que
// portableState): ruta vacía = logo por defecto empaquetado; *_removed = sin logo;
// relativa = junto a la ficha o bajo la raíz de Documentos del usuario.
QString CalicataDocument::photoLogoPath(const QString &source) const
{
    const bool entity = source == QLatin1String("ENTITY");
    if (m_images.value(entity ? QStringLiteral("logo_mtc_removed") : QStringLiteral("logo_proyecto_removed")).toBool())
        return {};
    const QString path = m_images.value(entity ? QStringLiteral("logo_mtc_path")
                                               : QStringLiteral("logo_proyecto_path")).toString().trimmed();
    if (path.isEmpty())
        return entity ? QStringLiteral(":/images/ICONO_LOGO_MTC.jpeg") : QStringLiteral(":/images/INGEMA_LOGO_COMPLETO.png");
    if (path.startsWith(QLatin1String("qrc:"))) return path.mid(3);   // "qrc:/x" -> ":/x"
    if (path.startsWith(QLatin1Char(':')) || path.startsWith(QLatin1String("content:"), Qt::CaseInsensitive)) return path;
    const QUrl url(path);
    if (url.isLocalFile()) return QDir::cleanPath(url.toLocalFile());
    if (QDir::isAbsolutePath(path)) return QDir::cleanPath(path);
    const QString base = baseDirAbs();
    if (!base.isEmpty()) {
        const QString nearDocument = cleanPathJoin(base, QDir::cleanPath(path));
        if (QFileInfo::exists(nearDocument)) return nearDocument;
    }
    if (m_resourcesBase.trimmed().isEmpty()) return {};
    return cleanPathJoin(QDir::cleanPath(m_resourcesBase), QDir::cleanPath(path));
}

QString CalicataDocument::photoLogoUrl(const QString &source) const
{
    const QString path = photoLogoPath(source);
    if (path.isEmpty()) return {};
    if (path.startsWith(QLatin1Char(':'))) return QStringLiteral("qrc") + path;
    if (path.startsWith(QLatin1String("content:"), Qt::CaseInsensitive)) return path;
    if (!QFileInfo::exists(path)) return {};
    return QUrl::fromLocalFile(path).toString();
}

QVariantMap CalicataDocument::suggestAutoWhiteBalance(int idx) const
{
    QVariantMap out{{QStringLiteral("warmth"), 0}, {QStringLiteral("tint"), 0}};
    const QUrl url = originalPhotoUrl(idx);
    if (url.isEmpty()) return out;
    QImageReader reader(url.toLocalFile());
    reader.setAutoTransform(true);
    const QSize full = reader.size();
    if (full.isValid()) reader.setScaledSize(full.scaled(160, 160, Qt::KeepAspectRatio));
    const QImage img = reader.read().convertToFormat(QImage::Format_RGB32);
    if (img.isNull()) return out;
    double r = 0, g = 0, b = 0;
    qint64 n = 0;
    for (int y = 0; y < img.height(); ++y) {
        const QRgb *line = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < img.width(); ++x) {
            const double l = (0.299 * qRed(line[x]) + 0.587 * qGreen(line[x]) + 0.114 * qBlue(line[x])) / 255.0;
            if (l < 0.06 || l > 0.94) continue;
            r += qRed(line[x]); g += qGreen(line[x]); b += qBlue(line[x]); ++n;
        }
    }
    if (n == 0) return out;
    r /= n; g /= n; b /= n;
    out[QStringLiteral("warmth")] = qBound(-100, qRound((b - r) / 255.0 / 0.16 * 100.0), 100);
    out[QStringLiteral("tint")] = qBound(-100, qRound(((r + b) / 2.0 - g) / 255.0 / 0.09 * 100.0), 100);
    return out;
}

// Borrador de edición: se guarda en la ficha (autosave normal), sin generar versión
// ni publicar.
bool CalicataDocument::savePhotoEditDraft(int idx, const QVariantMap &edit)
{
    if (m_closed || idx < 1 || idx > 3) return false;
    m_images[photoSlotKey(idx, QStringLiteral("edit"))] = edit;
    emit dataChanged();
    setDirty(true);
    return true;
}

bool CalicataDocument::renderDerivedPhoto(int idx, const QVariantMap &edit)
{
    if (m_closed || idx < 1 || idx > 3) return false;
    const QUrl originalUrl = originalPhotoUrl(idx);
    if (originalUrl.isEmpty()) {
        setErrorString(QStringLiteral("La fotografía original no está disponible."));
        return false;
    }
    const QString folder = cachedPhotosTypeFolderAbs(idx);
    if (folder.isEmpty() || !QDir().mkpath(folder)) {
        setErrorString(QStringLiteral("No se pudo preparar el almacenamiento de fotografías."));
        return false;
    }
    // Logo PROJECT / ENTITY of the ficha drawn on the photograph (Web logoAnchor/logoScalePct).
    // Same resolver as the editor preview, so the published derivative matches it.
    const QVariantMap logoEdit = edit.value(QStringLiteral("logo")).toMap();
    const bool logoWanted = logoEdit.value(QStringLiteral("enabled")).toBool();
    const QString logoPath = logoWanted ? photoLogoPath(logoEdit.value(QStringLiteral("source")).toString()) : QString();
    if (logoWanted && logoPath.isEmpty()) {
        setErrorString(QStringLiteral("La ficha no tiene logo disponible para esta fuente."));
        return false;
    }
    const QString originalAbs = originalUrl.toLocalFile();
    const QString versionId = QUuid::createUuid().toString(QUuid::WithoutBraces);
    const QString outPath = cleanPathJoin(folder, photoPrefixForIdx(idx) + QStringLiteral("_derivada_")
                                          + versionId + QStringLiteral(".jpg"));
    qInfo().noquote() << "INGE_PHOTO_COMPOSE_START idx=" << idx << "version=" << versionId;
    QPointer<CalicataDocument> self(this);
    QThreadPool::globalInstance()->start([self, idx, edit, originalAbs, logoPath, outPath, versionId]() {
        QImageReader reader(originalAbs);
        reader.setAutoTransform(true);   // EXIF orientation; original bytes untouched
        const QImage original = reader.read();
        QImage logo;
        if (!logoPath.isEmpty()) {
            QImageReader logoReader(logoPath);
            logoReader.setAutoTransform(true);
            logo = logoReader.read();
        }
        QString error;
        if (original.isNull()) {
            error = QStringLiteral("No se pudo leer la fotografía original.");
        } else if (!logoPath.isEmpty() && logo.isNull()) {
            // Never publish a derivative silently missing the logo the user configured.
            error = QStringLiteral("No se pudo leer el logo seleccionado.");
        } else {
            const QImage derived = paintPhotoDerivative(original, edit, logo);
            QSaveFile file(outPath);
            if (!file.open(QIODevice::WriteOnly) || !derived.save(&file, "JPG", 92) || !file.commit())
                error = QStringLiteral("No se pudo guardar la fotografía derivada.");
        }
        QMetaObject::invokeMethod(QCoreApplication::instance(), [self, idx, edit, outPath, versionId, error]() {
            if (!self) return;   // el editor también perdió su documento: lo cierra su watchdog
            // Toda ejecución termina en SUCCESS o ERROR: una ficha cerrada/reemplazada
            // (p. ej. tras cambiar el código) responde con error en vez de callar.
            if (self->m_closed) {
                QFile::remove(outPath);
                qWarning().noquote() << "INGE_PHOTO_COMPOSE_FAILED idx=" << idx << "reason=document_closed";
                emit self->derivedPhotoReady(idx, QUrl(), QString(),
                                             QStringLiteral("La ficha cambió durante la generación. Vuelve a intentarlo."));
                return;
            }
            if (!error.isEmpty()) {
                qWarning().noquote() << "INGE_PHOTO_COMPOSE_FAILED idx=" << idx << "reason=" << error;
                emit self->derivedPhotoReady(idx, QUrl(), QString(), error);
                return;
            }
            const auto key = [idx](const char *suffix) { return photoSlotKey(idx, QLatin1String(suffix)); };
            QVariantMap images = self->m_images;
            if (images.value(key("original_path")).toString().isEmpty())
                images[key("original_path")] = images.value(key("path"));
            const QString stored = self->hasSavedFile() ? self->relFromAbsInBase(outPath) : outPath;
            QVariantMap version;
            version[QStringLiteral("local_version_id")] = versionId;
            version[QStringLiteral("derived_path")] = stored;
            version[QStringLiteral("edit")] = edit;
            version[QStringLiteral("created_at")] = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
            version[QStringLiteral("state")] = QStringLiteral("PENDING");
            QVariantList versions = images.value(key("versions")).toList();
            versions.prepend(version);
            while (versions.size() > 30) versions.removeLast();
            images[key("versions")] = versions;
            images[key("edit")] = edit;
            images[key("path")] = stored;
            images[key("active_local_version")] = versionId;
            images[key("sync")] = QStringLiteral("PENDING");
            images[key("pending_op")] = QStringLiteral("PUBLISH");
            images[QStringLiteral("storage")] = self->hasSavedFile() ? QStringLiteral("editable_jpg_v2")
                                                                     : QStringLiteral("editable_jpg_v2_pending");
            if (!self->commitPhotoImages(images)) {
                emit self->derivedPhotoReady(idx, QUrl(), QString(), self->errorString());
                return;
            }
            if (appContext()) appContext()->notifyLocalFileModified(outPath);
            qInfo().noquote() << "INGE_PHOTO_COMPOSE_SUCCESS idx=" << idx << "version=" << versionId;
            emit self->derivedPhotoReady(idx, QUrl::fromLocalFile(outPath), versionId, QString());
        }, Qt::QueuedConnection);
    });
    return true;
}

bool CalicataDocument::restorePhotoVersion(int idx, const QString &localVersionId)
{
    if (m_closed || idx < 1 || idx > 3) return false;
    const auto key = [idx](const char *suffix) { return photoSlotKey(idx, QLatin1String(suffix)); };
    QVariantMap images = m_images;
    for (const QVariant &value : images.value(key("versions")).toList()) {
        const QVariantMap version = value.toMap();
        if (version.value(QStringLiteral("local_version_id")).toString() != localVersionId) continue;
        // Restoring only changes which derivative is in use; the original and
        // every other version stay where they are.
        images[key("path")] = version.value(QStringLiteral("derived_path"));
        images[key("edit")] = version.value(QStringLiteral("edit"));
        images[key("active_local_version")] = localVersionId;
        images[key("sync")] = QStringLiteral("PENDING");
        images[key("pending_op")] = version.value(QStringLiteral("cloud_version_id")).toString().isEmpty()
            ? QStringLiteral("PUBLISH") : QStringLiteral("ACTIVATE");
        return commitPhotoImages(images);
    }
    return false;
}

bool CalicataDocument::emptyPhotoSlot(int idx)
{
    if (m_closed || idx < 1 || idx > 3) return false;
    const auto key = [idx](const char *suffix) { return photoSlotKey(idx, QLatin1String(suffix)); };
    QVariantMap images = m_images;
    if (images.value(key("original_path")).toString().isEmpty())
        images[key("original_path")] = images.value(key("path"));
    images[key("path")] = QString();
    images[key("active_local_version")] = QString();
    images[key("sync")] = QStringLiteral("PENDING");
    images[key("pending_op")] = QStringLiteral("EMPTY_SLOT");
    return commitPhotoImages(images);
}

void CalicataDocument::setPhotoCloudState(int idx, const QVariantMap &changes)
{
    if (m_closed || idx < 1 || idx > 3) return;
    QVariantMap images = m_images;
    const QString localId = changes.value(QStringLiteral("local_version_id")).toString();
    for (auto it = changes.cbegin(); it != changes.cend(); ++it) {
        if (it.key() == QLatin1String("version_state") || it.key() == QLatin1String("local_version_id")
            || it.key() == QLatin1String("cloud_version_id"))
            continue;
        images[photoSlotKey(idx, it.key())] = it.value();
    }
    // Per-version confirmation (cloud_version_id / state) by local id.
    if (!localId.isEmpty()) {
        QVariantList versions = images.value(photoSlotKey(idx, QStringLiteral("versions"))).toList();
        for (QVariant &value : versions) {
            QVariantMap version = value.toMap();
            if (version.value(QStringLiteral("local_version_id")).toString() != localId) continue;
            if (changes.contains(QStringLiteral("cloud_version_id")))
                version[QStringLiteral("cloud_version_id")] = changes.value(QStringLiteral("cloud_version_id"));
            if (changes.contains(QStringLiteral("version_state")))
                version[QStringLiteral("state")] = changes.value(QStringLiteral("version_state"));
            value = version;
        }
        images[photoSlotKey(idx, QStringLiteral("versions"))] = versions;
    }
    if (images == m_images) return;
    // Cloud bookkeeping is not an edit: the dirty flag stays as it was.
    const bool wasDirty = m_dirty;
    m_images = images;
    emit dataChanged();
    if (!wasDirty) {
        saveDraft();
        setDirty(false);
    }
}

// P3: a stratum created on the server gets its UUID in the local mirror at
// once (matched by the stable local_stratum_id, never by position), so a retry
// after a later failure updates it instead of appending a duplicate.
bool CalicataDocument::bindStratumIdentity(const QString &localStratumId, const QString &remoteStratumId)
{
    if (m_closed || localStratumId.isEmpty() || remoteStratumId.isEmpty()) return false;
    for (qsizetype i = 0; i < m_cortes.size(); ++i) {
        QVariantMap row = m_cortes.at(i).toMap();
        QJsonObject extra = QJsonDocument::fromJson(row.value(QStringLiteral("_extraJson")).toString().toUtf8()).object();
        const QString rowLocal = row.value(QStringLiteral("local_stratum_id"),
                                           extra.value(QStringLiteral("local_stratum_id")).toString()).toString();
        if (rowLocal != localStratumId) continue;
        row[QStringLiteral("remote_stratum_id")] = remoteStratumId;
        if (row.contains(QStringLiteral("_extraJson"))) {
            extra[QStringLiteral("remote_stratum_id")] = remoteStratumId;
            row[QStringLiteral("_extraJson")] = QString::fromUtf8(QJsonDocument(extra).toJson(QJsonDocument::Compact));
        }
        m_cortes[i] = row;
        const bool wasDirty = m_dirty;
        saveDraft();
        if (!wasDirty) setDirty(false);
        qInfo().noquote() << "INGE_CALICATA_BIND_IDENTITY stratum local=" << localStratumId << "remote=" << remoteStratumId;
        emit stratumIdentityBound(localStratumId, remoteStratumId);
        return true;
    }
    return false;
}

bool CalicataDocument::adoptRemotePhoto(int idx, const QVariantMap &remote)
{
    if (m_closed || idx < 1 || idx > 3) return false;
    const auto key = [idx](const char *suffix) { return QStringLiteral("foto%1_%2").arg(idx).arg(QLatin1String(suffix)); };
    QVariantMap images = m_images;
    const QString cloudVersion = remote.value(QStringLiteral("version_id")).toString();
    const bool unpublished = images.value(key("sync")).toString() == QLatin1String("PENDING")
        && !images.value(key("pending_op")).toString().isEmpty();
    if (unpublished && images.value(key("cloud_active_version_id")).toString() != cloudVersion) return false;
    const auto stored = [this](const QString &abs) { return hasSavedFile() ? relFromAbsInBase(abs) : abs; };
    const QString localVersion = QStringLiteral("cloud:") + cloudVersion;
    QVariantList versions = images.value(key("versions")).toList();
    bool known = false;
    for (const QVariant &value : versions) {
        const QVariantMap v = value.toMap();
        if (v.value(QStringLiteral("cloud_version_id")).toString() == cloudVersion) known = true;
    }
    if (!known && !cloudVersion.isEmpty()) {
        QVariantMap version;
        version[QStringLiteral("local_version_id")] = localVersion;
        version[QStringLiteral("cloud_version_id")] = cloudVersion;
        version[QStringLiteral("derived_path")] = stored(remote.value(QStringLiteral("derived_abs")).toString());
        version[QStringLiteral("edit")] = remote.value(QStringLiteral("annotation")).toMap();
        version[QStringLiteral("created_at")] = QDateTime::currentDateTimeUtc().toString(Qt::ISODateWithMs);
        version[QStringLiteral("state")] = QStringLiteral("SYNCED");
        versions.prepend(version);
        images[key("versions")] = versions;
    }
    images[key("original_path")] = stored(remote.value(QStringLiteral("original_abs")).toString());
    images[key("path")] = stored(remote.value(QStringLiteral("derived_abs")).toString());
    images[key("edit")] = remote.value(QStringLiteral("annotation")).toMap();
    // Datos de captura de ESA foto (hora del sistema fijada, EXIF): la regeneración
    // en este dispositivo conserva la misma hora que el dispositivo de origen.
    const QVariantMap remoteCapture = remote.value(QStringLiteral("annotation")).toMap()
                                          .value(QStringLiteral("capture")).toMap();
    if (!remoteCapture.isEmpty()) images[key("capture")] = remoteCapture;
    images[key("media_id")] = remote.value(QStringLiteral("media_id"));
    images[key("cloud_active_version_id")] = cloudVersion;
    images[key("active_local_version")] = localVersion;
    images[key("sync")] = QStringLiteral("SYNCED");
    images[key("pending_op")] = QString();
    images[key("new_original")] = false;
    return commitPhotoImages(images);
}
