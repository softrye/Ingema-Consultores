#pragma once
#include "RetroplasmaScene.h"
#include <QColor>
#include <QStringList>
namespace inge::rp {
struct GeoFeature {
    QString name,kind,style;
    std::vector<GeoPoint> points;
    std::vector<std::vector<GeoPoint>> holes;
    QColor color=QColor("#FFCC54");
    bool visible=true;
};
struct GeoDocument {QString name;std::vector<GeoFeature> features;QStringList warnings;};
bool parseKml(const QByteArray &,GeoDocument &,QString &error);
QByteArray writeKml(const GeoDocument &);
bool readGeoDocument(const QString &,GeoDocument &,QString &error);
bool saveGeoDocument(const QString &,const GeoDocument &,QString &error);
std::shared_ptr<const LoadedTile> geoFeatureTile(const GeoFeature &,double widthMetres);
bool pickPlanet(const Mat4 &,Vec3 eye,double nx,double ny,GeoPoint &,double shellMetres=0);
std::size_t geoFeatureVertexCost(const GeoFeature &);
// Vincenty inverse on WGS84; near-antipodal non-convergence uses mean-radius great-circle distance.
double surfaceDistance(GeoPoint,GeoPoint);
}
