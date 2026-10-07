#pragma once

#include <QObject>
#include <QVariantMap>

class MapWorkspaceController final : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString workspaceHtml READ workspaceHtml CONSTANT)
    Q_PROPERTY(QString configurationPath READ configurationPath CONSTANT)

public:
    explicit MapWorkspaceController(QObject *parent = nullptr);

    QString workspaceHtml() const;
    QString configurationPath() const;

    Q_INVOKABLE QVariantMap runtimeConfiguration() const;

private:
    QString composeWorkspaceHtml() const;
    QVariantMap readExternalConfiguration() const;

    QString m_workspaceHtml;
    QString m_configurationPath;
};
