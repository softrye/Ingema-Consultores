#ifndef TIMESTAMPDIALOG_H
#define TIMESTAMPDIALOG_H

#include <QDialog>

namespace Ui {
class TimestampDialog;
}

class TimestampDialog : public QDialog
{
    Q_OBJECT

public:
    explicit TimestampDialog(QWidget *parent = nullptr);
    ~TimestampDialog();

    // --- GETTERS ---
    QString zona()     const;
    QString este()     const;
    QString norte()    const;
    QString altitud()  const;
    QString calicata() const;
    QString proyecto() const;
    QString fecha()    const;
    QString hora()     const;

    // --- SETTERS (para pre-rellenar el diálogo) ---
    void setZona(const QString &v);
    void setEste(const QString &v);
    void setNorte(const QString &v);
    void setAltitud(const QString &v);
    void setCalicata(const QString &v);
    void setProyecto(const QString &v);
    void setFecha(const QString &v);
    void setHora(const QString &v);

private:
    Ui::TimestampDialog *ui;
};

#endif // TIMESTAMPTDIALOG_H
