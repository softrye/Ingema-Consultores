#pragma once
// Modelo CENTRALIZADO de incidencias de Rendiciones (fuente única para auras y
// para el panel "Estado de Rendiciones"). Función pura sobre el estado REAL
// publicado por el bridge (conexión, fichas, gastos, borradores) más las fallas
// de acciones del usuario aún vigentes. Sin IA: catálogo determinista de
// problemas conocidos, con causa, ubicación, solución verificable y la acción
// real disponible (o ninguna). Nunca incluye tokens, credenciales ni rutas.
//
// Severidad (prioridad de las auras):
//   error     -> azul + ROJO: impide operar (sin conexión, sesión, permisos,
//                conflicto real, rechazo del servidor)
//   attention -> azul + AMARILLO: fallo TÉCNICO localizado y recuperable (gasto
//                rechazado por el servidor, carga de sustento fallida, bytes de
//                un borrador que nunca llegaron al servidor)
// NO son incidencias (tareas del usuario, se ofrecen como sugerencias en la
// ficha): gasto incompleto, sin sustento, observado o borrador sin terminar.
//   (ninguna) -> azul + verde cuando además todo está sincronizado.
#include "renditionconnectivity.h"
#include "renditioncontract.h"
#include "renditionvalidation.h"

#include <QSet>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>

namespace RenditionDiagnostics {

inline QVariantMap action(const QString &kind, const QString &label)
{
    return {{QStringLiteral("kind"), kind}, {QStringLiteral("label"), label}};
}

inline QVariantMap incident(const QString &key, const QString &code, const QString &severity,
                            const QString &title, const QString &area, const QString &what,
                            const QString &how, const QVariantMap &act = {})
{
    return {{QStringLiteral("key"), key}, {QStringLiteral("code"), code},
            {QStringLiteral("severity"), severity}, {QStringLiteral("title"), title},
            {QStringLiteral("area"), area}, {QStringLiteral("what"), what},
            {QStringLiteral("how"), how}, {QStringLiteral("action"), act}};
}

// Sección del formulario de Nuevo gasto que corrige cada validación.
inline QString sectionFor(const QString &validation)
{
    const QString v = validation.toLower();
    if (v.contains(QStringLiteral("supporttype")) || v.contains(QStringLiteral("comprobante")))
        return QStringLiteral("receipt");
    if (v.contains(QStringLiteral("paymentmethod")) || v.contains(QStringLiteral("medio real de pago"))
        || v.contains(QStringLiteral("monto")) || v.contains(QStringLiteral("moneda")))
        return QStringLiteral("payment");
    if (v.contains(QStringLiteral("justificación")))
        return QStringLiteral("supports");
    return QStringLiteral("general");
}
inline QString sectionLabel(const QString &section)
{
    if (section == QLatin1String("receipt")) return QStringLiteral("Comprobante");
    if (section == QLatin1String("payment")) return QStringLiteral("Pago e importe");
    if (section == QLatin1String("supports")) return QStringLiteral("Sustentos");
    return QStringLiteral("General");
}

// Causa conocida o probable (evidencia en la que se basa el diagnóstico).
inline QString causeFor(const QString &code)
{
    if (code == QLatin1String("NO_NETWORK"))
        return QStringLiteral("El sistema operativo informa que no hay una red utilizable (Wi-Fi o datos móviles).");
    if (code == QLatin1String("SERVER_UNREACHABLE"))
        return QStringLiteral("Hay red, pero las últimas solicitudes al servidor terminaron sin respuesta, por tiempo de espera o con error 5xx.");
    if (code == QLatin1String("SESSION_EXPIRED"))
        return QStringLiteral("El servidor respondió 401: el token de acceso de esta sesión venció o fue revocado.");
    if (code == QLatin1String("RENDITION_CONFLICT") || code == QLatin1String("WORKING_CONFLICT"))
        return QStringLiteral("La versión del servidor cambió (control de versiones CAS) mientras había cambios locales sin enviar.");
    if (code == QLatin1String("SYNC_REJECTED") || code == QLatin1String("EXPENSE_REJECTED"))
        return QStringLiteral("El servidor recibió la operación y la rechazó por una regla de negocio o de datos.");
    if (code == QLatin1String("PERMISSION_DENIED"))
        return QStringLiteral("La cuenta actual no tiene el permiso efectivo que exige esta operación.");
    if (code == QLatin1String("UPLOAD_FAILED"))
        return QStringLiteral("La reserva, subida o confirmación del archivo fue rechazada por el servidor.");
    if (code == QLatin1String("SUPPORT_REATTACH"))
        return QStringLiteral("El archivo se registró en otro dispositivo, pero su transferencia nunca se completó.");
    return QStringLiteral("Falla informada por la última operación que iniciaste.");
}

inline bool editable(const QVariantMap &row)
{
    const QString status = row.value(QStringLiteral("status"), QStringLiteral("BORRADOR")).toString();
    return (status == QLatin1String("BORRADOR") || status == QLatin1String("OBSERVADO"))
        && row.value(QStringLiteral("archived")).toBool() == false
        && RenditionContract::canEditWorkingCopy(row);
}

inline QString code(const QVariantMap &row)
{
    const QString visible = row.value(QStringLiteral("visibleCode")).toString();
    return visible.isEmpty() ? QStringLiteral("Borrador") : visible;
}

// state: evento "state" del bridge. actionIssues: fallas vigentes de acciones del
// usuario (ya filtradas por vigencia). Devuelve {level, incidents, errors, attention}.
inline QVariantMap evaluate(const QVariantMap &state, const QVariantList &actionIssues = {})
{
    QVariantList list;
    QSet<QString> keys;
    const auto add = [&](QVariantMap item, const QString &rendition = {}, const QString &expense = {},
                         const QString &section = {}, const QString &working = {}) {
        const QString key = item.value(QStringLiteral("key")).toString();
        if (keys.contains(key)) return;                 // sin duplicados entre pantallas
        keys.insert(key);
        item.insert(QStringLiteral("renditionLocalId"), rendition);
        item.insert(QStringLiteral("expenseLocalId"), expense);
        item.insert(QStringLiteral("section"), section);
        item.insert(QStringLiteral("workingId"), working);
        list.append(item);
    };

    // ---- Conexión (fuente única: RenditionConnectivity vía bridge)
    const QString connection = state.value(QStringLiteral("connectionState")).toString();
    const QString connectivity = state.value(QStringLiteral("connectivity")).toString();
    if (connection == QLatin1String("OFFLINE")) {
        if (connectivity == QLatin1String("SERVER_UNREACHABLE"))
            add(incident(QStringLiteral("link"), QStringLiteral("SERVER_UNREACHABLE"), QStringLiteral("error"),
                QStringLiteral("Servidor no disponible"), QStringLiteral("Rendiciones · Sincronización"),
                QStringLiteral("Hay red, pero el servidor de InGe+ no responde. Trabajas con los datos de este equipo y tus cambios quedan guardados y pendientes de envío."),
                QStringLiteral("La sincronización se reintenta sola. Si usas Wi-Fi, comprueba que tenga acceso a Internet."),
                action(QStringLiteral("retry"), QStringLiteral("Reintentar ahora"))));
        else
            add(incident(QStringLiteral("link"), QStringLiteral("NO_NETWORK"), QStringLiteral("error"),
                QStringLiteral("Sin conexión"), QStringLiteral("Rendiciones · Sincronización"),
                QStringLiteral("El equipo no tiene red. Trabajas con los datos de este equipo y tus cambios quedan guardados y pendientes de envío."),
                QStringLiteral("Activa Wi-Fi o datos móviles; la sincronización se retoma sola cuando haya conexión efectiva.")));
    } else if (connection == QLatin1String("AUTH_REQUIRED")) {
        add(incident(QStringLiteral("link"), QStringLiteral("SESSION_EXPIRED"), QStringLiteral("error"),
            QStringLiteral("Sesión expirada"), QStringLiteral("Rendiciones · Sincronización"),
            QStringLiteral("La aplicación conserva tus cambios, pero necesita renovar la sesión para enviarlos al servidor."),
            QStringLiteral("Renueva la sesión. Si no se puede renovar, vuelve a iniciar sesión desde tu perfil y después revisa las operaciones pendientes."),
            action(QStringLiteral("renewSession"), QStringLiteral("Renovar sesión"))));
    }

    // ---- Fichas y gastos
    const QString selected = state.value(QStringLiteral("selectedLocalId")).toString();
    for (const auto &value : state.value(QStringLiteral("renditions")).toList()) {
        const QVariantMap row = value.toMap();
        if (row.value(QStringLiteral("archived")).toBool()) continue;
        const QString local = row.value(QStringLiteral("localId")).toString();
        const QString where = QStringLiteral("Rendición ") + code(row);
        const QString syncState = row.value(QStringLiteral("syncState")).toString();
        const QString syncError = row.value(QStringLiteral("syncError")).toString();
        const bool visibleError = !syncError.isEmpty() && syncError != RenditionConnectivity::transportMarker();
        if (syncState == QLatin1String("CONFLICT")) {
            add(incident(QStringLiteral("conflict:") + local, QStringLiteral("RENDITION_CONFLICT"), QStringLiteral("error"),
                QStringLiteral("Conflicto de versiones"), where + QStringLiteral(" · Sincronización"),
                visibleError ? syncError : QStringLiteral("La rendición cambió en otra sesión mientras tenías cambios locales."),
                QStringLiteral("Abre la rendición y trae la versión vigente del servidor; tus cambios locales se conservan para revisarlos."),
                action(QStringLiteral("openRendition"), QStringLiteral("Abrir rendición"))), local);
        } else if (syncState == QLatin1String("ERROR") && visibleError) {
            const QString lower = syncError.toLower();
            const bool permission = lower.contains(QStringLiteral("permiso")) || lower.contains(QStringLiteral("forbidden"))
                || lower.contains(QStringLiteral("not_editable")) || lower.contains(QStringLiteral("no tiene permiso"));
            if (permission)
                add(incident(QStringLiteral("rejected:") + local, QStringLiteral("PERMISSION_DENIED"), QStringLiteral("error"),
                    QStringLiteral("Permiso insuficiente"), where + QStringLiteral(" · Sincronización"), syncError,
                    QStringLiteral("Esta operación necesita un permiso que tu cuenta no tiene en esta rendición. Tus cambios se conservan; consulta con el responsable de la rendición.")),
                    local);
            else
                add(incident(QStringLiteral("rejected:") + local, QStringLiteral("SYNC_REJECTED"), QStringLiteral("error"),
                    QStringLiteral("El servidor rechazó un cambio"), where + QStringLiteral(" · Sincronización"), syncError,
                    QStringLiteral("Abre la rendición, corrige el dato indicado y vuelve a sincronizar. Tus cambios se conservan."),
                    action(QStringLiteral("openRendition"), QStringLiteral("Abrir rendición"))), local);
        }
        const int workingConflicts = row.value(QStringLiteral("workingConflictCount")).toInt();
        if (workingConflicts > 0)
            add(incident(QStringLiteral("working-conflict:") + local, QStringLiteral("WORKING_CONFLICT"), QStringLiteral("error"),
                QStringLiteral("Borrador en conflicto"), where + QStringLiteral(" · Borradores"),
                QStringLiteral("%1 borrador(es) de gasto cambiaron en otra sesión mientras tenías cambios.").arg(workingConflicts),
                QStringLiteral("Revisa la versión del servidor en Gastos y elige cuál conservar; nada se sobrescribe sin tu decisión."),
                action(QStringLiteral("openExpenses"), QStringLiteral("Revisar borradores"))), local);

        // Atención TÉCNICA localizada (no tareas del usuario). Un gasto incompleto,
        // sin sustento u observado por el revisor es trabajo pendiente: se ofrece
        // en las sugerencias de la ficha, NO es una incidencia ni cambia el aura.
        // Aquí sólo entra lo que realmente falló: el servidor rechazó el gasto o
        // la transferencia de un sustento no se completó.
        for (const auto &e : row.value(QStringLiteral("expenses")).toList()) {
            const QVariantMap expense = e.toMap();
            if (expense.value(QStringLiteral("archived")).toBool()) continue;
            const QString expenseId = expense.value(QStringLiteral("localId")).toString();
            const QString conceptText = expense.value(QStringLiteral("concept")).toString().trimmed();
            const QString label = where + QStringLiteral(" · Gasto «") + (conceptText.isEmpty() ? QStringLiteral("sin concepto") : conceptText) + QStringLiteral("»");
            const QString expenseState = expense.value(QStringLiteral("syncState")).toString();
            const QString expenseError = expense.value(QStringLiteral("syncError")).toString();
            if (expenseState == QLatin1String("ERROR") && !expenseError.isEmpty()
                && expenseError != RenditionConnectivity::transportMarker())
                add(incident(QStringLiteral("expense-rejected:") + expenseId, QStringLiteral("EXPENSE_REJECTED"), QStringLiteral("attention"),
                    QStringLiteral("Gasto rechazado por el servidor"), label, expenseError,
                    QStringLiteral("Abre el gasto, corrige el dato indicado y vuelve a registrarlo. Tu versión se conserva en el equipo."),
                    action(QStringLiteral("openExpense"), QStringLiteral("Abrir gasto"))), local, expenseId);
            int failedUploads = 0;
            QString uploadError;
            for (const auto &a : expense.value(QStringLiteral("attachments")).toList()) {
                const QVariantMap file = a.toMap();
                if (!file.value(QStringLiteral("archived_at")).toString().isEmpty()) continue;
                const QString fileState = file.value(QStringLiteral("syncState")).toString();
                const QString fileError = file.value(QStringLiteral("syncError")).toString();
                if ((fileState == QLatin1String("ERROR") || fileState == QLatin1String("CONFLICT"))
                    && !fileError.isEmpty() && fileError != RenditionConnectivity::transportMarker()) {
                    ++failedUploads;
                    uploadError = fileError;
                }
            }
            if (failedUploads > 0)
                add(incident(QStringLiteral("upload:") + expenseId, QStringLiteral("UPLOAD_FAILED"), QStringLiteral("attention"),
                    QStringLiteral("Carga de sustento no completada"), label,
                    QStringLiteral("%1 sustento(s) no se pudieron registrar en el servidor: %2").arg(failedUploads).arg(uploadError),
                    QStringLiteral("Reintenta la carga. Si vuelve a fallar, abre el gasto y reemplaza el archivo en Sustentos."),
                    action(QStringLiteral("retry"), QStringLiteral("Reintentar carga"))), local, expenseId, QStringLiteral("supports"));
        }
        // Borradores de la ficha abierta con bytes que nunca llegaron al servidor.
        if (local == selected) {
            for (const auto &w : state.value(QStringLiteral("workingRows")).toList()) {
                const QVariantMap draft = w.toMap();
                const int missing = draft.value(QStringLiteral("missingSources")).toInt();
                if (missing <= 0) continue;
                const QString conceptText = draft.value(QStringLiteral("form")).toMap().value(QStringLiteral("concept")).toString().trimmed();
                add(incident(QStringLiteral("reattach:") + draft.value(QStringLiteral("id")).toString(),
                    QStringLiteral("SUPPORT_REATTACH"), QStringLiteral("attention"),
                    QStringLiteral("Sustento por volver a adjuntar"),
                    where + QStringLiteral(" · Borrador «") + (conceptText.isEmpty() ? QStringLiteral("sin concepto") : conceptText) + QStringLiteral("»"),
                    QStringLiteral("%1 archivo(s) se registraron en otro dispositivo pero sus bytes nunca llegaron al servidor.").arg(missing),
                    QStringLiteral("Abre el borrador y vuelve a adjuntar el comprobante en Sustentos."),
                    action(QStringLiteral("openDraft"), QStringLiteral("Abrir borrador"))),
                    local, draft.value(QStringLiteral("expenseLocalId")).toString(), QStringLiteral("supports"),
                    draft.value(QStringLiteral("id")).toString());
            }
        }
    }

    // ---- Fallas de acciones del usuario (sin toasts: se consultan aquí)
    for (const auto &value : actionIssues) {
        QVariantMap issue = value.toMap();
        add(incident(QStringLiteral("action:") + issue.value(QStringLiteral("key")).toString(),
                     issue.value(QStringLiteral("code"), QStringLiteral("ACTION_FAILED")).toString(),
                     issue.value(QStringLiteral("severity"), QStringLiteral("error")).toString(),
                     issue.value(QStringLiteral("title"), QStringLiteral("Operación no completada")).toString(),
                     issue.value(QStringLiteral("area"), QStringLiteral("Rendiciones")).toString(),
                     issue.value(QStringLiteral("what")).toString(),
                     issue.value(QStringLiteral("how"), QStringLiteral("Revisa el dato o el permiso indicado y vuelve a intentarlo.")).toString(),
                     action(QStringLiteral("dismiss"), QStringLiteral("Entendido"))),
            issue.value(QStringLiteral("renditionLocalId")).toString());
    }

    for (auto &value : list) {
        QVariantMap item = value.toMap();
        item.insert(QStringLiteral("cause"), causeFor(item.value(QStringLiteral("code")).toString()));
        value = item;
    }

    int errors = 0, attention = 0;
    for (const auto &item : list) {
        const QString severity = item.toMap().value(QStringLiteral("severity")).toString();
        if (severity == QLatin1String("error")) ++errors; else ++attention;
    }
    // Primero lo bloqueante, luego lo localizado (orden estable dentro de cada grupo).
    QVariantList ordered;
    for (const auto &item : list) if (item.toMap().value(QStringLiteral("severity")) == QLatin1String("error")) ordered.append(item);
    for (const auto &item : list) if (item.toMap().value(QStringLiteral("severity")) != QLatin1String("error")) ordered.append(item);
    return {{QStringLiteral("level"), errors > 0 ? QStringLiteral("error") : attention > 0 ? QStringLiteral("attention") : QStringLiteral("ok")},
            {QStringLiteral("incidents"), ordered},
            {QStringLiteral("errors"), errors}, {QStringLiteral("attention"), attention}};
}

} // namespace RenditionDiagnostics
