#pragma once

#include <QWidget>
#include <QImage>
#include <QColor>
#include <QPoint>
#include <QStack>

class PaintCanvasWidget : public QWidget
{
    Q_OBJECT

public:
    enum class Tool {
        Pencil,
        Brush,
        Eraser,
        Text
    };

    explicit PaintCanvasWidget(QWidget *parent = nullptr);

    void setImage(const QImage& image);
    QImage image() const;

    void clearCanvas();
    void setTool(Tool tool);
    void setPenColor(const QColor& color);
    void setPenWidth(int width);

    bool canUndo() const;
    bool canRedo() const;

public slots:
    void undo();
    void redo();

signals:
    void imageChanged();

protected:
    void paintEvent(QPaintEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;
    void resizeEvent(QResizeEvent *event) override;

private:
    void drawLineTo(const QPoint& endPoint);
    void pushUndoState();

private:
    QImage m_image;
    QColor m_penColor = Qt::black;
    int m_penWidth = 2;
    Tool m_tool = Tool::Pencil;

    bool m_drawing = false;
    QPoint m_lastPoint;

    QStack<QImage> m_undoStack;
    QStack<QImage> m_redoStack;
};