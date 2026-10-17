#pragma once
// Fuente ÚNICA del estado de conexión de Rendiciones (auras, cola y comandos).
//
// Combina dos tipos de evidencia, sin sondeos agresivos:
//  1. Eventos del sistema (QNetworkInformation): sin red => desconexión inmediata;
//     red disponible => sólo "posible": nunca se declara ONLINE por tener Wi-Fi.
//  2. Resultado real del transporte de cada RPC:
//       respuesta HTTP 2xx/4xx (incluidos conflictos CAS y errores de negocio)
//         => el servidor RESPONDIÓ: hay conexión efectiva;
//       sin respuesta, timeout o 5xx => servidor inaccesible;
//       401 => autenticación requerida (el servidor sí respondió).
//
// Un conflicto CAS NUNCA es un estado de conexión: vive en su fila/outbox.
// Una falla de red NUNCA es un conflicto: la operación sigue pendiente.
#include <QString>
#include <algorithm>

namespace RenditionConnectivity {

enum class Link { Unknown, NoNetwork, ServerUnreachable, Online, AuthRequired };
enum class Outcome { Reachable, Unreachable, Auth, Local };

// Marca técnica persistida en syncError de una operación que espera conexión.
// No es texto para el usuario: RenditionLocalStore::syncStatus la oculta.
inline QString transportMarker() { return QStringLiteral("TRANSPORT_RETRY"); }

// Códigos de transporte: el servidor no confirmó nada (la operación sigue pendiente).
inline bool isTransportFailure(const QString &code)
{
    const QString c = code.toUpper();
    return c.contains(QStringLiteral("NETWORK")) || c.contains(QStringLiteral("TIMEOUT"))
        || c == QLatin1String("OFFLINE") || c == QLatin1String("SERVER_UNREACHABLE")
        || c == QLatin1String("TRANSPORT_RETRY")
        || c == QLatin1String("ATTACHMENT_UPLOAD_NEEDS_RECONCILIATION")
        || (c.startsWith(QStringLiteral("HTTP_5")) && c.size() == 8)
        || c == QLatin1String("HTTP_0");
}

// Errores que el usuario no debe ver como aviso: los comunica el aura.
inline bool isSilent(const QString &code)
{
    // Sesión expirada: es un ESTADO (aura roja + diagnóstico con "Renovar sesión"),
    // no un aviso emergente repetido por cada intento de sincronización.
    return isTransportFailure(code) || code == QLatin1String("SYNC_BUSY")
        || code == QLatin1String("PULL_BUSY") || code == QLatin1String("AUTH_REQUIRED")
        || code == QLatin1String("HTTP_401");
}

// Clasificación por código ya normalizado por el repositorio.
inline Outcome classify(const QString &code)
{
    const QString c = code.toUpper();
    if (isTransportFailure(c)) return Outcome::Unreachable;
    if (c == QLatin1String("AUTH_REQUIRED") || c == QLatin1String("HTTP_401")) return Outcome::Auth;
    return Outcome::Reachable;
}

// Clasificación por respuesta HTTP real (0 = sin respuesta).
inline Outcome classifyHttp(int status, bool transportError)
{
    if (status == 401) return Outcome::Auth;
    if (status >= 200 && status < 500) return Outcome::Reachable;
    Q_UNUSED(transportError)
    return Outcome::Unreachable;   // 0 (sin respuesta/timeout/DNS) o 5xx
}

class State {
public:
    Link link() const { return m_link; }
    int failures() const { return m_failures; }
    bool networkAvailable() const { return m_network; }
    bool offline() const { return m_link == Link::NoNetwork || m_link == Link::ServerUnreachable; }
    bool online() const { return m_link == Link::Online; }

    // Evento del sistema. Devuelve true si cambió el estado publicado.
    bool onNetwork(bool available)
    {
        const Link before = m_link;
        m_network = available;
        if (!available) {
            m_link = Link::NoNetwork;
        } else if (m_link == Link::NoNetwork) {
            // Red recuperada: aún sin evidencia del servidor. Se mantiene la
            // desconexión hasta que una petición real responda (sin parpadeos).
            m_link = Link::ServerUnreachable;
            m_failures = 0;
        }
        return before != m_link;
    }

    // Evidencia de transporte. Devuelve true si cambió el estado publicado.
    bool onTransport(Outcome outcome)
    {
        const Link before = m_link;
        switch (outcome) {
        case Outcome::Reachable:
            m_link = Link::Online;
            m_network = true;
            m_failures = 0;
            break;
        case Outcome::Auth:
            m_link = Link::AuthRequired;
            m_network = true;
            m_failures = 0;
            break;
        case Outcome::Unreachable: {
            // Un intento (pull de ~8 RPC) cuenta UNA vez: la espera crece por intento.
            const bool firstLoss = !offline();
            m_link = m_network ? Link::ServerUnreachable : Link::NoNetwork;
            if (firstLoss || m_attemptOpen) {
                m_failures = std::min(m_failures + 1, 16);
                m_attemptOpen = false;
            }
            break;
        }
        case Outcome::Local:
            break;                       // sin contacto con el servidor: no es evidencia
        }
        return before != m_link;
    }

    // Marca el inicio de un reintento de reconexión (cuenta para la espera creciente).
    void beginAttempt() { m_attemptOpen = true; }

    // Reintento controlado con espera creciente (15 s, 30 s, 60 s… máx. 5 min).
    // Sólo aplica con red disponible y servidor inaccesible; sin red se espera al evento.
    int retryDelayMs() const
    {
        if (m_link != Link::ServerUnreachable) return -1;
        const int step = std::max(0, m_failures - 1);
        return std::min(15000 << std::min(step, 5), 300000);
    }

    // Compatibilidad con consumidores existentes (QML/Flutter): OFFLINE cubre
    // "sin red" y "servidor inaccesible"; el detalle va en connectivity().
    QString connectionState() const
    {
        switch (m_link) {
        case Link::Online: return QStringLiteral("ONLINE");
        case Link::NoNetwork:
        case Link::ServerUnreachable: return QStringLiteral("OFFLINE");
        case Link::AuthRequired: return QStringLiteral("AUTH_REQUIRED");
        case Link::Unknown: break;
        }
        return QStringLiteral("UNKNOWN");
    }
    QString connectivity() const
    {
        switch (m_link) {
        case Link::Online: return QStringLiteral("ONLINE");
        case Link::NoNetwork: return QStringLiteral("NO_NETWORK");
        case Link::ServerUnreachable: return QStringLiteral("SERVER_UNREACHABLE");
        case Link::AuthRequired: return QStringLiteral("AUTH_REQUIRED");
        case Link::Unknown: break;
        }
        return QStringLiteral("UNKNOWN");
    }

private:
    Link m_link = Link::Unknown;
    bool m_network = true;   // sin información del sistema se asume posible (se verifica)
    int m_failures = 0;
    bool m_attemptOpen = false;
};

} // namespace RenditionConnectivity
