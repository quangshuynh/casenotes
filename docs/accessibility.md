# Accessibility

CaseNotes uses semantic SwiftUI fonts so text responds to Dynamic Type.
Icon-only controls have accessibility labels, note metadata is combined into
meaningful spoken elements, headings receive the header trait, and drawing and
loading states have explicit labels.

Browsing rows are visually compact but keep a stated minimum height, and the
symbol column beside a row label scales with the text next to it. At
accessibility text sizes rows that pair a title with a date stop sharing a line
and stack instead, so readability wins over density.

Hierarchy is never left to indentation alone. A folder row is spoken as one
phrase naming the folder, how many folders it contains, and how many notes are
filed in it, so a row that leads somewhere says so rather than relying on a
filled icon. A destination in a move picker is spoken with the folders it sits
inside, as in "Research, inside Work, Project Alpha", and the row already
holding the thing being moved says that it is the current location. The written
path under an indented destination carries the same structure for anyone reading
the screen at a text size where indentation has to stop growing. A note names
its full location on its reading screen, and a compact list row shows the folder
name while speaking the whole path.

The collapse control on a section divider is a button with a spoken label that
names the action it performs and a value that states whether the section is
expanded or collapsed, so the state never depends on reading a chevron. The row
keeps a full-height target, and collapsed content leaves the view entirely
rather than being hidden in place, so VoiceOver reads only what is on screen.
The written hint beside a collapsed divider is dropped at accessibility text
sizes, where it would truncate; the button keeps its label and value.

Every action in the note's More Actions menu is a labelled word rather than a
bare symbol, including the two file exports, so the difference between exporting
Markdown and exporting a PDF is spoken rather than inferred from an icon.

An exported PDF keeps the note's text as text rather than flattening the page
into one image, which is what lets a reader select it, search it, and print it
at full quality. What a PDF reader then does with that text is the reader's
behavior rather than something CaseNotes controls, and the app makes no claim
about tagged-PDF structure or reading order. The document uses fixed type sizes
so it paginates the same way for everyone, which means the reader's Dynamic Type
setting deliberately does not change the file; zooming is done in whatever opens
it. An included drawing is an image with no alternative text.

Motion-sensitive transitions read the system Reduce Motion setting and disable
their animations when requested. Folding a section is one of them. The app-switcher privacy cover is independent
of those transitions and always appears immediately without animation.

The theme supports light and dark appearances. The drawing surface deliberately
uses a light paper appearance so PencilKit ink remains consistent between the
editor and rendered drawing.

Accessibility behavior should be checked manually with large Dynamic Type
sizes, VoiceOver, Reduce Motion, and both appearances. Rendering details are not
a substitute for those device or Simulator checks.
