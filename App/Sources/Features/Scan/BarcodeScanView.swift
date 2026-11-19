import AVFoundation
import SwiftData
import SwiftUI
import Vision
import VisionKit

/// Barcode scanner presented in a sheet (has its own NavigationStack).
/// Lookup order: bundled OpenNutrition DB → user's CustomFood (by EAN) → Open Food Facts.
struct BarcodeScanView: View {
    let context: LogContext
    /// Called just before the scanner closes itself after a successful log.
    let onLogged: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var cameraState: ScanCameraState = .checking
    @State private var scannerAppeared = false
    @State private var phase: ScanPhase = .scanning
    @State private var lookupTask: Task<Void, Never>?
    @State private var detectionCount = 0

    @State private var showManualEntry = false
    @State private var detailItem: FoodItem?
    @State private var itemToLog: FoodItem?
    @State private var editorRequest: ScanEditorRequest?
    @State private var closeAfterLogging = false

    init(context: LogContext, onLogged: (() -> Void)? = nil) {
        self.context = context
        self.onLogged = onLogged
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                cameraLayer

                if showsPanel {
                    panel
                        .frame(maxWidth: 520)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Theme.background.ignoresSafeArea()
            }
            .animation(.snappy, value: phase)
            .navigationTitle("Scanner un code-barres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showManualEntry = true
                    } label: {
                        Label("Saisir le code", systemImage: "keyboard")
                    }
                }
            }
            .navigationDestination(item: $detailItem) { item in
                FoodDetailView(item: item, context: context, onLogged: {
                    onLogged?()
                    dismiss()
                })
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: detectionCount)
        .sensoryFeedback(trigger: phase) { _, newPhase in
            switch newPhase {
            case .found: return .success
            case .notFound: return .warning
            case .failed: return .error
            default: return nil
            }
        }
        .sheet(isPresented: $showManualEntry) {
            ScanManualEntrySheet { code in
                handle(code: code, force: true)
            }
        }
        .sheet(item: $itemToLog, onDismiss: {
            if closeAfterLogging {
                closeAfterLogging = false
                onLogged?()
                dismiss()
            }
        }) { item in
            AddEntrySheet(item: item, context: context, onLogged: {
                closeAfterLogging = true
            })
        }
        .sheet(item: $editorRequest, onDismiss: refreshAfterEditor) { request in
            CustomFoodEditor(food: nil, prefill: request.prefill, barcode: request.barcode)
        }
        .task {
            await evaluateCamera()
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            if cameraState == .denied || cameraState == .unavailable {
                Task { await evaluateCamera() }
            }
        }
        .onDisappear {
            lookupTask?.cancel()
        }
    }

    // MARK: - Layers

    private var scannerIsActive: Bool {
        cameraState == .ready && scannerAppeared && phase == .scanning
            && detailItem == nil && itemToLog == nil && editorRequest == nil && !showManualEntry
            && scenePhase == .active
    }

    private var showsPanel: Bool {
        cameraState == .ready || phase != .scanning
    }

    @ViewBuilder
    private var cameraLayer: some View {
        switch cameraState {
        case .checking:
            ProgressView("Ouverture de la caméra…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            ZStack {
                ScanDataScanner(
                    isActive: scannerIsActive,
                    onCode: { code in handle(code: code, force: false) },
                    onUnavailable: { cameraState = .unavailable }
                )
                .ignoresSafeArea()
                .onAppear { scannerAppeared = true }
                .onDisappear { scannerAppeared = false }

                if phase == .scanning {
                    ScanViewfinder()
                }
            }
        case .unsupported, .denied, .unavailable:
            if phase == .scanning {
                unavailableView
            } else {
                Color.clear
            }
        }
    }

    private var unavailableView: some View {
        ContentUnavailableView {
            Label(cameraState.title, systemImage: cameraState.systemImage)
        } description: {
            Text(cameraState.message)
        } actions: {
            Button {
                showManualEntry = true
            } label: {
                Label("Saisir le code-barres", systemImage: "keyboard")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

            if cameraState == .denied {
                Button("Ouvrir les Réglages") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var panel: some View {
        Group {
            switch phase {
            case .scanning:
                ScanHintCard { showManualEntry = true }
            case .searching(let code, let step):
                ScanSearchingCard(code: code, step: step)
            case .found(let code, let item):
                ScanFoundCard(
                    item: item,
                    code: code,
                    onLog: { itemToLog = item },
                    onDetail: { detailItem = item },
                    onComplete: { editorRequest = ScanEditorRequest(barcode: code, prefill: item) },
                    onRescan: rescan
                )
            case .notFound(let code):
                ScanNotFoundCard(
                    code: code,
                    onCreate: { editorRequest = ScanEditorRequest(barcode: code, prefill: nil) },
                    onRescan: rescan
                )
            case .failed(let code, let message):
                ScanFailedCard(
                    code: code,
                    message: message,
                    onRetry: { handle(code: code, force: true) },
                    onCreate: { editorRequest = ScanEditorRequest(barcode: code, prefill: nil) },
                    onRescan: rescan
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .tint(Theme.accent)
    }

    // MARK: - Camera

    private func evaluateCamera() async {
        guard DataScannerViewController.isSupported else {
            cameraState = .unsupported
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if !granted {
                cameraState = .denied
                return
            }
        case .denied, .restricted:
            cameraState = .denied
            return
        default:
            break
        }
        cameraState = DataScannerViewController.isAvailable ? .ready : .unavailable
    }

    // MARK: - Lookup

    private func handle(code raw: String, force: Bool) {
        let code = raw.filter { $0.isASCII && $0.isNumber }
        guard !code.isEmpty else { return }
        if !force && phase != .scanning { return }
        detectionCount += 1
        lookupTask?.cancel()
        phase = .searching(code: code, step: "Base OpenNutrition")
        lookupTask = Task { await lookup(code) }
    }

    private func rescan() {
        lookupTask?.cancel()
        lookupTask = nil
        phase = .scanning
    }

    private func lookup(_ code: String) async {
        // 1. Bundled OpenNutrition database.
        let local = await Task.detached(priority: .userInitiated) {
            FoodDatabase.shared.food(barcode: code)
        }.value
        if Task.isCancelled { return }
        if let local {
            phase = .found(code: code, item: local.item)
            return
        }

        // 2. User's own foods.
        phase = .searching(code: code, step: "Mes aliments")
        if let custom = customFood(matching: code) {
            phase = .found(code: code, item: custom.item)
            return
        }

        // 3. Open Food Facts (online).
        phase = .searching(code: code, step: "Open Food Facts")
        do {
            let item = try await OpenFoodFactsClient.product(barcode: code)
            if Task.isCancelled { return }
            if let item {
                phase = .found(code: code, item: item)
            } else {
                phase = .notFound(code: code)
            }
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { return }
            phase = .failed(code: code, message: Self.message(for: error))
        }
    }

    private func customFood(matching code: String) -> CustomFood? {
        let key = Self.normalizedBarcode(code)
        guard !key.isEmpty else { return nil }
        let foods = (try? modelContext.fetch(FetchDescriptor<CustomFood>())) ?? []
        return foods.first { food in
            guard let ean = food.ean else { return false }
            return Self.normalizedBarcode(ean) == key
        }
    }

    /// After the custom food editor closes: if the user created a food for this code, show it.
    private func refreshAfterEditor() {
        guard let code = phase.code, let custom = customFood(matching: code) else { return }
        lookupTask?.cancel()
        phase = .found(code: code, item: custom.item)
    }

    /// Digits only, leading zeros dropped (so UPC-A "0123…" matches EAN-13 "00123…").
    private static func normalizedBarcode(_ value: String) -> String {
        let digits = value.filter { $0.isASCII && $0.isNumber }
        return String(digits.drop(while: { $0 == "0" }))
    }

    private static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return "Pas de connexion Internet. Vérifiez votre réseau puis réessayez."
            case .timedOut:
                return "Open Food Facts ne répond pas (délai dépassé)."
            default:
                break
            }
        }
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return "Impossible de contacter Open Food Facts."
    }
}

// MARK: - State

private enum ScanCameraState: Equatable {
    case checking, ready, unsupported, denied, unavailable

    var title: String {
        switch self {
        case .unsupported: return "Scanner non disponible"
        case .denied: return "Accès à la caméra refusé"
        default: return "Caméra indisponible"
        }
    }

    var message: String {
        switch self {
        case .unsupported:
            return "Cet appareil ne permet pas de scanner les codes-barres. Vous pouvez saisir le code à la main."
        case .denied:
            return "Autorisez l'accès à la caméra dans Réglages pour scanner les codes-barres, ou saisissez le code à la main."
        default:
            return "La caméra est utilisée par une autre app ou restreinte. Vous pouvez saisir le code à la main."
        }
    }

    var systemImage: String {
        switch self {
        case .denied: return "camera.fill"
        default: return "barcode.viewfinder"
        }
    }
}

private enum ScanPhase: Equatable {
    case scanning
    case searching(code: String, step: String)
    case found(code: String, item: FoodItem)
    case notFound(code: String)
    case failed(code: String, message: String)

    var code: String? {
        switch self {
        case .scanning: return nil
        case .searching(let code, _): return code
        case .found(let code, _): return code
        case .notFound(let code): return code
        case .failed(let code, _): return code
        }
    }
}

private struct ScanEditorRequest: Identifiable {
    let id = UUID()
    let barcode: String
    let prefill: FoodItem?
}

// MARK: - DataScannerViewController wrapper

private struct ScanDataScanner: UIViewControllerRepresentable {
    var isActive: Bool
    var onCode: (String) -> Void
    var onUnavailable: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode, onUnavailable: onUnavailable)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.onCode = onCode
        coordinator.onUnavailable = onUnavailable
        coordinator.wantsScanning = isActive

        if isActive {
            guard !scanner.isScanning else { return }
            // Start on the next main-actor turn, once the view is in the window.
            Task { @MainActor in
                guard coordinator.wantsScanning, !scanner.isScanning else { return }
                do {
                    try scanner.startScanning()
                } catch {
                    coordinator.onUnavailable()
                }
            }
        } else if scanner.isScanning {
            scanner.stopScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        coordinator.wantsScanning = false
        if scanner.isScanning { scanner.stopScanning() }
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        var onUnavailable: () -> Void
        var wantsScanning = false

        private var lastCode: String?
        private var lastDate = Date.distantPast

        init(onCode: @escaping (String) -> Void, onUnavailable: @escaping () -> Void) {
            self.onCode = onCode
            self.onUnavailable = onUnavailable
            super.init()
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems where emit(item, force: false) {
                break
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            _ = emit(item, force: true)
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            onUnavailable()
        }

        /// Forwards a barcode payload, ignoring the same code seen again within a few seconds.
        private func emit(_ item: RecognizedItem, force: Bool) -> Bool {
            guard case .barcode(let barcode) = item,
                  let payload = barcode.payloadStringValue,
                  !payload.isEmpty
            else { return false }
            let now = Date()
            if !force, payload == lastCode, now.timeIntervalSince(lastDate) < 3 { return false }
            lastCode = payload
            lastDate = now
            onCode(payload)
            return true
        }
    }
}

// MARK: - Overlay & cards

/// Dark overlay with a transparent window and an accent reticle.
private struct ScanViewfinder: View {
    private let width: CGFloat = 280
    private let height: CGFloat = 160
    private let radius: CGFloat = 18

    var body: some View {
        ZStack {
            Theme.background.opacity(0.55)
                .ignoresSafeArea()
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .frame(width: width, height: height)
                .padding(.bottom, 120)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 3)
                .frame(width: width, height: height)
                .padding(.bottom, 120)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct ScanHintCard: View {
    let onManual: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "barcode.viewfinder")
                .font(.title2)
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Visez le code-barres du produit")
                    .font(.subheadline.weight(.semibold))
                Text("EAN-13, EAN-8 ou UPC-E")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 8)
            Button(action: onManual) {
                Image(systemName: "keyboard")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Saisir le code manuellement")
        }
    }
}

private struct ScanSearchingCard: View {
    let code: String
    let step: String

    var body: some View {
        HStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)
            VStack(alignment: .leading, spacing: 2) {
                Text("Recherche en cours…")
                    .font(.subheadline.weight(.semibold))
                Text(step)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text(code)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ScanFoundCard: View {
    let item: FoodItem
    let code: String
    let onLog: () -> Void
    let onDetail: () -> Void
    let onComplete: () -> Void
    let onRescan: () -> Void

    private var hasNutrition: Bool { item.per100[.calories] != nil }

    private var sourceIcon: String {
        switch item.source {
        case .openNutrition: return "leaf.circle"
        case .custom: return "person.crop.circle"
        case .openFoodFacts: return "globe"
        case .quickAdd: return "bolt.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.fiber)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.headline)
                        .lineLimit(2)
                    if let brand = item.brand {
                        Text(brand)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Label(item.source.label, systemImage: sourceIcon)
                        Text("·")
                        Text(code).monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }

            if hasNutrition {
                VStack(spacing: 6) {
                    HStack(spacing: 0) {
                        ScanNutrientColumn(title: "kcal", value: item.per100[.calories], key: .calories)
                        ScanNutrientColumn(title: "Protéines", value: item.per100[.protein], key: .protein)
                        ScanNutrientColumn(title: "Glucides", value: item.per100[.carbohydrates], key: .carbohydrates)
                        ScanNutrientColumn(title: "Lipides", value: item.per100[.totalFat], key: .totalFat)
                    }
                    Text("Pour 100 \(item.unitSymbol)")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                Label("Valeurs nutritionnelles manquantes pour ce produit.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.fat)
            }

            Button(action: hasNutrition ? onLog : onComplete) {
                Label(hasNutrition ? "Ajouter au journal" : "Compléter cet aliment",
                      systemImage: hasNutrition ? "plus.circle.fill" : "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 10) {
                Button(action: onDetail) {
                    Label("Voir la fiche", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity)
                }
                Button(action: onRescan) {
                    Label("Autre produit", systemImage: "barcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .font(.subheadline)

            AttributionFooter(includeOpenFoodFacts: item.source == .openFoodFacts)
        }
    }
}

private struct ScanNutrientColumn: View {
    let title: String
    let value: Double?
    let key: NutrientKey

    private var formatted: String {
        guard let value else { return "–" }
        if key == .calories { return Formatters.number(value, maxFractionDigits: 0) }
        return "\(Formatters.number(value, maxFractionDigits: 1)) g"
    }

    var body: some View {
        VStack(spacing: 2) {
            Text(formatted)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.color(for: key))
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ScanNotFoundCard: View {
    let code: String
    let onCreate: () -> Void
    let onRescan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.fat)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Produit introuvable")
                        .font(.headline)
                    Text("Le code \(code) n'est ni dans la base OpenNutrition, ni dans vos aliments, ni sur Open Food Facts.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button(action: onCreate) {
                Label("Créer cet aliment", systemImage: "plus.square.on.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button(action: onRescan) {
                Label("Scanner un autre produit", systemImage: "barcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct ScanFailedCard: View {
    let code: String
    let message: String
    let onRetry: () -> Void
    let onCreate: () -> Void
    let onRescan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.title2)
                    .foregroundStyle(Theme.overTarget)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recherche en ligne impossible")
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Code \(code) absent de la base locale.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }

            Button(action: onRetry) {
                Label("Réessayer", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            HStack(spacing: 10) {
                Button(action: onCreate) {
                    Label("Créer", systemImage: "plus.square.on.square")
                        .frame(maxWidth: .infinity)
                }
                Button(action: onRescan) {
                    Label("Autre produit", systemImage: "barcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .font(.subheadline)
        }
    }
}

// MARK: - Manual entry

private struct ScanManualEntrySheet: View {
    let onSubmit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @FocusState private var isFocused: Bool

    init(onSubmit: @escaping (String) -> Void) {
        self.onSubmit = onSubmit
    }

    private var digits: String { code.filter { $0.isASCII && $0.isNumber } }
    private var isValid: Bool { (8...14).contains(digits.count) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ex. 3017620422003", text: $code)
                        .keyboardType(.numberPad)
                        .autocorrectionDisabled()
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .focused($isFocused)
                        .onSubmit(submit)
                        .listRowBackground(Theme.card)
                } header: {
                    Text("Code-barres")
                        .foregroundStyle(Theme.textSecondary)
                } footer: {
                    Text("Saisissez les 8 à 13 chiffres imprimés sous le code-barres.")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .themedBackground()
            .navigationTitle("Saisir un code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rechercher", action: submit)
                        .disabled(!isValid)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium])
    }

    private func submit() {
        guard isValid else { return }
        let value = digits
        dismiss()
        onSubmit(value)
    }
}
