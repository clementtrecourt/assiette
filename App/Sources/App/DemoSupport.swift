import Foundation
import SwiftData

/// Demo mode used by CI to take simulator screenshots of every screen.
/// Launch arguments:
///   -demo                 seed a realistic profile + 30 days of journal/weights (fresh store only)
///   -startTab <name>      today | progress (Accueil) | program | profile
///   -startSheet <name>    search | scan | quickadd | detail | add   (presented from the journal)
///                         wizard | wizard-summary                 (presented from Programme)
///   -startRoute <name>    expenditure | weight | goal | balance  (pushed on Accueil)
///   -updateBanner         show the "new version" banner with a fake build
enum DemoSupport {
    static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static var isDemo: Bool { arguments.contains("-demo") }

    static func value(after flag: String) -> String? {
        guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
        return arguments[i + 1]
    }

    static var startTab: AppTab? {
        switch value(after: "-startTab") {
        case "today": .today
        case "progress", "dashboard": .progress
        case "program": .program
        case "profile": .profile
        default: nil
        }
    }

    static var startSheet: String? { value(after: "-startSheet") }

    /// Page of Accueil's header carousel shown at launch (`-heroPage 1|2`).
    static var heroPage: Int? { value(after: "-heroPage").flatMap(Int.init) }

    /// Dashboard detail screen pushed at launch (`-startRoute expenditure|weight|goal|balance`).
    static var startRoute: DashboardRoute? {
        switch value(after: "-startRoute") {
        case "expenditure": .expenditure
        case "weight": .weightTrend
        case "goal": .goal
        case "balance": .energyBalance
        default: nil
        }
    }

    /// A food used for the "detail" / "add" demo sheets.
    static var sampleItem: FoodItem {
        FoodDatabase.shared.search("chicken breast cooked", limit: 1).first?.item
            ?? FoodItem(source: .quickAdd, ref: nil, name: "Poulet grillé", brand: nil, kind: .everyday,
                        servingLabel: "3 oz", servingGrams: 85, packageGrams: nil, isLiquid: false,
                        ean: nil, per100: NutrientValues([.calories: 165, .protein: 31, .totalFat: 3.6]))
    }

    private struct Planned {
        let query: String
        let grams: Double
        let hour: Int
        let minute: Int
        let meal: Meal
    }

    private static let dayPlan: [Planned] = [
        Planned(query: "rolled oats", grams: 60, hour: 7, minute: 45, meal: .breakfast),
        Planned(query: "banana", grams: 118, hour: 7, minute: 46, meal: .breakfast),
        Planned(query: "reduced fat milk", grams: 150, hour: 7, minute: 47, meal: .breakfast),
        Planned(query: "chicken breast cooked", grams: 150, hour: 12, minute: 50, meal: .lunch),
        Planned(query: "basmati rice cooked", grams: 200, hour: 12, minute: 51, meal: .lunch),
        Planned(query: "skyr plain", grams: 150, hour: 16, minute: 15, meal: .snack),
        Planned(query: "almonds", grams: 30, hour: 16, minute: 16, meal: .snack),
        Planned(query: "atlantic salmon cooked", grams: 160, hour: 20, minute: 10, meal: .dinner),
        Planned(query: "sweet potato baked", grams: 200, hour: 20, minute: 11, meal: .dinner),
        Planned(query: "broccoli steamed", grams: 120, hour: 20, minute: 12, meal: .dinner),
    ]

    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        guard isDemo else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<JournalEntry>())) ?? 0
        guard existing == 0 else { return }

        let profile = UserProfile.current(in: context)
        profile.hasCompletedOnboarding = true
        profile.sex = .male
        profile.birthYear = 1994
        profile.heightCm = 180
        profile.weightKg = 82
        profile.activity = .moderate
        profile.goal = .lose
        profile.weeklyRateKg = 0.5
        profile.targetWeightKg = 78
        // Coached program like the reference: last check-in yesterday, next one in a few days.
        profile.manualTargets = false
        profile.lastCheckInDate = Date.now.startOfDay.adding(days: -1)
        profile.checkInWeekday = (Calendar.current.component(.weekday, from: .now) + 4) % 7 + 1
        profile.calorieTarget = 2200
        profile.proteinTarget = 150
        profile.carbsTarget = 240
        profile.fatTarget = 70

        let items: [FoodItem?] = dayPlan.map { FoodDatabase.shared.search($0.query, limit: 1).first?.item }
        let cal = Calendar.current
        let today = Date.now.startOfDay
        // Screenshots must show a few meals even early in the day: pretend it is at least 17:00.
        let nowMinutes = max(cal.component(.hour, from: .now) * 60 + cal.component(.minute, from: .now), 17 * 60)

        for offset in 0..<30 {
            let day = today.adding(days: -offset)
            for (index, plan) in dayPlan.enumerated() {
                guard let item = items[index] else { continue }
                // Today: only what has "already been eaten" (dinner left empty for screenshots).
                if offset == 0 && (plan.meal == .dinner || plan.hour * 60 + plan.minute > nowMinutes) { continue }
                // Some variety across days.
                if offset % 3 == 1 && plan.meal == .snack { continue }
                let factor = 1 + Double((offset * 7 + index * 3) % 5 - 2) * 0.08
                let entry = JournalEntry(item: item, grams: (plan.grams * factor).rounded(), day: day, meal: plan.meal)
                entry.createdAt = cal.date(bySettingHour: plan.hour, minute: plan.minute, second: 0, of: day) ?? day
                context.insert(entry)
            }
            let kg = 82 - Double(30 - offset) * 0.11 + sin(Double(offset)) * 0.3
            context.insert(WeightEntry(date: cal.date(bySettingHour: 7, minute: 30, second: 0, of: day) ?? day,
                                       kg: (kg * 10).rounded() / 10))
            for _ in 0..<(offset == 0 ? 5 : 8) { context.insert(WaterEntry(day: day, ml: 250)) }
        }
        // Initials avatar on the Profil header, like the reference.
        UserDefaults.standard.set("Alex Martin", forKey: "profile.displayName")
        // Favorites row of the search tab (reference shows four).
        for index in [0, 3, 5, 6] {
            if let item = items[index] { context.insert(FavoriteFood(item: item)) }
        }
        try? context.save()
    }
}
