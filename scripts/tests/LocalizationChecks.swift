import Foundation

func runLocalizationChecks() throws -> Int {
    var count = 0
    func check(_ value: Bool, _ message: String) throws {
        try verificationRequire(value, message); count += 1
    }
    try check(L10n.catalog.count > 150, "Translation catalog must be bundled")
    let pattern = try NSRegularExpression(pattern: #"\{[0-9]+\}"#)
    func tokens(_ s: String) -> [String] {
        pattern.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap {
            Range($0.range, in: s).map { String(s[$0]) }
        }.sorted()
    }
    for (key, translations) in L10n.catalog {
        for language in ["nb", "en", "de", "es"] {
            try check(!(translations[language] ?? "").isEmpty, "Missing \(language): \(key)")
            try check(tokens(key) == tokens(translations[language] ?? ""), "Placeholder mismatch: \(language): \(key)")
        }
    }
    try check(AppLanguage.resolve("de", preferred: ["en-US"]) == .de, "Manual override")
    try check(AppLanguage.resolve("system", preferred: ["es-MX"]) == .es, "Regional language")
    try check(AppLanguage.resolve(nil, preferred: ["nn-NO"]) == .nb, "Norwegian fallback")
    try check(AppLanguage.resolve(nil, preferred: ["fr-FR", "de-DE"]) == .de, "Preferred supported language")
    try check(AppLanguage.resolve(nil, preferred: ["ja-JP"]) == .en, "English fallback")
    try check(L10n.translate("Opptak {0}", arguments: ["{1} 100%"], language: .en) == "Recording {1} 100%", "User text remains literal")
    return count
}
