#ifndef JSONWIDGETSERIALIZER_H
#define JSONWIDGETSERIALIZER_H

#include <QJsonObject>
#include <QStringList>
#include <QList>
#include <QMetaObject>

class QWidget;

class JsonWidgetSerializer
{
public:
    struct Options
    {
        // Si un widget tiene como ANCESTRO cualquiera de estos meta-objects,
        // se excluye del guardado/aplicado.
        QList<const QMetaObject*> excludeIfHasAncestorOf;

        // Excluir widgets por objectName exacto
        QStringList excludeObjectNames;

        bool includeLineEdits;
        bool includePlainTextEdits;
        bool includeTextEdits;
        bool includeComboBoxes;
        bool includeCheckBoxes;
        bool includeRadioButtons;
        bool includeSpinBoxes;
        bool includeDoubleSpinBoxes;
        bool includeDateEdits;

        // --- NUEVO: QPushButton (apagado por defecto) ---
        bool includePushButtons;                  // guarda "push_buttons": { objectName: text }
        QStringList includePushButtonObjectNames; // si no está vacío, solo guarda esos botones

        // --- NUEVO: Título de calicata como clave raíz ---
        // Si lo seteas (ej: "btnTituloCalicata"), el serializer guarda también:
        //   out["titulo_calicata"] = <texto del botón>
        // y al aplicar, lo restaura al mismo botón.
        QString tituloCalicataButtonObjectName;

        Options(); // defaults
    };

    // Formato compatible con tu JSON:
    // {
    //   "line_edits": {...},
    //   "plain_text_edits": {...},
    //   "text_edits": {...},
    //   "combo_boxes": { name: {index, text}, ... },
    //   "check_boxes": {...},
    //   "radio_buttons": {...},
    //   "spin_boxes": {...},
    //   "double_spin_boxes": {...},
    //   "date_edits": {...},
    //   "push_buttons": {...},            // (opcional)
    //   "titulo_calicata": "..."          // (opcional, clave raíz)
    // }
    static QJsonObject serialize(const QWidget* root, const Options& opt = Options());
    static void apply(QWidget* root, const QJsonObject& data, const Options& opt = Options());

private:
    static bool isSerializableName(const QString& name);
    static bool isExcludedByName(const QString& name, const Options& opt);
    static bool hasExcludedAncestor(const QObject* obj, const Options& opt);
    static bool allowedByIncludeList(const QString& name, const QStringList& includeList);
};

#endif // JSONWIDGETSERIALIZER_H
