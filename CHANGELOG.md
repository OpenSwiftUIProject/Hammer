# Change Log

## Unreleased

- Add mouse clicks, long presses, drags, and async waits for macOS 12 or later,
  with AppKit regression tests.
- Share location and geometry helpers across iOS and macOS. Require the main
  actor for event generation and location lookup on both platforms.
- Require Swift 5.9 or later.
- Keep platform tests in one `HammerTests` target and add `make test-macOS`.

Changes can be found here: https://github.com/lyft/Hammer/releases
