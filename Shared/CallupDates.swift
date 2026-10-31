//
//  CallupDates.swift
//  CallupTracker
//
//  Day strings shared by the app, its notifications, and the widget.
//

import Foundation

/// "yyyy-MM-dd" day strings, the form the MLB Stats API takes and returns.
///
/// The transaction feed is dated in US Eastern time, so "today" is the Eastern
/// date wherever the device is. ISO 8601 styles always use the Gregorian
/// calendar, so a Buddhist or Japanese device calendar can't shift the year.
/// A member of both the CallupTracker and CallupWidgetExtension targets.
nonisolated enum CallupDates {

    static let feedTimeZone = TimeZone(identifier: "America/New_York")!

    private static let utc = TimeZone(identifier: "UTC")!

    private static func dayStyle(_ timeZone: TimeZone) -> Date.ISO8601FormatStyle {
        Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day()
    }

    private static let feedStyle = dayStyle(feedTimeZone)
    private static let utcStyle = dayStyle(utc)
    private static let historyStyle = Date.FormatStyle(date: .abbreviated, time: .omitted, timeZone: utc)

    /// Today in the feed's time zone.
    static func today(now: Date = .now) -> String {
        feedStyle.format(now)
    }

    /// The day `date` falls on in the device's time zone, which is the day a
    /// date picker shows for it.
    static func localDay(of date: Date) -> String {
        dayStyle(.current).format(date)
    }

    /// Midnight on `day` in the device's time zone, for a date picker selection.
    static func localDate(of day: String) -> Date? {
        try? dayStyle(.current).parse(day)
    }

    /// The day before `day`, or nil if it doesn't parse.
    static func dayBefore(_ day: String) -> String? {
        self.day(day, offsetBy: -1)
    }

    /// The day `days` after `day` (before, if negative), or nil if it doesn't parse.
    static func day(_ day: String, offsetBy days: Int) -> String? {
        guard let date = try? utcStyle.parse(day) else { return nil }
        return utcStyle.format(date.addingTimeInterval(Double(days) * 86_400))
    }

    /// `day` for display, like "Oct 31, 2026"; `day` itself if it doesn't parse.
    static func displayString(for day: String) -> String {
        guard let date = try? utcStyle.parse(day) else { return day }
        return historyStyle.format(date)
    }
}
