# Working in this repository

Operating instructions for coding agents. Background on the project itself lives
in `CONTEXT.md`, an untracked local file; read it first when it is present.

## Build and test

Open `CaseNotes.xcodeproj` in Xcode, or from the command line:

```bash
# Build
xcodebuild build -project CaseNotes.xcodeproj -scheme CaseNotes \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# Unit tests, the suite CI gates on
xcodebuild test -project CaseNotes.xcodeproj -scheme CaseNotes \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:CaseNotesTests

# Everything, including the UI test
xcodebuild test -project CaseNotes.xcodeproj -scheme CaseNotes \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Requires Xcode 26.6 or newer. If `xcodebuild` reports that it requires Xcode
while command line tools are selected, prefix commands with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` rather than changing
the machine's global selection.

If a run fails with `Invalid device state`, reset the simulator with
`xcrun simctl shutdown all` and retry. That is environment noise, not a code
failure, and must not be reported as one.

## Layout

```
CaseNotes/Models/         SwiftData models and the editing draft
CaseNotes/Logic/          Testable behavior, no SwiftUI imports
CaseNotes/Views/          SwiftUI views
CaseNotes/DesignSystem/   Theme tokens
CaseNotesTests/           Swift Testing unit tests, one suite per area
CaseNotesUITests/         XCTest, deliberately minimal
```

The app target uses Xcode synchronized file groups. New files inside
`CaseNotes/` are picked up automatically, so **never hand-edit
`project.pbxproj`** to add sources.

## Coding standards

- Native Apple frameworks first. A third-party dependency needs a strong
  technical reason and explicit approval.
- Put stateable rules in `Logic/` where they can be tested, not inside views.
- Reach for `Theme` tokens rather than literal colors, spacing, or radii.
- Document declarations with `///` above them, using `- Parameters:`,
  `- Returns:`, and `- Throws:`. Explain intent, side effects, and constraints.
  Do not document `body`, generated conformances, or obvious initializers.
- Comments explain why. Delete comments that restate the code.
- **No em dashes** anywhere in code, comments, documentation, UI copy, commit
  messages, or release text.
- Every icon-only control needs an accessibility label. Use semantic fonts so
  Dynamic Type keeps working.

## Testing expectations

- Swift Testing (`@Test`, `#expect`, `#require`) for unit tests.
- Cover behavior, not rendering. New rules in `Logic/` arrive with tests.
- Persistence changes need a test using an in-memory `ModelContainer`, and schema
  changes need one that reopens a store written with the previous schema.
- Inject dates, locales, and time zones instead of depending on the machine's
  own. Formatted output must not vary by region.
- Add a UI test only when a unit test genuinely cannot give the same confidence.
- Never add a bypass of the app lock to make testing easier.

## Privacy rules

- Local-first is non-negotiable. Do not add networking, accounts, analytics,
  telemetry, advertising, or a cloud dependency.
- Never claim the app is encrypted, zero knowledge, or production-secure. The
  lock gates the interface, not the data at rest.
- Use synthetic content everywhere: tests, previews, fixtures, screenshots, docs,
  and commit history. Never real personal data.

## Before you finish

1. The build succeeds with no new warnings.
2. The unit suite passes in full.
3. `git diff` reviewed line by line, with no stray debug code, no leftover
   scaffolding, and no unrelated changes.
4. `git status` shows only files you meant to touch.
5. No em dashes anywhere:
   `grep -rn $'\u2014' CaseNotes CaseNotesTests CaseNotesUITests *.md`
   (the escape is used so this command does not match its own documentation)
6. Documentation and README still describe what the code actually does.

If verification was skipped or a step failed, say so plainly. Do not report work
as done when it is not.

## Git

- Small, coherent, commit-sized changes.
- Conventional commit subjects: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`,
  `chore:`.
- **Never commit and never push unless explicitly instructed.** Propose a message
  and stop.
- Do not rewrite history, force push, or discard uncommitted work that you did
  not create.
