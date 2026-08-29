# Features

## Notes

Notes have a required nonblank title, Markdown body, creation and edit
timestamps, optional event date, pinned state, optional folder, and optional
drawing. Reading and editing are separate modes, so opening a note does not
modify it.

Editing uses an in-memory draft. Save applies the draft, while Cancel discards
it. Authored content changes update `updatedAt`; opening, closing, or moving a
note between folders does not.

The list supports title and body substring search, Last Updated and Date
Created ordering, and pinned-first grouping within either order. A strip above
the list states how many notes are showing and which ordering is active, and
opens the ordering menu in one tap.

Rows are compact: the title with its date alongside, then a short preview with
the folder the note is filed in when the list mixes folders. At accessibility
text sizes a row unstacks into plain lines so nothing is truncated.

![All Notes showing a pinned note above a more recently edited one, a note
marked as carrying a drawing, folder names, and an event date](screenshots/notes-dark.png){ width="300" }

## Collapsible sections

Read mode treats a Markdown thematic break as a divider that can fold the
content below it. Each divider owns the content up to the next divider, so
collapsing one leaves the rest of the note alone, and anything written above the
first divider always stays visible.

Collapsing changes what is on screen and nothing else. The stored Markdown is
untouched, the editor still shows every character including the breaks, the
note's edit time does not move, no version is recorded, and copying, sharing, or
exporting still carries the whole note. Sections start expanded every time a
note is opened, and the collapsed state is not saved.

See [Content and Export](content-and-export.md) for which Markdown counts as a
break.

## Version history

Saving a change to an existing note keeps the version it replaces. Version
History is reached from the note's toolbar menu, lists previous versions newest
first, and opens each one read only before anything is restored.

Restoring makes a previous version current and keeps the version that was
current until then, so a restore can itself be undone by restoring again.
Nothing is removed from history.

A version records the authored text of the note: title, body, and event date.
Creating a note records nothing, because there is no earlier state to recover.
Saving without a change, cancelling, moving a note between folders, pinning it,
and simply reading it all leave history untouched.

Drawings are current-state attachments rather than versioned content. Restoring
a previous version changes the text and leaves the note's drawing exactly as it
is.

## Library

The root screen is the workspace navigator. Library holds the All Notes and
Unfiled scopes, Folders holds the ones you made, and Recent lists the notes
edited most recently so current work is one tap away.

Creation is available without leaving the screen: the toolbar offers New Note
and New Folder, the Folders heading carries its own folder action, and a
folder's context menu can start a note already filed in it. Creating a note
while browsing a folder or an empty folder files it there.

## Folders

Folders can be created, renamed, and deleted. All Notes and Unfiled are explicit
browsing scopes. A note belongs to at most one folder. Folders do not nest.

Deleting a folder does not delete its notes. SwiftData nullifies the
relationship, and the confirmation explains that affected notes move to
Unfiled.

![Folder list showing the All Notes and Unfiled scopes above three folders, each
with a note count](screenshots/library-dark.png){ width="300" }

## Drawing

A note can hold one PencilKit drawing. The drawing editor owns an in-progress
canvas, so Cancel discards changes and Done saves them. Saving a cleared canvas
removes the drawing record. Merely opening a drawing does not rewrite it or
change the note timestamp.

![PencilKit canvas holding a sketch, with the system tool picker along the
bottom and Cancel, Clear, and Done in the navigation bar](screenshots/drawing-dark.png){ width="300" }

The canvas keeps a light paper ground in either app appearance, so ink looks the
same while it is drawn and while it is read.

## Sharing and export

- Copy Note places the rendered Markdown document on the pasteboard without
  the CaseNotes footer, so a note pasted into other writing carries no wording
  the user did not write.
- Share Note sends Markdown text through the system share sheet.
- Export Markdown File creates a `.md` document through `Transferable`.

Exports include the title, optional event date, and body. App bookkeeping such
as creation time, edit time, and pinned state is omitted. A text line indicates
that a drawing exists because the drawing itself is not embedded.
