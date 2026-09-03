//
//  MarkdownLivePreview.swift
//  CaseNotes
//
//  Created by q on 9/2/26.
//

import SwiftUI
import UIKit

/// A note body that is rendered and editable at the same time.
///
/// Everything outside the region holding the caret is drawn by the same
/// ``MarkdownBlockView`` the reading screen uses. The region holding the caret
/// is replaced by its own Markdown source in a text view, so the syntax being
/// worked on is visible and everything around it stays legible.
///
/// Three rules shape the implementation:
///
/// - The draft's body string is the only copy of the text. There is no parallel
///   editable document, nothing is normalized on the way in or out, and an edit
///   is written straight back into the span the region owns through
///   ``MarkdownSourceMap/replacing(_:utf16Range:with:)``.
/// - Regions come from ``MarkdownSourceMap``, which proves every boundary
///   against Foundation's own parse. A fenced block, a block quote, a nested
///   list, and a setext heading therefore travel whole rather than being cut at
///   a line that happens to look like a boundary.
/// - The text view keeps one position in the view tree whether the active
///   region is the first or the last, so the caret, the keyboard, and the undo
///   stack survive the document being divided again underneath it.
///
/// Dividing a whole note costs more than parsing it, so it is deliberately kept
/// off the keystroke path. Typing extends the span the text view owns and
/// leaves the regions around it where they were; when a boundary appears inside
/// that span, only the span is divided again and the result is spliced back into
/// the map. A whole note is divided when it is opened, when a region is entered,
/// and when the source arrives from somewhere else, and a division already
/// proved against exactly that text is reused rather than made again.
struct MarkdownLivePreview: View {
    @Binding var source: String

    /// Where the body is being edited, reported for the editor's insertion
    /// action to place an attachment at.
    ///
    /// Written on every keystroke and every caret move, which is why it is a
    /// box rather than state: nothing on screen depends on it, and redrawing
    /// the editor for it would put work back onto the path this feature must
    /// not slow down.
    let bodyCaret: MarkdownBodyCaret

    /// The last division of the note.
    ///
    /// Its regions describe the current source everywhere except inside the
    /// active region, whose span is tracked separately because typing moves it.
    @State private var map = MarkdownSourceMap("")

    /// Which region is being edited, as an index into ``map``.
    @State private var activeIndex: Int?

    /// The span of the current source the text view owns, in UTF-16 code units.
    ///
    /// It starts as the active region's span and grows or shrinks with every
    /// edit, which is what lets the regions after it be placed without dividing
    /// the note again.
    @State private var activeRange = 0..<0

    /// The source as this view last left it, so a change made elsewhere, such
    /// as a switch to Source mode and back, is told apart from its own writing.
    @State private var syncedSource = ""

    /// A caret placement waiting for the text view to apply it.
    ///
    /// Only entering a region uses this. When an edit changes which region is
    /// active, the text view is reshaped inside the callback that reported the
    /// edit instead, so nothing computed before a keystroke can land after it.
    @State private var caretRequest: MarkdownCaretRequest?
    @State private var requestCounter = 0

    /// Incremented whenever a region is entered.
    ///
    /// The text view reports that it stopped editing after the tap that moved
    /// the caret elsewhere has already been handled, so the generation is what
    /// tells a genuine dismissal from a move between two regions.
    @State private var activationGeneration = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let activeIndex, map.regions.indices.contains(activeIndex) {
                renderedRegions(map.regions[..<activeIndex], shift: 0)

                activeEditor(for: map.regions[activeIndex], index: activeIndex)

                renderedRegions(map.regions[(activeIndex + 1)...], shift: activeShift)
            } else {
                renderedRegions(map.regions[...], shift: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            synchronize()
        }
        .onChange(of: source) {
            guard source != syncedSource else {
                return
            }

            synchronize()
        }
    }

    // MARK: Layout

    /// The regions that are being read rather than written.
    ///
    /// - Parameters:
    ///   - regions: A slice of the division, in reading order.
    ///   - shift: How far the current source has moved these regions since the
    ///     division was made, which is non-zero only for the regions below an
    ///     active one that has been typed into.
    /// - Returns: The rendered blocks, each able to take the caret.
    private func renderedRegions(
        _ regions: ArraySlice<MarkdownSourceMap.Region>,
        shift: Int
    ) -> some View {
        ForEach(regions) { region in
            renderedRegion(region, shift: shift)
        }
    }

    /// One region drawn the way the reading screen draws it, and tappable.
    ///
    /// A tap carries where it landed, so entering a region can put the caret
    /// near the words that were touched rather than at the start of the block.
    /// VoiceOver reaches the same behavior through a named action, because the
    /// rendered text stays individually readable rather than being flattened
    /// into one button.
    ///
    /// - Parameters:
    ///   - region: The region to draw.
    ///   - shift: The offset between the division and the current source.
    /// - Returns: The region's blocks, with a target over them.
    @ViewBuilder
    private func renderedRegion(
        _ region: MarkdownSourceMap.Region,
        shift: Int
    ) -> some View {
        if let attachmentID = InlineAttachments.attachmentID(of: region) {
            placedAttachment(attachmentID, in: region, shift: shift)
        } else {
            markdownRegion(region, shift: shift)
        }
    }

    /// One ordinary region drawn the way the reading screen draws it.
    ///
    /// - Parameters:
    ///   - region: The region to draw.
    ///   - shift: The offset between the division and the current source.
    /// - Returns: The region's blocks, with a target over them.
    private func markdownRegion(
        _ region: MarkdownSourceMap.Region,
        shift: Int
    ) -> some View {
        let start = region.utf16Range.lowerBound + shift

        return VStack(alignment: .leading, spacing: 0) {
            if region.isEmpty {
                // An empty note, which still needs somewhere to put the caret.
                Color.clear
                    .frame(height: Theme.Layout.minimumRowHeight)
            } else {
                MarkdownBlockStack(blocks: region.blocks)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, topPadding(before: region.id))
        .contentShape(.rect)
        .highPriorityGesture(
            SpatialTapGesture(coordinateSpace: .local)
                .onEnded { tap in
                    activate(atUTF16Offset: start, from: editorPoint(for: tap.location, in: region.id))
                }
        )
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Edit Markdown Source") {
            activate(atUTF16Offset: start, from: nil)
        }
    }

    /// One of the note's files, drawn where it was placed and with the controls
    /// that move it.
    ///
    /// A placement is a block rather than a piece of prose, so it is not
    /// entered for editing by a tap: tapping it opens the file. Its Markdown is
    /// still reachable, through the same named action every other region
    /// offers, so the marker is never hidden from the person who wrote it.
    ///
    /// Movement is offered as two directions rather than as a drag. Document
    /// order is the only order this feature has, and a pair of buttons is the
    /// same gesture for everyone, including a reader using VoiceOver or Switch
    /// Control, where a drag is not.
    ///
    /// - Parameters:
    ///   - id: The attachment the region places.
    ///   - region: The region holding the marker.
    ///   - shift: The offset between the division and the current source.
    /// - Returns: The attachment and its controls.
    private func placedAttachment(
        _ id: UUID,
        in region: MarkdownSourceMap.Region,
        shift: Int
    ) -> some View {
        let start = region.utf16Range.lowerBound + shift

        return VStack(alignment: .leading, spacing: Theme.Spacing.xSmall) {
            MarkdownBlockView(block: .attachment(id: id))

            placementControls(for: region)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, topPadding(before: region.id))
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Edit Markdown Source") {
            activate(atUTF16Offset: start, from: nil)
        }
    }

    /// The controls that reposition a placement or take it out of the note.
    ///
    /// Quiet on purpose: this is a document, not a toolbar. Each control keeps
    /// a full target and is named in words, and none of them is distinguished
    /// by color.
    ///
    /// - Parameter region: The region holding the marker.
    /// - Returns: The row of controls.
    private func placementControls(
        for region: MarkdownSourceMap.Region
    ) -> some View {
        HStack(spacing: Theme.Spacing.small) {
            placementControl(
                symbol: "arrow.up",
                label: "Move Attachment Up",
                isEnabled: region.id > 0
            ) {
                move(placement: region.id, .up)
            }

            placementControl(
                symbol: "arrow.down",
                label: "Move Attachment Down",
                isEnabled: region.id < map.regions.count - 1
            ) {
                move(placement: region.id, .down)
            }

            placementControl(
                symbol: "minus.circle",
                label: "Remove Attachment From Note Text",
                hint: "The file stays attached to the note",
                isEnabled: true
            ) {
                removePlacement(region.id)
            }

            Spacer(minLength: 0)
        }
    }

    /// One of the controls under a placement.
    ///
    /// - Parameters:
    ///   - symbol: The SF Symbol to draw.
    ///   - label: What the control is called, spoken and never written on
    ///     screen, since a document is not the place for three captions.
    ///   - hint: What it does, when that is not obvious from the name.
    ///   - isEnabled: Whether the action is available here.
    ///   - action: What to do.
    /// - Returns: The control.
    private func placementControl(
        symbol: String,
        label: String,
        hint: String = "",
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(
                    minWidth: Theme.Layout.minimumRowHeight,
                    minHeight: Theme.Layout.minimumRowHeight
                )
                .contentShape(.rect)
        }
        // Borderless rather than plain, which is not a style choice. Live
        // preview sits inside a form row, and a row treats the plain buttons
        // in it as one target: every control under a placement fired whichever
        // button the row had picked, so moving an image opened a PDF instead.
        // That was found by tapping them, not by reading the code.
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }

    /// The region currently being written, shown as its own Markdown source.
    ///
    /// The well it sits in is what tells a reader which region is live: a
    /// recessed surface and a rounded edge rather than a tint, so the state
    /// survives both appearances and any color vision.
    ///
    /// - Parameters:
    ///   - region: The active region as the last division described it.
    ///   - index: Its position in the division.
    /// - Returns: The editable source of that region.
    private func activeEditor(
        for region: MarkdownSourceMap.Region,
        index: Int
    ) -> some View {
        MarkdownSourceRegionEditor(
            text: activeText,
            font: Self.editorFont(for: region.leadingBlock),
            caretRequest: caretRequest,
            onChange: handleEditorChange,
            onDeleteBackwardAtStart: joinWithRegionAbove,
            onEndEditing: scheduleDeactivation,
            onCaretRequestHandled: { caretRequest = nil }
        )
        .padding(.vertical, Theme.Spacing.small)
        .background {
            // Drawn wider than the text it holds rather than by insetting the
            // text, so the source appears in the same column the rendered
            // block occupied and a region does not shuffle sideways as it is
            // entered.
            RoundedRectangle(cornerRadius: Theme.Radius.small)
                .fill(Theme.Colors.canvas)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.small)
                        .strokeBorder(Theme.Colors.separator, lineWidth: 1)
                }
                .padding(.horizontal, -Theme.Spacing.small)
        }
        .padding(.top, topPadding(before: index))
    }

    /// Moves a tap on a rendered region into the coordinate space the text view
    /// that replaces it will use.
    ///
    /// A rendered region and the editor that takes its place occupy the same
    /// slot and the same column, but each carries padding of its own above the
    /// text. Subtracting both is what makes a tap on the third line of a
    /// paragraph arrive on the third line of its source instead of a line below
    /// it. Only the offsets are arithmetic here: which character the point lands
    /// on is answered by the text view's own layout.
    ///
    /// - Parameters:
    ///   - point: Where the tap landed, in the rendered region's coordinates.
    ///   - id: The region that was tapped.
    /// - Returns: The equivalent point in the editor's text.
    private func editorPoint(for point: CGPoint, in id: Int) -> CGPoint {
        CGPoint(
            x: point.x,
            y: point.y - topPadding(before: id) - Theme.Spacing.small
        )
    }

    /// The gap above a region, matching the gap the reading screen leaves
    /// between the same two blocks.
    ///
    /// - Parameter index: The region's position in the division.
    /// - Returns: The leading padding in points.
    private func topPadding(before index: Int) -> CGFloat {
        guard index > 0, map.regions.indices.contains(index) else {
            return 0
        }

        guard let previous = map.regions[index - 1].blocks.last,
              let current = map.regions[index].blocks.first
        else {
            return Theme.Spacing.medium
        }

        return MarkdownBlockStack.spacingAbove(current, previous: previous)
    }

    /// The source the text view is holding.
    private var activeText: String {
        MarkdownSourceMap.substring(of: source, utf16Range: activeRange)
    }

    /// How far typing has moved everything below the active region since the
    /// last division.
    private var activeShift: Int {
        guard let activeIndex, map.regions.indices.contains(activeIndex) else {
            return 0
        }

        return activeRange.count - map.regions[activeIndex].utf16Range.count
    }

    // MARK: Editing

    /// Takes the text view's report and decides what the document should do
    /// about it.
    ///
    /// A report is ignored when the text it carries no longer matches the span
    /// the view is supposed to own, which happens for a moment after the
    /// document has been divided again underneath it.
    ///
    /// - Parameters:
    ///   - text: What the text view holds.
    ///   - caret: The caret's position within the region.
    ///   - isEdit: Whether the text changed rather than only the caret.
    /// - Returns: A reshaping for the text view to apply at once, or `nil` when
    ///   the region it holds still stands.
    private func handleEditorChange(
        text: String,
        caret: Int,
        isEdit: Bool
    ) -> MarkdownRegionReshape? {
        guard activeIndex != nil else {
            return nil
        }

        if isEdit {
            guard text != activeText else {
                return nil
            }

            return applyEdit(text, caret: caret)
        }

        guard text == activeText else {
            return nil
        }

        bodyCaret.utf16Offset = activeRange.lowerBound + caret

        return splitActiveRegion(regionText: text, in: source, caret: caret)
    }

    /// Writes what was typed back into the note body.
    ///
    /// Only the span the region owns is replaced, so every other character of
    /// the note is carried through untouched and the stored Markdown stays
    /// exactly what the user wrote.
    ///
    /// - Parameters:
    ///   - text: The region's new source.
    ///   - caret: The caret's position within it.
    /// - Returns: A reshaping when the edit changed which region is active.
    private func applyEdit(_ text: String, caret: Int) -> MarkdownRegionReshape? {
        guard isPlausibleEdit(of: activeText, into: text) else {
            // The text view is holding something this view does not believe it
            // gave it, which would make writing the edit back duplicate or drop
            // characters. Nothing is written; the region is pushed again
            // instead, which puts the two back in step.
            return MarkdownRegionReshape(
                text: activeText,
                caret: min(caret, activeText.utf16.count)
            )
        }

        let edited = MarkdownSourceMap.replacing(source, utf16Range: activeRange, with: text)
        let range = activeRange.lowerBound..<(activeRange.lowerBound + text.utf16.count)

        syncedSource = edited
        source = edited
        activeRange = range
        bodyCaret.utf16Offset = range.lowerBound + caret

        return splitActiveRegion(regionText: text, in: edited, caret: caret)
    }

    /// Whether one string could have become the other through a single edit in
    /// a text view.
    ///
    /// An edit replaces one contiguous run, so the two strings must agree at
    /// the front and at the back across everything the shorter one holds. This
    /// is a guard rather than a rule: it costs a comparison and it turns a
    /// disagreement between this view and its text view into a recoverable
    /// state rather than into corrupted Markdown.
    ///
    /// - Parameters:
    ///   - before: The text the region is believed to hold.
    ///   - after: The text the view reports.
    /// - Returns: `true` when the change could be one edit.
    private func isPlausibleEdit(of before: String, into after: String) -> Bool {
        let old = Array(before.utf16)
        let new = Array(after.utf16)

        var prefix = 0
        while prefix < old.count, prefix < new.count, old[prefix] == new[prefix] {
            prefix += 1
        }

        var suffix = 0
        while suffix < old.count - prefix, suffix < new.count - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] {
            suffix += 1
        }

        return prefix + suffix >= min(old.count, new.count)
    }

    /// Splits the region being edited once a boundary has appeared inside it.
    ///
    /// Both the check and the repair are confined to the region's own text,
    /// which is small. The note as a whole is never divided again on a
    /// keystroke: doing so on a long note took long enough that keys pressed
    /// during it queued up behind it and were then overwritten by the state it
    /// produced, which cost real text. That was found by typing quickly into a
    /// long note, not by reading the code.
    ///
    /// - Parameters:
    ///   - regionText: The active region's source.
    ///   - body: The note body the region belongs to.
    ///   - caret: The caret's position within the region.
    /// - Returns: The region the caret ended up in, or `nil` when the region
    ///   still holds together.
    private func splitActiveRegion(
        regionText: String,
        in body: String,
        caret: Int
    ) -> MarkdownRegionReshape? {
        guard MarkdownSourceMap(regionText).regions.count > 1,
              let activeIndex,
              map.regions.indices.contains(activeIndex)
        else {
            return nil
        }

        return rebuild(
            body,
            replacing: activeIndex..<(activeIndex + 1),
            covering: activeRange,
            caret: activeRange.lowerBound + caret
        )
    }

    /// Adopts a repaired division and moves the caret into whichever region now
    /// holds it.
    ///
    /// - Parameters:
    ///   - body: The note body after the edit.
    ///   - indices: The regions the span replaces.
    ///   - span: The span's place in the body.
    ///   - caret: The caret's position in the body.
    /// - Returns: The region the caret ended up in, or `nil` when the repair
    ///   was refused.
    private func rebuild(
        _ body: String,
        replacing indices: Range<Int>,
        covering span: Range<Int>,
        caret: Int
    ) -> MarkdownRegionReshape? {
        guard let rebuilt = map.rebuilt(from: body, replacing: indices, covering: span),
              let region = rebuilt.region(containingUTF16Offset: caret)
        else {
            return nil
        }

        map = rebuilt
        activeIndex = region.id
        activeRange = region.utf16Range
        activationGeneration += 1
        bodyCaret.utf16Offset = caret

        return MarkdownRegionReshape(
            text: MarkdownSourceMap.substring(of: body, utf16Range: region.utf16Range),
            caret: caret - region.utf16Range.lowerBound
        )
    }

    /// Joins the region above this one, which is what a delete at the very
    /// start of a region means.
    ///
    /// The character before the region is removed from the body rather than
    /// from the text view, because it belongs to the region above. One whole
    /// character is taken, so a deletion never lands between the halves of a
    /// surrogate pair.
    ///
    /// - Returns: The joined region, or `nil` when there was nothing above it.
    private func joinWithRegionAbove() -> MarkdownRegionReshape? {
        guard activeIndex != nil, activeRange.lowerBound > 0 else {
            // Nothing above to join, so the keystroke has nothing to do.
            return nil
        }

        let start = String.Index(utf16Offset: activeRange.lowerBound, in: source)
        let removed = source.index(before: start)
        let width = source[removed..<start].utf16.count
        let joined = source.replacingCharacters(in: removed..<start, with: "")
        let caret = activeRange.lowerBound - width

        syncedSource = joined
        source = joined
        bodyCaret.utf16Offset = caret

        guard let activeIndex, activeIndex > 0, map.regions.indices.contains(activeIndex) else {
            let moved = (activeRange.lowerBound - width)..<(activeRange.upperBound - width)
            self.activeRange = moved

            return MarkdownRegionReshape(
                text: MarkdownSourceMap.substring(of: joined, utf16Range: moved),
                caret: caret - moved.lowerBound
            )
        }

        // The two regions either side of the deletion are re-divided together,
        // because a join is exactly the case where the block above and the
        // block below stop being two blocks.
        let span = map.regions[activeIndex - 1].utf16Range.lowerBound..<(activeRange.upperBound - width)

        return rebuild(
            joined,
            replacing: (activeIndex - 1)..<(activeIndex + 1),
            covering: span,
            caret: caret
        )
    }

    // MARK: Regions

    /// Enters a region so its Markdown source can be edited.
    ///
    /// - Parameters:
    ///   - offset: A position inside the region, in UTF-16 code units from the
    ///     start of the body.
    ///   - point: Where a tap landed inside the rendered region, if it was a
    ///     tap. The caret is resolved from real text layout rather than from a
    ///     character count, so it survives Dynamic Type, wrapping, and text
    ///     that is not one code unit per character.
    private func activate(atUTF16Offset offset: Int, from point: CGPoint?) {
        let divided = division(of: source)

        guard let region = divided.region(containingUTF16Offset: offset) else {
            return
        }

        map = divided
        syncedSource = source
        activeIndex = region.id
        activeRange = region.utf16Range
        activationGeneration += 1
        bodyCaret.utf16Offset = region.utf16Range.lowerBound
        request(point.map { .point($0) } ?? .offset(0))
    }

    // MARK: Placements

    /// Moves a placed attachment one block through the document.
    ///
    /// Only the marker's own characters move, and the rewrite goes through the
    /// draft exactly as typing does, so Save and Cancel cover it without a rule
    /// of their own.
    ///
    /// - Parameters:
    ///   - id: The placement's region in the current division.
    ///   - direction: Which way to move it.
    private func move(placement id: Int, _ direction: InlineAttachments.MoveDirection) {
        guard let moved = InlineAttachments.moving(placement: id, direction, in: source) else {
            return
        }

        adopt(moved.source, caret: moved.caretUTF16Offset)
    }

    /// Takes a placement out of the note text.
    ///
    /// The attachment itself is untouched: it stays on the note, its file stays
    /// on disk, and it can be placed again. Deleting the file is a separate and
    /// deliberate action in the editor's attachments list.
    ///
    /// - Parameter id: The placement's region in the current division.
    private func removePlacement(_ id: Int) {
        guard let placement = map.region(id: id),
              let removed = InlineAttachments.removing(placement: id, in: source)
        else {
            return
        }

        adopt(removed, caret: placement.utf16Range.lowerBound)
    }

    /// Takes on a body this view rewrote itself.
    ///
    /// The division is redone in full rather than repaired, because a placement
    /// changing position is a deliberate action rather than a keystroke: it is
    /// not on the path where dividing a long note costs typed characters.
    ///
    /// - Parameters:
    ///   - body: The rewritten note body.
    ///   - caret: Where editing should be considered to be afterwards.
    private func adopt(_ body: String, caret offset: Int) {
        source = body
        syncedSource = body
        map = division(of: body)
        activeIndex = nil
        activeRange = 0..<0
        caretRequest = nil
        bodyCaret.utf16Offset = min(offset, body.utf16.count)
    }

    /// Leaves editing once the keyboard has genuinely gone away.
    ///
    /// Entering another region also ends editing in this one, and the reports
    /// arrive in that order, so the decision waits a turn and is dropped if a
    /// region was entered in the meantime.
    private func scheduleDeactivation() {
        let generation = activationGeneration

        DispatchQueue.main.async {
            guard generation == activationGeneration else {
                return
            }

            deactivate()
        }
    }

    /// Renders every region again, with none of them being edited.
    private func deactivate() {
        activeIndex = nil
        caretRequest = nil
        activeRange = 0..<0
        synchronize()
    }

    /// Divides the current source from scratch, with nothing active.
    ///
    /// Used when the body arrived from outside this view, which is what a switch
    /// away to Source mode and back looks like from here, and what placing an
    /// attachment from the toolbar looks like too. Nothing stays active, because
    /// a region identity from the previous division would name different text in
    /// the new one.
    private func synchronize() {
        map = division(of: source)
        syncedSource = source
        activeIndex = nil
        activeRange = 0..<0
        caretRequest = nil

        if let offset = bodyCaret.utf16Offset {
            bodyCaret.utf16Offset = min(offset, source.utf16.count)
        }
    }

    /// The division of a body, reusing the one already held when it describes
    /// exactly that text and was proved rather than repaired.
    ///
    /// Opening a note, entering a region, and leaving one all need a settled
    /// division, and they follow each other closely: opening then tapping a
    /// paragraph asked for two divisions of the same unchanged body, and the
    /// second cost 98 ms on a 76 kB note in Release on the simulator for an
    /// answer already in hand. A division that a keystroke repaired locally is
    /// deliberately not reused, because re-proving it is the mechanism that
    /// settles half-typed Markdown, so this drops the repeated work without
    /// dropping that.
    ///
    /// - Parameter body: The note body to divide.
    /// - Returns: The division of that body.
    private func division(of body: String) -> MarkdownSourceMap {
        guard map.isProven, map.source == body else {
            return MarkdownSourceMap(body)
        }

        return map
    }

    /// Asks the text view for a caret placement.
    ///
    /// - Parameter target: Where the caret should go.
    private func request(_ target: MarkdownCaretRequest.Target) {
        requestCounter += 1
        caretRequest = MarkdownCaretRequest(id: requestCounter, target: target)
    }

    // MARK: Presentation

    /// The font a region's source is edited in.
    ///
    /// It mirrors the fonts ``MarkdownBlockView`` renders with, so a heading
    /// keeps its weight while its `#` is showing and a fenced block stays
    /// monospaced while it is being typed into. The mapping is stated twice
    /// rather than shared because the reading side is expressed in SwiftUI
    /// fonts and a `UITextView` needs a `UIFont`; converting one into the other
    /// would change how reading renders, which is not this feature's business.
    ///
    /// - Parameter block: The block the region leads with.
    /// - Returns: The font for its source.
    static func editorFont(for block: MarkdownDocument.Block?) -> UIFont {
        switch block {
        case let .heading(level, _):
            switch level {
            case 1: weighted(.title2, weight: .semibold)
            case 2: weighted(.title3, weight: .semibold)
            default: UIFont.preferredFont(forTextStyle: .headline)
            }

        case .codeBlock:
            UIFontMetrics(forTextStyle: .callout).scaledFont(
                for: .monospacedSystemFont(
                    ofSize: UIFont.preferredFont(
                        forTextStyle: .callout,
                        compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
                    ).pointSize,
                    weight: .regular
                )
            )

        default:
            UIFont.preferredFont(forTextStyle: .body)
        }
    }

    /// A text style at a chosen weight, still sized by Dynamic Type.
    ///
    /// A system font at a chosen weight is not a text style and does not scale
    /// itself, so it is measured against the style at the default content size
    /// and then scaled by `UIFontMetrics`. That is what lets the text view keep
    /// resizing it as the reader's text size changes.
    ///
    /// - Parameters:
    ///   - style: The text style to take the reference size from.
    ///   - weight: The weight to apply.
    /// - Returns: The scaled font.
    private static func weighted(
        _ style: UIFont.TextStyle,
        weight: UIFont.Weight
    ) -> UIFont {
        let reference = UIFont.preferredFont(
            forTextStyle: style,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        )

        return UIFontMetrics(forTextStyle: style).scaledFont(
            for: .systemFont(ofSize: reference.pointSize, weight: weight)
        )
    }
}

#Preview {
    @Previewable @State var noteBody = """
        # Case Strategy

        This is **important evidence**.

        ## Documents

        - Review report
        - Check timeline

        > Parts are on order.

        ```swift
        let note = Note(title: "Site Visit")
        ```
        """

    ScrollView {
        MarkdownLivePreview(source: $noteBody, bodyCaret: MarkdownBodyCaret())
            .padding(Theme.Spacing.large)
    }
    .background(Theme.Colors.surface)
}
