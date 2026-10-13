#pragma once

#include <QObject>
#include <QString>
#include <QSet>

class SupabaseClient;
class AuthSession;
class CloudDocs;

// V55:
// En Android AppContext no usa metaobjeto Qt para evitar errores AUTOMOC.
// Se mantienen todos los métodos usados por archivos antiguos:
// appContext(), registerOpenFile(), unregisterOpenFile(), isOpenFile().

class AppContext : public QObject
{
#ifndef INGE_MOBILE
    Q_OBJECT

    Q_PROPERTY(QString supabaseUrl READ supabaseUrl CONSTANT)
    Q_PROPERTY(QString supabaseAnonKey READ supabaseAnonKey CONSTANT)
    Q_PROPERTY(QString supabaseBucket READ supabaseBucket CONSTANT)
#endif

public:
    explicit AppContext(QObject *parent = nullptr);
    ~AppContext() override;

    static AppContext* instance();
    static void setInstance(AppContext* ctx);

    SupabaseClient* supabase() const { return m_supabase; }
    AuthSession* auth() const { return m_auth; }
    CloudDocs* docs() const { return m_docs; }

    QString supabaseUrl() const;
    QString supabaseAnonKey() const;
    QString supabaseBucket() const;

#ifndef INGE_MOBILE
    Q_INVOKABLE
#endif
    void notifyLocalFileModified(const QString& absPath);

#ifndef INGE_MOBILE
    Q_INVOKABLE
#endif
    bool hasOpenUnderDir(const QString& dirAbs) const;

    void registerOpenFile(const QString& absPath);
    void unregisterOpenFile(const QString& absPath);
    bool isOpenFile(const QString& absPath) const;

#ifndef INGE_MOBILE
signals:
    void localFileModified(const QString& absPath);
#endif

private:
    SupabaseClient* m_supabase = nullptr;
    AuthSession* m_auth = nullptr;
    CloudDocs* m_docs = nullptr;
    QSet<QString> m_openFiles;
};

inline AppContext* appContext()
{
    return AppContext::instance();
}
