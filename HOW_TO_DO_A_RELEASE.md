# How To Do A Release

This document describes the local release process for `RULYX`, including version bumping, building an App Store archive, exporting an `.ipa`, and uploading it with Transporter.

## Important Rules

- Do not edit `RULYX.xcodeproj/project.pbxproj` manually.
- The source of truth for release versioning is [project.yml](/Users/ajung/src/RULYX/project.yml).
- After changing release settings, always run:

```bash
xcodegen generate
```

- `CFBundleShortVersionString` and `CFBundleVersion` are generated from:
  - `MARKETING_VERSION`
  - `CURRENT_PROJECT_VERSION`

## Current Release Settings

The app is currently prepared for:

- Version: `1.0.2`
- Build: `56`

These values live in [project.yml](/Users/ajung/src/RULYX/project.yml).

## Release Checklist

1. Confirm you are on the correct commit on `main`.
2. Update release version in `project.yml` if needed.
3. Regenerate the Xcode project.
4. Build an archive locally.
5. Export the `.ipa`.
6. Upload the `.ipa` with Transporter.
7. Complete submission/release steps in App Store Connect.

## 1. Update Version

Edit [project.yml](/Users/ajung/src/RULYX/project.yml) and update:

```yaml
MARKETING_VERSION: "1.0.2"
CURRENT_PROJECT_VERSION: "56"
```

Notes:

- `MARKETING_VERSION` is the App Store version users see.
- `CURRENT_PROJECT_VERSION` is the build number.
- Both must move forward for a new App Store upload.

## 2. Regenerate The Project

Run:

```bash
xcodegen generate
```

This updates:

- [RULYX.xcodeproj](/Users/ajung/src/RULYX/RULYX.xcodeproj)
- generated plist/project version wiring

## 3. Local Build Sanity Check

Optional simulator build:

```bash
xcodebuild \
  -project RULYX.xcodeproj \
  -scheme RULYX \
  -destination 'generic/platform=iOS Simulator' \
  build CODE_SIGNING_ALLOWED=NO
```

## 4. Team Signing Requirement

Local archive builds require a valid Apple Team ID.

Current project configuration uses:

- Team name: `Andreas Jung`
- Team ID: `4PC9Z56E47`

This is configured in [project.yml](/Users/ajung/src/RULYX/project.yml).

If signing fails, verify:

- the correct Apple account is signed into Xcode
- the team still exists and has valid certificates/profiles
- automatic signing is working for `com.ajung.RULYX`
- an App Store distribution profile exists for `com.ajung.RULYX`

## 5. Build And Export Locally

Use the helper script:

```bash
scripts/release.sh --no-upload
```

This script will:

1. run `xcodegen generate`
2. archive a Release build
3. request provisioning updates from Apple if needed
4. export an App Store Connect `.ipa`

Expected output location:

```bash
build/release/export/RULYX.ipa
```

## 6. Upload With Transporter

You can use the same script to upload after export.

### 6.1 Create App Store Connect API Key

In App Store Connect:

1. Open `Users and Access`
2. Open `Integrations`
3. Open `App Store Connect API`
4. Generate an API key

You will receive:

- `Key ID`
- `Issuer ID`
- `AuthKey_<KEYID>.p8`

### 6.2 Install The API Key Locally

Place the key file here:

```bash
~/.appstoreconnect/private_keys/AuthKey_<ASC_API_KEY_ID>.p8
```

Example:

```bash
~/.appstoreconnect/private_keys/AuthKey_ABC123XYZ9.p8
```

### 6.3 Export Required Environment Variables

```bash
export ASC_API_KEY_ID=ABC123XYZ9
export ASC_API_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

### 6.4 Run Upload

```bash
scripts/release.sh
```

The script will:

1. regenerate the project
2. archive the app
3. ask Xcode to refresh/fetch provisioning assets if needed
4. export the `.ipa`
5. upload the `.ipa` with Transporter

## 7. Manual Transporter Command

If you want to upload the exported `.ipa` yourself:

```bash
xcrun iTMSTransporter \
  -m upload \
  -assetFile build/release/export/RULYX.ipa \
  -apiKey "$ASC_API_KEY_ID" \
  -apiIssuer "$ASC_API_ISSUER_ID" \
  -v informational
```

## 8. Finish In App Store Connect

Transporter only uploads the build.

After upload:

1. Open App Store Connect
2. Wait for build processing to finish
3. Attach the build to the `1.0.2` version record
4. Complete release notes, compliance, screenshots, and submission steps

### 8.1 Confirm The Upload Worked

If Transporter ends with output like:

```text
1 package was uploaded successfully:
    /Users/ajung/src/RULYX/build/release/export/RULYX.ipa
==> Upload submitted to App Store Connect
```

then the binary upload is complete.

This does not mean the app is already submitted for review. It only means Apple accepted the `.ipa` for processing.

### 8.2 Wait For Processing

Before a build can be selected for release, App Store Connect must process it.

In App Store Connect:

1. Open `Apps`
2. Select `RULYX`
3. Open the `TestFlight` tab or the iOS app version page
4. Wait until the new build finishes processing

If the build is still processing, it will not be selectable in the release form.

### 8.3 Attach The Build To Version 1.0.2

Once processing is complete:

1. Open the `1.0.2` app version record
2. Scroll to the `Build` section
3. Click the `+` button
4. Select the processed `1.0.2` build
5. Click `Done`
6. Click `Save`

If the build does not appear there, either:

- processing has not finished yet
- the uploaded version/build number does not match the release you are preparing

### 8.4 Complete Required Metadata

Before submission, confirm all required App Store fields are complete:

- `What’s New in This Version`
- screenshots, if App Store Connect requests them
- app privacy data
- export compliance, if prompted
- age rating
- any missing review notes or sign-in information

### 8.5 Add For Review And Submit

After the build is attached and metadata is complete:

1. Click `Add for Review`
2. Review the submission checklist
3. Click `Submit for Review`

Important:

- `Add for Review` does not always send the app immediately
- the final action is `Submit for Review`
- your App Store Connect user must have permission to submit releases

### 8.6 Choose Release Timing

During submission, App Store Connect will ask how the release should go live after approval.

Typical options:

- manually release this version
- automatically release this version after approval
- automatically release no earlier than a chosen date

For controlled launches, choose manual release.

## Common Problems

### Invalid Version / Closed Train

Errors such as:

- `ITMS-90478: Invalid Version`
- `ITMS-90186: Invalid Pre-Release Train`
- `ITMS-90062: CFBundleShortVersionString must contain a higher version`

Mean you need to bump:

- `MARKETING_VERSION`
- usually also `CURRENT_PROJECT_VERSION`

Then regenerate the project again:

```bash
xcodegen generate
```

### Missing Team / Signing Failure

If archive fails with:

```text
Signing for "RULYX" requires a development team
```

Check:

- `DEVELOPMENT_TEAM` in `project.yml`
- your local Apple account in Xcode
- provisioning/signing for the bundle ID

### Export Failed: No Profiles Found

If export fails with:

```text
error: exportArchive No profiles for 'com.ajung.RULYX' were found
```

That means:

- the archive succeeded
- development signing worked
- App Store export signing is still missing for `com.ajung.RULYX`

The release script now passes:

```bash
-allowProvisioningUpdates
```

to both archive and export, which lets `xcodebuild` fetch signing assets when possible.

If that still does not fix the export, do this once in Xcode:

1. Open `RULYX.xcodeproj`
2. Archive the app
3. In Organizer, choose `Distribute App`
4. Select `App Store Connect`
5. Let Xcode repair/fetch signing assets

After Xcode has created or fetched the App Store distribution profile, the CLI release flow usually works afterward.

### Export Failed: Copy Failed

If export fails with:

```text
error: exportArchive Copy failed
```

and the distribution logs show something like:

```text
rsync: on remote machine: --extended-attributes: unknown option
```

then the problem is usually your local `PATH`, not signing.

Cause:

- Xcode IPA packaging expects Apple's patched system `rsync`
- a Homebrew or custom `rsync` earlier in `PATH` can break export

The release script now forces system tools first in `PATH`:

```bash
/usr/bin:/bin:/usr/sbin:/sbin
```

so `xcodebuild` export uses Apple’s expected `rsync` path.

If you still hit this manually outside the script, run your export command with:

```bash
PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
```

### Transporter API Key Error

If the script says:

```text
Set ASC_API_KEY_ID before uploading
```

You have not exported the required environment variables yet.

If it says the key file is missing, verify:

```bash
~/.appstoreconnect/private_keys/AuthKey_<ASC_API_KEY_ID>.p8
```

## Commands Summary

Version bump and project regeneration:

```bash
xcodegen generate
```

Archive and export only:

```bash
scripts/release.sh --no-upload
```

Archive, export, and upload:

```bash
export ASC_API_KEY_ID=YOUR_KEY_ID
export ASC_API_ISSUER_ID=YOUR_ISSUER_ID
scripts/release.sh
```

## End-To-End Short Version

For the normal CLI release flow:

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`
2. Run `scripts/release.sh`
3. Wait for App Store Connect processing
4. Open version `1.0.2`
5. Attach the processed build
6. Click `Add for Review`
7. Click `Submit for Review`
