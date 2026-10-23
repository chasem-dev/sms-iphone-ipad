# sms-iphone-ipad

A native iPhone/iPad distribution target for the Sunshine port family.
The intended model matches `sms-android`: distribute compiled port code, then import a disc image from the user's own copy inside the app.
No Nintendo game images, artwork, keys, or saves are included.

## Current status

**Experimental simulator game build; not a device-ready release.**
The separate native game target now boots Sunshine through its real title/file-select flow into the airstrip, renders game geometry, characters, textures and HUD, and accepts scripted movement through the engine's SDL input path.
See [native game bring-up](docs/GAMEPLAY.md) for the build, local-disc installation, and gameplay/control verification commands.
Physical iPhone/iPad gameplay, signing, saving, audio quality, and full-game graphics coverage remain unverified.

The original UIKit/Metal diagnostic host still builds independently and provides:

- iPhone and iPad layouts, rotation, and foreground/background rendering control.
- An indexed, textured Metal diagnostic using bundled, offline-compiled shaders, not a gameplay renderer.
- Full-image GPU readback checks for clear, geometry, texture orientation, depth occlusion, alpha blending, scissor, viewport, and linear-to-sRGB output at four target sizes.
- Files-based import of uncompressed GMSE01 revision 0 ISO/GCM images into the app's Documents/Game directory.
- Header/bounds checks, background copying, and replacement that preserves an existing image if the new import fails before installation.
- Connected-controller detection in the diagnostic host; the separate game target has UIKit touch controls and SDL controller support.
- Non-destructive tests of the PC ARM64 engine's memory windows, with a JSON report in Documents.
- Unsigned device IPA packaging and optional development signing.

The experimental `SunshineGame.app` links the real engine, SDL2, and static MoltenVK; it is distinct from the diagnostic `Sunshine.app` and the host-only IPA workflow below.
It currently requires the runner to install a local disc into its private container; the diagnostic host's Files importer is not yet connected to this game app.
`engine.lock.json` pins the existing PC engine and its submodules; `tools/prepare_engine.py` verifies or fetches it without changing the desktop checkout.
See [the integration plan](docs/PORTING.md) for work to reuse from the PC, Android, and Switch targets.

## Requirements

- macOS with full Xcode, the iOS SDK, and an installed simulator runtime for simulator testing.
- CMake 3.24+, Python 3.9+, and Git.
- An Apple signing identity and provisioning profile only when installing on a physical device.

This host does not request JIT, increased-memory, or extended-address-space entitlements.
Do not assume a paid developer account is required for the eventual Sunshine port solely because Odyssey's port needs one.
The game engine's memory requirements still need validation on physical hardware; a simulator result does not settle that question.

## Build

```sh
python3 tools/build.py simulator
python3 tools/build.py device
```

The simulator app is `build/simulator/Release-iphonesimulator/Sunshine.app`.
The unsigned device app is `build/device/Release-iphoneos/Sunshine.app`.
Both generated Xcode projects live in their respective build directories.
The simulator build targets ARM64 Macs.

To sign using an account already configured in Xcode:

```sh
python3 tools/build.py device --team YOUR_TEAM_ID --bundle-id your.unique.sunshine
python3 tools/package_ipa.py build/device/Release-iphoneos/Sunshine.app \
  --require-signed --output build/Sunshine-development.ipa
```

Provisioning must authorize the device that will run the app.
No signing secrets are stored by these tools.
For an unsigned artifact to sign separately:

```sh
python3 tools/package_ipa.py build/device/Release-iphoneos/Sunshine.app \
  --output build/Sunshine-unsigned.ipa
```

Unsigned means **not directly installable**.
The packager refuses simulator builds and recognized disc-image/DOL filenames; that is a safety check, not a complete content or licensing scanner.
No build step embeds an imported game image.

## Simulator

```sh
xcrun simctl list devices available
xcrun simctl boot DEVICE_UDID
xcrun simctl bootstatus DEVICE_UDID -b
xcrun simctl install DEVICE_UDID build/simulator/Release-iphonesimulator/Sunshine.app
xcrun simctl launch DEVICE_UDID dev.chasem.sms-iphone-ipad
```

Use **Test Engine Memory Layout** to write `memory-probe.json` to the app's Documents directory.
For automated diagnostics, append `--probe-memory` to the `simctl launch` command.
Only first/last pages are touched; mappings are released afterward and never replace an existing mapping.
This does not execute game code or prove that the full game is compatible.

## Graphics verification

```sh
python3 tools/build.py simulator
python3 tools/verify_simulator.py --device IPHONE_UDID --device IPAD_UDID
```

The verifier runs both light and dark appearances with Metal API validation requested.
Each app launch must pass all 32 scene/size combinations with full-frame pixel comparisons and complete at least three onscreen GPU command buffers without errors.
The runner then backgrounds the app through Settings and verifies that rendering pauses and resumes in the same process with new GPU frames.
Reports carry unique run IDs so old results cannot satisfy a new check.
Screenshots, graphics/lifecycle reports, command logs, and summaries are saved under `build/validation/graphics/`.
Use `--appearance light` or `--appearance dark` for one appearance.

The sizes cover square, portrait, landscape, and non-power-of-two offscreen targets; this is **not** an automated UI-rotation test.
These checks validate only the host diagnostic pipeline, not Sunshine's GX renderer, game scenes, performance, or physical-device behavior.
Use **Verify Metal Graphics** in the app to run the same GPU checks manually.

GitHub Actions runs portable tests and compiles the simulator/device hosts and shaders, then uploads a host-only unsigned IPA.
The workflow does not currently boot simulators or run the live GPU/lifecycle suite; run the command above on an Apple Silicon Mac for that coverage.

## Engine source and validation

```sh
python3 tools/prepare_engine.py --local ../sms-pc-port
# Or fetch the pinned source into the ignored .cache/engine directory:
python3 tools/prepare_engine.py

cmake -S . -B build/host-tests -DBUILD_TESTING=ON
cmake --build build/host-tests
ctest --test-dir build/host-tests --output-on-failure
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

Header validation tests use synthetic files, not a real disc.
Passing those checks is not proof of a complete, authentic game dump.
