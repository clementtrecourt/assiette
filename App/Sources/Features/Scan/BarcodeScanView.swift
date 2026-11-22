import AVFoundation
import SwiftData
import SwiftUI
import Vision
import VisionKit

/// Full-bleed camera scanner: barcodes (lookup order: bundled OpenNutrition DB → user's
/// CustomFood by EAN → Open Food Facts) or a nutrition facts label (OCR of the per-100 g values).
///
/// Standalone (sheet): own NavigationStack, close button in the camera top bar.
/// `embedded: true`: no NavigationStack chrome (the add sheet provides its header); the food
/// detail opens in a sheet instead of being pushed.
struct BarcodeScanView: View {
    let context: LogContext
    /// Called after a successful log ("Ajouter"); standalone, the scanner then closes itself.
    let onLogged: (() -> Void)?
    let embedded: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var cameraState: ScanCameraState = .checking
    @State private var scannerAppeared = false
    @State private var mode: ScanMode = .barcode
    @State private var phase: ScanPhase = .scanning
    @State private var labelPhase: ScanLabelPhase = .idle
    @State private var lookupTask: Task<Void, Never>?
    @State private var labelTask: Task<Void, Never>?
    @State private var detectionCount = 0
    @State private var captureHandle = ScanCaptureHandle()
    @State private var torchAvailable = false
    @State private var torchOn = false

    @State private var showManualEntry = false
    @State private var detailItem: FoodItem?
    @State private var itemToLog: FoodItem?
    @State private var editorRequest: ScanEditorRequest?
    @State private var closeAfterLogging = false

    /// Last product found by a scan (JSON snapshot, so it works offline) and when.
    @AppStorage("scan.lastProduct") private var lastProductData = Data()
    @AppStorage("scan.lastProductDate") private var lastProductDate: Double = 0

    init(context: LogContext, onLogged: (() -> Void)? = nil, embedded: Bool = false) {
        self.context = context
        self.onLogged = onLogged
        self.embedded = embedded
    }

    var body: some View {
        Group {
            if embedded {
                scanner
                    .slideCover(item: $detailItem) { item in
                        NavigationStack {
                            FoodDetailView(item: item, context: context, onLogged: finishLogging)
                        }
                    }
            } else {
                NavigationStack {
                    scanner
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(item: $detailItem) { item in
                            FoodDetailView(item: item, context: context, onLogged: finishLogging)
                        }
                }
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
        .sensoryFeedback(trigger: labelPhase) { _, newPhase in
            switch newPhase {
            case .result: return .success
            case .failed: return .warning
            default: return nil
            }
        }
        .sheet(isPresented: $showManualEntry) {
            ScanManualEntrySheet { code in
                if mode != .barcode { switchMode(to: .barcode) }
                handle(code: code, force: true)
            }
        }
        .slideCover(item: $itemToLog, onDismiss: {
            if closeAfterLogging {
                closeAfterLogging = false
                finishLogging()
            }
        }) { item in
            AddEntrySheet(item: item, context: context, onLogged: {
                closeAfterLogging = true
            })
        }
        .slideCover(item: $editorRequest, onDismiss: refreshAfterEditor) { request in
            CustomFoodEditor(food: nil, prefill: request.prefill, barcode: request.barcode)
        }
        .task {
            await evaluateCamera()
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                if cameraState == .denied || cameraState == .unavailable {
                    Task { await evaluateCamera() }
                }
            } else {
                torchOn = false
            }
        }
        .onChange(of: phase) { _, newPhase in
            if case .found(let code, let item) = newPhase {
                rememberLast(item, code: code)
            }
        }
        .onChange(of: torchOn) { _, on in
            ScanTorch.set(on)
        }
        .onDisappear {
            lookupTask?.cancel()
            labelTask?.cancel()
            if torchOn { ScanTorch.set(false) }
        }
    }

    /// Camera, overlays and bottom card.
    private var scanner: some View {
        ZStack(alignment: .bottom) {
            cameraLayer

            if let panelContent = panelKind {
                panel(panelContent)
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) { topBar }
        .background {
            Color.black.ignoresSafeArea()
        }
        .animation(.quick, value: phase)
        .animation(.quick, value: labelPhase)
        .animation(.quick, value: mode)
    }

    // MARK: - Layers

    private var scannerIsActive: Bool {
        guard cameraState == .ready, scannerAppeared, scenePhase == .active,
              detailItem == nil, itemToLog == nil, editorRequest == nil, !showManualEntry
        else { return false }
        switch mode {
        case .barcode: return phase == .scanning
        case .label: return labelPhase == .idle || labelPhase == .reading
        }
    }

    private var showsViewfinder: Bool {
        switch mode {
        case .barcode: return phase == .scanning
        case .label: return labelPhase == .idle || labelPhase == .reading
        }
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
            .background(Theme.background)
        case .ready:
            ZStack {
                ScanDataScanner(
                    mode: mode,
                    isActive: scannerIsActive,
                    handle: captureHandle,
                    onCode: { code in handle(code: code, force: false) },
                    onUnavailable: { cameraState = .unavailable }
                )
                .id(mode)
                .ignoresSafeArea()

                if showsViewfinder {
                    ScanViewfinder(mode: mode, bottomReserve: viewfinderBottomReserve)
                }
            }
            .onAppear { scannerAppeared = true }
            .onDisappear { scannerAppeared = false }
        case .unsupported, .denied, .unavailable:
            if mode == .label || phase == .scanning {
                unavailableView
                    .padding(.top, 56)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            } else {
                Theme.background
            }
        }
    }

    /// Room kept under the viewfinder for the bottom card.
    private var viewfinderBottomReserve: CGFloat {
        mode == .label ? 150 : 110
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
            Text(mode == .label ? cameraState.labelMessage : cameraState.message)
                .font(Theme.callout)
                .foregroundStyle(Theme.textSecondary)
        } actions: {
            unavailableActions
        }
    }

    @ViewBuilder
    private var unavailableActions: some View {
        if mode == .barcode {
            Button {
                showManualEntry = true
            } label: {
                Label("Saisir le code-barres", systemImage: "keyboard")
                    .padding(.horizontal, 20)
            }
            .buttonStyle(ScanPrimaryButtonStyle(fillsWidth: false))
        }

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

    /// Mode switch (Code-barres / Étiquette), manual entry and torch, over the camera.
    private var topBar: some View {
        HStack(spacing: 8) {
            if !embedded {
                ScanRoundButton(systemImage: "xmark", label: "Fermer") { dismiss() }
            }
            ScanModeSwitch(mode: mode, onSelect: switchMode(to:))
            Spacer(minLength: 8)
            ScanRoundButton(systemImage: "keyboard", label: "Saisir le code-barres") {
                showManualEntry = true
            }
            if torchAvailable && cameraState == .ready {
                ScanRoundButton(systemImage: torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                                label: torchOn ? "Éteindre la lampe" : "Allumer la lampe",
                                isOn: torchOn) {
                    torchOn.toggle()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: - Bottom card

    private enum PanelKind {
        case lastScan(FoodItem)
        case barcode
        case label
    }

    private var panelKind: PanelKind? {
        switch mode {
        case .label:
            if cameraState == .ready { return PanelKind.label }
            return nil
        case .barcode:
            if phase != .scanning { return .barcode }
            if let last = lastProduct { return .lastScan(last.item) }
            return nil
        }
    }

    @ViewBuilder
    private func panel(_ kind: PanelKind) -> some View {
        switch kind {
        case .lastScan(let item):
            ScanLastCard(
                item: item,
                detail: lastScanDetail(for: item),
                onOpen: {
                    if let code = lastProduct?.code { phase = .found(code: code, item: item) }
                },
                onAdd: { itemToLog = item }
            )
        case .barcode:
            barcodeCard
                .modifier(ScanCardBackground())
        case .label:
            labelCard
                .modifier(ScanCardBackground())
        }
    }

    @ViewBuilder
    private var barcodeCard: some View {
        switch phase {
        case .scanning:
            EmptyView()
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

    @ViewBuilder
    private var labelCard: some View {
        switch labelPhase {
        case .idle:
            ScanLabelIdleCard(onRead: readLabel)
        case .reading:
            ScanSearchingCard(code: nil, step: "Lecture du tableau nutritionnel", title: "Lecture de l'étiquette…")
        case .result(let values):
            ScanLabelResultCard(
                values: values,
                onLog: { itemToLog = BarcodeScanView.labelItem(values) },
                onCreate: { editorRequest = ScanEditorRequest(barcode: nil, prefill: BarcodeScanView.labelItem(values)) },
                onRetry: { labelPhase = .idle }
            )
        case .failed(let message):
            ScanLabelFailedCard(message: message, onRetry: readLabel)
        }
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
        torchAvailable = ScanTorch.isAvailable
        cameraState = DataScannerViewController.isAvailable ? .ready : .unavailable
    }

    private func switchMode(to newMode: ScanMode) {
        guard newMode != mode else { return }
        lookupTask?.cancel()
        labelTask?.cancel()
        phase = .scanning
        labelPhase = .idle
        torchOn = false
        mode = newMode
    }

    /// After a successful log: tell the caller; standalone, also close the scanner.
    private func finishLogging() {
        onLogged?()
        if !embedded { dismiss() }
    }

    // MARK: - Barcode lookup

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
        guard mode == .barcode, let code = phase.code, let custom = customFood(matching: code) else { return }
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

    // MARK: - Last scan

    private var lastProduct: ScanLastProduct? {
        guard !lastProductData.isEmpty else { return nil }
        return try? JSONDecoder().decode(ScanLastProduct.self, from: lastProductData)
    }

    private func rememberLast(_ item: FoodItem, code: String) {
        guard let data = try? JSONEncoder().encode(ScanLastProduct(item: item, code: code)) else { return }
        lastProductData = data
        lastProductDate = Date.now.timeIntervalSince1970
    }

    /// "il y a 2 jours · 15 g".
    private func lastScanDetail(for item: FoodItem) -> String {
        var parts: [String] = []
        if lastProductDate > 0 {
            let date = Date(timeIntervalSince1970: lastProductDate)
            parts.append(ScanLastCard.relativeFormatter.localizedString(for: date, relativeTo: .now))
        }
        if let grams = UserDefaults.standard.object(forKey: "lastGrams.\(item.id)") as? Double, grams > 0 {
            parts.append("\(Formatters.number(grams, maxFractionDigits: 0)) \(item.unitSymbol)")
        } else if let brand = item.brand, !brand.isEmpty {
            parts.append(brand)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Nutrition label (OCR)

    private func readLabel() {
        guard let scanner = captureHandle.scanner else {
            labelPhase = .failed("La caméra n'est pas prête. Réessayez dans un instant.")
            return
        }
        labelTask?.cancel()
        labelPhase = .reading
        labelTask = Task { @MainActor in
            do {
                let image = try await scanner.capturePhoto()
                let rows = await ScanLabelReader.recognizeRows(in: image)
                if Task.isCancelled { return }
                if let values = ScanLabelParser.parse(lines: rows) {
                    labelPhase = .result(values)
                } else {
                    labelPhase = .failed("Aucune valeur lue. Cadrez le tableau nutritionnel de plus près, bien éclairé, puis réessayez.")
                }
            } catch {
                if Task.isCancelled { return }
                labelPhase = .failed("Impossible de prendre la photo. Réessayez.")
            }
        }
    }

    /// Temporary loggable item built from label values (per 100 g).
    private static func labelItem(_ values: NutrientValues) -> FoodItem {
        FoodItem(source: .custom, ref: nil, name: "Étiquette scannée", brand: nil, kind: nil,
                 servingLabel: nil, servingGrams: nil, packageGrams: nil, isLiquid: false,
                 ean: nil, per100: values)
    }
}

// MARK: - State

private enum ScanMode: Hashable {
    case barcode, label
}

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

    var labelMessage: String {
        switch self {
        case .unsupported:
            return "Cet appareil ne permet pas de lire les étiquettes."
        case .denied:
            return "Autorisez l'accès à la caméra dans Réglages pour lire les étiquettes."
        default:
            return "La caméra est utilisée par une autre app ou restreinte."
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

private enum ScanLabelPhase: Equatable {
    case idle
    case reading
    case result(NutrientValues)
    case failed(String)
}

private struct ScanEditorRequest: Identifiable {
    let id = UUID()
    let barcode: String?
    let prefill: FoodItem?
}

/// Reference to the live scanner, used to take the label photo.
private final class ScanCaptureHandle {
    weak var scanner: DataScannerViewController?
}

/// Snapshot of the last scanned product (stored as JSON in AppStorage).
private struct ScanLastProduct: Codable {
    var code: String
    var name: String
    var brand: String?
    var sourceRaw: String
    var ref: String?
    var kindRaw: Int?
    var servingLabel: String?
    var servingGrams: Double?
    var packageGrams: Double?
    var isLiquid: Bool
    var ean: String?
    var per100: NutrientValues
    var icon: String?

    init(item: FoodItem, code: String) {
        self.code = code
        self.name = item.name
        self.brand = item.brand
        self.sourceRaw = item.source.rawValue
        self.ref = item.ref
        self.kindRaw = item.kind?.rawValue
        self.servingLabel = item.servingLabel
        self.servingGrams = item.servingGrams
        self.packageGrams = item.packageGrams
        self.isLiquid = item.isLiquid
        self.ean = item.ean
        self.per100 = item.per100
        self.icon = item.icon
    }

    var item: FoodItem {
        FoodItem(source: FoodSource(rawValue: sourceRaw) ?? .openFoodFacts, ref: ref, name: name,
                 brand: brand, kind: kindRaw.flatMap(FoodKind.init(rawValue:)),
                 servingLabel: servingLabel, servingGrams: servingGrams, packageGrams: packageGrams,
                 isLiquid: isLiquid, ean: ean, per100: per100, icon: icon)
    }
}

/// Torch of the back camera (the scanner's capture device).
private enum ScanTorch {
    static var isAvailable: Bool {
        AVCaptureDevice.default(for: .video)?.hasTorch ?? false
    }

    static func set(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        } catch {
            // Torch busy or unavailable: ignore.
        }
    }
}

// MARK: - DataScannerViewController wrapper

private struct ScanDataScanner: UIViewControllerRepresentable {
    var mode: ScanMode
    var isActive: Bool
    var handle: ScanCaptureHandle
    var onCode: (String) -> Void
    var onUnavailable: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode, onUnavailable: onUnavailable)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner: DataScannerViewController
        switch mode {
        case .barcode:
            scanner = DataScannerViewController(
                recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
                qualityLevel: .balanced,
                recognizesMultipleItems: false,
                isHighFrameRateTrackingEnabled: false,
                isPinchToZoomEnabled: true,
                isGuidanceEnabled: true,
                isHighlightingEnabled: true
            )
        case .label:
            scanner = DataScannerViewController(
                recognizedDataTypes: [.text()],
                qualityLevel: .accurate,
                recognizesMultipleItems: true,
                isHighFrameRateTrackingEnabled: false,
                isPinchToZoomEnabled: true,
                isGuidanceEnabled: false,
                isHighlightingEnabled: true
            )
        }
        scanner.delegate = context.coordinator
        handle.scanner = scanner
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.onCode = onCode
        coordinator.onUnavailable = onUnavailable
        coordinator.wantsScanning = isActive
        handle.scanner = scanner

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

// MARK: - Overlay

/// Dimmed camera with a clear window, 4 rounded corner brackets, an animated scan line
/// (calories blue) and the hint under the frame.
private struct ScanViewfinder: View {
    let mode: ScanMode
    let bottomReserve: CGFloat

    @State private var sweeping = false

    private var hint: String {
        mode == .barcode
            ? "Placez le code-barres dans le cadre"
            : "Cadrez le tableau nutritionnel (pour 100 g)"
    }

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width - 52, 360)
            let available = max(geo.size.height - bottomReserve - 90, 120)
            let height = mode == .barcode ? min(150, available) : min(width * 1.1, available)
            let centerY = 70 + (available - height) * 0.35 + height / 2
            let center = CGPoint(x: geo.size.width / 2, y: centerY)

            ZStack {
                ZStack {
                    Color.black.opacity(0.35)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .frame(width: width, height: height)
                        .position(center)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()

                ScanCornerBrackets()
                    .stroke(Theme.textPrimary, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: width, height: height)
                    .position(center)

                Capsule()
                    .fill(Theme.calories)
                    .frame(width: width - 28, height: 2)
                    .shadow(color: Theme.calories.opacity(0.7), radius: 6)
                    .position(x: center.x, y: center.y + (sweeping ? height / 2 - 16 : -height / 2 + 16))

                Text(hint)
                    .font(Theme.font(13, .medium, relativeTo: .footnote))
                    .foregroundStyle(Theme.textBody)
                    .shadow(color: .black.opacity(0.6), radius: 4)
                    .position(x: center.x, y: center.y + height / 2 + 24)
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hint)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                sweeping = true
            }
        }
    }
}

/// Four corner brackets with rounded corners.
private struct ScanCornerBrackets: Shape {
    var length: CGFloat = 26
    var radius: CGFloat = 12

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let l = min(length, rect.width / 2, rect.height / 2)
        let r = min(radius, l)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + l))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - l, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + l, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return path
    }
}

/// "Code-barres / Étiquette" switch (49 pt): white selected segment, white text on raised2.
private struct ScanModeSwitch: View {
    let mode: ScanMode
    let onSelect: (ScanMode) -> Void

    var body: some View {
        HStack(spacing: 0) {
            segment(.barcode, title: "Code-barres")
            segment(.label, title: "Étiquette")
        }
        .padding(4)
        .frame(height: 49)
        .background(Theme.raised2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mode de scan")
    }

    private func segment(_ value: ScanMode, title: String) -> some View {
        let isSelected = mode == value
        return Button {
            onSelect(value)
        } label: {
            Text(title)
                .font(Theme.font(16, .medium, relativeTo: .body))
                .lineLimit(1)
                // Standalone mode adds a close button: shrink a little rather than overflow.
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? Theme.onAccent : Theme.textPrimary)
                .padding(.horizontal, 16)
                .frame(maxHeight: .infinity)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Round translucent 49 pt button of the camera top bar.
private struct ScanRoundButton: View {
    let systemImage: String
    let label: String
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(isOn ? Theme.onAccent : Theme.textPrimary)
                .frame(width: 49, height: 49)
                .background(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.black.opacity(0.55)),
                            in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Bottom card surface over the camera.
private struct ScanCardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised.opacity(0.96), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            }
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
    }
}

// MARK: - Cards

/// "Dernier scan : …" with a "+" to log it again; tap to see the product card.
private struct ScanLastCard: View {
    let item: FoodItem
    let detail: String
    let onOpen: () -> Void
    let onAdd: () -> Void

    static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Formatters.locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .named
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    FoodIconView(item: item, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dernier scan : \(item.name)")
                            .font(Theme.font(14, .medium, relativeTo: .subheadline))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if !detail.isEmpty {
                            Text(detail)
                                .font(Theme.caption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(Theme.raised2, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Theme.separatorStrong, lineWidth: Theme.hairline)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ajouter \(item.name) au journal")
        }
        .padding(10)
        .background(Theme.raised.opacity(0.94), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.cardBorder, lineWidth: 1)
        }
    }
}

private struct ScanSearchingCard: View {
    let code: String?
    let step: String
    var title = "Recherche en cours…"

    var body: some View {
        HStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)
                .tint(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(step)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textSecondary)
                if let code {
                    Text(code)
                        .font(Theme.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
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
                ScanNutritionGrid(values: item.per100, unitSymbol: item.unitSymbol)
            } else {
                Label("Valeurs nutritionnelles manquantes pour ce produit.", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.callout)
                    .foregroundStyle(Theme.fat)
            }

            Button(action: hasNutrition ? onLog : onComplete) {
                Label(hasNutrition ? "Ajouter au journal" : "Compléter cet aliment",
                      systemImage: hasNutrition ? "plus" : "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ScanPrimaryButtonStyle())

            HStack(spacing: 8) {
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
}

/// Per-100 g kcal then G / P / L, 4 columns separated by hairlines.
private struct ScanNutritionGrid: View {
    let values: NutrientValues
    let unitSymbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                ScanNutrientColumn(title: "Kcal", value: values[.calories], key: .calories, showsLeadingHairline: false)
                ForEach(Theme.macroOrder, id: \.self) { key in
                    ScanNutrientColumn(title: key.label, value: values[key], key: key, showsLeadingHairline: true)
                }
            }
            .overlay(alignment: .top) { ScanHairline() }
            .overlay(alignment: .bottom) { ScanHairline() }
            Text("Pour 100 \(unitSymbol)")
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
                .tracking(0.5)
                .foregroundStyle(Theme.color(for: key))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
            .font(Theme.font(15, .bold, relativeTo: .headline))
            .foregroundStyle(isEnabled ? Theme.onAccent : Theme.textTertiary)
            .frame(maxWidth: fillsWidth ? CGFloat.infinity : nil)
            .frame(minHeight: 48)
            .background(isEnabled ? Theme.accent : Theme.separatorStrong,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Secondary action: raised2 fill.
private struct ScanSecondaryButtonStyle: ButtonStyle {
    var fillsWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(14, .medium, relativeTo: .subheadline))
            .foregroundStyle(Theme.textBody)
            .padding(.horizontal, 10)
            .frame(maxWidth: fillsWidth ? CGFloat.infinity : nil)
            .frame(minHeight: 40)
            .background(Theme.raised2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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

            HStack(spacing: 8) {
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

// MARK: - Label cards

private struct ScanLabelIdleCard: View {
    let onRead: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "text.viewfinder")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lire le tableau nutritionnel")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Valeurs pour 100 g, étiquette à plat et bien éclairée.")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Button(action: onRead) {
                Label("Lire l'étiquette", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ScanPrimaryButtonStyle())
        }
    }
}

private struct ScanLabelResultCard: View {
    let values: NutrientValues
    let onLog: () -> Void
    let onCreate: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Valeurs lues sur l'étiquette")
                    .font(Theme.font(17, .bold, relativeTo: .headline))
                    .foregroundStyle(Theme.textPrimary)
                Text("Vérifiez-les avant d'ajouter. Enregistrez l'aliment pour les corriger.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ScanNutritionGrid(values: values, unitSymbol: "g")

            Button(action: onLog) {
                Label("Ajouter au journal", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ScanPrimaryButtonStyle())

            HStack(spacing: 8) {
                Button(action: onCreate) {
                    Label("Enregistrer l'aliment", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                Button(action: onRetry) {
                    Label("Relire", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(ScanSecondaryButtonStyle())
        }
    }
}

private struct ScanLabelFailedCard: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "text.badge.xmark")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Theme.fat)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Étiquette illisible")
                        .font(Theme.font(17, .bold, relativeTo: .headline))
                        .foregroundStyle(Theme.textPrimary)
                    Text(message)
                        .font(Theme.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Button(action: onRetry) {
                Label("Réessayer", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ScanPrimaryButtonStyle())
        }
    }
}

// MARK: - Manual entry

/// Manual barcode entry: the number pad is up as soon as the sheet appears.
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
            VStack(alignment: .leading, spacing: 8) {
                Text("CODE-BARRES")
                    .font(Theme.label)
                    .tracking(0.6)
                    .foregroundStyle(Theme.textTertiary)
                TextField("Ex. 3017620422003", text: $code)
                    .keyboardType(.numberPad)
                    .autocorrectionDisabled()
                    .font(Theme.font(22, .medium, relativeTo: .title3))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.textPrimary)
                    .focused($isFocused)
                    .submitLabel(.search)
                    .onSubmit(submit)
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isFocused ? Theme.textBody : Theme.separatorStrong, lineWidth: 1.5)
                    }
                Text("Saisissez les 8 à 13 chiffres imprimés sous le code-barres.")
                    .font(Theme.caption)
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.raised.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(action: submit) {
                    Label("Rechercher", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ScanPrimaryButtonStyle())
                .disabled(!isValid)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.raised)
            }
            .navigationTitle("Saisir un code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.raised, for: .navigationBar)
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
            .task {
                // Sheets can drop the focus requested during the presentation animation.
                try? await Task.sleep(nanoseconds: 80_000_000)
                isFocused = true
            }
        }
        .presentationDetents([.medium])
        .presentationBackground(Theme.raised)
    }

    private func submit() {
        guard isValid else { return }
        let value = digits
        dismiss()
        onSubmit(value)
    }
}
