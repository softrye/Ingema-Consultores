#ifndef CARDFRAME_H
#define CARDFRAME_H

#include <QFrame>
#include <QGraphicsDropShadowEffect>
#include <QPropertyAnimation>

class CardFrame : public QFrame
{
    Q_OBJECT
    Q_PROPERTY(qreal scaleFactor READ scaleFactor WRITE setScaleFactor)

public:
    explicit CardFrame(QWidget *parent = nullptr);

    qreal scaleFactor() const { return m_scale; }
    void setScaleFactor(qreal value);

protected:
    void enterEvent(QEnterEvent *event) override;
    void leaveEvent(QEvent *event) override;
    void paintEvent(QPaintEvent *event) override;

private:
    qreal m_scale = 1.0;
    QPoint m_originalPos;

    // 🔹 animaciones separadas
    QPropertyAnimation *scaleAnim;
    QPropertyAnimation *posAnim;
    QPropertyAnimation *shadowAnim;

    QGraphicsDropShadowEffect *shadow;
};

#endif // CARDFRAME_H
