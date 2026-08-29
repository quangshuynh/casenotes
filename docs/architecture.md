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

Saving an existing note goes through `NoteHistory`, which keeps the version the
edit replaces before the draft is applied. Creating a note applies its draft
directly, since a new note has no earlier version to keep.

![Note editor showing the title and body fields, the Markdown hint, an enabled
event date, and the folder picker, with Cancel and Save in the navigation
bar](screenshots/note-editor-dark.png){ width="300" }

Nothing in that screen has reached the store yet. Cancel discards it, and Save
hands the finished draft to the caller.

For relationship rules, migration coverage, and timestamp behavior, see
[SwiftData and Persistence](persistence.md). Authentication and scene lifecycle
behavior are documented separately in [App Lock and Privacy](app-lock-and-privacy.md).

## Logic boundaries

- `NoteOrganizer` owns scope filtering, search, pinning, and sorting.
- `NoteHistory` owns version history: when a previous version is kept, the
  order history reads in, and what restoring one does.
- `MarkdownDocument` converts Markdown source into renderable blocks.
- `ListDateStyle` decides how much of a date a compact row spells out, and
  formats it for an injected calendar and locale.
- `NoteExport` defines the exact text and file representation leaving the app.
- `AppLockController` owns authentication and scene lifecycle policy behind a
  `DeviceAuthenticator` protocol.

## Rendering work

Markdown parsing is retained in `MarkdownText` state and refreshed only when
the source changes. List previews parse only an opening fragment instead of an
entire long note. Folder scope counts are accumulated in one pass.

The version history list uses the same plain-text preview strategy as the notes
list, so showing a long history parses no Markdown. A historical body is parsed
only when that version is opened. The library's Recent rows show a title and a
date only, so opening the app parses nothing.

Drawing bytes use external SwiftData storage and are read only when the drawing
view or editor opens. Rasterization is keyed to the drawing edit timestamp so
unrelated view updates do not rebuild the image.
