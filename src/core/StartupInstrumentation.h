#pragma once

#include <QDebug>
#include <QElapsedTimer>
#include <QMetaProperty>
#include <QSignalMapper>
#include <array>

namespace inge::core {

// Main-thread observer. Fixed storage, one log per event, no timers or I/O
// beyond diagnostic logging. Must outlive the observed objects.
class StartupInstrumentation final {
public:
    enum class Event { PROCESS_START, FIRST_UI, AUTH_START, AUTH_READY, HOME_READY };

    StartupInstrumentation()
    {
        m_clock.start();
        mark(Event::PROCESS_START);
    }

    bool mark(Event event)
    {
        const auto index = static_cast<size_t>(event);
        if (index >= m_times.size() || m_times[index] >= 0)
            return false;
        m_times[index] = m_clock.elapsed();
        qInfo().nospace() << "INGE_STARTUP " << name(event)
                          << " elapsedMs=" << m_times[index];
        return true;
    }

    qint64 elapsedMs(Event event) const
    {
        const auto index = static_cast<size_t>(event);
        return index < m_times.size() ? m_times[index] : -1;
    }

    // Observe an existing QML bool through its notify signal. Does not mutate
    // QML, evaluate scripts, poll Flutter or initialize a host.
    bool watchReadyProperty(QObject *object, const char *propertyName, Event event)
    {
        if (!object)
            return false;
        const auto meta = object->metaObject();
        const int index = meta->indexOfProperty(propertyName);
        if (index < 0)
            return false;
        const QMetaProperty property = meta->property(index);
        if (property.metaType().id() != QMetaType::Bool || !property.hasNotifySignal())
            return false;
        auto *observer = new QSignalMapper(object);
        observer->setMapping(object, 0);
        QObject::connect(object, property.notifySignal(), observer,
            observer->metaObject()->method(observer->metaObject()->indexOfSlot("map()")));
        const auto check = [this, object, property, event]() {
            if (property.read(object).toBool())
                mark(event);
        };
        QObject::connect(observer, &QSignalMapper::mappedInt, observer, check);
        check(); // Handles a property already true when the QML root is loaded.
        return true;
    }

private:
    static const char *name(Event event)
    {
        constexpr std::array names{"PROCESS_START", "FIRST_UI", "AUTH_START",
                                   "AUTH_READY", "HOME_READY"};
        return names[static_cast<size_t>(event)];
    }
    QElapsedTimer m_clock;
    std::array<qint64, 5> m_times{{-1, -1, -1, -1, -1}};
};

} // namespace inge::core
