#ifndef CALICATAEXCELEXPORTER_H
#define CALICATAEXCELEXPORTER_H

#include <QString>
#include <QJsonObject>

namespace QXlsx {class Document;}

class CalicataExcelExporter
{
public:
    static QString templateResourcePath(); // tu plantilla en .qrc
    static bool copyTemplateTo(const QString& outExcelPath, QString* outError);

    // Exporta desde JSON hacia un Excel basado en tu plantilla.
    // En Windows: usa Excel via PowerShell (COM), no requiere QAxObject.
    static bool exportFromCalicataFile(const QString& calicataJsonPath,
                                       const QString& outExcelPath,
                                       QString* err);

private:
void llenarHeaderYObservaciones(QXlsx::Document& xlsx,
                                const QString& sheet,
                                const QJsonObject& root);
};

#endif // CALICATAEXCELEXPORTER_H
