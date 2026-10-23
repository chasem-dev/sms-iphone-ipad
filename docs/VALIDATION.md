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

This is evidence of a playable simulator stage, not full-game completion or perfect graphics. Camera input delivery is verified, not quantitative camera-image correctness. Audio logged queue underruns and has not passed a quality/listening test; saving/loading, physical controllers, multi-touch combinations, native-game background/foreground safety, other stages/effects, physical devices, and a gameplay-capable signed IPA remain separate acceptance gates. Existing CI still builds/packages only the diagnostic host, not a game release. The experimental game target does not yet integrate the diagnostic host's Files importer.
