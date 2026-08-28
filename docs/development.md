# Development

## Repository conventions

- Prefer native Apple frameworks. Runtime dependencies require a strong reason.
- Put stateable rules in `CaseNotes/Logic/` and cover them with Swift Testing.
- Use `Theme` tokens instead of literal visual values.
- Keep examples, previews, tests, and screenshots synthetic.
- Do not hand-edit `project.pbxproj` to register sources. Xcode synchronized
  groups pick up files added under `CaseNotes/`.
- Do not add networking, accounts, analytics, telemetry, advertising, or cloud
  services.

Read `AGENTS.md` for the full coding and verification standards.

## Documentation

Documentation source lives in `docs/` and navigation is declared in
`mkdocs.yml`. Keep the root README concise and move durable technical detail
into the site.

When behavior changes, update the relevant page in the same change. Run the
strict documentation build so missing pages, invalid navigation, and warnings
fail before deployment.

## Before submitting a change

1. Build the application without new warnings.
2. Run the full unit suite.
3. Build the documentation with strict warnings enabled when docs change.
4. Review `git diff` and `git status` for unrelated files.
5. Search repository-facing text for em dash characters.
6. Confirm README and documentation claims still match the implementation.

Do not commit generated `site/` output. Do not commit or push unless explicitly
requested by the repository owner.
