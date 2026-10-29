#pragma once
#include <QVariantList>
#include <QVariantMap>

// Registro de llamadas del RenditionRepository de prueba (fake_repository.cpp).
struct FakeServer {
    static QVariantList calls;
    static QVariantMap last(const QString &method)
    {
        for (int i = calls.size() - 1; i >= 0; --i)
            if (calls.at(i).toMap().value(QStringLiteral("method")) == method)
                return calls.at(i).toMap().value(QStringLiteral("args")).toMap();
        return {};
    }
    static int count(const QString &method)
    {
        int n = 0;
        for (const auto &c : calls) n += c.toMap().value(QStringLiteral("method")) == method;
        return n;
    }
};
