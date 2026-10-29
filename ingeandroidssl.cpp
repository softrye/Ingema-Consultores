#include "ingeandroidssl.h"

#include <QDebug>
#include <QSslSocket>

void ingeConfigureAndroidSsl()
{
#ifdef Q_OS_ANDROID
    qputenv("ANDROID_OPENSSL_SUFFIX", "_3");
    qputenv("QT_NETWORK_DISABLE_HTTP2", "1");
#endif

    qInfo().noquote() << "[InGe+ SSL] ANDROID_OPENSSL_SUFFIX="
                      << qEnvironmentVariable("ANDROID_OPENSSL_SUFFIX");
    qInfo().noquote() << "[InGe+ SSL] supportsSsl="
                      << QSslSocket::supportsSsl()
                      << "build=" << QSslSocket::sslLibraryBuildVersionString()
                      << "runtime=" << QSslSocket::sslLibraryVersionString();
}
