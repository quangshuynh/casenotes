# Accessibility

CaseNotes uses semantic SwiftUI fonts so text responds to Dynamic Type.
Icon-only controls have accessibility labels, note metadata is combined into
meaningful spoken elements, headings receive the header trait, and drawing and
loading states have explicit labels.

Browsing rows are visually compact but keep a stated minimum height, and the
symbol column beside a row label scales with the text next to it. At
accessibility text sizes rows that pair a title with a date stop sharing a line
and stack instead, so readability wins over density.

The collapse control on a section divider is a button with a spoken label that
names the action it performs and a value that states whether the section is
expanded or collapsed, so the state never depends on reading a chevron. The row
keeps a full-height target, and collapsed content leaves the view entirely
rather than being hidden in place, so VoiceOver reads only what is on screen.
The written hint beside a collapsed divider is dropped at accessibility text
sizes, where it would truncate; the button keeps its label and value.

Motion-sensitive transitions read the system Reduce Motion setting and disable
their animations when requested. Folding a section is one of them. The app-switcher privacy cover is independent
of those transitions and always appears immediately without animation.

The theme supports light and dark appearances. The drawing surface deliberately
uses a light paper appearance so PencilKit ink remains consistent between the
editor and rendered drawing.

Accessibility behavior should be checked manually with large Dynamic Type
sizes, VoiceOver, Reduce Motion, and both appearances. Rendering details are not
a substitute for those device or Simulator checks.
