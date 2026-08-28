//
//  Theme.swift
//  CaseNotes
//
//  Created by q on 8/27/26.
//

import SwiftUI

/// The shared visual vocabulary for CaseNotes.
///
/// The palette is designed dark first: a warm near-black canvas, warm off-white
/// text, and an amber accent. Light mode mirrors the same warmth with a cream
/// canvas so the app keeps one personality in either appearance.
///
/// Concrete color values live in the asset catalog rather than in Swift so they
/// remain editable in Xcode and adapt to the system appearance automatically.
/// Views should reference these tokens instead of declaring their own colors,
/// spacing, or corner radii.
enum Theme {
    /// Semantic colors backed by asset catalog color sets.
    ///
    /// Names describe the role a color plays, not the color itself, so the
    /// palette can be retuned in one place without touching view code.
    enum Colors {
        /// Background behind scrolling content and full-screen states.
        static let canvas = Color(.appCanvas)

        /// Background for raised content such as list rows and form sections.
        static let surface = Color(.appSurface)

        /// Hairline dividers and subtle borders.
        static let separator = Color(.appSeparator)

        /// Titles and body copy.
        static let textPrimary = Color(.appTextPrimary)

        /// Supporting copy such as note previews.
        static let textSecondary = Color(.appTextSecondary)

        /// Timestamps and other low-emphasis metadata.
        static let textTertiary = Color(.appTextTertiary)

        /// Interactive tint, sourced from the app-wide accent color so system
        /// controls and custom views stay in agreement.
        static let accent = Color.accentColor

        /// Background for drawings, in both appearances.
        ///
        /// Sketches keep a light paper ground on purpose. PencilKit ink is
        /// stored with the color it was drawn in, so dark ink on a dark canvas
        /// would vanish. Fixing the ground means a drawing looks the same while
        /// it is made, while it is read, and in either appearance.
        static let paper = Color(.appPaper)
    }

    /// Layout spacing steps.
    ///
    /// Values are deliberately few so vertical rhythm stays consistent across
    /// screens.
    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
    }

    /// Corner radii for surfaces and controls.
    enum Radius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 14
    }
}

extension View {
    /// Replaces the default scroll background of a `List` or `Form` with the
    /// warm app canvas.
    ///
    /// SwiftUI paints its own grouped background behind scrolling containers,
    /// so it has to be hidden before the canvas becomes visible.
    ///
    /// - Returns: The view drawn over the app canvas.
    func appCanvasBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.Colors.canvas)
    }
}
