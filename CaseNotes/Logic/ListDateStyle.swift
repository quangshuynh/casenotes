//
//  ListDateStyle.swift
//  CaseNotes
//
//  Created by q on 8/29/26.
//

import Foundation

/// How a date is spelled inside a compact list row.
///
/// A browsing list is scanned rather than read, so a date there earns its space
/// only by saying what a glance needs: the time for something written today,
/// the day and month within the current year, and the year only once it
/// actually distinguishes anything.
///
/// The choice is separated from the formatting so it can be tested without
/// depending on the machine's calendar, time zone, or region.
enum ListDateStyle: Equatable {
    /// Written today, so only the time tells two notes apart.
    case time

    /// Written earlier in the same calendar year.
    case dayAndMonth

    /// Written in an earlier year, where the year is the useful part.
    case full

    /// Chooses how far a date needs to be spelled out.
    ///
    /// - Parameters:
    ///   - date: The date being shown.
    ///   - reference: The moment the list is being read, usually now.
    ///   - calendar: The calendar deciding what counts as today and as this
    ///     year. Injectable so tests do not depend on the host.
    /// - Returns: The style to render the date with.
    static func style(
        for date: Date,
        relativeTo reference: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> ListDateStyle {
        if calendar.isDate(date, inSameDayAs: reference) {
            return .time
        }

        let year = calendar.component(.year, from: date)
        let referenceYear = calendar.component(.year, from: reference)

        return year == referenceYear ? .dayAndMonth : .full
    }

    /// Renders a date the way a list row should show it.
    ///
    /// - Parameters:
    ///   - date: The date being shown.
    ///   - reference: The moment the list is being read, usually now.
    ///   - includingTime: Whether to keep the time of day on a date from an
    ///     earlier day. Version history needs it, because two versions of one
    ///     note are often minutes apart, while a notes list does not.
    ///   - calendar: The calendar deciding what counts as today and as this
    ///     year.
    ///   - locale: The locale the result is formatted for.
    /// - Returns: A short string such as a time, a day and month, or a full date.
    static func text(
        for date: Date,
        relativeTo reference: Date,
        includingTime: Bool = false,
        calendar: Calendar = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let style = style(for: date, relativeTo: reference, calendar: calendar)
        let time: Date.FormatStyle.TimeStyle = includingTime ? .shortened : .omitted

        switch style {
        case .time:
            return date.formatted(
                configured(
                    Date.FormatStyle(date: .omitted, time: .shortened),
                    calendar: calendar,
                    locale: locale
                )
            )
        case .dayAndMonth:
            return date.formatted(
                configured(
                    Date.FormatStyle(date: .omitted, time: time)
                        .month(.abbreviated)
                        .day(),
                    calendar: calendar,
                    locale: locale
                )
            )
        case .full:
            return date.formatted(
                configured(
                    Date.FormatStyle(date: .abbreviated, time: time),
                    calendar: calendar,
                    locale: locale
                )
            )
        }
    }

    /// Pins a format style to a calendar, its time zone, and a locale.
    ///
    /// Formatting otherwise reads the host's own settings, which would make the
    /// result vary by region and by machine rather than by the caller's intent.
    ///
    /// - Parameters:
    ///   - style: The style to configure.
    ///   - calendar: The calendar and time zone to format in.
    ///   - locale: The locale to format for.
    /// - Returns: The configured style.
    private static func configured(
        _ style: Date.FormatStyle,
        calendar: Calendar,
        locale: Locale
    ) -> Date.FormatStyle {
        var configured = style
        configured.calendar = calendar
        configured.timeZone = calendar.timeZone
        configured.locale = locale

        return configured
    }

    /// The same date spelled in full, for anyone listening rather than glancing.
    ///
    /// VoiceOver reads a row out of the context that makes a bare time or a
    /// missing year obvious, so the spoken form always names the whole date.
    ///
    /// - Parameters:
    ///   - date: The date being described.
    ///   - locale: The locale the result is formatted for.
    /// - Returns: A full date with the time of day.
    static func spokenText(
        for date: Date,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.locale = locale

        return date.formatted(style)
    }
}
