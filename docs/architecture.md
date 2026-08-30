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
- `FolderHierarchy` owns the folder tree: ancestor and descendant traversal,
  display paths, which moves are legal, and what deleting a folder does to the
  folders and notes inside it. `FolderTree` beside it groups a fetched set of
  folders by parent in one pass, which is what browsing screens and destination
  pickers read instead of walking relationships per row.
- `NoteHistory` owns version history: when a previous version is kept, the
  order history reads in, and what restoring one does.
- `MarkdownDocument` converts Markdown source into renderable blocks, and
  divides those blocks into the regions read mode can fold.
- `ListDateStyle` decides how much of a date a compact row spells out, and
  formats it for an injected calendar and locale.
- `NoteExport` defines the exact text and file representation leaving the app.
- `NotePDFRenderer` lays a note out as a paginated PDF document, working from a
  value copy of the note's authored content rather than from any view.
- `AppLockController` owns authentication and scene lifecycle policy behind a
  `DeviceAuthenticator` protocol.

## Rendering work

Folder hierarchy is derived rather than stored. A location is built by walking
the parent chain when it is displayed, so renaming or moving a folder needs no
rewrite of anything beneath it and no path string can go stale.

Markdown parsing is retained in `MarkdownText` state and refreshed only when
the source changes. Section division happens once with the parse rather than on
demand, so folding a section costs a redraw and no reparsing. List previews
parse only an opening fragment instead of an entire long note. Folder scope
counts are accumulated in one pass, as is the grouping of folders by parent, so
a screen showing folders issues no fetch per row and counts no descendants.

The version history list uses the same plain-text preview strategy as the notes
list, so showing a long history parses no Markdown. A historical body is parsed
only when that version is opened. The library's Recent rows show a title and a
date only, so opening the app parses nothing.

Drawing bytes use external SwiftData storage and are read only when the drawing
view or editor opens. Rasterization is keyed to the drawing edit timestamp so
unrelated view updates do not rebuild the image.

## PDF generation

`NotePDFRenderer` builds a PDF with `UIGraphicsPDFRenderer` and typesets it with
Core Text, both first-party. Core Text lays each block into whatever height is
left on the page, reports how much of the block fitted, and the remainder
continues on the next page, which is how a long paragraph, list, or code block
crosses a boundary without losing a line at the seam. Text is drawn as text, so
a reader can select and search it; only a PencilKit drawing is rasterized.

Rendering never reads the reading view. It takes a `NotePDFRenderer.Content`
value holding the title, the optional event date, the body, and the drawing
bytes, and it parses the body with the same `MarkdownDocument` read mode uses.
Section folding lives in view state and has no route into the exporter.

Generation happens inside the share item's transfer representation, so it runs
when a destination is chosen rather than while the actions menu is on screen.
It runs on the main actor, because rasterizing a PencilKit drawing is not
documented as safe anywhere else and an export is one document on an explicit
user action.
