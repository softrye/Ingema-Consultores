#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <functional>

class QNetworkReply;

// Solicitudes de acceso (perfiles PENDIENTE) para administradores, en paridad
// con la Web. Solo RPC SECURITY DEFINER con el token del usuario (nunca
// service_role): el servidor decide quién puede listar y aprobar.
//  - Listado:   list_profiles_for_administration_v02 (p_status = PENDIENTE)
//  - Roles:     list_assignable_institutional_roles_v01
//  - Aprobar:   approve_profile_with_role_controlled_v01
//  - Proyecto:  create_project_team_member_with_access_v01 (opcional)
//  - Rechazar:  [PENDIENTE SERVIDOR] no existe RPC de rechazo.
class AccessRequestsClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList requests READ requests NOTIFY requestsChanged)
    Q_PROPERTY(QVariantList roles READ roles NOTIFY rolesChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString error READ error NOTIFY errorChanged)
    Q_PROPERTY(bool rejectAvailable READ rejectAvailable CONSTANT)

public:
    explicit AccessRequestsClient(QObject *parent = nullptr);

    QVariantList requests() const { return m_requests; }
    QVariantList roles() const { return m_roles; }
    bool busy() const { return m_pending > 0; }
    QString error() const { return m_error; }
    bool rejectAvailable() const { return false; }   // [PENDIENTE SERVIDOR]

    Q_INVOKABLE void refresh();
    // projectId vacío: solo aprueba el perfil. accessLevel: NONE, READ o WRITE.
    Q_INVOKABLE void approve(const QString &profileId, const QString &expectedUpdatedAt,
                             const QString &roleCode, const QString &projectId,
                             const QString &projectRole, const QString &accessLevel);
    Q_INVOKABLE void reject(const QString &profileId);

signals:
    void requestsChanged();
    void rolesChanged();
    void busyChanged();
    void errorChanged();
    void actionFinished(bool ok, const QString &message);

private:
    using Done = std::function<void(bool ok, const QVariant &result, const QString &error)>;
    void callRpc(const QString &name, const QVariantMap &params, Done done);
    void setError(const QString &error);
    static QString friendlyError(const QString &raw);

    QVariantList m_requests;
    QVariantList m_roles;
    QString m_error;
    int m_pending = 0;
};
