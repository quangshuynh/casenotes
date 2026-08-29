//
//  ListDateStyleTests.swift
//  CaseNotesTests
//
//  Created by q on 8/29/26.
//

import Foundation
import Testing
@testable import CaseNotes

/// Covers how a browsing row decides how much of a date to spell out.
struct ListDateStyleTests {
    /// A fixed calendar so the rules are tested rather than the host's region.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    private let locale = Locale(identifier: "en_US")

    /// - Parameters:
    ///   - year: Calendar year.
    ///   - month: Month of the year.
    ///   - day: Day of the month.
    ///   - hour: Hour of the day.
    ///   - minute: Minute of the hour.
    /// - Returns: That moment in UTC.
    /// - Throws: When the components do not describe a real date.
    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0
    ) throws -> Date {
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )

        return try #require(components.date)
    }

    @Test
    func todayIsToldByItsTime() throws {
        let style = ListDateStyle.style(
            for: try date(2026, 8, 29, 11, 42),
            relativeTo: try date(2026, 8, 29, 16, 5),
            calendar: calendar
        )

        #expect(style == .time)
    }

    @Test
    func yesterdayIsNotTreatedAsTodayEvenHoursApart() throws {
        // The rule is a calendar day rather than a rolling day, so a note
        // written late last night must not read as a bare time this morning.
        let style = ListDateStyle.style(
            for: try date(2026, 8, 28, 23, 50),
            relativeTo: try date(2026, 8, 29, 0, 30),
            calendar: calendar
        )

        #expect(style == .dayAndMonth)
    }

    @Test
    func earlierThisYearDropsTheYear() throws {
        let style = ListDateStyle.style(
            for: try date(2026, 1, 4),
            relativeTo: try date(2026, 8, 29),
            calendar: calendar
        )

        #expect(style == .dayAndMonth)
    }

    @Test
    func anEarlierYearIsSpelledInFull() throws {
        let style = ListDateStyle.style(
            for: try date(2025, 12, 31),
            relativeTo: try date(2026, 1, 1),
            calendar: calendar
        )

        #expect(style == .full)
    }

    @Test
    func renderedTextMatchesTheChosenStyle() throws {
        let reference = try date(2026, 8, 29, 16, 5)

        // Contains rather than equals: the platform separates the time from
        // the meridiem with a narrow space that is not worth pinning a test to.
        let today = ListDateStyle.text(
            for: try date(2026, 8, 29, 11, 42),
            relativeTo: reference,
            calendar: calendar,
            locale: locale
        )

        #expect(today.contains("11:42"))
        #expect(today.contains("AM"))
        #expect(today.contains("Aug") == false)

        #expect(
            ListDateStyle.text(
                for: try date(2026, 1, 4),
                relativeTo: reference,
                calendar: calendar,
                locale: locale
            ) == "Jan 4"
        )

        #expect(
            ListDateStyle.text(
                for: try date(2023, 11, 15),
                relativeTo: reference,
                calendar: calendar,
                locale: locale
            ) == "Nov 15, 2023"
        )
    }

    @Test
    func timeIsKeptOnAnEarlierDayWhenAskedFor() throws {
        // Version history rows ask for this: two versions of one note are often
        // minutes apart, so a bare day would leave them looking identical.
        let text = ListDateStyle.text(
            for: try date(2026, 1, 4, 9, 15),
            relativeTo: try date(2026, 8, 29, 16, 5),
            includingTime: true,
            calendar: calendar,
            locale: locale
        )

        #expect(text.contains("Jan 4"))
        #expect(text.contains("9:15"))
    }

    @Test
    func spokenTextAlwaysNamesTheWholeDate() throws {
        // A row read aloud arrives without the context that makes a bare time
        // or a missing year obvious.
        let spoken = ListDateStyle.spokenText(
            for: try date(2026, 8, 29, 11, 42),
            locale: locale
        )

        #expect(spoken.contains("2026"))
        #expect(spoken.contains("Aug"))
    }
}
