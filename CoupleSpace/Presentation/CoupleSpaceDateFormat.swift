import Foundation

enum CoupleSpaceTimeFormat: String, CaseIterable, Identifiable {
    case twelveHour
    case twentyFourHour
    case followSystem

    static let defaultsKey = "couplespace.time-format"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .twelveHour: "12 小時"
        case .twentyFourHour: "24 小時"
        case .followSystem: "跟隨系統設置"
        }
    }

    static var current: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .followSystem
    }
}

enum CoupleSpaceDateFormat {
    private static let locale = Locale(identifier: "zh-Hant-TW")

    static func string(
        _ date: Date,
        date dateStyle: Date.FormatStyle.DateStyle,
        time timeStyle: Date.FormatStyle.TimeStyle,
        timeFormat: CoupleSpaceTimeFormat = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(
            dateTemplate(for: dateStyle) + timeTemplate(for: timeStyle, format: timeFormat)
        )
        return formatter.string(from: date)
    }

    static func yearMonth(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().year().month(.wide).locale(locale))
    }

    static func yearMonthDay(_ date: Date) -> String {
        date.formatted(Date.FormatStyle().year().month().day().locale(locale))
    }

    private static func dateTemplate(for style: Date.FormatStyle.DateStyle) -> String {
        return switch style {
        case .omitted: ""
        case .numeric: "yMd"
        case .abbreviated: "yMMMd"
        case .long: "yMMMMd"
        case .complete: "yMMMMEEEEd"
        default: "yMMMd"
        }
    }

    private static func timeTemplate(
        for style: Date.FormatStyle.TimeStyle,
        format: CoupleSpaceTimeFormat
    ) -> String {
        guard style != .omitted else { return "" }
        let hour = uses24HourClock(for: format) ? "HH" : "h"
        return switch style {
        case .shortened: hour + "mm"
        case .standard: hour + "mmss"
        case .complete: hour + "mmsszzzz"
        case .omitted: ""
        default: hour + "mm"
        }
    }

    private static func uses24HourClock(for format: CoupleSpaceTimeFormat) -> Bool {
        switch format {
        case .twelveHour:
            return false
        case .twentyFourHour:
            return true
        case .followSystem:
            let systemHourFormat = DateFormatter.dateFormat(
                fromTemplate: "j",
                options: 0,
                locale: .autoupdatingCurrent
            ) ?? ""
            return !systemHourFormat.contains("a")
        }
    }
}
