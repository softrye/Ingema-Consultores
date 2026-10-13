#include "toggleswitch.h"

#include <QPainter>
#include <QMouseEvent>
#include <QPropertyAnimation>
#include <QEasingCurve>
#include <QPalette>

#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
#include <QEnterEvent>
#endif

ToggleSwitch::ToggleSwitch(QWidget *parent)
    : QWidget(parent)
{
    setCursor(Qt::PointingHandCursor);
    setFixedSize(sizeHint());

    m_anim = new QPropertyAnimation(this, "offset", this);
    m_anim->setDuration(160);
    m_anim->setEasingCurve(QEasingCurve::OutCubic);
}

void ToggleSwitch::setChecked(bool on)
{
    if (m_checked == on)
        return;

    m_checked = on;
    animateTo(on);
    emit toggled(on);
}

void ToggleSwitch::animateTo(bool on)
{
    if (!m_anim) return;

    m_anim->stop();
    m_anim->setStartValue(m_offset);
    m_anim->setEndValue(on ? 1.0 : 0.0);
    m_anim->start();
}

void ToggleSwitch::mouseReleaseEvent(QMouseEvent *e)
{
    if (e->button() == Qt::LeftButton) {
        setChecked(!m_checked);
        e->accept();
        return;
    }
    QWidget::mouseReleaseEvent(e);
}

#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
void ToggleSwitch::enterEvent(QEnterEvent *e)
{
    m_hover = true;
    update();
    QWidget::enterEvent(e);
}
#else
void ToggleSwitch::enterEvent(QEvent *e)
{
    m_hover = true;
    update();
    QWidget::enterEvent(e);
}
#endif

void ToggleSwitch::leaveEvent(QEvent *e)
{
    m_hover = false;
    update();
    QWidget::leaveEvent(e);
}

void ToggleSwitch::paintEvent(QPaintEvent *)
{
    QPainter p(this);
    p.setRenderHint(QPainter::Antialiasing, true);

    const int w = width();
    const int h = height();
    const int m = 2;

    QRectF track(m, m, w - 2*m, h - 2*m);
    const qreal r = track.height() / 2.0;

    const QColor offColor("#D0D4E4");
    const QColor onColor("#4C8DFF");
    QColor trackColor = m_checked ? onColor : offColor;

    if (m_hover) {
        trackColor = trackColor.lighter(108);
    }

    // Track
    p.setPen(Qt::NoPen);
    p.setBrush(trackColor);
    p.drawRoundedRect(track, r, r);

    // Thumb
    const qreal thumbD = track.height() - 4;           // diámetro
    const qreal xMin = track.left() + 2;
    const qreal xMax = track.right() - 2 - thumbD;
    const qreal x = xMin + (xMax - xMin) * m_offset;
    QRectF thumb(x, track.top() + 2, thumbD, thumbD);

    p.setBrush(Qt::white);
    p.setPen(QColor(0, 0, 0, 30));
    p.drawEllipse(thumb);
}
