#pragma once

#include <QList>
#include <QString>
#include <QStringList>
#include <QVariant>
#include <QVariantMap>
#include <QtGlobal>
#include <cmath>
#include <functional>

// Coordinación de escrituras remotas de UNA ficha desde esta sesión.
//
// Servidor (DEV, verificado en private.enforce_calicata_invariants): todo UPDATE
// de public.calicatas suma 1 a row_version, salvo un cambio "live"
// (apply_calicata_field_change_v02) que modifique exactamente UNA columna. Si el
// valor live ya era el vigente (p. ej. lo acaba de escribir el autosave), no
// cambia ninguna columna y el servidor SÍ suma 1 sin devolver la revisión:
// la siguiente escritura CAS del mismo dispositivo recibía 40001.
//
// Reglas puras (sin red), usadas por CalicataCloudService:
//  - una sola escritura que mueva row_version en vuelo por ficha (Lane);
//  - syncs pedidas mientras tanto se coalescen en una sola (la más fuerte);
//  - la revisión esperada nunca es menor que la última confirmada en sesión;
//  - un salto de revisión solo se adopta si se demuestra propio.
namespace CalicataSync {

// Columnas raíz de contenido (row_version / updated_at no son contenido).
inline const QStringList &rootColumns()
{
    static const QStringList columns{
        QStringLiteral("code"), QStringLiteral("title"), QStringLiteral("location"),
        QStringLiteral("progresiva"), QStringLiteral("easting"), QStringLiteral("northing"),
        QStringLiteral("altitude_m"), QStringLiteral("depth_m"), QStringLiteral("groundwater_depth_m"),
        QStringLiteral("utm_zone"), QStringLiteral("supervisor"), QStringLiteral("machine"),
        QStringLiteral("start_date"), QStringLiteral("end_date"), QStringLiteral("description"),
        QStringLiteral("observations"), QStringLiteral("status"),
        // 20261007181000: hora de la ficha y metadato de la cota.
        QStringLiteral("start_time"), QStringLiteral("altitude_source"), QStringLiteral("altitude_mode"),
        QStringLiteral("altitude_confidence"), QStringLiteral("altitude_accuracy_m"),
        QStringLiteral("altitude_vertical_reference"), QStringLiteral("altitude_resolved_at")};
    return columns;
}

inline QString valueText(const QVariant &value)
{
    return value.isValid() && !value.isNull() ? value.toString().trimmed() : QString();
}

// Igualdad de valores tal como los devuelve PostgREST (numeric 661554 == "661554.00").
inline bool sameValue(const QVariant &a, const QVariant &b)
{
    const QString ta = valueText(a), tb = valueText(b);
    if (ta == tb) return true;
    bool okA = false, okB = false;
    const double da = ta.toDouble(&okA), db = tb.toDouble(&okB);
    return okA && okB && std::fabs(da - db) <= 1e-9 * qMax(1.0, std::fabs(da));
}

// La fila remota coincide con lo que ESTA sesión dejó: base confirmada + sus
// escrituras live posteriores. Sin base no se puede demostrar nada.
inline bool rootMatches(const QVariantMap &server, const QVariantMap &base, const QVariantMap &ownLive)
{
    if (base.isEmpty() || server.isEmpty()) return false;
    for (const QString &column : rootColumns()) {
        const QVariant expected = ownLive.contains(column) ? ownLive.value(column) : base.value(column);
        if (!sameValue(server.value(column), expected)) return false;
    }
    return true;
}

// Revisión con la que debe empezar una escritura: la del documento, salvo que
// esta sesión ya haya confirmado una posterior para la misma ficha remota.
inline qint64 expectedRevision(qint64 documentRevision, qint64 sessionConfirmed)
{
    return qMax(documentRevision, sessionConfirmed);
}

// Tras un cambio live propio (sondeo antes = before, después = after).
enum class LiveWrite { Unchanged, OwnNoopBump, Unexplained };
inline LiveWrite attributeLiveWrite(qint64 confirmed, qint64 before, qint64 after,
                                    bool fieldHoldsOurValue, bool otherColumnsUnchanged)
{
    if (before != confirmed) return LiveWrite::Unexplained;   // algo externo ocurrió antes
    if (after == before) return LiveWrite::Unchanged;          // el servidor no movió la revisión
    if (after == before + 1 && fieldHoldsOurValue && otherColumnsUnchanged)
        return LiveWrite::OwnNoopBump;                         // el +1 es nuestro (valor ya vigente)
    return LiveWrite::Unexplained;
}

// 40001 en una escritura CAS: rebase + UN reintento solo si el salto queda
// explicado por escrituras propias no verificadas y la fila coincide con lo
// propio. Todo lo demás es un conflicto real (nunca se sobrescribe).
enum class Stale { Rebase, RealConflict };
inline Stale classifyStale(qint64 expected, qint64 server, int uncertainOwnBumps,
                           bool rootConsistent, bool alreadyRetried)
{
    if (alreadyRetried || server <= expected) return Stale::RealConflict;
    return server - expected <= uncertainOwnBumps && rootConsistent ? Stale::Rebase : Stale::RealConflict;
}

inline int reasonRank(const QString &reason)
{
    if (reason == QLatin1String("export")) return 3;
    if (reason == QLatin1String("save")) return 2;
    return 1; // autosave
}

// Cola por ficha: una escritura en vuelo; syncs coalescidas; operaciones de
// estado en orden. La sync pendiente lee el documento al arrancar, así que
// siempre sube el snapshot local más reciente.
class Lane
{
public:
    enum class Request { Started, Coalesced };
    struct Next { QString syncReason; std::function<void()> operation; };

    bool busy() const { return m_busy; }
    QString queuedSync() const { return m_queuedSync; }
    int deferredCount() const { return int(m_deferred.size()); }
    quint64 generation() const { return m_generation; }

    bool tryAcquire()
    {
        if (m_busy) return false;
        m_busy = true;
        return true;
    }
    Request requestSync(const QString &reason)
    {
        if (tryAcquire()) { ++m_generation; return Request::Started; }
        if (m_queuedSync.isEmpty() || reasonRank(reason) > reasonRank(m_queuedSync)) m_queuedSync = reason;
        return Request::Coalesced;
    }
    void defer(std::function<void()> operation) { m_deferred.append(std::move(operation)); }
    // Libera la escritura en vuelo y entrega la siguiente (sync primero: lleva
    // el contenido más nuevo; luego cambios de estado en orden de llegada).
    Next release()
    {
        m_busy = false;
        Next next;
        if (!m_queuedSync.isEmpty()) { next.syncReason = m_queuedSync; m_queuedSync.clear(); }
        else if (!m_deferred.isEmpty()) next.operation = m_deferred.takeFirst();
        return next;
    }
    // Conflicto real: no se encadenan más escrituras de contenido.
    void dropQueuedSync() { m_queuedSync.clear(); }

    // Contabilidad de revisiones propias.
    qint64 confirmedRevision = 0;   // última revisión que el servidor confirmó a esta sesión
    int uncertainOwnBumps = 0;      // cambios live propios cuyo efecto no se pudo sondear
    QVariantMap baseRoot;           // fila raíz confirmada (PATCH propio o sondeo)
    QVariantMap ownLive;            // valores live propios aplicados desde baseRoot
    bool retryAfterRebase = false;  // la próxima sync es el reintento único

private:
    bool m_busy = false;
    quint64 m_generation = 0;
    QString m_queuedSync;
    QList<std::function<void()>> m_deferred;
};

} // namespace CalicataSync
