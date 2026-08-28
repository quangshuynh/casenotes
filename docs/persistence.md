# SwiftData and Persistence

## Model container

The application container registers `Note`, `Folder`, `NoteDrawing`, and
`NoteRevision`. SwiftData owns persisted records while views keep transient
editing and presentation state locally.

## Relationships and deletion

A folder's notes relationship uses the `.nullify` delete rule. Deleting a
folder therefore keeps each note and leaves it Unfiled. A note's drawing
relationship uses `.cascade` because the drawing is owned content that should
not outlive its note.

A note's revisions relationship also uses `.cascade`. Version history describes
one note and is meaningless without it, so deleting a note deletes its history.
Deleting a folder nullifies its side of the note relationship and leaves both
the notes and their history in place.

PencilKit data is stored on `NoteDrawing` with `@Attribute(.externalStorage)`.
This keeps the large blob outside the main database file and lets list browsing
avoid loading it.

## Migration safety

Folders, drawings, and version history were each introduced as a new entity plus
a relationship on `Note`. These additive changes rely on automatic lightweight
migration, and no `VersionedSchema` or migration plan is declared.

Naming fewer models when opening a store does not produce an older schema, since
SwiftData registers every entity reachable through a relationship. The migration
test therefore writes its store through model declarations frozen at the
previous schema, then reopens the file with the model list the application
registers and verifies that notes, folders, and drawings survive and that
version history starts empty.

Future schema changes should include a persistence behavior test and a test that
reopens a store written with the previous schema.

## Timestamp semantics

`createdAt` records creation. `updatedAt` changes only when authored content
changes: title, body, event date, or drawing. Refiling is organization rather
than authorship, so it does not change the edit timestamp. Restoring a previous
version is an edit, so it moves `updatedAt` to the time of the restore.

A revision carries two dates. `updatedAt` is the note's edit timestamp while
that version was current, which is the date shown to the reader, and `capturedAt`
is when the version was replaced, which is what history is ordered by. Ties are
broken deterministically rather than left to relationship order.

These rules are centralized in the draft, history, and drawing persistence
helpers so views do not decide timestamp behavior independently.
