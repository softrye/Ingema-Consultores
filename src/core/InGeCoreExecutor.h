#pragma once

#include "InGeCoreTypes.h"

namespace inge::core {

enum class ExecutorHealth { DISABLED, NOT_AVAILABLE, READY };

// Shared contract for future LocalExecutor, RemoteExecutor and HybridExecutor.
// Implementations must not block the UI: execute returns an immediate terminal
// response or QUEUED acknowledgement with the same requestId. Async completion
// delivery will be defined before introducing any real backend.
class InGeCoreExecutor {
public:
    virtual ~InGeCoreExecutor() = default;
    virtual bool canExecute(const Request &request) const = 0;
    virtual Response execute(const Request &request) = 0;
    // False means there was no active request to cancel.
    virtual bool cancel(const QString &requestId) = 0;
    // Cached/local availability only; health must never probe the network.
    virtual ExecutorHealth health() const = 0;
};

class NullExecutor final : public InGeCoreExecutor {
public:
    explicit NullExecutor(bool enabled = false) : m_enabled(enabled) {}

    bool canExecute(const Request &) const override { return false; }
    Response execute(const Request &request) override
    {
        Response response;
        response.requestId = request.requestId;
        response.status = Status::FAILED;
        response.errorCode = m_enabled ? QStringLiteral("NOT_AVAILABLE")
                                       : QStringLiteral("DISABLED");
        response.errorMessage = m_enabled
            ? QStringLiteral("No intelligence executor is available.")
            : QStringLiteral("Intelligence execution is disabled.");
        return response;
    }
    bool cancel(const QString &) override { return false; }
    ExecutorHealth health() const override
    {
        return m_enabled ? ExecutorHealth::NOT_AVAILABLE : ExecutorHealth::DISABLED;
    }

private:
    const bool m_enabled;
};

} // namespace inge::core
