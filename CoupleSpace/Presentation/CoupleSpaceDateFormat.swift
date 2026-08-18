import Foundation

enum CoupleSpaceDateFormat {
    private static let locale = Locale(identifier: "zh-Hant-TW")

    static func string(
        _ date: Date,
        date dateStyle: Date.FormatStyle.DateStyle,
        time timeStyle: Date.FormatStyle.TimeStyle
    ) -> String {
        date.formatted(
            Date.FormatStyle(date: dateStyle, time: timeStyle, locale: locale)
        )
    }

    static func yearMonth(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().year().month(.wide).locale(locale))
    }

    static func yearMonthDay(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().year().month().day().locale(locale))
    }
}
