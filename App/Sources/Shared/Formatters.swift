import Foundation

enum Formatters {
    static let locale = Locale(identifier: "fr_FR")

    /// French number formatting ("1 234,5").
    static func number(_ value: Double, maxFractionDigits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxFractionDigits)).locale(locale))
    }

    /// "1 850 kcal"
    static func kcal(_ value: Double) -> String { "\(number(value, maxFractionDigits: 0)) kcal" }

    /// Amount with the nutrient unit and a sensible precision: "12,3 g", "450 mg", "2,4 µg".
    static func amount(_ value: Double, of key: NutrientKey) -> String {
        let digits: Int
        switch value {
        case 100...: digits = 0
        case 10..<100: digits = key == .calories ? 0 : 1
        case 1..<10: digits = 1
        default: digits = 2
        }
        return "\(number(value, maxFractionDigits: digits)) \(key.unit)"
    }

    /// "23 %"
    static func percent(_ fraction: Double) -> String {
        "\(number(fraction * 100, maxFractionDigits: 0)) %"
    }

    /// "lundi 19 novembre"
    static func dayTitle(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Aujourd'hui" }
        if cal.isDateInYesterday(date) { return "Hier" }
        if cal.isDateInTomorrow(date) { return "Demain" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(locale))
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }
}
