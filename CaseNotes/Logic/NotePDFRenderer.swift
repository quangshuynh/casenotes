//
//  NotePDFRenderer.swift
//  CaseNotes
//
//  Created by q on 8/29/26.
//

import CoreText
import Foundation
import PencilKit
import UIKit

/// Renders a note as a paginated PDF document.
///
/// This is the presentation counterpart to ``NoteExport``. A Markdown export
/// hands over the source the user wrote; a PDF hands over the note as a reader
/// sees it, with the syntax resolved into headings, lists, quotes, and code.
///
/// The renderer works from a value copy of the note's authored content, never
/// from a view. Read mode's folding is view state and cannot reach here: the
/// document is built from ``MarkdownDocument/blocks``, which holds every block
/// of the note including the thematic breaks, so a collapsed region on screen
/// still exports in full and a break exports as an ordinary rule.
///
/// Text is drawn as text with Core Text rather than rasterized, so a reader can
/// select, search, and print it, and the file stays small. Only a PencilKit
/// drawing becomes an image, because that is what it is.
enum NotePDFRenderer {
    /// The authored content a PDF is built from.
    ///
    /// A value type rather than the model, for two reasons: it can cross to
    /// another actor with the note's SwiftData object staying where it belongs,
    /// and it makes explicit that a PDF carries authored content only. Creation
    /// timestamps, edit timestamps, pinned state, folder, and version history
    /// are app bookkeeping and are not represented here at all.
    struct Content: Sendable, Equatable {
        let title: String
        let eventDate: Date?
        let body: String

        /// The note's current drawing, as PencilKit serialized it.
        ///
        /// Optional because most notes have none. Bytes that no longer decode
        /// are handled at render time rather than here, so a damaged sketch
        /// costs the drawing and never the text.
        let drawingData: Data?

        init(
            title: String,
            eventDate: Date? = nil,
            body: String = "",
            drawingData: Data? = nil
        ) {
            self.title = title
            self.eventDate = eventDate
            self.body = body
            self.drawingData = drawingData
        }

        /// Captures a note's authored content.
        ///
        /// - Parameter note: The note being exported.
        init(note: Note) {
            self.init(
                title: note.displayTitle,
                eventDate: note.eventDate,
                body: note.body,
                drawingData: note.drawing?.data
            )
        }
    }

    /// US Letter, in points, and the margin around the text column.
    ///
    /// One deliberate paper size rather than a preference. Letter is the
    /// everyday size where this app is used, and a fixed size is what lets
    /// pagination be reasoned about and tested. A 72 point margin leaves a 468
    /// point column, which is a comfortable measure for the body size below.
    private enum Page {
        static let size = CGSize(width: 612, height: 792)
        static let margin: CGFloat = 72
        static var rect: CGRect { CGRect(origin: .zero, size: size) }
    }

    /// Type sizes and the gaps between blocks, in points.
    ///
    /// Fixed rather than derived from Dynamic Type. A shared document has to
    /// paginate the same way for everyone who opens it, so the reader's text
    /// size setting deliberately does not reach the page.
    private enum Metrics {
        static let titleSize: CGFloat = 22
        static let eventDateSize: CGFloat = 10
        static let bodySize: CGFloat = 11
        static let codeSize: CGFloat = 9.5
        static let inlineCodeSize: CGFloat = 10
        static let lineSpacing: CGFloat = 3

        static let titleToEventDate: CGFloat = 5
        static let headerToRule: CGFloat = 14
        static let ruleToBody: CGFloat = 16

        static let paragraphSpacing: CGFloat = 9
        static let listItemSpacing: CGFloat = 4
        static let quoteSpacing: CGFloat = 10
        static let codeSpacing: CGFloat = 10
        static let breakSpacing: CGFloat = 16
        static let drawingSpacing: CGFloat = 16

        static let codePadding: CGFloat = 8
        static let quoteRuleWidth: CGFloat = 2
        static let quoteIndent: CGFloat = 12
        static let listIndentStep: CGFloat = 18
        static let listMarkerColumn: CGFloat = 16

        /// The least room a block needs before it is worth starting on this
        /// page rather than the next one.
        static let minimumFragmentHeight: CGFloat = 26

        /// Margin left around a rasterized drawing so strokes do not sit on the
        /// text column's edge.
        static let drawingInset: CGFloat = 8

        /// Raster scale for the drawing. Enough for print without turning a
        /// sketch into the bulk of the file.
        static let drawingScale: CGFloat = 2
    }

    /// Ink for the page.
    ///
    /// Deliberately not the app palette. CaseNotes reads dark, and a document
    /// meant to be shared and printed has to be light and ink conscious, so
    /// these are print values that only borrow the app's warmth: a warm near
    /// black for text and a muted amber for headings and marks.
    private enum Palette {
        static let paper = UIColor.white
        static let ink = UIColor(red: 0.11, green: 0.10, blue: 0.09, alpha: 1)
        static let secondaryInk = UIColor(red: 0.42, green: 0.40, blue: 0.37, alpha: 1)
        static let accent = UIColor(red: 0.55, green: 0.35, blue: 0.05, alpha: 1)
        static let rule = UIColor(red: 0.82, green: 0.80, blue: 0.77, alpha: 1)
        static let codeBackground = UIColor(red: 0.96, green: 0.955, blue: 0.945, alpha: 1)
        static let link = UIColor(red: 0.13, green: 0.32, blue: 0.52, alpha: 1)
    }

    /// The decoration drawn behind or beside a block.
    private enum Decoration {
        case none
        case code
        case quote
    }

    /// Renders a note as a PDF document.
    ///
    /// Runs on the main actor because it rasterizes a PencilKit drawing and
    /// resolves a `UITraitCollection` to do it, neither of which is documented
    /// as safe anywhere else. Export is an explicit, one document action, so
    /// correctness is worth more here than moving the work off the main thread.
    ///
    /// Never throws and never fails: malformed Markdown falls back to plain
    /// text inside ``MarkdownDocument``, and a drawing that cannot be decoded is
    /// left out rather than taking the note's text down with it.
    ///
    /// - Parameters:
    ///   - content: The authored content to lay out.
    ///   - locale: Locale used to format the event date.
    ///   - timeZone: Time zone used to format the event date.
    /// - Returns: A complete PDF file, at least one page long.
    @MainActor
    static func pdfData(
        for content: Content,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: content.title,
            kCGPDFContextCreator as String: "CaseNotes",
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: Page.rect, format: format)

        return renderer.pdfData { context in
            let writer = PageWriter(
                context: context,
                pageRect: Page.rect,
                margin: Page.margin,
                paper: Palette.paper
            )
            writer.beginPage()

            drawHeader(for: content, locale: locale, timeZone: timeZone, into: writer)
            drawBody(content.body, into: writer)

            if let data = content.drawingData, let image = drawingImage(from: data) {
                draw(image, into: writer)
            }
        }
    }

    // MARK: - Header

    /// Draws the title, the event date when there is one, and the rule under them.
    ///
    /// - Parameters:
    ///   - content: The note's authored content.
    ///   - locale: Locale used to format the event date.
    ///   - timeZone: Time zone used to format the event date.
    ///   - writer: The page the header is drawn on.
    @MainActor
    private static func drawHeader(
        for content: Content,
        locale: Locale,
        timeZone: TimeZone,
        into writer: PageWriter
    ) {
        let title = attributed(
            AttributedString(content.title),
            font: .systemFont(ofSize: Metrics.titleSize, weight: .semibold),
            color: Palette.ink,
            style: paragraphStyle(lineSpacing: 1)
        )
        draw(title, into: writer, spacingBefore: 0)

        if let eventDate = content.eventDate {
            let formatted = eventDate.formatted(
                Date.FormatStyle(
                    date: .long,
                    time: .omitted,
                    locale: locale,
                    calendar: locale.calendar,
                    timeZone: timeZone
                )
            )

            let line = attributed(
                AttributedString("Event date: \(formatted)"),
                font: .systemFont(ofSize: Metrics.eventDateSize),
                color: Palette.secondaryInk,
                style: paragraphStyle(lineSpacing: 1)
            )
            draw(line, into: writer, spacingBefore: Metrics.titleToEventDate)
        }

        writer.space(Metrics.headerToRule)
        writer.drawRule(color: Palette.rule)
        writer.advance(Metrics.ruleToBody)
    }

    // MARK: - Body

    /// Draws the parsed note body.
    ///
    /// Blocks are taken straight from the parse, so every region of the note is
    /// present whatever the reading view currently has folded, and a thematic
    /// break lands as the plain rule it is rather than as a control.
    ///
    /// - Parameters:
    ///   - source: The stored Markdown body.
    ///   - writer: The page the body is drawn on.
    @MainActor
    private static func drawBody(_ source: String, into writer: PageWriter) {
        let blocks = MarkdownDocument(source).blocks
        var previous: MarkdownDocument.Block?

        for block in blocks {
            switch block {
            case let .paragraph(text):
                draw(
                    attributed(
                        text,
                        font: .systemFont(ofSize: Metrics.bodySize),
                        color: Palette.ink,
                        style: paragraphStyle()
                    ),
                    into: writer,
                    spacingBefore: Metrics.paragraphSpacing
                )

            case let .heading(level, text):
                draw(
                    attributed(
                        text,
                        font: headingFont(for: level),
                        color: Palette.accent,
                        style: paragraphStyle(lineSpacing: 1)
                    ),
                    into: writer,
                    spacingBefore: headingSpacing(for: level)
                )

            case let .listItem(ordinal, depth, text):
                let spacing: CGFloat
                if case .listItem = previous {
                    spacing = Metrics.listItemSpacing
                } else {
                    spacing = Metrics.paragraphSpacing
                }

                draw(
                    listItem(ordinal: ordinal, text: text),
                    into: writer,
                    indent: CGFloat(depth) * Metrics.listIndentStep,
                    spacingBefore: spacing
                )

            case let .blockQuote(text):
                draw(
                    attributed(
                        text,
                        font: .italicSystemFont(ofSize: Metrics.bodySize),
                        color: Palette.secondaryInk,
                        style: paragraphStyle()
                    ),
                    into: writer,
                    indent: Metrics.quoteIndent,
                    spacingBefore: Metrics.quoteSpacing,
                    decoration: .quote
                )

            case let .codeBlock(_, code):
                draw(
                    NSAttributedString(
                        string: code,
                        attributes: [
                            .font: UIFont.monospacedSystemFont(
                                ofSize: Metrics.codeSize,
                                weight: .regular
                            ),
                            .foregroundColor: Palette.ink,
                            // Code wraps on characters rather than words so a
                            // long identifier or URL folds onto the next line
                            // instead of running off the page.
                            .paragraphStyle: paragraphStyle(
                                lineSpacing: 2,
                                lineBreakMode: .byCharWrapping
                            ),
                        ]
                    ),
                    into: writer,
                    spacingBefore: Metrics.codeSpacing,
                    decoration: .code
                )

            case .thematicBreak:
                writer.space(Metrics.breakSpacing)
                writer.drawRule(color: Palette.rule)
                writer.advance(Metrics.breakSpacing)
            }

            previous = block
        }
    }

    /// Builds a list item as one string, so its marker and its text share a
    /// baseline and wrapped lines line up under the text rather than under the
    /// marker.
    ///
    /// - Parameters:
    ///   - ordinal: The item number, or `nil` for a bulleted item.
    ///   - text: The item's text.
    /// - Returns: The marker, a tab, and the item text.
    private static func listItem(ordinal: Int?, text: AttributedString) -> NSAttributedString {
        let style = paragraphStyle()
        style.headIndent = Metrics.listMarkerColumn
        style.tabStops = [
            NSTextTab(textAlignment: .left, location: Metrics.listMarkerColumn),
        ]
        style.defaultTabInterval = Metrics.listMarkerColumn

        let marker = NSAttributedString(
            string: "\(ordinal.map { "\($0)." } ?? "\u{2022}")\t",
            attributes: [
                .font: UIFont.monospacedDigitSystemFont(
                    ofSize: Metrics.bodySize,
                    weight: .regular
                ),
                .foregroundColor: Palette.accent,
                .paragraphStyle: style,
            ]
        )

        let item = NSMutableAttributedString(attributedString: marker)
        item.append(
            attributed(
                text,
                font: .systemFont(ofSize: Metrics.bodySize),
                color: Palette.ink,
                style: style
            )
        )

        return item
    }

    /// The font a heading level is set in.
    ///
    /// Levels past three share one style, matching read mode: notes rarely nest
    /// deeper, and smaller steps stop reading as headings.
    ///
    /// - Parameter level: The heading level, starting at one.
    /// - Returns: The font for that level.
    private static func headingFont(for level: Int) -> UIFont {
        switch level {
        case 1: .systemFont(ofSize: 16, weight: .semibold)
        case 2: .systemFont(ofSize: 13.5, weight: .semibold)
        default: .systemFont(ofSize: 11.5, weight: .semibold)
        }
    }

    /// The gap above a heading, which is larger for a more senior level so the
    /// page groups under its heading rather than reading as an even stack.
    ///
    /// - Parameter level: The heading level, starting at one.
    /// - Returns: The leading gap in points.
    private static func headingSpacing(for level: Int) -> CGFloat {
        switch level {
        case 1: 18
        case 2: 14
        default: 12
        }
    }

    // MARK: - Text layout

    /// A shared paragraph style for body text.
    ///
    /// - Parameters:
    ///   - lineSpacing: Extra leading between lines.
    ///   - lineBreakMode: How a line too long for the column is broken.
    /// - Returns: A mutable style, so callers can add list indents to it.
    private static func paragraphStyle(
        lineSpacing: CGFloat = Metrics.lineSpacing,
        lineBreakMode: NSLineBreakMode = .byWordWrapping
    ) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.lineBreakMode = lineBreakMode
        return style
    }

    /// Resolves parsed inline Markdown into concrete UIKit attributes.
    ///
    /// The same intents read mode honours are honoured here: bold, italic,
    /// inline code, and links. A link keeps its URL on the run so the drawing
    /// pass can turn it into a real PDF link, and is styled so it still reads as
    /// a link on paper, where nothing is tappable.
    ///
    /// - Parameters:
    ///   - text: A block's text, still carrying inline presentation intent.
    ///   - font: The font the block is set in.
    ///   - color: The block's text color.
    ///   - style: The block's paragraph style.
    /// - Returns: The text with attributes applied to every run.
    private static func attributed(
        _ text: AttributedString,
        font: UIFont,
        color: UIColor,
        style: NSParagraphStyle
    ) -> NSMutableAttributedString {
        let result = NSMutableAttributedString()

        for run in text.runs {
            let intent = run.inlinePresentationIntent ?? []
            var runFont = font

            if intent.contains(.code) {
                runFont = .monospacedSystemFont(
                    ofSize: Metrics.inlineCodeSize,
                    weight: .regular
                )
            }

            var traits: UIFontDescriptor.SymbolicTraits = []
            if intent.contains(.stronglyEmphasized) {
                traits.insert(.traitBold)
            }
            if intent.contains(.emphasized) {
                traits.insert(.traitItalic)
            }
            if !traits.isEmpty {
                runFont = runFont.adding(traits)
            }

            var attributes: [NSAttributedString.Key: Any] = [
                .font: runFont,
                .foregroundColor: color,
                .paragraphStyle: style,
            ]

            if let url = run.link {
                attributes[.foregroundColor] = Palette.link
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                attributes[.link] = url
            }

            result.append(
                NSAttributedString(
                    string: String(text[run.range].characters),
                    attributes: attributes
                )
            )
        }

        return result
    }

    /// Lays out one block and draws it, starting new pages as it runs out of room.
    ///
    /// Core Text does the typesetting. The block is framed into whatever height
    /// is left on the page, asked how much of itself fitted, and the remainder
    /// continues on the next page, which is what lets a long paragraph, a long
    /// list item, or a long code block cross a page boundary without losing a
    /// line at the seam.
    ///
    /// - Parameters:
    ///   - text: The block, fully attributed.
    ///   - writer: The page being written.
    ///   - indent: Extra left inset for the block, used by lists and quotes.
    ///   - spacingBefore: The gap above the block, dropped at the top of a page.
    ///   - decoration: A background or rule drawn with the block.
    @MainActor
    private static func draw(
        _ text: NSAttributedString,
        into writer: PageWriter,
        indent: CGFloat = 0,
        spacingBefore: CGFloat,
        decoration: Decoration = .none
    ) {
        guard text.length > 0 else {
            return
        }

        writer.space(spacingBefore)

        let padding = decoration == .code ? Metrics.codePadding : 0
        let columnWidth = writer.contentWidth - indent - 2 * padding
        guard columnWidth > 0 else {
            return
        }

        let framesetter = CTFramesetterCreateWithAttributedString(text)
        var location = 0

        while location < text.length {
            if writer.remainingHeight < Metrics.minimumFragmentHeight + 2 * padding,
               !writer.isAtTopOfPage {
                writer.beginPage()
            }

            let available = writer.remainingHeight - 2 * padding
            guard available > 0 else {
                break
            }

            let originX = writer.contentOriginX + indent + padding
            let top = writer.cursorY + padding
            let frameRect = writer.pdfRect(x: originX, top: top, width: columnWidth, height: available)
            let path = CGPath(rect: frameRect, transform: nil)
            let frame = CTFramesetterCreateFrame(
                framesetter,
                CFRange(location: location, length: 0),
                path,
                nil
            )

            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else {
                // Nothing fitted. On a fresh page that means the block cannot be
                // laid out at all, so stop rather than paging forever.
                if writer.isAtTopOfPage {
                    return
                }
                writer.beginPage()
                continue
            }

            let used = usedHeight(of: frame, in: frameRect)

            switch decoration {
            case .none:
                break
            case .code:
                writer.fill(
                    rect: CGRect(
                        x: writer.contentOriginX + indent,
                        y: writer.cursorY,
                        width: columnWidth + 2 * padding,
                        height: used + 2 * padding
                    ),
                    color: Palette.codeBackground,
                    cornerRadius: 4
                )
            case .quote:
                writer.fill(
                    rect: CGRect(
                        x: writer.contentOriginX,
                        y: writer.cursorY,
                        width: Metrics.quoteRuleWidth,
                        height: used
                    ),
                    color: Palette.accent,
                    cornerRadius: 1
                )
            }

            writer.drawFrame(frame)
            writer.linkAnnotations(in: frame)

            writer.advance(used + 2 * padding)
            location += visible.length

            if location < text.length {
                writer.beginPage()
            }
        }
    }

    /// How much vertical room a laid out frame actually used.
    ///
    /// Measured from the frame's own lines rather than estimated, so the next
    /// block starts exactly under this one and no gap accumulates down the page.
    ///
    /// Core Text reports line origins relative to the frame path's bounding box
    /// rather than in page coordinates, which was measured with a throwaway
    /// probe. Treating them as absolute silently adds the page margin to every
    /// block, which is invisible to a test that only reads the text back and was
    /// caught by looking at a rendered page.
    ///
    /// - Parameters:
    ///   - frame: The laid out frame.
    ///   - rect: The rectangle the frame was laid out in, in PDF coordinates.
    /// - Returns: The height occupied by the visible lines.
    private static func usedHeight(of frame: CTFrame, in rect: CGRect) -> CGFloat {
        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        guard let last = lines.last else {
            return 0
        }

        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        var descent: CGFloat = 0
        CTLineGetTypographicBounds(last, nil, &descent, nil)

        guard let lastOrigin = origins.last else {
            return 0
        }

        return min(rect.height - lastOrigin.y + descent, rect.height)
    }

    // MARK: - Drawing

    /// Rasterizes a stored drawing for the page.
    ///
    /// Rendering is pinned to the light appearance for the same reason the
    /// reading view pins it: PencilKit inverts ink for dark mode as it
    /// rasterizes, which would turn a black sketch white on white paper.
    ///
    /// - Parameter data: The stored drawing bytes.
    /// - Returns: The rendered image, or `nil` when the drawing is empty or the
    ///   bytes do not decode. Both cases mean the same thing for a document:
    ///   there is nothing to show, so nothing is added.
    @MainActor
    private static func drawingImage(from data: Data) -> UIImage? {
        let drawing = DrawingCodec.decode(data)

        guard !drawing.bounds.isEmpty else {
            return nil
        }

        let bounds = drawing.bounds.insetBy(
            dx: -Metrics.drawingInset,
            dy: -Metrics.drawingInset
        )

        var rendered: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            rendered = drawing.image(from: bounds, scale: Metrics.drawingScale)
        }

        return rendered
    }

    /// Places a rendered drawing on the page.
    ///
    /// The aspect ratio is kept throughout. A drawing wider than the column is
    /// scaled down to it, never stretched and never upscaled; one too tall for
    /// the room left moves to the next page; and one too tall for a whole page
    /// is scaled to fit that page rather than being cut off.
    ///
    /// - Parameters:
    ///   - image: The rasterized drawing.
    ///   - writer: The page being written.
    @MainActor
    private static func draw(_ image: UIImage, into writer: PageWriter) {
        guard image.size.width > 0, image.size.height > 0 else {
            return
        }

        writer.space(Metrics.drawingSpacing)

        let widthScale = min(writer.contentWidth / image.size.width, 1)
        var size = CGSize(
            width: image.size.width * widthScale,
            height: image.size.height * widthScale
        )

        if size.height > writer.remainingHeight, !writer.isAtTopOfPage {
            writer.beginPage()
        }

        if size.height > writer.remainingHeight {
            let heightScale = writer.remainingHeight / size.height
            size = CGSize(width: size.width * heightScale, height: writer.remainingHeight)
        }

        writer.draw(
            image,
            in: CGRect(
                x: writer.contentOriginX,
                y: writer.cursorY,
                width: size.width,
                height: size.height
            )
        )
        writer.advance(size.height)
    }
}

/// Tracks where the next block goes and owns everything that touches the page.
///
/// Kept separate from layout so the rules about pages live in one place: a page
/// is only started when there is something to put on it, which is what keeps a
/// document from opening on a blank page or ending with one.
@MainActor
private final class PageWriter {
    private let context: UIGraphicsPDFRendererContext
    private let pageRect: CGRect
    private let margin: CGFloat
    private let paper: UIColor

    /// Distance from the top of the page to where the next block starts.
    private(set) var cursorY: CGFloat

    init(
        context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        margin: CGFloat,
        paper: UIColor
    ) {
        self.context = context
        self.pageRect = pageRect
        self.margin = margin
        self.paper = paper
        cursorY = margin
    }

    var contentOriginX: CGFloat { margin }
    var contentWidth: CGFloat { pageRect.width - 2 * margin }
    var remainingHeight: CGFloat { pageRect.height - margin - cursorY }
    var isAtTopOfPage: Bool { cursorY <= margin + 0.5 }

    /// Starts a page and paints its ground.
    ///
    /// The paper color is drawn rather than left to the viewer, so the document
    /// looks the same in Files, in Preview, and on a printer.
    func beginPage() {
        context.beginPage()
        context.cgContext.setFillColor(paper.cgColor)
        context.cgContext.fill(pageRect)
        cursorY = margin
    }

    /// Moves the cursor down.
    ///
    /// - Parameter amount: Points to advance.
    func advance(_ amount: CGFloat) {
        cursorY += amount
    }

    /// Leaves a gap, unless the cursor is already at the top of a page.
    ///
    /// A block that begins a page needs no gap above it, and adding one would
    /// leave a visible indent at the top of every continuation page.
    ///
    /// - Parameter amount: Points to leave.
    func space(_ amount: CGFloat) {
        guard !isAtTopOfPage else {
            return
        }
        cursorY += amount
    }

    /// Draws a hairline across the text column and advances past it.
    ///
    /// - Parameter color: The rule's color.
    func drawRule(color: UIColor) {
        if remainingHeight < 1, !isAtTopOfPage {
            beginPage()
        }

        fill(
            rect: CGRect(x: contentOriginX, y: cursorY, width: contentWidth, height: 0.75),
            color: color,
            cornerRadius: 0
        )
        cursorY += 0.75
    }

    /// Fills a rounded rectangle in page coordinates.
    ///
    /// - Parameters:
    ///   - rect: The rectangle, measured from the top left of the page.
    ///   - color: The fill color.
    ///   - cornerRadius: Corner radius, zero for a square rectangle.
    func fill(rect: CGRect, color: UIColor, cornerRadius: CGFloat) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
        context.cgContext.setFillColor(color.cgColor)
        context.cgContext.addPath(path.cgPath)
        context.cgContext.fillPath()
    }

    /// Draws an image in page coordinates.
    ///
    /// - Parameters:
    ///   - image: The image to draw.
    ///   - rect: Where to draw it, measured from the top left of the page.
    func draw(_ image: UIImage, in rect: CGRect) {
        image.draw(in: rect)
    }

    /// Converts a rectangle measured from the top of the page into the PDF
    /// coordinate space Core Text lays out in.
    ///
    /// - Parameters:
    ///   - x: Left edge.
    ///   - top: Distance from the top of the page to the rectangle's top edge.
    ///   - width: Rectangle width.
    ///   - height: Rectangle height.
    /// - Returns: The same rectangle with its origin at the bottom left of the page.
    func pdfRect(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(x: x, y: pageRect.height - top - height, width: width, height: height)
    }

    /// Draws a laid out Core Text frame.
    ///
    /// `UIGraphicsPDFRenderer` installs a flipped transform so UIKit drawing
    /// reads top down. Core Text expects the native PDF space, so the flip is
    /// undone for the duration of the draw and the frame's own path, already
    /// built in that space, lands in the right place with upright glyphs.
    ///
    /// - Parameter frame: The frame to draw.
    func drawFrame(_ frame: CTFrame) {
        let cgContext = context.cgContext

        cgContext.saveGState()
        cgContext.translateBy(x: 0, y: pageRect.height)
        cgContext.scaleBy(x: 1, y: -1)
        CTFrameDraw(frame, cgContext)
        cgContext.restoreGState()
    }

    /// Adds a real PDF link for every linked run in a laid out frame.
    ///
    /// Core Text draws a link's text but knows nothing about PDF annotations,
    /// so the run rectangles are walked once after drawing and handed to the
    /// renderer. The cost is one pass over the lines that were just laid out,
    /// and the result is a document whose links can actually be followed.
    ///
    /// - Parameter frame: The frame that was just drawn.
    func linkAnnotations(in frame: CTFrame) {
        let lines = CTFrameGetLines(frame) as? [CTLine] ?? []
        guard !lines.isEmpty else {
            return
        }

        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)

        // Line origins are relative to the frame path's bounding box, so the
        // path's own origin is what puts a run back on the page.
        let frameOrigin = CTFrameGetPath(frame).boundingBox.origin

        for (index, line) in lines.enumerated() {
            let origin = origins[index]
            let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []

            for run in runs {
                let attributes = CTRunGetAttributes(run) as NSDictionary
                guard let url = attributes[NSAttributedString.Key.link] as? URL else {
                    continue
                }

                var ascent: CGFloat = 0
                var descent: CGFloat = 0
                let width = CGFloat(
                    CTRunGetTypographicBounds(
                        run,
                        CFRange(location: 0, length: 0),
                        &ascent,
                        &descent,
                        nil
                    )
                )

                let stringRange = CTRunGetStringRange(run)
                let offset = CTLineGetOffsetForStringIndex(line, stringRange.location, nil)

                // Measured with a throwaway probe rather than assumed: this
                // takes the rectangle in native PDF page coordinates, with the
                // origin at the bottom left, and does not apply the flipped
                // transform the renderer installs for UIKit drawing.
                context.setURL(
                    url,
                    for: CGRect(
                        x: frameOrigin.x + origin.x + offset,
                        y: frameOrigin.y + origin.y - descent,
                        width: width,
                        height: ascent + descent
                    )
                )
            }
        }
    }
}

private extension UIFont {
    /// Adds symbolic traits while keeping the ones the font already has.
    ///
    /// Applying bold to an italic run has to leave it italic, which a plain
    /// descriptor replacement would not.
    ///
    /// - Parameter traits: Traits to add.
    /// - Returns: The font with the combined traits, or the original font when
    ///   the family has no such face.
    func adding(_ traits: UIFontDescriptor.SymbolicTraits) -> UIFont {
        let combined = fontDescriptor.symbolicTraits.union(traits)

        guard let descriptor = fontDescriptor.withSymbolicTraits(combined) else {
            return self
        }

        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
