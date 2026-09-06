import Foundation
import SwiftUI

// MARK: - Insight templates
//
// A template is a small, fixed set of named sections that the Templates specialist
// view fills from the transcript (BANT, an interview scorecard, a stand-up, ...).
// The definition travels with every request, so the backend needs no catalog and a
// future user-defined editor only has to produce the same shape. Limits here mirror
// the backend's `validateTemplateDefinition`; keep them in sync.

struct InsightTemplateSection: Codable, Hashable, Identifiable, Sendable {
    let key: String
    let title: String
    let guidance: String

    var id: String { key }
}

struct InsightTemplate: Codable, Hashable, Identifiable, Sendable {
    let id: String
    /// Full name shown in menus and section headers ("Interview scorecard").
    let name: String
    /// Compact name for the tab strip ("Interview"). Kept short so the More label stays one word.
    let shortName: String
    /// One line explaining what the template is for; shown in the specialist menu.
    let summary: String
    let systemImage: String
    let sections: [InsightTemplateSection]

    static let maxSections = 8
    static let maxKeyLength = 32
    static let maxTitleLength = 60
    static let maxGuidanceLength = 300
    static let maxNameLength = 60

    /// The wire shape for `POST /api/insights` (`template`).
    var requestDictionary: [String: Any] {
        [
            "id": id,
            "name": name,
            "sections": sections.map { ["key": $0.key, "title": $0.title, "guidance": $0.guidance] },
        ]
    }

    /// Section order, for rendering and exports.
    func orderedSections(from values: [String: String]) -> [(section: InsightTemplateSection, value: String)] {
        sections.compactMap { section in
            guard let value = values[section.key], InsightTemplateSections.hasValue(value) else { return nil }
            return (section, value)
        }
    }

    // MARK: Built-in catalog

    static let defaultID = "bant"

    static func builtIn(id: String?) -> InsightTemplate? {
        guard let id else { return nil }
        return builtIn.first { $0.id == id }
    }

    static let builtIn: [InsightTemplate] = [
        InsightTemplate(
            id: "bant",
            name: "BANT qualification",
            shortName: "BANT",
            summary: "Budget, authority, need, and timeline",
            systemImage: "checklist",
            sections: [
                .init(key: "budget", title: "budget", guidance: "Money that has been mentioned, approved, or is missing: amounts, ranges, who controls it, and whether it exists yet."),
                .init(key: "authority", title: "authority", guidance: "Who decides, who signs, and who else must approve. Include names and roles when stated."),
                .init(key: "need", title: "need", guidance: "The problem in the customer's words, its impact, and what happens if nothing changes."),
                .init(key: "timeline", title: "timeline", guidance: "Dates, deadlines, and events driving the decision, plus anything that could slip it."),
                .init(key: "next_steps", title: "next steps", guidance: "What was agreed to happen next, by whom, and by when."),
            ]
        ),
        InsightTemplate(
            id: "spin",
            name: "SPIN discovery",
            shortName: "SPIN",
            summary: "Situation, problem, implication, need-payoff",
            systemImage: "arrow.triangle.branch",
            sections: [
                .init(key: "situation", title: "situation", guidance: "Facts about how things work today: team, tools, process, volumes."),
                .init(key: "problem", title: "problem", guidance: "Difficulties and dissatisfactions the customer stated with the current situation."),
                .init(key: "implication", title: "implication", guidance: "Consequences of those problems that were discussed: cost, time, risk, morale."),
                .init(key: "need_payoff", title: "need-payoff", guidance: "Value the customer said a solution would bring, in their own words."),
                .init(key: "next_steps", title: "next steps", guidance: "Agreed follow-ups with owners and dates."),
            ]
        ),
        InsightTemplate(
            id: "interview",
            name: "Interview scorecard",
            shortName: "Interview",
            summary: "Evidence-based notes for a hiring interview",
            systemImage: "person.text.rectangle",
            sections: [
                .init(key: "strengths", title: "strengths", guidance: "Skills and qualities the candidate demonstrated, each tied to something they actually said or described."),
                .init(key: "concerns", title: "concerns", guidance: "Gaps, risks, or unclear areas that came up. State the evidence, not a verdict."),
                .init(key: "examples", title: "examples", guidance: "Concrete stories, projects, or results the candidate cited, with outcomes where given."),
                .init(key: "open_questions", title: "open questions", guidance: "Things still unknown that a later interview should probe."),
                .init(key: "candidate_questions", title: "candidate questions", guidance: "What the candidate asked about the role, team, or company."),
                .init(key: "next_steps", title: "next steps", guidance: "Process commitments made to the candidate and internal follow-ups."),
            ]
        ),
        InsightTemplate(
            id: "customer_check_in",
            name: "Customer check-in",
            shortName: "Check-in",
            summary: "Health, wins, risks, and asks from an account call",
            systemImage: "heart.text.square",
            sections: [
                .init(key: "health", title: "health", guidance: "Signals about adoption, satisfaction, and sentiment that were expressed, positive or negative."),
                .init(key: "wins", title: "wins", guidance: "Outcomes and successes the customer reported."),
                .init(key: "risks", title: "risks", guidance: "Churn or expansion risks: blockers, frustrations, competitor mentions, budget or champion changes."),
                .init(key: "requests", title: "requests", guidance: "Feature requests, support asks, and questions the customer raised."),
                .init(key: "commitments", title: "commitments", guidance: "What each side promised to do."),
                .init(key: "next_steps", title: "next steps", guidance: "Agreed follow-ups with owners and dates."),
            ]
        ),
        InsightTemplate(
            id: "standup",
            name: "Stand-up",
            shortName: "Stand-up",
            summary: "Done, next, blockers, and decisions",
            systemImage: "sun.max",
            sections: [
                .init(key: "done", title: "done", guidance: "Work completed since the last stand-up, attributed to the person who reported it."),
                .init(key: "next", title: "next", guidance: "What each person plans to do next."),
                .init(key: "blockers", title: "blockers", guidance: "Anything stopping progress and who is needed to unblock it."),
                .init(key: "decisions", title: "decisions", guidance: "Decisions made during the stand-up."),
                .init(key: "follow_ups", title: "follow-ups", guidance: "Conversations to take offline, with the people involved."),
            ]
        ),
        InsightTemplate(
            id: "one_on_one",
            name: "1:1",
            shortName: "1:1",
            summary: "Updates, wins, challenges, feedback, and growth",
            systemImage: "person.2",
            sections: [
                .init(key: "updates", title: "updates", guidance: "Status on ongoing work and priorities discussed."),
                .init(key: "wins", title: "wins", guidance: "Things that went well and were called out."),
                .init(key: "challenges", title: "challenges", guidance: "Difficulties, frustrations, or risks raised by either person."),
                .init(key: "feedback", title: "feedback", guidance: "Feedback given in either direction, as stated."),
                .init(key: "growth", title: "growth", guidance: "Career, learning, and development topics."),
                .init(key: "actions", title: "actions", guidance: "Commitments made, with owners and dates."),
            ]
        ),
    ]
}

// MARK: - Section values

enum InsightTemplateSections {
    /// A section counts as filled when it holds real text rather than a null-ish placeholder.
    static func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !trimmed.isEmpty && trimmed != "null" && trimmed != "n/a" && trimmed != "none"
    }

    /// Keeps only the template's own keys, strips bullet prefixes, and drops empty values.
    static func normalize(_ raw: [String: String?], for template: InsightTemplate) -> [String: String] {
        var result: [String: String] = [:]
        for section in template.sections {
            guard let value = raw[section.key] ?? nil else { continue }
            let cleaned = value
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { line -> String in
                    var text = line.trimmingCharacters(in: .whitespaces)
                    for prefix in ["- ", "• ", "– ", "* "] where text.hasPrefix(prefix) {
                        text = String(text.dropFirst(prefix.count))
                    }
                    return text
                }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            guard hasValue(cleaned) else { continue }
            result[section.key] = cleaned
        }
        return result
    }

    static func encode(_ sections: [String: String]) -> String? {
        guard !sections.isEmpty,
              let data = try? JSONEncoder().encode(sections),
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    static func decode(_ json: String?) -> [String: String] {
        guard let json, let data = json.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    /// Markdown block shared by every export surface (live, saved, share sheets, auto-export).
    static func markdown(template: InsightTemplate, sections: [String: String], headingLevel: Int = 3) -> String {
        let entries = template.orderedSections(from: sections)
        guard !entries.isEmpty else { return "" }
        let heading = String(repeating: "#", count: headingLevel)
        var md = "\(heading) \(template.name)\n\n"
        for (section, value) in entries {
            md += "**\(section.title.capitalized):** \(value)\n\n"
        }
        return md
    }
}

// MARK: - Prompt (BYOK)
//
// Mirrors the backend's `buildTemplatePrompt` so managed and BYOK meetings produce the
// same shape. Change both together.

enum InsightTemplatePrompt {
    static let systemPrompt =
        "You are a strict structured note-taker. You fill a fixed set of named sections from a meeting transcript using only what was actually said. Do not infer missing facts. If a section has no explicit evidence, return null."

    static func userPrompt(
        template: InsightTemplate,
        previousSections: [String: String]?,
        languageInstruction: String,
        transcript: String
    ) -> String {
        let sectionLines = template.sections
            .map { "- \($0.key) — \($0.title)\($0.guidance.isEmpty ? "" : ": \($0.guidance)")" }
            .joined(separator: "\n")
        let schemaLines = template.sections
            .map { "        \"\($0.key)\": \"Point one\\nPoint two (or null)\"" }
            .joined(separator: ",\n")
        let baseline: String
        if let previousSections, !previousSections.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: previousSections, options: [.prettyPrinted, .sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            baseline = "Previous sections (baseline from earlier in this meeting; keep wording stable, update only when new transcript evidence supports it, remove a point only when it was contradicted or resolved):\n\(json)"
        } else {
            baseline = "This is the start of the meeting. Fill every section the transcript supports."
        }

        return """
        \(languageInstruction)Task: fill the "\(template.name)" template from the transcript.

        \(baseline)

        Sections to fill (key — title: what belongs here):
        \(sectionLines)

        Hard rules:
        - Return ONLY one valid JSON object. No markdown, no prose, no code fences, no comments.
        - Use exactly the section keys listed above under "sections". Do not add keys. Do not rename keys.
        - For each section: either return null OR a newline-separated string of points. Do NOT prefix lines with "- " or "• " or any bullet character - the UI adds bullets automatically.
        - Null policy: if evidence is missing, ambiguous, or implied-but-not-stated, return null.
        - Dedupe policy: merge semantically identical points; do not repeat the same fact across lines or across sections.
        - Normalization policy: normalize wording, tense, and entity names; keep canonical phrasing stable across updates.
        - Contradictions: if newer transcript evidence conflicts with older evidence, keep the newer fact only.
        - Attribute statements to the person who made them when the transcript makes that clear.
        - Keep content concise: max 4 points per section; each point <= 160 chars.

        Respond in JSON:
        {
            "sections": {
        \(schemaLines)
            }
        }

        Latest transcript:
        \(transcript)
        """
    }
}
