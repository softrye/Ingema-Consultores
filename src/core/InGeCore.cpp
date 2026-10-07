#include "InGeCore.h"
#include "InGeCoreExecutor.h"

#include <QElapsedTimer>

// Safe even when compiled outside the application's CMake target.
#ifndef INGE_CORE_ENABLED
#define INGE_CORE_ENABLED 0
#endif

namespace inge::core {

InGeCore &InGeCore::instance()
{
    static InGeCore core;
    return core;
}

bool InGeCore::initializeLightweight()
{
    m_ready = (INGE_CORE_ENABLED != 0);
    return m_ready;
}

bool InGeCore::isReady() const
{
    return m_ready;
}

Response InGeCore::submit(const Request &request)
{
    QElapsedTimer timer;
    timer.start();
    Response response;
    response.requestId = request.requestId;
    response.status = Status::FAILED;
    if (!INGE_CORE_ENABLED) {
        response.errorCode = QStringLiteral("CORE_DISABLED");
        response.errorMessage = QStringLiteral("InGe Core is disabled.");
    } else if (!m_ready) {
        response.errorCode = QStringLiteral("CORE_NOT_READY");
        response.errorMessage = QStringLiteral("InGe Core has not been initialized.");
    } else {
        NullExecutor unavailable(true);
        response = m_executor ? m_executor->execute(request) : unavailable.execute(request);
    }
    response.latencyMs = timer.elapsed();
    return response;
}

bool InGeCore::cancel(const QString &requestId)
{
    return m_ready && m_executor && m_executor->cancel(requestId);
}

void InGeCore::updateContext(const InGeCoreContext &context)
{
    m_context = context;
}

InGeCoreContext InGeCore::context() const
{
    return m_context;
}

} // namespace inge::core
