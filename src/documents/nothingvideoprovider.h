// SPDX-License-Identifier: GPL-3.0-only
#pragma once
#include <QQuickImageProvider>
#include <QUrl>
#ifdef Q_OS_ANDROID
#include <QJniObject>
#include <QJniEnvironment>
#endif
class NothingVideoProvider final : public QQuickImageProvider {
public:
    NothingVideoProvider() : QQuickImageProvider(Image,ForceAsynchronousImageLoading) {}
    QImage requestImage(const QString &id,QSize *size,const QSize &) override {
        QImage image;
#ifdef Q_OS_ANDROID
        const auto path=QJniObject::fromString(QUrl::fromPercentEncoding(id.toUtf8()));
        const auto bytes=QJniObject::callStaticObjectMethod("com/ingema/ingeplus/NothingFileBridge","thumbnail","(Ljava/lang/String;)[B",path.object<jstring>());
        QJniEnvironment env;
        if(env->ExceptionCheck()) { env->ExceptionClear(); return image; }
        if(bytes.isValid()) {
            auto array=bytes.object<jbyteArray>();
            QByteArray data(env->GetArrayLength(array),Qt::Uninitialized);
            env->GetByteArrayRegion(array,0,data.size(),reinterpret_cast<jbyte*>(data.data()));
            image.loadFromData(data);
        }
#else
        Q_UNUSED(id)
#endif
        if(size) *size=image.size();
        return image;
    }
};
