#pragma once

#include "InGeCoreTypes.h"

namespace inge::core {
class InGeCoreExecutor;

// Application-thread facade, lazily constructed on first explicit access.
// No QML registration, workers, I/O, model loading or execution in microphase 0.
class InGeCore final {
public:
    static InGeCore &instance();

    InGeCore(const InGeCore &) = delete;
    InGeCore &operator=(const InGeCore &) = delete;
    InGeCore(InGeCore &&) = delete;
    InGeCore &operator=(InGeCore &&) = delete;

    // Idempotent; false when the build-time feature flag is disabled.
    bool initializeLightweight();
    bool isReady() const;
    void setExecutor(InGeCoreExecutor *executor) { m_executor = executor; }

    // Immediate explicit rejection until executors exist; never queues work.
    Response submit(const Request &request);
    // True only if active work was cancelled. There is no active work yet.
    bool cancel(const QString &requestId);

    // Replaces the entire snapshot, including empty fields on account changes.
    void updateContext(const InGeCoreContext &context);
    InGeCoreContext context() const;

private:
    InGeCore() = default;
    bool m_ready = false;
    InGeCoreExecutor *m_executor = nullptr;
    InGeCoreContext m_context;
};

} // namespace inge::core
