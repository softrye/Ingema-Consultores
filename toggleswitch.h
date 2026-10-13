#pragma once
#include <QWidget>
#include <QEnterEvent>   // <-- Qt6

class QPropertyAnimation;

class ToggleSwitch : public QWidget
{
    Q_OBJECT
    Q_PROPERTY(qreal offset READ offset WRITE setOffset)

public:
    explicit ToggleSwitch(QWidget *parent = nullptr);

    bool isChecked() const { return m_checked; }
    QSize sizeHint() const override { return QSize(46, 24); }

public slots:
    void setChecked(bool on);

signals:
    void toggled(bool on);

protected:
    void paintEvent(QPaintEvent *e) override;
    void mouseReleaseEvent(QMouseEvent *e) override;

#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
    void enterEvent(QEnterEvent *e) override;   // <-- Qt6
#else
    void enterEvent(QEvent *e) override;        // <-- Qt5
#endif

    void leaveEvent(QEvent *e) override;

private:
    qreal offset() const { return m_offset; }
    void setOffset(qreal v) { m_offset = v; update(); }
    void animateTo(bool on);

    bool  m_checked = false;
    qreal m_offset  = 0.0;   // 0..1
    bool  m_hover   = false;

    QPropertyAnimation *m_anim = nullptr;
};
