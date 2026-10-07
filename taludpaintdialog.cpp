#include "TaludPaintDialog.h"
#include "PaintCanvasWidget.h"

#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QPushButton>
#include <QColorDialog>
#include <QSpinBox>

TaludPaintDialog::TaludPaintDialog(QWidget *parent)
    : QDialog(parent)
{
    setWindowTitle("Zona de dibujo del perfil");
    resize(1000, 700);

    auto* mainLayout = new QVBoxLayout(this);
    auto* toolsLayout = new QHBoxLayout();

    auto* btnPencil = new QPushButton("Lápiz");
    auto* btnBrush = new QPushButton("Pincel");
    auto* btnEraser = new QPushButton("Borrador");
    auto* btnColor = new QPushButton("Color");
    auto* btnUndo = new QPushButton("Deshacer");
    auto* btnRedo = new QPushButton("Rehacer");
    auto* btnClear = new QPushButton("Limpiar");

    auto* widthSpin = new QSpinBox();
    widthSpin->setRange(1, 20);
    widthSpin->setValue(2);

    toolsLayout->addWidget(btnPencil);
    toolsLayout->addWidget(btnBrush);
    toolsLayout->addWidget(btnEraser);
    toolsLayout->addWidget(btnColor);
    toolsLayout->addWidget(widthSpin);
    toolsLayout->addStretch();
    toolsLayout->addWidget(btnUndo);
    toolsLayout->addWidget(btnRedo);
    toolsLayout->addWidget(btnClear);

    m_canvas = new PaintCanvasWidget(this);

    auto* actionsLayout = new QHBoxLayout();
    auto* btnAceptar = new QPushButton("Aceptar");
    auto* btnCancelar = new QPushButton("Cancelar");

    actionsLayout->addStretch();
    actionsLayout->addWidget(btnAceptar);
    actionsLayout->addWidget(btnCancelar);

    mainLayout->addLayout(toolsLayout);
    mainLayout->addWidget(m_canvas, 1);
    mainLayout->addLayout(actionsLayout);

    connect(btnPencil, &QPushButton::clicked, this, [this]() {
        m_canvas->setTool(PaintCanvasWidget::Tool::Pencil);
    });

    connect(btnBrush, &QPushButton::clicked, this, [this]() {
        m_canvas->setTool(PaintCanvasWidget::Tool::Brush);
    });

    connect(btnEraser, &QPushButton::clicked, this, [this]() {
        m_canvas->setTool(PaintCanvasWidget::Tool::Eraser);
    });

    connect(btnColor, &QPushButton::clicked, this, [this]() {
        QColor c = QColorDialog::getColor(Qt::black, this);
        if (c.isValid())
            m_canvas->setPenColor(c);
    });

    connect(widthSpin, qOverload<int>(&QSpinBox::valueChanged),
            this, [this](int v) {
                m_canvas->setPenWidth(v);
            });

    connect(btnUndo, &QPushButton::clicked, m_canvas, &PaintCanvasWidget::undo);
    connect(btnRedo, &QPushButton::clicked, m_canvas, &PaintCanvasWidget::redo);
    connect(btnClear, &QPushButton::clicked, this, &TaludPaintDialog::onClear);

    connect(btnAceptar, &QPushButton::clicked, this, &TaludPaintDialog::onAccept);
    connect(btnCancelar, &QPushButton::clicked, this, &QDialog::reject);
}

void TaludPaintDialog::setInitialImage(const QImage &image)
{
    if (!image.isNull())
        m_canvas->setImage(image);
}

QImage TaludPaintDialog::resultImage() const
{
    return m_resultImage;
}

void TaludPaintDialog::onClear()
{
    m_canvas->clearCanvas();
}

void TaludPaintDialog::onAccept()
{
    m_resultImage = m_canvas->image();
    accept();
}