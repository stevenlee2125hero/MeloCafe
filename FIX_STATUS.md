# 1.0 stability repair — unverified source candidate

Base: official tag 1.0, abada1c88a4de493949e4e32b2eebf28c552568f.
Branch: fix/1.0-dual-rumble-lifecycle.

Only NativeController.swift changes runtime behavior. Original input/motion handlers, Metal, JIT and dependencies are unchanged.

P0: callback registered independently of controller haptics availability. Queue serializes both independent outputs, ignores duplicate starts, stops on detach and app inactivity. Controller uses GameController engine (.all with .default fallback); phone uses CHHapticEngine device initializer. Engine errors are logged and disable that output until reattachment. Reset/interruption does not replay stale rumble. No timers or button-generated rumble.

Evidence: VPADController::update sends rumble bits at approximately 60 Hz; EmulatedController::start_rumble forwards every start; old NativeController rebuilt player on every callback on MainActor and suppressed errors. This is a suspected failure/performance mechanism, not a proven Joy-Con root cause. Game -> VPAD -> physical-device callback path exists statically; no runtime traces were collected. Left/right combined Joy-Con routing is unverified.

P1 NOT implemented: no reusable title-wide pause/resume API found in the iOS bridge. CemuShutdown calls full CafeSystem::Shutdown, which shuts down persistent subsystems and clears initialization state. Safe title reload and audio pause require further investigation and device validation. Existing behavior is preserved rather than introducing unsafe thread suspension or a cosmetic pause menu.

Validation performed: official git tag/HEAD verification; git diff --check; manual callback and shutdown source inspection. No Swift compiler or xcodebuild available on this Windows host. No iOS build, mocked haptics test, physical device test or IPA produced. This candidate must not be considered a verified fix.

On macOS: initialize original pinned git submodules, follow repository BUILD.md and original Xcode configuration; build MeloCafe/MeloCafe.xcodeproj using its existing scheme and original dependency setup. Do not upgrade dependencies or signing configuration. Resolve compiler diagnostics before deploying this candidate.

Required device checks: iPhone 15 Plus + actual iOS version + paired and individual Joy-Con; collect engine errors and real game rumble traces; verify simultaneous start/stop, prolonged rumble, rapid pulses, 20 disconnect/reconnect and foreground/background cycles, engine failures isolated per output, relaunch and 30–60 minute Wind Waker HD comparison. Interruption disables affected output until reattachment intentionally; report this limitation. No pause/exit acceptance tests can pass because P1 remains unimplemented.

Core Haptics physical start latency and phone/controller simultaneous playback support remain unverified; no exact synchronization guarantee. If device playback conflicts with controller playback, retain stability and do not ship this candidate as successful.
