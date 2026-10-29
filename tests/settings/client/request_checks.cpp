#include "../../../supabaseclient.h"
#include <QCoreApplication>
#include <QNetworkRequest>
#include <cstdio>
int authChecks();

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    QCoreApplication::setApplicationVersion(QStringLiteral("1.0.0-test"));
    SupabaseClient client(QStringLiteral("https://example.invalid"), QStringLiteral("test-public-key"));
    const auto request = client.makeRequest(client.restUrl(QStringLiteral("rpc/list_my_auth_sessions_v01")),
                                            QStringLiteral("test-user-credential"), 20000);
    const QByteArray ua = request.rawHeader("User-Agent");
    if (!ua.startsWith("InGePlus-Desktop/1.0.0-test (") || !ua.endsWith(')')
        || ua.contains('\r') || ua.contains('\n')) {
        std::fputs("FAIL: request must identify app version and platform with a safe User-Agent\n", stderr);
        return 1;
    }
    if (request.rawHeader("apikey") != QByteArrayLiteral("test-public-key")
        || request.rawHeader("Authorization") != QByteArrayLiteral("Bearer test-user-credential")
        || request.transferTimeout() != 20000
        || client.makeRequest(client.authUrl(QStringLiteral("token"))).hasRawHeader("Authorization")) {
        std::fputs("FAIL: request credentials or timeout contract changed\n", stderr);
        return 1;
    }
    std::puts("PASS: User-Agent, session-header isolation and timeout");
    return authChecks();
}
