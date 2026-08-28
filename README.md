# CaseNotes

[![CI](https://github.com/quangshuynh/casenotes/actions/workflows/ci.yml/badge.svg)](https://github.com/quangshuynh/casenotes/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/badge/Swift-SwiftUI-orange)](https://www.swift.org/)
[![Platform](https://img.shields.io/badge/platform-iOS%2026.5%2B-lightgrey)](https://developer.apple.com/ios/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A local-first notes app for iOS, built with SwiftUI, SwiftData, and first-party
Apple frameworks only.

CaseNotes is written for long-form personal note taking: folders for
organization, Markdown for structure, PencilKit for sketches, and device
authentication in front of all of it. Notes are stored on the device. There are
no accounts, no servers, and no analytics.

The project is also a portfolio and learning repository, so implementation
quality, native platform conventions, and test coverage are treated as part of
the deliverable rather than as an afterthought.

## Screenshots

Screenshots are kept in [`docs/screenshots`](docs/screenshots), which documents
the intended set and the rule that captures use synthetic content only.

## Features

**Notes**

- Create, read, edit, and delete notes backed by SwiftData
- A reading view separate from editing, so opening a note cannot change it
- Draft based editing with explicit Save and Cancel, plus a discard confirmation
  for unsaved changes
- Optional event date, recorded separately from when the note was written
- Pinned notes, which sort first inside every folder
- Search across titles and bodies, scoped to whatever is being browsed
- Sort by last updated or date created

**Markdown**

- Note bodies are written and stored as Markdown source
- Reading mode renders headings, bold, italic, inline code, links, ordered and
  unordered lists with nesting, block quotes, fenced code blocks, and thematic
  breaks
- Parsing uses Foundation's `AttributedString` Markdown support, with block
  structure recovered from `PresentationIntent`
- Hand written line breaks are preserved rather than reflowed, so plain prose
  still reads the way it was typed
- Malformed Markdown renders as text instead of failing

**Folders**

- Create, rename, and delete folders
- Notes may be filed or left unfiled, and Unfiled is a real browsing scope
- Deleting a folder keeps its notes and moves them to Unfiled, which the
  confirmation states plainly
- Move notes between folders from the editor or from a context menu in the list
- Live note counts per scope

**Drawings**

- Attach one optional PencilKit drawing per note
- Finger and Apple Pencil input, with the system tool picker
- Drawings are stored outside the database with `externalStorage` and are not
  loaded while browsing lists
- Clearing the canvas and confirming removes the drawing from the note

**Sharing and export**

- Copy Note places the Markdown source on the pasteboard with no added wording
- Share Note sends Markdown text through the system share sheet
- Export Markdown File produces a real `.md` document using `Transferable`
- Exports carry the title, the event date when present, and the body, and
  nothing else

**Privacy and platform**

- Device authentication with Face ID, Touch ID, or passcode in front of the app
- The interface is covered whenever the app leaves the foreground, so notes do
  not appear in the app switcher
- Dark first warm visual design that also supports light appearance
- Dynamic Type throughout, and VoiceOver labels on every icon only control

## Privacy

CaseNotes is local-first. Notes, folders, and drawings are written to the app's
own SwiftData store on the device. The app has no network code, no accounts, no
analytics, no telemetry, no advertising, and no cloud dependency.

**What the app lock does and does not do.** Unlocking uses LocalAuthentication
with `deviceOwnerAuthentication`, so biometry is offered where available and the
device passcode always works as a fallback. The lock gates the interface: it
decides when notes may be displayed. It is not encryption. Data at rest is
covered by the standard iOS file protection that applies to any app container on
a device with a passcode, and CaseNotes adds no encryption layer of its own.

CaseNotes is therefore **not** encrypted by the app, not zero knowledge, and has
not been through a security review. It should not be described as any of those
things.

Exports contain only what the user wrote. Creation and edit timestamps and
pinned state are app bookkeeping and are deliberately left out. A note holding a
drawing says so in one line, since a text export cannot carry the sketch.

The repository contains application source and synthetic sample content only.

## Architecture

SwiftUI views over SwiftData models, with the rules worth testing pulled out of
the views.

```
CaseNotes/
  CaseNotesApp.swift    App entry point and model container
  Models/               SwiftData models and the editing draft
  Logic/                Behavior with no SwiftUI dependency
  Views/                SwiftUI views
  DesignSystem/         Colors, spacing, and corner radii
```

`Logic/` is defined by a property rather than by taste: nothing in it imports
SwiftUI, and all of it is unit tested.

- `NoteOrganizer` decides what a scope shows and in what order, so filtering,
  search, pinning, and sorting are testable without a UI
- `MarkdownDocument` turns Markdown source into renderable blocks
- `NoteExport` produces the exact text that leaves the app
- `AppLock` holds the lock policy behind a `DeviceAuthenticator` protocol, so the
  privacy behavior can be tested without the system authentication sheet

**Data model.** A `Note` has a title, a Markdown body, created and updated dates,
a pinned flag, an optional event date, an optional `Folder`, and an optional
`NoteDrawing`.

Two relationship decisions carry weight:

- `Folder.notes` uses `.nullify`, so deleting a folder never deletes writing. The
  notes survive and become unfiled.
- `Note.drawing` uses `.cascade`, because a drawing is part of the note rather
  than a place it lives. It also keeps large drawing data out of list rendering.

**Editing.** Editing a SwiftData model directly writes straight to the store,
which leaves no way to abandon an edit. Editing therefore happens on a
`NoteDraft` value that is applied only on save. A note's `updatedAt` moves when
its authored content changes and not when it is merely read, and not when it is
refiled, since filing organizes a note rather than rewrites it.

**Schema evolution.** Folders and drawings were both added as new entities plus
optional properties, which SwiftData migrates automatically. A test writes a
store using the older schema, reopens it with the current schema, and asserts the
existing notes survive.

## Tech Stack

- Swift and SwiftUI
- SwiftData for persistence
- Swift Testing for unit tests, XCTest for UI tests
- PencilKit for drawings
- LocalAuthentication for the app lock
- Foundation `AttributedString` for Markdown parsing
- CoreTransferable and UniformTypeIdentifiers for file export
- GitHub Actions for CI

**No third-party dependencies.** The project declares no Swift packages and
vendors no code.

## Development

Requirements:

- Xcode 26.6 or newer
- iOS 26.5 deployment target
- iPhone or iPad simulator, or a device for Apple Pencil and biometry testing

Open `CaseNotes.xcodeproj` and run. Nothing needs fetching or generating first.

The project uses Xcode's synchronized file groups, so new source files added
inside `CaseNotes/` are picked up automatically without editing
`project.pbxproj`.

To build from the command line:

```bash
xcodebuild build -project CaseNotes.xcodeproj -scheme CaseNotes -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Testing

Run the unit tests in Xcode with `Command-U`, or from the command line:

```bash
xcodebuild test -project CaseNotes.xcodeproj -scheme CaseNotes -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:CaseNotesTests
```

94 unit tests cover the parts of the app where behavior can be stated precisely:

| Suite | Covers |
| --- | --- |
| `NoteTests` | Model defaults, persistence, schema migration |
| `NoteDraftTests` | What counts as an edit, Cancel semantics, timestamp rules |
| `NoteOrganizerTests` | Scopes, search, pinning, sort orders |
| `MarkdownDocumentTests` | Block parsing, line breaks, malformed input |
| `NoteExportTests` | Exact export text, file naming, excluded metadata |
| `FolderTests` | Relationships, moving, and folder deletion keeping notes |
| `NoteDrawingTests` | Serialization, attach and clear, cascade deletion |
| `AppLockControllerTests` | Lock policy across authentication and scene phases |

UI tests are deliberately minimal. One end-to-end test asserts that a launched
app shows the lock screen and that no note content is reachable before
authenticating, which is the one thing unit tests cannot check. Everything else
is covered faster and more reliably at the unit level.

To run every test including UI tests:

```bash
xcodebuild test -project CaseNotes.xcodeproj -scheme CaseNotes -destination 'platform=iOS Simulator,name=iPhone 17'
```

## CI

[GitHub Actions](.github/workflows/ci.yml) runs on pushes and pull requests
targeting `main`, using a `macos-26` runner with Xcode 26.6 and an iPhone 17
simulator on iOS 26.5.

CI runs the unit test suite only. UI tests depend on simulator launch behavior
that is prone to unrelated flakiness, so they are kept as a local check rather
than a merge gate.

## Project Status

Working and feature complete for its intended scope. Notes, folders, Markdown,
sharing and export, drawings, and the app lock are all implemented and tested.
It has not been submitted to the App Store.

## Current Limitations

- The app lock gates the interface. It does not encrypt the store, and the app
  adds no encryption of its own.
- No sync and no iCloud. Notes exist on one device, and survive only through the
  device's own backups.
- Drawings are not included in exports. A note holding one says so in its export.
- One drawing per note.
- Folders do not nest, and a note belongs to at most one folder.
- On iPad the app uses single column navigation rather than a folder sidebar.
- Import is not implemented. Markdown can leave the app but cannot be brought in.
- Search matches plain substrings, without tokenization or ranking.

## Roadmap

Meaningful work that remains, roughly in order of value:

- An iPad layout with a persistent folder sidebar
- Including drawings in exports, as an image alongside the Markdown
- Importing `.md` files into notes
- Nested folders or tags, whichever proves more useful in practice

## License

[MIT](LICENSE)
