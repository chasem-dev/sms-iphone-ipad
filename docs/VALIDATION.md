# Bring-up validation — October 23, 2026

Environment: Apple Silicon Mac, Xcode 16.2, iPhoneOS/iPhoneSimulator SDK 18.2, simulator runtime reporting iOS 18.3.1.

## Original diagnostic-host checkpoint

- Release iPhoneOS ARM64 app: built successfully without signing.
- Release iPhoneSimulator ARM64 app: built successfully.
- iPhone 16 Pro simulator: light and dark runs passed all 32 graphics tests each.
- iPad Pro 11-inch (M4) simulator: light and dark runs passed all 32 graphics tests each.
- Every run compared 616,576 GPU-rendered pixels, covering indexed geometry, nearest texture sampling/orientation, depth, source-alpha blending, scissor, viewport, clear, and linear-to-sRGB output.
- All 128 scene/size/appearance/device combinations passed: 2,466,304 checked pixels, zero mismatched pixels, and zero channel differences against the reference images.
- Onscreen command buffers completed without recorded GPU errors; simulator logs confirmed `Metal API Validation Enabled`.
- All four background/foreground checks passed: the view was paused in the background and resumed in the same process with additional completed GPU frames.
- Both simulators: exact 8 MiB low-stack sample and 64 MiB MEM1 mappings succeeded, including endpoint writes and pointer round trips.
- Host CTest: synthetic disc header validation passed.
- Python unit tests: all 27 passed, covering packaging, source preparation, complete test coverage, stale-report rejection, and lifecycle evidence validation.
- Unsigned device IPA: generated with a `Payload/Sunshine.app` bundle and no game data.
- Device executable: Mach-O build platform checked as iOS, not simulator.
- No signing identities are configured; physical device installation, hardware address-space availability, and signed IPA installation remain unverified.
- At this original host-only checkpoint, game boot, engine rendering, audio, and input mapping were not tested; the diagnostic app reports that the engine is not connected.

Local ignored evidence is in `build/validation/`: screenshots and JSON memory-probe reports for each simulator.
The reproducible graphics suite writes its reports and command logs to `build/validation/graphics/`.
Checked-in graphics/lifecycle evidence and representative screenshots are in `docs/validation/`.
The unsigned host-only artifact is `build/Sunshine-unsigned.ipa`.
Simulator memory results are host-process observations and must not be treated as evidence about an iPhone/iPad kernel's allowed virtual address space.

## Issues corrected during verification

- Replaced the unverified clear-only view with a shared indexed/texture pipeline and full-image offscreen readback tests.
- Added explicit render-target/depth formats, resource-allocation checks, and command-buffer error reporting.
- Forced view initialization before launch-triggered verification; previously the initial button-state guard silently skipped automation before UIKit loaded the view.
- Paused rendering when resigning active and resumed only after becoming active, rather than starting rendering prematurely while entering the foreground.
- Required the exact 32-test matrix and matching run IDs; incomplete, duplicate, stale, or failed reports cannot satisfy the verifier.

Portrait/landscape tests refer to offscreen target shapes, not automated device rotation.
This shader suite is a diagnostic host pipeline and remains separate from the native game renderer below.

## Native game checkpoint

The separate `SunshineGame.app` now links and runs the pinned engine. Both iPhone 16 Pro and iPad Pro 11-inch (M4) simulators booted through real title/file selection into the airstrip (area 0), using a locally supplied disc. Screenshots were inspected for actual geometry, characters, materials, dialogue, water, and HUD; they were not blank host views. Scripted SDL input produced player displacement in the real stage. The known Vulkan/MoltenVK failure checks passed.

XCTest then exercised the actual accessible UIKit touch buttons on each running stage. Telemetry independently confirmed:

| Check | iPhone 16 Pro | iPad Pro 11-inch (M4) |
| --- | --- | --- |
| Native button presses | 5 | 5 |
| Same-stage player displacement | 240.852 game units | 317.432 game units |
| Jump height range | 500–723.25 | 500–718.75 |
| Camera PAD input samples added | 30 | 30 |
| Pause/resume observed | Yes | Yes |
| All final controls released | Yes | Yes |
| XCTest / telemetry acceptance | Passed / passed | Passed / passed |

- All 44 Python tests pass, including managed patch replay/rollback, simulator target configuration, gameplay rejection gates, and touch-evidence rejection tests.
- The iPad test initially exposed iPhone-compatibility presentation. Explicit device-family metadata and native fullscreen SDL window creation corrected it; the successful native game/touch runs include that fix.
- Simulator compatibility fixes isolate static volk dispatch globals, scalarize unsupported sampler arrays, and rebase nonzero-base indexed draws. Critical Vulkan initialization failures now fail with logs instead of continuing into an invalid pipeline layout.
- The reference PC checkout remains untouched. The game image and saves stay in simulator-private storage; no game image, save, game screenshot, or MoltenVK binary is committed.
- Verified executable SHA-256: `51fb64a102a2bbbcf15816a1b9d8e1d5f37e1c0a6e549008fc2abc9fbb1762a4`.

Local evidence:

- iPhone boot/gameplay: `build/validation/gameplay/4C080652-7470-4102-9BE5-85A21DFE6D29/20261023-093800/`.
- iPad boot/gameplay: `build/validation/gameplay/AB16FAF4-F1BE-421F-810C-249898641A5E/20261023-093611/`.
- iPhone native-touch XCTest and telemetry: `build/validation/touch/4C080652-7470-4102-9BE5-85A21DFE6D29/20261023-094723/`.
- iPad native-touch XCTest and telemetry: `build/validation/touch/AB16FAF4-F1BE-421F-810C-249898641A5E/20261023-093856/`.

This simulator checkpoint is evidence of a playable stage, not full-game completion or perfect graphics. Camera input delivery is verified, not quantitative camera-image correctness. Audio logged queue underruns and has not passed a quality/listening test; saving/loading, physical controllers, multi-touch combinations, native-game background/foreground safety, and other stages/effects remain separate acceptance gates. Initial signed physical-device gameplay was subsequently verified in the device checkpoint below. Existing CI still builds/packages only the diagnostic host, not a game release.

## Launcher and GameCube controls checkpoint

Normal game-app launches now open a native launcher before engine initialization. It offers Files import, persistent graphics/gameplay/control/audio preferences, and Play. The game overlay reuses the Android GameCube artwork/layout and sends proportional sticks, triggers, D-pad and buttons through an SDL virtual GameController instead of the original keyboard-button overlay.

Verified on October 23, 2026:

- Launcher Settings/Play XCTest passes on iPhone 16 Pro and iPad Pro 11-inch (M4). Resolution/aspect choices survive reopening settings, mute survives reopening settings and reaches the applied `SMS_VOLUME=0` report, and Play reaches the real engine with the GameCube overlay.
- Cross-process preference persistence passes on both simulators. Terminating/relaunching returns to the launcher with saved resolution/aspect choices.
- Missing-disc Play gating and Files picker presentation/cancellation pass on iPhone. An interrupted-import staging-file fixture is removed on the next launch.
- Synthetic CTest cases reject invalid FST roots/counts, names, file ranges, incorrect directory parents and crossing subtree boundaries; a valid nested tree and the local GMSE01 image pass. Imports validate the staged image before replacement. This is structural validation, not proof of authenticity or complete required assets.
- All 44 Python tests pass, the native engine target builds, its bundle plist validates, and the reference PC checkout remains clean.

Real airstrip gameplay with native analog-stick drags and button touches:

| Check | iPhone 16 Pro | iPad Pro 11-inch (M4) |
| --- | --- | --- |
| Native control presses | 5 | 5 |
| Maximum player displacement from initial position | 999.640 game units | 1315.357 game units |
| Jump height range | 500–712 | 500–718.75 |
| Camera PAD input samples added | 75 | 100 |
| Pause/resume and final release | Passed | Passed |
| XCTest / telemetry acceptance | Passed / passed | Passed / passed |

Local ignored evidence:

- `build/launcher-settings-iphone-final.xcresult` and `build/launcher-settings-ipad-final.xcresult`.
- `build/launcher-persistence-iphone.xcresult` and `build/launcher-persistence-ipad.xcresult`.
- `build/launcher-missing-disc-final.xcresult` and `build/launcher-import-recovery.log`.
- iPhone touch: `build/validation/touch/4C080652-7470-4102-9BE5-85A21DFE6D29/20261023-102443/`.
- iPad touch: `build/validation/touch/AB16FAF4-F1BE-421F-810C-249898641A5E/20261023-102256/`.

Full successful Files-provider import/replacement is not yet an automated acceptance test. Nondefault rendering settings, hardware-controller coexistence, touch combinations, and physical-device behavior retain separate verification gates. Returning to settings requires terminating/relaunching; merely backgrounding and reopening resumes the game. Test apps and both test simulators are stopped after verification to avoid lingering audio/render processes.

## Physical-device startup fix — 2026-10-23

The first signed private build installed and opened its launcher but exited on Play: MEM1 at the desktop address `0x10080000000` was unavailable. The user's Console export recorded voluntary exits, consistent with the runtime's explicit failure rather than an observed GPU crash.

A separate, temporary signed probe on the paired iPhone 15 Pro running iOS 27.0 beta (24A435) verified 64 MiB of exact writable memory at `0x7080000000`. The device-only engine patch and host-built LLVM pointer pass now use the matching `0x7000000000` rebase prefix. Simulator and desktop prefixes remain unchanged. Both plugin variants were checked by compiling representative dynamic and constant pointer conversions to LLVM IR. All 78 Python tests pass.

After a device rebuild, private repackaging, signature verification, and in-place installation, the real game log confirms MEM1 allocation, the A17 Pro Vulkan device/swapchain, shader warm-up, audio initialization, and entry into `SMS_main`. Live device telemetry reached the airstrip (area 0), received native touch/stick/camera input, and remained in the same process. Two samples within the same stage instance advanced from 1,779 to 2,447 frames and showed player displacement greater than 400 game units. The user also paused the game through the touch controls. The temporary probe app was removed; the game was left running without restarting the user's session.

Evidence is local-only under `build/local-private/device-crash/`: the original `game.log`, patched runtime logs, gameplay samples, device details, and `verification.json`. The rebuilt signed IPA and its receipt remain under `build/local-private/`; nothing was uploaded. This verifies initial physical-device gameplay/control delivery on this device, not full-game graphics correctness, saving/loading, audio quality, performance, or compatibility with other OS versions/devices.

### Open performance and lifecycle issues

The user reports uneven performance even at the 30 fps setting. Audio underruns are logged, but no valid live frame-rate or CPU/GPU profile was captured: the later profiling attempt found no running game process, and stale telemetry was rejected rather than interpreted as a measured frame rate.

A later session logged `VK_ERROR_DEVICE_LOST` with `kIOGPUCommandBufferCallbackErrorBackgroundExecutionNotPermitted`, followed by failed queue presentation/submission and `SIGABRT`. This background-GPU failure is separate from the fixed startup memory-window problem. Earlier simulator resume observations do not establish physical-device lifecycle safety. Proper rendering suspension/resumption and frame-pacing/CPU/GPU profiling remain unfinished; no performance optimization or background-crash fix is claimed in this checkpoint.
