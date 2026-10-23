#import "MemoryProbe.h"

#include <cerrno>
#include <cstdint>
#include <cstring>
#include <sys/mman.h>

static NSDictionary* ProbeMapping(std::uintptr_t address, std::size_t size)
{
    void* requested = reinterpret_cast<void*>(address);
    errno = 0;
    void* mapped = mmap(requested, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    int error = errno;
    BOOL exact = mapped == requested;
    BOOL roundTrip = NO;
    if (exact) {
        auto* bytes = static_cast<volatile unsigned char*>(mapped);
        bytes[0] = 0x53;
        bytes[size - 1] = 0x4d;
        std::uint32_t gameAddress = static_cast<std::uint32_t>(address);
        std::uintptr_t rebased = gameAddress | ((gameAddress & 0x80000000u) ? 0x10000000000ull : 0x100000000ull);
        roundTrip = rebased == address && bytes[0] == 0x53 && bytes[size - 1] == 0x4d;
    }
    NSString* returnedAddress = mapped == MAP_FAILED ? @"MAP_FAILED"
        : [NSString stringWithFormat:@"0x%llx", (unsigned long long)reinterpret_cast<std::uintptr_t>(mapped)];
    if (mapped != MAP_FAILED) munmap(mapped, size);
    return @{
        @"requested": [NSString stringWithFormat:@"0x%llx", (unsigned long long)address],
        @"returned": returnedAddress,
        @"bytes": @(size),
        @"exact": @(exact),
        @"pointerRoundTrip": @(roundTrip),
        @"error": mapped == MAP_FAILED ? [NSString stringWithUTF8String:std::strerror(error)] : @""
    };
}

NSDictionary<NSString*, id>* SMSRunMemoryProbe(void)
{
    NSDictionary* low = ProbeMapping(0x110000000ull, 8u << 20);
    NSDictionary* mem1 = ProbeMapping(0x10080000000ull, 64u << 20);
    return @{
        @"schemaVersion": @1,
        @"system": NSProcessInfo.processInfo.operatingSystemVersionString,
#if TARGET_OS_SIMULATOR
        @"simulator": @YES,
#else
        @"simulator": @NO,
#endif
        @"lowStackSample": low,
        @"mem1": mem1,
        @"note": @"Non-destructive mapping hints only. A low-stack sample failure does not exhaust the address window. Success is not proof the complete engine works."
    };
}
