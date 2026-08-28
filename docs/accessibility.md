# Accessibility

CaseNotes uses semantic SwiftUI fonts so text responds to Dynamic Type.
Icon-only controls have accessibility labels, note metadata is combined into
meaningful spoken elements, headings receive the header trait, and drawing and
loading states have explicit labels.

Motion-sensitive transitions read the system Reduce Motion setting and disable
their animations when requested. The app-switcher privacy cover is independent
of those transitions and always appears immediately without animation.

The theme supports light and dark appearances. The drawing surface deliberately
uses a light paper appearance so PencilKit ink remains consistent between the
editor and rendered drawing.

Accessibility behavior should be checked manually with large Dynamic Type
sizes, VoiceOver, Reduce Motion, and both appearances. Rendering details are not
a substitute for those device or Simulator checks.
