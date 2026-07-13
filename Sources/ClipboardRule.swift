import Foundation

struct ClipboardRule: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var isBuiltIn: Bool
    var trigger: RuleTrigger
    var actions: [RuleAction]
    var order: Int
    
    init(id: UUID = UUID(), name: String, isEnabled: Bool = true, isBuiltIn: Bool = false, trigger: RuleTrigger = .always, actions: [RuleAction], order: Int = 0) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
        self.trigger = trigger
        self.actions = actions
        self.order = order
    }
}

enum RuleTrigger: Codable, Equatable {
    case always
    case contentMatches(pattern: String)
    case sourceApp(bundleID: String)
    case contentType(ClipboardItem.ItemType)
}

enum RuleAction: Codable, Equatable {
    case stripURLTracking
    case detectSensitive(autoDeleteSeconds: Int?)
    case replaceRegex(pattern: String, replacement: String)
    case trimWhitespace
    case autoPin
    case discard
    case runScript(source: String)
}
