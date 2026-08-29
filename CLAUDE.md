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
- Visuals must not imply persistence the model does not have. Folders are flat,
  so no indentation, disclosure triangles, or trees.
- A redesign is not a licence to add persisted state. No `@Model` change and no
  new stored setting belongs in a visual slice.
- Screenshot the result in Simulator. Two defects in this pass were only visible
  that way: a plain list footer drawing black instead of the canvas, and a fixed
  symbol column overlapping its label at accessibility text sizes.
- After a UI change, check `docs/`, the README, and the screenshots before
  calling it done.

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
