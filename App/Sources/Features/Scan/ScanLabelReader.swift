import Foundation
import ImageIO
import UIKit
import Vision

/// Reads a nutrition facts label photo: Vision text recognition, then rows of text rebuilt
/// from the observations' positions (label on the left, values on the right of the same row).
enum ScanLabelReader {
    /// Recognized text, one string per visual row, top to bottom.
    static func recognizeRows(in image: UIImage) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let imageOrientation = ScanLabelReader.orientation(of: image)
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                request.recognitionLanguages = ["fr-FR", "en-US"]
                let handler = VNImageRequestHandler(cgImage: cgImage, orientation: imageOrientation, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: [])
                    return
                }
                let observations = request.results ?? []
                continuation.resume(returning: ScanLabelReader.rows(from: observations))
            }
        }
    }

    private struct Piece {
        let midX: CGFloat
        let midY: CGFloat
        let height: CGFloat
        let text: String
    }

    /// Groups observations whose vertical centers are close into one row, left to right.
    private static func rows(from observations: [VNRecognizedTextObservation]) -> [String] {
        let pieces: [Piece] = observations.compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
            let box = observation.boundingBox
            return Piece(midX: box.midX, midY: box.midY, height: box.height, text: text)
        }
        // Vision's origin is bottom-left: higher midY = higher on the label.
        let sorted = pieces.sorted { $0.midY > $1.midY }
        var groups: [[Piece]] = []
        for piece in sorted {
            if let last = groups.last, let reference = last.first {
                let tolerance = max(reference.height, piece.height) * 0.6
                if abs(reference.midY - piece.midY) <= tolerance {
                    groups[groups.count - 1].append(piece)
                    continue
                }
            }
            groups.append([piece])
        }
        return groups.map { group in
            group.sorted { $0.midX < $1.midX }.map(\.text).joined(separator: " ")
        }
    }

    private static func orientation(of image: UIImage) -> CGImagePropertyOrientation {
        switch image.imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

/// Pure parser of nutrition label text (French or English) into per-100 g values.
/// Takes, for each nutrient, the first amount written after its name on the same row
/// (the "pour 100 g" column comes first on EU labels).
enum ScanLabelParser {
    struct Token: Equatable {
        let value: Double
        /// Letters right after the number, lowercased (e.g. "g", "kcal", "kj", "mg").
        let unit: String
    }

    private struct Keyword {
        let key: NutrientKey
        let pattern: String
        let wholeWord: Bool
        /// Converts (value, unit) into the stored unit of `key`.
        let convert: (Double, String) -> Double
    }

    private static let grams: (Double, String) -> Double = { value, unit in
        unit.hasPrefix("mg") ? value / 1000 : value
    }

    private static let keywords: [Keyword] = [
        Keyword(key: .saturatedFats, pattern: "satur", wholeWord: false, convert: grams),
        Keyword(key: .totalSugars, pattern: "sucre", wholeWord: false, convert: grams),
        Keyword(key: .totalSugars, pattern: "sugar", wholeWord: false, convert: grams),
        Keyword(key: .dietaryFiber, pattern: "fibre", wholeWord: false, convert: grams),
        Keyword(key: .dietaryFiber, pattern: "fiber", wholeWord: false, convert: grams),
        // Salt (g) → sodium (mg): sodium = salt / 2.5.
        Keyword(key: .sodium, pattern: "sel", wholeWord: true, convert: { value, unit in
            (unit.hasPrefix("mg") ? value / 1000 : value) * 400
        }),
        Keyword(key: .sodium, pattern: "salt", wholeWord: true, convert: { value, unit in
            (unit.hasPrefix("mg") ? value / 1000 : value) * 400
        }),
        Keyword(key: .sodium, pattern: "sodium", wholeWord: true, convert: { value, unit in
            unit.hasPrefix("mg") ? value : value * 1000
        }),
        Keyword(key: .carbohydrates, pattern: "glucide", wholeWord: false, convert: grams),
        Keyword(key: .carbohydrates, pattern: "carbohydrate", wholeWord: false, convert: grams),
        Keyword(key: .protein, pattern: "protein", wholeWord: false, convert: grams),
        Keyword(key: .totalFat, pattern: "matieres grasses", wholeWord: false, convert: grams),
        Keyword(key: .totalFat, pattern: "matiere grasse", wholeWord: false, convert: grams),
        Keyword(key: .totalFat, pattern: "lipide", wholeWord: false, convert: grams),
        Keyword(key: .totalFat, pattern: "graisse", wholeWord: false, convert: grams),
        Keyword(key: .totalFat, pattern: "fat", wholeWord: true, convert: grams),
    ]

    private struct Hit {
        let keyword: Keyword
        let start: Int
        let end: Int
    }

    /// Per-100 g values read from the label rows, or nil when nothing usable was found.
    static func parse(lines: [String]) -> NutrientValues? {
        var values = NutrientValues()
        var kcal: Double?
        var kj: Double?

        for raw in lines {
            let line = normalize(raw)
            guard !line.isEmpty else { continue }
            let tokens = ScanLabelParser.tokens(in: line)

            // Energy.
            if kcal == nil, let token = tokens.first(where: { $0.unit.hasPrefix("kcal") }),
               token.value > 0, token.value <= 950 {
                kcal = token.value
            }
            if kj == nil, let token = tokens.first(where: { $0.unit == "kj" }), token.value > 0 {
                kj = token.value
            }
            if kcal == nil, line.contains("kcal"), tokens.count >= 2 {
                // "Énergie (kJ/kcal) 1546/368": a kJ value followed by its kcal equivalent.
                for index in 0..<(tokens.count - 1) {
                    let a = tokens[index].value
                    let b = tokens[index + 1].value
                    if b > 0, b <= 950, abs(a / 4.184 - b) <= max(3, b * 0.06) {
                        kcal = b
                        break
                    }
                }
            }
            if kcal == nil, line.hasPrefix("calorie"), !line.contains("kj"),
               let token = tokens.first(where: { $0.unit.isEmpty }), token.value > 0, token.value <= 950 {
                // US style "Calories 230".
                kcal = token.value
            }

            // Nutrients: each keyword owns the text up to the next keyword on the row.
            let hits = keywordHits(in: line)
            let characters = Array(line)
            for (index, hit) in hits.enumerated() {
                let key = hit.keyword.key
                guard values[key] == nil else { continue }
                let end = index + 1 < hits.count ? hits[index + 1].start : characters.count
                guard hit.end < end else { continue }
                let segment = String(characters[hit.end..<end])
                guard let token = ScanLabelParser.tokens(in: segment).first(where: { !$0.unit.hasPrefix("kj") && !$0.unit.hasPrefix("kcal") })
                else { continue }
                let amount = hit.keyword.convert(token.value, token.unit)
                let limit: Double = key == .sodium ? 40000 : 100
                guard amount >= 0, amount <= limit else { continue }
                values[key] = amount
            }
        }

        if kcal == nil, let kj { kcal = kj / 4.184 }
        let macroCount = [NutrientKey.carbohydrates, .protein, .totalFat].filter { values[$0] != nil }.count
        if kcal == nil, macroCount >= 2 {
            kcal = values.carbs * 4 + values.protein * 4 + values.fat * 9
        }
        // Usable when the energy or at least one macro was read.
        guard let kcal, kcal > 0 || macroCount >= 1 else { return nil }
        values[.calories] = kcal
        return values
    }

    /// Lowercased, accents removed, single spaces.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
        return folded
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Numbers of a line with the letters right after them ("12,5 g", "368kcal", "<0,5 g").
    static func tokens(in line: String) -> [Token] {
        let characters = Array(line)
        var result: [Token] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            guard character.isASCII, character.isNumber else {
                index += 1
                continue
            }
            // Ignore digits glued to letters before them ("b12", "omega3").
            if index > 0, characters[index - 1].isLetter {
                while index < characters.count, characters[index].isASCII, characters[index].isNumber {
                    index += 1
                }
                continue
            }
            var text = ""
            var hasSeparator = false
            while index < characters.count {
                let current = characters[index]
                if current.isASCII, current.isNumber {
                    text.append(current)
                    index += 1
                } else if current == "," || current == ".", !hasSeparator,
                          index + 1 < characters.count,
                          characters[index + 1].isASCII, characters[index + 1].isNumber {
                    text.append(".")
                    hasSeparator = true
                    index += 1
                } else {
                    break
                }
            }
            var cursor = index
            while cursor < characters.count, characters[cursor] == " " {
                cursor += 1
            }
            var unit = ""
            while cursor < characters.count, characters[cursor].isLetter, unit.count < 4 {
                unit.append(characters[cursor])
                cursor += 1
            }
            if let value = Double(text) {
                result.append(Token(value: value, unit: unit))
            }
        }
        return result
    }

    private static func keywordHits(in line: String) -> [Hit] {
        let characters = Array(line)
        var hits: [Hit] = []
        var saturStarts: [Int] = []
        for keyword in keywords {
            let pattern = Array(keyword.pattern)
            guard pattern.count <= characters.count else { continue }
            var start = 0
            while start + pattern.count <= characters.count {
                guard Array(characters[start..<(start + pattern.count)]) == pattern else {
                    start += 1
                    continue
                }
                let end = start + pattern.count
                if keyword.pattern == "satur" { saturStarts.append(start) }
                var accepted = true
                if keyword.wholeWord {
                    let before = start > 0 ? characters[start - 1] : " "
                    let after = end < characters.count ? characters[end] : " "
                    // Allow plurals: "sels", "fats".
                    let afterIsPlural = after == "s" && (end + 1 >= characters.count || !characters[end + 1].isLetter)
                    if before.isLetter || (after.isLetter && !afterIsPlural) { accepted = false }
                }
                if keyword.pattern == "satur", start >= 2 {
                    let prefix = String(characters[(start - 2)..<start])
                    // "insaturés", "unsaturated": not saturated fats.
                    if prefix == "in" || prefix == "un" { accepted = false }
                }
                if accepted {
                    hits.append(Hit(keyword: keyword, start: start, end: end))
                }
                start = end
            }
        }
        // "saturated fat", "trans fat", "monounsaturated fat": the word "fat" belongs to them.
        hits.removeAll { hit in
            guard hit.keyword.pattern == "fat" else { return false }
            if saturStarts.contains(where: { $0 < hit.start && hit.start - $0 <= 16 }) { return true }
            let from = max(0, hit.start - 8)
            return String(characters[from..<hit.start]).contains("trans")
        }
        hits.sort { $0.start < $1.start }
        // Drop overlapping hits (keep the first).
        var result: [Hit] = []
        for hit in hits {
            if let last = result.last, hit.start < last.end { continue }
            result.append(hit)
        }
        return result
    }
}
