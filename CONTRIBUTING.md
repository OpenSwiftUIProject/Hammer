## Contributing

1. Fork the repo.
1. For iOS tests, generate the project by running `make`.
    - iOS tests require TestHost through Xcode. macOS tests run with SwiftPM.
1. Run `make test-macOS` for macOS tests or `make test` for lint and both platforms.
    - Run iOS stylus tests on an iPad.
1. Add tests if you are adding a feature or fixing a bug.
1. Make your tests pass.
1. Add an entry to the `CHANGELOG.md`
1. Push to your fork and submit a pull request!
