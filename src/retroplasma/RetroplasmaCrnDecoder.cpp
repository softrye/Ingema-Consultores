#include "RetroplasmaRocktree.h"
#include "RetroplasmaTextureDecoder.h"
#include <QtEndian>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <malloc.h>
#ifdef Q_OS_WIN
// The upstream NaCl/Linux path uses malloc_usable_size; MSVC calls it _msize.
static std::size_t malloc_usable_size(void *p){return _msize(p);}
#endif
#include "third_party/crn/crn_decomp.h"

namespace inge::rp::rocktree {
bool decodeCrn(const QByteArray &bytes,int width,int height,QImage &image,QString &error){
    if(bytes.size()<qsizetype(sizeof(crnd::crn_header))||bytes.size()>8*1024*1024||width<1||height<1||width>2048||height>2048){error=QStringLiteral("RP_CRN_SIZE_INVALID");return false;}
    // Upstream CRC validation trusts header lengths. Bound them BEFORE calling it.
    const auto *header=reinterpret_cast<const crnd::crn_header *>(bytes.constData());
    const unsigned headerBytes=header->m_header_size,totalBytes=header->m_data_size,levels=header->m_levels;
    if(headerBytes<sizeof(crnd::crn_header)||headerBytes>unsigned(bytes.size())||totalBytes!=unsigned(bytes.size())
       ||levels<1||levels>12||offsetof(crnd::crn_header,m_level_ofs)+levels*4>headerBytes){error=QStringLiteral("RP_CRN_HEADER_RANGE_INVALID");return false;}
    auto range=[&](unsigned start,unsigned size){return size==0||(start>=headerBytes&&start<=totalBytes&&size<=totalBytes-start);};
    for(const auto *palette:{&header->m_color_endpoints,&header->m_color_selectors,&header->m_alpha_endpoints,&header->m_alpha_selectors})
        if(!range(palette->m_ofs,palette->m_size)){error=QStringLiteral("RP_CRN_PALETTE_RANGE_INVALID");return false;}
    if(!range(header->m_tables_ofs,header->m_tables_size)){error=QStringLiteral("RP_CRN_TABLE_RANGE_INVALID");return false;}
    unsigned previous=headerBytes;
    for(unsigned i=0;i<levels;++i){unsigned offset=qFromBigEndian<quint32>(bytes.constData()+offsetof(crnd::crn_header,m_level_ofs)+i*4);
        if(offset<previous||offset>=totalBytes){error=QStringLiteral("RP_CRN_LEVEL_RANGE_INVALID");return false;}previous=offset;}
    crnd::crn_texture_info info;
    if(!crnd::crnd_validate_file(bytes.constData(),unsigned(bytes.size()),nullptr)
       ||!crnd::crnd_get_texture_info(bytes.constData(),unsigned(bytes.size()),&info)
       ||info.m_width!=unsigned(width)||info.m_height!=unsigned(height)||info.m_faces!=1||info.m_format!=cCRNFmtDXT1){
        error=QStringLiteral("RP_CRN_HEADER_INVALID");return false;
    }
    const auto row=unsigned((width+3)/4)*8, size=row*unsigned((height+3)/4);
    std::vector<unsigned char> bc1(size);void *dest=bc1.data();
    auto context=crnd::crnd_unpack_begin(bytes.constData(),unsigned(bytes.size()));
    if(!context){error=QStringLiteral("RP_CRN_BEGIN_FAILED");return false;}
    const bool ok=crnd::crnd_unpack_level(context,&dest,size,row,0);crnd::crnd_unpack_end(context);
    if(!ok){error=QStringLiteral("RP_CRN_DECODE_FAILED");return false;}
    std::vector<unsigned char> rgba;std::string detail;
    if(!decodeBc1(bc1,width,height,rgba,detail)){error=QString::fromStdString(detail);return false;}
    for(std::size_t i=3;i<rgba.size();i+=4)rgba[i]=255; // Original CRN_DXT1 path is opaque RGB.
    image=QImage(rgba.data(),width,height,QImage::Format_RGBA8888).copy();
    if(image.isNull()){error=QStringLiteral("RP_CRN_IMAGE_ALLOCATION_FAILED");return false;}
    return true;
}
}
