import Foundation
import SwiftUI

class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    
    @AppStorage("appLanguage") var language: String = Locale.current.language.languageCode?.identifier ?? "en" {
        didSet { objectWillChange.send() }
    }
    
    var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: language == "zh" ? "zh-Hans" : "en", ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
    
    func l(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }
    
    func l(_ key: String, _ args: CVarArg...) -> String {
        String(format: l(key), arguments: args)
    }
}

extension String {
    var localized: String { LanguageManager.shared.l(self) }
    func localized(_ args: CVarArg...) -> String { String(format: localized, arguments: args) }
}
