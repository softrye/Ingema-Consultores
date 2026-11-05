#include "CesiumNativeView.h"
#include "CesiumRocktreeAssets.h"
#include "RetroplasmaController.h"
#include <QCoreApplication>
#include <QJsonDocument>
#include <QQuickWindow>
#include <QSGGeometryNode>
#include <QSGFlatColorMaterial>
#ifdef Q_OS_ANDROID
#include <QJniObject>
#include <jni.h>
#endif
namespace inge::earth {
static QPointer<RetroplasmaController> target;
void setController(RetroplasmaController *value){target=value;}
bool show(){
    setAssetSession(true);
#ifdef Q_OS_ANDROID
    return QJniObject::callStaticMethod<jboolean>("com/ingema/ingeplus/InGeQtActivity","showEarthViewer","()Z");
#else
    return false;
#endif
}
void hide(){
    setAssetSession(false);
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>("com/ingema/ingeplus/InGeQtActivity","hideEarthViewer","()V");
#endif
}
void command(const QJsonObject &object){
#ifdef Q_OS_ANDROID
    const auto script=QJniObject::fromString(QStringLiteral("window.InGeCesiumCommand && window.InGeCesiumCommand(%1)").arg(QString::fromUtf8(QJsonDocument(object).toJson(QJsonDocument::Compact))));
    QJniObject::callStaticMethod<void>("com/ingema/ingeplus/InGeQtActivity","executeEarthCommand","(Ljava/lang/String;)V",script.object<jstring>());
#else
    Q_UNUSED(object)
#endif
}
void viewport(int x,int y,int width,int height){
#ifdef Q_OS_ANDROID
    QJniObject::callStaticMethod<void>("com/ingema/ingeplus/InGeQtActivity","setEarthViewport","(IIII)V",jint(x),jint(y),jint(width),jint(height));
#else
    Q_UNUSED(x)Q_UNUSED(y)Q_UNUSED(width)Q_UNUSED(height)
#endif
}
}
#ifdef Q_OS_ANDROID
extern "C" JNIEXPORT jbyteArray JNICALL Java_com_ingema_ingeplus_CesiumNativeBridge_nativeAsset(JNIEnv *env,jclass,jstring path){
    if(!path||env->GetStringLength(path)>128)return nullptr;
    const auto *chars=env->GetStringChars(path,nullptr);if(!chars)return nullptr;
    const auto value=QString::fromUtf16(reinterpret_cast<const char16_t *>(chars),env->GetStringLength(path));env->ReleaseStringChars(path,chars);
    const auto bytes=inge::earth::rocktreeAsset(value);
    auto result=env->NewByteArray(jsize(bytes.size()));if(result)env->SetByteArrayRegion(result,0,jsize(bytes.size()),reinterpret_cast<const jbyte *>(bytes.constData()));return result;
}
extern "C" JNIEXPORT void JNICALL Java_com_ingema_ingeplus_CesiumNativeBridge_nativePost(JNIEnv *env,jclass,jstring json){
    if(!json||env->GetStringLength(json)>32768)return;const auto *chars=env->GetStringChars(json,nullptr);if(!chars)return;
    const auto message=QString::fromUtf16(reinterpret_cast<const char16_t *>(chars),env->GetStringLength(json));env->ReleaseStringChars(json,chars);
    if(auto *app=QCoreApplication::instance())QMetaObject::invokeMethod(app,[message](){if(inge::earth::target)inge::earth::target->acceptCesiumEvent(QJsonDocument::fromJson(message.toUtf8()).object());},Qt::QueuedConnection);
}
#endif
CesiumNativeView::CesiumNativeView(QQuickItem *parent):QQuickItem(parent){
    setFlag(ItemHasContents);connect(this,&QQuickItem::windowChanged,this,[this](){syncViewport();});
    connect(this,&QQuickItem::visibleChanged,this,[this](){syncViewport();update();});
}
void CesiumNativeView::setController(RetroplasmaController *value){if(m_controller==value)return;if(m_controller)disconnect(m_controller,nullptr,this,nullptr);m_controller=value;
    if(value)connect(value,&RetroplasmaController::renderChanged,this,[this](){syncViewport();update();});emit controllerChanged();syncViewport();update();}
void CesiumNativeView::geometryChange(const QRectF &now,const QRectF &before){QQuickItem::geometryChange(now,before);syncViewport();update();}
void CesiumNativeView::syncViewport(){if(!window()||!m_controller||!isVisible()||!m_controller->active())return;const auto p=mapToScene({0,0});const double dpr=window()->devicePixelRatio();
    m_controller->setViewport(width(),height(),dpr);inge::earth::viewport(qRound(p.x()*dpr),qRound(p.y()*dpr),qRound(width()*dpr),qRound(height()*dpr));}
QSGNode *CesiumNativeView::updatePaintNode(QSGNode *old,UpdatePaintNodeData *){
    if(!m_controller||!m_controller->active()){delete old;return nullptr;}
    auto *node=static_cast<QSGGeometryNode *>(old);
    if(!node){node=new QSGGeometryNode;auto *geometry=new QSGGeometry(QSGGeometry::defaultAttributes_Point2D(),4);geometry->setDrawingMode(QSGGeometry::DrawTriangleStrip);node->setGeometry(geometry);node->setFlag(QSGNode::OwnsGeometry);
        auto *material=new QSGFlatColorMaterial;material->setColor(Qt::transparent);material->setFlag(QSGMaterial::Blending,false);node->setMaterial(material);node->setFlag(QSGNode::OwnsMaterial);}
    // Write transparent pixels, rather than alpha-blending a transparent texture.
    // This exposes the single native WebView BELOW Qt; all subsequent QML UI stays above.
    QSGGeometry::updateRectGeometry(node->geometry(),boundingRect());node->markDirty(QSGNode::DirtyGeometry);return node;
}
