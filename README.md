# CaseNotes

[![CI](https://github.com/quangshuynh/casenotes/actions/workflows/ci.yml/badge.svg)](https://github.com/quangshuynh/casenotes/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange)](https://www.swift.org/)
[![Platform](https://img.shields.io/badge/platform-iOS-lightgrey)](https://developer.apple.com/ios/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A local-first notes app for iOS built with Swift, SwiftUI, and SwiftData.

CaseNotes is a native iOS project focused on practical note-taking, local persistence,
and learning Apple platform development through a small, intentionally scoped app.

## Implemented

- Create, edit, and delete notes
- Local persistence with SwiftData
- Native SwiftUI navigation and forms
- Empty-state handling
- Unit tests with Swift Testing
- GitHub Actions CI

## Planned

- Search and sorting
- Pinned notes
- Tags or lightweight organization
- Optional event dates
- Face ID, Touch ID, or device authentication as appropriate
- Plain-text or Markdown export with the native Share Sheet
- Accessibility and UI polish

## Tech

- Swift
- SwiftUI
- SwiftData
- Swift Testing
- Xcode
- GitHub Actions

## Development

Open `CaseNotes.xcodeproj` in Xcode and run the app with an iOS Simulator.

Run the unit tests in Xcode with `Command-U`, or from the command line with:

```bash
xcodebuild test \
  -project CaseNotes.xcodeproj \
  -scheme CaseNotes \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' \
  -only-testing:CaseNotesTests
```

CI runs the unit-test suite on pushes and pull requests targeting `main`.

## Status

Early development. Core note editing and local persistence are implemented. Organization,
privacy controls, export, and release polish are still planned.

## Privacy

CaseNotes is designed around local-first storage. The repository contains only application
source code and synthetic development data, never personal notes.

No claims are made that the current application is encrypted, zero-knowledge, or production-secure.

## License

[MIT](LICENSE)
