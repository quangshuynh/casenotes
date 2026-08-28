# CaseNotes documentation

<p class="casenotes-logo">
  <img src="images/casenotes-logo.png" alt="CaseNotes app icon" width="112">
</p>

CaseNotes is a local-first notes app for iOS. It uses SwiftUI and SwiftData for
the core experience, Markdown for structured writing, PencilKit for sketches,
and LocalAuthentication to gate the interface.

The application uses first-party Apple frameworks only. It contains no
networking, account system, analytics, telemetry, advertising, or cloud
dependency.

## What is implemented

- Create, read, edit, pin, search, sort, and delete notes
- Organize notes into flat folders or leave them Unfiled
- Render Markdown in a dedicated reading view
- Attach one PencilKit drawing to a note
- Copy, share, or export Markdown text
- Require device-owner authentication before showing note content
- Cover the interface immediately outside the active scene phase

Start with [Getting Started](getting-started.md), explore the user-facing
[Features](features.md), or read the [Architecture](architecture.md) overview.

## Project position

CaseNotes is a focused portfolio and learning project. Its core feature set is
implemented and tested, but it has not been submitted to the App Store or
through a security review. The [limitations](limitations.md) page records what
the app intentionally does not support.
