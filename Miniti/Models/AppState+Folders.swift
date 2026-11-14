import Foundation
import SwiftData

extension AppState {
    struct FolderMove {
        let owner: String
        let meeting: Meeting
        let folderID: UUID?
        let manual: Bool?
        let localOnly: Bool?
    }
    struct FolderProposal: Identifiable {
        let owner: String
        var id: UUID { meeting.id }
        let meeting: Meeting
        let title: String
        let previousFolder: UUID?
        let previousManual: Bool?
        let previousLocalOnly: Bool?
        let folder: MeetingFolder
        /// Chosen by the user in Preview. Applies as hand-filed, so its series learns from it.
        var manual = false
    }

    func folderIncludes(_ meeting: Meeting) -> Bool {
        let folder = meetingFolders.folder(meeting.folderID)
        if showUnfiledMeetings || (folderFilterID != nil && meetingFolders.folder(folderFilterID) == nil) { return folder == nil }
        return folderFilterID == nil || folder?.id == folderFilterID
    }

    @discardableResult
    func moveMeeting(_ meeting: Meeting, to folder: MeetingFolder?, manual: Bool = true) -> FolderMove? {
        let old = FolderMove(owner: meetingFolders.owner, meeting: meeting, folderID: meeting.folderID, manual: meeting.folderManual, localOnly: meeting.folderLocalOnly)
        guard commit(.folder, mutate: {
            MeetingSyncDocument.prepareFolderEdit(meeting)
            meeting.folderID = folder?.id; meeting.folderManual = manual; meeting.folderLocalOnly = folder?.localOnly
        }, revert: {
            meeting.folderID = old.folderID; meeting.folderManual = old.manual; meeting.folderLocalOnly = old.localOnly
        }) else { return nil }
        return old
    }

    func undoLastFolderChange() {
        let moves = folderUndo
        folderUndo = []
        undoFolderMoves(moves)
    }

    func undoFolderMoves(_ moves: [FolderMove]) {
        _ = commit(.folder, mutate: {
            for old in moves where old.owner == self.meetingFolders.owner && !self.isMeetingDeleted(old.meeting.id) {
                MeetingSyncDocument.prepareFolderEdit(old.meeting)
                old.meeting.folderID = old.folderID; old.meeting.folderManual = old.manual; old.meeting.folderLocalOnly = old.localOnly
            }
        })
    }

    /// Email domains of a meeting's participants, for local folder evidence only.
    struct FolderParticipants {
        var own: Set<String> = []
        var others: [String] = []
    }

    /// Calendar attendees and speaker emails, split into the user's own addresses and
    /// everyone else's domains. An address is the user's if the calendar marks it as
    /// self, a speaker marked as me carries it, or it is the verified account email;
    /// such an address never also counts as another participant. Nothing here leaves
    /// the device.
    func folderParticipants(of meeting: Meeting, accountEmail: String? = nil) -> FolderParticipants {
        let attendees = meeting.attendees
        let speakers = meeting.speakerEmails
        let selfSpeakers = Set(meeting.selfSpeakerIDs.map(String.init))
        var mine = Set(attendees.filter(\.isSelf).map { $0.email.lowercased() })
        mine.formUnion(speakers.filter { selfSpeakers.contains($0.key) }.map { $0.value.lowercased() })
        if let accountEmail { mine.insert(accountEmail.lowercased()) }
        var result = FolderParticipants()
        var seen = Set<String>()
        for email in attendees.map({ $0.email.lowercased() }) + speakers.values.map({ $0.lowercased() }).sorted() {
            guard let domain = FolderMatcher.domain(ofEmail: email), seen.insert(email).inserted else { continue }
            if mine.contains(email) { result.own.insert(domain) } else { result.others.append(domain) }
        }
        return result
    }

    /// At most 1,000 finished rows, after settlement or an explicit preview. Never audio callbacks.
    /// `preview` is the organise screen: there, summary evidence may propose a new broad
    /// folder when at least two meetings agree. Automatic filing never creates one from summaries.
    func folderProposals(meetings: [Meeting], regroupManual: Bool = false, onlyMeetingID: UUID? = nil,
                         preview: Bool = false) -> [FolderProposal] {
        let candidates = Array(meetings.lazy.filter { $0.endTime != nil }.prefix(1000))
        var folders = meetingFolders.active
        let owner = meetingFolders.owner
        // Broad evidence per meeting, strongest first: a title phrase, then strong summary
        // vocabulary, then who was there.
        var titled: [UUID: FolderMatcher.Category] = [:]
        var participants: [UUID: FolderParticipants] = [:]
        // The user's usual company domain: the verified account email, plus the domain
        // their calendar most often marks as theirs. Counted over every candidate, so a
        // meeting's title never changes how other meetings are read.
        let accountEmail = accountEmailState.email?.verified
        var usualDomains = Set<String>()
        if let accountEmail, let domain = FolderMatcher.domain(ofEmail: accountEmail) { usualDomains.insert(domain) }
        var selfDomainCounts: [String: Int] = [:]
        for meeting in candidates {
            if let category = FolderMatcher.Category.matching(title: meeting.calendarEventTitle ?? meeting.title) {
                titled[meeting.id] = category
            }
            guard meeting.attendeesJSON != nil || meeting.speakerEmailsJSON != nil else { continue }
            let found = folderParticipants(of: meeting, accountEmail: accountEmail)
            for domain in found.own where !FolderMatcher.webmailDomains.contains(domain) { selfDomainCounts[domain, default: 0] += 1 }
            if titled[meeting.id] == nil, !found.others.isEmpty { participants[meeting.id] = found }
        }
        if let usual = selfDomainCounts.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key { usualDomains.insert(usual) }
        // A meeting that names the user's address is read against that address alone, so a
        // client-issued address used once does not turn that client's people into colleagues
        // everywhere else. Other meetings fall back to the usual domain.
        let attended = participants.compactMapValues {
            FolderMatcher.domainCategory(others: $0.others, ownDomains: $0.own.isEmpty ? usualDomains : $0.own)
        }
        // Summaries are tokenised at most once per meeting per pass.
        var summarized: [UUID: FolderMatcher.Category?] = [:]
        func summaryCategory(_ meeting: Meeting) -> FolderMatcher.Category? {
            if let known = summarized[meeting.id] { return known }
            let category = FolderMatcher.Category.matching(summary: meeting.summaryText)
            summarized[meeting.id] = .some(category)
            return category
        }
        /// Who was there, unless the summary clearly says something else.
        func attendedCategory(_ meeting: Meeting) -> FolderMatcher.Category? {
            guard let category = attended[meeting.id] else { return nil }
            let summary = summaryCategory(meeting)
            return summary == nil || summary == category ? category : nil
        }
        if automaticFolderCreation {
            let groups = Dictionary(grouping: candidates.compactMap { meeting -> (FolderMatcher.Category, Meeting)? in
                let category = titled[meeting.id] ?? (preview ? summaryCategory(meeting) : nil) ?? attendedCategory(meeting)
                return category.map { ($0, meeting) }
            }, by: { $0.0 })
            for category in FolderMatcher.Category.allCases {
                guard let group = groups[category], group.count >= 2, folders.count < 200 else { continue }
                // Never replace a rename or resurrect a deleted suggestion. A folder
                // created by the user with the same broad name is used as-is.
                guard !folders.contains(where: {
                    FolderMatcher.Category.identifying($0, owner: owner) == category ||
                    $0.name.caseInsensitiveCompare(category.name) == .orderedSame
                }) else { continue }
                let localOnly = group.contains { $0.1.syncExcluded } || privateModeEnabled
                let folder = category.folder(owner: owner, localOnly: localOnly)
                guard !meetingFolders.scope.folders.contains(where: {
                    $0.id == category.id(owner: owner, localOnly: false) || $0.id == category.id(owner: owner, localOnly: true)
                }) else { continue }
                folders.append(folder)
            }
        }
        // Resolve stable category identities once per batch. Renaming a broad
        // folder does not opt it into incidental summary-keyword matching.
        let categories = Dictionary(uniqueKeysWithValues: folders.compactMap { folder in
            FolderMatcher.Category.identifying(folder, owner: owner).map { (folder.id, $0) }
        })
        let custom = folders.filter {
            guard let category = categories[$0.id] else { return true }
            return !$0.titleRule.isEmpty || $0.description != category.description
        }
        let prepared = FolderMatcher.Prepared(custom)
        let broad = Dictionary(FolderMatcher.Category.allCases.compactMap { category in
            folders.first { categories[$0.id] == category || $0.name.caseInsensitiveCompare(category.name) == .orderedSame }
                .map { (category, $0) }
        }, uniquingKeysWith: { first, _ in first })
        let precedents = seriesPrecedents(in: candidates)
        return candidates.compactMap { meeting in
            guard onlyMeetingID == nil || meeting.id == onlyMeetingID,
                  regroupManual || meeting.folderManual != true,
                  let folder = matchingFolder(for: meeting, custom: custom, prepared: prepared, broad: broad, precedents: precedents,
                                              titled: titled[meeting.id],
                                              summarized: { summaryCategory(meeting) },
                                              attended: { attendedCategory(meeting) }, preview: preview),
                  folder.id != meeting.folderID else { return nil }
            return .init(owner: meetingFolders.owner, meeting: meeting, title: meeting.title, previousFolder: meeting.folderID,
                         previousManual: meeting.folderManual, previousLocalOnly: meeting.folderLocalOnly, folder: folder)
        }
    }

    struct SeriesPrecedent {
        let folder: MeetingFolder
        let manual: Bool
        let meetingID: UUID
    }

    /// The folders recurring series already use, hand-chosen first, then newest. Calendar
    /// series learn from any filed meeting; title series only from hand moves, because
    /// generic titles can collide. Only existing, active folders count.
    private func seriesPrecedents(in candidates: [Meeting]) -> [String: [SeriesPrecedent]] {
        var result: [String: [SeriesPrecedent]] = [:]
        let ordered = candidates.sorted {
            let a = $0.folderManual == true, b = $1.folderManual == true
            return a != b ? a : $0.startTime > $1.startTime
        }
        for meeting in ordered {
            guard let folder = meetingFolders.folder(meeting.folderID) else { continue }
            let manual = meeting.folderManual == true
            for key in FolderMatcher.seriesKeys(calendarEventID: meeting.calendarEventId, title: meeting.calendarEventTitle ?? meeting.title)
                where manual || key.hasPrefix("event:") {
                // Two entries are enough to find one that is not the meeting being filed.
                if result[key, default: []].count < 2 {
                    result[key, default: []].append(.init(folder: folder, manual: manual, meetingID: meeting.id))
                }
            }
        }
        return result
    }

    private func seriesPrecedent(for meeting: Meeting, title: String, in precedents: [String: [SeriesPrecedent]]) -> SeriesPrecedent? {
        let found = FolderMatcher.seriesKeys(calendarEventID: meeting.calendarEventId, title: title)
            .compactMap { key in precedents[key]?.first { $0.meetingID != meeting.id } }
        return found.first { $0.manual } ?? found.first
    }

    private func matchingFolder(for meeting: Meeting, custom: [MeetingFolder], prepared: FolderMatcher.Prepared,
                                broad: [FolderMatcher.Category: MeetingFolder],
                                precedents: [String: [SeriesPrecedent]] = [:],
                                titled: FolderMatcher.Category?,
                                // Read only when nothing stronger matched: tokenising a summary is the costly step.
                                summarized: () -> FolderMatcher.Category?, attended: () -> FolderMatcher.Category?,
                                preview: Bool) -> MeetingFolder? {
        let title = meeting.calendarEventTitle ?? meeting.title
        let precedent = seriesPrecedent(for: meeting, title: title, in: precedents)
        // A hand-chosen folder for the same series is the strongest signal there is.
        // Never used against a meeting that was itself filed by hand (regrouping included).
        if let precedent, precedent.manual, meeting.folderManual != true { return precedent.folder }
        switch prepared.resolve(title: title, summary: meeting.summaryText) {
        case .folder(let id):
            return custom.first { $0.id == id }
        case .ambiguous:
            return nil
        case .none:
            break
        }
        // An automatic series folder files an unfiled meeting and keeps a meeting that
        // already sits there from being moved again on a later pass.
        if let precedent, meetingFolders.folder(meeting.folderID) == nil || meeting.folderID == precedent.folder.id {
            return precedent.folder
        }
        if let titled {
            if let folder = broad[titled] { return folder }
            // 3.9.0 filed investor and board titles under planning. Keep doing so into a
            // planning folder that already exists while there is no Investors folder.
            if titled == .investors, let planning = broad[.planning], meetingFolders.folder(planning.id) != nil { return planning }
            return nil
        }
        // Strong summary evidence files into a broad folder that already exists. Only
        // Preview may also use one proposed in this batch, which Apply then creates.
        // Without such a folder the meeting stays unfiled: `attended` is already nil
        // when the summary disagrees with it.
        if let summarized = summarized(), let folder = broad[summarized], preview || meetingFolders.folder(folder.id) != nil {
            return folder
        }
        // Who was there: colleagues only is Team, an outside company is Customers.
        if let attended = attended(), let folder = broad[attended] { return folder }
        return nil
    }

    /// Finished meetings Preview leaves without a folder: not in a live folder and not
    /// proposed for one. Same 1,000-row bound as the proposals.
    func meetingsLeftUnfiled(in meetings: [Meeting], after proposals: [FolderProposal]) -> [Meeting] {
        let proposed = Set(proposals.map(\.id))
        return meetings.lazy.filter { $0.endTime != nil }.prefix(1000)
            .filter { !proposed.contains($0.id) && self.meetingFolders.folder($0.folderID) == nil }
    }

    /// A folder the user picked for one meeting in Preview. Nothing moves until Apply.
    func manualFolderProposal(for meeting: Meeting, folder: MeetingFolder) -> FolderProposal {
        .init(owner: meetingFolders.owner, meeting: meeting, title: meeting.title, previousFolder: meeting.folderID,
              previousManual: meeting.folderManual, previousLocalOnly: meeting.folderLocalOnly, folder: folder, manual: true)
    }

    /// Apply from Preview: the rules' proposals plus the folders the user picked. A picked
    /// folder that does not exist yet is swapped for a live folder of the same name, so a
    /// folder that arrived by sync or was created meanwhile is not duplicated. Returns
    /// what moved, for Undo, and what was refused (changed since, folder limit, save
    /// failure) so the screen can keep it.
    func applyFolderPreview(_ proposals: [FolderProposal], choices: [FolderProposal]) -> (undo: [FolderMove], rejected: [FolderProposal]) {
        let picked = choices.map { choice -> FolderProposal in
            guard meetingFolders.folder(choice.folder.id) == nil,
                  let live = meetingFolders.active.first(where: { $0.name.caseInsensitiveCompare(choice.folder.name) == .orderedSame })
            else { return choice }
            return .init(owner: choice.owner, meeting: choice.meeting, title: choice.title, previousFolder: choice.previousFolder,
                         previousManual: choice.previousManual, previousLocalOnly: choice.previousLocalOnly, folder: live, manual: true)
        }
        let all = proposals + picked
        let undo = applyFolderProposals(all)
        let moved = Set(undo.map { $0.meeting.id })
        return (undo, all.filter { !moved.contains($0.id) })
    }

    func applyFolderProposals(_ proposals: [FolderProposal]) -> [FolderMove] {
        var accepted: [FolderProposal] = []
        for proposal in proposals.prefix(1000) {
            let meeting = proposal.meeting
            guard proposal.owner == meetingFolders.owner, !isMeetingDeleted(meeting.id), meeting.title == proposal.title,
                  meeting.folderID == proposal.previousFolder, meeting.folderManual == proposal.previousManual,
                  meeting.folderLocalOnly == proposal.previousLocalOnly else { continue }
            if meetingFolders.folder(proposal.folder.id) == nil, !meetingFolders.edit(proposal.folder) { continue }
            accepted.append(proposal)
        }
        guard !accepted.isEmpty else { return [] }
        let undo = accepted.map { FolderMove(owner: meetingFolders.owner, meeting: $0.meeting,
            folderID: $0.previousFolder, manual: $0.previousManual, localOnly: $0.previousLocalOnly) }
        guard commit(.folder, mutate: {
            for proposal in accepted {
                MeetingSyncDocument.prepareFolderEdit(proposal.meeting)
                proposal.meeting.folderID = proposal.folder.id
                proposal.meeting.folderManual = proposal.manual
                proposal.meeting.folderLocalOnly = proposal.folder.localOnly
            }
        }, revert: {
            for old in undo { old.meeting.folderID = old.folderID; old.meeting.folderManual = old.manual; old.meeting.folderLocalOnly = old.localOnly }
        }) else { return [] }
        cloudSync.noteLocalChange()
        return undo
    }

    func automaticallyFileMeeting(_ meeting: Meeting) {
        guard automaticFolderFiling, meeting.folderManual != true, meeting.endTime != nil,
              let modelContext else { return }
        var query = FetchDescriptor<Meeting>(sortBy: [SortDescriptor(\.startTime, order: .reverse)])
        query.fetchLimit = 1000
        guard let recent = try? modelContext.fetch(query) else { return }
        let proposals = folderProposals(meetings: recent, onlyMeetingID: meeting.id)
        _ = applyFolderProposals(proposals)
    }

    func cloudSyncFolders() async {
        guard let api = minitiAPIService, let account = cloudAccountID, cloudPauseReason == nil else { return }
        meetingFolders.selectOwner(account)
        let credential = clientAuthManager.credentialGeneration
        await meetingFolders.sync(allowed: { [weak self] in
            self?.cloudPauseReason == nil && self?.cloudAccountID == account && self?.clientAuthManager.credentialGeneration == credential
        }, read: { try await api.readFolders(accountID: account, credentialGeneration: credential) },
        write: { try await api.writeFolders($0, accountID: account, credentialGeneration: credential) })
    }
}
