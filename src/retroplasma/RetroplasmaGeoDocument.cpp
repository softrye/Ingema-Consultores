#include "RetroplasmaGeoDocument.h"
#include "RetroplasmaPlanet.h"
#include <QXmlStreamReader>
#include <QXmlStreamWriter>
#include <QRegularExpression>
#include <QFile>
#include <QSaveFile>
#include <QFileInfo>
#include <QBuffer>
#include <private/qzipreader_p.h>
#include <private/qzipwriter_p.h>
#include <algorithm>
#include <numeric>
#include <functional>

namespace inge::rp {
namespace {
constexpr qint64 ByteLimit=4*1024*1024;
constexpr int CoordinateLimit=20000,FeatureLimit=500;
int fillDepth(const GeoFeature &f){
    if(f.kind!=QLatin1String("Polygon")||!f.holes.empty()||f.points.size()<4||f.points.size()>400)return -1;
    const double anchor=f.points.front().longitude;double west=anchor,east=anchor,south=90,north=-90;
    for(auto p:f.points){double lon=anchor+std::remainder(p.longitude-anchor,360.0);west=std::min(west,lon);east=std::max(east,lon);south=std::min(south,p.latitude);north=std::max(north,p.latitude);}
    if(east-west>.5||north-south>.5)return -1;
    double diagonal=surfaceDistance({south,west,0},{north,east,0});int depth=std::max(0,int(std::ceil(std::log2(std::max(1.0,diagonal/2500)))));
    return (f.points.size()-2)*3*std::pow(4.0,depth)<=6000?depth:-1;
}
bool coordinates(const QString &text,std::vector<GeoPoint> &points,int &count){
    for(const auto &tuple:text.split(QRegularExpression(QStringLiteral("\\s+")),Qt::SkipEmptyParts)){
        auto values=tuple.split(',');bool a=false,b=false,c=true;
        if(values.size()<2||values.size()>3||++count>CoordinateLimit)return false;
        GeoPoint p;p.longitude=values[0].toDouble(&a);p.latitude=values[1].toDouble(&b);if(values.size()==3)p.altitude=values[2].toDouble(&c);
        if(!a||!b||!c||!std::isfinite(p.latitude)||!std::isfinite(p.longitude)||!std::isfinite(p.altitude)||std::abs(p.latitude)>90||std::abs(p.longitude)>180||std::abs(p.altitude)>100000)return false;
        points.push_back(p);
    }return !points.empty();
}
QColor kmlColor(const QString &s){bool ok=false;auto value=s.trimmed().toUInt(&ok,16);return ok&&s.trimmed().size()==8?QColor(int(value&255),int((value>>8)&255),int((value>>16)&255),int(value>>24)):QColor("#FFCC54");}
void readGeometry(QXmlStreamReader &xml,GeoFeature &f,int &count,QStringList &warnings){
    int depth=1;bool inner=false;QString altitudeMode=QStringLiteral("clampToGround");
    while(depth&&!xml.atEnd()){
        xml.readNext();if(xml.isStartElement()){
            ++depth;
            if(xml.name()==QLatin1String("innerBoundaryIs"))inner=true;
            if(xml.name()==QLatin1String("coordinates")){
                std::vector<GeoPoint> ring;
                if(!coordinates(xml.readElementText(),ring,count)){xml.raiseError(QStringLiteral("Coordenadas inválidas o límite de 20000 posiciones."));return;}--depth;
                if(inner)f.holes.push_back(std::move(ring));else f.points=std::move(ring);
            }else if(xml.name()==QLatin1String("altitudeMode")){altitudeMode=xml.readElementText();--depth;}
        }else if(xml.isEndElement()){if(xml.name()==QLatin1String("innerBoundaryIs"))inner=false;--depth;}
    }
    if(f.points.size()<(f.kind==QLatin1String("Point")?1:f.kind==QLatin1String("LineString")?2:4)){xml.raiseError(QStringLiteral("Geometría incompleta."));return;}
    if(f.kind==QLatin1String("Point")&&f.points.size()!=1){xml.raiseError(QStringLiteral("Point requiere una posición."));return;}
    if(f.kind==QLatin1String("Polygon")){
        auto closed=[](const auto &ring){return ring.size()>=4&&surfaceDistance(ring.front(),ring.back())<.01;};
        if(!closed(f.points)||std::any_of(f.holes.begin(),f.holes.end(),[&](const auto &ring){return !closed(ring);})){xml.raiseError(QStringLiteral("Los anillos del polígono deben estar cerrados."));return;}
        double west=f.points.front().longitude,east=west,south=90,north=-90;const double anchor=west;
        for(auto p:f.points){double lon=anchor+std::remainder(p.longitude-anchor,360.0);west=std::min(west,lon);east=std::max(east,lon);south=std::min(south,p.latitude);north=std::max(north,p.latitude);}
        if(f.holes.empty()&&fillDepth(f)<0)warnings<<QStringLiteral("Polígono grande o complejo: contorno, sin relleno.");
    }
    int segments=0;
    auto estimate=[&](const auto &ring){for(std::size_t i=1;i<ring.size();++i)segments+=std::clamp(int(std::ceil(std::max(std::abs(std::remainder(ring[i].longitude-ring[i-1].longitude,360.0)),std::abs(ring[i].latitude-ring[i-1].latitude))/.02)),1,9000);};
    estimate(f.points);for(auto &h:f.holes)estimate(h);
    if(segments>9000||geoFeatureVertexCost(f)>57000){xml.raiseError(QStringLiteral("Geometría demasiado extensa: simplifica la línea o el polígono antes de importar."));return;}
    if(altitudeMode!=QLatin1String("absolute")){
        for(auto &p:f.points)p.altitude=0;for(auto &ring:f.holes)for(auto &p:ring)p.altitude=0;
        if(altitudeMode!=QLatin1String("clampToGround"))warnings<<QStringLiteral("Sin modelo de elevación: relativeToGround se fija al elipsoide.");
    }
    if(!f.holes.empty())warnings<<QStringLiteral("Polígono con huecos: se representan todos los contornos; relleno omitido.");
}
void placemark(QXmlStreamReader &xml,GeoDocument &doc,int &count){
    QString name,style;QColor color;std::vector<GeoFeature> features;int depth=1;bool visible=true;
    while(depth&&!xml.atEnd()){
        xml.readNext();if(xml.isStartElement()){
            ++depth;auto tag=xml.name();
            if(tag==QLatin1String("name")){name=xml.readElementText().left(256);--depth;}
            else if(tag==QLatin1String("visibility")){visible=xml.readElementText()!=QLatin1String("0");--depth;}
            else if(tag==QLatin1String("styleUrl")){style=xml.readElementText();--depth;}
            else if(tag==QLatin1String("color")){color=kmlColor(xml.readElementText());--depth;}
            else if(tag==QLatin1String("Point")||tag==QLatin1String("LineString")||tag==QLatin1String("Polygon")){
                GeoFeature f;f.kind=tag.toString();readGeometry(xml,f,count,doc.warnings);features.push_back(std::move(f));--depth;
                if(doc.features.size()+features.size()>FeatureLimit){xml.raiseError(QStringLiteral("Límite de 500 geometrías."));return;}
            }else if(tag==QLatin1String("Model")||tag==QLatin1String("Track")) {doc.warnings<<QStringLiteral("Modelos 3D y tracks temporales no admitidos.");xml.skipCurrentElement();--depth;}
        }else if(xml.isEndElement())--depth;
    }
    for(auto &f:features){f.name=name.isEmpty()?f.kind:name;f.style=style;f.visible=visible;if(color.isValid())f.color=color;doc.features.push_back(std::move(f));}
}
void writeCoordinates(QXmlStreamWriter &xml,const std::vector<GeoPoint> &points){
    QStringList tuples;for(auto p:points)tuples<<QStringLiteral("%1,%2,%3").arg(p.longitude,0,'g',15).arg(p.latitude,0,'g',15).arg(p.altitude,0,'g',15);
    xml.writeTextElement(QStringLiteral("coordinates"),tuples.join(' '));
}
// Regional imagery uses a 60..71 m graphic shell. This 72 m overlay
// follows it within a few metres; stored coordinates/altitudes remain unchanged.
Vec3 position(GeoPoint p){p.altitude+=72;return ecefToPlanet(geodeticToEcef(p));}
std::uint32_t vertex(Geometry &g,Vec3 p){auto n=normalized(p);Vertex v;v.position[0]=float(p.x);v.position[1]=float(p.y);v.position[2]=float(p.z);v.normal[0]=float(n.x);v.normal[1]=float(n.y);v.normal[2]=float(n.z);v.uv[0]=v.uv[1]=.5f;g.vertices.push_back(v);return std::uint32_t(g.vertices.size()-1);}
void triangle(Geometry &g,Vec3 a,Vec3 b,Vec3 c){if(dot(cross(b-a,c-a),a)<0)std::swap(b,c);auto i=vertex(g,a);vertex(g,b);vertex(g,c);g.indices.insert(g.indices.end(),{i,i+1,i+2});}
void line(Geometry &g,const std::vector<GeoPoint> &points,double width){
    for(std::size_t i=1;i<points.size()&&g.vertices.size()<58000;++i){
        auto a=points[i-1],b=points[i];double lon=std::remainder(b.longitude-a.longitude,360.0);int steps=std::clamp(int(std::ceil(std::max(std::abs(lon),std::abs(b.latitude-a.latitude))/.02)),1,9000);
        Vec3 previous=position(a);
        for(int j=1;j<=steps&&g.vertices.size()<58000;++j){double t=double(j)/steps;auto next=position({a.latitude+(b.latitude-a.latitude)*t,a.longitude+lon*t,a.altitude+(b.altitude-a.altitude)*t});auto side=normalized(cross(normalized(previous+next),next-previous))*(width/EarthRadius*.5);triangle(g,previous-side,next-side,next+side);triangle(g,previous-side,next+side,previous+side);previous=next;}
    }
}
// Ear clipping in an unwrapped local lon/lat plane. Large global polygons retain outlines only.
void fillPolygon(Geometry &g,const std::vector<GeoPoint> &ring,int depth){
    if(ring.size()<4||ring.size()>400)return;auto points=ring;
    if(surfaceDistance(points.front(),points.back())<.01)points.pop_back();if(points.size()<3)return;
    std::vector<double>x,y;double previous=points[0].longitude;
    for(auto p:points){previous+=std::remainder(p.longitude-previous,360.0);x.push_back(previous);y.push_back(p.latitude);}
    auto span=[](auto &v){auto m=std::minmax_element(v.begin(),v.end());return *m.second-*m.first;};if(span(x)>.5||span(y)>.5)return;
    double area=0;for(std::size_t i=0,j=x.size()-1;i<x.size();j=i++)area+=x[j]*y[i]-x[i]*y[j];
    std::vector<int> ids(points.size());std::iota(ids.begin(),ids.end(),0);if(area<0)std::reverse(ids.begin(),ids.end());
    auto orient=[&](int a,int b,int c){return (x[b]-x[a])*(y[c]-y[a])-(y[b]-y[a])*(x[c]-x[a]);};
    Geometry filled;
    auto midpoint=[](Vec3 a,Vec3 b){auto p=ecefToGeodetic(planetToEcef((a+b)*.5));auto pa=ecefToGeodetic(planetToEcef(a)),pb=ecefToGeodetic(planetToEcef(b));p.altitude=(pa.altitude+pb.altitude)*.5;return ecefToPlanet(geodeticToEcef(p));};
    std::function<void(Vec3,Vec3,Vec3,int)> subdivide=[&](Vec3 a,Vec3 b,Vec3 c,int level){if(!level){triangle(filled,a,b,c);return;}auto ab=midpoint(a,b),bc=midpoint(b,c),ca=midpoint(c,a);subdivide(a,ab,ca,level-1);subdivide(ab,b,bc,level-1);subdivide(ca,bc,c,level-1);subdivide(ab,bc,ca,level-1);};
    while(ids.size()>2){bool found=false;
        for(std::size_t i=0;i<ids.size();++i){int a=ids[(i+ids.size()-1)%ids.size()],b=ids[i],c=ids[(i+1)%ids.size()];if(orient(a,b,c)<=1e-12)continue;bool inside=false;
            for(auto p:ids)if(p!=a&&p!=b&&p!=c&&orient(a,b,p)>=-1e-12&&orient(b,c,p)>=-1e-12&&orient(c,a,p)>=-1e-12){inside=true;break;}
            if(inside)continue;subdivide(position(points[a]),position(points[b]),position(points[c]),depth);ids.erase(ids.begin()+i);found=true;break;
        }if(!found)return;
    }
    // Preserve geometry budget and counterclockwise faces.
    auto offset=std::uint32_t(g.vertices.size());g.vertices.insert(g.vertices.end(),filled.vertices.begin(),filled.vertices.end());for(auto i:filled.indices)g.indices.push_back(offset+i);
}
}
bool parseKml(const QByteArray &bytes,GeoDocument &result,QString &error){
    result={};error.clear();if(bytes.size()>ByteLimit){error=QStringLiteral("KML supera 4 MiB.");return false;}
    QXmlStreamReader xml(bytes);GeoDocument doc;int count=0;QHash<QString,QColor> styles;bool root=false;
    while(!xml.atEnd()){
        xml.readNext();if(xml.isDTD()||xml.isEntityReference()){xml.raiseError(QStringLiteral("DTD y entidades no admitidos."));break;}
        if(!xml.isStartElement())continue;
        auto tag=xml.name();if(!root){root=tag==QLatin1String("kml");if(!root){xml.raiseError(QStringLiteral("Se requiere raíz kml."));break;}}
        if(tag==QLatin1String("Placemark"))placemark(xml,doc,count);
        else if(tag==QLatin1String("Style")){QString id=xml.attributes().value("id").toString();QColor color;int depth=1;while(depth&&!xml.atEnd()){xml.readNext();if(xml.isStartElement()){++depth;if(xml.name()==QLatin1String("color")){color=kmlColor(xml.readElementText());--depth;}}else if(xml.isEndElement())--depth;}if(!id.isEmpty()&&color.isValid())styles.insert("#"+id,color);}
        else if(tag==QLatin1String("NetworkLink")||tag==QLatin1String("GroundOverlay")||tag==QLatin1String("ScreenOverlay")){doc.warnings<<QStringLiteral("NetworkLinks y overlays raster no admitidos.");xml.skipCurrentElement();}
        else if(tag==QLatin1String("name")&&doc.name.isEmpty())doc.name=xml.readElementText().left(256);
    }
    if(xml.hasError()||doc.features.empty()){error=xml.hasError()?xml.errorString():QStringLiteral("Sin puntos, líneas o polígonos compatibles.");return false;}
    for(auto &f:doc.features)if(styles.contains(f.style))f.color=styles.value(f.style);
    doc.warnings.removeDuplicates();result=std::move(doc);return true;
}
QByteArray writeKml(const GeoDocument &doc){
    QByteArray bytes;QXmlStreamWriter xml(&bytes);xml.setAutoFormatting(true);xml.writeStartDocument();xml.writeStartElement("kml");xml.writeDefaultNamespace("http://www.opengis.net/kml/2.2");xml.writeStartElement("Document");xml.writeTextElement("name",doc.name);
    for(const auto &f:doc.features){xml.writeStartElement("Placemark");xml.writeTextElement("name",f.name);xml.writeTextElement("visibility",f.visible?"1":"0");
        xml.writeStartElement("Style");xml.writeStartElement(f.kind==QLatin1String("Polygon")?"PolyStyle":"LineStyle");QString c=QStringLiteral("%1%2%3%4").arg(f.color.alpha(),2,16,QChar('0')).arg(f.color.blue(),2,16,QChar('0')).arg(f.color.green(),2,16,QChar('0')).arg(f.color.red(),2,16,QChar('0'));xml.writeTextElement("color",c);xml.writeEndElement();xml.writeEndElement();
        xml.writeStartElement(f.kind);xml.writeTextElement("altitudeMode","absolute");
        if(f.kind==QLatin1String("Polygon")){auto ring=[&](const char *name,const auto &points){xml.writeStartElement(name);xml.writeStartElement("LinearRing");writeCoordinates(xml,points);xml.writeEndElement();xml.writeEndElement();};ring("outerBoundaryIs",f.points);for(auto &h:f.holes)ring("innerBoundaryIs",h);}else writeCoordinates(xml,f.points);
        xml.writeEndElement();xml.writeEndElement();
    }xml.writeEndElement();xml.writeEndElement();xml.writeEndDocument();return bytes;
}
bool readGeoDocument(const QString &path,GeoDocument &doc,QString &error){
    QFile file(path);if(!file.open(QIODevice::ReadOnly)||file.size()>ByteLimit){error=QStringLiteral("Archivo inaccesible o superior a 4 MiB.");return false;}
    QByteArray bytes,payload=file.read(ByteLimit+1);
    if(payload.size()>ByteLimit){error=QStringLiteral("Archivo superior a 4 MiB.");return false;}
    // Android SAF document IDs need not contain a filename or extension.
    if(payload.startsWith(QByteArray("PK\003\004",4))){
        // SAF providers may deliver a sequential descriptor. ZIP seeks only in bounded memory.
        QBuffer buffer(&payload);buffer.open(QIODevice::ReadOnly);
        QZipReader zip(&buffer);auto entries=zip.fileInfoList();if(entries.size()>256){error=QStringLiteral("KMZ supera 256 entradas.");return false;}
        QString kml;qint64 total=0;
        for(auto &e:entries){total+=e.size;if(e.isSymLink||e.filePath.startsWith('/')||e.filePath.contains('\\')||e.filePath.split('/').contains("..")||e.size>ByteLimit||total>8*1024*1024){error=QStringLiteral("KMZ inseguro o demasiado grande.");return false;}if(e.isFile&&e.filePath.endsWith(".kml",Qt::CaseInsensitive)){if(kml.isEmpty()||e.filePath==QLatin1String("doc.kml"))kml=e.filePath;}}
        if(kml.isEmpty()){error=QStringLiteral("KMZ no contiene KML.");return false;}bytes=zip.fileData(kml);if(zip.status()!=QZipReader::NoError){error=QStringLiteral("KMZ corrupto.");return false;}
    }else bytes=payload;
    if(!parseKml(bytes,doc,error))return false;if(doc.name.isEmpty())doc.name=QFileInfo(path).completeBaseName();return true;
}
bool saveGeoDocument(const QString &path,const GeoDocument &doc,QString &error){
    auto bytes=writeKml(doc);if(bytes.size()>ByteLimit){error=QStringLiteral("Exportación supera 4 MiB.");return false;}
    QSaveFile file(path);file.setDirectWriteFallback(false);if(!file.open(QIODevice::WriteOnly)){error=file.errorString();return false;}
    if(QFileInfo(path).suffix().compare("kmz",Qt::CaseInsensitive)==0){QByteArray archive;QBuffer buffer(&archive);buffer.open(QIODevice::WriteOnly);QZipWriter zip(&buffer);zip.addFile("doc.kml",bytes);zip.close();if(zip.status()!=QZipWriter::NoError){error=QStringLiteral("No se pudo escribir KMZ.");return false;}bytes=archive;}
    if(file.write(bytes)!=bytes.size()){error=file.errorString();return false;}
    if(!file.commit()){error=file.errorString();return false;}return true;
}
std::shared_ptr<const LoadedTile> geoFeatureTile(const GeoFeature &f,double width){
    if(f.points.empty())return {};auto tile=std::make_shared<LoadedTile>();auto &g=tile->geometry;width=std::clamp(width,10.0,30000.0);
    if(f.kind==QLatin1String("Point")){auto p=position(f.points[0]);auto n=normalized(p),east=normalized(cross(std::abs(n.y)>.99?Vec3{1,0,0}:Vec3{0,1,0},n)),north=cross(n,east);double r=width*2/EarthRadius;
        for(int i=0;i<16;++i){double a=2*Pi*i/16,b=2*Pi*(i+1)/16;triangle(g,p,p+(east*std::cos(a)+north*std::sin(a))*r,p+(east*std::cos(b)+north*std::sin(b))*r);}
    }else {int depth=fillDepth(f);if(depth>=0)fillPolygon(g,f.points,depth);line(g,f.points,width);for(const auto &h:f.holes)line(g,h,width);}
    if(g.vertices.empty())return {};Vec3 lo{1e9,1e9,1e9},hi{-1e9,-1e9,-1e9};for(auto &v:g.vertices)for(int a=0;a<3;++a){double *l=a==0?&lo.x:a==1?&lo.y:&lo.z;double *h=a==0?&hi.x:a==1?&hi.y:&hi.z;*l=std::min(*l,double(v.position[a]));*h=std::max(*h,double(v.position[a]));}g.bounds={lo,hi};
    tile->texture=QImage(1,1,QImage::Format_RGBA8888);auto color=f.color;color.setAlpha(255);tile->texture.fill(color);tile->source=QStringLiteral("KML geometry");tile->resolutionMetres=1e9;tile->bytes=g.vertices.size()*sizeof(Vertex)+g.indices.size()*4+4;return tile;
}
bool pickPlanet(const Mat4 &matrix,Vec3 eye,double nx,double ny,GeoPoint &hit,double shellMetres){
    if(!std::isfinite(nx)||!std::isfinite(ny))return false;double a[4][8]{};
    for(int r=0;r<4;++r)for(int c=0;c<4;++c){a[r][c]=matrix.at(r,c);a[r][c+4]=r==c?1:0;}
    for(int c=0;c<4;++c){int pivot=c;for(int r=c+1;r<4;++r)if(std::abs(a[r][c])>std::abs(a[pivot][c]))pivot=r;if(std::abs(a[pivot][c])<1e-15)return false;for(int j=0;j<8;++j)std::swap(a[c][j],a[pivot][j]);double n=a[c][c];for(auto &v:a[c])v/=n;for(int r=0;r<4;++r)if(r!=c){double t=a[r][c];for(int j=0;j<8;++j)a[r][j]-=t*a[c][j];}}
    double p[4]{nx,ny,-1,1},out[4]{};for(int r=0;r<4;++r)for(int c=0;c<4;++c)out[r]+=a[r][c+4]*p[c];if(std::abs(out[3])<1e-15)return false;
    auto d=normalized(Vec3{out[0]/out[3],out[1]/out[3],out[2]/out[3]}-eye);double equator=(EarthRadius+shellMetres)/EarthRadius,pole=(6356752.314245+shellMetres)/EarthRadius;
    auto scaled=[&](Vec3 v){return Vec3{v.x/equator,v.y/pole,v.z/equator};};auto e=scaled(eye),s=scaled(d);double A=dot(s,s),B=2*dot(e,s),C=dot(e,e)-1,disc=B*B-4*A*C;if(disc<0)return false;double t=(-B-std::sqrt(disc))/(2*A);if(t<0)return false;hit=ecefToGeodetic(planetToEcef(eye+d*t));return finite(geodeticToEcef(hit));
}
std::size_t geoFeatureVertexCost(const GeoFeature &f){
    if(f.kind==QLatin1String("Point"))return 48;
    std::size_t segments=0;auto estimate=[&](const auto &ring){for(std::size_t i=1;i<ring.size();++i)segments+=std::clamp(int(std::ceil(std::max(std::abs(std::remainder(ring[i].longitude-ring[i-1].longitude,360.0)),std::abs(ring[i].latitude-ring[i-1].latitude))/.02)),1,9000);};
    estimate(f.points);for(auto &h:f.holes)estimate(h);
    int depth=fillDepth(f);return segments*6+(depth>=0?std::size_t((f.points.size()-2)*3*std::pow(4.0,depth)):0);
}
double surfaceDistance(GeoPoint p,GeoPoint q){
    constexpr double f=1/298.257223563,b=6356752.314245;double U1=std::atan((1-f)*std::tan(p.latitude*Radians)),U2=std::atan((1-f)*std::tan(q.latitude*Radians));double L=std::remainder((q.longitude-p.longitude)*Radians,2*Pi),lambda=L,sigma=0,sinSigma=0,cosSigma=0,cos2Alpha=0,cos2SigmaM=0;
    for(int i=0;i<100;++i){double sl=std::sin(lambda),cl=std::cos(lambda);sinSigma=std::hypot(std::cos(U2)*sl,std::cos(U1)*std::sin(U2)-std::sin(U1)*std::cos(U2)*cl);if(sinSigma<1e-15)return 0;cosSigma=std::sin(U1)*std::sin(U2)+std::cos(U1)*std::cos(U2)*cl;sigma=std::atan2(sinSigma,cosSigma);double sinAlpha=std::cos(U1)*std::cos(U2)*sl/sinSigma;cos2Alpha=1-sinAlpha*sinAlpha;cos2SigmaM=cos2Alpha>1e-15?cosSigma-2*std::sin(U1)*std::sin(U2)/cos2Alpha:0;double C=f/16*cos2Alpha*(4+f*(4-3*cos2Alpha));double previous=lambda;lambda=L+(1-C)*f*sinAlpha*(sigma+C*sinSigma*(cos2SigmaM+C*cosSigma*(-1+2*cos2SigmaM*cos2SigmaM)));
        if(std::abs(lambda-previous)<1e-12){double u2=cos2Alpha*(EarthRadius*EarthRadius-b*b)/(b*b),A=1+u2/16384*(4096+u2*(-768+u2*(320-175*u2))),B=u2/1024*(256+u2*(-128+u2*(74-47*u2)));double delta=B*sinSigma*(cos2SigmaM+B/4*(cosSigma*(-1+2*cos2SigmaM*cos2SigmaM)-B/6*cos2SigmaM*(-3+4*sinSigma*sinSigma)*(-3+4*cos2SigmaM*cos2SigmaM)));return b*A*(sigma-delta);}
    }
    double h=std::pow(std::sin((q.latitude-p.latitude)*Radians*.5),2)+std::cos(p.latitude*Radians)*std::cos(q.latitude*Radians)*std::pow(std::sin(L*.5),2);return 6371008.8*2*std::asin(std::sqrt(std::clamp(h,0.0,1.0)));
}
}
