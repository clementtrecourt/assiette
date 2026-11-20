import SwiftData
import SwiftUI

/// Creates or edits an exception period (surgery, illness, travel…): date range + note.
/// The note field has the keyboard on appear; return saves.
struct CoachingExceptionEditor: View {
    /// nil = new period.
    let period: ExceptionPeriod?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var start: Date
    @State private var end: Date
    @State private var note: String
    @State private var showDeleteConfirm = false
    @FocusState private var noteFocused: Bool

    init(period: ExceptionPeriod?) {
        self.period = period
        let today = Date.now.startOfDay
        _start = State(initialValue: period?.start ?? today)
        _end = State(initialValue: period?.end ?? today.adding(days: 6))
        _note = State(initialValue: period?.note ?? "")
    }

    private var dayCount: Int {
        let days = Calendar.current.dateComponents([.day], from: start.startOfDay, to: end.startOfDay).day ?? 0
        return max(1, days + 1)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Opération, maladie, vacances…", text: $note)
                        .focused($noteFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .font(Theme.body)
                        .foregroundStyle(Theme.textPrimary)
                } header: {
                    ProfileSectionHeader("Motif")
                }
                .listRowBackground(Theme.background)

                Section {
                    DatePicker(selection: $start, displayedComponents: .date) {
                        Text("Début").foregroundStyle(Theme.textBody)
                    }
                    DatePicker(selection: $end, in: start..., displayedComponents: .date) {
                        Text("Fin (incluse)").foregroundStyle(Theme.textBody)
                    }
                } header: {
                    ProfileSectionHeader("Période")
                } footer: {
                    ProfileSectionFooter("\(dayCount) jour\(dayCount > 1 ? "s" : ""). Ces jours sont ignorés par l'estimation de la dépense, qui reste figée jusqu'au retour d'une semaine normale. Pendant la période, vous pouvez passer en mode manuel.")
                }
                .listRowBackground(Theme.background)
                .listRowSeparatorTint(Theme.separator)

                if period != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Text("Supprimer l'exception")
                                .font(Theme.font(15, .medium, relativeTo: .body))
                                .foregroundStyle(Theme.overTarget)
                        }
                    }
                    .listRowBackground(Theme.background)
                }
            }
            .listSectionSpacing(.compact)
            .themedBackground()
            .tint(Theme.accent)
            .navigationTitle(period == nil ? "Nouvelle exception" : "Exception")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                }
            }
            .onChange(of: start) { _, newStart in
                if end < newStart { end = newStart }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(450))
                noteFocused = true
            }
            .confirmationDialog("Supprimer cette exception ?", isPresented: $showDeleteConfirm,
                                titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) { deletePeriod() }
                Button("Annuler", role: .cancel) {}
            }
        }
        .presentationBackground(Theme.background)
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = min(start, end).startOfDay
        let last = max(start, end).startOfDay
        if let period {
            period.start = first
            period.end = last
            period.note = trimmed
        } else {
            modelContext.insert(ExceptionPeriod(start: first, end: last, note: trimmed))
        }
        try? modelContext.save()
        dismiss()
    }

    private func deletePeriod() {
        if let period { modelContext.delete(period) }
        try? modelContext.save()
        dismiss()
    }
}
