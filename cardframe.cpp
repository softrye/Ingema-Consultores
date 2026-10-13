#include "cardframe.h"
#include <QPainter>
#include <QEnterEvent>

CardFrame::CardFrame(QWidget *parent)
    : QFrame(parent)
{
    // 🔹 Sombra inicial
    shadow = new QGraphicsDropShadowEffect(this);
    shadow->setBlurRadius(20);
    shadow->setColor(QColor(0, 0, 0, 80));
    shadow->setOffset(0, 4);
    setGraphicsEffect(shadow);

    setStyleSheet("background-color: white; border-radius: 10px;");

    // 🔹 Animación de escala (zoom)
    scaleAnim = new QPropertyAnimation(this, "scaleFactor");
    scaleAnim->setDuration(220);
    scaleAnim->setEasingCurve(QEasingCurve::OutCubic);

    // 🔹 Animación de posición
    posAnim = new QPropertyAnimation(this, "pos");
    posAnim->setDuration(220);
    posAnim->setEasingCurve(QEasingCurve::OutCubic);

    // 🔹 Animación de sombra
    shadowAnim = new QPropertyAnimation(shadow, "blurRadius");
    shadowAnim->setDuration(220);
    shadowAnim->setEasingCurve(QEasingCurve::OutCubic);
}

void CardFrame::enterEvent(QEnterEvent *event)
{
    Q_UNUSED(event);
    m_originalPos = pos();

    // Zoom suave
    scaleAnim->stop();
    scaleAnim->setStartValue(m_scale);
    scaleAnim->setEndValue(1.08);
    scaleAnim->start();

    // Posición animada hacia arriba
    posAnim->stop();
    posAnim->setStartValue(m_originalPos);
    posAnim->setEndValue(QPoint(m_originalPos.x(), m_originalPos.y() - 4));
    posAnim->start();

    // Sombra animada
    shadowAnim->stop();
    shadowAnim->setStartValue(20);
    shadowAnim->setEndValue(38);
    shadowAnim->start();
    shadow->setOffset(0, 2);
}

void CardFrame::leaveEvent(QEvent *event)
{
    Q_UNUSED(event);

    // Zoom inverso
    scaleAnim->stop();
    scaleAnim->setStartValue(m_scale);
    scaleAnim->setEndValue(1.0);
    scaleAnim->start();

    // Volver a la posición original
    posAnim->stop();
    posAnim->setStartValue(pos());
    posAnim->setEndValue(m_originalPos);
    posAnim->start();

    // Sombra vuelve a su estado base
    shadowAnim->stop();
    shadowAnim->setStartValue(38);
    shadowAnim->setEndValue(20);
    shadowAnim->start();
    shadow->setOffset(0, 4);
}

void CardFrame::setScaleFactor(qreal value)
{
    m_scale = value;
    update();
}

void CardFrame::paintEvent(QPaintEvent *event)
{
    QPainter painter(this);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.setRenderHint(QPainter::SmoothPixmapTransform);
    painter.translate(width() / 2.0, height() / 2.0);
    painter.scale(m_scale, m_scale);
    painter.translate(-width() / 2.0, -height() / 2.0);
    QFrame::paintEvent(event);
}
