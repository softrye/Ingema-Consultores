// Offline harness only. Production account/auth code is neither replaced nor run.
#include "appcontext.h"
#include "authsession.h"
AppContext* AppContext::instance() { return nullptr; }
void AppContext::registerOpenFile(const QString&) {}
void AppContext::unregisterOpenFile(const QString&) {}
bool AppContext::isOpenFile(const QString&) const { return false; }
void AppContext::notifyLocalFileModified(const QString&) {}
bool AuthSession::logged() const { return false; }
QString AuthSession::localUserFolderName() const { return {}; }
