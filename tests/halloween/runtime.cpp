#include <QGuiApplication>
#include <QQmlEngine>
#include <QQmlComponent>
#include <QQuickItem>
#include <QFileInfo>
#include <QSignalSpy>
#include <iostream>
#include <cstdlib>

static void check(bool ok, const char *label) {
    if (!ok) { std::cerr << "FAIL " << label << '\n'; std::exit(1); }
}
int main(int argc, char **argv) {
    QGuiApplication app(argc, argv);
    QQmlEngine engine;
    QQmlComponent flow(&engine);
    flow.setData("import QtQml; QtObject { property bool motionAllowed: true; property int thermalStatus: 0; function duration(ms) { return ms } }", QUrl());
    std::unique_ptr<QObject> core(flow.create());
    check(bool(core), "flow input");
    const auto dir = QString::fromLocal8Bit(argv[1]);
    QQmlComponent component(&engine, QUrl::fromLocalFile(dir + "/HalloweenController.qml"));
    if (component.isError()) std::cerr << component.errorString().toStdString();
    std::unique_ptr<QObject> ctl(component.createWithInitialProperties({{"flow", QVariant::fromValue(core.get())}, {"choice", "halloween"}, {"foreground", true}, {"safeSurface", true}}));
    if (!ctl) std::cerr << component.errorString().toStdString();
    check(bool(ctl), "real controller loads");
    QSignalSpy presented(ctl.get(), SIGNAL(scarePresented(int)));
    auto advance = [&](double ms) { check(QMetaObject::invokeMethod(ctl.get(), "advance", Q_ARG(QVariant, ms)), "advance active clock"); };
    check(ctl->property("motionActive").toBool(), "motion enabled");
    advance(300000);
    check(ctl->property("scareVisible").toBool(), "scare at five minutes");
    check(ctl->property("scareSerial").toInt() == 1, "first scare");
    check(presented.count() == 1, "scare publishes haptic/sound event exactly once");
    ctl->setProperty("safeSurface", false);
    check(!ctl->property("scareVisible").toBool(), "modal hides scare immediately");
    advance(300000);
    check(ctl->property("scareSerial").toInt() == 1, "modal defers next scare");
    ctl->setProperty("foreground", false);
    advance(300000);
    check(!ctl->property("motionActive").toBool(), "background freezes motion");
    ctl->setProperty("foreground", true);
    ctl->setProperty("safeSurface", true);
    advance(1);
    check(ctl->property("scareSerial").toInt() == 2, "second deferred scare");
    ctl->setProperty("reducedMotion", true);
    check(!ctl->property("motionActive").toBool(), "reduce motion freezes decorations");
    check(ctl->property("scareVisible").toBool(), "reduce motion retains static notice");
    core->setProperty("thermalStatus", 2);
    check(!ctl->property("scareVisible").toBool(), "thermal hides scare");
    ctl->setProperty("choice", "none");
    check(!ctl->property("seasonEnabled").toBool(), "none disables season");
    QQmlComponent layer(&engine, QUrl::fromLocalFile(dir + "/HalloweenLayer.qml"));
    std::unique_ptr<QObject> art(layer.createWithInitialProperties({{"controller", QVariant::fromValue(ctl.get())}}));
    if (!art) std::cerr << layer.errorString().toStdString();
    check(bool(art), "real layer loads");
    check(!art->property("enabled").toBool(), "decorations never take input");
    check(art->property("animatedSpriteCount").toInt() <= 12, "sprite budget");
    ctl->setProperty("choice", "halloween");
    ctl->setProperty("reducedMotion", false);
    core->setProperty("thermalStatus", 0);
    check(art->property("moving").toBool(), "foreground layer moves");
    check(art->setProperty("running", false), "surface has an activity input");
    check(!art->property("moving").toBool(), "covered surface freezes while clock continues");
    check(art->property("animatedSpriteCount").toInt() == 0, "covered surface consumes no animated sprite budget");
    std::cout << "PASS Halloween real QML: clock, modals, background, reduced motion, thermal, sprite budget\n";
}
