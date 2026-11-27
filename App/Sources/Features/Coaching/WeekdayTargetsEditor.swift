import SwiftUI

struct WeekdayTargetsEditor: View {
    let profile: UserProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.weekdayCalorieTargets) private var overrides
    /// Only write fields the user touched; another weekday may have changed during editing.
    @State private var edits: [Int: String] = [:]
    @FocusState private var focusedDay: Int?

    private var valid: Bool {
        edits.values.allSatisfy { $0.isEmpty || Int($0).map(WeekdayCalorieTargets.allowedCalories.contains) == true }
    }

    var body: some View {
        let base = ProgramPreferences.current.weekCalories(average: profile.calorieTarget)
        NavigationStack {
            Form {
                Section {
                    ForEach(1...7, id: \.self) { day in
                        let weekday = CoachingFormat.mondayFirstWeekdays[day - 1]
                        let name = CoachingFormat.capitalized(CoachingFormat.weekdayName(weekday))
                        HStack {
                            Text(name)
                            Spacer()
                            TextField(CoachingFormat.kcalNumber(base[day - 1]), text: Binding(
                                get: { edits[day] ?? overrides.values[day].map(String.init) ?? "" },
                                set: { edits[day] = $0 }
                            ))
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .monospacedDigit()
                            .focused($focusedDay, equals: day)
                            .accessibilityLabel("Objectif du \(name.lowercased())")
                            Text("kcal").foregroundStyle(Theme.textSecondary)
                        }
                    }
                } header: {
                    ProfileSectionHeader("Calories par jour de la semaine")
                } footer: {
                    ProfileSectionFooter("Saisissez entre 800 et 10 000 kcal. Laissez un champ vide pour suivre le programme (valeur en gris). Un objectif saisi se répète chaque semaine, même après un bilan, sans modifier les autres jours.")
                }
                .listRowBackground(Theme.background)
            }
            .font(Theme.body)
            .themedBackground()
            .navigationTitle("Objectifs par jour")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer", action: save).disabled(!valid) }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Terminé") { focusedDay = nil }
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(450))
                focusedDay = CoachingFormat.mondayIndex(of: .now) + 1
            }
        }
        .presentationBackground(Theme.background)
    }

    private func save() {
        guard valid else { return }
        for (day, text) in edits {
            WeekdayCalorieTargets.set(Int(text), forISOWeekday: day)
        }
        dismiss()
    }
}
