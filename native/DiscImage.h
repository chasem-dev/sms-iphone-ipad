#pragma once

#include <cstdint>
#include <string>

namespace sms {

struct DiscImage {
    std::string gameID;
    std::string title;
    std::uint64_t size;
};

DiscImage inspectDiscImage(const std::string& path);

}
