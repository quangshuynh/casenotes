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

The draft also carries the note's attachments, mixing files the note already has
with files the current edit has staged. An imported document is copied into a
staging directory rather than into the note's own storage, so the same Save and
Cancel boundary covers files as well as text.

Saving an existing note goes through `NoteHistory`, which keeps the version the
edit replaces before the draft is applied, and then through `NoteAttachments`,
which reconciles the files. They are separate calls because they answer
different rules: only authored text produces a version, while an attachment
change moves the edit timestamp without producing one. Creating a note applies
its draft directly, since a new note has no earlier version to keep.

![Note editor showing the title field, the body holding raw Markdown source,
the Markdown hint, the event date row, and the folder picker naming a nested
folder, with Cancel and Save in the navigation
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
- `AttachmentStore` owns attachment files: the directories they live in, how an
  imported document is staged and then committed, and how one is deleted. It
  knows nothing about notes.
- `NoteAttachments` owns the model rules around those files: display order, what
  a save does to the list, and what has to happen before a note is deleted. It
  reaches the file system only through the store.
- `AttachmentDescriptor` derives what a row says about a file: its type, its
  size, and the phrase a screen reader hears.
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

## Attachment storage

Attachment bytes are deliberately not held in SwiftData. A `NoteAttachment`
record carries metadata only, and the file lives in an `Attachments` directory
the application owns inside Application Support. Files are named after the
attachment's identity rather than after the document, which is what lets two
files that arrived under the same name coexist and removes any need to make a
user's file name safe for a path. The name the reader knows is kept as metadata.

No path is persisted. Sandbox locations change between installs, so the URL is
rebuilt from the store's directory and the recorded file name on every read, and
a recorded name that is not a single path component is refused rather than
resolved.

Importing copies the chosen file into a staging directory under the container's
temporary area. The copy takes security-scoped access and reads through
`NSFileCoordinator`, so a document owned by a file provider is copied in a
consistent state, and the content type is read from the file rather than
inferred from its name. Saving then moves the staged file into the attachments
directory, which is a rename inside one container rather than a copy that could
stop halfway. Cancelling deletes what the edit staged, and the whole staging
directory is cleared at launch so an interrupted edit leaves nothing behind.

Removal is ordered deliberately: the store is written before the bytes are
deleted. The two cannot be made one transaction, and this direction means an
interruption can only leave a file nothing points at, never a note listing an
attachment it cannot open.

Previewing uses `QLPreviewController` through a small representable. Quick Look
already reads every format the importer accepts, so no document renderer is
written here, and the preview is titled with the name the file arrived with
rather than the name it is stored under.

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
