# Validation

Validated with Xcode 27.1 on an iPhone 17 Pro simulator running iOS 26.2.

- iOS simulator build: passed.
- ToodleCore: 7 tests passed, zero failures. Covers FRI boundaries, rainfall curve and memory, rolling windows, conservative ensemble merge, simulation states, JSON adapters and mock client.
- UI walkthrough: passed, zero failures. Opens Command, inspects a node, plays the storm sequence, previews and simulates dispatch, then visits Capture and Settings.
- Swift app compiler warnings: none in the final test build. Xcode emits an App Intents metadata extraction notice and a host build-version parsing diagnostic; neither failed the build or tests.
- `git diff --check`: passed.

Device-only and integration checks remain: camera/photo permission denial, real GPS behavior, VoiceOver on hardware, large accessibility sizes, minimum iOS 17 runtime, configured backend access, and SMS delivery. No real SMS was sent and no simulation telemetry was uploaded during validation.

