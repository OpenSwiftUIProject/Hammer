## Contributing

1. Fork the repo.
1. Generate the Xcode workspace with Tuist by running `make`.
    - Open `Hammer.xcworkspace`.
    - The Hammer scheme runs iOS and macOS tests in TestHost.
1. Run `make test-macOS` for macOS tests or `make test` for lint and both platforms.
    - Run iOS stylus tests on an iPad.
1. Add tests if you are adding a feature or fixing a bug.
1. Make your tests pass.
1. Push to your fork and submit a pull request!
