#include "RetroplasmaTextureDecoder.h"
#include <array>
#include <cstdint>
namespace inge::rp {
bool decodeBc1(const std::vector<unsigned char> &bytes,int width,int height,std::vector<unsigned char> &rgba,std::string &error){
    rgba.clear();error.clear();
    if(width<=0||height<=0||width>4096||height>4096){error="BC1_DIMENSION_LIMIT";return false;}
    const int bw=(width+3)/4,bh=(height+3)/4;
    if(bytes.size()!=std::size_t(bw)*bh*8){error="BC1_TRUNCATED_OR_EXTRA_BLOCKS";return false;}
    rgba.resize(std::size_t(width)*height*4);
    auto expand=[](unsigned c){return std::array<unsigned char,4>{static_cast<unsigned char>(((c>>11)&31)*255/31),static_cast<unsigned char>(((c>>5)&63)*255/63),static_cast<unsigned char>((c&31)*255/31),255};};
    for(int by=0;by<bh;++by)for(int bx=0;bx<bw;++bx){
        const auto *p=bytes.data()+(by*bw+bx)*8;unsigned a=p[0]|unsigned(p[1])<<8,b=p[2]|unsigned(p[3])<<8;
        std::array<std::array<unsigned char,4>,4> colors{expand(a),expand(b),{}, {}};
        for(int c=0;c<3;++c){colors[2][c]=static_cast<unsigned char>(a>b?(2*colors[0][c]+colors[1][c])/3:(colors[0][c]+colors[1][c])/2);colors[3][c]=static_cast<unsigned char>(a>b?(colors[0][c]+2*colors[1][c])/3:0);}
        colors[2][3]=255;colors[3][3]=a>b?255:0;
        std::uint32_t mask=p[4]|std::uint32_t(p[5])<<8|std::uint32_t(p[6])<<16|std::uint32_t(p[7])<<24;
        for(int y=0;y<4;++y)for(int x=0;x<4;++x){int ox=bx*4+x,oy=by*4+y;unsigned selector=(mask>>(2*(y*4+x)))&3;if(ox<width&&oy<height)for(int c=0;c<4;++c)rgba[(std::size_t(oy)*width+ox)*4+c]=colors[selector][c];}
    }
    return true;
}
}
