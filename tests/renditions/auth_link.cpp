// Unused Auth link boundary: tests use the explicit isolated account scope.
// Persistence, outbox and mutation guards remain the production implementation.
#include "appcontext.h"
#include "authsession.h"
AppContext *AppContext::instance() { qFatal("Test must not access application Auth"); return nullptr; }
QString AppContext::supabaseUrl() const { qFatal("Unexpected Auth access"); return {}; }
bool AuthSession::logged() const { qFatal("Unexpected Auth access"); return false; }
const QMetaObject AuthSession::staticMetaObject = QObject::staticMetaObject;
void AuthSession::loggedOut() {}
void AuthSession::userInfoChanged() {}
void AuthSession::currentAccountChanged() {}
