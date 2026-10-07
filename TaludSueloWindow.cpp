#include "taludsuelowindow.h"
#include "ui_TaludSueloWindow.h"
#include "taludpaintdialog.h"

#include <QLabel>
#include <QVBoxLayout>
#include <QDir>
#include <QStandardPaths>
#include <QResizeEvent>
#include <QDialog>
#include <QFileInfo>
#include <QMessageBox>
#include <QCheckBox>
#include <QSignalBlocker>
#include <QList>
#include <QToolButton>
#include <QPushButton>
#include <QStyle>
#include <QIcon>
#include <QPainter>
#include <QPixmap>
#include <QEvent>
#include <QPointer>
#include <QAbstractButton>
#include <QMouseEvent>
#include <QSize>
#include <cmath>
#include <QLineEdit>
#include <QDoubleSpinBox>
#include <QIntValidator>
#include <QRegularExpression>
#include <QRegularExpressionValidator>
#include <QAbstractSpinBox>

// ============================================================
// Helpers visuales para iconos pequeños (pick / clear)
// ============================================================
static QPixmap tintedPixmap(const QIcon& icon, const QSize& size, const QColor& color)
{
    if (icon.isNull() || !size.isValid())
        return QPixmap();

    QPixmap src = icon.pixmap(size);
    if (src.isNull())
        return QPixmap();

    QPixmap out(src.size());
    out.fill(Qt::transparent);

    QPainter p(&out);
    p.setRenderHint(QPainter::Antialiasing, true);
    p.drawPixmap(0, 0, src);

    p.setCompositionMode(QPainter::CompositionMode_SourceIn);
    p.fillRect(out.rect(), color);
    p.end();

    return out;
}

class IconHoverTintFilter : public QObject
{
public:
    IconHoverTintFilter(QAbstractButton* btn,
                        const QIcon& base,
                        const QSize& size,
                        const QColor& normal,
                        const QColor& hover,
                        const QColor& pressed)
        : QObject(btn)
        , m_btn(btn)
        , m_base(base)
        , m_size(size)
        , m_normal(normal)
        , m_hover(hover)
        , m_pressed(pressed)
    {
        applyNormal();
    }

protected:
    bool eventFilter(QObject* obj, QEvent* ev) override
    {
        if (obj != m_btn || !m_btn)
            return QObject::eventFilter(obj, ev);

        switch (ev->type()) {
        case QEvent::Enter:
            applyHover();
            break;

        case QEvent::Leave:
            applyNormal();
            break;

        case QEvent::MouseButtonPress:
            applyPressed();
            break;

        case QEvent::MouseButtonRelease: {
            auto *me = static_cast<QMouseEvent*>(ev);
            if (m_btn->rect().contains(me->position().toPoint()))
                applyHover();
            else
                applyNormal();
            break;
        }

        case QEvent::EnabledChange:
            applyNormal();
            break;

        default:
            break;
        }

        return QObject::eventFilter(obj, ev);
    }

private:
    void applyColor(const QColor& c)
    {
        if (!m_btn) return;
        const QPixmap px = tintedPixmap(m_base, m_size, c);
        if (!px.isNull()) {
            m_btn->setIcon(QIcon(px));
            m_btn->setIconSize(m_size);
        }
    }

    void applyNormal()  { applyColor(m_normal);  }
    void applyHover()   { applyColor(m_hover);   }
    void applyPressed() { applyColor(m_pressed); }

private:
    QPointer<QAbstractButton> m_btn;
    QIcon  m_base;
    QSize  m_size;
    QColor m_normal;
    QColor m_hover;
    QColor m_pressed;
};

// ============================================================
// Helpers visuales para placeholders de cámara grande
// ============================================================
class PhotoPlaceholderStateFilter : public QObject
{
public:
    PhotoPlaceholderStateFilter(QPushButton* btn,
                                const QIcon& darkIcon,
                                const QIcon& whiteIcon,
                                const QSize& iconSize)
        : QObject(btn)
        , m_btn(btn)
        , m_darkIcon(darkIcon)
        , m_whiteIcon(whiteIcon)
        , m_iconSize(iconSize)
    {
        applyNormal();
    }

protected:
    bool eventFilter(QObject* obj, QEvent* ev) override
    {
        if (obj != m_btn || !m_btn)
            return QObject::eventFilter(obj, ev);

        // Solo actuar si sigue siendo placeholder
        if (!m_btn->property("_isPhotoPlaceholder").toBool())
            return QObject::eventFilter(obj, ev);

        switch (ev->type()) {
        case QEvent::Enter:
            applyHover();
            break;

        case QEvent::Leave:
            applyNormal();
            break;

        case QEvent::MouseButtonPress:
            applyPressed();
            break;

        case QEvent::MouseButtonRelease: {
            auto *me = static_cast<QMouseEvent*>(ev);
            if (m_btn->rect().contains(me->position().toPoint()))
                applyHover();
            else
                applyNormal();
            break;
        }

        case QEvent::EnabledChange:
            applyNormal();
            break;

        default:
            break;
        }

        return QObject::eventFilter(obj, ev);
    }

private:
    void applyIcon(const QIcon& ico)
    {
        if (!m_btn) return;
        m_btn->setIcon(ico);
        m_btn->setIconSize(m_iconSize);
        m_btn->setText(QString());
    }

    void applyNormal()  { applyIcon(m_darkIcon); }
    void applyHover()   { applyIcon(m_darkIcon); }
    void applyPressed() { applyIcon(m_whiteIcon.isNull() ? m_darkIcon : m_whiteIcon); }

private:
    QPointer<QPushButton> m_btn;
    QIcon m_darkIcon;
    QIcon m_whiteIcon;
    QSize m_iconSize;
};

static void installPickFilter(QToolButton* b)
{
    if (!b) return;

    QIcon base = b->style()->standardIcon(QStyle::SP_DialogOpenButton);
    b->setIcon(base);
    b->setIconSize(QSize(16, 16));

    b->installEventFilter(
        new IconHoverTintFilter(
            b,
            base,
            QSize(16, 16),
            QColor("#6a6a6a"),   // normal
            QColor("#111111"),   // hover
            QColor("#ffffff")    // pressed
            )
        );
}

static void installClearFilter(QToolButton* b)
{
    if (!b) return;

    QIcon base = b->style()->standardIcon(QStyle::SP_TitleBarCloseButton);
    b->setIcon(base);
    b->setIconSize(QSize(16, 16));

    b->installEventFilter(
        new IconHoverTintFilter(
            b,
            base,
            QSize(16, 16),
            QColor("#6a6a6a"),   // normal
            QColor("#111111"),   // hover
            QColor("#005282")    // pressed
            )
        );
}

static void setPhotoPlaceholder(QPushButton* btn)
{
    if (!btn) return;

    QIcon camDark(":/icons/images/camera_thin_dark.svg");
    QIcon camWhite(":/icons/images/camera_thin_white.svg");

    if (camDark.isNull()) {
        btn->setIcon(QIcon());
        btn->setText(QString());
        return;
    }

    QSize sz = btn->iconSize();
    if (!sz.isValid() || sz.width() <= 0 || sz.height() <= 0)
        sz = QSize(180, 180);

    btn->setProperty("_isPhotoPlaceholder", true);
    btn->setIcon(camDark);
    btn->setIconSize(sz);
    btn->setText(QString());

    if (!btn->property("_photoStateFilterInstalled").toBool()) {
        btn->setProperty("_photoStateFilterInstalled", true);
        btn->installEventFilter(
            new PhotoPlaceholderStateFilter(
                btn,
                camDark,
                camWhite.isNull() ? camDark : camWhite,
                sz
                )
            );
    }
}

TaludSueloWindow::TaludSueloWindow(QWidget *parent)
    : TaludFormBase(parent)
    , ui(new Ui::TaludSueloWindow)
{
    ui->setupUi(this);

    setObjectName("TaludSueloWindow");
    setBaseWindowTitle(tr("Ficha de Talud - Suelo"));
    updateWindowTitleWithDirtyMark();

    setupCheckboxRules();
    setupInputRules();

    // --------------------------------------------------------
    // ToolButtons: mismo criterio visual que Calicata
    // --------------------------------------------------------
    installClearFilter(ui->toolClear);

    installPickFilter(ui->toolFotoPick);
    installClearFilter(ui->toolFotoClear);

    installPickFilter(ui->toolFotoAereaPick);
    installClearFilter(ui->toolFotoAereaClear);

    // --------------------------------------------------------
    // Placeholders grandes de cámara
    // --------------------------------------------------------
    setPhotoPlaceholder(ui->btnFotografia);
    setPhotoPlaceholder(ui->btnFotografiaAerea);

    // --------------------------------------------------------
    // Vista previa / editor de dibujo del perfil
    // --------------------------------------------------------
    setupPaintPreview();
}

TaludSueloWindow::~TaludSueloWindow()
{
    delete ui;
}

TaludFormBase::TaludType TaludSueloWindow::taludType() const
{
    return TaludType::Suelo;
}

QString TaludSueloWindow::displayName() const
{
    if (!currentFilePath().trimmed().isEmpty())
        return QFileInfo(currentFilePath()).completeBaseName();

    return tr("Talud Suelo");
}

bool TaludSueloWindow::cargarDesdeArchivo(const QString& filePath)
{
    if (filePath.trimmed().isEmpty())
        return false;

    // Temporal: solo registra ruta y estado limpio.
    setCurrentFilePathInternal(filePath);
    setDirtyInternal(false);
    notifyDisplayNameChanged();
    updateWindowTitleWithDirtyMark();

    return true;
}

bool TaludSueloWindow::guardar()
{
    // Temporal: aún sin lógica real de serialización.
    if (currentFilePath().trimmed().isEmpty())
        return guardarComo();

    setDirtyInternal(false);
    updateWindowTitleWithDirtyMark();
    return true;
}

bool TaludSueloWindow::guardarComo()
{
    QMessageBox::information(this,
                             tr("Guardar como"),
                             tr("Talud Suelo: guardado aún no implementado."));
    return false;
}

void TaludSueloWindow::setupExclusiveNullablePair(QCheckBox* a, QCheckBox* b)
{
    if (!a || !b) return;

    connect(a, &QCheckBox::toggled, this, [a, b](bool checked) {
        if (!checked) return; // permitir que se desmarque solo
        QSignalBlocker blocker(b);
        b->setChecked(false);
    });

    connect(b, &QCheckBox::toggled, this, [a, b](bool checked) {
        if (!checked) return; // permitir que se desmarque solo
        QSignalBlocker blocker(a);
        a->setChecked(false);
    });
}

void TaludSueloWindow::setupExclusiveNullableGroup(const QList<QCheckBox*>& boxes)
{
    for (QCheckBox* current : boxes) {
        if (!current) continue;

        connect(current, &QCheckBox::toggled, this, [boxes, current](bool checked) {
            if (!checked) return; // permitir que todas queden desmarcadas

            for (QCheckBox* other : boxes) {
                if (!other || other == current) continue;
                QSignalBlocker blocker(other);
                other->setChecked(false);
            }
        });
    }
}

void TaludSueloWindow::setupCheckboxRules()
{
    // BERMAS: SI / NO
    setupExclusiveNullablePair(ui->checkSiBermas, ui->checkNoBermas);

    // CUNETÓN: SI / NO
    setupExclusiveNullablePair(ui->checkSiCuneton, ui->checkNoCuneton);

    // ESTABILIDAD GENERAL: solo una, pero todas pueden quedar desmarcadas
    setupExclusiveNullableGroup({
        ui->checkExcelente,
        ui->checkBuena,
        ui->checkMedia,
        ui->checkMala,
        ui->checkMuyMala
    });
}

void TaludSueloWindow::setupIntegerField(QLineEdit* edit, int min, int max)
{
    if (!edit) return;

    auto* validator = new QIntValidator(min, max, edit);
    edit->setValidator(validator);
    edit->setAlignment(Qt::AlignCenter);
}

void TaludSueloWindow::setupRegexField(QLineEdit* edit, const QString& pattern)
{
    if (!edit) return;

    auto* validator = new QRegularExpressionValidator(QRegularExpression(pattern), edit);
    edit->setValidator(validator);
    edit->setAlignment(Qt::AlignCenter);
}

void TaludSueloWindow::setupMeasureSpin(QDoubleSpinBox* spin,
                                        double minVisible,
                                        double max,
                                        const QString& suffix,
                                        int decimals)
{
    if (!spin) return;

    const double sentinel = minVisible - std::pow(10.0, -decimals);

    spin->setDecimals(decimals);
    spin->setRange(sentinel, max);
    spin->setValue(sentinel);

    spin->setSpecialValueText(" ");   // visualmente vacío
    spin->setSuffix(suffix);
    spin->setAlignment(Qt::AlignCenter);
    spin->setButtonSymbols(QAbstractSpinBox::NoButtons);
    spin->setGroupSeparatorShown(false);
    spin->setKeyboardTracking(false);

    // IMPORTANTE: que no vuelva al valor anterior al borrar
    spin->setCorrectionMode(QAbstractSpinBox::CorrectToNearestValue);

    if (QLineEdit* le = spin->findChild<QLineEdit*>()) {
        QObject::connect(le, &QLineEdit::textChanged, spin, [spin, le]() {
            QString t = le->text();

            const QString suf = spin->suffix();
            if (!suf.isEmpty() && t.endsWith(suf))
                t.chop(suf.size());

            t = t.trimmed();

            if (t.isEmpty()) {
                QSignalBlocker b1(spin);
                QSignalBlocker b2(le);
                spin->setValue(spin->minimum());
            }
        });
    }
}


void TaludSueloWindow::setupInputRules()
{
    setupMeasureSpin(ui->spnAltura,       0.00, 9999.99, " m", 2);
    setupMeasureSpin(ui->spnLongitud,     0.00, 9999.99, " m", 2);
    setupMeasureSpin(ui->spnAnchoBermas,  0.00, 9999.99, " m", 2);
    setupMeasureSpin(ui->spnInclinacion,  0.00,   90.00, "°", 2);

    setupIntegerField(ui->txtNBermas,     0, 999);
    setupIntegerField(ui->txtUTMX,        0, 99999999);
    setupIntegerField(ui->txtUTMY,        0, 99999999);

    // ANTES:
    // setupIntegerField(ui->txtZona, 1, 60);

    // AHORA:
    setupRegexField(ui->txtZona, R"(^\d{1,2}[A-Za-z]$)");

    setupIntegerField(ui->txtHojaActual,  0, 999);
    setupIntegerField(ui->txtHojaTotal,   0, 999);

    setupRegexField(ui->txtProgresiva, R"(^\d+$|^\d+\+\d+$)");
}

void TaludSueloWindow::setupPaintPreview()
{
    if (!ui || !ui->framePaint)
        return;

    // Evitar duplicar layout si luego vuelves a llamar este método
    if (!ui->framePaint->layout()) {
        auto* lay = new QVBoxLayout(ui->framePaint);
        lay->setContentsMargins(10, 10, 10, 10);
        lay->setSpacing(0);

        m_profilePreview = new QLabel(ui->framePaint);
        m_profilePreview->setAlignment(Qt::AlignCenter);
        m_profilePreview->setText(tr("Clic aquí para crear o editar el dibujo del perfil"));
        m_profilePreview->setWordWrap(true);
        m_profilePreview->setStyleSheet(
            "background: transparent;"
            "color: rgba(15,31,42,170);"
            "font-weight: 600;"
            );
        m_profilePreview->setCursor(Qt::PointingHandCursor);

        lay->addWidget(m_profilePreview);
    } else {
        m_profilePreview = ui->framePaint->findChild<QLabel*>();
    }

    ui->framePaint->setCursor(Qt::PointingHandCursor);
    ui->framePaint->setToolTip(tr("Abrir editor de dibujo"));

    ui->framePaint->installEventFilter(this);
    if (m_profilePreview)
        m_profilePreview->installEventFilter(this);

    updatePaintPreview();
}

bool TaludSueloWindow::eventFilter(QObject* watched, QEvent* event)
{
    if ((watched == ui->framePaint || watched == m_profilePreview) && event) {
        if (event->type() == QEvent::MouseButtonRelease) {
            auto* me = static_cast<QMouseEvent*>(event);
            if (me && me->button() == Qt::LeftButton) {
                openPaintDialog();
                return true;
            }
        }
    }

    return TaludFormBase::eventFilter(watched, event);
}

void TaludSueloWindow::resizeEvent(QResizeEvent* event)
{
    TaludFormBase::resizeEvent(event);
    updatePaintPreview();
}

void TaludSueloWindow::openPaintDialog()
{
    TaludPaintDialog dlg(this);

    if (!m_profileImage.isNull())
        dlg.setInitialImage(m_profileImage);

    if (dlg.exec() != QDialog::Accepted)
        return;

    const QImage result = dlg.resultImage();
    if (result.isNull())
        return;

    m_profileImage = result;
    saveProfilePreviewToFile();
    updatePaintPreview();

    setDirtyInternal(true);
    updateWindowTitleWithDirtyMark();
}

void TaludSueloWindow::updatePaintPreview()
{
    if (!m_profilePreview)
        return;

    if (m_profileImage.isNull()) {
        m_profilePreview->setPixmap(QPixmap());
        m_profilePreview->setText(tr("Clic aquí para crear o editar el dibujo del perfil"));
        return;
    }

    const QSize targetSize = m_profilePreview->size() - QSize(8, 8);
    if (targetSize.width() <= 0 || targetSize.height() <= 0)
        return;

    QPixmap px = QPixmap::fromImage(m_profileImage);
    m_profilePreview->setText(QString());
    m_profilePreview->setPixmap(
        px.scaled(targetSize, Qt::KeepAspectRatio, Qt::SmoothTransformation)
        );
}

bool TaludSueloWindow::saveProfilePreviewToFile()
{
    if (m_profileImage.isNull())
        return false;

    QString baseDir;
    QString baseName;

    if (!currentFilePath().trimmed().isEmpty()) {
        QFileInfo fi(currentFilePath());
        baseDir = fi.absolutePath() + "/_talud_preview";
        baseName = fi.completeBaseName();
    } else {
        baseDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
        + "/talud_preview";
        baseName = "talud_suelo_tmp";
    }

    QDir().mkpath(baseDir);

    m_profileImagePath = baseDir + "/" + baseName + "_perfil_talud.png";
    return m_profileImage.save(m_profileImagePath, "PNG");
}