#include "RetroplasmaGeoDocument.h"
#include "RetroplasmaCamera.h"
#include "RetroplasmaPlanet.h"
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QFile>
#include <iostream>
#include <stdexcept>
using namespace inge::rp;
void require(bool b,const char *s){std::cerr<<(b?"OK ":"FAIL ")<<s<<'\n';if(!b)throw std::runtime_error(s);}
int main(int argc,char **argv){
 QCoreApplication app(argc,argv);QString error;GeoDocument doc;
 QByteArray kml=R"(<kml xmlns="http://www.opengis.net/kml/2.2"><Document><Placemark><name>Lima</name><MultiGeometry><Point><coordinates>-77.0428,-12.0464,153</coordinates></Point><LineString><coordinates>-77,-12,0 -76.9,-12.1,0</coordinates></LineString><Polygon><outerBoundaryIs><LinearRing><coordinates>-77,-12 -76.9,-12 -76.9,-12.1 -77,-12.1 -77,-12</coordinates></LinearRing></outerBoundaryIs></Polygon></MultiGeometry></Placemark></Document></kml>)";
 require(parseKml(kml,doc,error)&&doc.features.size()==3,"point line polygon MultiGeometry import");
 require(doc.features[0].points[0].longitude==-77.0428,"KML longitude latitude axis order");
 require(doc.features[0].name=="Lima","placemark name preserved");
 for(auto &f:doc.features){auto tile=geoFeatureTile(f,100);require(tile&&!tile->geometry.indices.empty(),"KML uploaded as native ellipsoid geometry");}
 GeoDocument again;require(parseKml(writeKml(doc),again,error)&&again.features.size()==3,"KML round trip preserves all geometry");
 QTemporaryDir dir;auto path=dir.path()+"/earth.kmz";
 require(saveGeoDocument(path,doc,error)&&readGeoDocument(path,again,error),"KMZ doc.kml round trip without extraction");
 require(!parseKml("<!DOCTYPE kml [<!ENTITY x 'bad'>]><kml>&x;</kml>",again,error),"reject DTD/entity declarations");
 require(!parseKml("<kml><Placemark><Point><coordinates>181,91</coordinates></Point></Placemark></kml>",again,error),"reject invalid coordinate rather than misplacing data");
 require(!parseKml("<kml><Placemark>",again,error),"reject truncated XML");
 QByteArray hole=R"(<kml><Placemark><Polygon><outerBoundaryIs><LinearRing><coordinates>-77,-12 -76.9,-12 -76.9,-12.1 -77,-12.1 -77,-12</coordinates></LinearRing></outerBoundaryIs><innerBoundaryIs><LinearRing><coordinates>-76.98,-12.02 -76.96,-12.02 -76.96,-12.04 -76.98,-12.02</coordinates></LinearRing></innerBoundaryIs></Polygon></Placemark></kml>)";
 require(parseKml(hole,again,error)&&again.features[0].holes.size()==1&&!again.warnings.isEmpty(),"polygon holes retained and unsupported fill explicitly reported");
 require(!parseKml("<kml><Placemark><Polygon><outerBoundaryIs><LinearRing><coordinates>0,0 1,0 1,1 0,1</coordinates></LinearRing></outerBoundaryIs></Polygon></Placemark></kml>",again,error),"unclosed polygon rejected");
 require(parseKml("<kml><NetworkLink/><Placemark><Point><coordinates>0,0</coordinates></Point></Placemark></kml>",again,error)&&!again.warnings.isEmpty(),"unsupported NetworkLink reported without fetching external content");
 require(surfaceDistance({0,179,0},{0,-179,0})>222000&&surfaceDistance({0,179,0},{0,-179,0})<223000,"distance crosses antimeridian via short arc");
 Camera c;c.resetPlanet(true);c.goToGeographic({-12,-77,0},2000);for(int i=0;i<200;++i)c.step(.016);GeoPoint hit;
 require(pickPlanet(c.viewProjection(1),c.eye(),0,0,hit)&&std::abs(hit.latitude+12)<.001&&std::abs(hit.longitude+77)<.001,"center screen picks real WGS84 location");
 GeoFeature marker;marker.kind="Point";marker.points={{-12,-76.991,0}};auto rendered=geoFeatureTile(marker,10);auto &v=rendered->geometry.vertices[0];auto vp=c.viewProjection(1);
 auto project=[&](Vec3 p){double w=vp.at(3,0)*p.x+vp.at(3,1)*p.y+vp.at(3,2)*p.z+vp.at(3,3);return (vp.at(0,0)*p.x+vp.at(0,1)*p.y+vp.at(0,2)*p.z+vp.at(0,3))/w;};
 require(std::abs(project({v.position[0],v.position[1],v.position[2]})-project(ecefToPlanet(geodeticToEcef({-12,-76.991,71}))))*600<1,"marker and imagery remain registered below one pixel at 2km camera altitude");
 for(auto &f:doc.features){auto tile=geoFeatureTile(f,100);require(tile->geometry.vertices.size()<=geoFeatureVertexCost(f),"geometry admission cost bounds actual tessellation");}
 c.resetPlanet(true);require(!pickPlanet(c.viewProjection(1),c.eye(),.99,.99,hit),"space pixel is not a ground position");
 c.framePlanet(.46,true);require(!pickPlanet(c.viewProjection(.46),c.eye(),.95,0,hit),"whole planet fits portrait viewport");
 std::cout<<"GEODOCUMENT PASS: KML, KMZ, native geometry, coordinate rejection, geodesic distance and WGS84 picking\n";
}
