# RULYX Appium Tests

Minimal WebDriverIO + Appium tests for the RULYX iOS app.

## Prerequisites

- Xcode 16+
- Node.js 20+
- Appium 2.x (`npm i -g appium`)
- Appium XCUITest driver (`appium driver install xcuitest`)

## Setup

```bash
appium driver install xcuitest
cd appium-tests && npm install
```

## Build the app

```bash
cd ..
xcodebuild -project RULYX.xcodeproj -scheme RULYX \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build build CODE_SIGNING_ALLOWED=NO
```

If you already have a build in DerivedData, update the `appium:app` path in `wdio.conf.js`.

## Run tests

Ensure a simulator is booted:

```bash
xcrun simctl boot "iPhone 16 Pro Max"
```

Then:

```bash
cd appium-tests && npm test
```

Tests pass `--uitesting` to the app on launch, which skips onboarding and sets the language to English.

## Tests

| Test | What it does |
|------|-------------|
| `launch.spec.js` | Verifies the app launches and all 4 default tabs (Moderation, Info, Settings, Accounts) are visible by accessibility label |
