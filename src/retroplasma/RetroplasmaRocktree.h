#pragma once
#include "RetroplasmaScene.h"
#include <QByteArray>
#include <QHash>
#include <QUrl>

namespace inge::rp::rocktree {
// Schema and unpacking algorithms from the user-supplied earth-reverse-engineering
// source. Wire reads are bounded; remote bytes must never reach upstream asserts.
struct NodeInfo {
    QString path;
    Bounds bounds;
    double metresPerTexel=0;
    quint32 epoch=0,bulkEpoch=0,imageryEpoch=0,flags=0;
    int textureFormat=0;
    bool useImageryEpoch=false;
    bool hasData()const{return !(flags&8);}
    bool hasChildren()const{return !(flags&4);}
    bool hasBulk()const{return path.size()%4==0&&hasChildren();}
};
struct Bulk {QString path;quint32 epoch=0;QHash<QString,NodeInfo> nodes;};
bool validPath(const QString &,bool allowEmpty=false);
QUrl bulkUrl(const QString &,quint32 epoch);
QUrl nodeUrl(const NodeInfo &);
bool decodePlanetoid(const QByteArray &,quint32 &epoch,double &radius,QString &error);
bool decodeBulk(const QByteArray &,const QString &path,quint32 epoch,Bulk &,QString &error);
std::shared_ptr<const LoadedTile> decodeNode(const QByteArray &,const NodeInfo &,QString &error,const std::atomic_bool &cancel);
bool decodeCrn(const QByteArray &,int width,int height,QImage &,QString &error);
}
