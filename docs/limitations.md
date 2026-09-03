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
- Attachments are local files the app copies into its own container. They are
  not encrypted, are not synced, and travel only in that device's backups.
- Attachments do not appear in Markdown or PDF exports, and there is no archive
  format that carries a note together with its files.
- Importable kinds are PDF, Word documents, plain text and Markdown, and PNG and
  JPEG images. Other formats are refused, as are empty files.
- Attachment contents are not searched, indexed, or read. Search covers note
  text, and an attachment is matched by nothing at all, not even its file name.
- Attachments are not versioned. History records authored text, so removing a
  file cannot be undone by restoring an older version.
- Attachments are shown in the order they were added and cannot be reordered or
  renamed, and there is no drag and drop.
- An attachment is previewed through the system document viewer. CaseNotes
  renders no document format itself and cannot edit or annotate one.
- A file whose bytes have gone missing is reported as missing rather than
  repaired. The note stays usable and the row can be removed.
- Version history covers the authored text of a note: title, body, and event
  date. Drawings, folder membership, and pinned state are not versioned, and
  history is kept on the device with the note rather than exported.
- Version history is a recovery feature, not an audit log. It is stored in the
  same unencrypted store as the notes, is not tamper evident, and is not
  pruned, so a heavily edited note keeps every previous version.
- Previous versions can be read and restored but not compared side by side.
- The Markdown mode is view state and is not remembered between edits. The
  editor opens in Live Preview every time, because the app stores no preferences
  and a display choice was not a reason to add any.
- Live Preview edits one region at a time, so a selection cannot span two
  regions and Select All covers the region rather than the note. Source mode
  shows the whole body in one field for any change that has to reach across it.
- A Live Preview region grows to hold what is typed into it, so writing several
  blocks without moving the cursor leaves them all showing source until the
  cursor moves.
- Tapping rendered text in Live Preview lands in the right region and on the
  right line, but not always on the exact character: the source shows syntax the
  rendered form hides, so a tap late in a line carrying `**` or a link can be a
  character or two out.
- Undo in Live Preview covers the region being edited, and is cleared when the
  region being edited changes.
- Collapsing a section is read-mode state only. It is not saved, so every
  section is expanded again the next time a note is opened, and folding is
  driven by thematic breaks rather than by headings or nesting.
- Folders nest, but there is no drag and drop and no manual ordering. Folders
  are shown in name order, and a folder is moved through an explicit
  destination picker.
- A folder row counts the notes filed directly in it rather than everything
  beneath it, and browsing or searching a folder shows those same direct notes
  rather than reaching into its subfolders.
- Each note belongs to at most one folder, or to none.
- iPad uses single-column navigation rather than a persistent folder sidebar.
- Search uses localized case-insensitive substring matching without ranking or
  tokenization.
- The project has not been submitted to the App Store or through a security
  review.

Possible future work includes an iPad folder sidebar, Markdown import, folder
ordering and drag and drop, and comparing two versions of a note. These are ideas, not
implemented features or commitments.
