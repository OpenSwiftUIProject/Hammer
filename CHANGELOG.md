# Change Log

## Unreleased

- Add mouse clicks, long presses, drags, and async waits for macOS 12 or later,
  with AppKit regression tests.
- Share location and geometry helpers across iOS and macOS. Require the main
  actor for event generation and location lookup on both platforms.
- Require Swift 5.9 or later.
- Keep platform tests in one `HammerTests` target and add `make test-macOS`.
- Require iOS 15 or macOS 12 in SwiftPM and the shared Xcode targets.
- Run Xcode tests in TestHost on both iOS and macOS.
- Remove the CocoaPods specification.
- Generate the Xcode workspace with Tuist and use automatic signing.

Changes can be found here: https://github.com/lyft/Hammer/releases
