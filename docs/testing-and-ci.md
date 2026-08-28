# Testing and CI

## Unit tests

The CI-gated suite uses Swift Testing and covers model behavior, persistence,
schema migration, drafts and timestamps, version history and restore, organizing
notes, Markdown parsing, exports, folder relationships, drawing persistence, and
app lock policy.

```bash
xcodebuild test -project CaseNotes.xcodeproj -scheme CaseNotes \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:CaseNotesTests
```

Dates, locales, and time zones are injected where formatted output matters.
Persistence tests use an in-memory `ModelContainer` except when reopening an
older on-disk schema is the behavior under test. That older store is written
through `PreRevisionSchema` in the test target, which declares the models as
they stood before version history and must stay frozen there.

## UI test

The deliberately small XCTest UI suite verifies that a fresh launch exposes the
lock screen and does not make note content reachable before authentication. Run
all tests locally with:

```bash
xcodebuild test -project CaseNotes.xcodeproj -scheme CaseNotes \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Automation

`.github/workflows/ci.yml` runs the unit suite for pushes and pull requests to
`main` on macOS with Xcode 26.6. The UI test remains a local check because it
depends on simulator launch and authentication behavior.

`.github/workflows/docs.yml` installs the pinned MkDocs version and runs
`mkdocs build --strict`. Pull requests validate the site. Pushes to `main` also
upload the generated output and deploy it through GitHub Pages. Generated site
files are not committed.

```bash
python -m pip install -r requirements-docs.txt
python -m mkdocs build --strict
```
