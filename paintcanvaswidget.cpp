#include "PaintCanvasWidget.h"

#include <QPainter>
#include <QMouseEvent>
#include <QPaintEvent>

PaintCanvasWidget::PaintCanvasWidget(QWidget *parent)
    : QWidget(parent)
{
    setAttribute(Qt::WA_StaticContents);

    m_image = QImage(2000, 1000, QImage::Format_ARGB32_Premultiplied);
    m_image.fill(Qt::white);
}

void PaintCanvasWidget::setImage(const QImage &image)
{
    if (!image.isNull()) {
        m_image = image;
        update();
        emit imageChanged();
    }
}

QImage PaintCanvasWidget::image() const
{
    return m_image;
}

void PaintCanvasWidget::clearCanvas()
{
    pushUndoState();
    m_image.fill(Qt::white);
    m_redoStack.clear();
    update();
    emit imageChanged();
}

void PaintCanvasWidget::setTool(Tool tool)
{
    m_tool = tool;
}

void PaintCanvasWidget::setPenColor(const QColor &color)
{
    m_penColor = color;
}

void PaintCanvasWidget::setPenWidth(int width)
{
    m_penWidth = width;
}

bool PaintCanvasWidget::canUndo() const
{
    return !m_undoStack.isEmpty();
}

bool PaintCanvasWidget::canRedo() const
{
    return !m_redoStack.isEmpty();
}

void PaintCanvasWidget::undo()
{
    if (m_undoStack.isEmpty()) return;
    m_redoStack.push(m_image);
    m_image = m_undoStack.pop();
    update();
    emit imageChanged();
}

void PaintCanvasWidget::redo()
{
    if (m_redoStack.isEmpty()) return;
    m_undoStack.push(m_image);
    m_image = m_redoStack.pop();
    update();
    emit imageChanged();
}

void PaintCanvasWidget::pushUndoState()
{
    m_undoStack.push(m_image);
    if (m_undoStack.size() > 20)
        m_undoStack.remove(0);
}

void PaintCanvasWidget::paintEvent(QPaintEvent *)
{
    QPainter painter(this);
    painter.fillRect(rect(), Qt::white);

    QImage scaled = m_image.scaled(size(), Qt::KeepAspectRatio, Qt::SmoothTransformation);

    QPoint topLeft((width() - scaled.width()) / 2,
                   (height() - scaled.height()) / 2);

    painter.drawImage(topLeft, scaled);
}

void PaintCanvasWidget::mousePressEvent(QMouseEvent *event)
{
    if (event->button() != Qt::LeftButton)
        return;

    pushUndoState();
    m_redoStack.clear();

    m_drawing = true;
    m_lastPoint = event->pos();
}

void PaintCanvasWidget::mouseMoveEvent(QMouseEvent *event)
{
    if ((event->buttons() & Qt::LeftButton) && m_drawing) {
        drawLineTo(event->pos());
    }
}

void PaintCanvasWidget::mouseReleaseEvent(QMouseEvent *event)
{
    if (event->button() == Qt::LeftButton && m_drawing) {
        drawLineTo(event->pos());
        m_drawing = false;
        emit imageChanged();
    }
}

void PaintCanvasWidget::drawLineTo(const QPoint &endPoint)
{
    // Convertir coordenadas del widget a coordenadas de la imagen
    QSize scaledSize = m_image.size();
    scaledSize.scale(size(), Qt::KeepAspectRatio);

    QPoint offset((width() - scaledSize.width()) / 2,
                  (height() - scaledSize.height()) / 2);

    auto mapToImage = [&](const QPoint& p) -> QPoint {
        double x = double(p.x() - offset.x()) * m_image.width() / scaledSize.width();
        double y = double(p.y() - offset.y()) * m_image.height() / scaledSize.height();
        return QPoint(int(x), int(y));
    };

    QPoint p1 = mapToImage(m_lastPoint);
    QPoint p2 = mapToImage(endPoint);

    QPainter painter(&m_image);
    QPen pen;

    if (m_tool == Tool::Eraser) {
        pen.setColor(Qt::white);
        pen.setWidth(m_penWidth * 2);
    } else {
        pen.setColor(m_penColor);
        pen.setWidth(m_penWidth);
    }

    pen.setCapStyle(Qt::RoundCap);
    pen.setJoinStyle(Qt::RoundJoin);
    painter.setPen(pen);
    painter.drawLine(p1, p2);

    m_lastPoint = endPoint;
    update();
}

void PaintCanvasWidget::resizeEvent(QResizeEvent *event)
{
    QWidget::resizeEvent(event);
    update();
}