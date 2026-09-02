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

Run Apple-only commands only on macOS. On Windows, perform the checks the
environment supports and state which Xcode or Simulator checks still need to be
run on a Mac. Never imply that an Apple-only check ran on Windows.

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

## Interface conventions

The browsing screens are a workspace, not a card gallery. Rows sit flat on the
canvas and are separated by hairlines, grouped by quiet capitalized section
headers, and reached through plain `NavigationStack` pushes. Reach for
`workspaceList()` and `workspaceRow()` rather than restyling a list per screen,
and keep cards for the editor, where a distinct surface is the point.

- Density never costs a target. Rows keep the stated minimum height, symbol
  columns scale with `@ScaledMetric`, and any row that pairs a title with a
  trailing date unstacks at accessibility text sizes.
- Folder rows carry hierarchy through navigation, not through an expanded tree.
  A screen lists one level, and indentation appears only in a destination
  picker, where a written path states the same structure beside it.
- Note creation goes through `NoteDraft.insertNote(into:at:using:)` wherever it
  is offered, which is what keeps a new note's first save out of version history
  and what saves the files a new note was composed with.
- Visual work must not change Save and Cancel, authored timestamps, or version
  history semantics.

## Testing expectations

- Swift Testing (`@Test`, `#expect`, `#require`) for unit tests.
- Cover behavior, not rendering. New rules in `Logic/` arrive with tests.
- Persistence changes need a test using an in-memory `ModelContainer`, and schema
  changes need one that reopens a store written with the previous schema.
- Inject dates, locales, and time zones instead of depending on the machine's
  own. Formatted output must not vary by region.
- Add a UI test only when a unit test genuinely cannot give the same confidence.
- Never add a bypass of the app lock to make testing easier.

## Folder hierarchy invariants

Folders form a tree, and organizing notes never edits them:

- Folders are a cycle-free parent and child tree. A root folder has a `nil`
  parent, and the library is the conceptual root: no stored record stands in
  for it.
- SwiftData will persist a self-referential graph that is not a tree, so the
  invariant lives in `FolderHierarchy`. Every move goes through it, a move into
  the folder itself or into its own subtree is refused, and hiding a
  destination in the interface is never the safeguard. Traversal keeps a visited
  guard so it terminates on malformed data.
- Deleting a folder deletes nothing else. Its direct notes become Unfiled, its
  direct children move into its own parent, and anything deeper is untouched.
  Never cascade notes or descendant folders.
- A note belongs to exactly one folder or to none, at any depth. Unfiled means
  `folder == nil` and nesting does not change that. All Notes stays global.
- Hierarchy is derived, never stored as a path string. Display paths are built
  by walking parents, so a rename or a move needs no rewrite beneath it.
- Counts and browsing are direct membership. A folder row counts the notes
  filed in that folder, which is the same set opening it shows.
- Hierarchy changes are organization: moving, renaming, creating, or deleting a
  folder must never touch a note's authored content, `updatedAt`, or version
  history.
- A schema change to `Folder` needs a migration test written through a genuinely
  frozen prior schema. `CaseNotesTests/PreNestedFolderSchema.swift` is frozen at
  the flat-folder models and must not gain properties.
  `CaseNotesTests/PreAttachmentSchema.swift` is frozen at the models as they
  stood before a note could carry a file, for the same reason.

## Markdown folding invariants

Read mode folds a note at its thematic breaks. These are behavior:

- Folding is read-mode presentation. Stored Markdown is never rewritten, no
  marker is injected, and no fold state is persisted.
- A break owns the content after it until the next break or the end of the note.
  Content before the first break is always visible and has no control.
- Boundaries come from the parsed `.thematicBreak` blocks, never from matching
  lines of source text. A rule inside fenced or indented code is code, and
  `Heading` over dashes is a setext heading.
- Every spelling the parser accepts as a break folds alike.
- Collapsing must not touch `updatedAt`, write a `NoteRevision`, or reach the
  model at all.
- The editor always exposes the complete source, so native selection and Select
  All keep covering the whole note.
- Copy, share, and export always use the full body.

## Export invariants

A note leaves the app as authored content and nothing else. These hold for both
export formats:

- Markdown export is the source. PDF export is presentation. Neither replaces
  the other, and the PDF never shows raw Markdown syntax.
- A PDF carries the complete note body. Read-mode collapse state is view state
  and has no route into an exporter, so folding never changes a file.
- Title, event date, and body are exported. Timestamps, pinned state, folder,
  version history, and attached files are not.
- A PDF includes the note's current drawing. That does not change version
  history, which still records authored text only.
- A drawing that is empty or whose bytes no longer decode is omitted, and the
  note's text still exports. Corrupt drawing data must never block an export.
- Never rasterize a note into a PDF. The page is typeset so its text stays
  selectable, searchable, and printable; only the drawing is an image.
- Generated PDFs are not persisted. No SwiftData model, no export history, and
  no cached file in the note store.
- Filenames come from `NoteExport.fileBaseName(for:)`. There is one
  sanitization policy, and formats differ only by extension.
- Exported files are not encrypted or password protected, and documentation must
  not imply otherwise.

## Attachment invariants

A note can keep local files. These rules are behavior, and tests protect them:

- Bytes are not in SwiftData. `NoteAttachment` is metadata, and the file lives
  in the application's own `Attachments` directory, which `AttachmentStore`
  owns. No path is persisted: the URL is rebuilt from the directory and the
  stored file name, and a name that is not a single path component addresses
  nothing.
- A file is stored under its attachment's identity, never under the name it
  arrived with. That is what lets two files called the same thing coexist, and
  it is why the original name is display metadata rather than the file's
  identity.
- Importing stages. A chosen file is copied into a staging directory, and
  nothing about the note or its permanent storage changes until Save. Cancel
  deletes what the edit staged, including for a note that was never created,
  and leaves a file the edit had only marked for removal in place.
- Content type comes from the file, not from its name. Security-scoped access
  and a coordinated read are taken for anything outside the container, and an
  unsupported, empty, or unreadable file is refused with a message rather than
  attached.
- `Note.attachments` cascades, and a cascade removes records only. Deleting a
  note goes through `NoteAttachments.delete(_:in:using:)` so the bytes go too.
  Deleting a folder deletes no note and must therefore reach no attachment.
- Records are written before bytes are deleted. The order is the whole
  guarantee: an interruption may leave a file nothing points at, never a note
  listing an attachment it cannot open.
- Attaching or removing a file moves `updatedAt` and writes no `NoteRevision`.
  Opening or previewing one changes nothing at all.
- A missing or corrupt file costs that file. The note still reads, the row says
  the file is missing, and it can still be removed.
- Attachments are structured relationships. Never inject a link into the stored
  Markdown, never rewrite the body when the list changes, and never put an
  attachment into an export.
- Previewing is Quick Look. Do not write a renderer for any attached format.

## Version history invariants

Notes keep previous authored states as `NoteRevision` records. These rules are
behavior, not implementation detail, and tests exist to protect them:

- A revision is written only when a save or a restore actually changes authored
  content: title, body, or event date. Filing, pinning, drawing edits, opening a
  note, and cancelling an edit never write one.
- Saving a new note writes no revision. There is no earlier state to recover, so
  history stays empty until the first later edit.
- A revision holds the state being replaced, not the state being written. The
  note itself is always the newest version.
- Restoring keeps the current state as a revision first, then applies the older
  one. Nothing is deleted from history, and restoring a state the note already
  matches does nothing.
- `Note.revisions` cascades. Deleting a note deletes its history, while deleting
  a folder nullifies filing and touches neither notes nor their history.
- History order is established by `NoteHistory`, never by relationship order.

Changing the revision model, its relationship, or these rules means changing the
schema. Review migration behavior and keep the pre-revision migration test in
`CaseNotesTests/PreRevisionSchema.swift` frozen at the schema it describes.

## Privacy rules

- Local-first is non-negotiable. Do not add networking, accounts, analytics,
  telemetry, advertising, or a cloud dependency.
- Never claim the app is encrypted, zero knowledge, or production-secure. The
  lock gates the interface, not the data at rest.
- Use synthetic content everywhere: tests, previews, fixtures, screenshots, docs,
  and commit history. Never real personal data.
- Version history is a recovery feature. Never describe it as an audit log,
  tamper evident, immutable, or a record of provenance.

## Keep support files synchronized

An implementation slice includes every test, document, and configuration change
needed to keep the repository accurate. After changing implementation, review
the impact on:

- unit, UI, persistence, and migration tests
- README, documentation pages, MkDocs navigation, limitations, project status,
  roadmap material, and development instructions
- screenshots and screenshot references
- `AGENTS.md`, `CLAUDE.md`, comments, and public API documentation
- `.gitignore`, GitHub Actions, Xcode project configuration, and shared schemes
- accessibility behavior and documentation
- privacy and security wording, especially after changes to authentication,
  lifecycle handling, persistence, exports, sharing, clipboard use, drawings,
  or files

This is an impact review, not a requirement to edit every listed file. Leave
accurate files alone and avoid documentation churn for internal refactors that
do not change meaningful behavior or architecture. Search for stale terminology
and contradictory descriptions before finishing.

When a feature becomes implemented, remove it from limitations or planned-work
material and document the implemented behavior. If a visible UI change makes a
public screenshot materially inaccurate, flag the exact screen and state that
needs recapturing. Do not fabricate a replacement, and use synthetic content
only.

Treat every `@Model` change as a schema change. Review existing stores,
declaration-level defaults, optionality, relationships, delete rules, and
migration behavior. Add behavioral coverage without weakening existing tests or
adding tests solely to increase a count. Document a test count only after
verifying it.

## Before you finish

1. Review the implementation's repository-wide impact using the checklist above.
2. The build succeeds with no new warnings where the environment supports it.
3. Affected tests pass, including the full unit suite for application changes.
4. Documentation builds when documentation or its configuration changed.
5. Internal documentation links pass when relevant.
6. `git diff` reviewed line by line, with no stray debug code, no leftover
   scaffolding, and no unrelated changes.
7. `git status` shows only files you meant to touch, with no generated or
   machine-specific files.
8. No em dashes anywhere:
   `grep -rn $'\u2014' CaseNotes CaseNotesTests CaseNotesUITests *.md`
   (the escape is used so this command does not match its own documentation)
9. Documentation and README still describe what the code actually does.
10. No real personal or private content was introduced.

If verification was skipped or a step failed, say so plainly. Do not report work
as done when it is not.

For an implementation slice, the final report states:

1. implementation changes
2. tests added or updated
3. documentation updated
4. configuration or CI updated
5. screenshots needing recapture
6. files changed
7. verification performed and results
8. manual verification still required
9. intentionally unchanged related files and why
10. migration or persistence implications
11. privacy or accessibility implications
12. a suggested conventional commit message

## Git

- Small, coherent, commit-sized changes.
- Conventional commit subjects: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`,
  `chore:`.
- **Never commit and never push unless explicitly instructed.** Propose a message
  and stop.
- Do not rewrite history, force push, or discard uncommitted work that you did
  not create.
