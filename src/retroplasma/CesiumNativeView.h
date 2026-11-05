#pragma once
#include <QQuickItem>
#include <QPointer>
#include <QJsonObject>
#include <QtQml/qqmlregistration.h>
#include "RetroplasmaController.h"
namespace inge::earth {
void setController(RetroplasmaController *);
bool show();
void hide();
void command(const QJsonObject &);
void viewport(int x,int y,int width,int height);
}
class CesiumNativeView : public QQuickItem {
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(RetroplasmaController *controller READ controller WRITE setController NOTIFY controllerChanged)
public:
    explicit CesiumNativeView(QQuickItem *parent=nullptr);
    RetroplasmaController *controller()const{return m_controller;}
    void setController(RetroplasmaController *);
signals:
    void controllerChanged();
protected:
    QSGNode *updatePaintNode(QSGNode *,UpdatePaintNodeData *)override;
    void geometryChange(const QRectF &,const QRectF &)override;
private:
    QPointer<RetroplasmaController> m_controller;
    void syncViewport();
};
