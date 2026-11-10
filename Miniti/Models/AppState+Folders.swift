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

    /// At most 1,000 finished rows, after settlement or an explicit preview. Never audio callbacks.
    func folderProposals(meetings: [Meeting], regroupManual: Bool = false, onlyMeetingID: UUID? = nil) -> [FolderProposal] {
        let candidates = Array(meetings.lazy.filter { $0.endTime != nil }.prefix(1000))
        var folders = meetingFolders.active
        let owner = meetingFolders.owner
        if automaticFolderCreation {
            let groups = Dictionary(grouping: candidates.compactMap { meeting -> (FolderMatcher.Category, Meeting)? in
                guard let category = FolderMatcher.Category.matching(title: meeting.calendarEventTitle ?? meeting.title) else { return nil }
                return (category, meeting)
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
                  let folder = matchingFolder(for: meeting, custom: custom, prepared: prepared, broad: broad, precedents: precedents),
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
                                precedents: [String: [SeriesPrecedent]] = [:]) -> MeetingFolder? {
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
        if let category = FolderMatcher.Category.matching(title: title), let folder = broad[category] { return folder }
        // Strong summary evidence may file into a broad folder that already exists, never a new one.
        if let category = FolderMatcher.Category.matching(summary: meeting.summaryText),
           let folder = broad[category], meetingFolders.folder(folder.id) != nil {
            return folder
        }
        return nil
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
                proposal.meeting.folderManual = false
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
