import SwiftUI

struct RulesSettingsView: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @ObservedObject var lang = LanguageManager.shared
    @State private var showAddRule = false
    @State private var testInput = ""
    @State private var testResult: ClipboardRuleEngine.TestResult?
    @State private var ruleError: String?
    
    private var rules: [ClipboardRule] {
        clipboardManager.ruleEngine.rules.sorted { $0.order < $1.order }
    }

    /// Move a user rule one step up (lower order) or down (higher order) in the sorted list.
    /// Built-in rules are pinned at the top and cannot be reordered.
    private func moveRule(_ rule: ClipboardRule, direction: Int) {
        let sorted = rules
        guard let idx = sorted.firstIndex(where: { $0.id == rule.id }) else { return }
        let targetIdx = idx + direction
        guard targetIdx >= 0, targetIdx < sorted.count else { return }
        let neighbor = sorted[targetIdx]
        // Swap order values between the two rules.
        guard let ri = clipboardManager.ruleEngine.rules.firstIndex(where: { $0.id == rule.id }),
              let ni = clipboardManager.ruleEngine.rules.firstIndex(where: { $0.id == neighbor.id })
        else { return }
        let tmp = clipboardManager.ruleEngine.rules[ri].order
        clipboardManager.ruleEngine.rules[ri].order = clipboardManager.ruleEngine.rules[ni].order
        clipboardManager.ruleEngine.rules[ni].order = tmp
        clipboardManager.saveRules()
    }
    
    var body: some View {
        Section {
            HStack(spacing: 8) {
                Button(lang.l("rules.export")) { exportRules() }
                    .font(.system(size: 11))
                Button(lang.l("rules.import")) { importRules() }
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)

            ForEach(rules) { rule in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.isBuiltIn ? lang.l("rule.\(rule.name)") : rule.name)
                            .font(.system(size: 13))
                        Text(triggerDescription(rule.trigger))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if rule.isSensitive {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                    Toggle("", isOn: Binding(
                        get: { rule.isEnabled },
                        set: { newValue in
                            if let idx = clipboardManager.ruleEngine.rules.firstIndex(where: { $0.id == rule.id }) {
                                clipboardManager.ruleEngine.rules[idx].isEnabled = newValue
                                clipboardManager.saveRules()
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()

                    if !rule.isBuiltIn {
                        // Reorder buttons — only shown for user-created rules
                        let sorted = rules
                        let ruleIdx = sorted.firstIndex(where: { $0.id == rule.id }) ?? 0
                        HStack(spacing: 0) {
                            Button {
                                moveRule(rule, direction: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 9, weight: .semibold))
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.plain)
                            .disabled(ruleIdx == 0)
                            .opacity(ruleIdx == 0 ? 0.25 : 0.6)

                            Button {
                                moveRule(rule, direction: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.plain)
                            .disabled(ruleIdx == sorted.count - 1)
                            .opacity(ruleIdx == sorted.count - 1 ? 0.25 : 0.6)
                        }

                        Button(role: .destructive) {
                            clipboardManager.ruleEngine.rules.removeAll { $0.id == rule.id }
                            clipboardManager.saveRules()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.red.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            
            Button {
                showAddRule = true
            } label: {
                Label(lang.l("rules.addRule"), systemImage: "plus.circle")
                    .font(.system(size: 12))
            }
        } header: {
            Text(lang.l("rules.title"))
        }
        .popupWindow(isPresented: $showAddRule) {
            AddRuleSheet(clipboardManager: clipboardManager, isPresented: $showAddRule)
        }

        // Rule Test / Preview — error alert anchored here so it's visible anywhere in this view
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(lang.l("rules.test.title"))
                    .font(.system(size: 12, weight: .medium))
                TextField(lang.l("rules.test.placeholder"), text: $testInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                Button(lang.l("rules.test.run")) {
                    Task {
                        testResult = await clipboardManager.ruleEngine.testProcess(text: testInput)
                    }
                }
                .disabled(testInput.isEmpty)
                .font(.system(size: 12))

                if let result = testResult {
                    Divider().opacity(0.3)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(lang.l("rules.test.outcome"))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(result.outcome)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(result.outcome == "discard" ? .red : (result.outcome == "sensitive" ? .orange : .green))
                        }
                        if !result.matchedRules.isEmpty {
                            Text("\(lang.l("rules.test.matched")): \(result.matchedRules.joined(separator: ", "))")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(lang.l("rules.test.noMatch"))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        if result.outcome != "discard" {
                            Text(result.output)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(4)
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        // Execution Trace
                        if !result.steps.isEmpty {
                            Divider().opacity(0.2)
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(result.steps.enumerated()), id: \.offset) { i, step in
                                        HStack(alignment: .top, spacing: 6) {
                                            Image(systemName: step.isTerminal
                                                    ? "xmark.circle.fill"
                                                    : (step.didChange ? "arrow.right.circle.fill" : "checkmark.circle"))
                                                .font(.system(size: 9))
                                                .foregroundColor(step.isTerminal ? .red : (step.didChange ? .orange : Color.secondary.opacity(0.6)))
                                                .padding(.top, 1)
                                            VStack(alignment: .leading, spacing: 1) {
                                                HStack(spacing: 3) {
                                                    Text(step.ruleName)
                                                        .font(.system(size: 10, weight: .semibold))
                                                        .foregroundStyle(.secondary)
                                                    Text("·")
                                                        .foregroundStyle(.tertiary)
                                                        .font(.system(size: 10))
                                                    Text(step.actionName)
                                                        .font(.system(size: 10, design: .monospaced))
                                                        .foregroundColor(step.isTerminal ? .red : .primary)
                                                }
                                                if step.didChange {
                                                    Text(step.outputText.prefix(120))
                                                        .font(.system(size: 9, design: .monospaced))
                                                        .lineLimit(2)
                                                        .foregroundStyle(.tertiary)
                                                        .padding(.leading, 2)
                                                }
                                            }
                                        }
                                        .padding(.vertical, 3)
                                        if i < result.steps.count - 1 {
                                            Divider().opacity(0.15)
                                        }
                                    }
                                }
                                .padding(.vertical, 2)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "list.bullet.indent")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                    Text(lang.l("rules.test.trace", result.steps.count))
                                        .font(.system(size: DesignSystem.FontSize.footnote, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .background(errorAlert)
    }

    // MARK: - Import / Export

    private func exportRules() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "cliprules")!]
        panel.nameFieldStringValue = "MyRules.cliprules"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let store = JSONClipboardRuleStore(storageDirectory: FileManager.default.temporaryDirectory)
        do {
            let userRules = clipboardManager.ruleEngine.rules.filter { !$0.isBuiltIn }
            try store.exportRules(to: url, rules: userRules)
        } catch {
            ruleError = error.localizedDescription
        }
    }

    private func importRules() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "cliprules")!]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let store = JSONClipboardRuleStore(storageDirectory: FileManager.default.temporaryDirectory)
        do {
            let imported = try store.importRules(from: url)
            let maxOrder = clipboardManager.ruleEngine.rules.map(\.order).max() ?? 0
            for (i, rule) in imported.enumerated() {
                var r = rule
                r = ClipboardRule(id: rule.id, name: rule.name, isEnabled: rule.isEnabled, isBuiltIn: false, trigger: rule.trigger, actions: rule.actions, order: maxOrder + i + 1)
                clipboardManager.ruleEngine.rules.append(r)
            }
            clipboardManager.saveRules()
        } catch {
            ruleError = error.localizedDescription
        }
    }

    private var isSensitive: Bool { false }

    // MARK: - Error Alert

    /// Append a `.alert` modifier to the body to surface import/export errors.
    var errorAlert: some View {
        EmptyView()
            .alert(
                lang.l("rules.error.title"),
                isPresented: Binding(get: { ruleError != nil }, set: { if !$0 { ruleError = nil } })
            ) {
                Button(lang.l("button.cancel"), role: .cancel) { ruleError = nil }
            } message: {
                if let msg = ruleError { Text(msg) }
            }
    }

    private func triggerDescription(_ trigger: RuleTrigger) -> String {
        switch trigger {
        case .always: return lang.l("rules.trigger.always")
        case .contentMatches(let p): return lang.l("rules.trigger.matches", p)
        case .sourceApp(let b): return lang.l("rules.trigger.app", b)
        case .contentType(let t): return lang.l("rules.trigger.type", t.rawValue)
        }
    }
}

// MARK: - Sensitive badge helper
private extension ClipboardRule {
    var isSensitive: Bool {
        actions.contains { if case .detectSensitive = $0 { return true }; return false }
    }
}

// MARK: - Running App entry

struct RunningAppEntry: Identifiable {
    let id: String  // bundleID
    let name: String
    let icon: NSImage?
}

// MARK: - Add Rule Sheet

struct AddRuleSheet: View {
    @ObservedObject var clipboardManager: ClipboardManager
    @Binding var isPresented: Bool
    @ObservedObject var lang = LanguageManager.shared

    @State private var name = ""
    @State private var triggerType = 0 // 0=always, 1=regex, 2=app
    @State private var triggerValue = ""
    @State private var selectedActions: Set<String> = []
    @State private var regexPattern = ""
    @State private var regexReplacement = ""
    @State private var scriptSource = ""
    @State private var showScriptEditor = false
    @State private var showAppPicker = false
    @State private var runningApps: [RunningAppEntry] = []

    private let actionOptions = ["stripURLTracking", "trimWhitespace", "autoPin", "discard"]

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(lang.l("rules.addRule"), onClose: { isPresented = false })

            ScrollView {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    TextField(lang.l("rules.name"), text: $name)
                        .textFieldStyle(.roundedBorder)

                    Picker(lang.l("rules.trigger"), selection: $triggerType) {
                        Text(lang.l("rules.trigger.always")).tag(0)
                        Text(lang.l("rules.trigger.regexLabel")).tag(1)
                        Text(lang.l("rules.trigger.appLabel")).tag(2)
                    }

                    if triggerType == 1 {
                        TextField(lang.l("rules.trigger.regexPlaceholder"), text: $triggerValue)
                            .textFieldStyle(.roundedBorder)
                    }

                    if triggerType == 2 {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            TextField(lang.l("rules.trigger.appPlaceholder"), text: $triggerValue)
                                .textFieldStyle(.roundedBorder)
                            Button(lang.l("rules.trigger.chooseApp")) {
                                runningApps = loadRunningApps()
                                showAppPicker = true
                            }
                            .font(.system(size: DesignSystem.FontSize.caption))
                            .foregroundColor(.accentColor)
                            .buttonStyle(.plain)
                        }
                        .popupWindow(isPresented: $showAppPicker) {
                            AppPickerSheet(apps: runningApps, isPresented: $showAppPicker) { entry in
                                triggerValue = entry.id
                                if name.isEmpty { name = entry.name }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        Text(lang.l("rules.actions"))
                            .font(.subheadline)
                        ForEach(actionOptions, id: \.self) { action in
                            Toggle(lang.l("rules.action.\(action)"), isOn: Binding(
                                get: { selectedActions.contains(action) },
                                set: { if $0 { selectedActions.insert(action) } else { selectedActions.remove(action) } }
                            ))
                            .font(.system(size: DesignSystem.FontSize.secondary))
                        }

                        Toggle(lang.l("rules.action.replaceRegex"), isOn: Binding(
                            get: { !regexPattern.isEmpty },
                            set: { if !$0 { regexPattern = ""; regexReplacement = "" } }
                        ))
                        .font(.system(size: DesignSystem.FontSize.secondary))

                        if !regexPattern.isEmpty || selectedActions.isEmpty {
                            HStack {
                                TextField(lang.l("rules.regex.pattern"), text: $regexPattern)
                                    .textFieldStyle(.roundedBorder)
                                TextField(lang.l("rules.regex.replacement"), text: $regexReplacement)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        Toggle(lang.l("rules.action.customScript"), isOn: $showScriptEditor)
                            .font(.system(size: DesignSystem.FontSize.secondary))

                        if showScriptEditor {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                                TextEditor(text: $scriptSource)
                                    .font(.system(size: DesignSystem.FontSize.caption, design: .monospaced))
                                    .frame(height: 80)
                                    .standardEditorSurface(cornerRadius: DesignSystem.Radius.card)
                                HStack(spacing: DesignSystem.Spacing.md) {
                                    Button(lang.l("rules.script.formatJSON")) {
                                        scriptSource = "function process(content, bundleID) {\n  try { return JSON.stringify(JSON.parse(content), null, 2); }\n  catch(e) { return content; }\n}"
                                    }
                                    .font(.system(size: DesignSystem.FontSize.footnote))
                                    Button(lang.l("rules.script.extractEmails")) {
                                        scriptSource = "function process(content, bundleID) {\n  var emails = content.match(/[\\w.-]+@[\\w.-]+\\.\\w+/g);\n  return emails ? emails.join('\\n') : content;\n}"
                                    }
                                    .font(.system(size: DesignSystem.FontSize.footnote))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
                .padding(DesignSystem.Spacing.xxl)
            }

            SheetFooter {
                Button(lang.l("button.cancel")) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(lang.l("rules.save")) {
                    saveRule()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.isEmpty)
            }
        }
        .standardPopupLayout()
    }
    
    private func saveRule() {
        let trigger: RuleTrigger
        switch triggerType {
        case 1: trigger = .contentMatches(pattern: triggerValue)
        case 2: trigger = .sourceApp(bundleID: triggerValue)
        default: trigger = .always
        }

        var actions: [RuleAction] = []
        for a in selectedActions {
            switch a {
            case "stripURLTracking": actions.append(.stripURLTracking)
            case "trimWhitespace": actions.append(.trimWhitespace)
            case "autoPin": actions.append(.autoPin)
            case "discard": actions.append(.discard)
            default: break
            }
        }
        if !regexPattern.isEmpty {
            actions.append(.replaceRegex(pattern: regexPattern, replacement: regexReplacement))
        }
        if showScriptEditor && !scriptSource.isEmpty {
            actions.append(.runScript(source: scriptSource))
        }
        guard !actions.isEmpty else { return }

        let maxOrder = clipboardManager.ruleEngine.rules.map(\.order).max() ?? 0
        let rule = ClipboardRule(name: name, trigger: trigger, actions: actions, order: maxOrder + 1)
        clipboardManager.ruleEngine.rules.append(rule)
        clipboardManager.saveRules()
    }

    /// Build a deduplicated, sorted list of currently running user-facing apps.
    private func loadRunningApps() -> [RunningAppEntry] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular &&
                app.bundleIdentifier != nil &&
                !(app.localizedName ?? "").isEmpty
            }
            .compactMap { app -> RunningAppEntry? in
                guard let bundleID = app.bundleIdentifier,
                      let name = app.localizedName else { return nil }
                return RunningAppEntry(id: bundleID, name: name, icon: app.icon)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - App Picker Sheet

struct AppPickerSheet: View {
    let apps: [RunningAppEntry]
    @Binding var isPresented: Bool
    let onSelect: (RunningAppEntry) -> Void
    @State private var searchText = ""
    @ObservedObject private var lang = LanguageManager.shared

    private var filtered: [RunningAppEntry] {
        guard !searchText.isEmpty else { return apps }
        let q = searchText.lowercased()
        return apps.filter {
            $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(
                text: $searchText,
                placeholder: lang.l("search.placeholder"),
                size: .compact
            )

            Divider().opacity(0.3)

            List(filtered) { entry in
                Button {
                    onSelect(entry)
                    isPresented = false
                } label: {
                    HStack(spacing: 10) {
                        if let icon = entry.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 22, height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name)
                                .font(.system(size: 13))
                            Text(entry.id)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .standardPopupLayout()
    }
}
