import Foundation
import Security

enum InterviewProvider: String, CaseIterable, Identifiable {
    case groq, gemini, openrouter, anthropic, openai
    var id: String { rawValue }
    var title: String {
        switch self {
        case .groq: return "Groq"
        case .gemini: return "Google Gemini"
        case .openrouter: return "OpenRouter"
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        }
    }
}

enum InterviewCredentialStore {
    private static let service = "app.rium.notch.interview"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func save(_ key: String, account: String) -> OSStatus {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.utf8.count <= 16_384,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return errSecParam }
        let data = Data(value.utf8)
        let base = query(account)
        let attributes = [kSecValueData as String: data] as CFDictionary
        let updated = SecItemUpdate(base as CFDictionary, attributes)
        guard updated == errSecItemNotFound else { return updated }
        var added = base
        added[kSecValueData as String] = data
        added[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let result = SecItemAdd(added as CFDictionary, nil)
        return result == errSecDuplicateItem ? SecItemUpdate(base as CFDictionary, attributes) : result
    }

    static func remove(account: String) -> OSStatus {
        let result = SecItemDelete(query(account) as CFDictionary)
        return result == errSecItemNotFound ? errSecSuccess : result
    }

    static func read(account: String) -> String? {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, data.count <= 16_384 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
