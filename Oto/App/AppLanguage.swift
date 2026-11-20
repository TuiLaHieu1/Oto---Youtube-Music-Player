import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case vietnamese = "vi"
    case english = "en"

    static let storageKey = "app_language"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Theo ngôn ngữ máy"
        case .vietnamese: "Tiếng Việt"
        case .english: "English"
        }
    }

    var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .vietnamese: Locale(identifier: "vi")
        case .english: Locale(identifier: "en")
        }
    }

    var effectiveCode: String {
        locale.language.languageCode?.identifier == "vi" ? "vi" : "en"
    }

    static var current: AppLanguage {
        let saved = UserDefaults.standard.string(forKey: storageKey) ?? "system"
        return AppLanguage(rawValue: saved) ?? .system
    }
}
