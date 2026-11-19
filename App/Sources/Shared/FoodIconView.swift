import SwiftUI
import UIKit

/// Rounded-square tile (Theme.raised + 1 pt Theme.separator border) showing the OpenNutrition illustration of a food (webp with alpha,
/// loaded from the OpenNutrition CDN and cached in memory + on disk). Shows a subtle SF Symbol
/// while loading, when the food has no icon, or offline.
///
/// When `icon` is nil but `foodId` is given (journal entries, favorites, recents rebuilt
/// from a `JournalEntry`), the icon name is looked up in `FoodDatabase` off the main thread.
struct FoodIconView: View {
    private let icon: String?
    private let foodId: Int64?
    private let kind: FoodKind?
    private let size: CGFloat
    private let placeholder: String?

    @Environment(\.displayScale) private var displayScale
    @State private var loadedImage: UIImage?
    @State private var loadedKey: String?

    init(icon: String?, kind: FoodKind?, size: CGFloat = 40) {
        self.init(icon: icon, foodId: nil, kind: kind, size: size, placeholder: nil)
    }

    init(icon: String?, foodId: Int64?, kind: FoodKind?, size: CGFloat = 40, placeholder: String? = nil) {
        self.icon = (icon?.isEmpty ?? true) ? nil : icon
        self.foodId = foodId
        self.kind = kind
        self.size = size
        self.placeholder = placeholder
    }

    init(item: FoodItem, size: CGFloat = 40) {
        self.init(icon: item.icon,
                  foodId: item.source == .openNutrition ? item.ref.flatMap { Int64($0) } : nil,
                  kind: item.kind,
                  size: size,
                  placeholder: FoodIconView.placeholderSymbol(for: item.source))
    }

    /// Symbol for items without a kind (custom foods, Open Food Facts, quick adds).
    static func placeholderSymbol(for source: FoodSource) -> String? {
        switch source {
        case .openNutrition: return nil
        case .custom: return "fork.knife"
        case .openFoodFacts: return "barcode"
        case .quickAdd: return "bolt.fill"
        }
    }

    /// Tile shape: radius proportional to the size (7 pt at 32 pt, as in the mockup).
    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: (size * 0.22).rounded(), style: .continuous)
    }

    /// Illustration inside the tile (~72 % of the side, leaving a margin around it).
    private var imageSide: CGFloat { (size * 0.72).rounded() }

    private var pixelSide: Int { max(Int((imageSide * max(displayScale, 1)).rounded()), 1) }

    /// Identity of the image to show: changes when the row is reused for another food.
    private var taskKey: String {
        "\(icon ?? "")|\(foodId.map { String($0) } ?? "")|\(pixelSide)"
    }

    /// Image available synchronously (memory cache), so cached icons never flash.
    private var cachedImage: UIImage? {
        var name: String? = icon
        if name == nil, let foodId, let cached = FoodIconLoader.cachedIconName(forFoodId: foodId) {
            name = cached
        }
        guard let name else { return nil }
        return FoodIconLoader.memoryImage(name: name, pixelSide: pixelSide)
    }

    var body: some View {
        let image = cachedImage ?? (loadedKey == taskKey ? loadedImage : nil)
        ZStack {
            tileShape
                .fill(Theme.raised)
            tileShape
                .strokeBorder(Theme.separator, lineWidth: Theme.hairline)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: imageSide, height: imageSide)
            } else {
                Image(systemName: placeholder ?? kind?.systemImage ?? "fork.knife")
                    .font(.system(size: size * 0.4, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: taskKey) {
            await load(key: taskKey)
        }
    }

    private func load(key: String) async {
        if cachedImage != nil { return }
        var name = icon
        if name == nil, let foodId {
            name = await FoodIconLoader.shared.iconName(forFoodId: foodId)
        }
        guard let name, !Task.isCancelled else { return }
        let image = await FoodIconLoader.shared.image(name: name, pixelSide: pixelSide)
        guard !Task.isCancelled else { return }
        loadedImage = image
        loadedKey = key
    }
}

/// Shared icon loader: de-duplicates in-flight downloads, decodes + downscales once per
/// display size off the main thread, caches decoded images in memory (NSCache) and raw
/// webp files in Caches/FoodIcons/<basename>.webp.
actor FoodIconLoader {
    static let shared = FoodIconLoader()

    private static let baseURL = "https://drd3kry2ubqnc.cloudfront.net/"

    private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        return cache
    }()

    /// foodId -> icon basename ("" = the food has no icon).
    private static let iconNames: NSCache<NSNumber, NSString> = {
        let cache = NSCache<NSNumber, NSString>()
        cache.countLimit = 2000
        return cache
    }()

    private var inFlight: [String: Task<FoodIconLoadResult, Never>] = [:]
    /// Names the CDN answered with an error (e.g. 404): not retried during this session.
    private var missing: Set<String> = []

    private static func cacheKey(name: String, pixelSide: Int) -> String { "\(name)@\(pixelSide)" }

    // MARK: Synchronous cache peeks (thread-safe, NSCache)

    static func memoryImage(name: String, pixelSide: Int) -> UIImage? {
        images.object(forKey: cacheKey(name: name, pixelSide: pixelSide) as NSString)
    }

    /// `.some(nil)` when the food is known to have no icon, nil when not looked up yet.
    static func cachedIconName(forFoodId id: Int64) -> String?? {
        guard let value = iconNames.object(forKey: NSNumber(value: id)) else { return nil }
        let name = value as String
        return .some(name.isEmpty ? nil : name)
    }

    // MARK: Loading

    /// Icon basename of a bundled food, resolved from the database off the main thread.
    func iconName(forFoodId id: Int64) async -> String? {
        if let cached = Self.cachedIconName(forFoodId: id) { return cached }
        let name = await Task.detached(priority: .utility) {
            FoodDatabase.shared.iconName(forFoodId: id)
        }.value
        Self.iconNames.setObject((name ?? "") as NSString, forKey: NSNumber(value: id))
        return name
    }

    func image(name: String, pixelSide: Int) async -> UIImage? {
        let key = Self.cacheKey(name: name, pixelSide: pixelSide)
        if let image = Self.images.object(forKey: key as NSString) { return image }
        if missing.contains(name) { return nil }
        if let task = inFlight[key] { return await task.value.image }

        let task = Task.detached(priority: .utility) { () -> FoodIconLoadResult in
            await FoodIconLoader.fetch(name: name, pixelSide: pixelSide)
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        if let image = result.image {
            Self.images.setObject(image, forKey: key as NSString)
        } else if result.notFound {
            missing.insert(name)
        }
        return result.image
    }

    // MARK: Disk + network (nonisolated, runs on a background task)

    private static let directory: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = caches.appendingPathComponent("FoodIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func safeName(_ name: String) -> String {
        String(name.map { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" ? $0 : "_" })
    }

    private static func fetch(name: String, pixelSide: Int) async -> FoodIconLoadResult {
        let file = directory?.appendingPathComponent(safeName(name) + ".webp")
        if let file, let data = try? Data(contentsOf: file), let image = decode(data, pixelSide: pixelSide) {
            return FoodIconLoadResult(image: image, notFound: false)
        }
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: baseURL + encoded + "@4x.webp") else {
            return FoodIconLoadResult(image: nil, notFound: true)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let fetched: (Data, URLResponse)? = try? await URLSession.shared.data(for: request)
        guard let fetched else {
            return FoodIconLoadResult(image: nil, notFound: false) // offline: retry later
        }
        let data = fetched.0
        let status = (fetched.1 as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, let image = decode(data, pixelSide: pixelSide) else {
            return FoodIconLoadResult(image: nil, notFound: (400..<500).contains(status) || status == 200)
        }
        if let file {
            try? data.write(to: file, options: .atomic)
        }
        return FoodIconLoadResult(image: image, notFound: false)
    }

    /// Decodes the webp and redraws it once at the display size (smooth scrolling: no
    /// per-frame scaling of the 192 px source).
    private static func decode(_ data: Data, pixelSide: Int) -> UIImage? {
        guard let source = UIImage(data: data), source.size.width > 0, source.size.height > 0 else {
            return nil
        }
        let side = CGFloat(pixelSide)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let ratio = min(side / source.size.width, side / source.size.height)
        let drawSize = CGSize(width: source.size.width * ratio, height: source.size.height * ratio)
        let origin = CGPoint(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2)
        return renderer.image { _ in
            source.draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}

/// Result of one icon fetch (`notFound` = do not retry this session). Unchecked: UIImage is
/// immutable once rendered, and `Task` requires a Sendable result.
struct FoodIconLoadResult: @unchecked Sendable {
    let image: UIImage?
    let notFound: Bool
}
