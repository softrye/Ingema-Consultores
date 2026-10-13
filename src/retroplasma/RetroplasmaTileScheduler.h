#pragma once
#include "RetroplasmaScene.h"
#include <QHash>
#include <QSet>
namespace inge::rp {
struct TileRequest {QString key;int node=0,lod=0;double priority=0;};
struct Schedule {std::vector<TileRequest> requests;std::vector<RenderTile> draw;QSet<QString> wanted;};
class RetroplasmaTileScheduler {
public:
    static Schedule select(const Scene &,const Mat4 &,Vec3 eye,double height,
        const QHash<QString,std::shared_ptr<const LoadedTile>> &resident,const QString &revision);
};
}
