PROJECT := RULYX.xcodeproj
SCHEME := RULYX

# Build destination for compiling: `generic` needs no simulator, so it works on any machine
# (developer machine or CI runner).
GENERIC_DESTINATION ?= generic/platform=iOS Simulator

# Tests need a concrete simulator; `scripts/simulator-destination.py` resolves one that exists
# here (CI device first, newest runtime, shut down) — UDIDs and device sets differ per machine.
# Override to pin one: make test SIMULATOR_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro Max'
SIMULATOR_DESTINATION ?= $(shell python3 scripts/simulator-destination.py)
DERIVED_DATA_PATH := /private/tmp/RULYX-TestDerivedData

.PHONY: help ensure-secrets generate build build-for-testing test test-ci test-sim test-fresh lint format screenshots translations-export translations-sync translations-repair translations-validate translations-validate-ci

help:
	@printf '%s\n' \
		'Available targets:' \
		'  make generate          Regenerate the Xcode project with xcodegen' \
		'  make build             Build for the generic iOS Simulator destination' \
		'  make build-for-testing Build test products for the generic simulator destination' \
		'  make test              Run tests on iPhone 16 Pro Max simulator' \
		'  make test-sim          Same as test (alias for compatibility)' \
		'  make test-fresh        Run tests on iPhone 16 Pro Max with a fresh derived data path' \
		'  make lint              Run swiftformat --lint and swiftlint' \
		'  make format            Format Sources and Tests with swiftformat' \
		'  make screenshots       Capture App Store screenshots via fastlane snapshot (1260x2736)' \
		'  make translations-sync Sync JSON bundles into Localizable.xcstrings' \
		'  make translations-repair Repair placeholder mismatches via English fallback'

# Config/Secrets.xcconfig is gitignored but referenced by project.yml, so xcodegen refuses to
# generate the project without it. A fresh clone — and CI — gets the tracked template copied
# into place; real values are never committed.
ensure-secrets:
	@mkdir -p Config
	@test -f Config/Secrets.xcconfig || cp Config/Secrets.xcconfig.template Config/Secrets.xcconfig

generate: ensure-secrets
	xcodegen generate

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(GENERIC_DESTINATION)' build CODE_SIGNING_ALLOWED=NO

build-for-testing:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(GENERIC_DESTINATION)' build-for-testing CODE_SIGNING_ALLOWED=NO

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(SIMULATOR_DESTINATION)' test CODE_SIGNING_ALLOWED=NO

# The unit-test run CI uses: coverage + parallel testing, app target only.
test-ci:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(SIMULATOR_DESTINATION)' -only-testing:RULYXTests -enableCodeCoverage YES -parallel-testing-enabled YES test CODE_SIGNING_ALLOWED=NO

test-sim: test

test-fresh:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(SIMULATOR_DESTINATION)' -derivedDataPath $(DERIVED_DATA_PATH) test CODE_SIGNING_ALLOWED=NO

lint:
	swiftformat --lint .
	swiftlint

format:
	swiftformat Sources Tests

screenshots:
	bundle exec fastlane snapshot

translations-export:
	python3 scripts/export-translations.py

translations-sync:
	python3 scripts/sync-xcstrings-from-json.py

translations-repair:
	python3 scripts/repair-placeholder-mismatches.py

translations-validate:
	@printf 'Validating translations...\n'
	python3 scripts/sync-xcstrings-from-json.py
	python3 scripts/validate-translations.py

translations-validate-ci: translations-validate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(SIMULATOR_DESTINATION)' test CODE_SIGNING_ALLOWED=NO -only-testing:RULYXTests/LocalizationCompletenessTests
