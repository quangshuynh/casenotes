# Guidance for Claude

Read [AGENTS.md](AGENTS.md) for commands, standards, and the pre-finish
checklist. This file covers judgment: how to decide, not what to type.

`CONTEXT.md` carries the background on what this project is and why it is built
the way it is. It is deliberately untracked, so read it when the working copy has
it and do not treat its absence as a problem.

## Inspect before changing

Read the surrounding code first. This repository has deliberate decisions behind
unusual-looking choices, and most of them are recorded in CONTEXT.md. If
something looks wrong, check there before rewriting it.

Match the conventions already present rather than importing habits from
elsewhere.

## Preserve what works

Working architecture stays unless there is a stated reason to change it. Refactor
when it solves a real problem, not for symmetry, and do not add layers that only
look professional. Preserve existing behavior unless changing it is the point of
the task.

Scope is the deliverable. Do not quietly widen a task, and do not narrow one
either. If part of it turns out to be a bad idea, say so and then finish the
rest.

## Verify, do not assume

Use the verification the current environment supports. On macOS, build the app,
run the tests, and inspect relevant behavior in Simulator. On Windows, do not
claim or recommend running Apple-only tools; report the Mac checks that remain.
Several defects in this codebase were found only by taking a screenshot: ink
rendering white in dark mode, a title vanishing in a collapsed split view, and a
badge landing on the wrong side of a chevron.

When platform behavior is unclear, write a throwaway probe and read the real
answer instead of guessing. Delete the probe afterwards.

Report outcomes honestly. If tests fail, show the failure. If something was not
verified, say which part.

## Non-negotiables

- Native Apple frameworks first. No new dependencies without a strong reason.
  Attached files are previewed with Quick Look, never with a renderer of ours.
- Local-first. No networking, accounts, analytics, telemetry, or cloud.
- No unsupported security claims. The app lock gates the interface, not the data.
- Synthetic content only. Never real personal data anywhere, including history.
- No em dashes in anything the repository contains.

## Swift and SwiftUI conventions

Follow the patterns already established: SwiftData models in `Models/`, testable
rules in `Logic/`, thin views that receive their inputs, `Theme` tokens instead
of literals, and `///` documentation above declarations that explains intent
rather than restating signatures. AGENTS.md has the specifics.

Persistence changes deserve extra care. Think through delete rules and schema
compatibility before writing code, and prove the result with a test.

## Interface work

The browsing surfaces were redesigned into a warm dark workspace. Obsidian was
a reference for density and hierarchy only. Do not copy its layout, icons, or
chrome, and never describe CaseNotes as Obsidian-like. The identity is the warm
palette already in the asset catalog, reached through `Theme`.

- Prefer flat rows, hairlines, and quiet section headers over cards. The editor
  keeps its raised surfaces on purpose, because read and write modes should not
  look the same.
- Extend the existing semantic tokens before adding new ones, and never restate
  a color in a view.
- Visuals must not imply persistence the model does not have. Folders nest, so
  a folder screen lists one level and pushes; no inline expanded tree.
- A redesign is not a licence to add persisted state. No `@Model` change and no
  new stored setting belongs in a visual slice.
- Screenshot the result in Simulator. Two defects in this pass were only visible
  that way: a plain list footer drawing black instead of the canvas, and a fixed
  symbol column overlapping its label at accessibility text sizes.
- After a UI change, check `docs/`, the README, and the screenshots before
  calling it done.

## Nested folders

Folders are a real persisted tree. Constraints when touching them:

- Validate moves in `FolderHierarchy`, never only by what the picker offers. A
  folder may not move into itself or into its own subtree.
- Deleting a folder promotes its direct children to its parent and unfiles its
  direct notes. Never cascade notes or descendant folders.
- Counts and folder screens are direct membership only. Do not aggregate
  descendants without saying so in the interface and the docs.
- Group folders once per screen with `FolderTree`. No per-row relationship walk
  and no fetch per row.
- No persisted path strings. Build a location from the parent chain.
- Hierarchy work never writes a `NoteRevision` or moves `updatedAt`, and never
  changes draft, history, or export semantics.
- A `Folder` schema change extends the frozen `PreNestedFolderSchema` approach
  rather than reusing current models for the fixture.
- No drag and drop and no manual ordering in this slice.

## Markdown folding

Read mode folds sections at thematic breaks. Constraints when touching it:

- Never implement a boundary by splitting raw source on a line of dashes. Divide
  the parsed blocks, and check the fenced-code, indented-code, and setext-heading
  cases before believing a change is correct.
- Reuse the existing parser and renderer. The section mechanism sits around
  `MarkdownDocument` and `MarkdownText`, not inside a new one.
- Folding must not reach the model: no `updatedAt` move, no revision, no schema
  change, no stored preference. Persisted fold state needs explicit scope.
- Leave the editor alone. The full source stays visible and natively selectable,
  which rules out building folding into the editable text control.

## Markdown modes

Reading, Live Preview, and Source are three views of one stored string.
Constraints when touching them:

- Source stays canonical. No WYSIWYG storage, no HTML, no second editable copy,
  and no rewriting of a user's Markdown behind their back.
- Region boundaries come from `MarkdownSourceMap`, which proves each candidate
  against the existing parse. Do not split the source on newlines, and do not
  add a second parser or a third-party engine.
- Live Preview edits `NoteDraft`. It must not bind to SwiftData, must not
  autosave, and must not write a revision or move `updatedAt`. Mode switching
  changes nothing at all.
- The mode is ephemeral. Persisting it needs a preference mechanism this app
  does not have and should not gain for a display choice.
- Keep the UIKit bridge narrow: one `UITextView`, one region, plain source. Any
  reshaping of what it holds happens in the same event that caused it, because
  pushing text on a later redraw loses keystrokes under fast typing. That was
  found by typing into a long note, not by reading the code.
- Do not disable autocorrection to make `---` easier to type. The smart-dash
  finding in CONTEXT.md is still a product call and still out of scope.

## Attachments

A note owns local files. `AttachmentStore` in `Logic/` owns the file system and
knows nothing about notes; `NoteAttachments` beside it owns the model rules and
reaches the file system only through the store. Constraints when touching them:

- Never put attachment bytes in SwiftData, and never persist a path. A stored
  file is named after the attachment's identity and found by rebuilding its URL.
- Importing stages into a temporary directory. Cancel has to undo the import as
  well as the list, and Save is a move inside the container rather than a copy
  that can stop halfway.
- Ask the file what it is. A name is display metadata; the content type decides
  whether a file is accepted and what extension it is stored under.
- Order removals: write the store, then delete the bytes. A record without a
  file is visible breakage; a file without a record is invisible. This was found
  by running it, not by reading the code.
- Attaching or removing moves `updatedAt` and writes no revision. Previewing
  writes nothing. Deleting a note must clear its files; deleting a folder must
  not.
- Quick Look is the viewer. Do not write a renderer for PDF, DOCX, or anything
  else, and do not let an attachment into an export or into the Markdown body.
- One bad attachment must never cost the note. Missing bytes are a row that says
  so, not a blank screen.

## Inline attachments

A note's own file can be placed inside its Markdown. `InlineAttachmentMarker`
owns the syntax, `InlineAttachments` owns the body rewrites, and
`InlineAttachmentSource` answers what a reference refers to. Constraints when
touching them:

- A placement is a reference by identity. Never write a file name, a path, or a
  display name into the body, and never copy a file to place it.
- Never decide a placement from the parsed text. Foundation discards the
  difference between a written reference and an escaped one, so a candidate line
  is proved against the whole-document parse in `MarkdownDocument`, exactly as
  `MarkdownSourceMap` proves a boundary.
- Do not add a second parser, and do not split the source on newlines. A refused
  candidate stays literal text and must not disable the placements around it.
- Rewrites go through the source map's span replacement. Nothing is normalized,
  trimmed, or reflowed, and a fence is never cut open by an insertion.
- Blocks, not layout. No floating, no wrapping, no resize handles, no arbitrary
  positions. Movement is a block at a time and is offered as named controls so
  it works for VoiceOver and Switch Control, not only as a drag.
- Removing a reference and deleting a file are different actions, and only the
  second one destroys anything. Never rewrite authored text to tidy up a stale
  reference.
- Placement is authored text, so draft, timestamp, and history semantics follow
  with no new rule and no schema change.
- The keystroke path stays clean: resolution is rebuilt when the list of files
  changes rather than per redraw, the environment value handed to the rendered
  body is state rather than a value recomputed each update, and images are
  decoded off the main actor at a bounded size and cached by identity.
- A form row routes plain buttons in it to one target, so controls inside live
  preview are borderless. That was found by tapping them.

## PDF export

`NotePDFRenderer` in `Logic/` builds the document; views trigger an export and
own no layout. Constraints when touching it:

- Never render a view into an image and call it a PDF. Text is typeset with
  Core Text so it stays selectable and searchable; only the drawing is a raster.
- Reuse the existing parse. Blocks come from `MarkdownDocument`, so a break is
  an ordinary rule and no collapsed-state type is shared with the renderer.
- The exporter's input is a `Content` value. Do not give it a view, a
  `ModelContext`, or anything a reading view holds.
- First-party frameworks only: UIKit, Core Text, PencilKit, Foundation.
- A PDF includes the note's current drawing. Version history semantics are
  unchanged and still exclude drawings.
- No schema change, and nothing generated is persisted.
- Filenames come from `NoteExport.fileBaseName(for:)`. Do not add a second
  sanitization policy.
- Page geometry and the print palette are local to the renderer. Do not push
  paper measurements or print-only colors into `Theme`.
- Two Core Text facts here were measured with probes, not assumed, and are
  recorded in CONTEXT.md. Verify by rendering a page to an image before
  believing a layout change is correct; the text-extraction tests pass happily
  on a badly spaced page.

## Version history

Revisions record authored text only: title, body, and event date. Keep the
draft-based Save and Cancel architecture as it is. Nothing is snapshotted while
typing, on Cancel, or on organizational changes such as filing and pinning, and
a new note's first save records nothing.

Do not put drawings into revision history unless the scope is explicitly
widened, and do not add diff, blame, or line-level annotation infrastructure
until it is asked for. Snapshots already hold enough authored state for a future
comparison feature.

`NoteHistory` owns these rules. Read the migration behavior in `NoteTests` before
touching the revision model, and remember that naming fewer models does not
create an older SwiftData schema.

## Working rhythm

Work in commit-sized pieces. For each implementation change, use the impact
review in AGENTS.md to keep affected tests, documentation, configuration, and
repository-facing material synchronized. Finish one coherent change, verify it,
summarize what changed and what was checked, and propose a conventional commit
message.

**Never commit and never push unless explicitly instructed.** Leave the working
tree for review.
