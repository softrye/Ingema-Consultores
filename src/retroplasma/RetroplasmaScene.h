#pragma once
#include "RetroplasmaGeometryDecoder.h"
#include <QImage>
#include <QString>
#include <memory>
#include <mutex>
#include <vector>
namespace inge::rp {
struct Lod {double geometricError=0;QString meshPath,texturePath;};
struct Node {QString id;int parent=-1;Bounds bounds;std::vector<int> children;std::vector<Lod> lods;};
struct Scene {QString title,source,license,basePath;GeoPoint origin;Bounds bounds;std::vector<Node> nodes;std::vector<int> roots;};
struct LoadedTile {Geometry geometry;QImage texture;std::size_t bytes=0;};
struct RenderTile {QString key;std::shared_ptr<const LoadedTile> tile;};
struct RenderMetrics {std::uint64_t frames=0;double cpuRecordMs=0;std::size_t gpuBytes=0;int meshes=0,triangles=0,textures=0;QString error,backend;};
struct MetricsMailbox {std::mutex mutex;RenderMetrics value;};
}
