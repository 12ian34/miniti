import Foundation

// MARK: - Custom insight templates (roadmap P2.1, 2.9.0)
//
// A person's own templates. They use the same `InsightTemplate` shape as the built-in pack,
// so the request path, the specialist view, exports, webhooks, and CRM notes need no new
// code paths. Storage is UserDefaults JSON like the personal dictionary; nothing here touches
// the meeting store. Limits mirror `InsightTemplate` and the backend's validator.

extension InsightTemplate {
    static let customIDPrefix = "custom_"
    static let customSystemImage = "doc.text"
    static let maxCustomTemplates = 24
    static let maxSummaryLength = 120
    static let maxShortNameLength = 16

    var isBuiltIn: Bool { InsightTemplate.builtIn(id: id) != nil }
    var isCustom: Bool { id.hasPrefix(Self.customIDPrefix) }

    static func newCustomID() -> String {
        customIDPrefix + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
    }

    /// "Customer QBR review" → "Customer QBR". Two words or 16 characters, whichever is shorter.
    static func derivedShortName(from name: String) -> String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var short = words.prefix(2).joined(separator: " ")
        if short.isEmpty { short = name.trimmingCharacters(in: .whitespacesAndNewlines) }
        if short.count > maxShortNameLength {
            short = String(short.prefix(maxShortNameLength)).trimmingCharacters(in: .whitespaces)
        }
        return short.isEmpty ? "Template" : short
    }

    /// The JSON people move between devices. Ids are regenerated on import.
    var exportData: Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(self)
    }
}

// MARK: - Draft (what the editor edits)

struct InsightTemplateDraft: Equatable {
    struct Section: Identifiable, Equatable {
        let id: UUID
        var title: String
        var guidance: String

        init(id: UUID = UUID(), title: String = "", guidance: String = "") {
            self.id = id
            self.title = title
            self.guidance = guidance
        }
    }

    var name: String
    var summary: String
    var sections: [Section]

    init(name: String = "", summary: String = "", sections: [Section] = [Section()]) {
        self.name = name
        self.summary = summary
        self.sections = sections
    }

    init(template: InsightTemplate) {
        name = template.name
        summary = template.summary
        sections = template.sections.map { Section(title: $0.title, guidance: $0.guidance) }
    }

    /// Everything wrong with the draft, in the order the editor shows fields. Empty means valid.
    var problems: [String] {
        var problems: [String] = []
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty {
            problems.append("give the template a name")
        } else if trimmedName.count > InsightTemplate.maxNameLength {
            problems.append("the name is over \(InsightTemplate.maxNameLength) characters")
        }
        if summary.trimmingCharacters(in: .whitespacesAndNewlines).count > InsightTemplate.maxSummaryLength {
            problems.append("the summary is over \(InsightTemplate.maxSummaryLength) characters")
        }
        let titled = sections.filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if titled.isEmpty {
            problems.append("add at least one section with a title")
        }
        if sections.count > InsightTemplate.maxSections {
            problems.append("at most \(InsightTemplate.maxSections) sections")
        }
        for (index, section) in sections.enumerated() {
            let title = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.count > InsightTemplate.maxTitleLength {
                problems.append("section \(index + 1) title is over \(InsightTemplate.maxTitleLength) characters")
            }
            if section.guidance.trimmingCharacters(in: .whitespacesAndNewlines).count > InsightTemplate.maxGuidanceLength {
                problems.append("section \(index + 1) guidance is over \(InsightTemplate.maxGuidanceLength) characters")
            }
        }
        let keys = titled.map { CustomInsightTemplates.baseSectionKey(for: $0.title) }
        if Set(keys).count != keys.count {
            problems.append("two sections have the same title")
        }
        return problems
    }

    var isValid: Bool { problems.isEmpty }

    /// Build the template. Untitled sections are dropped; keys derive from titles.
    func build(id: String) -> InsightTemplate? {
        guard isValid else { return nil }
        let titled = sections
            .map { Section(id: $0.id, title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines), guidance: $0.guidance.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.title.isEmpty }
        let keys = CustomInsightTemplates.sectionKeys(for: titled.map(\.title))
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return InsightTemplate(
            id: id,
            name: trimmedName,
            shortName: InsightTemplate.derivedShortName(from: trimmedName),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            systemImage: InsightTemplate.customSystemImage,
            sections: zip(keys, titled).map { key, section in
                InsightTemplateSection(key: key, title: section.title, guidance: section.guidance)
            }
        )
    }
}

// MARK: - Store, keys, import/export

enum CustomInsightTemplates {
    static let storageKey = "customInsightTemplates.v1"

    enum ImportError: LocalizedError {
        case notATemplate
        case invalid([String])

        var errorDescription: String? {
            switch self {
            case .notATemplate:
                return "that file is not a miniti template"
            case .invalid(let problems):
                return "that template can't be used: " + problems.joined(separator: ", ")
            }
        }
    }

    static func load(defaults: UserDefaults = .standard) -> [InsightTemplate] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([InsightTemplate].self, from: data) else {
            return []
        }
        return decoded.filter { $0.isCustom && !$0.sections.isEmpty }
    }

    static func save(_ templates: [InsightTemplate], defaults: UserDefaults = .standard) {
        let custom = templates.filter(\.isCustom)
        guard !custom.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(custom) else { return }
        defaults.set(data, forKey: storageKey)
    }

    /// The key a title maps to before uniqueness: ASCII-folded lowercase, anything else
    /// collapsed to `_`, leading letter, at most 32 characters ("Next steps" → `next_steps`,
    /// "Ünïcode títle" → `unicode_title`). Two titles with the same base key are duplicates.
    static func baseSectionKey(for title: String) -> String {
        var base = title
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .map { ($0.isASCII && ($0.isLetter || $0.isNumber)) ? String($0) : "_" }
            .joined()
            .replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        if base.isEmpty || !(base.first?.isLetter ?? false) { base = "section_" + base }
        return String(base.prefix(InsightTemplate.maxKeyLength)).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    /// Stable, unique keys from titles; a numeric suffix resolves collisions that validation
    /// did not already reject.
    static func sectionKeys(for titles: [String]) -> [String] {
        var used = Set<String>()
        return titles.map { title in
            let base = baseSectionKey(for: title)
            var key = base
            var suffix = 2
            while used.contains(key) {
                let stem = String(base.prefix(InsightTemplate.maxKeyLength - 3))
                key = "\(stem)_\(suffix)"
                suffix += 1
            }
            used.insert(key)
            return key
        }
    }

    /// Decode an exported template and give it a fresh custom id. Built-in ids never come back
    /// as built-ins; an imported copy of BANT is just another custom template.
    static func importTemplate(from data: Data) throws -> InsightTemplate {
        guard let decoded = try? JSONDecoder().decode(InsightTemplate.self, from: data) else {
            throw ImportError.notATemplate
        }
        let draft = InsightTemplateDraft(template: decoded)
        guard let template = draft.build(id: InsightTemplate.newCustomID()) else {
            throw ImportError.invalid(draft.problems)
        }
        return template
    }

    /// "Copy of BANT qualification", as a fresh custom template.
    static func duplicate(_ template: InsightTemplate) -> InsightTemplate {
        var draft = InsightTemplateDraft(template: template)
        let prefix = "Copy of "
        let maxBase = InsightTemplate.maxNameLength - prefix.count
        draft.name = prefix + String(template.name.prefix(maxBase))
        return draft.build(id: InsightTemplate.newCustomID())
            ?? InsightTemplate(id: InsightTemplate.newCustomID(), name: draft.name, shortName: InsightTemplate.derivedShortName(from: draft.name), summary: template.summary, systemImage: InsightTemplate.customSystemImage, sections: template.sections)
    }
}
