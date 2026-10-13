#pragma once

#include <QObject>

class QApplication;
class QWidget;

class InGeUiTheme : public QObject
{
    Q_OBJECT
public:
    // Llamar 1 vez en main.cpp
    static void install(QApplication* app);

    // Opcional: llamar manualmente en un diálogo si quieres (normalmente no hace falta)
    static void polishDialog(QWidget* w);

protected:
    bool eventFilter(QObject* obj, QEvent* ev) override;

private:
    explicit InGeUiTheme(QObject* parent = nullptr);

    static QString buildDialogQss();
    static void applyWinCaptionColorIfPossible(QWidget* w);

    static constexpr const char* kPropDlg = "ingepDlg";
    static constexpr const char* kPropPolished = "ingepDlgPolished";
};
