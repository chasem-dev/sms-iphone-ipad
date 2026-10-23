# sms-iphone-ipad

A native iPhone/iPad distribution target for the Sunshine port family.
The intended model matches `sms-android`: distribute compiled port code, then import a disc image from the user's own copy inside the app.
The repository and normal distribution builds include no game disc contents, keys, or saves. Touch-controller artwork is reused from `sms-android`. An explicit [personal-only packaging workflow](docs/GAMEPLAY.md) can embed a locally supplied disc into an ignored private IPA; it must never be distributed or uploaded.

## Current status

**Experimental game build; not a release-ready port.**
The separate native game target now boots Sunshine through its real title/file-select flow into the airstrip, renders game geometry, characters, textures and HUD, and accepts scripted movement through the engine's SDL input path.
See [native game bring-up](docs/GAMEPLAY.md) for the build, local-disc installation, and gameplay/control verification commands.
Initial signed-device gameplay is verified on an iPhone 15 Pro running iOS 27.0 beta: the airstrip loads and native touch controls move the player. The device-only memory-window fix and evidence are recorded in [validation notes](docs/VALIDATION.md). Other physical devices/OS versions, saving, audio quality, and full-game graphics coverage remain unverified.

Known issues: the user reports uneven performance even at the 30 fps setting, audio underruns are logged, and backgrounding can cause a Vulkan device-lost error and app exit. Frame-pacing/CPU/GPU profiling and proper background/foreground rendering suspension remain unfinished; do not treat this checkpoint as a stable release.

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
It opens a native launcher before engine initialization, with Files import, persistent settings, and a Play button. Gameplay uses the Android version's GameCube touch artwork/layout with analog movement and camera sticks. See [native game setup](docs/GAMEPLAY.md); the commands below still build the separate diagnostic host.
`engine.lock.json` pins the existing PC engine and its submodules; `tools/prepare_engine.py` verifies or fetches it without changing the desktop checkout.
See [the integration plan](docs/PORTING.md) for work to reuse from the PC, Android, and Switch targets.

## Requirements

- macOS with full Xcode, the iOS SDK, and an installed simulator runtime for simulator testing.
- CMake 3.24+, Python 3.9+, and Git.
- An Apple signing identity and provisioning profile only when installing on a physical device.

This host does not request JIT, increased-memory, or extended-address-space entitlements.
Do not assume a paid developer account is required for the eventual Sunshine port solely because Odyssey's port needs one.
The game engine's memory window is verified only on the physical-device configuration noted above; a simulator result does not establish compatibility with other hardware or OS versions.

## Build

### Actual game: build, package, and sign locally

These commands build **SunshineGame**, not the diagnostic host. Run from this repository on an Apple Silicon Mac with Xcode selected as the command-line tools installation. Install CMake, Ninja, Python 3.9+, Git, and the host shader tools described in [native game setup](docs/GAMEPLAY.md). Supply a MoltenVK XCFramework containing the **iPhoneOS arm64** slice; a macOS-only or simulator archive cannot produce a device IPA.

```sh
python3 tools/build_engine.py --platform device \
  --moltenvk /absolute/path/MoltenVK.xcframework/ios-arm64/libMoltenVK.a

python3 tools/package_local_ipa.py \
  --disc /absolute/path/to/your/GMSE01-revision-0.iso \
  --icon /absolute/path/to/your/local-sunshine-icon.png
```

The device app is `build/engine-device/SunshineGame.app`. The private output is `build/local-private/Sunshine-personal-unsigned.ipa`. The optional icon is compiled for iPhone and iPad. This opt-in IPA contains your disc and opens the launcher ready to Play without importing it. **Never upload or distribute the preloaded IPA or artwork.** Omit this private packaging workflow for normal asset-free distribution.

Before signing:

1. Open **Xcode → Settings → Accounts** (Apple Accounts in newer Xcode) and sign in locally. Select your team; under **Manage Certificates**, create an **Apple Development** certificate if needed. The certificate's private key must be in this Mac's Keychain. Do not put credentials, certificates/private keys, or profiles in Git.
2. Connect and unlock the iPhone/iPad, trust the Mac, and enable **Settings → Privacy & Security → Developer Mode**, restarting if prompted.
3. Run the commands below. Use your Apple Team ID and the intended device identifier. The signing helper accepts a CoreDevice identifier or hardware UDID and resolves it before validating device registration.

```sh
security find-identity -v -p codesigning
xcrun devicectl list devices

python3 tools/sign_local_ipa.py \
  --team YOUR_TEAM_ID \
  --device YOUR_DEVICE_IDENTIFIER
```

The helper asks Xcode to provision a separate diagnostic target with the game's exact bundle ID, `dev.chasem.sunshine.game`, using your signed-in account. **Only that asset-free target participates in provisioning; the private game IPA is not uploaded.** It validates profile expiry, app ID authorization, team, device registration, and a matching Keychain identity, then signs a temporary copy of the actual game app. Explicit profiles and matching trailing-wildcard profiles are supported; the signed application identifier is always expanded to this exact app, never a wildcard. It verifies the signature and entitlements before writing `build/local-private/Sunshine-personal-signed.ipa` and its JSON receipt. The unsigned IPA, clean game build, icon, and bundled disc are preserved. Provisioning logs stay in `build/local-private/signing-provision.log`.

Alternatively, supply an existing **development** profile authorizing this bundle ID and device (explicit or matching wildcard):

```sh
python3 tools/sign_local_ipa.py \
  --profile /absolute/path/to/Sunshine.mobileprovision \
  --device YOUR_DEVICE_IDENTIFIER
```

Signing does not install or launch the game. To install the signed result without uploading it:

```sh
mkdir -p build/local-private/install
chmod 700 build/local-private/install
ditto -x -k build/local-private/Sunshine-personal-signed.ipa build/local-private/install
xcrun devicectl device install app --device YOUR_DEVICE_IDENTIFIER \
  build/local-private/install/Payload/SunshineGame.app
```

If Xcode reports **No Accounts**, sign in in Xcode and rerun. **No matching signing certificate/private key** means a profile alone is insufficient: create or import the corresponding development identity through Xcode/Keychain. Expired profiles must be renewed, and the device must appear in the selected profile. Do not use ad-hoc signing (`codesign -s -`) as a substitute for development provisioning. Keep the bundle ID/team stable across updates; back up saves before changing either.

This follows the reference Odyssey repository's **Xcode provisioning → local signing** approach, not its game-specific memory/iCloud capabilities. Sunshine's helper requests no JIT, Increased Memory Limit, or extended-address-space entitlement. Neither a paid-team requirement nor free-account compatibility has been established for full Sunshine gameplay on hardware. A verified signature is not proof of playable physical-device rendering or address-space compatibility. Development installations expire with their provisioning profile; the receipt records its expiration.

Reference: [Odyssey installation workflow](https://github.com/NicholasDominici/super-mario-odyssey-ios#install-it-yourself) and [Apple's registered-device distribution guide](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices).

### Separate diagnostic host

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

Header/filesystem validation tests use synthetic files, not a real disc.
Passing those checks is not proof of a complete, authentic game dump.
