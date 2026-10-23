# Engine integration

## Reuse rather than reimplement

The existing Apple Silicon game build is the starting point, not a new decompilation or an emulator.
The checked local PC engine is pinned in `engine.lock.json`.
The app host currently stands alone so packaging, sandboxed import, and device diagnostics can be tested before linking the full engine.

Additional read-only source checkouts are in `.cache/sms-android` and `.cache/sms-switch` on the development machine; they are ignored, not vendored or modified.

| Source | Inspected revision | Reuse |
| --- | --- | --- |
| chasem-dev/sms-pc-port | ef70f022fcba0cbbadc83ed24e375c379874c768 | ARM64 pointer-rebasing pass, game/runtime, GX renderer and MoltenVK backend |
| chasem-dev/sms-android | ac25317f6da9fc3aa80190bc486b1a8babfdcc99 | Separate launcher/native-engine structure, imported game data, controller profiles, touch-control behavior, lifecycle patterns |
| chasem-dev/sms-switch | 8d4872958492e68f2fe58944b68d712cd1943d70 | Target wrapper around sms-port, patches isolated from core, ARM64 threading and render-queue adaptations |

Android pins engine `bb9fd1d0fbd113cbe37e16a37091238026ff25f0` on `feat/android-arm64`.
Its Gradle project builds the engine's CMake target directly and `build.sh` calls the engine's `android/build-native.sh`.
Switch pins `ddeeadae7638263df0dcf9291faab2e3ebb4b792` and wraps the engine with its own CMake target and patches.
These are different engine revisions; review their deltas before selecting the common base for iOS.

## Graphics

In the inspected PC checkout, the path to Metal is the Vulkan/MoltenVK backend in `platform/gx/src/vk`, not a direct MTL implementation of GX.
Retain that renderer first; this app's Metal clear-pass diagnostic is only an iOS host test and is not its replacement.
An iOS-built, bundled or statically linked MoltenVK and iOS SDL integration are required instead of the desktop dylib search and OpenGL fallback.
Keep any shader compilation within supported graphics APIs; the game code itself should remain ahead-of-time native ARM64 code.

## Bring-up order

Simulator progress: the isolated engine target now builds and boots a real airstrip stage through SDL2/static MoltenVK. The overlay separates the macOS LLVM pass from iOS compilation, namespaces volk dispatch globals, omits unavailable desktop runtime APIs, scalarizes simulator sampler arrays, and rebases indexed draws for the simulator's Metal feature set. The game entry runs on a low-window stack and installs UIKit controls. See `GAMEPLAY.md` and `VALIDATION.md`; the hardware and distribution gates below still apply.

1. Run the memory probe on real iPhone and iPad hardware under ordinary development signing.
   The PC engine uses `PORT_GAME_LO = 0x100000000`, `PORT_GAME_HI = 0x10000000000`, and a 64 MiB MEM1 mapping at `0x10080000000`.
   `src/port_include/dolphin/types.h`, `tools/gameptr/GamePtrPass.cpp`, and `platform/port_runtime.cpp` must agree.
   The low sample is at `0x110000000`, not a complete scan of the low allocation window.
   If the high mapping fails on iOS, investigate a compact rebase layout before making any entitlement requirement claims.
2. Split host-tool and target compilation.
   Build the LLVM gameptr plugin for macOS with the same LLVM version as the compiler targeting iOS.
   Do not try to load an iOS-built plugin into the host compiler or blindly use Xcode's clang with a Homebrew LLVM plugin.
   Separate `APPLE`/macOS branches from `CMAKE_SYSTEM_NAME=iOS`, remove target `-m64`, and preserve ARM64 signed-char semantics.
3. Reuse the Android engine's library/bootstrap seam where practical.
   Replace the desktop `main` instead of invoking it from UIKit: no `posix_spawn` ASLR restart, process replacement, or blocking game loop on the UI thread.
   Validate the low-window game stack and OS threads without disrupting UIKit's main run loop.
4. Bring up existing GX through iOS MoltenVK/SDL, then boot the game using the imported disc path.
   Add an explicit game start API and stop/suspend semantics; do not add a fake enabled Play button.
5. Route settings, cards, caches, screenshots, and logs to app-container paths.
   Reuse the Android separation of app-private data and imported images.
   Link audio directly, exclude desktop USB loading, and replace fork/exec symbolication with offline symbolication.
6. Wire GameController and touch input using existing port mappings, and validate scene transitions/backgrounding.
   Disable cross-launch save states until the existing fixed-address assumptions are solved for iOS ASLR.
7. Validate a real device game boot before publishing gameplay-capable releases or performance claims.

## Distribution boundary

Distribute compiled native code and redistributable dependencies, not a Nintendo disc image.
No Switch keys or Switch executable rewriting are needed for this GameCube source port.
Development signatures/provisioning are separate from IPA packaging; signed distribution must match the intended device/account/channel.
The current host requests no special memory or JIT entitlements.
There are no configured signing identities on this development machine, so physical-device installation cannot yet be verified.
