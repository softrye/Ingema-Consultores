#pragma once

#include <QHash>
#include <QObject>
#include <QSet>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

// Host-owned source of truth for the single contextual dock.
//
// Surfaces (QML, Flutter, Earth JS) publish a semantic snapshot:
//   ownerId, contextId, actions[] {id,label,icon,command,enabled,visible,
//   selected,badge,priority,repeatable,destructive,children[]}
// `children` makes an action hierarchical: tap runs `command` (the primary
// action) or, when the action has no command, opens its children; long press
// always opens them. Children use the same fields recursively (kMaxDepth
// levels). Every id is unique across the whole tree so a dispatch resolves
// one node. How a branch is drawn belongs to the dock view only.
// The controller validates and normalises it, keeps the latest snapshot per
// owner and exposes exactly one active snapshot: the one of the foreground
// owner declared by the shell. Every activation bumps a monotonic generation.
// It has no knowledge of any subapp and accepts no geometry or theme fields.
class DockContextController : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int generation READ generation NOTIFY contextChanged)
    Q_PROPERTY(QString ownerId READ ownerId NOTIFY contextChanged)
    Q_PROPERTY(QString contextId READ contextId NOTIFY contextChanged)
    Q_PROPERTY(QVariantList actions READ actions NOTIFY contextChanged)
    Q_PROPERTY(QString foregroundOwner READ foregroundOwner WRITE setForegroundOwner NOTIFY foregroundOwnerChanged)
    Q_PROPERTY(bool ingeCoreAvailable READ ingeCoreAvailable NOTIFY capabilitiesChanged)
    Q_PROPERTY(bool transitionPending READ transitionPending NOTIFY transitionPendingChanged)
    // Optional backdrop image for native surfaces Qt cannot sample, provided
    // by the channel of the active snapshot (e.g. the Earth WebView).
    Q_PROPERTY(QString nativeBackdrop READ nativeBackdrop NOTIFY nativeBackdropChanged)
    Q_PROPERTY(qreal nativeBackdropLuma READ nativeBackdropLuma NOTIFY nativeBackdropChanged)

public:
    explicit DockContextController(QObject *parent = nullptr);
    ~DockContextController() override;

    static DockContextController *instance();

    int generation() const { return m_generation; }
    QString ownerId() const { return m_active.ownerId; }
    QString contextId() const { return m_active.contextId; }
    QVariantList actions() const { return m_active.actions; }
    QString channel() const { return m_active.channel; }
    QString foregroundOwner() const { return m_foregroundOwner; }
    bool ingeCoreAvailable() const { return m_ingeCoreAvailable; }
    bool transitionPending() const { return m_transitionPending; }

    void setForegroundOwner(const QString &ownerId);
    void setIngeCoreAvailable(bool available);

    Q_INVOKABLE bool publishContext(const QString &ownerId, const QString &contextId,
                                    const QVariantList &actions,
                                    const QString &channel = QStringLiteral("qml"));
    Q_INVOKABLE bool clearContext(const QString &ownerId);
    Q_INVOKABLE bool preloadContext(const QString &ownerId, const QString &contextId,
                                    const QVariantList &actions,
                                    const QString &channel = QStringLiteral("qml"));
    Q_INVOKABLE bool activatePreloadedContext(const QString &ownerId, const QString &contextId);

    // The dock view reports the band it occupies so native surfaces drawn
    // above the Qt window (Flutter, Earth WebView) leave it uncovered.
    Q_INVOKABLE void setNativeBand(int pixels);
    QString nativeBackdrop() const { return m_nativeBackdrop; }
    qreal nativeBackdropLuma() const { return m_nativeBackdropLuma; }
    void setNativeBackdrop(const QString &channel, const QString &json);
    Q_INVOKABLE void setNativeGeometry(float left, float width, float height,
                                      float bottom, float coreSize, float gap,
                                      float searchWidth, float searchHeight, float searchGap);

    // Native entry points (already on the Qt thread). The channel comes from
    // the entry point, never from the payload.
    bool publishJson(const QString &channel, const QString &json);
    bool clearFromChannel(const QString &channel, const QString &ownerId);

    // Resolves an id anywhere in the active tree. A node is returned only when
    // it and all of its ancestors are visible and enabled.
    QVariantMap actionById(const QString &actionId) const;

signals:
    void contextChanged();
    void foregroundOwnerChanged();
    void capabilitiesChanged();
    void transitionPendingChanged();
    void nativeBackdropChanged();

private:
    struct Snapshot {
        QString ownerId;
        QString contextId;
        QString channel;
        QVariantList actions;
        bool isEmpty() const { return ownerId.isEmpty(); }
        bool sameAs(const Snapshot &other) const
        {
            return ownerId == other.ownerId && contextId == other.contextId
                && channel == other.channel && actions == other.actions;
        }
    };

    bool buildSnapshot(const QString &ownerId, const QString &contextId,
                       const QVariantList &actions, const QString &channel,
                       Snapshot *out) const;
    QVariantList normalizeActions(const QVariantList &actions, int depth,
                                  const QString &owner, const QString &context,
                                  QSet<QString> *ids) const;
    void activate(const Snapshot &snapshot);
    void beginTransition();
    static QString preloadKey(const QString &ownerId, const QString &contextId);

    Snapshot m_active;
    QHash<QString, Snapshot> m_latestByOwner;
    QHash<QString, Snapshot> m_preloaded;
    QString m_foregroundOwner;
    int m_generation = 0;
    int m_nativeBand = -1;
    bool m_ingeCoreAvailable = false;
    bool m_transitionPending = false;
    QString m_nativeBackdrop;
    QString m_nativeBackdropChannel;
    QString m_nativeBackdropOwner;
    qreal m_nativeBackdropLuma = -1.0;
    bool m_commitQueued = false;
};
