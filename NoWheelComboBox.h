#pragma once
#include <QComboBox>
#include <QWheelEvent>

class NoWheelComboBox : public QComboBox
{
public:
    using QComboBox::QComboBox;

protected:
    void wheelEvent(QWheelEvent *e) override
    {
        // No cambiar selección con la rueda.
        // Importante: ignore => deja que el scroll (si hay) lo use.
        e->ignore();
    }
};
