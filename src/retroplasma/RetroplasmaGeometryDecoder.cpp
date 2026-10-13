#include "RetroplasmaGeometryDecoder.h"
#include <algorithm>
#include <limits>
#include <locale>
#include <map>
#include <sstream>
#include <tuple>
namespace inge::rp {
bool decodeObj(const std::string &text,Geometry &out,std::string &error,const std::atomic_bool *cancel){
    out={};error.clear();
    auto fail=[&](const char *code){out={};error=code;return false;};
    if(text.size()>32*1024*1024)return fail("OBJ_BYTE_LIMIT");
    std::vector<Vec3> positions,normals;std::vector<std::array<double,2>> uvs;
    std::map<std::tuple<int,int,int>,std::uint32_t> unique;
    std::vector<bool> needsNormal;
    std::istringstream lines(text);lines.imbue(std::locale::classic());std::string line;
    try{
        auto index=[](const std::string &s,int count){std::size_t end=0;int v=std::stoi(s,&end);if(end!=s.size()||v==0)throw std::runtime_error("index");int resolved=v>0?v-1:count+v;if(resolved<0||resolved>=count)throw std::runtime_error("index");return resolved;};
        while(std::getline(lines,line)){
            if(cancel&&cancel->load())return fail("CANCELLED");
            if(line.size()>4096)return fail("OBJ_LINE_LIMIT");
            std::istringstream row(line);row.imbue(std::locale::classic());std::string kind;row>>kind;
            if(kind=="v"||kind=="vn"){
                Vec3 p;if(!(row>>p.x>>p.y>>p.z)||!finite(p)||length(p)>100000)return fail("OBJ_INVALID_POSITION_OR_NORMAL");
                (kind=="v"?positions:normals).push_back(enuToRender(p));
                if(positions.size()>200000||normals.size()>200000)return fail("OBJ_VERTEX_LIMIT");
            }else if(kind=="vt"){
                std::array<double,2> uv;if(!(row>>uv[0]>>uv[1])||!std::isfinite(uv[0])||!std::isfinite(uv[1])||std::abs(uv[0])>1e6||std::abs(uv[1])>1e6)return fail("OBJ_INVALID_UV");
                uvs.push_back(uv);if(uvs.size()>200000)return fail("OBJ_UV_LIMIT");
            }else if(kind=="f"){
                std::vector<std::uint32_t> polygon;std::string part;
                while(row>>part){
                    if(part[0]=='#')break;
                    auto slash=part.find('/'),second=slash==std::string::npos?slash:part.find('/',slash+1);
                    if(slash==std::string::npos)return fail("OBJ_UV_REQUIRED");
                    int pi=index(part.substr(0,slash),int(positions.size()));
                    int ti=index(part.substr(slash+1,second==std::string::npos?second:second-slash-1),int(uvs.size()));
                    int ni=second==std::string::npos||second+1==part.size()?-1:index(part.substr(second+1),int(normals.size()));
                    auto key=std::make_tuple(pi,ti,ni);auto found=unique.find(key);
                    if(found==unique.end()){
                        Vertex v;auto p=positions[pi],n=ni>=0?normalized(normals[ni]):Vec3{};
                        v.position[0]=float(p.x);v.position[1]=float(p.y);v.position[2]=float(p.z);
                        v.normal[0]=float(n.x);v.normal[1]=float(n.y);v.normal[2]=float(n.z);
                        v.uv[0]=float(uvs[ti][0]);v.uv[1]=float(uvs[ti][1]);
                        std::uint32_t number=std::uint32_t(out.vertices.size());unique.emplace(key,number);out.vertices.push_back(v);needsNormal.push_back(ni<0);polygon.push_back(number);
                    }else polygon.push_back(found->second);
                    // Every supported backend accepts UInt16 indices; split larger assets into nodes.
                    if(polygon.size()>128||out.vertices.size()>65535)return fail("OBJ_FACE_OR_VERTEX_LIMIT");
                }
                if(polygon.size()<3)return fail("OBJ_SHORT_FACE");
                for(std::size_t i=1;i+1<polygon.size();++i){out.indices.insert(out.indices.end(),{polygon[0],polygon[i],polygon[i+1]});if(out.indices.size()>600000)return fail("OBJ_INDEX_LIMIT");}
            }
        }
    }catch(const std::exception &){return fail("OBJ_INVALID_INDEX");}
    if(out.indices.empty())return fail("OBJ_EMPTY_MESH");
    auto position=[&](std::uint32_t i){auto &v=out.vertices[i];return Vec3{v.position[0],v.position[1],v.position[2]};};
    for(std::size_t i=0;i<out.indices.size();i+=3){
        Vec3 normal=cross(position(out.indices[i+1])-position(out.indices[i]),position(out.indices[i+2])-position(out.indices[i]));
        for(int j=0;j<3;++j){auto idx=out.indices[i+j];if(needsNormal[idx]){auto &v=out.vertices[idx];v.normal[0]+=float(normal.x);v.normal[1]+=float(normal.y);v.normal[2]+=float(normal.z);}}
    }
    double inf=std::numeric_limits<double>::infinity();out.bounds={{inf,inf,inf},{-inf,-inf,-inf}};
    for(auto &v:out.vertices){
        Vec3 n=normalized({v.normal[0],v.normal[1],v.normal[2]});v.normal[0]=float(n.x);v.normal[1]=float(n.y);v.normal[2]=float(n.z);
        out.bounds.minimum.x=std::min(out.bounds.minimum.x,double(v.position[0]));out.bounds.minimum.y=std::min(out.bounds.minimum.y,double(v.position[1]));out.bounds.minimum.z=std::min(out.bounds.minimum.z,double(v.position[2]));
        out.bounds.maximum.x=std::max(out.bounds.maximum.x,double(v.position[0]));out.bounds.maximum.y=std::max(out.bounds.maximum.y,double(v.position[1]));out.bounds.maximum.z=std::max(out.bounds.maximum.z,double(v.position[2]));
    }
    return true;
}
}
