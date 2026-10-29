#pragma once
#include "RetroplasmaScene.h"
#include <QUrl>
#include <atomic>
namespace inge::rp {
// Provider boundary is independent of camera/RHI. LocalSceneProvider stays local-only.
class RetroplasmaDataProvider {
public:
    virtual ~RetroplasmaDataProvider()=default;
    virtual std::shared_ptr<const Scene> readScene(const QUrl &,QString &error,const std::atomic_bool &)const=0;
    virtual std::shared_ptr<const LoadedTile> readTile(const Lod &,QString &error,const std::atomic_bool &)const=0;
};
class LocalSceneProvider final : public RetroplasmaDataProvider {
public:
    std::shared_ptr<const Scene> readScene(const QUrl &,QString &,const std::atomic_bool &)const override;
    std::shared_ptr<const LoadedTile> readTile(const Lod &,QString &,const std::atomic_bool &)const override;
};
}
