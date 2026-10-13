#include "../../src/core/InGeCore.h"
#include "../../src/core/InGeCoreExecutor.h"
#include "../../src/core/StartupInstrumentation.h"
#include <QCoreApplication>
#include <QQmlComponent>
#include <QQmlEngine>
#include <memory>

#include <cstdio>
#include <type_traits>

using namespace inge::core;

#define CHECK(condition) do { if (!(condition)) { \
    std::fprintf(stderr, "FAIL line %d: %s\n", __LINE__, #condition); return 1; \
} } while (false)

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    static_assert(!std::is_copy_constructible_v<InGeCore>);
    static_assert(!std::is_move_constructible_v<InGeCore>);
    auto &core = InGeCore::instance();
    CHECK(&core == &InGeCore::instance());
    CHECK(!core.isReady());

    Request request;
    request.requestId = QStringLiteral("contract-request");
    CHECK(!request.allowRemote && !request.allowLocal);
    CHECK(request.createdAt.isValid());
#if defined(INGE_CORE_ENABLED) && INGE_CORE_ENABLED
    CHECK(core.submit(request).errorCode == QStringLiteral("CORE_NOT_READY"));
    CHECK(core.initializeLightweight());
    CHECK(core.initializeLightweight());
    CHECK(core.isReady());
    const auto expectedError = QStringLiteral("NOT_AVAILABLE");
#else
    CHECK(core.submit(request).errorCode == QStringLiteral("CORE_DISABLED"));
    CHECK(!core.initializeLightweight());
    CHECK(!core.initializeLightweight());
    CHECK(!core.isReady());
    const auto expectedError = QStringLiteral("CORE_DISABLED");
#endif

    for (const auto skill : {Skill::Renditions, Skill::Calicatas, Skill::Drive,
                             Skill::Performance, Skill::Documents}) {
        request.skill = skill;
        request.operation = QStringLiteral("future-operation");
        request.allowLocal = true;
        request.allowRemote = true;
        request.context.connectivity = Connectivity::Online;
        const auto response = core.submit(request);
        CHECK(response.requestId == request.requestId);
        CHECK(response.status == Status::FAILED);
        CHECK(response.errorCode == expectedError);
        CHECK(!response.errorMessage.isEmpty());
        CHECK(response.source == Source::None);
        CHECK(response.result.isEmpty() && response.warnings.isEmpty());
        CHECK(response.confidence == -1.0 && response.latencyMs >= 0);
        CHECK(!core.cancel(request.requestId));
    }
    CHECK(!core.cancel(QString()));

    static_assert(std::has_virtual_destructor_v<InGeCoreExecutor>);
    for (bool enabled : {false, true}) {
        NullExecutor nullExecutor(enabled);
        InGeCoreExecutor &executor = nullExecutor;
        CHECK(!executor.canExecute(request));
        CHECK(executor.health() == (enabled ? ExecutorHealth::NOT_AVAILABLE : ExecutorHealth::DISABLED));
        const auto response = executor.execute(request);
        CHECK(response.requestId == request.requestId);
        CHECK(response.status == Status::FAILED);
        CHECK(response.errorCode == (enabled ? QStringLiteral("NOT_AVAILABLE") : QStringLiteral("DISABLED")));
        CHECK(!response.errorMessage.isEmpty());
        CHECK(response.result.isEmpty() && response.warnings.isEmpty());
        CHECK(response.source == Source::None && response.confidence == -1.0);
        CHECK(!executor.cancel(request.requestId));
        CHECK(!executor.cancel(QString()));
    }

    StartupInstrumentation startup;
    using Event = StartupInstrumentation::Event;
    CHECK(startup.elapsedMs(Event::PROCESS_START) >= 0);
    CHECK(startup.elapsedMs(Event::HOME_READY) == -1);
    CHECK(startup.mark(Event::AUTH_START));
    CHECK(startup.mark(Event::AUTH_READY));
    CHECK(startup.mark(Event::FIRST_UI));
    CHECK(!startup.mark(Event::FIRST_UI));
    QQmlEngine engine;
    QQmlComponent component(&engine);
    component.setData("import QtQml\nQtObject { property bool homeReady: false }", QUrl());
    std::unique_ptr<QObject> root(component.create());
    CHECK(root != nullptr);
    CHECK(!startup.watchReadyProperty(root.get(), "missing", Event::HOME_READY));
    CHECK(startup.watchReadyProperty(root.get(), "homeReady", Event::HOME_READY));
    CHECK(startup.elapsedMs(Event::HOME_READY) == -1);
    CHECK(root->setProperty("homeReady", true));
    const auto homeTime = startup.elapsedMs(Event::HOME_READY);
    CHECK(homeTime >= startup.elapsedMs(Event::PROCESS_START));
    CHECK(root->setProperty("homeReady", false));
    CHECK(root->setProperty("homeReady", true));
    CHECK(startup.elapsedMs(Event::HOME_READY) == homeTime);
    StartupInstrumentation alreadyReady;
    CHECK(alreadyReady.watchReadyProperty(root.get(), "homeReady", Event::HOME_READY));
    CHECK(alreadyReady.elapsedMs(Event::HOME_READY) >= 0);
    root.reset(); // Observers disconnect with their sender before instrumentation dies.

    InGeCoreContext context;
    context.authenticatedUserId = QStringLiteral("user-a");
    context.activeProjectId = QStringLiteral("project-a");
    context.activeModule = QStringLiteral("Renditions");
    context.activeEntityId = QStringLiteral("entity-a");
    context.connectivity = Connectivity::Offline;
    context.deviceTier = DeviceTier::Low;
    core.updateContext(context);
    CHECK(core.context().authenticatedUserId == context.authenticatedUserId);
    CHECK(core.context().activeProjectId == context.activeProjectId);
    CHECK(core.context().activeModule == context.activeModule);
    CHECK(core.context().activeEntityId == context.activeEntityId);
    CHECK(core.context().connectivity == Connectivity::Offline);
    CHECK(core.context().deviceTier == DeviceTier::Low);
    context.authenticatedUserId = QStringLiteral("user-b");
    CHECK(core.context().authenticatedUserId == QStringLiteral("user-a"));
    core.updateContext({});
    CHECK(core.context().authenticatedUserId.isEmpty());
    CHECK(core.context().activeProjectId.isEmpty());
    CHECK(core.context().activeModule.isEmpty());
    CHECK(core.context().activeEntityId.isEmpty());
    CHECK(core.context().connectivity == Connectivity::Unknown);
    CHECK(core.context().deviceTier == DeviceTier::Unknown);
    std::puts("PASS: core contract, NullExecutor, startup events and QML ready observer");
    return 0;
}
