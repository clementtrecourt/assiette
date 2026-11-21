import Foundation
import PhotosUI
import Security
import SwiftUI
import UIKit

/// Calories and G / P / L of a meal photo, estimated by Claude. Prefills the quick add form.
struct PhotoEstimate: Decodable, Equatable {
    var name: String
    var kcal: Double
    var carbsG: Double
    var proteinG: Double
    var fatG: Double

    enum CodingKeys: String, CodingKey {
        case name, kcal
        case carbsG = "carbs_g"
        case proteinG = "protein_g"
        case fatG = "fat_g"
    }
}

/// Claude API key, kept in the Keychain of this device only.
enum ClaudeKey {
    private static let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                               kSecAttrService as String: "app.assiette.claude",
                                               kSecAttrAccount as String: "api-key"]

    static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        var value: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &value) == errSecSuccess,
              let data = value as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8),
                                         kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess
        }
        return result == errSecSuccess
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

enum PhotoEstimateError: LocalizedError {
    case badKey, rateLimited, overloaded, refused, unreadable, http(Int, String?)

    var errorDescription: String? {
        switch self {
        case .badKey: "Clé API refusée. Vérifiez-la dans « Clé Claude »."
        case .rateLimited: "Trop de demandes ou crédit épuisé. Réessayez plus tard."
        case .overloaded: "Le service est surchargé. Réessayez dans un instant."
        case .refused: "L'IA n'a pas pu analyser cette photo."
        case .unreadable: "Réponse illisible. Réessayez."
        case .http(let code, let message): "Erreur \(code)\(message.map { " : \($0)" } ?? "")"
        }
    }
}

/// One Messages API call (raw HTTP: there is no official Swift SDK).
enum PhotoEstimator {
    static let model = "claude-sonnet-5-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    private static let instructions = """
    Tu estimes la nutrition d'un repas à partir de photos et/ou d'une description, pour un journal alimentaire.
    Plusieurs photos montrent le même repas sous différents angles : ne compte pas deux fois un aliment.
    Estime l'ensemble de ce qui est visible et destiné à être mangé : identifie chaque aliment, \
    estime sa quantité en grammes d'après la taille de l'assiette, des couverts et des contenants, \
    et compte les matières grasses de cuisson et les sauces probables. \
    Si une note de l'utilisateur est donnée, elle prime sur ce que tu vois (quantités, ingrédients).
    Réponds avec : name, un nom court en français (moins de 40 caractères) ; kcal, l'énergie totale ; \
    carbs_g, protein_g, fat_g, les glucides, protéines et lipides totaux en grammes. \
    Les kcal doivent rester cohérentes avec 4 × glucides + 4 × protéines + 9 × lipides. \
    Si rien ne correspond à de la nourriture, renvoie des zéros et name = "Aucun aliment".
    """

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "name": ["type": "string"],
            "kcal": ["type": "number"],
            "carbs_g": ["type": "number"],
            "protein_g": ["type": "number"],
            "fat_g": ["type": "number"],
        ],
        "required": ["name", "kcal", "carbs_g", "protein_g", "fat_g"],
        "additionalProperties": false,
    ]

    /// `jpegs`: 0 to 3 photos; `note`: what the user typed. At least one of the two.
    static func estimate(jpegs: [Data], note: String, apiKey: String) async throws -> PhotoEstimate {
        var content: [[String: Any]] = jpegs.map { jpeg in
            ["type": "image",
             "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]]
        }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let ask = jpegs.isEmpty ? "Estime ce repas d'après sa description." : "Estime ce repas."
        content.append(["type": "text", "text": trimmed.isEmpty ? ask : "\(ask) Note de l'utilisateur : \(trimmed)"])
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 8000,
            "system": instructions,
            "output_config": ["effort": "medium", "format": ["type": "json_schema", "schema": schema]],
            // On a refusal, the API retries on a fallback model inside the same call.
            "fallbacks": "default",
            "messages": [["role": "user", "content": content]],
        ]

        var request = URLRequest(url: endpoint, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            switch status {
            case 401, 403: throw PhotoEstimateError.badKey
            case 429: throw PhotoEstimateError.rateLimited
            case 529, 503: throw PhotoEstimateError.overloaded
            default:
                let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"]
                throw PhotoEstimateError.http(status, (error as? [String: Any])?["message"] as? String)
            }
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PhotoEstimateError.unreadable
        }
        if json["stop_reason"] as? String == "refusal" { throw PhotoEstimateError.refused }
        let blocks = json["content"] as? [[String: Any]] ?? []
        guard let text = blocks.last(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let estimate = try? JSONDecoder().decode(PhotoEstimate.self, from: Data(text.utf8)) else {
            throw PhotoEstimateError.unreadable
        }
        return estimate
    }

    /// Long edge at most 1280 px, JPEG: about 1 500 image tokens per photo.
    static func jpeg(from image: UIImage) -> Data? {
        let longEdge = max(image.size.width, image.size.height)
        let scale = min(1, 1280 / max(longEdge, 1))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.7)
    }
}

/// Paste the Claude API key once; it stays in the Keychain.
struct ClaudeKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ClaudeKey.read() ?? ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-…", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                } footer: {
                    Text("La clé reste sur cet iPhone (Keychain). Chaque photo est envoyée à l'API Claude (\(PhotoEstimator.model)), environ 0,015 $ par photo.")
                }
                if ClaudeKey.read() != nil {
                    Button("Supprimer la clé", role: .destructive) {
                        ClaudeKey.delete()
                        key = ""
                    }
                }
            }
            .navigationTitle("Clé Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        ClaudeKey.save(key.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task { focused = true }
        }
    }
}
