#pragma once
#include <string>
#include <vector>
namespace inge::rp {
// Raw BC1 blocks, not CRN. Always expands to RGBA; no S3TC GPU requirement.
bool decodeBc1(const std::vector<unsigned char> &,int width,int height,std::vector<unsigned char> &,std::string &error);
}
