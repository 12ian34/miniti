import Foundation

/// Links a named speaker to a calendar attendee so exports can carry the email (3.2.0).
/// Deterministic and conservative: a full-name match, else a unique first-name match, else a
/// unique match on the email's local part with separators removed. Anything ambiguous is nil;
/// the person can pick the attendee by hand in the rename sheet.
enum SpeakerAttendeeMatcher {
    static func match(name: String, attendees: [MeetingAttendee]) -> MeetingAttendee? {
        let needle = normalise(name)
        guard !needle.isEmpty, !attendees.isEmpty else { return nil }
        let candidates = attendees.filter { !$0.email.isEmpty }

        // 1. The whole display name.
        let full = candidates.filter { normalise($0.displayName ?? "") == needle }
        if full.count == 1 { return full[0] }
        if full.count > 1 { return nil }

        // 2. First name, when exactly one attendee has it.
        let firstToken = needle.split(separator: " ").first.map(String.init) ?? needle
        let byFirst = candidates.filter { attendee in
            let tokens = normalise(attendee.displayName ?? "").split(separator: " ").map(String.init)
            return tokens.first == firstToken && (needle == firstToken || tokens == needle.split(separator: " ").map(String.init))
        }
        if byFirst.count == 1 { return byFirst[0] }
        if byFirst.count > 1 { return nil }

        // 3. The email's local part: sam.jones, sam_jones, samjones all mean "sam jones".
        let squashed = needle.replacingOccurrences(of: " ", with: "")
        let byLocal = candidates.filter { localPart($0.email) == squashed }
        if byLocal.count == 1 { return byLocal[0] }
        return nil
    }

    /// What to call a speaker who was picked from the attendee list.
    static func displayName(for attendee: MeetingAttendee) -> String {
        if let name = attendee.displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        let local = attendee.email.split(separator: "@").first.map(String.init) ?? attendee.email
        return local.replacingOccurrences(of: ".", with: " ").replacingOccurrences(of: "_", with: " ").capitalized
    }

    static func normalise(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined(separator: " ")
            .split(separator: " ").joined(separator: " ")
    }

    private static func localPart(_ email: String) -> String {
        let local = email.split(separator: "@").first.map(String.init) ?? email
        return normalise(local).replacingOccurrences(of: " ", with: "")
    }
}
