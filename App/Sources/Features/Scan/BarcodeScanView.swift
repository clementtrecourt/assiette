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
                        .tint(Theme.textSecondary)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showManualEntry = true
                    } label: {
                        Label("Saisir le code", systemImage: "keyboard")
                    }
                    .tint(Theme.textPrimary)
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
            ProgressView {
                Text("Ouverture de la caméra…")
                    .font(Theme.callout)
                    .foregroundStyle(Theme.textSecondary)
            }
            .tint(Theme.textSecondary)
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
            Label {
                Text(cameraState.title)
                    .font(Theme.title)
                    .foregroundStyle(Theme.textPrimary)
            } icon: {
                Image(systemName: cameraState.systemImage)
                    .foregroundStyle(Theme.textTertiary)
            }
        } description: {
            Text(cameraState.message)
                .font(Theme.callout)
                .foregroundStyle(Theme.textSecondary)
        } actions: {
            unavailableActions
        }
    }

    @ViewBuilder
    private var unavailableActions: some View {
        Button {
            showManualEntry = true
        } label: {
            Label("Saisir le code-barres", systemImage: "keyboard")
                .padding(.horizontal, 20)
        }
        .buttonStyle(ScanPrimaryButtonStyle(fillsWidth: false))

        if cameraState == .denied {
            Button("Ouvrir les Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .font(Theme.font(15, .medium, relativeTo: .body))
            .tint(Theme.textSecondary)
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
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.separatorStrong, lineWidth: Theme.hairline)
        }
        .foregroundStyle(Theme.textPrimary)
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

/// Dark overlay with a transparent window and a thin white frame.
private struct ScanViewfinder: View {
    private let width: CGFloat = 280
    private let height: CGFloat = 160
    private let radius: CGFloat = 12

    var body: some View {
        ZStack {
            Theme.background.opacity(0.6)
                .ignoresSafeArea()
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .frame(width: width, height: height)
                .padding(.bottom, 120)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Theme.accent, lineWidth: 2)
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
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Theme.textPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Visez le code-barres du produit")
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text("EAN-13, EAN-8 ou UPC-E")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            Button(action: onManual) {
                Image(systemName: "keyboard")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)
            }
            .buttonStyle(ScanSecondaryButtonStyle(fillsWidth: false))
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
                .tint(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Recherche en cours…")
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(step)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text(code)
                    .font(Theme.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
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
                FoodIconView(item: item, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(Theme.font(17, .bold, relativeTo: .headline))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    if let brand = item.brand {
                        Text(brand)
                            .font(Theme.callout)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Label(item.source.label, systemImage: sourceIcon)
                        Text("·")
                        Text(code).monospacedDigit()
                    }
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
            }

            if hasNutrition {
                nutritionGrid
            } else {
                Label("Valeurs nutritionnelles manquantes pour ce produit.", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.callout)
                    .foregroundStyle(Theme.fat)
            }

            Button(action: hasNutrition ? onLog : onComplete) {
                Label(hasNutrition ? "Ajouter au journal" : "Compléter cet aliment",
                      systemImage: hasNutrition ? "plus.circle.fill" : "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ScanPrimaryButtonStyle())

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
            .buttonStyle(ScanSecondaryButtonStyle())

            AttributionFooter(includeOpenFoodFacts: item.source == .openFoodFacts)
        }
    }

    /// Per-100 g values, 4 columns separated by hairlines like the journal header.
    private var nutritionGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                ScanNutrientColumn(title: "Kcal", value: item.per100[.calories], key: .calories, showsLeadingHairline: false)
                ScanNutrientColumn(title: "Prot.", value: item.per100[.protein], key: .protein, showsLeadingHairline: true)
                ScanNutrientColumn(title: "Gluc.", value: item.per100[.carbohydrates], key: .carbohydrates, showsLeadingHairline: true)
                ScanNutrientColumn(title: "Lip.", value: item.per100[.totalFat], key: .totalFat, showsLeadingHairline: true)
            }
            .overlay(alignment: .top) { ScanHairline() }
            .overlay(alignment: .bottom) { ScanHairline() }
            Text("Pour 100 \(item.unitSymbol)")
                .font(Theme.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

private struct ScanNutrientColumn: View {
    let title: String
    let value: Double?
    let key: NutrientKey
    let showsLeadingHairline: Bool

    private var formatted: String {
        guard let value else { return "–" }
        if key == .calories { return Formatters.number(value, maxFractionDigits: 0) }
        return Formatters.number(value, maxFractionDigits: 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Theme.font(10, .bold, relativeTo: .caption2))
                .textCase(.uppercase)
                .tracking(0.7)
                .foregroundStyle(Theme.color(for: key))
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(formatted)
                    .font(Theme.font(18, .bold, relativeTo: .title3))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if key != .calories && value != nil {
                    Text("g")
                        .font(Theme.font(11, .medium, relativeTo: .caption2))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if showsLeadingHairline {
                Rectangle()
                    .fill(Theme.separator)
                    .frame(width: Theme.hairline)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ScanHairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: Theme.hairline)
    }
}

/// Primary action: white fill (`Theme.accent`) with near-black content.
private struct ScanPrimaryButtonStyle: ButtonStyle {
    var fillsWidth: Bool
    @Environment(\.isEnabled) private var isEnabled

    init(fillsWidth: Bool = true) {
        self.fillsWidth = fillsWidth
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(16, .bold, relativeTo: .headline))
            .foregroundStyle(isEnabled ? Theme.onAccent : Theme.textTertiary)
            .frame(maxWidth: fillsWidth ? CGFloat.infinity : nil)
            .frame(minHeight: 48)
            .background(isEnabled ? Theme.accent : Theme.separatorStrong,
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

/// Secondary action: transparent with a 1 px `separatorStrong` outline.
private struct ScanSecondaryButtonStyle: ButtonStyle {
    var fillsWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(14, .medium, relativeTo: .subheadline))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .frame(maxWidth: fillsWidth ? CGFloat.infinity : nil)
            .frame(minHeight: 40)
            .background(configuration.isPressed ? Theme.separator : Color.clear,
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.separatorStrong, lineWidth: Theme.hairline)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

private struct ScanNotFoundCard: View {
    let code: String
    let onCreate: () -> Void
    let onRescan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Produit introuvable")
                        .font(Theme.font(17, .bold, relativeTo: .headline))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Le code \(code) n'est ni dans la base OpenNutrition, ni dans vos aliments, ni sur Open Food Facts.")
                        .font(Theme.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Button(action: onCreate) {
                Label("Créer cet aliment", systemImage: "plus.square.on.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ScanPrimaryButtonStyle())

            Button(action: onRescan) {
                Label("Scanner un autre produit", systemImage: "barcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ScanSecondaryButtonStyle())
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
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.overTarget)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recherche en ligne impossible")
                        .font(Theme.font(17, .bold, relativeTo: .headline))
                        .foregroundStyle(Theme.textPrimary)
                    Text(message)
                        .font(Theme.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Code \(code) absent de la base locale.")
                        .font(Theme.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
            }

            Button(action: onRetry) {
                Label("Réessayer", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ScanPrimaryButtonStyle())

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
            .buttonStyle(ScanSecondaryButtonStyle())
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
                        .font(Theme.font(20, .medium, relativeTo: .title3))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .tint(Theme.textPrimary)
                        .focused($isFocused)
                        .onSubmit(submit)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 48)
                        .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                                .strokeBorder(isFocused ? Theme.textTertiary : Theme.separatorStrong,
                                              lineWidth: Theme.hairline)
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                } header: {
                    Text("Code-barres")
                        .font(Theme.label)
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(Theme.textTertiary)
                } footer: {
                    Text("Saisissez les 8 à 13 chiffres imprimés sous le code-barres.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .themedBackground()
            .navigationTitle("Saisir un code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                        .tint(Theme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rechercher", action: submit)
                        .font(Theme.font(17, .bold, relativeTo: .body))
                        .tint(Theme.textPrimary)
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
