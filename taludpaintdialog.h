#pragma once

#include <QDialog>
#include <QImage>

class PaintCanvasWidget;
class QPushButton;
class QComboBox;

class TaludPaintDialog : public QDialog
{
    Q_OBJECT

public:
    explicit TaludPaintDialog(QWidget *parent = nullptr);

    void setInitialImage(const QImage& image);
    QImage resultImage() const;

private slots:
    void onClear();
    void onAccept();

private:
    PaintCanvasWidget* m_canvas = nullptr;
    QImage m_resultImage;
};