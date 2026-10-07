#pragma once

#include <QFile>
#include <QJSEngine>
#include <QJSValue>
#include <QVariantList>
#include <QVariantMap>

// Execute the same pure rules consumed by QML; do not duplicate blockers in C++.
namespace CalicataValidation {
namespace detail {
// Un motor por hilo con CalicataRules.js YA evaluado. Antes cada validación creaba un
// QJSEngine y volvía a parsear/compilar los ~70 KB del script (decenas de ms en el
// hilo de UI en gama baja: entrada a Revisión, exportación, cambios de estado). Las
// reglas son funciones puras sin estado, así que reutilizar el motor no cambia el
// resultado. Se crea en el hilo que lo usa (QJSEngine no es thread-safe) y no se
// destruye a propósito: evita depender del orden de destrucción al cerrar la app.
struct RulesEngine {
    QJSEngine engine;
    QJSValue validate;
    RulesEngine()
    {
        QFile source(QStringLiteral(":/InGe/Mobile/lib/CalicataRules.js"));
        if (!source.open(QIODevice::ReadOnly)) return;
        QString script = QString::fromUtf8(source.readAll());
        script.remove(QStringLiteral(".pragma library"));
        const auto loaded = engine.evaluate(script, QStringLiteral("CalicataRules.js"));
        if (!loaded.isError())
            validate = engine.globalObject().property(QStringLiteral("validateDocument"));
    }
};

inline RulesEngine &rulesEngine()
{
    thread_local RulesEngine *instance = new RulesEngine;
    return *instance;
}
} // namespace detail

inline QVariantList issues(const QVariantMap &state)
{
    auto &rules = detail::rulesEngine();
    if (rules.validate.isCallable()) {
        const auto result = rules.validate.call({rules.engine.toScriptValue(state)});
        if (!result.isError() && result.isArray()) return result.toVariant().toList();
    }
    return {QVariantMap{{"section", 9}, {"stratum", -1}, {"severity", "BLOCKER"},
        {"message", QStringLiteral("No se pudo cargar el validador de Calicatas.")}}};
}

inline QString firstBlocker(const QVariantMap &state)
{
    for (const auto &value : issues(state)) {
        const auto issue = value.toMap();
        if (issue.value("severity") != "WARNING") return issue.value("message").toString();
    }
    return {};
}
}
