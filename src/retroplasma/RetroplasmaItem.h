#pragma once
#include "RetroplasmaController.h"
#include <QQuickRhiItem>
#include <QPointer>
#include <QtQml/qqmlregistration.h>
class RetroplasmaItem final : public QQuickRhiItem {
    Q_OBJECT
    QML_NAMED_ELEMENT(RetroplasmaView)
    Q_PROPERTY(RetroplasmaController* controller READ controller WRITE setController NOTIFY controllerChanged)
public:
    explicit RetroplasmaItem(QQuickItem *parent=nullptr);
    RetroplasmaController *controller()const{return m_controller.data();}
    void setController(RetroplasmaController *);
signals:
    void controllerChanged();
protected:
    QQuickRhiItemRenderer *createRenderer()override;
    void geometryChange(const QRectF &,const QRectF &)override;
private:
    QPointer<RetroplasmaController> m_controller;
    QMetaObject::Connection m_updateConnection;
};
