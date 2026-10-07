#include "verticallabel.h"
#include <QPainter>
#include <QStyleOption>

VerticalLabel::VerticalLabel(QWidget* parent)
    : QLabel(parent)
{
    setAlignment(Qt::AlignCenter);
    setWordWrap(false);
}

QSize VerticalLabel::sizeHint() const
{
    QSize s = QLabel::sizeHint();
    return QSize(s.height(), s.width());
}

QSize VerticalLabel::minimumSizeHint() const
{
    QSize s = QLabel::minimumSizeHint();
    return QSize(s.height(), s.width());
}

void VerticalLabel::paintEvent(QPaintEvent *event)
{
    Q_UNUSED(event);

    QPainter painter(this);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.setRenderHint(QPainter::TextAntialiasing);

    painter.translate(width() / 2.0, height() / 2.0);
    painter.rotate(-90);

    QRect r(-height() / 2, -width() / 2, height(), width());

    painter.setFont(font());
    painter.setPen(palette().color(QPalette::WindowText));
    painter.drawText(r, alignment(), text());
}
