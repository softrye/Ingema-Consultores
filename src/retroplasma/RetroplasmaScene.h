#pragma once
#include "RetroplasmaGeometryDecoder.h"
#include "RetroplasmaPlanet.h"
#include <QImage>
#include <QString>
#include <memory>
#include <mutex>
#include <vector>
namespace inge::rp {
namespace rocktree {struct Bulk;}
struct Lod {double geometricError=0;QString meshPath,texturePath;bool planetary=false;GeoSector sector;QString layer,date;int level=0;quint32 epoch=0,imageryEpoch=0;int textureFormat=1;bool useImageryEpoch=false;};
struct Node {QString id;int parent=-1;Bounds bounds;std::vector<int> children;std::vector<Lod> lods;};
struct Scene {QString title,source,license,basePath;GeoPoint origin;Bounds bounds;std::vector<Node> nodes;std::vector<int> roots;bool planetary=false;QString imagery,date;std::shared_ptr<const rocktree::Bulk> rocktreeRoot;};
struct LoadedTile {Geometry geometry;QImage texture;std::size_t bytes=0;QString source;double resolutionMetres=0;int coveragePercent=100;QString acquisitionDate;std::shared_ptr<const rocktree::Bulk> rocktreeBulk;std::vector<std::shared_ptr<const LoadedTile>> parts;};
struct RenderTile {QString key;std::shared_ptr<const LoadedTile> tile;QString ownerKey;};
struct EarthBudget {std::size_t cpuBytes=40*1024*1024,gpuBytes=32*1024*1024;int parallel=1,nodes=32,maxLevel=15;double pixelError=14;};
struct RenderMetrics {std::uint64_t frames=0;double cpuRecordMs=0;std::size_t gpuBytes=0;int meshes=0,triangles=0,textures=0;QString error,backend;};
struct MetricsMailbox {std::mutex mutex;RenderMetrics value;};
}
