#pragma once

#include <QString>
#include <QVariantMap>
#include <QVariantList>

namespace inge::core {

enum class Connectivity { Unknown, Offline, Online };
enum class DeviceTier { Unknown, Low, Medium, High };

// Bounded operational snapshot. Never include credentials or reasoning traces.
struct InGeCoreContext {
    QString authenticatedUserId;
    QString activeProjectId;
    QString activeModule;
    QString activeEntityId;
    Connectivity connectivity = Connectivity::Unknown;
    DeviceTier deviceTier = DeviceTier::Unknown;
    QVariantMap currentFields, entity, rules, permissions, deviceProfile;
    QVariantList attachments, relatedHistory, pendingOperations, recentActions;

    QVariantMap toVariantMap() const {
        return {{"schema_version", 2}, {"user", QVariantMap{{"id", authenticatedUserId}}},
            {"project", QVariantMap{{"id", activeProjectId}}}, {"module", activeModule},
            {"entity", entity}, {"entity_id", activeEntityId}, {"current_fields", currentFields},
            {"attachments", attachments}, {"related_history", relatedHistory.mid(0, 20)},
            {"rules", rules}, {"permissions", permissions}, {"device_profile", deviceProfile},
            {"connectivity", QVariantMap{{"state", connectivity == Connectivity::Online ? "ONLINE" :
                connectivity == Connectivity::Offline ? "OFFLINE" : "UNKNOWN"}}},
            {"pending_operations", pendingOperations.mid(0, 20)}, {"recent_actions", recentActions.mid(0, 20)}};
    }
};

} // namespace inge::core
