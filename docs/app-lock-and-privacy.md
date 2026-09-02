# App Lock and Privacy

## Authentication policy

`AppLockController` requests LocalAuthentication policy
`deviceOwnerAuthentication`. Biometry may be offered when available, with the
device passcode as a system-controlled fallback.

Authentication is isolated behind the `DeviceAuthenticator` protocol. Unit
tests can therefore exercise lock policy without displaying the system prompt.

The app declares `NSFaceIDUsageDescription`, which iOS requires before an app
may use Face ID.

Only one prompt is raised at a time. The system authentication sheet moves the
scene out of the active phase and back into it, so the scene lifecycle can ask
to unlock while the prompt that caused the change is still showing. A request
made while an attempt is in flight is ignored rather than answered with a second
prompt.

## Scene lifecycle

The app locks when the scene becomes inactive or enters the background. When an
active scene returns, authentication is required before note content becomes
available again.

An opaque privacy cover is shown whenever the scene is not active so note
content is not exposed in an app-switcher snapshot. The cover appears
immediately and has no animation.

## Security boundary

The lock gates the interface. It does not encrypt the SwiftData store, add an
application encryption layer, or make the system zero knowledge. The project
has not undergone a security review and does not claim production security.

Data stays in the app container and may be included in normal device backups.
The application itself contains no networking, accounts, sync, analytics,
telemetry, advertising, or cloud service.

Attached files are part of that same boundary. Importing one copies it into a
directory the app owns inside the container, where it relies on the same
standard file protection as the store rather than on any encryption CaseNotes
adds. The lock gates the interface, not those files.

## Attachments and the document picker

Choosing a file opens the system document picker, and previewing one opens the
system document viewer. Both run inside the app rather than switching to another
app, so neither takes the scene out of the active phase and neither cancels the
lock. Leaving the app while a preview is open locks it exactly as leaving any
other screen does, and returning requires authenticating before the preview is
visible again.

An attachment is copied into the app rather than referenced where it was found,
so CaseNotes never holds a bookmark to a location outside its own container and
nothing it stores can reach back into the user's other files. Sharing or
printing a file from inside the preview is a system action the user takes, and
what happens to the file after that is outside the app's control.

## Exported files

Copying, sharing, and exporting a note as Markdown or as a PDF are explicit user
actions that move authored content out of the app. Exports carry the title, the
event date, and the body, and a PDF also carries the note's current drawing.
Creation and edit timestamps, folder membership, pinned state, and version
history are not included.

Attached files are not part of an export. A shared Markdown file or PDF carries
the note's writing and nothing the note points at.

An exported file is an ordinary document. It is not encrypted or password
protected, the app lock does not apply to it, and once it has been shared or
saved it is controlled by whatever destination the user chose rather than by
CaseNotes. Generation happens on the device, and nothing is uploaded: the file
is handed to the system share sheet, which is what decides where it goes.
