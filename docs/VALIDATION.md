# Bring-up validation — October 23, 2026

Environment: Apple Silicon Mac, Xcode 16.2, iPhoneOS/iPhoneSimulator SDK 18.2, simulator runtime reporting iOS 18.3.1.

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
- No game boot, engine rendering, audio, input mapping, or real disc import has been tested; the app explicitly reports that the engine is not connected.

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
The current shader suite is a diagnostic host pipeline; the game engine and its GX shaders remain unlinked and unverified.
