#include "timestampdialog.h"
#include "ui_timestampdialog.h"

#include <QDate>
#include <QTime>

TimestampDialog::TimestampDialog(QWidget *parent)
    : QDialog(parent)
    , ui(new Ui::TimestampDialog)
{
    ui->setupUi(this);

    // 🔹 Aumentar tamaño general de la fuente del diálogo
    QFont f = this->font();
    f.setPointSize(8);          // ajusta si quieres más grande
    setFont(f);

    // 🔹 Hacer el diálogo un poco más grande visualmente
    resize(500, 420);

    // 🔹 Formatos de los nuevos widgets de fecha y hora
    if (ui->dateEditFecha)
        ui->dateEditFecha->setDisplayFormat("dd/MM/yy");
    if (ui->timeEditHora)
        ui->timeEditHora->setDisplayFormat("HH:mm:ss");
}

TimestampDialog::~TimestampDialog()
{
    delete ui;
}

// --- GETTERS ---
QString TimestampDialog::zona()     const { return ui->txtZona->text(); }
QString TimestampDialog::este()     const { return ui->txtEste->text(); }
QString TimestampDialog::norte()    const { return ui->txtNorte->text(); }
QString TimestampDialog::altitud()  const { return ui->txtAltitud->text(); }
QString TimestampDialog::calicata() const { return ui->txtCalicata->text(); }
QString TimestampDialog::proyecto() const { return ui->txtProyecto->text(); }

// 👉 Ahora fecha() y hora() leen de QDateEdit / QTimeEdit
QString TimestampDialog::fecha() const
{
    if (!ui->dateEditFecha)
        return QString();
    return ui->dateEditFecha->date().toString("dd/MM/yy");
}

QString TimestampDialog::hora() const
{
    if (!ui->timeEditHora)
        return QString();
    return ui->timeEditHora->time().toString("HH:mm:ss");
}

// --- SETTERS ---
void TimestampDialog::setZona(const QString &v)     { ui->txtZona->setText(v); }
void TimestampDialog::setEste(const QString &v)     { ui->txtEste->setText(v); }
void TimestampDialog::setNorte(const QString &v)    { ui->txtNorte->setText(v); }
void TimestampDialog::setAltitud(const QString &v)  { ui->txtAltitud->setText(v); }
void TimestampDialog::setCalicata(const QString &v) { ui->txtCalicata->setText(v); }
void TimestampDialog::setProyecto(const QString &v) { ui->txtProyecto->setText(v); }

// 👉 Estos setters ahora rellenan el QDateEdit / QTimeEdit
void TimestampDialog::setFecha(const QString &v)
{
    if (!ui->dateEditFecha || v.isEmpty())
        return;

    // Intentamos dd/MM/yy primero
    QDate d = QDate::fromString(v, "dd/MM/yy");
    if (!d.isValid())
        d = QDate::fromString(v, Qt::ISODate);  // por si viene en ISO

    if (d.isValid())
        ui->dateEditFecha->setDate(d);
}

void TimestampDialog::setHora(const QString &v)
{
    if (!ui->timeEditHora || v.isEmpty())
        return;

    // Intentamos HH:mm:ss primero
    QTime t = QTime::fromString(v, "HH:mm:ss");
    if (!t.isValid())
        t = QTime::fromString(v, "HH:mm");  // formato corto opcional

    if (t.isValid())
        ui->timeEditHora->setTime(t);
}
