import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

/// IA tab of the add sheet, two modes:
/// - Snap: live camera filling the panel; shutter (or a library photo) sends it straight away.
/// - Describe: up to 3 photos (camera or library) plus a text, then "Analyser".
/// The estimate opens the quick add form, prefilled, to check before adding.
struct AIEstimateView: View {
    let context: LogContext
    let onLogged: () -> Void

    private enum Mode { case snap, describe }

    @State private var mode: Mode = .snap
    @State private var estimate: PhotoEstimate?
    @State private var generation = 0
    @StateObject private var camera = LiveCamera()
    @State private var torchOn = false

    // Describe
    @State private var photos: [AIPhoto] = []
    @State private var note = ""
    @State private var showingCapturePage = false
    @FocusState private var noteFocused: Bool

    // Library
    @State private var showingLibrary = false
    @State private var libraryItems: [PhotosPickerItem] = []

    // Request
    @State private var isWorking = false
    @State private var errorText: String?
    @State private var showingKey = false
    @State private var pendingRun: (() -> Void)?

    private static let maxPhotos = 3
    private static let maxNote = 500

    var body: some View {
        ZStack {
            if let estimate {
                result(estimate)
                    .transition(.move(edge: .trailing))
            } else {
                Group {
                    switch mode {
                    case .snap: snap
                    case .describe: describe
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: estimate)
        .photosPicker(isPresented: $showingLibrary, selection: $libraryItems,
                      maxSelectionCount: mode == .snap ? 1 : max(1, Self.maxPhotos - photos.count),
                      matching: .images)
        .onChange(of: libraryItems) { _, items in
            guard !items.isEmpty else { return }
            libraryItems = []
            Task { await importLibrary(items) }
        }
        .slideCover(isPresented: $showingKey, onDismiss: {
            let run = pendingRun
            pendingRun = nil
            if ClaudeKey.read() != nil { run?() }
        }) {
            ClaudeKeySheet()
        }
        .slideCover(isPresented: $showingCapturePage) {
            AICapturePage(remaining: Self.maxPhotos - photos.count) { image in
                addPhoto(image)
            }
        }
        .onChange(of: torchOn) { _, on in camera.setTorch(on) }
        .onChange(of: cameraWanted) { _, wanted in
            if wanted { camera.start() } else { torchOn = false; camera.stop() }
        }
        .onAppear { if cameraWanted { camera.start() } }
        .onDisappear { torchOn = false; camera.stop() }
    }

    private var cameraWanted: Bool { mode == .snap && estimate == nil && !showingCapturePage }

    // MARK: - Snap

    private var snap: some View {
        ZStack {
            Color.black
            LiveCameraPreview(camera: camera)
                .opacity(camera.state == .running ? 1 : 0)
            if camera.state == .denied {
                cameraDenied
            }
            if isWorking {
                analyzing
            }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    modeSwitch(dark: true)
                    Spacer(minLength: 8)
                    AIRoundButton(systemImage: "square.and.arrow.up", label: "Importer une photo") {
                        showingLibrary = true
                    }
                    if camera.hasTorch {
                        AIRoundButton(systemImage: torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                                      label: torchOn ? "Éteindre la lampe" : "Allumer la lampe",
                                      isOn: torchOn) { torchOn.toggle() }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                if let errorText {
                    errorLabel(errorText)
                        .padding(12)
                        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                }
                Spacer()
                shutter
                    .padding(.bottom, 28)
            }
        }
        .clipped()
    }

    private var shutter: some View {
        Button {
            Task { await snapPhoto() }
        } label: {
            ZStack {
                Circle().strokeBorder(Color.white, lineWidth: 4).frame(width: 82, height: 82)
                Circle().fill(Color.white).frame(width: 68, height: 68)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isWorking || camera.state != .running)
        .opacity(isWorking ? 0.4 : 1)
        .accessibilityLabel("Prendre la photo et analyser")
    }

    private var analyzing: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large).tint(.white)
            Text("Analyse en cours…")
                .font(Theme.font(17, .medium, relativeTo: .body))
                .foregroundStyle(.white)
        }
        .padding(24)
        .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var cameraDenied: some View {
        VStack(spacing: 12) {
            Text("Autorisez la caméra dans Réglages pour photographier vos repas.")
                .font(Theme.font(15, .regular, relativeTo: .subheadline))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Ouvrir Réglages") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .font(Theme.font(15, .medium, relativeTo: .body))
            .tint(Theme.textPrimary)
        }
        .padding(32)
    }

    // MARK: - Describe

    private var describe: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    modeSwitch(dark: false)
                        .padding(.bottom, 28)

                    sectionHeader("Photos", count: "\(photos.count)/\(Self.maxPhotos)")
                    HStack(spacing: 12) {
                        Button { noteFocused = false; showingCapturePage = true } label: {
                            Label("Prendre", systemImage: "camera.fill")
                                .font(Theme.font(20, .regular, relativeTo: .title3))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 66)
                                .background(Theme.raised2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        Button { noteFocused = false; showingLibrary = true } label: {
                            Image(systemName: "icloud.and.arrow.up.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(width: 66, height: 66)
                                .background(Theme.raised2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Importer des photos")
                    }
                    .disabled(photos.count >= Self.maxPhotos || isWorking)
                    .opacity(photos.count >= Self.maxPhotos ? 0.4 : 1)

                    if !photos.isEmpty {
                        thumbnails.padding(.top, 12)
                    }

                    sectionHeader("Description", count: "\(note.count)/\(Self.maxNote)")
                        .padding(.top, 28)
                    TextField("", text: $note,
                              prompt: Text("Décrivez votre repas").foregroundColor(Theme.textTertiary),
                              axis: .vertical)
                        .lineLimit(3...8)
                        .focused($noteFocused)
                        .font(Theme.font(17, .regular, relativeTo: .body))
                        .foregroundStyle(Theme.textPrimary)
                        .tint(Theme.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .frame(minHeight: 96, alignment: .topLeading)
                        .background(Theme.raised2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .onChange(of: note) { _, text in
                            if text.count > Self.maxNote { note = String(text.prefix(Self.maxNote)) }
                        }

                    if let errorText {
                        errorLabel(errorText).padding(.top, 12)
                    }

                    Button { showingKey = true } label: {
                        Label("Clé Claude", systemImage: "key")
                            .font(Theme.font(15, .regular, relativeTo: .subheadline))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 20)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)

            analyzeButton
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
        }
        .background(Theme.raised.ignoresSafeArea())
    }

    private var canAnalyze: Bool {
        !isWorking && (!photos.isEmpty || !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var analyzeButton: some View {
        Button {
            noteFocused = false
            let jpegs = photos.map(\.jpeg)
            run { await analyze(jpegs: jpegs, note: note) }
        } label: {
            HStack(spacing: 10) {
                if isWorking { ProgressView().tint(Theme.onAccent) }
                Text(isWorking ? "Analyse en cours…" : "Analyser")
                    .font(Theme.font(20, .medium, relativeTo: .title3))
            }
            .foregroundStyle(canAnalyze || isWorking ? Theme.onAccent : Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background(canAnalyze || isWorking ? Theme.accent : Theme.raised2,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canAnalyze)
    }

    private var thumbnails: some View {
        HStack(spacing: 10) {
            ForEach(photos) { photo in
                Image(uiImage: photo.thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button {
                            withAnimation(.snappy) { photos.removeAll { $0.id == photo.id } }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.black.opacity(0.7), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(5)
                        .accessibilityLabel("Retirer la photo")
                    }
            }
        }
    }

    private func sectionHeader(_ title: String, count: String) -> some View {
        HStack {
            Text(title)
                .font(Theme.font(20, .medium, relativeTo: .title3))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(count)
                .font(Theme.font(20, .regular, relativeTo: .title3))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.bottom, 12)
    }

    // MARK: - Shared pieces

    /// "Snap / Describe": white pill on a dark capsule (over the camera, or on the panel).
    private func modeSwitch(dark: Bool) -> some View {
        HStack(spacing: 0) {
            modeSegment(.snap, title: "Photo")
            modeSegment(.describe, title: "Décrire")
        }
        .padding(5)
        .background(dark ? AnyShapeStyle(Color.black.opacity(0.75)) : AnyShapeStyle(Theme.raised2),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func modeSegment(_ value: Mode, title: String) -> some View {
        let isSelected = mode == value
        return Button {
            errorText = nil
            withAnimation(.snappy(duration: 0.2)) { mode = value }
            if value == .describe {
                Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    if photos.isEmpty { noteFocused = true }
                }
            } else {
                noteFocused = false
            }
        } label: {
            Text(title)
                .font(Theme.font(17, .regular, relativeTo: .body))
                .foregroundStyle(isSelected ? Color.black : Theme.textPrimary)
                .padding(.horizontal, 20)
                .frame(height: 44)
                .background {
                    if isSelected { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white) }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func errorLabel(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(Theme.font(15, .regular, relativeTo: .subheadline))
            .foregroundStyle(Theme.overTarget)
    }

    // MARK: - Result

    private func result(_ estimate: PhotoEstimate) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.smooth(duration: 0.3)) { self.estimate = nil }
            } label: {
                Label("Nouvelle analyse", systemImage: "chevron.left")
                    .font(Theme.font(15, .regular, relativeTo: .subheadline))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
            .buttonStyle(.plain)
            QuickAddSheet(context: context, isEmbedded: true, estimate: estimate, onLogged: onLogged)
                .id(generation)
        }
        .background(Theme.raised.ignoresSafeArea())
    }

    // MARK: - Actions

    /// Runs `work` now, or after the API key has been entered.
    private func run(_ work: @escaping () async -> Void) {
        errorText = nil
        if ClaudeKey.read() == nil {
            pendingRun = { Task { await work() } }
            showingKey = true
        } else {
            Task { await work() }
        }
    }

    private func snapPhoto() async {
        guard ClaudeKey.read() != nil else {
            run { await snapPhoto() }
            return
        }
        errorText = nil
        isWorking = true
        guard let image = await camera.capture(), let jpeg = PhotoEstimator.jpeg(from: image) else {
            isWorking = false
            errorText = "Impossible de prendre la photo. Réessayez."
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        await analyze(jpegs: [jpeg], note: "")
    }

    private func analyze(jpegs: [Data], note: String) async {
        guard let key = ClaudeKey.read() else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let value = try await PhotoEstimator.estimate(jpegs: jpegs, note: note, apiKey: key)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            generation += 1
            estimate = value
            photos = []
            self.note = ""
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func importLibrary(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }
        guard !images.isEmpty else {
            errorText = "Impossible d'ouvrir cette photo."
            return
        }
        if mode == .snap {
            guard let jpeg = PhotoEstimator.jpeg(from: images[0]) else { return }
            run { await analyze(jpegs: [jpeg], note: "") }
        } else {
            images.forEach(addPhoto)
        }
    }

    private func addPhoto(_ image: UIImage) {
        guard photos.count < Self.maxPhotos, let photo = AIPhoto(image) else { return }
        withAnimation(.snappy) { photos.append(photo) }
    }
}

/// A photo of the Describe mode: the JPEG sent to the API and a small preview.
private struct AIPhoto: Identifiable {
    let id = UUID()
    let jpeg: Data
    let thumbnail: UIImage

    init?(_ image: UIImage) {
        guard let jpeg = PhotoEstimator.jpeg(from: image) else { return nil }
        self.jpeg = jpeg
        let side: CGFloat = 240
        let scale = side / max(1, min(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        thumbnail = UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

/// Full page camera of the Describe mode: each shot is added, up to `remaining`.
private struct AICapturePage: View {
    let remaining: Int
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = LiveCamera()
    @State private var taken = 0
    @State private var torchOn = false
    @State private var isCapturing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            LiveCameraPreview(camera: camera)
                .ignoresSafeArea()
            VStack {
                HStack(spacing: 10) {
                    AIRoundButton(systemImage: "xmark", label: "Fermer") { dismiss() }
                    Spacer()
                    Text("\(taken)/\(remaining)")
                        .font(Theme.font(17, .medium, relativeTo: .body))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 50)
                        .background(Color.black.opacity(0.75), in: Capsule())
                    Spacer()
                    if camera.hasTorch {
                        AIRoundButton(systemImage: torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                                      label: torchOn ? "Éteindre la lampe" : "Allumer la lampe",
                                      isOn: torchOn) { torchOn.toggle() }
                    } else {
                        Color.clear.frame(width: 50, height: 50)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                Spacer()
                Button {
                    Task {
                        isCapturing = true
                        defer { isCapturing = false }
                        guard let image = await camera.capture() else { return }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onCapture(image)
                        taken += 1
                        if taken >= remaining { dismiss() }
                    }
                } label: {
                    ZStack {
                        Circle().strokeBorder(Color.white, lineWidth: 4).frame(width: 82, height: 82)
                        Circle().fill(Color.white).frame(width: 68, height: 68)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isCapturing || camera.state != .running)
                .accessibilityLabel("Prendre la photo")
                .padding(.bottom, 24)
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.setTorch(false); camera.stop() }
        .onChange(of: torchOn) { _, on in camera.setTorch(on) }
    }
}

/// Round 50 pt black button over the camera.
private struct AIRoundButton: View {
    let systemImage: String
    let label: String
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isOn ? Color.black : Color.white)
                .frame(width: 50, height: 50)
                .background(isOn ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.black.opacity(0.75)), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Camera

/// Back camera with a still photo output. The session runs on its own queue.
final class LiveCamera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    enum State { case idle, running, denied, unavailable }

    @Published private(set) var state: State = .idle
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "app.assiette.ai-camera")
    private var device: AVCaptureDevice?
    private var configured = false
    private var wantsRunning = false
    private var pending: CheckedContinuation<UIImage?, Never>?

    var hasTorch: Bool { device?.hasTorch ?? false }

    func start() {
        wantsRunning = true
        Task { @MainActor in
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .notDetermined:
                guard await AVCaptureDevice.requestAccess(for: .video) else { state = .denied; return }
            case .denied, .restricted:
                state = .denied
                return
            default:
                break
            }
            guard wantsRunning else { return }
            queue.async { [self] in
                if !configured { configure() }
                guard configured, wantsRunning, !session.isRunning else { return }
                session.startRunning()
                let running = session.isRunning
                DispatchQueue.main.async { self.state = running ? .running : .unavailable }
            }
        }
    }

    func stop() {
        wantsRunning = false
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            DispatchQueue.main.async { if self.state == .running { self.state = .idle } }
        }
    }

    private func configure() {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else { return }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        device = camera
        configured = true
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    func setTorch(_ on: Bool) {
        queue.async { [self] in
            guard let device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }

    @MainActor
    func capture() async -> UIImage? {
        guard state == .running, pending == nil else { return nil }
        return await withCheckedContinuation { continuation in
            pending = continuation
            queue.async { [self] in
                let settings = AVCapturePhotoSettings()
                if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        DispatchQueue.main.async {
            self.pending?.resume(returning: image)
            self.pending = nil
        }
    }
}

/// Preview layer of a `LiveCamera` session, filling its frame.
struct LiveCameraPreview: UIViewRepresentable {
    @ObservedObject var camera: LiveCamera

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = camera.session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
