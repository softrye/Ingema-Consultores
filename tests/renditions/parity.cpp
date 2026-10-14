// Paridad nativa con los vectores compartidos Web/Android (tests/renditions/vectors,
// copia de packages/test-vectors de E1PT04m0/ingeplus) y verificación del
// interruptor de IA de Rendiciones. Fixtures sintéticos: no prueban Supabase real.
#include <QCoreApplication>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>
#include "src/cpp/renditionvalidation.h"
#include "src/cpp/renditioncontract.h"
#include "src/cpp/renditionfeatures.h"
#include "src/cpp/renditionassistantport.h"
#include "tests/renditions/vectors/policy.h"

static void verify(bool condition, const QString &name) { if (!condition) qFatal("Shared parity failed: %s", qPrintable(name)); }
static QJsonObject fixture(const QString &path) { QFile f(path); verify(f.open(QIODevice::ReadOnly), path); QJsonParseError e; auto d=QJsonDocument::fromJson(f.readAll(), &e); verify(e.error==QJsonParseError::NoError, path); return d.object(); }
int main(int argc, char **argv) {
  QCoreApplication app(argc, argv);
  verify(argc == 2, "vector directory required");
  const QString dir = QString::fromLocal8Bit(argv[1]);
  const auto cases=fixture(dir+"/renditions-calculation.json")["cases"].toArray();
  int checks=0;
  for (const auto &entry : cases) {
    const auto c=entry.toObject(); const auto id=c["id"].toString(); const auto expected=c["expected"].toObject();
    if (c.contains("expenses") && expected.contains("pen")) {
      QVariantList rows;
      for (const auto &value : c["expenses"].toArray()) {
        const auto e=value.toObject();
        rows.append(QVariantMap{{"amount",e["amount"].toString()},{"currencyCode",e["currency"].toString()},{"reviewStatus",e["reviewStatus"].toString()},{"archived",e["archived"].toBool()}});
      }
      QVariantMap draft{{"expenses",rows}}; RenditionValidation::totals(draft);
      verify(draft["totalPen"].toDouble()==expected["pen"].toString().toDouble(),id+" PEN");
      verify(draft["totalUsd"].toDouble()==expected["usd"].toString().toDouble(),id+" USD");
      verify(draft["expenseCount"].toInt()==expected["count"].toInt(),id+" count");
      verify(draft["pendingCount"].toInt()==expected["pending"].toInt(),id+" pending"); checks+=4;
    }
    if (id=="CALC-04") {
      QVariantMap draft{{"periodStart","2026-10-01"},{"periodEnd","2026-10-31"},{"projectIds",QVariantList{"synthetic-project"}}};
      for (const auto &value:c["invalid"].toArray()) {
        const auto e=value.toObject();
        QVariantMap row{{"expenseDate","2026-10-09"},{"projectId","synthetic-project"},{"amount",e["amount"].toString()},{"currencyCode",e["currency"].toString()},{"concept","Alimentacion de campo"},{"categoryCode","FOOD"},{"paymentMethodCode","CASH"},{"supportTypeCode","RECEIPT"}};
        verify(!RenditionValidation::expense(draft,row).isEmpty(),id+" rejects invalid expense"); ++checks;
      }
    }
  }
  verify(QString::fromLatin1(IngeContract::currencies[0])=="PEN", "generated currency policy");
  const auto protocol=fixture(dir+"/protocol.json");
  for (const auto &value:protocol["stateCases"].toArray()) {
    const auto row=value.toObject(); auto input=row.toVariantMap(); input.remove("id");
    verify(RenditionContract::canEditWorkingCopy(input)==!row["androidReadOnly"].toBool(),row["id"].toString()); ++checks;
  }
  const auto money=fixture(dir+"/money.json");
  for (const auto &value:money["cases"].toArray()) {
    const auto row=value.toObject(); const auto parsed=RenditionMoney::cents(row["input"].toString());
    verify(row["error"].toBool() ? !parsed.has_value() : parsed && *parsed==row["cents"].toInteger(), "decimal numeric parity "+row["input"].toString()); ++checks;
  }
  for (const auto &value:money["fundCases"].toArray()) {
    const auto row=value.toObject();
    const auto result=RenditionMoney::commonFund(*RenditionMoney::cents(row["fundPen"].toString()), *RenditionMoney::cents(row["fundUsd"].toString()), *RenditionMoney::cents(row["spentPen"].toString()), *RenditionMoney::cents(row["spentUsd"].toString()), row["rate"].isNull() ? std::nullopt : RenditionMoney::scaled(row["rate"].toString(), 6));
    verify(row["balancePenCents"].isNull() ? !result.pen : result.pen && *result.pen==row["balancePenCents"].toInteger(), "common fund PEN");
    verify(row["balanceUsdCents"].isNull() ? !result.usd : result.usd && *result.usd==row["balanceUsdCents"].toInteger(), "common fund USD"); checks+=2;
  }

  // IA de Rendiciones: apagada por defecto y el puerto de InGe IA no deja pasar nada.
  verify(!RenditionFeatures::aiEnabled, "AI disabled by default");
  RenditionAssistantRequest read{"req-1","refresh",{},false};
  verify(RenditionAssistantPolicy::rejection(read)=="AI_DISABLED", "port rejects while AI disabled");
  verify(RenditionAssistantPolicy::bridgeCommand(read).isEmpty(), "no bridge command while AI disabled");
  verify(RenditionAssistantPolicy::rejection(read,true).isEmpty(), "future read allowed when enabled");
  RenditionAssistantRequest write{"req-2","saveFinancial",{{"localId","l"}},false};
  verify(RenditionAssistantPolicy::rejection(write,true)=="USER_CONFIRMATION_REQUIRED", "writes need user confirmation");
  write.userConfirmed=true;
  const auto command=QJsonDocument::fromJson(RenditionAssistantPolicy::bridgeCommand(write,true).toUtf8()).object();
  verify(command["requestId"].toString()=="req-2" && command["operation"].toString()=="saveFinancial", "bridge envelope shape");
  verify(RenditionAssistantPolicy::rejection({"req-3","coreAnalyze",{},true},true)=="OPERATION_NOT_ALLOWED", "assistant cannot trigger AI analysis");
  verify(RenditionAssistantPolicy::rejection({"req-4","deleteDraft",{},true},true)=="OPERATION_NOT_ALLOWED", "assistant cannot delete");
  verify(RenditionAssistantPolicy::rejection({"","refresh",{},false},true)=="REQUEST_ID_REQUIRED", "request id required");
  checks+=9;
  qInfo()<<"PASS shared native parity checks:"<<checks<<"; remote E2E NOT attested";
  return 0;
}
