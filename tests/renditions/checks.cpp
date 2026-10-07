#include "src/cpp/renditionlocalstore.h"
#include "src/cpp/renditionsnapshotexporter.h"
#include "xlsxdocument.h"
#include <QGuiApplication>
#include <QStandardPaths>
#include <QFile>
#include <QJsonDocument>
#include <QDir>
#include <QUuid>
#include <QTemporaryDir>
#include <QFileInfo>
#include <iostream>
#include <cstdlib>
void check(bool value, const char *label) { if (!value) { std::cerr << "FAIL " << label << '\n'; std::exit(1); } }
int main(int argc, char **argv) {
 QGuiApplication app(argc, argv);
 QStandardPaths::setTestModeEnabled(true);
 QCoreApplication::setApplicationName("RenditionNativeChecks");
 const auto scope = QUuid::createUuid().toString();
 RenditionLocalStore store(scope);
 const QString rid="22222222-2222-4222-8222-222222222222", eid="33333333-3333-4333-8333-333333333333", aid="11111111-1111-4111-8111-111111111111";
 auto local=store.createDraft("2026-09-01","2026-09-30",{"p1"},"p1","folder","space",true);
 check(!local.isEmpty(), "persist draft");
 check(!store.presentationBlocker(local).isEmpty(), "invalid presentation blocked");
 check(store.markRenditionSynced(local,{{"rendition_id",rid},{"visible_code","RDC-2026-000007"},{"row_version",1}}), "remote rendition identity");
 QVariantMap expense{{"projectId","p1"},{"expenseDate","2026-09-08"},{"categoryCode","FOOD"},{"currencyCode","PEN"},{"amount","10.00"},{"concept","Lunch"},{"beneficiary","Provider"},{"paymentMethodCode","CASH"},{"supportTypeCode","RECEIPT"}};
 auto child=store.addLocalExpense(local,expense,true); check(!child.isEmpty(),"persist expense");
 check(store.markExpenseSynced(local,child,{{"expense_id",eid},{"row_version",1},{"rendition_row_version",2}}),"remote expense");
 expense.insert("amount","20.00"); check(store.saveLocalExpense(local,child,expense,true),"edit same expense");
 check(store.markExpenseSyncing(local,child),"edit starts durably");
 check(store.markExpenseNeedsReconciliation(local,child,"lost response"),"edit failure retained");
 for (const auto &v : store.outbox()) {
   const auto op=v.toMap();
   if(op.value("operation")=="expense_create" && op.value("childLocalId")==child)
     check(op.value("state")=="SYNCED","failed edit cannot revive confirmed CREATE");
 }
 store.mergeRemoteExpenses(local,{QVariantMap{{"id",eid},{"row_version",1},{"amount","10.00"}}});
 check(store.pendingOperations().size()==1 && store.pendingOperations().first().toMap().value("kind")=="expense_update","uncommitted edit retries original UPDATE only");
 check(store.expensesFor(local).first().toMap().value("amount")=="20.00","pull preserves pending edit");
 check(store.expensesFor(local).size()==1,"no duplicate expense");
 check(store.markExpenseSynced(local,child,{{"expense_id",eid},{"row_version",2},{"rendition_row_version",3}}),"edit sync");
 QTemporaryDir attachmentSources;
 check(attachmentSources.isValid(),"attachment fixture directory");
 const auto retainedSource=attachmentSources.filePath("retained.jpg");
 QFile retainedFile(retainedSource);
 check(retainedFile.open(QIODevice::WriteOnly) && retainedFile.write(QByteArray(100,'a'))==100,"attachment source fixture"); retainedFile.close();
 QVariantMap attachmentInput{{"localUri",retainedSource},{"fileName","retained.jpg"},{"mimeType","image/jpeg"},{"sizeBytes",100},{"supportTypeCode","RECEIPT"}};
 auto attachment=store.addLocalAttachment(local,child,attachmentInput);
 check(!attachment.isEmpty(),"persist attachment");
 check(store.addLocalAttachment(local,child,attachmentInput)==attachment,"same bytes reuse attachment identity");
 const auto retainedMirror=store.attachmentsFor(local,child).first().toMap().value("localUri").toString();
 check(retainedMirror!=retainedSource && QFileInfo(retainedMirror).size()==100,"attachment copied to persistent mirror");
 check(QFile::remove(retainedSource),"discard picker original");
 auto path="renditions/"+rid+"/expenses/"+eid+"/attachments/"+aid;
 check(store.updateAttachmentPhase(local,child,attachment,"UPLOAD",{{"attachment_id",aid},{"bucket","project-files"},{"storage_path",path}}),"reserve mapping");
 check(store.updateAttachmentPhase(local,child,attachment,"NEEDS_RECONCILIATION"),"offline retry state");
 check(!store.pendingOperations().isEmpty(),"retry available");
 check(store.updateAttachmentPhase(local,child,attachment,"READY",{{"attachment_id",aid}}),"finalize");
 RenditionLocalStore reopened(scope);
 check(QFileInfo(reopened.attachmentsFor(local,child).first().toMap().value("localUri").toString()).size()==100,"mirror survives original deletion and store reopen");
 check(QJsonDocument::fromVariant(reopened.rendition(local)).toJson()==QJsonDocument::fromVariant(store.rendition(local)).toJson(),"disk reopen exact serialized state");
 check(reopened.attachmentsFor(local,child).first().toMap().value("objectPath")==path,"path survives disk");
 check(reopened.rendition(local).value("totalPen").toDouble()==20,"persisted total");
 // Use the actual RPC shape: id is the expense, rendition_id is its parent.
 const QString eid2="44444444-4444-4444-8444-444444444444";
 auto remoteExpense = expense;
 remoteExpense.insert("id",eid); remoteExpense.insert("rendition_id",rid); remoteExpense.insert("row_version",2);
 auto secondRemote=remoteExpense; secondRemote.insert("id",eid2); secondRemote.insert("amount","50.00");
 reopened.mergeRemoteExpenses(local,{remoteExpense,secondRemote});
 check(reopened.expensesFor(local).size()==2,"PULL local 1 remote 2 becomes 2");
 reopened.mergeRemoteExpenses(local,{remoteExpense,secondRemote});
 check(reopened.expensesFor(local).size()==2,"repeated PULL does not duplicate");
 check(reopened.expensesFor(local).first().toMap().value("remoteId")==eid,"PULL never adopts parent UUID as expense identity");
 check(reopened.rendition(local).value("totalPen").toDouble()==70,"PULL reconciles totals");
 reopened.mergeRemoteAttachments(local,{QVariantMap{{"id",aid},{"rendition_id",rid},{"expense_id",eid},{"file_name","retained.jpg"},{"row_version",1}}});
 check(reopened.attachmentsFor(local,child).size()==1,"remote READY attachment merged without duplicate");
 check(reopened.attachmentsFor(local,child).first().toMap().value("remoteId")==aid,"attachment UUID is not parent UUID");
 reopened.adoptRemoteSummary(local,{{"total_expenses",2},{"total_declared_pen",70},{"total_declared_usd",0},{"rendition_row_version",3}});
 check(reopened.syncStatus(local).value("syncState")=="SYNCED","SYNCED only after complete reconciliation");
 check(reopened.syncStatus(local,true).value("syncState")!="SYNCED","active request excludes SYNCED");
 auto pendingValues=expense; pendingValues.insert("clientIntentId","stable-intent");
 auto pendingChild=reopened.addLocalExpense(local,pendingValues);
 check(reopened.addLocalExpense(local,pendingValues)==pendingChild,"double submit reuses local intention");
 check(reopened.syncStatus(local).value("syncState")!="SYNCED","outbox excludes SYNCED");
 const auto originalRequest=reopened.expensesFor(local).last().toMap().value("requestId");
 check(reopened.markExpenseSyncing(local,pendingChild),"mark request active");
 RenditionLocalStore interrupted(scope);
 check(interrupted.expensesFor(local).last().toMap().value("requestId")==originalRequest,"request survives process death");
 check(!interrupted.pendingOperations().isEmpty(),"interrupted create replayable");
 check(interrupted.markExpenseSynced(local,pendingChild,{{"expense_id","55555555-5555-4555-8555-555555555555"},{"expense_row_version",1},{"rendition_row_version",4}}),"actual V02 response adopted");
 const auto pendingSource=attachmentSources.filePath("pending.jpg");
 QFile pendingFile(pendingSource);
 check(pendingFile.open(QIODevice::WriteOnly) && pendingFile.write(QByteArray(100,'b'))==100,"pending attachment fixture"); pendingFile.close();
 auto queuedAttachment=interrupted.addLocalAttachment(local,pendingChild,{{"localUri",pendingSource},{"fileName","pending.jpg"},{"mimeType","image/jpeg"},{"sizeBytes",100}});
 check(!queuedAttachment.isEmpty(),"offline attachment staged");
 const auto queued=interrupted.pendingOperations().last().toMap();
 check(queued.value("expenseRemoteId")=="55555555-5555-4555-8555-555555555555","reserve uses confirmed expense UUID");
 const auto attachmentRequest=queued.value("requestId");
 check(interrupted.updateAttachmentPhase(local,pendingChild,queuedAttachment,"NEEDS_RECONCILIATION",{{"syncError","upload interrupted"}}),"attachment retry persisted");
 RenditionLocalStore afterUpload(scope);
 check(afterUpload.pendingOperations().last().toMap().value("requestId")==attachmentRequest,"attachment retry same request across reopen");
 check(afterUpload.expensesFor(local).last().toMap().value("remoteId")=="55555555-5555-4555-8555-555555555555","expense UUID survives reopen");
 check(afterUpload.saveEditorDraft("expense:new",{{"concept","unfinished"},{"amount","1,"}}),"partial editor autosave");
 RenditionLocalStore draftRestored(scope);
 check(draftRestored.editorDrafts().value("expense:new").toMap().value("amount")=="1,","partial editor survives reopen without normalization");
 check(!draftRestored.markRenditionPresented(local,{{"rendition_id",eid},{"status","PRESENTADA"}}),"different UUID presentation rejected");
 check(reopened.markRenditionPresented(local,{{"rendition_id",rid},{"status","PRESENTADA"},{"row_version",4},{"version_number",1},{"version_id","version-1"}}),"present same record");
 check(reopened.rendition(local).value("remoteId")==rid,"same UUID presented");
 check(reopened.addLocalExpense(local,expense).isEmpty(),"presented create blocked");
 check(!reopened.saveLocalExpense(local,child,expense),"presented edit blocked");
 check(reopened.addLocalAttachment(local,child,{{"sizeBytes",1}}).isEmpty(),"presented attachment mutation blocked");
 // Deletion uses the current remote identity and keeps its tombstone on replay.
 const auto deleteScope=QUuid::createUuid().toString();
 RenditionLocalStore deletes(deleteScope);
 const auto dl=deletes.createDraft("2026-09-01","2026-09-30",{"p1"},"p1","folder","space");
 check(deletes.markRenditionSynced(dl,{{"rendition_id",rid},{"row_version",1}}),"delete fixture header");
 const auto dc=deletes.addLocalExpense(dl,expense);
 check(deletes.markExpenseSynced(dl,dc,{{"expense_id",eid},{"expense_row_version",1},{"rendition_row_version",2}}),"delete fixture expense");
 check(deletes.removeLocalExpense(dl,dc),"remote delete queued");
 check(deletes.markExpenseSyncing(dl,dc),"delete starts");
 RenditionLocalStore deleteReopened(deleteScope);
 check(deleteReopened.pendingOperations().size()==1 && deleteReopened.pendingOperations().first().toMap().value("kind")=="expense_delete","interrupted DELETE never becomes UPDATE");
 check(deleteReopened.markExpenseSynced(dl,dc,{{"expense_id",eid},{"expense_row_version",2},{"rendition_row_version",3}}),"delete acknowledged");
 deleteReopened.mergeRemoteExpenses(dl,{remoteExpense});
 check(deleteReopened.expensesFor(dl).isEmpty(),"stale pull cannot resurrect deleted expense");
 check(deleteReopened.removeDraft(dl),"draft tombstone staged");
 check(deleteReopened.pendingOperations().first().toMap().value("kind")=="rendition_delete","draft uses delete RPC");
 QVariantMap header{{"id",rid},{"visible_code","RDC-2026-000007"},{"status","PRESENTADA"},{"period_start","2026-09-01"},{"period_end","2026-09-30"},{"owner_user_id","owner"}};
 QVariantMap snapshot{{"schema_version","RENDITION_SNAPSHOT_V01"},{"rendition",header},{"totals",QVariantMap{{"total_declared_pen",20.0},{"total_declared_usd",0.0}}},{"projects",QVariantList{QVariantMap{{"id","p1"},{"name","Project"},{"is_primary",true}}}},{"expenses",QVariantList{QVariantMap{{"id",eid},{"project_id","p1"},{"expense_date","2026-09-08"},{"amount",20.0},{"currency_code","PEN"},{"concept","Lunch"}}}}};
 QVariantMap version{{"snapshot_payload",snapshot},{"rendition_id",rid},{"visible_code","RDC-2026-000007"},{"version_number",1},{"rendition_version_id","version-1"},{"snapshot_hash",QString(64,'a')},{"owner_name","Owner"}};
 SnapshotExportModel model; QString error;
 check(SnapshotExportModel::fromReceived(version,&model,&error),"immutable export model");
 QDir().mkpath("artifacts");
 check(RenditionSnapshotExporter::write(model,"pdf","artifacts/rendition-v1.pdf",&error),"PDF write");
 QFile pdf("artifacts/rendition-v1.pdf"); check(pdf.open(QIODevice::ReadOnly)&&pdf.read(5)=="%PDF-","valid PDF bytes");
 check(RenditionSnapshotExporter::write(model,"xlsx","artifacts/rendition-v1.xlsx",&error),"XLSX write");
 QXlsx::Document xlsx("artifacts/rendition-v1.xlsx"); check(xlsx.load(),"XLSX readable");
 check(xlsx.selectSheet("Gastos")&&xlsx.read(2,1).toString()==model.code&&xlsx.read(2,13).toDouble()==20,"XLSX snapshot values");
 std::cout<<"PASS persistence, retry, same-ID presentation, immutability, PDF bytes, XLSX contents\n";
}
