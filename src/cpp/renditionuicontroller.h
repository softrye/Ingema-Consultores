#pragma once

#include <QHash>
#include <QObject>
#include <QPointer>
#include <QStringList>
#include <QUrl>
#include <QVariantMap>

// Adaptador de presentación QML de Rendiciones (subapp nativa, 2026-10-14).
//
// No contiene reglas de negocio propias ni acceso a Supabase: envía comandos
// JSON al bridge existente (RenditionFlutterBridge::submit), correlaciona cada
// commandResult por requestId, evita solicitudes duplicadas por pulsaciones
// repetidas (clave de formulario) y publica el último evento "state". Los
// cálculos monetarios, permisos y validaciones delegan en RenditionMoney,
// RenditionContract y RenditionValidation (las mismas que usa el dominio).
class RenditionUiController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantMap state READ state NOTIFY stateChanged)
    Q_PROPERTY(bool ready READ ready NOTIFY stateChanged)
    Q_PROPERTY(QStringList pendingKeys READ pendingKeys NOTIFY pendingChanged)
    Q_PROPERTY(bool aiEnabled READ aiEnabled CONSTANT)
    // Incidencias centralizadas (RenditionDiagnostics): {level, incidents, errors, attention}.
    Q_PROPERTY(QVariantMap diagnostics READ diagnostics NOTIFY diagnosticsChanged)

public:
    explicit RenditionUiController(QObject *bridge, QObject *parent = nullptr);

    QVariantMap state() const { return m_state; }
    bool ready() const { return m_ready; }
    QStringList pendingKeys() const;
    bool aiEnabled() const;

    // Comando al bridge. Devuelve el requestId, o "" si [key] ya tiene una
    // solicitud en curso (doble pulsación) o el bridge no está disponible.
    Q_INVOKABLE QString send(const QString &operation, const QVariantMap &arguments = {},
                             const QString &key = {});
    Q_INVOKABLE bool isPending(const QString &key) const;
    Q_INVOKABLE QString newId() const;

    // Reglas del dominio expuestas a QML (sin duplicarlas en JavaScript).
    Q_INVOKABLE bool canEdit(const QVariantMap &rendition) const;
    Q_INVOKABLE QString headerError(const QVariantMap &header) const;
    Q_INVOKABLE QString expenseError(const QVariantMap &rendition, const QVariantMap &expense) const;
    Q_INVOKABLE QString amountError(const QString &amount) const;
    Q_INVOKABLE QString formatMoney(const QVariant &amount, const QString &currency) const;
    Q_INVOKABLE QString formatCents(const QVariant &cents, const QString &currency) const;
    Q_INVOKABLE QVariantMap totals(const QVariantList &expenses) const;
    Q_INVOKABLE QVariantMap fundBalance(const QVariantMap &rendition) const;
    // Avance de completitud (0..100) derivado de los requisitos reales de
    // presentación; known=false cuando faltan datos para evaluarlo.
    Q_INVOKABLE QVariantMap completion(const QVariantMap &rendition) const;
    Q_INVOKABLE QString fundingError(const QVariantMap &values) const;
    Q_INVOKABLE QString rateError(const QString &rate) const;
    Q_INVOKABLE QVariantList catalog(const QString &kind) const;
    Q_INVOKABLE QVariantMap project(const QString &id) const;
    Q_INVOKABLE QString projectLabel(const QString &id) const;
    Q_INVOKABLE QVariantList filterRenditions(const QString &query, const QString &status,
                                              const QString &projectId) const;
    Q_INVOKABLE QString syncLabel(const QString &syncState) const;
    Q_INVOKABLE QString statusLabel(const QString &status) const;
    Q_INVOKABLE QString errorText(const QString &code, const QString &message) const;
    // Política de avisos: la pérdida de conexión, timeouts y reintentos automáticos
    // NO se muestran como texto/toast; los comunica el aura (estado publicado).
    Q_INVOKABLE bool silentError(const QString &code) const;
    // Texto persistido de una fila apto para mostrarse (oculta marcas técnicas).
    Q_INVOKABLE QString visibleSyncError(const QString &text) const;
    // Estado mostrado de una fila cruda (gasto/sustento): un ERROR que sólo espera
    // conexión (marca de transporte) se presenta como pendiente, nunca como error.
    Q_INVOKABLE QString effectiveSyncState(const QVariantMap &row) const;
    Q_INVOKABLE QVariantMap describeLocalFile(const QUrl &url) const;

    QVariantMap diagnostics() const { return m_diagnostics; }
    // Falla de una acción explícita del usuario (antes un toast): se registra como
    // incidencia consultable en "Estado de Rendiciones" y vence en 3 min o al
    // repetirse con éxito la misma acción (key). Nunca contiene secretos.
    Q_INVOKABLE void reportIssue(const QString &key, const QVariantMap &issue);
    Q_INVOKABLE void resolveIssue(const QString &key);
    Q_INVOKABLE QString today() const;
    Q_INVOKABLE bool validDate(const QString &value) const;

signals:
    void stateChanged();
    void pendingChanged();
    void diagnosticsChanged();
    void finished(const QString &requestId, const QString &operation, const QString &key,
                  bool ok, const QVariantMap &result, const QString &code, const QString &message);
    // Error de comando sin solicitud correlacionada (p. ej. openDocumentTarget).
    void bridgeError(const QString &code, const QString &message);
    void bridgeEvent(const QString &type, const QVariantMap &event);

private slots:
    void handleEvent(const QString &eventJson);

private:
    struct Pending { QString operation; QString key; };
    void recomputeDiagnostics();
    QPointer<QObject> m_bridge;
    QVariantMap m_state;
    QVariantMap m_diagnostics;
    QVariantMap m_issues;            // key -> issue (+ "at" ms)
    bool m_issueTickScheduled = false;
    bool m_ready = false;
    QHash<QString, Pending> m_pending;
};
