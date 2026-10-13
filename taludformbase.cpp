#include "taludformbase.h"

#include <QTimer>
#include <QFileInfo>
#include <QDir>

TaludFormBase::TaludFormBase(QWidget *parent)
    : QMainWindow(parent)
    , m_autoSaveTimer(new QTimer(this))
{
    m_autoSaveTimer->setInterval(m_autoSaveIntervalMs);
    m_autoSaveTimer->setSingleShot(false);

    connect(m_autoSaveTimer, &QTimer::timeout,
            this, &TaludFormBase::onAutoSaveTimeout);


    setWindowTitle(tr("Ficha de Talud"));
}

TaludFormBase::~TaludFormBase() = default;

// ------------------------------------------------------------
// Estado común
// ------------------------------------------------------------
QString TaludFormBase::currentFilePath() const
{
    return m_currentFilePath;
}

bool TaludFormBase::isDirty() const
{
    return m_dirty;
}

bool TaludFormBase::autoSaveEnabled() const
{
    return m_autoSaveEnabled;
}

int TaludFormBase::autoSaveIntervalMs() const
{
    return m_autoSaveIntervalMs;
}

void TaludFormBase::setAutoSaveEnabled(bool enabled)
{
    if (m_autoSaveEnabled == enabled)
        return;

    m_autoSaveEnabled = enabled;

    if (m_autoSaveEnabled) {
        m_autoSaveTimer->start();
    } else {
        m_autoSaveTimer->stop();
    }

    emit autoSaveEnabledChanged(m_autoSaveEnabled);
}

void TaludFormBase::setAutoSaveIntervalMs(int ms)
{
    if (ms < 1000)
        ms = 1000;

    if (m_autoSaveIntervalMs == ms)
        return;

    m_autoSaveIntervalMs = ms;

    if (m_autoSaveTimer)
        m_autoSaveTimer->setInterval(m_autoSaveIntervalMs);
}

// ------------------------------------------------------------
// Helpers protegidos
// ------------------------------------------------------------
void TaludFormBase::setCurrentFilePathInternal(const QString& filePath)
{
    const QString clean = QDir::cleanPath(QDir::fromNativeSeparators(filePath.trimmed()));

    if (m_currentFilePath == clean)
        return;

    m_currentFilePath = clean;

    emit currentFilePathChanged(m_currentFilePath);

    // Normalmente el nombre visible cambia cuando la ficha ya tiene archivo
    emit displayNameChanged();
    updateWindowTitleWithDirtyMark();
}

void TaludFormBase::clearCurrentFilePathInternal()
{
    if (m_currentFilePath.isEmpty())
        return;

    m_currentFilePath.clear();

    emit currentFilePathChanged(m_currentFilePath);
    emit displayNameChanged();
    updateWindowTitleWithDirtyMark();
}

void TaludFormBase::setDirtyInternal(bool dirty)
{
    if (m_dirty == dirty)
        return;

    m_dirty = dirty;
    emit dirtyChanged(m_dirty);
    updateWindowTitleWithDirtyMark();
}

void TaludFormBase::markDirty()
{
    setDirtyInternal(true);
}

void TaludFormBase::setBaseWindowTitle(const QString& title)
{
    const QString t = title.trimmed();
    if (m_baseWindowTitle == t)
        return;

    m_baseWindowTitle = t;
    updateWindowTitleWithDirtyMark();
}

QString TaludFormBase::baseWindowTitle() const
{
    return m_baseWindowTitle;
}

void TaludFormBase::notifyDisplayNameChanged()
{
    emit displayNameChanged();
    updateWindowTitleWithDirtyMark();
}

void TaludFormBase::updateWindowTitleWithDirtyMark()
{
    QString title = m_baseWindowTitle.trimmed();

    if (title.isEmpty()) {
        title = tr("Ficha de Talud");
    }

    if (m_dirty)
        title += " *";

    setWindowTitle(title);
}
// ------------------------------------------------------------
// Auto-save por defecto
// ------------------------------------------------------------
void TaludFormBase::onAutoSaveTimeout()
{
    if (!m_autoSaveEnabled)
        return;

    if (!m_dirty)
        return;

    if (m_currentFilePath.isEmpty())
        return;

    guardar();
}
