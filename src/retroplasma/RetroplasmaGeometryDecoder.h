#pragma once
#include "RetroplasmaMath.h"
#include <atomic>
#include <cstdint>
#include <string>
#include <vector>
namespace inge::rp {
struct Vertex {float position[3]{};float normal[3]{};float uv[2]{};};
static_assert(sizeof(Vertex)==32,"GPU vertex layout");
struct Geometry {std::vector<Vertex> vertices;std::vector<std::uint32_t> indices;Bounds bounds;};
bool decodeObj(const std::string &,Geometry &,std::string &error,const std::atomic_bool *cancel=nullptr);
}
