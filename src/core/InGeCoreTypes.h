#pragma once

#include "InGeCoreContext.h"
#include "InGeCoreSkill.h"

#include <QDateTime>
#include <QStringList>
#include <QVariantMap>

namespace inge::core {

enum class Status { IDLE, QUEUED, RUNNING, SUCCESS, FAILED, OFFLINE, CANCELLED };
enum class Priority { Low, Normal, High };
enum class Source { None, Local, Remote };

struct Request {
    // Caller supplies a nonempty correlation ID and its own context snapshot.
    QString requestId;
    Skill skill = Skill::Unknown;
    QString operation;
    InGeCoreContext context;
    QVariantMap payload;
    Priority priority = Priority::Normal;
    bool allowRemote = false;
    bool allowLocal = false;
    QDateTime createdAt = QDateTime::currentDateTimeUtc();
};

struct Response {
    QString requestId;
    Status status = Status::IDLE;
    QVariantMap result;
    // -1 means no confidence estimate is available.
    double confidence = -1.0;
    QStringList warnings;
    Source source = Source::None;
    qint64 latencyMs = 0;
    QString errorCode;
    QString errorMessage;
};

} // namespace inge::core
