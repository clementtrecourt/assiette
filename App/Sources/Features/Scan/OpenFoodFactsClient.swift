import Foundation

/// Minimal Open Food Facts client (read-only product lookup by barcode).
/// No personal data is sent: only the barcode and a generic User-Agent.
struct OpenFoodFactsClient {
    enum ClientError: LocalizedError {
        case invalidBarcode
        case badStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidBarcode: "Code-barres invalide."
            case .badStatus(let code): "Open Food Facts a répondu avec une erreur (\(code))."
            }
        }
    }

    private static let fields = [
        "code", "product_name", "product_name_fr", "generic_name", "generic_name_fr",
        "brands", "serving_quantity", "serving_size", "nutrition_data_per",
        "quantity", "product_quantity", "product_quantity_unit", "nutriments",
    ].joined(separator: ",")

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Fetches a product from Open Food Facts. Returns nil when the product is unknown
    /// (HTTP 404 or `status` 0). Throws on network errors / unexpected HTTP status.
    static func product(barcode: String) async throws -> FoodItem? {
        let digits = barcode.filter { $0.isASCII && $0.isNumber }
        guard (6...14).contains(digits.count),
              let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(digits).json?fields=\(fields)")
        else { throw ClientError.invalidBarcode }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("Assiette-iOS/0.1", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw ClientError.badStatus(status) }
        return map(json: data, barcode: digits)
    }

    /// Pure mapping of an OFF API v2 product JSON payload to a `FoodItem`.
    /// Returns nil when the payload has no product (status 0) or is unusable.
    static func map(json: Data, barcode: String) -> FoodItem? {
        guard let root = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
        if let status = number(root["status"]), status == 0 { return nil }
        guard let product = root["product"] as? [String: Any] else { return nil }

        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        let per100 = nutrients(from: nutriments)

        let name = text(product["product_name_fr"])
            ?? text(product["product_name"])
            ?? text(product["generic_name_fr"])
            ?? text(product["generic_name"])
        if name == nil && per100.isEmpty { return nil }

        let brand = text(product["brands"])?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }

        var servingGrams: Double?
        if let q = number(product["serving_quantity"]), q > 0 { servingGrams = q }
        var servingLabel: String?
        if servingGrams != nil {
            servingLabel = text(product["serving_size"]) ?? "1 portion"
        }

        var packageGrams: Double?
        if let q = number(product["product_quantity"]), q > 0 { packageGrams = q }

        let code = barcode.isEmpty ? (text(product["code"]) ?? barcode) : barcode

        return FoodItem(
            source: .openFoodFacts,
            ref: code,
            name: name ?? "Produit \(code)",
            brand: brand,
            kind: .grocery,
            servingLabel: servingLabel,
            servingGrams: servingGrams,
            packageGrams: packageGrams,
            isLiquid: isLiquid(product),
            ean: code,
            per100: per100
        )
    }

    // MARK: - Mapping helpers

    /// (OFF key without "_100g", nutrient, factor from OFF unit to our unit).
    /// OFF stores *_100g values in grams (energy-kcal in kcal, alcohol in % vol).
    private static let nutrientMap: [(String, NutrientKey, Double)] = [
        ("proteins", .protein, 1),
        ("carbohydrates", .carbohydrates, 1),
        ("fat", .totalFat, 1),
        ("saturated-fat", .saturatedFats, 1),
        ("monounsaturated-fat", .monounsaturatedFats, 1),
        ("polyunsaturated-fat", .polyunsaturatedFats, 1),
        ("trans-fat", .transFats, 1),
        ("cholesterol", .cholesterol, 1000),
        ("fiber", .dietaryFiber, 1),
        ("sugars", .totalSugars, 1),
        ("added-sugars", .addedSugars, 1),
        ("potassium", .potassium, 1000),
        ("calcium", .calcium, 1000),
        ("iron", .iron, 1000),
        ("magnesium", .magnesium, 1000),
        ("zinc", .zinc, 1000),
        ("phosphorus", .phosphorus, 1000),
        ("vitamin-a", .vitaminA, 1_000_000),
        ("vitamin-c", .vitaminC, 1000),
        ("vitamin-d", .vitaminD, 1_000_000),
        ("vitamin-e", .vitaminE, 1000),
        ("vitamin-k", .vitaminK, 1_000_000),
        ("vitamin-b1", .thiamin, 1000),
        ("vitamin-b2", .riboflavin, 1000),
        ("vitamin-pp", .niacin, 1000),
        ("vitamin-b6", .vitaminB6, 1000),
        ("vitamin-b9", .folate, 1_000_000),
        ("vitamin-b12", .vitaminB12, 1_000_000),
        ("omega-3-fat", .omega3, 1),
        ("caffeine", .caffeine, 1000),
        ("water", .water, 1),
    ]

    private static func nutrients(from n: [String: Any]) -> NutrientValues {
        func value(_ key: String) -> Double? {
            guard let v = number(n[key + "_100g"]), v.isFinite, v >= 0 else { return nil }
            return v
        }

        var values = NutrientValues()
        if let kcal = value("energy-kcal") {
            values[.calories] = kcal
        } else if let kj = value("energy-kj") ?? value("energy") {
            values[.calories] = kj / 4.184
        }
        for (offKey, key, factor) in nutrientMap {
            if let v = value(offKey) { values[key] = v * factor }
        }
        // Sodium is in g in OFF -> mg. Fall back on salt (sodium = salt / 2.5).
        if let sodium = value("sodium") {
            values[.sodium] = sodium * 1000
        } else if let salt = value("salt") {
            values[.sodium] = salt / 2.5 * 1000
        }
        // Alcohol is expressed in % vol -> g per 100 ml (ethanol density 0.789).
        if let alcohol = value("alcohol") {
            values[.alcohol] = alcohol * 0.789
        }
        return values
    }

    private static func isLiquid(_ product: [String: Any]) -> Bool {
        let liquidUnits: Set<String> = ["ml", "cl", "dl", "l", "litre", "litres", "liter", "liters"]
        if let per = text(product["nutrition_data_per"])?.lowercased(), per.contains("ml") {
            return true
        }
        if let unit = text(product["product_quantity_unit"])?.lowercased(), liquidUnits.contains(unit) {
            return true
        }
        if let quantity = text(product["quantity"])?.lowercased() {
            // Trailing alphabetic unit, e.g. "1,5 L", "6 x 33 cl", "500 g".
            let trimmed = quantity.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            let unit = String(trimmed.reversed().prefix(while: { $0.isLetter }).reversed())
            if liquidUnits.contains(unit) { return true }
        }
        return false
    }

    private static func text(_ any: Any?) -> String? {
        guard let s = any as? String else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func number(_ any: Any?) -> Double? {
        switch any {
        case let n as NSNumber:
            return n.doubleValue
        case let s as String:
            let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: ",", with: ".")
            return Double(cleaned)
        default:
            return nil
        }
    }
}
