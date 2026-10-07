#include "nothingfileops.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QFile>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <private/qzipwriter_p.h>
#include <cstdio>
#include <cstdlib>
static void check(bool ok,const char *name) { if(!ok) { std::fprintf(stderr,"FAIL %s\n",name); std::exit(1); } std::printf("PASS %s\n",name); }
int main(int argc,char **argv) {
    std::setbuf(stdout,nullptr);
    QCoreApplication app(argc,argv); QTemporaryDir fixture;
    const auto root=fixture.path(),a=root+"/report.txt";
    auto op=[&](const QString &name,const QStringList &paths=QStringList(),const QString &arg=QString()) { return NothingFiles::operate(root,root,name,paths,arg); };
    auto ok=[](const QVariantMap &r){return r.value("error").toString().isEmpty();};
    check(ok(op("createFile",{},"report.txt")),"create real file");
    QFile f(a); check(f.open(QIODevice::WriteOnly),"write fixture"); f.write("account data"); f.close();
    check(!ok(op("createFile",{},"report.txt")),"create collision rejected");
    check(!ok(op("rename",{a},"../outside")),"rename traversal rejected");
    auto trashed=op("trash",{a}); check(ok(trashed) && !QFile::exists(a),"trash real file");
    auto payload=trashed["path"].toString();
    check(ok(op("restore",{payload})) && QFile::exists(a),"restore original path");
    check(!ok(op("remove",{a})) && QFile::exists(a),"permanent delete outside trash rejected");
    auto zip=op("compress",{a}); check(ok(zip) && QFile::exists(root+"/report.zip"),"compress ZIP");
    check(ok(op("extract",{root+"/report.zip"})),"extract ZIP");
    QFile extracted(root+"/report/report.txt"); check(extracted.open(QIODevice::ReadOnly) && extracted.readAll()=="account data","ZIP round trip content");
    check(!ok(op("extract",{root+"/report.zip"})),"extract collision rejected");
    { QZipWriter bad(root+"/bad.zip"); bad.addFile("../escape.txt",QByteArray("bad")); bad.close(); }
    check(!ok(op("extract",{root+"/bad.zip"})) && !QFile::exists(root+"/escape.txt"),"ZIP traversal rejected before writing");
    check(!NothingFiles::inside(root,root+"/../"),"account boundary enforced");
    auto listing=NothingFiles::scan(root,root,"files",{}); check(ok(listing) && listing["rows"].toList().size()>=3,"real directory model");
    return 0;
}
