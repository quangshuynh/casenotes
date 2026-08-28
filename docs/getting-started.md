# Getting Started

## Requirements

- macOS with Xcode 26.6 or newer
- An iOS 26.5 or newer simulator or device
- An iPhone 17 simulator for commands matching CI

No packages, generated sources, accounts, or services need to be configured.

## Open and run

Open `CaseNotes.xcodeproj` in Xcode, select the shared `CaseNotes` scheme, and
run the app. The initial screen is the app lock. Simulator authentication
behavior depends on the simulator's enrolled biometric and passcode state.

```bash
xcodebuild build -project CaseNotes.xcodeproj -scheme CaseNotes \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

If command line tools are selected instead of Xcode, prefix the command without
changing the machine-wide selection:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild build -project CaseNotes.xcodeproj -scheme CaseNotes \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Run unit tests

```bash
xcodebuild test -project CaseNotes.xcodeproj -scheme CaseNotes \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:CaseNotesTests
```

See [Testing and CI](testing-and-ci.md) for suite boundaries.
