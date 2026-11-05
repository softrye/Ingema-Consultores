#pragma once
#include "RetroplasmaDataProvider.h"
#include "RetroplasmaRocktree.h"

namespace inge::rp {
class RocktreeSceneProvider final : public RetroplasmaDataProvider {
public:
    std::shared_ptr<const Scene> readScene(const QUrl &,QString &,const std::atomic_bool &)const override;
    std::shared_ptr<const LoadedTile> readTile(const Lod &,QString &,const std::atomic_bool &)const override;
};
}
