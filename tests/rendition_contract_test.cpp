#include "src/cpp/renditioncontract.h"
#include "src/cpp/renditionvalidation.h"
#include "src/cpp/renditionattachmentcontract.h"
#include <QJsonDocument>
#include <cassert>
#include <iostream>
int main() {
    const QString aid = "11111111-1111-4111-8111-111111111111";
    const QString key = "renditions/22222222-2222-4222-8222-222222222222/expenses/33333333-3333-4333-8333-333333333333/attachments/" + aid;
    assert(RenditionAttachmentContract::objectPath({{"storage_path", key}}) == key);
    assert(RenditionAttachmentContract::valid("project-files", key, aid));
    assert(!RenditionAttachmentContract::valid("project-files", "", aid));
    assert(!RenditionAttachmentContract::valid("project-files", key + "/", aid));
    assert(!RenditionAttachmentContract::valid("other", key, aid));
    const QVariantMap saved{{"localId", "local-1"}, {"remoteId", "remote-1"},
        {"rowVersion", 4}, {"documentParentNodeId", "folder"}, {"spaceId", "space"},
        {"periodStart", "2026-09-01"}, {"periodEnd", "2026-09-30"},
        {"totalPen", 20.0}, {"versionNumber", 1}};
    const QVariantMap rpc{{"projects", QVariantList{
        QVariantMap{{"id", "p1"}, {"is_primary", false}},
        QVariantMap{{"id", "p2"}, {"is_primary", true}, {"name", "Principal"}}}},
        {"version_number", 2}};
    auto normalized = RenditionContract::normalize(rpc, saved);
    assert(normalized.value("projectIds").toList() == QVariantList({"p1", "p2"}));
    assert(normalized.value("primaryProjectId") == "p2");
    assert(normalized.value("versionNumber") == 2);
    assert(normalized.value("totalPen").toDouble() == 20);
    auto draft = saved;
    for (auto it = normalized.cbegin(); it != normalized.cend(); ++it) draft.insert(it.key(), it.value());
    QVariantMap expense{{"localId", "expense-1"}, {"projectId", "p2"}, {"expenseDate", "2026-09-08"},
        {"amount", "10.00"}, {"currencyCode", "PEN"}, {"concept", "Comida"},
        {"categoryCode", "CAT"}, {"paymentMethodCode", "PAY"}, {"supportTypeCode", "SUP"}};
    assert(RenditionValidation::expense(draft, expense).isEmpty());
    auto invalid = expense; invalid.insert("projectId", "foreign");
    assert(!RenditionValidation::expense(draft, invalid).isEmpty());
    invalid = expense; invalid.insert("expenseDate", "2026-10-01");
    assert(!RenditionValidation::expense(draft, invalid).isEmpty());
    auto usd = expense; usd.insert("currencyCode", "USD"); usd.insert("amount", "3.25");
    draft.insert("expenses", QVariantList{expense, expense, usd});
    RenditionValidation::totals(draft);
    assert(draft.value("totalPen").toDouble() == 20.0);
    assert(draft.value("totalUsd").toDouble() == 3.25);
    assert(draft.value("expenseCount").toInt() == 3);
    assert(draft.value("pendingCount").toInt() == 3);
    const auto reopened = QJsonDocument::fromJson(QJsonDocument::fromVariant(draft).toJson()).toVariant().toMap();
    for (const auto &key : {"localId", "remoteId", "rowVersion", "documentParentNodeId", "primaryProjectId", "projectIds", "expenses"})
        assert(reopened.value(key) == draft.value(key));
    const auto sparse = RenditionContract::normalize({{"status", "PRESENTADA"}}, reopened);
    assert(sparse.value("primaryProjectId") == "p2");
    assert(sparse.value("projectIds").toList().size() == 2);
    assert(RenditionContract::normalize({{"projects", QVariantList{}}}, reopened).value("projectIds").toList().isEmpty());
    std::cout << "PASS: RPC projects, explicit primary, sparse responses, versions, expense validation, separate totals, JSON roundtrip\n";
}
