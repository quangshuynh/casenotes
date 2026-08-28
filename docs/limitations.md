# Limitations

The following boundaries are current and intentional unless a future change
explicitly addresses them:

- The app lock gates the interface but does not encrypt the persistent store.
- There is no sync or iCloud integration. Notes live on one device and survive
  only through that device's backup behavior.
- Markdown files can be exported but not imported.
- Drawings are not embedded in exports, and each note supports one drawing.
- Folders are flat, and each note belongs to at most one folder.
- iPad uses single-column navigation rather than a persistent folder sidebar.
- Search uses localized case-insensitive substring matching without ranking or
  tokenization.
- The project has not been submitted to the App Store or through a security
  review.

Possible future work includes an iPad sidebar, drawing-aware export, Markdown
import, and richer organization. These are ideas, not implemented features or
commitments.
