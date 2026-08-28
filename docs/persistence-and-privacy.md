# Persistence and Privacy

## SwiftData model

The application container registers `Note`, `Folder`, and `NoteDrawing`.

A folder's notes relationship uses the `.nullify` delete rule. Deleting a
folder therefore keeps each note and leaves it Unfiled. A note's drawing
relationship uses `.cascade` because the drawing is owned content that should
not outlive its note.

PencilKit data is stored on `NoteDrawing` with `@Attribute(.externalStorage)`.
This keeps the large blob outside the main database file and lets list browsing
avoid loading it.

## Schema evolution and timestamps

Folders and drawings were introduced as new entities with optional note
relationships. Tests create a store with the earlier note-only schema, reopen
it with the current schema, and verify that existing notes survive.

`createdAt` records creation. `updatedAt` changes only when authored content
changes: title, body, event date, or drawing. Refiling is organization rather
than authorship, so it does not change the edit timestamp.

## App lock

`AppLockController` requests LocalAuthentication policy
`deviceOwnerAuthentication`. Biometry may be offered when available, with the
device passcode as a system-controlled fallback.

The app locks when the scene becomes inactive or enters the background. An
opaque privacy cover is also shown whenever the scene is not active so note
content is not exposed in an app-switcher snapshot. That cover appears
immediately and has no animation.

## Security boundary

The lock gates the interface. It does not encrypt the SwiftData store, add an
application encryption layer, or make the system zero knowledge. The project
has not undergone a security review and does not claim production security.

Data stays in the app container and may be included in normal device backups.
The application itself contains no networking, accounts, sync, analytics,
telemetry, advertising, or cloud service.
