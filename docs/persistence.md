# SwiftData and Persistence

## Model container

The application container registers `Note`, `Folder`, and `NoteDrawing`.
SwiftData owns persisted records while views keep transient editing and
presentation state locally.

## Relationships and deletion

A folder's notes relationship uses the `.nullify` delete rule. Deleting a
folder therefore keeps each note and leaves it Unfiled. A note's drawing
relationship uses `.cascade` because the drawing is owned content that should
not outlive its note.

PencilKit data is stored on `NoteDrawing` with `@Attribute(.externalStorage)`.
This keeps the large blob outside the main database file and lets list browsing
avoid loading it.

## Migration safety

Folders and drawings were introduced as new entities with optional note
relationships. Tests create a store with the earlier note-only schema, reopen
it with the current schema, and verify that existing notes survive.

Future schema changes should include a persistence behavior test and a test
that reopens a store written with the previous schema.

## Timestamp semantics

`createdAt` records creation. `updatedAt` changes only when authored content
changes: title, body, event date, or drawing. Refiling is organization rather
than authorship, so it does not change the edit timestamp.

These rules are centralized in the draft and drawing persistence helpers so
views do not decide timestamp behavior independently.
