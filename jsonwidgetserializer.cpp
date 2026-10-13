#include "jsonwidgetserializer.h"

#include <QWidget>
#include <QSignalBlocker>

#include <QLineEdit>
#include <QPlainTextEdit>
#include <QTextEdit>
#include <QComboBox>
#include <QCheckBox>
#include <QRadioButton>
#include <QSpinBox>
#include <QDoubleSpinBox>
#include <QDateEdit>
#include <QDate>
#include <QPushButton>

JsonWidgetSerializer::Options::Options()
    : includeLineEdits(true)
    , includePlainTextEdits(true)
    , includeTextEdits(true)
    , includeComboBoxes(true)
    , includeCheckBoxes(true)
    , includeRadioButtons(true)
    , includeSpinBoxes(true)
    , includeDoubleSpinBoxes(true)
    , includeDateEdits(true)
    , includePushButtons(false) // <- apagado por defecto para no afectar tu UI
{
}

bool JsonWidgetSerializer::isSerializableName(const QString& name)
{
    if (name.isEmpty()) return false;
    if (name.startsWith("qt_", Qt::CaseInsensitive)) return false;
    return true;
}

bool JsonWidgetSerializer::isExcludedByName(const QString& name, const Options& opt)
{
    return opt.excludeObjectNames.contains(name);
}

bool JsonWidgetSerializer::hasExcludedAncestor(const QObject* obj, const Options& opt)
{
    if (!obj) return false;
    if (opt.excludeIfHasAncestorOf.isEmpty()) return false;

    const QObject* p = obj->parent();
    while (p) {
        const QMetaObject* pm = p->metaObject();
        for (const QMetaObject* ex : opt.excludeIfHasAncestorOf) {
            if (!ex || !pm) continue;
            if (pm->inherits(ex)) return true;
        }
        p = p->parent();
    }
    return false;
}

bool JsonWidgetSerializer::allowedByIncludeList(const QString& name, const QStringList& includeList)
{
    return includeList.isEmpty() || includeList.contains(name);
}

QJsonObject JsonWidgetSerializer::serialize(const QWidget* root, const Options& opt)
{
    QJsonObject out;
    if (!root) return out;

    QJsonObject lineEdits, plainEdits, textEdits, combos, checks, radios, spins, dspins, dates;
    QJsonObject pushButtons;

    if (opt.includeLineEdits) {
        const auto ws = root->findChildren<QLineEdit*>();
        for (auto* w : ws) {
            const QString n = w->objectName();
            if (!isSerializableName(n)) continue;
            if (isExcludedByName(n, opt)) continue;
            if (hasExcludedAncestor(w, opt)) continue;
            lineEdits.insert(n, w->text());
        }
    }

    if (opt.includePlainTextEdits) {
        const auto ws = root->findChildren<QPlainTextEdit*>();
        for (auto* w : ws) {
            const QString n = w->objectName();
            if (!isSerializableName(n)) continue;
            if (isExcludedByName(n, opt)) continue;
            if (hasExcludedAncestor(w, opt)) continue;
            plainEdits.insert(n, w->toPlainText());
        }
    }

    if (opt.includeTextEdits) {
        const auto ws = root->findChildren<QTextEdit*>();
        for (auto* w : ws) {
            const QString n = w->objectName();
            if (!isSerializableName(n)) continue;
            if (isExcludedByName(n, opt)) continue;
            if (hasExcludedAncestor(w, opt)) continue;
            textEdits.insert(n, w->toPlainText());
        }
    }

    if (opt.includeComboBoxes) {
        const auto ws = root->findChildren<QComboBox*>();
        for (auto* w : ws) {
            const QString n = w->objectName();
            if (!isSerializableName(n)) continue;
            if (isExcludedByName(n, opt)) continue;
            if (hasExcludedAncestor(w, opt)) continue;

            QJsonObject v;
            v.insert("index", w->currentIndex());
            v.insert("text",  w->currentText());
            combos.insert(n, v);
        }
    }

    if (opt.includeCheckBoxes) {
        const auto ws = root->findChildren<QCheckBox*>();
        for (auto* w : ws) {
            const QString n = w->objectName();
            if (!isSerializableName(n)) continue;
            if (isExcludedByName(n, opt)) continue;
            if (hasExcludedAncestor(w, opt)) continue;
            checks.insert(n, w->isChecked());
        }
    }

    if (opt.includeRadioButtons) {
        const auto ws = root->findChildren<QRadioButton*>();
        for (auto* w : ws) {
            const QString n = w->objectName();
            if (!isSerializableName(n)) continue;
            if (isExcludedByName(n, opt)) continue;
            if (hasExcludedAncestor(w, opt)) continue;
            radios.insert(n, w->isChecked());
        }
    }

    if (opt.includeSpinBoxes) {
        const auto ws = root->findChildren<QSpinBox*>();
        for (auto* w : ws) {
            const QString n = w->objectName();
            if (!isSerializableName(n)) continue;
            if (isExcludedByName(n, opt)) continue;
            if (hasExcludedAncestor(w, opt)) continue;
            spins.insert(n, w->value());
        }
    }

    if (opt.includeDoubleSpinBoxes) {
        const auto ws = root->findChildren<QDoubleSpinBox*>();
        for (auto* w : ws) {
            const QString n = w->objectName();
            if (!isSerializableName(n)) continue;
            if (isExcludedByName(n, opt)) continue;
            if (hasExcludedAncestor(w, opt)) continue;
            dspins.insert(n, w->value());
        }
    }

    if (opt.includeDateEdits) {
        const auto ws = root->findChildren<QDateEdit*>();
        for (auto* w : ws) {
            const QString n = w->objectName();
            if (!isSerializableName(n)) continue;
            if (isExcludedByName(n, opt)) continue;
            if (hasExcludedAncestor(w, opt)) continue;
            dates.insert(n, w->date().toString(Qt::ISODate));
        }
    }

    // --- NUEVO: guardar push buttons si se habilita ---
    if (opt.includePushButtons) {
        const auto ws = root->findChildren<QPushButton*>();
        for (auto* w : ws) {
            const QString n = w->objectName();
            if (!isSerializableName(n)) continue;
            if (!allowedByIncludeList(n, opt.includePushButtonObjectNames)) continue;
            if (isExcludedByName(n, opt)) continue;
            if (hasExcludedAncestor(w, opt)) continue;
            pushButtons.insert(n, w->text());
        }
    }

    out.insert("line_edits", lineEdits);
    out.insert("plain_text_edits", plainEdits);
    out.insert("text_edits", textEdits);
    out.insert("combo_boxes", combos);
    out.insert("check_boxes", checks);
    out.insert("radio_buttons", radios);
    out.insert("spin_boxes", spins);
    out.insert("double_spin_boxes", dspins);
    out.insert("date_edits", dates);

    if (!pushButtons.isEmpty())
        out.insert("push_buttons", pushButtons);

    // --- NUEVO: título de calicata como clave raíz "titulo_calicata" ---
    if (!opt.tituloCalicataButtonObjectName.trimmed().isEmpty()) {
        auto *btn = root->findChild<QPushButton*>(opt.tituloCalicataButtonObjectName);
        if (btn && isSerializableName(btn->objectName())
            && !isExcludedByName(btn->objectName(), opt)
            && !hasExcludedAncestor(btn, opt))
        {
            out.insert("titulo_calicata", btn->text());
        }
    }

    return out;
}

void JsonWidgetSerializer::apply(QWidget* root, const QJsonObject& data, const Options& opt)
{
    if (!root) return;

    auto applyLineEdits = [&](){
        if (!data.contains("line_edits") || !data["line_edits"].isObject()) return;
        const QJsonObject m = data["line_edits"].toObject();
        for (auto it = m.begin(); it != m.end(); ++it) {
            const QString n = it.key();
            if (!isSerializableName(n)) continue;
            if (isExcludedByName(n, opt)) continue;
            auto* w = root->findChild<QLineEdit*>(n);
            if (!w) continue;
            if (hasExcludedAncestor(w, opt)) continue;
            const QSignalBlocker b(w);
            w->setText(it.value().toString());
        }
    };

    auto applyPlainText = [&](){
        if (!data.contains("plain_text_edits") || !data["plain_text_edits"].isObject()) return;
        const QJsonObject m = data["plain_text_edits"].toObject();
        for (auto it = m.begin(); it != m.end(); ++it) {
            const QString n = it.key();
            if (!isSerializableName(n)) continue;
            if (isExcludedByName(n, opt)) continue;
            auto* w = root->findChild<QPlainTextEdit*>(n);
            if (!w) continue;
            if (hasExcludedAncestor(w, opt)) continue;
            const QSignalBlocker b(w);
            w->setPlainText(it.value().toString());
        }
    };

    auto applyTextEdits = [&](){
        if (!data.contains("text_edits") || !data["text_edits"].isObject()) return;
        const QJsonObject m = data["text_edits"].toObject();
        for (auto it = m.begin(); it != m.end(); ++it) {
            const QString n = it.key();
            if (!isSerializableName(n)) continue;
            if (isExcludedByName(n, opt)) continue;
            auto* w = root->findChild<QTextEdit*>(n);
            if (!w) continue;
            if (hasExcludedAncestor(w, opt)) continue;
            const QSignalBlocker b(w);
            w->setPlainText(it.value().toString());
        }
    };

    auto applyCombos = [&](){
        if (!data.contains("combo_boxes") || !data["combo_boxes"].isObject()) return;
        const QJsonObject m = data["combo_boxes"].toObject();
        for (auto it = m.begin(); it != m.end(); ++it) {
            const QString n = it.key();
            if (!isSerializableName(n)) continue;
            if (isExcludedByName(n, opt)) continue;

            auto* w = root->findChild<QComboBox*>(n);
            if (!w) continue;
            if (hasExcludedAncestor(w, opt)) continue;

            QString txt;
            int idx = -1;

            if (it.value().isObject()) {
                const QJsonObject v = it.value().toObject();
                idx = v.value("index").toInt(-1);
                txt = v.value("text").toString();
            } else {
                txt = it.value().toString();
            }

            const QSignalBlocker b(w);

            if (!txt.isEmpty()) {
                const int f = w->findText(txt);
                if (f >= 0) { w->setCurrentIndex(f); continue; }
                if (w->isEditable()) { w->setEditText(txt); continue; }
            }

            if (idx >= 0 && idx < w->count())
                w->setCurrentIndex(idx);
        }
    };

    auto applyChecks = [&](){
        if (!data.contains("check_boxes") || !data["check_boxes"].isObject()) return;
        const QJsonObject m = data["check_boxes"].toObject();
        for (auto it = m.begin(); it != m.end(); ++it) {
            const QString n = it.key();
            if (!isSerializableName(n)) continue;
            if (isExcludedByName(n, opt)) continue;
            auto* w = root->findChild<QCheckBox*>(n);
            if (!w) continue;
            if (hasExcludedAncestor(w, opt)) continue;
            const QSignalBlocker b(w);
            w->setChecked(it.value().toBool());
        }
    };

    auto applyRadios = [&](){
        if (!data.contains("radio_buttons") || !data["radio_buttons"].isObject()) return;
        const QJsonObject m = data["radio_buttons"].toObject();
        for (auto it = m.begin(); it != m.end(); ++it) {
            const QString n = it.key();
            if (!isSerializableName(n)) continue;
            if (isExcludedByName(n, opt)) continue;
            auto* w = root->findChild<QRadioButton*>(n);
            if (!w) continue;
            if (hasExcludedAncestor(w, opt)) continue;
            const QSignalBlocker b(w);
            w->setChecked(it.value().toBool());
        }
    };

    auto applySpins = [&](){
        if (!data.contains("spin_boxes") || !data["spin_boxes"].isObject()) return;
        const QJsonObject m = data["spin_boxes"].toObject();
        for (auto it = m.begin(); it != m.end(); ++it) {
            const QString n = it.key();
            if (!isSerializableName(n)) continue;
            if (isExcludedByName(n, opt)) continue;
            auto* w = root->findChild<QSpinBox*>(n);
            if (!w) continue;
            if (hasExcludedAncestor(w, opt)) continue;
            const QSignalBlocker b(w);
            w->setValue(it.value().toInt());
        }
    };

    auto applyDSpins = [&](){
        if (!data.contains("double_spin_boxes") || !data["double_spin_boxes"].isObject()) return;
        const QJsonObject m = data["double_spin_boxes"].toObject();
        for (auto it = m.begin(); it != m.end(); ++it) {
            const QString n = it.key();
            if (!isSerializableName(n)) continue;
            if (isExcludedByName(n, opt)) continue;
            auto* w = root->findChild<QDoubleSpinBox*>(n);
            if (!w) continue;
            if (hasExcludedAncestor(w, opt)) continue;
            const QSignalBlocker b(w);
            w->setValue(it.value().toDouble());
        }
    };

    auto applyDates = [&](){
        if (!data.contains("date_edits") || !data["date_edits"].isObject()) return;
        const QJsonObject m = data["date_edits"].toObject();
        for (auto it = m.begin(); it != m.end(); ++it) {
            const QString n = it.key();
            if (!isSerializableName(n)) continue;
            if (isExcludedByName(n, opt)) continue;
            auto* w = root->findChild<QDateEdit*>(n);
            if (!w) continue;
            if (hasExcludedAncestor(w, opt)) continue;

            const QDate d = QDate::fromString(it.value().toString(), Qt::ISODate);
            if (!d.isValid()) continue;
            const QSignalBlocker b(w);
            w->setDate(d);
        }
    };

    // --- NUEVO: aplicar push_buttons si existe ---
    auto applyPushButtons = [&](){
        if (!data.contains("push_buttons") || !data["push_buttons"].isObject()) return;
        const QJsonObject m = data["push_buttons"].toObject();
        for (auto it = m.begin(); it != m.end(); ++it) {
            const QString n = it.key();
            if (!isSerializableName(n)) continue;
            if (!allowedByIncludeList(n, opt.includePushButtonObjectNames)) continue;
            if (isExcludedByName(n, opt)) continue;

            auto* w = root->findChild<QPushButton*>(n);
            if (!w) continue;
            if (hasExcludedAncestor(w, opt)) continue;

            const QSignalBlocker b(w);
            w->setText(it.value().toString());
        }
    };

    // --- NUEVO: aplicar titulo_calicata al botón configurado ---
    auto applyTituloCalicata = [&](){
        if (opt.tituloCalicataButtonObjectName.trimmed().isEmpty()) return;
        if (!data.contains("titulo_calicata")) return;

        auto* btn = root->findChild<QPushButton*>(opt.tituloCalicataButtonObjectName);
        if (!btn) return;

        const QString n = btn->objectName();
        if (!isSerializableName(n)) return;
        if (isExcludedByName(n, opt)) return;
        if (hasExcludedAncestor(btn, opt)) return;

        const QSignalBlocker b(btn);
        btn->setText(data.value("titulo_calicata").toString());
    };

    // Aplicar en orden “natural”
    applyLineEdits();
    applyPlainText();
    applyTextEdits();
    applyCombos();
    applyChecks();
    applyRadios();
    applySpins();
    applyDSpins();
    applyDates();

    // nuevos
    applyPushButtons();
    applyTituloCalicata();
}
