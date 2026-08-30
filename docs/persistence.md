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

`Folder` also relates to itself: an optional `parent` and a `children`
relationship inverse to it. A folder with no parent is a root folder, and the
library is the conceptual root rather than a stored record. `children` uses
`.nullify` as well, so a folder can never take an organization tree down with
it.

The product behavior goes further than that rule. `FolderHierarchy.delete`
moves the folder's direct children into its own parent before deleting it, so
they keep their place in the tree instead of scattering to the top level, and it
unfiles the folder's direct notes. Anything deeper is untouched.

SwiftData does not enforce that a self-referential relationship stays a tree: a
graph containing a cycle is accepted, saved, and reopened. The invariant is
therefore enforced in `FolderHierarchy`, which refuses to move a folder into
itself or into its own subtree, and every move in the app goes through it.
Traversal carries a visited guard so it terminates on malformed data regardless.

A note's revisions relationship also uses `.cascade`. Version history describes
one note and is meaningless without it, so deleting a note deletes its history.
Deleting a folder nullifies its side of the note relationship and leaves both
the notes and their history in place.

PencilKit data is stored on `NoteDrawing` with `@Attribute(.externalStorage)`.
This keeps the large blob outside the main database file and lets list browsing
avoid loading it.

## Migration safety

Folders, drawings, and version history were each introduced as a new entity plus
a relationship on `Note`. Nesting instead added two relationships to an existing
entity. All of these are additive changes that rely on automatic lightweight
migration, and no `VersionedSchema` or migration plan is declared.

Naming fewer models when opening a store does not produce an older schema, since
SwiftData registers every entity reachable through a relationship. A migration
test therefore writes its store through model declarations frozen at the
previous schema, then reopens the file with the model list the application
registers.

Two such frozen declarations exist, one for each schema change they describe.
`PreRevisionSchema` predates version history. `PreNestedFolderSchema` predates
nesting, and its `Folder` has no way to sit inside another, which is what makes
the test meaningful: writing the fixture with today's `Folder` would produce the
new schema and prove nothing. Reopening that store shows that every folder
survives as a root folder, that note filing survives exactly, that unfiled notes
stay unfiled, that drawings and revisions come across, that authored text and
timestamps are unchanged, and that the resulting hierarchy is cycle free.

Future schema changes should include a persistence behavior test and a test that
reopens a store written with the previous schema.

## Timestamp semantics

`createdAt` records creation. `updatedAt` changes only when authored content
changes: title, body, event date, or drawing. Organization is not authorship, so
none of it moves the edit timestamp: refiling a note, moving a folder, renaming
an ancestor, and having a folder deleted out from under a note all leave the
note exactly as it was, and none of them writes a revision. Restoring a previous
version is an edit, so it moves `updatedAt` to the time of the restore.

A revision carries two dates. `updatedAt` is the note's edit timestamp while
that version was current, which is the date shown to the reader, and `capturedAt`
is when the version was replaced, which is what history is ordered by. Ties are
broken deterministically rather than left to relationship order.

These rules are centralized in the draft, history, and drawing persistence
helpers so views do not decide timestamp behavior independently.
