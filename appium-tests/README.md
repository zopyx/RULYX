# RULYX Appium Tests

Minimal WebDriverIO + Appium tests for the RULYX iOS app.

## Prerequisites

- Xcode 16+
- Node.js 20+
- Appium 2.x (`npm i -g appium`)
- Appium XCUITest driver (`appium driver install xcuitest`)

## Setup

```bash
cd appium-tests
npm install
```

## Build the app

```bash
cd ..
xcodebuild -project RULYX.xcodeproj -scheme RULYX \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build build CODE_SIGNING_ALLOWED=NO
```

## Run tests

```bash
cd appium-tests
npm test
```
