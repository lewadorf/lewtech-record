import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, nb, en, de, es
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return L10n.tr("Følg Mac-ens språk")
        case .nb: return "Norsk bokmål"
        case .en: return "English"
        case .de: return "Deutsch"
        case .es: return "Español"
        }
    }
    static func resolve(_ selection: String?, preferred: [String]) -> AppLanguage {
        if let selection, let language = AppLanguage(rawValue: selection), language != .system { return language }
        for tag in preferred {
            let base = tag.replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init)?.lowercased() ?? ""
            if ["nb", "nn", "no"].contains(base) { return .nb }
            if let language = AppLanguage(rawValue: base), language != .system { return language }
        }
        return .en
    }
}

@MainActor
final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()
    @Published var selection: AppLanguage {
        didSet { UserDefaults.standard.set(selection.rawValue, forKey: L10n.preferenceKey) }
    }
    init() { selection = AppLanguage(rawValue: UserDefaults.standard.string(forKey: L10n.preferenceKey) ?? "system") ?? .system }
    var locale: Locale { L10n.locale }
}

/// Preserve the literal translation key separately from dynamic values. User
/// names, paths and OS errors are inserted once, never translated or evaluated.
struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    let key: String
    let arguments: [String]
    init(stringLiteral value: String) { key = value; arguments = [] }
    init(stringInterpolation: StringInterpolation) { key = stringInterpolation.key; arguments = stringInterpolation.arguments }
    struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity) }
        mutating func appendLiteral(_ literal: String) { key += literal }
        mutating func appendInterpolation<T>(_ value: T) {
            key += "{\(arguments.count)}"
            arguments.append(String(describing: value))
        }
    }
}

enum L10n {
    static let preferenceKey = "appLanguage"
    static var language: AppLanguage { AppLanguage.resolve(UserDefaults.standard.string(forKey: preferenceKey), preferred: Locale.preferredLanguages) }
    static var locale: Locale { Locale(identifier: language.rawValue) }
    static let catalog: [String: [String: String]] = {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("LewtechRecord_LewtechRecord.bundle/Translations.json"))
            candidates.append(resources.appendingPathComponent("Translations.json"))
        }
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "Translations", withExtension: "json") { candidates.append(url) }
        #else
        if let root = ProcessInfo.processInfo.environment["LEWTECH_LOCALIZATION_DIRECTORY"] {
            candidates.append(URL(fileURLWithPath: root).appendingPathComponent("Translations.json"))
        }
        #endif
        for url in candidates {
            if let data = try? Data(contentsOf: url), let result = try? JSONDecoder().decode([String: [String: String]].self, from: data) { return result }
        }
        return [:]
    }()
    static func tr(_ message: LocalizedMessage) -> String { translate(message.key, arguments: message.arguments, language: language) }
    static func lookup(_ key: String) -> String { translate(key, language: language) }
    static func translate(_ key: String, arguments: [String] = [], language: AppLanguage) -> String {
        let entry = catalog[key]
        var result = entry?[language.rawValue] ?? entry?["en"] ?? key
        let expression = try! NSRegularExpression(pattern: #"\{([0-9]+)\}"#)
        let matches = expression.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let indexRange = Range(match.range(at: 1), in: result), let index = Int(result[indexRange]), arguments.indices.contains(index),
                  let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: arguments[index])
        }
        return result
    }
}
