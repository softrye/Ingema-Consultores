#include "mainwindow.h"
#include "appcontext.h"
#include "ingetheme.h"

#include <QApplication>
#include <QCoreApplication>
#include <QIcon>
#include <QEvent>
#include <QWidget>
#include <QStyleFactory>


class AppIconFilter : public QObject {
public:
    bool eventFilter(QObject* obj, QEvent* ev) override {
        if (ev->type() == QEvent::Show) {
            auto* w = qobject_cast<QWidget*>(obj);
            if (w && w->isWindow()) {
                // Si por algún motivo quedó nulo o distinto, lo forzamos
                const QIcon ic = qApp->windowIcon();
                if (!ic.isNull() && w->windowIcon().cacheKey() != ic.cacheKey()) {
                    w->setWindowIcon(ic);
                }
            }
        }
        return QObject::eventFilter(obj, ev);
    }
};

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);

    app.setStyle(QStyleFactory::create("Fusion"));
    IngeTheme::apply(app);

    app.setWindowIcon(QIcon(":/icons/ICONO_APP.png"));

    static AppIconFilter iconFilter;
    app.installEventFilter(&iconFilter);

    QCoreApplication::setOrganizationName("INGEMA");
    QCoreApplication::setOrganizationDomain("ingema.pe");
    QCoreApplication::setApplicationName("InGePlus");

    QObject::connect(qApp, &QCoreApplication::aboutToQuit, [](){
        qDebug() << ">>> aboutToQuit() disparado";
    });

    AppContext ctx;
    AppContext::setInstance(&ctx);

    MainWindow w(&ctx);
    w.show();

    return app.exec();
}
