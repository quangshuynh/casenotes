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
