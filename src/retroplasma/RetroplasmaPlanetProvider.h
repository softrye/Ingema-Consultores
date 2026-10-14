#pragma once
#include "RetroplasmaDataProvider.h"
#include <QMutex>
namespace inge::rp {
// Extends the existing provider seam; the native renderer is unchanged.
class PlanetSceneProvider final : public RetroplasmaDataProvider {
public:
    std::shared_ptr<const Scene> readScene(const QUrl &,QString &,const std::atomic_bool &)const override;
    std::shared_ptr<const LoadedTile> readTile(const Lod &,QString &,const std::atomic_bool &)const override;
    static QUrl imageryUrl(const Lod &);
    static Geometry geometryFor(const Lod &);
private:
    LocalSceneProvider m_local;
    mutable QMutex m_imageMutex;
    mutable QMutex m_networkMutex;
    mutable QImage m_overview;
    QImage overview(QString &error)const;
};
}
