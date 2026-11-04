#pragma once

#include <QDateTime>
#include <QHash>
#include <QObject>
#include <QSet>
#include <QString>

// Identidad visible en la presencia de Realtime (Calicatas y Rendiciones),
// común a SupabaseRealtimeChannel y CalicataCloudService.
//
// - Color: el mismo que la Web (presenceIdentity.ts): FNV-1a del userId sobre
//   la paleta de 8 tonos «-400» de Tailwind. Misma persona, mismo color.
// - Foto: la meta publica la REFERENCIA del perfil ("storage://avatars/<uid>/…",
//   igual que profiles.avatar_url), nunca una URL firmada: cada receptor la firma
//   con su propio token, descarga solo los bytes a la caché y expone un file://.
//   Ningún token viaja por el canal ni llega a QML. Si no se puede leer, la
//   inicial es el respaldo.
namespace PresenceIdentity {
QString colorFor(const QString &userId);
QString initialsFor(const QString &name);
QString selfAvatarRef();                       // "" si el perfil no tiene foto privada
bool isAvatarRef(const QString &ref);
}

class PresenceAvatarCache : public QObject
{
    Q_OBJECT
public:
    static PresenceAvatarCache *instance();
    // file:// listo para Image, o "" mientras se descarga / si falla.
    QString source(const QString &ref);

signals:
    void avatarReady(const QString &ref);

private:
    explicit PresenceAvatarCache(QObject *parent = nullptr);
    QString cachePath(const QString &ref) const;
    void fetch(const QString &ref);

    QSet<QString> m_pending;
    QHash<QString, QDateTime> m_failedAt;      // reintento como mucho cada 10 min
};
