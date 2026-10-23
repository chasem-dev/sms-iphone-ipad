#include "DiscImage.h"

#include <array>
#include <cstring>
#include <fstream>
#include <stdexcept>
#include <utility>
#include <vector>

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
        || fstOffset < header.size() || fstSize < 12 || fstSize > (64u << 20) || fstOffset + fstSize > size) {
        throw std::runtime_error("Disc executable or filesystem lies outside the image.");
    }
    std::vector<unsigned char> filesystem(fstSize);
    stream.seekg(fstOffset);
    stream.read(reinterpret_cast<char*>(filesystem.data()), filesystem.size());
    if (!stream) throw std::runtime_error("Cannot read disc filesystem.");
    const std::uint64_t entryCount = readBigEndian(filesystem.data() + 8);
    if (!filesystem[0] || readBigEndian(filesystem.data() + 4) != 0
        || !entryCount || entryCount * 12 > fstSize) {
        throw std::runtime_error("Disc filesystem has an invalid root or entry count.");
    }
    const auto* names = filesystem.data() + entryCount * 12;
    const auto namesSize = fstSize - entryCount * 12;
    std::vector<std::pair<std::uint64_t, std::uint64_t>> directories{{0, entryCount}};
    for (std::uint64_t index = 1; index < entryCount; ++index) {
        while (index >= directories.back().second) directories.pop_back();
        const auto* entry = filesystem.data() + index * 12;
        const auto nameOffset = readBigEndian(entry) & 0xffffff;
        if (nameOffset >= namesSize || !std::memchr(names + nameOffset, 0, namesSize - nameOffset)) {
            throw std::runtime_error("Disc filesystem has an invalid filename.");
        }
        const std::uint64_t offset = readBigEndian(entry + 4);
        const std::uint64_t length = readBigEndian(entry + 8);
        if (entry[0] ? offset != directories.back().first || length <= index || length > directories.back().second
                     : offset + length > size) {
            throw std::runtime_error("Disc filesystem has an invalid directory or file range.");
        }
        if (entry[0]) directories.emplace_back(index, length);
    }
    const char* title = reinterpret_cast<const char*>(header.data() + 0x20);
    const auto titleLength = strnlen(title, 0x3e0);
    return {"GMSE01", std::string(title, titleLength), size};
}

}
