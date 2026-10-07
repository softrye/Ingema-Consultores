#include "appcontext.h"
#include "supabaseclient.h"
#include "authsession.h"
#include "clouddocs.h"
#include "settingshelper.h"
#include "src/cpp/renditionexportservice.h"

#include <QSettings>
#include <QDir>
#include <QDebug>


static AppContext* g_ctx = nullptr;

AppContext* AppContext::instance() { return g_ctx; }
void AppContext::setInstance(AppContext* ctx) { g_ctx = ctx; }


AppContext::AppContext(QObject *parent)
    : QObject(parent)
{
    // ✅ NEW SERVER REF: aalmeaqhhlhzwwzsbbxz
    const QString projectUrl = "https://aalmeaqhhlhzwwzsbbxz.supabase.co";
    const QString anonKey    = "sb_publishable_-ch81VY9aD-kQGZjWq1N7w_yZ6DzNb1";

    const QString bucket     = "IngePlus"; // <-- tu bucket real

    QSettings s = appSettings();
    s.setValue("supabase/url", projectUrl);

    // ✅ guarda en ambas para compatibilidad
    s.setValue("supabase/anon",     anonKey);
    s.setValue("supabase/anon_key", anonKey);

    s.setValue("supabase/bucket", bucket);
    s.sync();

    qDebug() << "[AppContext] Supabase config:"
             << "url=" << s.value("supabase/url").toString()
             << "keyPresent=" << !anonKey.isEmpty()
             << "keyLength=" << anonKey.size()
             << "bucket=" << s.value("supabase/bucket").toString();


    m_supabase = new SupabaseClient(projectUrl, anonKey, this);
    m_auth     = new AuthSession(m_supabase, this);

    m_docs = new CloudDocs(m_supabase, m_auth, this);
    // Restore pending exports on login even when the export screen is never opened.
    RenditionExportService::shared(m_supabase, m_auth);


    // La restauración de sesión se inicia desde Main.qml para que la UI
    // muestre un estado de carga y nunca entre accidentalmente como invitado.
}

AppContext::~AppContext() = default;

QString AppContext::supabaseUrl() const
{
    QSettings s = appSettings();
    QString v = s.value("supabase/url").toString();
    if (v.isEmpty()) v = s.value("supabase/base_url").toString();
    if (v.isEmpty()) v = s.value("base_url").toString();
    return v;
}

QString AppContext::supabaseAnonKey() const
{
    QSettings s = appSettings();
    QString v = s.value("supabase/anon").toString();        // 👈 primero
    if (v.isEmpty()) v = s.value("supabase/anon_key").toString();
    if (v.isEmpty()) v = s.value("supabase/anon-key").toString();
    if (v.isEmpty()) v = s.value("anon_key").toString();
    return v;
}


QString AppContext::supabaseBucket() const
{
    QSettings s = appSettings();
    QString v = s.value("supabase/bucket").toString();
    if (v.isEmpty()) v = s.value("bucket").toString();
    return v;
}

void AppContext::notifyLocalFileModified(const QString& absPath)
{
#ifdef INGE_MOBILE
    Q_UNUSED(absPath)
#else
    emit localFileModified(absPath);
#endif
}

bool AppContext::hasOpenUnderDir(const QString& dirAbs) const
{
    const QString prefix = QDir::cleanPath(dirAbs) + QDir::separator();
    for (const QString& p : m_openFiles) {
        if (p.startsWith(prefix))
            return true;
    }
    return false;
}

void AppContext::registerOpenFile(const QString& absPath)
{
    const QString clean = QDir::cleanPath(absPath);
    if (!clean.isEmpty())
        m_openFiles.insert(clean);
}

void AppContext::unregisterOpenFile(const QString& absPath)
{
    const QString clean = QDir::cleanPath(absPath);
    if (!clean.isEmpty())
        m_openFiles.remove(clean);
}

bool AppContext::isOpenFile(const QString& absPath) const
{
    const QString clean = QDir::cleanPath(absPath);
    return !clean.isEmpty() && m_openFiles.contains(clean);
}
