# Architecture

CaseNotes is a small SwiftUI application over SwiftData models. Rules that can
be stated and tested independently live outside the views.

```text
CaseNotes/
  CaseNotesApp.swift    Application entry point and model container
  Models/               SwiftData models and the editing draft
  Logic/                Testable behavior without SwiftUI imports
  Views/                SwiftUI screens and platform adapters
  DesignSystem/         Shared theme and motion tokens
```

## State ownership

SwiftData owns persisted notes, folders, and drawing records. Views query or
receive those models and keep only transient interaction state locally.

`NoteDraft` is a value type that isolates text editing from the persistent
model. Directly binding controls to a SwiftData model would write changes
through immediately and make Cancel unreliable. The drawing editor follows the
same boundary by holding its live `PKCanvasView` until Done.

For relationship rules, migration coverage, and timestamp behavior, see
[SwiftData and Persistence](persistence.md). Authentication and scene lifecycle
behavior are documented separately in [App Lock and Privacy](app-lock-and-privacy.md).

## Logic boundaries

- `NoteOrganizer` owns scope filtering, search, pinning, and sorting.
- `MarkdownDocument` converts Markdown source into renderable blocks.
- `NoteExport` defines the exact text and file representation leaving the app.
- `AppLockController` owns authentication and scene lifecycle policy behind a
  `DeviceAuthenticator` protocol.

## Rendering work

Markdown parsing is retained in `MarkdownText` state and refreshed only when
the source changes. List previews parse only an opening fragment instead of an
entire long note. Folder scope counts are accumulated in one pass.

Drawing bytes use external SwiftData storage and are read only when the drawing
view or editor opens. Rasterization is keyed to the drawing edit timestamp so
unrelated view updates do not rebuild the image.
