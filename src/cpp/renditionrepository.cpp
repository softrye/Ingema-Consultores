#include "renditionrepository.h"
#include "renditionadminrpc.h"

#include "appcontext.h"
#include "authsession.h"
#include "supabaseclient.h"
#include "renditionattachmentcontract.h"
#include "renditionexportservice.h"

#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QFileInfo>
#include <QMimeDatabase>
#include <QMimeType>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPointer>
#include <QTimer>
#include <QUrl>
#include <QUrlQuery>
#ifndef INGEPLUS_WEB_API_ORIGIN
#define INGEPLUS_WEB_API_ORIGIN ""
#endif

namespace {

QString responseErrorCode(const QJsonObject &object)
{
    const QString backendCode = object.value(QStringLiteral("message")).toString();
    if (backendCode.startsWith(QStringLiteral("RENDITION_"))
        || backendCode == QStringLiteral("AUTH_REQUIRED")
        || backendCode == QStringLiteral("PROFILE_NOT_ACTIVE")) {
        return backendCode;
    }
    return object.value(QStringLiteral("code")).toString(QStringLiteral("HTTP_ERROR"));
}

QString responseErrorMessage(const QJsonObject &object, const QString &fallback)
{
    const QString message = object.value(QStringLiteral("message")).toString();
    if (!message.isEmpty())
        return message;
    const QString details = object.value(QStringLiteral("details")).toString();
    return details.isEmpty() ? fallback : details;
}

QVariant valueFor(const QVariantMap &map, const QString &camel,
                  const QString &snake)
{
    const QVariant camelValue = map.value(camel);
    return camelValue.isValid() ? camelValue : map.value(snake);
}

QString localFileName(const QString &pathOrUrl)
{
    const QUrl url(pathOrUrl);
    return url.isLocalFile() ? url.toLocalFile() : pathOrUrl;
}

QString storageObjectUrl(const SupabaseClient *client, const QString &bucket,
                         const QString &objectPath)
{
    QStringList encodedSegments;
    const QStringList segments = objectPath.split(QLatin1Char('/'), Qt::SkipEmptyParts);
    encodedSegments.reserve(segments.size());
    for (const QString &segment : segments)
        encodedSegments.append(QString::fromLatin1(QUrl::toPercentEncoding(segment)));
    return client->projectUrl() + QStringLiteral("/storage/v1/object/")
        + QString::fromLatin1(QUrl::toPercentEncoding(bucket)) + QLatin1Char('/')
        + encodedSegments.join(QLatin1Char('/'));
}

} // namespace

RenditionRepository::RenditionRepository(QObject *parent)
    : QObject(parent)
{
    if (appContext() && appContext()->auth()) {
        connect(appContext()->auth(), &AuthSession::loggedOut,
                this, &RenditionRepository::clear);
        connect(appContext()->auth(), &AuthSession::accountSwitchStarted,
                this, [this](const QString &) { clear(); });
    }
}


void RenditionRepository::setFinancial(const QString &kind, const QVariantMap &op)
{
    QVariantMap args{{"p_rendition_id",op.value("renditionRemoteId")},
                     {"p_expected_row_version",op.value("expectedRowVersion")},
                     {"p_request_id",op.value("requestId")}};
    QString rpc;
    if (kind=="funding_set") {
        rpc="set_rendition_funding_v01";args.insert("p_enabled",op.value("enabled"));
        args.insert("p_pen",op.value("pen"));args.insert("p_usd",op.value("usd"));
    } else if (kind=="exchange_set") {
        rpc="set_rendition_exchange_rate_v02";args.insert("p_rate",op.value("rate"));
        args.insert("p_mode",op.value("mode"));args.insert("p_quoted_on",op.value("quoted_on"));
    } else { emit operationFailed(kind,"UNKNOWN_OPERATION","Unsupported financial operation");return; }
    callRpc(kind,rpc,args,[this](const QVariant &payload) { emit financialSaved(firstRow(payload)); });
}

void RenditionRepository::requestExchangeQuote(const QString &requestId, const QString &renditionId)
{
    const QString operation="received/"+requestId;
    auto *session=appContext() ? appContext()->auth() : nullptr;
    auto *client=supabase();
    if (!client || !session || !session->logged() || session->accessToken().isEmpty()) {
        emit operationFailed(operation,"AUTH_REQUIRED","Sign in before requesting a quote");return;
    }
    QUrl origin(qEnvironmentVariable("INGEPLUS_WEB_API_ORIGIN",QStringLiteral(INGEPLUS_WEB_API_ORIGIN)));
    const bool loopback=origin.host()=="127.0.0.1" || origin.host()=="localhost" || origin.host()=="::1";
    if (!origin.isValid() || origin.host().isEmpty() || (!origin.path().isEmpty() && origin.path()!="/")
        || !origin.userInfo().isEmpty() || origin.hasQuery() || origin.hasFragment()
        || (origin.scheme()!="https" && !(origin.scheme()=="http" && loopback))) {
        emit operationFailed(operation,"QUOTE_ORIGIN_NOT_CONFIGURED","Configure the authenticated DEV Web API origin; saved rate is retained");return;
    }
    origin.setPath("/api/renditions/exchange-rate");QUrlQuery query;query.addQueryItem("renditionId",renditionId);origin.setQuery(query);
    QNetworkRequest request(origin);request.setRawHeader("Authorization",("Bearer "+session->accessToken()).toUtf8());
    request.setRawHeader("Accept","application/json");request.setTransferTimeout(15000);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,QNetworkRequest::ManualRedirectPolicy);
    auto *reply=client->nam()->get(request);const auto epoch=m_requestEpoch;beginRequest();
    connect(reply,&QNetworkReply::finished,this,[this,reply,epoch,requestId,operation] {
        endRequest();const int status=reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto raw=reply->readAll();const auto error=reply->error();reply->deleteLater();
        if (epoch!=m_requestEpoch) return;
        if (error!=QNetworkReply::NoError || status!=200 || raw.size()>100000) {
            emit operationFailed(operation,status==401 ? "AUTH_REQUIRED" : status==403 ? "FORBIDDEN" : "QUOTE_UNAVAILABLE","Quote unavailable; saved rate is retained");return;
        }
        QJsonParseError parse;const auto json=QJsonDocument::fromJson(raw,&parse);
        if (parse.error!=QJsonParseError::NoError || !json.isObject()) {
            emit operationFailed(operation,"INVALID_RESPONSE","Invalid quote; saved rate is retained");return;
        }
        emit receivedResult(requestId,"exchangeQuote",json.object().toVariantMap());
    });
}

void RenditionRepository::clear()
{
    ++m_requestEpoch;
    emit receivedReset();
    m_renditions.clear();
    m_projects.clear();
    m_currentRendition.clear();
    m_expenses.clear();
    m_expenseSummary.clear();
    m_expenseCatalogs.clear();
    m_versions.clear();
    m_attachments.clear();
    m_documentLocation.clear();
    m_documentWorkspace.clear();
    m_documentSpace.clear();
    m_documentFolders.clear();
    m_documentCapabilities.clear();
    setLastError({});
    emit renditionsChanged();
    emit projectsChanged();
    emit currentRenditionChanged();
    emit expensesChanged();
    emit expenseSummaryChanged();
    emit expenseCatalogsChanged();
    emit versionsChanged();
    emit attachmentsChanged();
    emit documentLocationChanged();
    emit documentWorkspaceChanged();
    emit documentSpaceChanged();
    emit documentFoldersChanged();
    emit documentCapabilitiesChanged();
}

void RenditionRepository::listRenditions(int limit,
                                         const QString &afterUpdatedAt,
                                         const QString &afterId)
{
    callRpc(QStringLiteral("list"), QStringLiteral("list_renditions_effective_v06"), {
        {QStringLiteral("p_limit"), qBound(1, limit, 100)},
        {QStringLiteral("p_after_updated_at"), nullableText(afterUpdatedAt)},
        {QStringLiteral("p_after_id"), nullableText(afterId)}
    }, [this, limit, afterUpdatedAt, afterId](const QVariant &payload) {
        const auto page = rows(payload);
        if (afterId.isEmpty()) m_renditions.clear();
        if (m_renditions.size() + page.size() > 100000) {
            emit operationFailed("list", "PULL_CAPACITY", "La lista supera la capacidad local. No se completó la actualización.");
            return;
        }
        m_renditions.append(page);
        if (page.size() == qBound(1, limit, 100)) {
            const auto last = page.last().toMap();
            const auto nextId = last.value("id").toString();
            const auto nextTime = last.value("updated_at").toString();
            if (nextId.isEmpty() || nextTime.isEmpty() ||
                (nextId == afterId && nextTime == afterUpdatedAt)) {
                emit operationFailed("list", "PULL_CURSOR_INVALID", "No se pudo completar la actualización. Intenta nuevamente.");
                return;
            }
            listRenditions(limit, nextTime, nextId);
            return;
        }
        emit renditionsChanged();
        emit operationSucceeded(QStringLiteral("list"));
    });
}

void RenditionRepository::getRendition(const QString &renditionId)
{
    const auto serial = ++m_detailRequestSerial;
    callRpc(QStringLiteral("get"), QStringLiteral("get_rendition_effective_v06"), {
        {QStringLiteral("p_rendition_id"), renditionId}
    }, [this, renditionId, serial](const QVariant &payload) {
        if (serial != m_detailRequestSerial) return;
        m_currentRendition = firstRow(payload);
        m_currentRendition.remove("financialVersionId");
        emit currentRenditionChanged();
        const auto status = m_currentRendition.value("status").toString();
        const bool workingCopy = status == "BORRADOR" || status == "OBSERVADO";
        // READ users also read the current working supplement, never a stale
        // frozen fund merely because they cannot edit the working copy.
        const auto versionId = workingCopy ? QVariant{} : nullableText(m_currentRendition.value("current_version_id").toString());
        for (const auto &supplement : {QStringLiteral("funding"), QStringLiteral("exchangeRate")}) {
            const auto rpc = supplement == "funding" ? QStringLiteral("get_rendition_funding_v01") : QStringLiteral("get_rendition_exchange_rate_v02");
            callRpc(supplement + "_read", rpc, {{"p_rendition_id", renditionId}, {"p_version_id", versionId}},
                [this, serial, supplement, versionId](const QVariant &value) {
                    if (serial != m_detailRequestSerial) return;
                    m_currentRendition.insert(supplement, firstRow(value));
                    if (!versionId.isNull() && m_currentRendition.contains("funding") && m_currentRendition.contains("exchangeRate"))
                        m_currentRendition.insert("financialVersionId", versionId);
                    emit currentRenditionChanged();
                });
        }
    });
}

void RenditionRepository::listProjects()
{
    callRpc(QStringLiteral("projects"),
            QStringLiteral("list_my_rendition_projects_v01"), {},
            [this](const QVariant &payload) {
        m_projects = rows(payload);
        emit projectsChanged();
    });
}

void RenditionRepository::createRendition(const QString &requestId,
                                          const QString &periodStart,
                                          const QString &periodEnd,
                                          const QVariantList &projectIds,
                                          const QString &primaryProjectId,
                                          const QString &documentParentNodeId)
{
    QVariantMap arguments{
        {QStringLiteral("p_request_id"), requestId},
        {QStringLiteral("p_period_start"), periodStart},
        {QStringLiteral("p_period_end"), periodEnd},
        {QStringLiteral("p_project_ids"), uuidArray(projectIds)},
        {QStringLiteral("p_primary_project_id"), primaryProjectId}
    };
    QString rpcName = QStringLiteral("create_my_rendition_draft_v01");
    if (v02Enabled()) {
        if (documentParentNodeId.trimmed().isEmpty()) {
            emit operationFailed(QStringLiteral("create"),
                                 QStringLiteral("RENDITION_DOCUMENT_LOCATION_REQUIRED"),
                                 QStringLiteral("Selecciona una ubicación .rend."));
            return;
        }
        rpcName = QStringLiteral("create_my_rendition_draft_v02");
        arguments.insert(QStringLiteral("p_document_parent_node_id"),
                         documentParentNodeId);
    }
    callRpc(QStringLiteral("create"), rpcName, arguments,
            [this](const QVariant &payload) {
        const auto confirmed = firstRow(payload);
        const auto id = confirmed.value("rendition_id", confirmed.value("id")).toString();
        // CREATE confirms identity, not an ACL capability. Read the effective
        // capability before enabling pending local expenses on the new remote root.
        callRpc(QStringLiteral("create"), QStringLiteral("get_rendition_effective_v06"), {{"p_rendition_id", id}},
            [this, confirmed](const QVariant &contextPayload) {
                auto result = confirmed;
                const auto context = firstRow(contextPayload);
                result.insert("can_edit_content", context.value("can_edit_content", false));
                emit renditionCreated(result);
            });
    });
}

void RenditionRepository::editRendition(const QString &renditionId,
                                        qint64 expectedRowVersion,
                                        const QString &periodStart,
                                        const QString &periodEnd,
                                        const QVariantList &projectIds,
                                        const QString &primaryProjectId,
                                        const QString &documentParentNodeId,
                                        qint64 expectedDocumentNodeVersion)
{
    QVariantMap arguments{
        {QStringLiteral("p_rendition_id"), renditionId},
        {QStringLiteral("p_expected_row_version"), expectedRowVersion},
        {QStringLiteral("p_period_start"), periodStart},
        {QStringLiteral("p_period_end"), periodEnd},
        {QStringLiteral("p_project_ids"), uuidArray(projectIds)},
        {QStringLiteral("p_primary_project_id"), primaryProjectId}
    };
    QString rpcName = QStringLiteral("update_my_rendition_draft_v01");
    if (v02Enabled()) {
        if (documentParentNodeId.trimmed().isEmpty()) {
            emit operationFailed(QStringLiteral("edit"),
                                 QStringLiteral("RENDITION_DOCUMENT_LOCATION_REQUIRED"),
                                 QStringLiteral("Selecciona una ubicación .rend."));
            return;
        }
        rpcName = QStringLiteral("update_my_rendition_draft_v02");
        arguments.insert(QStringLiteral("p_document_parent_node_id"),
                         documentParentNodeId);
        arguments.insert(QStringLiteral("p_expected_document_node_version"),
                         nullablePositiveVersion(expectedDocumentNodeVersion));
    }
    callRpc(QStringLiteral("edit"), rpcName, arguments,
            [this](const QVariant &payload) {
        emit renditionEdited(firstRow(payload));
    });
}

bool RenditionRepository::requireV02(const QString &operation)
{
    if (v02Enabled())
        return true;
    const QString code = QStringLiteral("RENDITION_V02_NOT_ACTIVE");
    const QString message = QStringLiteral("El contrato V02 espera backend #74 desplegado y validado.");
    setLastError(message);
    emit operationFailed(operation, code, message);
    return false;
}

void RenditionRepository::getDocumentLocation(const QString &renditionId)
{
    if (!requireV02(QStringLiteral("get_location")))
        return;
    callRpc(QStringLiteral("get_location"),
            QStringLiteral("get_my_rendition_smart_document_location_v01"), {
        {QStringLiteral("p_rendition_id"), renditionId}
    }, [this, renditionId](const QVariant &payload) {
        m_documentLocation = firstRow(payload);
        emit documentLocationLoaded(renditionId, m_documentLocation);
        emit documentLocationChanged();
    });
}

void RenditionRepository::setDocumentLocation(
    const QString &renditionId, const QString &documentParentNodeId,
    qint64 expectedDocumentNodeVersion)
{
    if (!requireV02(QStringLiteral("set_location")))
        return;
    callRpc(QStringLiteral("set_location"),
            QStringLiteral("set_rendition_smart_document_location_v01"), {
        {QStringLiteral("p_rendition_id"), renditionId},
        {QStringLiteral("p_document_parent_node_id"), documentParentNodeId},
        {QStringLiteral("p_expected_document_node_version"),
         nullablePositiveVersion(expectedDocumentNodeVersion)}
    }, [this](const QVariant &payload) {
        const QVariantMap result = firstRow(payload);
        m_documentLocation = result;
        emit documentLocationChanged();
        emit documentLocationSet(result);
    });
}

void RenditionRepository::getProjectWorkspace(const QString &projectId)
{
    if (!requireV02(QStringLiteral("project_workspace")))
        return;
    callRpc(QStringLiteral("project_workspace"),
            QStringLiteral("get_my_project_workspace_v01"), {
        {QStringLiteral("p_project_id"), projectId}
    }, [this](const QVariant &payload) {
        m_documentWorkspace = firstRow(payload);
        emit documentWorkspaceChanged();
    });
}

void RenditionRepository::getDocumentSpace(const QString &spaceId)
{
    if (!requireV02(QStringLiteral("document_space")))
        return;
    callRpc(QStringLiteral("document_space"),
            QStringLiteral("get_my_document_space_v02"), {
        {QStringLiteral("p_space_id"), nullableText(spaceId)}
    }, [this](const QVariant &payload) {
        m_documentSpace = firstRow(payload);
        emit documentSpaceChanged();
    });
}

void RenditionRepository::listDocumentFolders(const QString &spaceId,
                                              const QString &parentNodeId)
{
    if (!requireV02(QStringLiteral("document_folders")))
        return;
    callRpc(QStringLiteral("document_folders"),
            QStringLiteral("list_my_document_explorer_items_v03"), {
        {QStringLiteral("p_space_id"), nullableText(spaceId)},
        {QStringLiteral("p_parent_node_id"), nullableText(parentNodeId)}
    }, [this](const QVariant &payload) {
        QVariantList folders;
        for (const QVariant &value : rows(payload)) {
            const QVariantMap item = value.toMap();
            const QString kind = valueFor(item, QStringLiteral("item_kind"),
                                          QStringLiteral("node_type")).toString().toUpper();
            // Explorer v03 does not return lifecycle or write capabilities.
            // Those are verified separately for the selected node, including leaves.
            if (kind == QLatin1String("FOLDER")) {
                QVariantMap folder = item;
                folder.insert(QStringLiteral("kind"), kind);
                folders.append(folder);
            }
        }
        m_documentFolders = folders;
        emit documentFoldersChanged();
    });
}

void RenditionRepository::getDocumentCapabilities(const QString &spaceId,
                                                  const QString &nodeId)
{
    if (!requireV02(QStringLiteral("document_capabilities")))
        return;
    callRpc(QStringLiteral("document_capabilities"),
            QStringLiteral("get_document_structural_capabilities_v02"), {
        {QStringLiteral("p_space_id"), spaceId},
        {QStringLiteral("p_node_id"), nullableText(nodeId)}
    }, [this](const QVariant &payload) {
        m_documentCapabilities = firstRow(payload);
        emit documentCapabilitiesChanged();
    });
}

void RenditionRepository::listExpenseCatalogs()
{
    callRpc(QStringLiteral("expense_catalogs"),
            QStringLiteral("list_my_rendition_expense_catalogs_v01"), {},
            [this](const QVariant &payload) {
        m_expenseCatalogs = rows(payload);
        emit expenseCatalogsChanged();
    });
}

void RenditionRepository::listExpenses(const QString &renditionId)
{
    callRpc(QStringLiteral("expenses"),
            QStringLiteral("list_my_rendition_expenses_v01"), {
        {QStringLiteral("p_rendition_id"), renditionId}
    }, [this, renditionId](const QVariant &payload) {
        m_expenses = rows(payload);
        emit expensesLoaded(renditionId, m_expenses);
        emit expensesChanged();
    });
}

void RenditionRepository::getExpenseSummary(const QString &renditionId)
{
    callRpc(QStringLiteral("expense_summary"),
            QStringLiteral("get_my_rendition_expense_summary_v01"), {
        {QStringLiteral("p_rendition_id"), renditionId}
    }, [this, renditionId](const QVariant &payload) {
        m_expenseSummary = firstRow(payload);
        emit summaryLoaded(renditionId, m_expenseSummary);
        emit expenseSummaryChanged();
    });
}

QVariantMap RenditionRepository::expenseArguments(const QVariantMap &expense)
{
    const auto nullable = [](const QVariant &value) -> QVariant {
        const QString text = value.toString().trimmed();
        return text.isEmpty() ? QVariant() : QVariant(text);
    };
    const QString amount = valueFor(expense, QStringLiteral("amount"),
                                    QStringLiteral("amount")).toString();
    return {
        {QStringLiteral("p_project_id"), valueFor(expense, QStringLiteral("projectId"), QStringLiteral("project_id"))},
        {QStringLiteral("p_expense_date"), valueFor(expense, QStringLiteral("expenseDate"), QStringLiteral("expense_date"))},
        {QStringLiteral("p_category_code"), valueFor(expense, QStringLiteral("categoryCode"), QStringLiteral("category_code"))},
        {QStringLiteral("p_concept"), valueFor(expense, QStringLiteral("concept"), QStringLiteral("concept"))},
        {QStringLiteral("p_payment_method_code"), valueFor(expense, QStringLiteral("paymentMethodCode"), QStringLiteral("payment_method_code"))},
        {QStringLiteral("p_support_type_code"), valueFor(expense, QStringLiteral("supportTypeCode"), QStringLiteral("support_type_code"))},
        {QStringLiteral("p_currency_code"), valueFor(expense, QStringLiteral("currencyCode"), QStringLiteral("currency_code"))},
        {QStringLiteral("p_amount"), amount.toDouble()},
        {QStringLiteral("p_beneficiary"), nullable(valueFor(expense, QStringLiteral("beneficiary"), QStringLiteral("beneficiary")))},
        {QStringLiteral("p_payment_method_detail"), nullable(valueFor(expense, QStringLiteral("paymentMethodDetail"), QStringLiteral("payment_method_detail")))},
        {QStringLiteral("p_support_number"), nullable(valueFor(expense, QStringLiteral("supportNumber"), QStringLiteral("support_number")))},
        {QStringLiteral("p_support_detail"), nullable(valueFor(expense, QStringLiteral("supportDetail"), QStringLiteral("support_detail")))},
        {QStringLiteral("p_justification"), nullable(valueFor(expense, QStringLiteral("justification"), QStringLiteral("justification")))}
    };
}

void RenditionRepository::addExpense(const QString &requestId,
                                     const QString &renditionId,
                                     qint64 expectedRenditionRowVersion,
                                     const QString &projectId,
                                     const QString &expenseDate,
                                     const QString &categoryCode,
                                     const QString &expenseConcept,
                                     const QString &beneficiary,
                                     const QString &paymentMethodCode,
                                     const QString &paymentMethodDetail,
                                     const QString &supportTypeCode,
                                     const QString &supportNumber,
                                     const QString &supportDetail,
                                     const QString &currencyCode,
                                     const QString &amount,
                                     const QString &justification)
{
    QVariantMap expense{
        {QStringLiteral("projectId"), projectId},
        {QStringLiteral("expenseDate"), expenseDate},
        {QStringLiteral("categoryCode"), categoryCode},
        {QStringLiteral("concept"), expenseConcept},
        {QStringLiteral("beneficiary"), beneficiary},
        {QStringLiteral("paymentMethodCode"), paymentMethodCode},
        {QStringLiteral("paymentMethodDetail"), paymentMethodDetail},
        {QStringLiteral("supportTypeCode"), supportTypeCode},
        {QStringLiteral("supportNumber"), supportNumber},
        {QStringLiteral("supportDetail"), supportDetail},
        {QStringLiteral("currencyCode"), currencyCode},
        {QStringLiteral("amount"), amount},
        {QStringLiteral("justification"), justification}
    };
    QVariantMap arguments = expenseArguments(expense);
    arguments.insert(QStringLiteral("p_request_id"), requestId);
    arguments.insert(QStringLiteral("p_rendition_id"), renditionId);
    arguments.insert(QStringLiteral("p_expected_rendition_row_version"),
                     expectedRenditionRowVersion);
    callRpc(QStringLiteral("expense_create"),
            QStringLiteral("create_my_rendition_expense_v02"), arguments,
            [this](const QVariant &payload) {
        emit expenseAdded(firstRow(payload));
    });
}

void RenditionRepository::updateExpense(const QString &expenseId,
                                        const QString &renditionId,
                                        qint64 expectedExpenseRowVersion,
                                        qint64 expectedRenditionRowVersion,
                                        const QVariantMap &expense)
{
    QVariantMap arguments = expenseArguments(expense);
    arguments.insert(QStringLiteral("p_expense_id"), expenseId);
    arguments.insert(QStringLiteral("p_rendition_id"), renditionId);
    arguments.insert(QStringLiteral("p_expected_expense_row_version"),
                     expectedExpenseRowVersion);
    arguments.insert(QStringLiteral("p_expected_rendition_row_version"),
                     expectedRenditionRowVersion);
    callRpc(QStringLiteral("expense_update"),
            QStringLiteral("update_my_rendition_expense_v01"), arguments,
            [this](const QVariant &payload) {
        emit expenseEdited(firstRow(payload));
    });
}

void RenditionRepository::deleteExpense(const QString &renditionId,
                                        const QString &expenseId,
                                        qint64 expectedExpenseRowVersion,
                                        qint64 expectedRenditionRowVersion)
{
    callRpc(QStringLiteral("expense_delete"),
            QStringLiteral("delete_my_rendition_expense_v01"), {
        {QStringLiteral("p_rendition_id"), renditionId},
        {QStringLiteral("p_expense_id"), expenseId},
        {QStringLiteral("p_expected_expense_row_version"), expectedExpenseRowVersion},
        {QStringLiteral("p_expected_rendition_row_version"), expectedRenditionRowVersion}
    }, [this](const QVariant &payload) {
        emit expenseDeleted(firstRow(payload));
    });
}

void RenditionRepository::listVersions(const QString &renditionId)
{
    callRpc(QStringLiteral("versions"),
            QStringLiteral("list_my_rendition_versions_v01"), {
        {QStringLiteral("p_rendition_id"), renditionId}
    }, [this](const QVariant &payload) {
        m_versions = rows(payload);
        emit versionsChanged();
    });
}

void RenditionRepository::deleteDraft(const QString &renditionId, qint64 expectedRowVersion)
{
    callRpc(QStringLiteral("rendition_delete"), QStringLiteral("delete_my_rendition_draft_v01"),
        {{QStringLiteral("p_rendition_id"), renditionId}, {QStringLiteral("p_expected_row_version"), expectedRowVersion}},
        [this](const QVariant &payload) { emit draftDeleted(firstRow(payload)); });
}

void RenditionRepository::presentRendition(const QString &renditionId,
                                           qint64 expectedRowVersion,
                                           const QString &requestId)
{
    callRpc(QStringLiteral("present"),
            QStringLiteral("present_my_rendition_v02"), {
        {QStringLiteral("p_rendition_id"), renditionId},
        {QStringLiteral("p_expected_row_version"), expectedRowVersion},
        {QStringLiteral("p_request_id"), requestId}
    }, [this, renditionId](const QVariant &payload) {
        emit renditionPresented(firstRow(payload));
        getRendition(renditionId);
        listVersions(renditionId);
        listRenditions();
    });
}

void RenditionRepository::reserveAttachment(
    const QString &renditionId, const QString &expenseId,
    const QString &requestId, const QString &fileName, const QString &mimeType,
    qint64 sizeBytes, const QString &supportTypeCode,
    const QString &documentNumber)
{
    if (sizeBytes <= 0 || sizeBytes > 20LL * 1024LL * 1024LL) {
        emit operationFailed(QStringLiteral("attachment_reserve"),
                             QStringLiteral("RENDITION_ATTACHMENT_SIZE_INVALID"),
                             QStringLiteral("El sustento debe pesar como máximo 20 MiB."));
        return;
    }
    callRpc(QStringLiteral("attachment_reserve"),
            QStringLiteral("reserve_rendition_attachment_v01"), {
        {QStringLiteral("p_rendition_id"), renditionId},
        {QStringLiteral("p_expense_id"), expenseId},
        {QStringLiteral("p_request_id"), requestId},
        {QStringLiteral("p_file_name"), fileName},
        {QStringLiteral("p_mime_type"), mimeType},
        {QStringLiteral("p_size_bytes"), sizeBytes},
        {QStringLiteral("p_support_type_code"), supportTypeCode},
        {QStringLiteral("p_document_number"), nullableText(documentNumber)}
    }, [this](const QVariant &payload) {
        emit attachmentReserved(firstRow(payload));
    });
}

QVariantMap RenditionRepository::localFileMetadata(
    const QString &localFilePath) const
{
    const QString source = localFileName(localFilePath);
    QFile file(source);
    if (!file.open(QIODevice::ReadOnly) || file.size() <= 0)
        return {};

    const QUrl sourceUrl(localFilePath);
    QString fileName = sourceUrl.fileName();
    if (fileName.isEmpty())
        fileName = QFileInfo(source).fileName();
    if (fileName.isEmpty())
        fileName = QStringLiteral("adjunto");

    QMimeDatabase mimeDatabase;
    QMimeType mime = mimeDatabase.mimeTypeForFileNameAndData(fileName, &file);
    if (!mime.isValid())
        mime = mimeDatabase.mimeTypeForFile(fileName, QMimeDatabase::MatchExtension);
    return {
        {QStringLiteral("localUri"), localFilePath},
        {QStringLiteral("fileName"), fileName},
        {QStringLiteral("mimeType"), mime.isValid()
             ? mime.name() : QStringLiteral("application/octet-stream")},
        {QStringLiteral("sizeBytes"), file.size()}
    };
}

void RenditionRepository::uploadReservedAttachment(
    const QString &localFilePath, const QString &bucket,
    const QString &objectPath, const QString &mimeType,
    const QString &attachmentId)
{
    if (!RenditionAttachmentContract::valid(bucket, objectPath, attachmentId)) {
        emit operationFailed(QStringLiteral("attachment_upload"),
                             QStringLiteral("RENDITION_ATTACHMENT_PATH_INVALID"),
                             QStringLiteral("No se envió el sustento: bucket, storage_path o identidad inválidos. Archivo pendiente local."));
        return;
    }
    SupabaseClient *client = supabase();
    AuthSession *session = appContext() ? appContext()->auth() : nullptr;
    QFile file(localFileName(localFilePath));
    if (!client || !session || !session->logged() || session->accessToken().isEmpty()) {
        emit operationFailed(QStringLiteral("attachment_upload"),
                             QStringLiteral("AUTH_REQUIRED"),
                             QStringLiteral("AUTH_REQUIRED"));
        return;
    }
    if (!file.open(QIODevice::ReadOnly) || file.size() <= 0
        || file.size() > 20LL * 1024LL * 1024LL) {
        emit operationFailed(QStringLiteral("attachment_upload"),
                             QStringLiteral("RENDITION_ATTACHMENT_LOCAL_FILE_INVALID"),
                             QStringLiteral("El archivo local ya no está disponible o supera 20 MiB."));
        return;
    }

    const quint64 epoch = m_requestEpoch;
    beginRequest();
    const QPointer<RenditionRepository> guard(this);
    qInfo() << "INGE_DRIVE_ATTACHMENT owner=renditions state=uploading";
    RenditionExportService::shared(client, session)->storage()->uploadReserved(
        localFileName(localFilePath), bucket, objectPath, mimeType,
        [guard, attachmentId, epoch](bool ok, const QString &error, bool retryable) {
        if (!guard || epoch != guard->m_requestEpoch) return;
        guard->endRequest();
        if (!ok) {
            qInfo() << "INGE_DRIVE_ATTACHMENT owner=renditions state=error";
            emit guard->operationFailed(QStringLiteral("attachment_upload"),
                retryable ? QStringLiteral("ATTACHMENT_UPLOAD_NEEDS_RECONCILIATION") : error, error);
            return;
        }
        // The existing domain controller persists FINALIZE, then confirms READY.
        emit guard->attachmentUploaded(attachmentId);
    });
}

void RenditionRepository::finalizeAttachment(const QString &attachmentId)
{
    callRpc(QStringLiteral("attachment_finalize"),
            QStringLiteral("finalize_rendition_attachment_v01"), {
        {QStringLiteral("p_attachment_id"), attachmentId}
    }, [this](const QVariant &payload) {
        emit attachmentFinalized(firstRow(payload));
    });
}

void RenditionRepository::listAttachments(const QString &renditionId)
{
    callRpc(QStringLiteral("attachments"),
            QStringLiteral("list_rendition_attachments_v01"), {
        {QStringLiteral("p_rendition_id"), renditionId}
    }, [this, renditionId](const QVariant &payload) {
        m_attachments = rows(payload);
        emit attachmentsLoaded(renditionId, m_attachments);
        emit attachmentsChanged();
    });
}

void RenditionRepository::getAttachmentAccess(const QString &attachmentId)
{
    callRpc(QStringLiteral("attachment_access"),
            QStringLiteral("get_rendition_attachment_access_v01"), {
        {QStringLiteral("p_attachment_id"), attachmentId}
    }, [this](const QVariant &payload) {
        emit attachmentAccessReady(firstRow(payload));
    });
}

void RenditionRepository::archiveAttachment(const QString &attachmentId,
                                            qint64 expectedRowVersion)
{
    callRpc(QStringLiteral("attachment_archive"),
            QStringLiteral("archive_rendition_attachment_v01"), {
        {QStringLiteral("p_attachment_id"), attachmentId},
        {QStringLiteral("p_expected_row_version"), expectedRowVersion}
    }, [this](const QVariant &payload) {
        emit attachmentArchived(firstRow(payload));
    });
}

void RenditionRepository::accessReceivedAttachment(const QString &requestId, const QString &attachmentId)
{
    const QString operation = QStringLiteral("received/") + requestId;
    callRpc(operation, QStringLiteral("get_rendition_attachment_access_v01"),
            {{QStringLiteral("p_attachment_id"), attachmentId}},
            [this, operation, requestId](const QVariant &payload) {
        const auto access = firstRow(payload);
        const QString bucket = access.value(QStringLiteral("bucket")).toString();
        const QString path = access.value(QStringLiteral("storage_path")).toString();
        if (bucket.isEmpty() || path.isEmpty()) {
            emit operationFailed(operation, QStringLiteral("ATTACHMENT_ACCESS_INVALID"), QStringLiteral("El servidor no devolvió una referencia de acceso."));
            return;
        }
        auto *client = supabase();
        auto *session = appContext() ? appContext()->auth() : nullptr;
        if (!client || !session || !session->logged()) {
            emit operationFailed(operation, QStringLiteral("AUTH_REQUIRED"), QStringLiteral("Inicia sesión para acceder al sustento."));
            return;
        }
        QString url = storageObjectUrl(client, bucket, path);
        url.replace(QStringLiteral("/storage/v1/object/"), QStringLiteral("/storage/v1/object/sign/"));
        const QString base = client->projectUrl();
        QNetworkRequest request = client->makeRequest(QUrl(url), session->accessToken());
        request.setTransferTimeout(30000);
        auto *reply = client->nam()->post(request, QByteArrayLiteral("{\"expiresIn\":60}"));
        const quint64 epoch = m_requestEpoch;
        beginRequest();
        connect(reply, &QNetworkReply::finished, this, [this, reply, operation, requestId, epoch, base]() {
            endRequest();
            const auto raw = reply->readAll();
            const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            const bool ok = reply->error() == QNetworkReply::NoError && status >= 200 && status < 300;
            reply->deleteLater();
            if (epoch != m_requestEpoch) return;
            const auto object = QJsonDocument::fromJson(raw).object();
            const QString relative = object.value(QStringLiteral("signedURL")).toString();
            if (!ok || !relative.startsWith(QLatin1String("/object/sign/"))) {
                emit operationFailed(operation, QStringLiteral("ATTACHMENT_ACCESS_DENIED"), QStringLiteral("No se pudo autorizar el acceso privado al sustento."));
                return;
            }
            emit receivedResult(requestId, QStringLiteral("receivedAttachment"),
                QVariantMap{{QStringLiteral("signedUrl"), base + QStringLiteral("/storage/v1") + relative}});
        });
    });
}

void RenditionRepository::receivedCommand(const QString &requestId,
                                          const QString &operation,
                                          const QVariantMap &arguments)
{
    QString rpc;
    QVariantMap params;
    RenditionAdminRpc::call(operation, arguments, &rpc, &params);
    const QString correlation = QStringLiteral("received/") + requestId;
    if (rpc.isEmpty()) {
        emit operationFailed(correlation, QStringLiteral("UNKNOWN_COMMAND"), QStringLiteral("Contrato administrativo no disponible."));
        return;
    }
    callRpc(correlation, rpc, params, [this, requestId, operation](const QVariant &payload) {
        if (operation != "receivedQuery") { emit receivedResult(requestId, operation, payload); return; }
        auto row = firstRow(payload);
        const auto renditionId = row.value("rendition_id");
        const auto versionId = row.value("rendition_version_id");
        if (renditionId.toString().isEmpty() || versionId.toString().isEmpty()) {
            emit operationFailed("received/" + requestId, "SNAPSHOT_REQUIRED", "Versión confirmada requerida."); return;
        }
        // Supplements are fetched for this immutable version, never the current draft.
        callRpc("received/" + requestId, "get_rendition_funding_v01", {{"p_rendition_id",renditionId},{"p_version_id",versionId}},
            [this, requestId, operation, row, renditionId, versionId](const QVariant &fund) mutable {
                row.insert("funding", firstRow(fund));
                callRpc("received/" + requestId, "get_rendition_exchange_rate_v02", {{"p_rendition_id",renditionId},{"p_version_id",versionId}},
                    [this, requestId, operation, row, versionId](const QVariant &rate) mutable {
                        row.insert("exchangeRate", firstRow(rate)); row.insert("financialVersionId", versionId);
                        emit receivedResult(requestId, operation, row);
                    });
            });
    });
}


SupabaseClient *RenditionRepository::supabase() const
{
    return appContext() ? appContext()->supabase() : nullptr;
}

void RenditionRepository::callRpc(const QString &operation,
                                  const QString &rpcName,
                                  const QVariantMap &arguments,
                                  SuccessHandler onSuccess)
{
    SupabaseClient *client = supabase();
    AuthSession *session = appContext() ? appContext()->auth() : nullptr;
    if (!client || !session || !session->logged() || session->accessToken().isEmpty()) {
        const QString message = QStringLiteral("AUTH_REQUIRED");
        setLastError(message);
        emit operationFailed(operation, message, message);
        return;
    }

    QNetworkRequest request = client->makeRequest(
        client->restUrl(QStringLiteral("rpc/") + rpcName),
        session->accessToken());
    request.setRawHeader("Prefer", "return=representation");
    request.setRawHeader("x-ingeplus-platform", "ANDROID");
    request.setRawHeader("X-Client-Info", "InGePlus-Android/1.0");

    const QByteArray body = QJsonDocument::fromVariant(arguments).toJson(
        QJsonDocument::Compact);
    QNetworkReply *reply = client->nam()->post(request, body);
    QTimer::singleShot(30000, reply, [reply]() {
        if (!reply->isFinished()) reply->abort();
    });
    const quint64 requestEpoch = m_requestEpoch;
    beginRequest();
    setLastError({});

    connect(reply, &QNetworkReply::finished, this,
            [this, reply = QPointer<QNetworkReply>(reply), operation, requestEpoch,
             onSuccess = std::move(onSuccess)]() mutable {
        endRequest();
        if (!reply)
            return;

        const int status = reply->attribute(
            QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const QByteArray raw = reply->readAll();
        const QNetworkReply::NetworkError networkError = reply->error();
        const QString networkMessage = reply->errorString();
        reply->deleteLater();

        if (requestEpoch != m_requestEpoch)
            return;

        QJsonParseError parseError;
        const QJsonDocument document = QJsonDocument::fromJson(raw, &parseError);
        if (networkError != QNetworkReply::NoError || status < 200 || status >= 300) {
            const QJsonObject errorObject = document.isObject()
                ? document.object() : QJsonObject{};
            const QString fallback = networkError == QNetworkReply::NoError
                ? QStringLiteral("HTTP_%1").arg(status) : networkMessage;
            const QString code = status == 401 ? QStringLiteral("AUTH_REQUIRED")
                : (status >= 400 && status < 500
                    ? responseErrorCode(errorObject)
                    : QStringLiteral("NETWORK_AMBIGUOUS"));
            const QString message = responseErrorMessage(errorObject, fallback);
            setLastError(message);
            emit operationFailed(operation, code, message);
            return;
        }

        if (parseError.error != QJsonParseError::NoError) {
            const QString message = QStringLiteral("RENDITION_INVALID_RESPONSE");
            setLastError(message);
            emit operationFailed(operation, message, message);
            return;
        }

        if (onSuccess)
            onSuccess(document.toVariant());
        if (operation != QLatin1String("list")) emit operationSucceeded(operation);
    });
}

void RenditionRepository::setLastError(const QString &message)
{
    if (m_lastError == message)
        return;
    m_lastError = message;
    emit lastErrorChanged();
}

void RenditionRepository::beginRequest()
{
    const bool wasBusy = busy();
    ++m_pendingRequests;
    if (wasBusy != busy())
        emit busyChanged();
}

void RenditionRepository::endRequest()
{
    const bool wasBusy = busy();
    if (m_pendingRequests > 0)
        --m_pendingRequests;
    if (wasBusy != busy())
        emit busyChanged();
}

QVariantList RenditionRepository::rows(const QVariant &payload)
{
    if (payload.metaType().id() == QMetaType::QVariantList)
        return payload.toList();
    if (payload.metaType().id() == QMetaType::QVariantMap)
        return {payload};
    return {};
}

QVariantMap RenditionRepository::firstRow(const QVariant &payload)
{
    const QVariantList resultRows = rows(payload);
    return resultRows.isEmpty() ? QVariantMap{} : resultRows.constFirst().toMap();
}

QVariant RenditionRepository::nullableText(const QString &value)
{
    return value.trimmed().isEmpty() ? QVariant() : QVariant(value.trimmed());
}

QVariant RenditionRepository::nullablePositiveVersion(qint64 value)
{
    return value > 0 ? QVariant::fromValue(value) : QVariant();
}

QVariantList RenditionRepository::uuidArray(const QVariantList &values)
{
    QVariantList result;
    result.reserve(values.size());
    for (const QVariant &value : values)
        result.append(value.toString());
    return result;
}
