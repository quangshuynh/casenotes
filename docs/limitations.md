# Limitations

The following boundaries are current and intentional unless a future change
explicitly addresses them:

- The app lock gates the interface but does not encrypt the persistent store.
- There is no sync or iCloud integration. Notes live on one device and survive
  only through that device's backup behavior.
- Markdown files can be exported but not imported, and PDF export is one way as
  well: a PDF cannot be read back into a note.
- Drawings are not embedded in Markdown exports, and each note supports one
  drawing. A PDF export does include the note's current drawing.
- PDF export covers one note at a time. There is no folder, multi-note, or
  combined export, no export of a previous version, and no paper size, font,
  page number, header, or footer options. The page is US Letter.
- Exported files are not encrypted or password protected. Once a file is shared
  or saved it is controlled by wherever it was sent rather than by CaseNotes.
- PDF code blocks are monospaced but not syntax highlighted.
- Version history covers the authored text of a note: title, body, and event
  date. Drawings, folder membership, and pinned state are not versioned, and
  history is kept on the device with the note rather than exported.
- Version history is a recovery feature, not an audit log. It is stored in the
  same unencrypted store as the notes, is not tamper evident, and is not
  pruned, so a heavily edited note keeps every previous version.
- Previous versions can be read and restored but not compared side by side.
- Collapsing a section is read-mode state only. It is not saved, so every
  section is expanded again the next time a note is opened, and folding is
  driven by thematic breaks rather than by headings or nesting.
- Folders are flat, and each note belongs to at most one folder.
- iPad uses single-column navigation rather than a persistent folder sidebar.
- Search uses localized case-insensitive substring matching without ranking or
  tokenization.
- The project has not been submitted to the App Store or through a security
  review.

Possible future work includes an iPad sidebar, Markdown import, richer
organization, and comparing two versions of a note. These are ideas, not
implemented features or commitments.
