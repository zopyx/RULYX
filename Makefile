PROJECT := RULYX.xcodeproj
SCHEME := RULYX
SIMULATOR_DESTINATION := platform=iOS Simulator,id=0B0AC0B5-3A0C-429B-A229-276BF5610A9D
DERIVED_DATA_PATH := /private/tmp/RULYX-TestDerivedData

.PHONY: help generate build build-for-testing test test-sim test-fresh lint format screenshots translations-export translations-sync translations-repair translations-validate translations-validate-ci

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

generate:
	xcodegen generate

build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(SIMULATOR_DESTINATION)' build CODE_SIGNING_ALLOWED=NO

build-for-testing:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(SIMULATOR_DESTINATION)' build-for-testing CODE_SIGNING_ALLOWED=NO

test:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(SIMULATOR_DESTINATION)' test CODE_SIGNING_ALLOWED=NO

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
	python3 scripts/validate-translations.py

translations-validate-ci: translations-validate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(GENERIC_DESTINATION)' test CODE_SIGNING_ALLOWED=NO -only-testing:RULYXTests/LocalizationCompletenessTests
