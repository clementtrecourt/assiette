import SwiftData
import SwiftUI
import UIKit

/// Sheet to log a weighing (own NavigationStack).
struct ProgressAddWeightSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var date: Date = .now
    @State private var text: String
    @FocusState private var fieldFocused: Bool

    init(initialKg: Double?) {
        _text = State(initialValue: initialKg.map { Formatters.number($0, maxFractionDigits: 1) } ?? "")
    }

    private var parsedKg: Double? { ProgressWeightSync.parseKg(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: ...Date.now,
                               displayedComponents: [.date, .hourAndMinute])
                        .tint(Theme.calories)
                        .font(Theme.body)
                        .foregroundStyle(Theme.textBody)
                    HStack {
                        Label("Poids", systemImage: "scalemass")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textBody)
                        Spacer()
                        TextField("0,0", text: $text)
                            .font(Theme.font(17, .bold, relativeTo: .body))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .focused($fieldFocused)
                            .frame(maxWidth: 120)
                        Text("kg")
                            .font(Theme.body)
                            .foregroundStyle(Theme.textTertiary)
                    }
                } footer: {
                    if !text.isEmpty && parsedKg == nil {
                        Text("Saisissez un poids entre 20 et 400 kg.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.overTarget)
                    } else {
                        Text("Pour des mesures comparables, pesez-vous le matin, à jeun.")
                            .font(Theme.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .listRowBackground(Theme.raised)
                .listRowSeparatorTint(Theme.separator)
            }
            .themedBackground()
            .navigationTitle("Nouvelle pesée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .font(Theme.headline)
                        .disabled(parsedKg == nil)
                }
            }
            .onAppear { fieldFocused = true }
            .task {
                // Fallback: inside a Form in a sheet, the field may not be in the window yet
                // at onAppear; retry once the presentation has settled (keyboard first).
                try? await Task.sleep(nanoseconds: 350_000_000)
                if !fieldFocused { fieldFocused = true }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let kg = parsedKg else { return }
        modelContext.insert(WeightEntry(date: date, kg: kg))
        ProgressWeightSync.syncProfileWeight(in: modelContext)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

/// Row showing one weighing and the change since the previous one.
struct ProgressWeightRow: View {
    let entry: WeightEntry
    let previousKg: Double?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Formatters.dayTitle(entry.date))
                    .font(Theme.body)
                    .foregroundStyle(Theme.textBody)
                Text(entry.date.formatted(.dateTime.hour().minute().locale(Formatters.locale)))
                    .font(Theme.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(ProgressStats.kg(entry.kg))
                    .font(Theme.headline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                if let previousKg {
                    Text(ProgressStats.signedKg(entry.kg - previousKg))
                        .font(Theme.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }
}

/// Full history of weighings, with delete (pushed view, no NavigationStack).
struct ProgressWeightHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WeightEntry.date, order: .reverse) private var weights: [WeightEntry]
    @State private var showingAdd = false

    var body: some View {
        List {
            if weights.isEmpty {
                ThemedUnavailableView(title: "Aucune pesée",
                                      systemImage: "scalemass",
                                      description: "Ajoutez votre première pesée pour suivre votre évolution.")
                    .listRowBackground(Theme.background)
            } else {
                Section {
                    ForEach(Array(weights.enumerated()), id: \.element.persistentModelID) { index, entry in
                        ProgressWeightRow(entry: entry,
                                          previousKg: index + 1 < weights.count ? weights[index + 1].kg : nil)
                    }
                    .onDelete(perform: delete)
                } footer: {
                    Text(weights.count > 1 ? "\(weights.count) pesées" : "1 pesée")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .listRowBackground(Theme.background)
                .listRowSeparatorTint(Theme.separator)
            }
        }
        .themedBackground()
        .navigationTitle("Pesées")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Ajouter une pesée", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: $showingAdd) {
            ProgressAddWeightSheet(initialKg: weights.first?.kg)
        }
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { weights[$0] }
        for entry in toDelete { modelContext.delete(entry) }
        ProgressWeightSync.syncProfileWeight(in: modelContext)
    }
}
