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

## Game image and evidence

```sh
python3 tools/run_game_simulator.py \
  --device SIMULATOR_UDID \
  --disc /absolute/path/to/your/GMSE01-revision-0.iso \
  --seconds 180 \
  --autopress 'START@1400,STICK_LEFT@2000,A@2400,STICK_LEFT@3100,A@3250,A@3450,A@3800,A@4100,A@4400,A@4700,A@5000,A@5300,A@5600,A@5900,STICK_UP@6500+30,A@7000+20,CSTICK_RIGHT@7400+60,START@7800,START@8000' \
  --require-gameplay
```

The runner validates the local image header and bounds, copies it into the simulator app's private Documents/Game directory, and never embeds it in the app or repository.
The script uses the engine's existing field-based input automation, not a mock game loop.
It collects actual screenshots, engine logs, presence changes, and native engine telemetry under ignored `build/validation/gameplay/`.
An app-launch success is not a game-boot success: `--require-gameplay` requires an actual primary playable stage (not the title/menu stage), advancing movement ticks, observed input, player displacement within the same stage/process, a live process, and logs without known Vulkan/Metal failures.
These checks still do not prove correct graphics or human playability on their own.

The experimental game entry adds UIKit touch buttons for movement, camera, Start, A/B/X/Y and triggers, mapped through SDL keyboard events and the engine's normal bindings.
SDL's controller support is also linked, but a physical controller is not yet verified.
Cross-launch save states are explicitly disabled because iOS ASLR compatibility has not been established; normal game memory-card saves are separate.

## Native touch verification

After the startup script finishes, leave the game in an unpaused airstrip stage with dialogue dismissed, then run:

```sh
python3 tools/verify_game_controls.py --device SIMULATOR_UDID
```

This builds a separate XCTest UI runner and touches the actual accessible UIKit buttons, rather than calling button handlers directly or injecting the engine's scripted keyboard events.
It observes same-process game telemetry while exercising movement, A/jump, C-stick, Start/pause, Start/resume and release.
Acceptance requires player displacement, vertical movement with the A button observed, native touch-press counts, camera PAD input, a pause/resume transition, no stuck final keys, no renderer error logs, and a passing XCTest run.
The test does not establish camera-image correctness or arbitrary-stage coverage. Inspect the screenshots and XCTest attachments as well.
Evidence remains ignored under `build/validation/touch/`; no disc, save, or gameplay screenshot is committed.
Do not run simultaneous tests against the same app or leave future autopresses scheduled during the touch test.

## Required acceptance evidence

- Title and file-select screens visibly render, rather than merely running CPU frames.
- A new game or existing save loads a real stage with its geometry, materials, HUD, and player.
- Directional input moves Mario, A jumps, the camera changes, and pause/resume responds.
- Input release stops movement, and touch controls do not leave keys stuck.
- Audio, normal saving/loading, foreground/background transitions, and both simulator form factors are exercised independently.
- Vulkan/Metal errors, crashes, blank captures, and non-advancing simulation all fail acceptance.

Do not infer real iPhone/iPad compatibility, performance, or signing requirements from a simulator run.
