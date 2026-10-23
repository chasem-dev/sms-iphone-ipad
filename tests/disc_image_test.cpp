#include "DiscImage.h"

#include <algorithm>
#include <array>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <unistd.h>

static void setBigEndian(std::array<unsigned char, 0x800>& bytes, std::size_t offset, std::uint32_t value)
{
    bytes[offset] = value >> 24;
    bytes[offset + 1] = value >> 16;
    bytes[offset + 2] = value >> 8;
    bytes[offset + 3] = value;
}

int main()
{
    const auto path = std::filesystem::temp_directory_path() / ("sms-disc-test-" + std::to_string(getpid()) + ".gcm");
    std::array<unsigned char, 0x800> bytes{};
    const std::string gameID = "GMSE01";
    std::copy(gameID.begin(), gameID.end(), bytes.begin());
    setBigEndian(bytes, 0x1c, 0xc2339f3d);
    setBigEndian(bytes, 0x420, 0x440);
    setBigEndian(bytes, 0x424, 0x600);
    setBigEndian(bytes, 0x428, 12);
    auto save = [&] {
        std::ofstream output(path, std::ios::binary | std::ios::trunc);
        output.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
    };
    auto rejects = [&] {
        save();
        try {
            sms::inspectDiscImage(path.string());
        } catch (const std::runtime_error&) {
            return;
        }
        throw std::runtime_error("Invalid image was accepted.");
    };
    try {
        save();
        const auto disc = sms::inspectDiscImage(path.string());
        if (disc.gameID != gameID || disc.size != bytes.size()) {
            throw std::runtime_error("Valid image metadata differs.");
        }
        bytes[7] = 1;
        rejects();
        bytes[7] = 0;
        bytes[3] = 'P';
        rejects();
        bytes[3] = 'E';
        setBigEndian(bytes, 0x424, 0xfffffff0);
        rejects();
        setBigEndian(bytes, 0x424, 0x600);
        setBigEndian(bytes, 0x420, 0x7ff);
        rejects();
        setBigEndian(bytes, 0x420, 0x440);
        setBigEndian(bytes, 0x1c, 0);
        rejects();
        std::filesystem::resize_file(path, 4);
        bool truncatedRejected = false;
        try {
            sms::inspectDiscImage(path.string());
        } catch (const std::runtime_error&) {
            truncatedRejected = true;
        }
        if (!truncatedRejected) throw std::runtime_error("Truncated image was accepted.");
        std::filesystem::remove(path);
        bool missingRejected = false;
        try {
            sms::inspectDiscImage(path.string());
        } catch (const std::runtime_error&) {
            missingRejected = true;
        }
        if (!missingRejected) throw std::runtime_error("Missing image was accepted.");
    } catch (const std::exception& error) {
        std::filesystem::remove(path);
        std::cerr << error.what() << '\n';
        return 1;
    }
    std::cout << "Disc header validation passed. Synthetic input only; no game assets used.\n";
}
