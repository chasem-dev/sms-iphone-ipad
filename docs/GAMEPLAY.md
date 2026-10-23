# Native game simulator bring-up

The original `tools/build.py` builds only the UIKit/Metal diagnostic app.
It must not be used as evidence that Sunshine boots or is playable.

## Separate engine build

```sh
python3 tools/build_engine.py --reference ../sms-pc-port \
  --moltenvk /absolute/path/MoltenVK.xcframework/ios-arm64_x86_64-simulator/libMoltenVK.a
```

This experimental target uses the pinned engine and submodules, a separate macOS LLVM pointer-pass plugin, SDL2 built for iOS Simulator, and statically linked MoltenVK.
It requires Homebrew LLVM and Ninja in addition to the diagnostic host's prerequisites.
Supply an actual iOS Simulator MoltenVK archive, not a macOS-only or device-only framework. The verified runs used MoltenVK 1.2.9. `SMS_IOS_MOLTENVK` can supply the path instead of `--moltenvk`; otherwise the default is `.cache/MoltenVK.xcframework/ios-arm64_x86_64-simulator/libMoltenVK.a`. MoltenVK binaries are not included in this repository.
The tool patches only the ignored `.cache/engine` checkout; it refuses unexpected tracked edits there and leaves the reference checkout untouched.
The resulting app is `build/engine-simulator/SunshineGame.app`, with bundle identifier `dev.chasem.sunshine.game`.
The diagnostic host remains a separate app and retains its existing verification suite.

## Private preloaded device IPA

For personal local use only, a separate opt-in packager can embed your own ISO and make the launcher ready to Play without selecting/importing a file. An imported Documents/Game/disc.gcm takes precedence over this bundled fallback. The clean build app and default distribution packager remain asset-free; the default packager rejects the local-only marker and all game images.

```sh
python3 tools/build_engine.py --platform device \
  --moltenvk /absolute/path/MoltenVK.xcframework/ios-arm64/libMoltenVK.a
python3 tools/package_local_ipa.py --disc /absolute/path/to/your/GMSE01-revision-0.iso
```

Optionally pass `--icon /absolute/path/to/local-artwork.png` to compile an opaque Home Screen icon for both iPhone and iPad. Transparent artwork is centered on a blue background; iOS applies the corner mask. This requires macOS with Xcode and Swift. Keep private artwork under ignored `build/local-private/`; the generated icons exist only in the staged private bundle, not the clean source app. The verification report records the artwork hash and icon metadata.

The device app is `build/engine-device/SunshineGame.app`. The private IPA and hash/verification report are written under ignored `build/local-private/`, with owner-only permissions. The source app is not modified. Packaging copies the disc only into a temporary local app, adds explicit local-only bundle metadata, removes stale signing metadata, and checks that the archived disc's SHA-256 matches the selected input. It does not upload or publish anything.

**Never distribute or upload this private IPA or its embedded game image.** The resulting `Sunshine-personal-unsigned.ipa` is not an install-ready signed release: it must be signed/provisioned separately. Device compilation/linking does not establish physical-device address-space compatibility, gameplay, graphics, or performance. The launcher and its settings remain available; only image selection is skipped. Normal public builds do not discover arbitrary bundle images without the explicit private markers.

## Physical-device memory windows

The device build defines `SMS_IOS_DEVICE` in both the engine and its host-built LLVM pointer pass. Its MEM1 base is `0x7080000000`, while the executable/low-pointer window remains above `0x100000000`. Simulator and desktop pointer bases are unchanged. These must agree at compile time: changing only the runtime allocation would leave generated game pointers pointing elsewhere.

The original signed build exited on Play because the desktop MEM1 address `0x10080000000` could not be mapped on the tested iPhone 15 Pro. A separate signed on-device probe verified a 64 MiB exact mapping, endpoint reads/writes, and non-overwriting Mach allocation at `0x7080000000` without additional entitlements. This establishes that device's reservation capability, not compatibility with every iOS version/device or full-game correctness. The patched runtime reports this as an iOS memory-reservation failure rather than suggesting a desktop launcher setting.

## Game image and evidence

Normal launches show the native launcher, not the game. Import your own uncompressed North American GMSE01 revision 0 ISO/GCM through Files, configure Settings, then choose Play. An existing valid image enables Play on subsequent launches; missing or structurally invalid images leave it disabled. No game data is bundled.

Settings persist across process restarts and apply before the engine initializes:

- Graphics: 1×–4× rendering resolution and 4:3/16:9 aspect ratio.
- Gameplay: 30/60 fps, camera X/Y inversion, and skip intro/movies.
- Controls: touch overlay visibility and opacity.
- Audio: master volume.

The renderer remains Vulkan through Metal/MoltenVK. Terminate and relaunch the app to return to settings; merely backgrounding/reopening resumes gameplay. Returning from gameplay to the launcher in-process is not implemented. Higher resolutions and nondefault gameplay settings are available, not a promise of physical-device performance or every setting's visual correctness.

Imports are coordinated security-scoped reads into a staging file in Documents/Game. Header identity, filesystem structure, names, and file ranges are checked before replacing the installed image; interrupted staging files are removed on the next launch. These checks cannot establish authenticity or the presence of every required game asset. Documents/launcher-settings.json records the options actually applied on Play.

For automated simulator setup, the runner can install your local image directly:

```sh
python3 tools/run_game_simulator.py \
  --device SIMULATOR_UDID \
  --disc /absolute/path/to/your/GMSE01-revision-0.iso \
  --seconds 180 \
  --autopress 'START@1400,STICK_LEFT@2000,A@2400,STICK_LEFT@3100,A@3250,A@3450,A@3800,A@4100,A@4400,A@4700,A@5000,A@5300,A@5600,A@5900,STICK_UP@6500+30,A@7000+20,CSTICK_RIGHT@7400+60,START@7800,START@8000' \
  --require-gameplay
```

The runner validates the local image header and bounds, copies it into the simulator app's private Documents/Game directory, and never embeds it in the app or repository. It explicitly sets `SMS_IOS_AUTOLAUNCH=1` to bypass the launcher for automated gameplay runs. Pass `--launcher` to exercise the normal launcher instead; scheduled engine inputs start only after Play.
The script uses the engine's existing field-based input automation, not a mock game loop.
It collects actual screenshots, engine logs, presence changes, and native engine telemetry under ignored `build/validation/gameplay/`.
An app-launch success is not a game-boot success: `--require-gameplay` requires an actual primary playable stage (not the title/menu stage), advancing movement ticks, observed input, player displacement within the same stage/process, a live process, and logs without known Vulkan/Metal failures.
These checks still do not prove correct graphics or human playability on their own.

The game entry uses the Android GameCube artwork and normalized layout: analog movement and C sticks, D-pad, A/B/X/Y, L/R/Z, and Start. Multitouch, button sliding, and cancellation/release handling feed a dedicated SDL virtual GameController; sticks are proportional, not keyboard approximations. Physical controllers use SDL's existing mappings, but hardware-controller testing and physical/touch arbitration or auto-hide are not implemented/verified.
Cross-launch save states are explicitly disabled because iOS ASLR compatibility has not been established; normal game memory-card saves are separate.

## Native touch verification

After the startup script finishes, leave the game in an unpaused airstrip stage with dialogue dismissed, then run:

```sh
python3 tools/verify_game_controls.py --device SIMULATOR_UDID
```

This builds a separate XCTest UI runner and drags the actual accessible analog sticks and touches UIKit buttons, rather than calling handlers directly or injecting the engine's scripted keyboard events.
It observes same-process game telemetry while exercising movement, A/jump, C-stick, Start/pause, Start/resume and release.
Acceptance requires player displacement, vertical movement with the A button observed, native touch-press counts, camera PAD input, a pause/resume transition, no stuck final keys, no renderer error logs, and a passing XCTest run.
The test does not establish camera-image correctness or arbitrary-stage coverage. Inspect the screenshots and XCTest attachments as well.
Evidence remains ignored under `build/validation/touch/`; no disc, save, or gameplay screenshot is committed.
Do not run simultaneous tests against the same app or leave future autopresses scheduled during the touch test.

Launcher UI tests live in the same Xcode project. Select `testLauncherSettingsAndPlay` with a running launcher and valid disc, `testLauncherMissingDisc` with no disc, or `testLauncherPreferencesSurviveRelaunch` to check cross-process persistence. The latter launches/terminates the app and intentionally leaves it at the launcher. Settings/Play checks also verify that muting survives reopening the settings sheet before the real game starts. A successful full Files-provider import remains a separate manual check; picker presentation/cancellation is covered.

## Required acceptance evidence

- Title and file-select screens visibly render, rather than merely running CPU frames.
- A new game or existing save loads a real stage with its geometry, materials, HUD, and player.
- Directional input moves Mario, A jumps, the camera changes, and pause/resume responds.
- Input release stops movement, and touch controls do not leave keys stuck.
- Audio, normal saving/loading, foreground/background transitions, and both simulator form factors are exercised independently.
- Vulkan/Metal errors, crashes, blank captures, and non-advancing simulation all fail acceptance.

Do not infer real iPhone/iPad compatibility, performance, or signing requirements from a simulator run.
