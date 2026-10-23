#include "DiscImage.h"

#include <array>
#include <cstring>
#include <fstream>
#include <stdexcept>

namespace sms {
namespace {

std::uint32_t readBigEndian(const unsigned char* bytes)
{
    return (std::uint32_t(bytes[0]) << 24) | (std::uint32_t(bytes[1]) << 16)
        | (std::uint32_t(bytes[2]) << 8) | std::uint32_t(bytes[3]);
}

}

DiscImage inspectDiscImage(const std::string& path)
{
    std::ifstream stream(path, std::ios::binary | std::ios::ate);
    if (!stream) {
        throw std::runtime_error("Cannot open disc image.");
    }
    const auto end = stream.tellg();
    if (end < std::streamoff(0x440)) {
        throw std::runtime_error("Disc image is truncated.");
    }
    const auto size = static_cast<std::uint64_t>(end);
    stream.seekg(0);
    std::array<unsigned char, 0x440> header{};
    stream.read(reinterpret_cast<char*>(header.data()), header.size());
    if (!stream || readBigEndian(header.data() + 0x1c) != 0xc2339f3d) {
        throw std::runtime_error("Use an uncompressed GameCube ISO or GCM image; CISO/RVZ are not supported yet.");
    }
    if (std::memcmp(header.data(), "GMSE01", 6) != 0 || header[6] != 0 || header[7] != 0) {
        throw std::runtime_error("This build requires North American Sunshine GMSE01, disc 1, revision 0.");
    }
    const std::uint64_t dolOffset = readBigEndian(header.data() + 0x420);
    const std::uint64_t fstOffset = readBigEndian(header.data() + 0x424);
    const std::uint64_t fstSize = readBigEndian(header.data() + 0x428);
    if (dolOffset < header.size() || dolOffset + 0x100 > size
        || fstOffset < header.size() || fstSize < 12 || fstOffset + fstSize > size) {
        throw std::runtime_error("Disc executable or filesystem lies outside the image.");
    }
    const char* title = reinterpret_cast<const char*>(header.data() + 0x20);
    const auto titleLength = strnlen(title, 0x3e0);
    return {"GMSE01", std::string(title, titleLength), size};
}

}
