#pragma once

#include <QWidget>
#include <QPoint>
#include <QStringList>
#include <QJsonObject>

class QComboBox;
class QToolButton;
class QEvent;

namespace Ui {
class CorteRowWidget;
}

class CorteRowWidget : public QWidget
{
    Q_OBJECT
public:
    explicit CorteRowWidget(QWidget *parent = nullptr);
    ~CorteRowWidget() override;

    // MIME único para drag & drop (úsalo también en CalicataWindow)
    static constexpr const char* mimeTypeCorteRow() { return "application/x-corte-row"; }

    void setCorteNumero(int n);
    int corteNumero() const;

    // En tu .ui estos combos se llaman txtDE y txtA
    QComboBox* editDE() const;
    QComboBox* editA()  const;

    // Alias por compatibilidad
    QComboBox* comboDE() const { return editDE(); }
    QComboBox* comboA()  const { return editA(); }

    // Para confirmar borrado solo si hay datos
    bool hasMeaningfulData() const;

    // Para el caso de que sea el último corte (no lo eliminamos, lo limpiamos)
    void clearUserData();

    QToolButton* deleteButton() const;
    QJsonObject toJson() const;
    void fromJson(const QJsonObject& obj);
    void normalizePercentFields();

signals:
    void solicitarEliminar(CorteRowWidget *row);

protected:
    bool eventFilter(QObject *obj, QEvent *ev) override;

private:
    QWidget* dragHandle() const;                 // headerBar si existe, si no lblCorteTitulo
    void startDrag(const QPoint &hotSpotInRow);  // hotSpot en coords del ROW

    // combos con items + popup legible
    static void ensureComboItems(QComboBox *cb, const QStringList &items, bool allowEmpty);
    static void tuneComboPopup(QComboBox *cb);

private:
    Ui::CorteRowWidget *ui = nullptr;
    int m_numero = 1;

    // Dónde se presionó en el HANDLE (coords del handle)
    QPoint m_pressPosInHandle;

    // Cache del handle (buscado por objectName "headerBar" si existe)
    mutable QWidget *m_cachedHandle = nullptr;
};
