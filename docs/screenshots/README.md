# Screenshots

Captures used by the README and the documentation site. Every one shows the
application running in the iOS Simulator with synthetic note content.

| File | Screen | Referenced from |
| --- | --- | --- |
| `library-dark.png` | Library scopes, folders, and recent notes | [Features](../features.md) |
| `notes-dark.png` | All Notes, pinned note first | README, [Features](../features.md) |
| `note-markdown-dark.png` | Reading view with rendered Markdown | [Content and Export](../content-and-export.md) |
| `note-editor-dark.png` | Draft editor showing Markdown source and the folder picker | [Architecture](../architecture.md) |
| `drawing-dark.png` | PencilKit canvas with the system tool picker | [Features](../features.md) |

The `-dark` suffix records the app appearance. The drawing canvas is
deliberately light in both appearances, because PencilKit stores ink in the
color it was drawn in and a fixed paper ground keeps a sketch looking the same
while it is drawn and while it is read.

## Rules

- Synthetic content only. Never a real personal note, name, address, or case
  detail.
- Capture the running application. Do not draw a mockup, add a device frame,
  compose a marketing background, or annotate the image.
- Recapture rather than retouch when the interface changes.
- Keep the file names stable. A screenshot is replaced in place when the screen
  it shows changes, so no timestamp or device model belongs in a name.

## Recapturing

Requires macOS with Xcode. Build and install onto a booted iPhone 17 simulator,
then fix the appearance and status bar so a recapture matches the existing set:

```bash
xcrun simctl ui booted appearance dark
xcrun simctl status_bar booted override --time 9:41 \
  --batteryState charged --batteryLevel 100 \
  --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4
```

The app lock stands in front of every screen. On a simulator, enroll and match
biometry from the host rather than adding any bypass to the app:

```bash
xcrun simctl spawn booted notifyutil -s com.apple.BiometricKit.enrollmentChanged 1
xcrun simctl spawn booted notifyutil -p com.apple.BiometricKit.enrollmentChanged
xcrun simctl spawn booted notifyutil -p com.apple.BiometricKit_Sim.pearl.match
```

Then capture each screen at its stable name:

```bash
xcrun simctl io booted screenshot docs/screenshots/library-dark.png
```

Default Dynamic Type size, and no keyboard on screen. After recapturing, check
that every page referencing the image still describes what it shows.
