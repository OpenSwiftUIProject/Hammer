.DEFAULT_GOAL := generate

# Install Tasks

install-lint:
	brew list swiftlint &>/dev/null || brew install swiftlint

install-tuist:
	command -v mise >/dev/null || brew install mise
	mise install

install-xcbeautify:
	brew list xcbeautify &>/dev/null || brew install xcbeautify

# Run Tasks

generate: install-tuist
	mise exec -- tuist generate --no-open

test: lint test-macOS test-iPad

lint: install-lint
	swiftlint lint --strict 2>/dev/null

.PHONY: generate test test-macOS test-iPad test-iPhone test-iPhone-iOS17

test-macOS: install-xcbeautify
	set -o pipefail && \
		xcodebuild \
		-workspace Hammer.xcworkspace \
		-scheme Hammer \
		-destination "platform=macOS" \
		test | xcbeautify

test-iPad: install-xcbeautify
	set -o pipefail && \
		xcodebuild \
		-workspace Hammer.xcworkspace \
		-scheme Hammer \
		-destination "name=iPad Pro 13-inch (M4)" \
		test | xcbeautify

test-iPhone: install-xcbeautify
	set -o pipefail && \
		xcodebuild \
		-workspace Hammer.xcworkspace \
		-scheme Hammer \
		-destination "name=iPhone 17" \
		test | xcbeautify

test-iPhone-iOS17: install-xcbeautify
	set -o pipefail && \
		xcodebuild \
		-workspace Hammer.xcworkspace \
		-scheme Hammer \
		-destination "name=iPhone 15" \
		-sdk iphonesimulator17.4 \
		test | xcbeautify

# List all targets (from https://stackoverflow.com/questions/4219255/how-do-you-get-the-list-of-targets-in-a-makefile)

list:
	@$(MAKE) -pRrq -f $(lastword $(MAKEFILE_LIST)) : 2>/dev/null | awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | sort | egrep -v -e '^[^[:alnum:]]' -e '^$@$$'
