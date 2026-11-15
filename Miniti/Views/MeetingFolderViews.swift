import SwiftUI
import SwiftData

struct MeetingFolderControls: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var managing = false
    let meetings: [Meeting]
    private var selection: Binding<String> {
        Binding(get: { appState.showUnfiledMeetings || (appState.folderFilterID != nil && appState.meetingFolders.folder(appState.folderFilterID) == nil) ? "unfiled" : (appState.folderFilterID?.uuidString ?? "all") }, set: {
            appState.showUnfiledMeetings = $0 == "unfiled"
            appState.folderFilterID = UUID(uuidString: $0)
        })
    }
    private var usesVerticalControls: Bool {
#if os(iOS)
        dynamicTypeSize.isAccessibilitySize
#else
        false
#endif
    }
    private var controlsLayout: AnyLayout {
        usesVerticalControls ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout())
    }
    var body: some View {
        controlsLayout {
            Picker("Folder", selection: selection) {
                Text("All meetings").tag("all")
                Text("Unfiled").tag("unfiled")
                ForEach(appState.meetingFolders.active) { folder in Text(folder.name).tag(folder.id.uuidString) }
            }.labelsHidden().accessibilityLabel("Filter meetings by folder")
                .frame(maxWidth: usesVerticalControls ? .infinity : nil, alignment: .leading)
            Button { managing = true } label: { Label("Folders", systemImage: "folder.badge.gearshape") }
                .labelStyle(.iconOnly).accessibilityLabel("Manage folders")
            if !appState.folderUndo.isEmpty {
                Button("Undo") { appState.undoLastFolderChange() }.accessibilityLabel("Undo folder changes")
            }
        }
        .sheet(isPresented: $managing) {
            MeetingFolderManager(meetings: meetings)
                .environmentObject(appState)
                .dynamicTypeSize(dynamicTypeSize)
        }
    }
}

struct MeetingFolderMoveMenu: View {
    @EnvironmentObject private var appState: AppState
    let meeting: Meeting
    var body: some View {
        Menu("Move to folder") {
            Button("Unfiled") { move(nil) }
            ForEach(appState.meetingFolders.active) { folder in Button(folder.name) { move(folder) } }
        }
    }
    private func move(_ folder: MeetingFolder?) {
        if let undo = appState.moveMeeting(meeting, to: folder) { appState.folderUndo = [undo] }
    }
}

struct MeetingFolderManager: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var meetings: [Meeting]? = nil
    var onConfirmSetup: (() -> Void)? = nil
    /// Opens straight on the organise preview (History's organise prompt).
    var startsInPreview = false
    @State private var didApplyInitialScreen = false

    private enum Screen: Hashable { case preview, create, manage, edit }
    private enum Field: Hashable { case name, detail, rule }
    @State private var path: [Screen] = []
    @FocusState private var focusedField: Field?
    @State private var editing: MeetingFolder?
    @State private var name = ""
    @State private var detail = ""
    @State private var rule = ""
    @State private var localOnly = false
    @State private var deleting: MeetingFolder?
    @State private var proposals: [AppState.FolderProposal] = []
    @State private var previewIssue: String?
    @State private var regroupManual = false
    /// Meetings Preview leaves unfiled, and the folders the user picked for them here.
    @State private var unfiled: [Meeting] = []
    /// Captured when chosen, so Apply refuses a meeting that changed in the meantime.
    @State private var choices: [UUID: AppState.FolderProposal] = [:]
    @State private var unfiledShown = unfiledPageSize
    @State private var applyIssue: String?
    /// Folders named in Preview. They are created with Apply, like proposed broad folders.
    @State private var newFolders: [MeetingFolder] = []
    @State private var namingFolderFor: Meeting?
    @State private var newFolderName = ""
    /// AI suggestions for meetings the rules left unfiled (3.10.0 FO2.4). They join the
    /// proposals and still need Apply. Each meeting is asked about once per Preview.
    @State private var suggested: [AppState.FolderProposal] = []
    @State private var suggestionAsked: Set<UUID> = []
    @State private var suggesting = false
    @State private var suggestionRound = 0
    /// The request in flight. Leaving, clearing or applying Preview cancels it, which stops
    /// before the next batch is sent.
    @State private var suggestionTask: Task<Void, Never>?
    /// Meetings in the request in flight. If it is cancelled they have not been asked about.
    @State private var suggestionInFlight: Set<UUID> = []
    private static let unfiledPageSize = 200

    private struct PreviewGroup: Identifiable {
        let folder: MeetingFolder
        let meetings: [AppState.FolderProposal]
        var id: UUID { folder.id }
    }
    private var previewGroups: [PreviewGroup] {
        Dictionary(grouping: proposals, by: { $0.folder.id }).values.compactMap { rows in
            rows.first.map { PreviewGroup(folder: $0.folder, meetings: rows) }
        }.sorted { $0.folder.name.localizedStandardCompare($1.folder.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch path.last {
                case .preview: preview
                case .create, .edit: editor
                case .manage: folderList
                case nil: overview
                }
            }
            .id(path.last)
            .onAppear {
                guard startsInPreview, !didApplyInitialScreen else { return }
                didApplyInitialScreen = true
                regroupManual = false
                refreshPreview()
                path = [.preview]
            }
            .navigationTitle(screenTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if path.isEmpty {
                        Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                    } else {
                        Button { focusedField = nil; path.removeLast() } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .accessibilityIdentifier("folders.back")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !path.isEmpty { Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 620, minHeight: 560, idealHeight: 680)
        .disclosureGroupStyle(MinitiDisclosureStyle(minimumHeight: MinitiDesignSystem.Control.minimumIconHitSize))
        .background(ColorPalette.Background.primary)
        .presentationBackground(ColorPalette.Background.primary)
        .preferredColorScheme(.dark)
        #endif
        .confirmationDialog("Delete this folder? Meetings will stay in Unfiled.", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete folder", role: .destructive) {
                if var folder = deleting {
                    folder.deleted = true
                    if appState.meetingFolders.edit(folder) {
                        appState.cloudSync.noteLocalChange()
                        resetEditor()
                        if path.last == .edit { path.removeLast() }
                    }
                }
                deleting = nil
            }
        }
        .onChange(of: appState.meetingFolders.owner) { _, _ in
            path = []; clearPreview(); previewIssue = nil; deleting = nil; resetEditor()
        }
    }

    private var screenTitle: String {
        switch path.last {
        case .preview: return "Preview"
        case .create: return "New folder"
        case .edit: return "Edit folder"
        case .manage: return "Your folders"
        case nil: return "Folders"
        }
    }

    private var overview: some View {
        Form {
            Section {
                journey("Organise existing meetings", detail: "Preview folders and meeting counts before anything moves.", icon: "tray.full", id: "folders.preview") {
                    regroupManual = false
                    clearPreview()
                    refreshPreview()
                    path.append(.preview)
                }
                journey("Create a folder", detail: "Give related conversations a place of their own.", icon: "folder.badge.plus", id: "folders.create") {
                    resetEditor(); path.append(.create)
                }
                journey("Manage your folders", detail: "Rename folders or change what belongs in them.", icon: "folder", id: "folders.manage") {
                    path.append(.manage)
                }
            }
            Section {
                Toggle("Automatically organise new meetings", isOn: $appState.automaticFolderFiling)
                Text("New completed meetings are grouped automatically. Existing history changes only after Preview and Apply.")
                    .font(.footnote).foregroundStyle(ColorPalette.Text.secondary)
                DisclosureGroup("More options") {
                    Toggle("Create broad folders automatically", isOn: $appState.automaticFolderCreation)
                    Text("Suggests groups such as Team, Customers and Hiring. Your folders also guide matching. Uncertain matches stay Unfiled.")
                        .font(.footnote).foregroundStyle(ColorPalette.Text.secondary)
                    FolderSuggestionToggle()
                }
            }
            syncIssue
            if !appState.meetingFolders.scope.conflicts.isEmpty {
                Section {
                    Button("Review folder changes from another device") { path.append(.manage) }
                }
            }
            undoAction
            if let onConfirmSetup {
                Section {
                    Button("confirm folder choices") { onConfirmSetup(); dismiss() }
                        .accessibilityIdentifier("setup.folders.confirm")
                    Text("Marks the setup task complete. Your choices already apply; existing meetings stay where they are.")
                        .font(.footnote).foregroundStyle(ColorPalette.Text.secondary)
                }
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .scrollContentBackground(.hidden)
        .background(ColorPalette.Background.primary)
        #endif
    }

    private func journey(_ title: String, detail: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: MinitiDesignSystem.Spacing.control) {
                Image(systemName: icon).frame(width: MinitiDesignSystem.Control.minimumIconHitSize)
                VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.compact) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(ColorPalette.Text.primary)
                    Text(detail).font(.caption).foregroundStyle(ColorPalette.Text.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: MinitiDesignSystem.Spacing.compact)
                Image(systemName: "chevron.right").foregroundStyle(ColorPalette.Text.muted)
            }
            .padding(.vertical, MinitiDesignSystem.Spacing.standard)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private var filedCount: Int { proposals.count + choices.count }
    private var previewSummary: String {
        let stay = unfiled.count - choices.count
        return "\(filedCount) \(filedCount == 1 ? "meeting" : "meetings") will be filed, \(stay) \(stay == 1 ? "stays" : "stay") unfiled"
    }
    /// Folders a still-unfiled meeting can go to: existing ones, broad folders this
    /// Preview proposes, and any named here.
    private var choosableFolders: [MeetingFolder] {
        var seen = Set<UUID>()
        return (appState.meetingFolders.active + previewGroups.map(\.folder) + newFolders)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Unfiled meetings a suggestion could be asked for and has not been yet.
    private var suggestionCandidates: [Meeting] {
        appState.folderSuggestionItems(for: unfiled.filter { !suggestionAsked.contains($0.id) && choices[$0.id] == nil }).map(\.meeting)
    }

    /// Nothing is sent from Preview until this button is pressed, and it says what goes.
    @ViewBuilder private var suggestionRequest: some View {
        let count = suggestionCandidates.count
        if suggesting || count == 0 {
            EmptyView()
        } else if appState.folderSuggestionBlock == .privateMode {
            Text("AI folder suggestions are off while private mode is on. Nothing is sent.")
                .font(.footnote).foregroundStyle(ColorPalette.Text.secondary)
                .accessibilityIdentifier("folders.suggest.caption")
        } else if appState.folderSuggestionBlock == nil {
            Button("Suggest folders with AI") { askForSuggestions() }
                .accessibilityIdentifier("folders.suggest")
            Text(FolderSuggestionToggle.requestCaption(count: count))
                .font(.footnote).foregroundStyle(ColorPalette.Text.secondary)
                .accessibilityIdentifier("folders.suggest.caption")
        }
    }

    private var preview: some View {
        Form {
            Section {
                Text(previewSummary).font(.headline).accessibilityIdentifier("folders.preview.summary")
                Text("Up to 1,000 recent finished meetings. Nothing moves until you apply.")
                    .font(.footnote).foregroundStyle(ColorPalette.Text.secondary)
                if suggesting {
                    HStack(spacing: MinitiDesignSystem.Spacing.standard) {
                        ProgressView().controlSize(.small)
                        Text("Asking AI about meetings the rules could not place.")
                            .font(.footnote).foregroundStyle(ColorPalette.Text.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("folders.suggesting")
                }
                suggestionRequest
                DisclosureGroup("Preview options") {
                    Toggle("Include manually filed meetings", isOn: $regroupManual)
                        .onChange(of: regroupManual) { _, _ in refreshPreview() }
                }
            }
            if let applyIssue {
                Section { Text(applyIssue).foregroundStyle(ColorPalette.Status.warning).accessibilityIdentifier("folders.apply.issue") }
            }
            if let previewIssue {
                Section { Text(previewIssue).foregroundStyle(ColorPalette.Status.warning); Button("Retry preview") { refreshPreview() } }
            } else if proposals.isEmpty && unfiled.isEmpty {
                Section {
                    Text("No changes suggested")
                    Text("Every finished meeting is already in a folder.")
                        .foregroundStyle(ColorPalette.Text.secondary)
                }
            }
            ForEach(previewGroups) { group in
                Section {
                    DisclosureGroup {
                        ForEach(group.meetings) { proposal in proposalRow(proposal) }
                    } label: {
                        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.compact) {
                            Text(group.folder.name).font(.headline)
                            Text("\(group.meetings.count) meetings to file").font(.subheadline)
                                .accessibilityIdentifier("folders.preview.count.\(group.folder.name)")
                            Text(group.folder.description.isEmpty ?
                                 (group.folder.titleRule.isEmpty ? "Matches this folder's name." : "Meeting titles containing \(group.folder.titleRule).") : group.folder.description)
                                .font(.footnote).foregroundStyle(ColorPalette.Text.secondary)
                        }
                    }
                }
            }
            if previewIssue == nil, !unfiled.isEmpty {
                Section {
                    Text("miniti could not tell where these belong. Choose a folder for any of them, or leave them unfiled.")
                        .font(.footnote).foregroundStyle(ColorPalette.Text.secondary)
                    ForEach(unfiled.prefix(unfiledShown)) { meeting in unfiledRow(meeting) }
                    if unfiled.count > unfiledShown {
                        Button("Show \(min(Self.unfiledPageSize, unfiled.count - unfiledShown)) more") { unfiledShown += Self.unfiledPageSize }
                            .accessibilityIdentifier("folders.unfiled.more")
                        Text("Showing the \(unfiledShown) most recent of \(unfiled.count).")
                            .font(.footnote).foregroundStyle(ColorPalette.Text.secondary)
                    }
                } header: {
                    Text("Still unfiled")
                }
            }
        }
        .formStyle(.grouped)
        #if os(macOS)
        .scrollContentBackground(.hidden)
        .background(ColorPalette.Background.primary)
        #endif
        .safeAreaInset(edge: .bottom) {
            actionBar {
                Button("Apply organisation") { applyPreview() }
                .disabled(filedCount == 0 || previewIssue != nil)
                .accessibilityIdentifier("folders.apply")
            }
        }
        // Back, Close and Apply all leave this screen: stop asking for suggestions.
        .onDisappear { stopSuggesting() }
        .alert("New folder", isPresented: Binding(get: { namingFolderFor != nil }, set: { if !$0 { namingFolderFor = nil } })) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) { namingFolderFor = nil }
            Button("Add") { addNewFolderChoice() }
        } message: {
            Text("The folder is created when you apply.")
        }
    }

    private func proposalRow(_ proposal: AppState.FolderProposal) -> some View {
        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.compact) {
            Text(proposal.title).font(.callout)
            if proposal.suggested {
                Text("Suggested by AI").font(.footnote).foregroundStyle(ColorPalette.Text.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func unfiledRow(_ meeting: Meeting) -> some View {
        let dynamic = dynamicTypeSize.isAccessibilitySize
        let layout = dynamic ? AnyLayout(VStackLayout(alignment: .leading, spacing: MinitiDesignSystem.Spacing.compact))
                             : AnyLayout(HStackLayout(spacing: MinitiDesignSystem.Spacing.control))
        return layout {
            VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.hairline) {
                Text(meeting.title).font(.callout)
                Text(meeting.startTime.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(ColorPalette.Text.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            .accessibilityElement(children: .combine)
            if !dynamic { Spacer(minLength: MinitiDesignSystem.Spacing.compact) }
            Menu {
                ForEach(choosableFolders) { folder in
                    Button(folder.name) { choices[meeting.id] = appState.manualFolderProposal(for: meeting, folder: folder) }
                }
                Divider()
                Button("New folder…") { newFolderName = ""; namingFolderFor = meeting }
                if choices[meeting.id] != nil {
                    Button("Leave unfiled") { choices[meeting.id] = nil }
                }
            } label: {
                // One line, shortened if needed: a folder name can be 80 characters.
                Text(choices[meeting.id]?.folder.name ?? "Choose folder").lineLimit(1).truncationMode(.tail)
            }
            .frame(minWidth: MinitiDesignSystem.Control.minimumIconHitSize, alignment: dynamic ? .leading : .trailing)
            .accessibilityLabel("Folder for \(meeting.title), \(meeting.startTime.formatted(date: .abbreviated, time: .shortened))")
            .accessibilityValue(choices[meeting.id]?.folder.name ?? "Unfiled")
            .accessibilityIdentifier("folders.unfiled.\(meeting.title)")
        }
    }

    private func addNewFolderChoice() {
        guard let meeting = namingFolderFor else { return }
        namingFolderFor = nil
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf16.count <= 80 else { return }
        // Reuse a folder with the same name rather than creating a twin.
        if let existing = choosableFolders.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            choices[meeting.id] = appState.manualFolderProposal(for: meeting, folder: existing); return
        }
        let folder = MeetingFolder(id: UUID(), name: name, localOnly: appState.privateModeEnabled || meeting.syncExcluded)
        newFolders.append(folder)
        choices[meeting.id] = appState.manualFolderProposal(for: meeting, folder: folder)
    }

    private func clearPreview() {
        proposals = []; unfiled = []; choices = [:]; newFolders = []; applyIssue = nil; unfiledShown = Self.unfiledPageSize
        suggested = []; suggestionAsked = []; stopSuggesting()
    }

    private func stopSuggesting() {
        suggestionTask?.cancel(); suggestionTask = nil
        suggestionAsked.subtract(suggestionInFlight); suggestionInFlight = []
        suggesting = false; suggestionRound += 1
    }

    /// Ask once about each meeting the rules left unfiled, only when the person presses
    /// "Suggest folders with AI". Opening Preview sends nothing. The answers join the
    /// proposals and wait for Apply. A failed or refused request adds nothing and leaves
    /// the rules' proposals as they are.
    private func askForSuggestions() {
        guard appState.folderSuggestionBlock == nil else { return }
        let targets = unfiled.filter { !suggestionAsked.contains($0.id) && choices[$0.id] == nil }
        guard !appState.folderSuggestionItems(for: targets).isEmpty else { return }
        suggestionAsked.formUnion(targets.map(\.id))
        suggestionRound += 1
        let round = suggestionRound
        suggesting = true
        suggestionInFlight = Set(targets.map(\.id))
        suggestionTask?.cancel()
        suggestionTask = Task {
            let found = await appState.suggestedFolderProposals(for: targets, creatingFolders: true)
            // A cleared or refreshed Preview has moved on; its answers are not for this screen.
            guard round == suggestionRound, !Task.isCancelled else { return }
            suggesting = false
            suggestionTask = nil
            suggestionInFlight = []
            guard !found.isEmpty else { return }
            suggested += found
            refreshPreview()
        }
    }

    private func applyPreview() {
        // Applying ends this round of suggestions, whatever happens next: nothing more is
        // sent for a Preview the person has acted on.
        stopSuggesting()
        let result = appState.applyFolderPreview(proposals, choices: unfiled.compactMap { choices[$0.id] })
        if !result.undo.isEmpty { appState.folderUndo = result.undo }
        guard !result.rejected.isEmpty else { clearPreview(); path.removeLast(); return }
        // Keep what was refused on screen, with the user's own choices intact.
        let refused = Set(result.rejected.map(\.id))
        choices = choices.filter { refused.contains($0.key) }
        refreshPreview()
        let count = result.rejected.count
        applyIssue = result.undo.isEmpty
            ? "Nothing could be filed. Check the folder limit and try again."
            : "\(count) \(count == 1 ? "meeting was" : "meetings were") not filed: they changed, or the folder limit was reached. They are still listed here."
    }

    private var editor: some View {
        Form {
            Section {
                TextField("Name", text: $name).focused($focusedField, equals: .name)
                    .accessibilityIdentifier("folders.name").textFieldStyle(.roundedBorder)
                TextField("What belongs here", text: $detail, axis: .vertical)
                    .focused($focusedField, equals: .detail).lineLimit(2...5).textFieldStyle(.roundedBorder)
                Text("A short description helps miniti file related meetings here automatically.")
                    .font(.footnote).foregroundStyle(ColorPalette.Text.secondary)
            }
            Section {
                DisclosureGroup("More options") {
                    TextField("Calendar or meeting title contains", text: $rule)
                        .focused($focusedField, equals: .rule).textFieldStyle(.roundedBorder)
                    if editing == nil { Toggle("Keep this folder on this device", isOn: $localOnly) }
                    Text("Folders sync only with cloud sync enabled. Device-only folders stay on this device.")
                        .font(.footnote).foregroundStyle(ColorPalette.Text.secondary)
                }
            }
            if let editing {
                Section { Button("Delete folder", role: .destructive) { deleting = editing } }
            }
            syncIssue
        }
        .formStyle(.grouped)
        #if os(macOS)
        .scrollContentBackground(.hidden)
        .background(ColorPalette.Background.primary)
        #endif
        .safeAreaInset(edge: .bottom) {
            actionBar {
                Button(editing == nil ? "Create" : "Save") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("folders.save")
            }
        }
    }

    private var folderList: some View {
        Form {
            Section {
                if appState.meetingFolders.active.isEmpty {
                    Text("No folders yet").foregroundStyle(ColorPalette.Text.secondary)
                    Button("Create a folder") { resetEditor(); path.append(.create) }
                }
                ForEach(appState.meetingFolders.active) { folder in
                    journey(folder.name, detail: (folder.description.isEmpty ? "Choose what belongs here" : folder.description) + (folder.localOnly ? "\nOn this device" : ""),
                            icon: folder.localOnly ? "folder.badge.person.crop" : "folder", id: "folders.edit.\(folder.id)") {
                        editing = folder; name = folder.name; detail = folder.description; rule = folder.titleRule
                        path.append(.edit)
                    }
                }
            }
            if !appState.meetingFolders.scope.conflicts.isEmpty {
                Section("Changes from another device") {
                    Text("These folders were edited in two places. Choose which version to keep.")
                    ForEach(appState.meetingFolders.scope.conflicts) { mine in
                        VStack(alignment: .leading, spacing: MinitiDesignSystem.Spacing.standard) {
                            Text("Your version: \(mine.name)"); Text(mine.description)
                            Button("Keep my version") { appState.meetingFolders.resolveConflict(mine.id, keepMine: true) }
                            Button("Use cloud version") { appState.meetingFolders.resolveConflict(mine.id, keepMine: false) }
                        }
                    }
                }
            }
            syncIssue
            undoAction
        }
        .formStyle(.grouped)
        #if os(macOS)
        .scrollContentBackground(.hidden)
        .background(ColorPalette.Background.primary)
        #endif
    }

    @ViewBuilder private var syncIssue: some View {
        if let issue = appState.meetingFolders.issue {
            Section { Text(issue).foregroundStyle(ColorPalette.Status.warning); Button("Retry sync") { Task { await appState.cloudSyncFolders() } } }
        }
    }
    @ViewBuilder private var undoAction: some View {
        if !appState.folderUndo.isEmpty {
            Section { Button("Undo folder changes") { appState.undoLastFolderChange() } }
        }
    }
    private func actionBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack { Spacer(minLength: 0); content(); Spacer(minLength: 0) }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .padding(MinitiDesignSystem.Spacing.standard)
            .frame(maxWidth: .infinity).background(ColorPalette.Background.primary)
    }
    private func refreshPreview() {
        do {
            let source: [Meeting]
            if let meetings { source = meetings }
            else {
                guard let context = appState.modelContext else {
                    previewIssue = "Meeting history is not ready. Try again in a moment."
                    clearPreview(); return
                }
                var fetch = FetchDescriptor<Meeting>(predicate: #Predicate { $0.endTime != nil }, sortBy: [SortDescriptor(\Meeting.startTime, order: .reverse)])
                fetch.fetchLimit = 1000
                source = try context.fetch(fetch)
            }
            // A folder the user picked here outranks a new suggestion for the same meeting.
            proposals = appState.folderProposals(meetings: source, regroupManual: regroupManual, preview: true)
                .filter { choices[$0.id] == nil }
            unfiled = appState.meetingsLeftUnfiled(in: source, after: proposals)
            // AI suggestions apply only where the rules still have nothing and the user has
            // not picked a folder; a meeting that changed since is dropped by Apply itself.
            let open = Set(unfiled.map(\.id))
            suggested = suggested.filter {
                open.contains($0.id) && choices[$0.id] == nil && appState.folderSuggestionBlock == nil
                    && appState.folderSuggestionStillApplies($0)
            }
            if !suggested.isEmpty {
                proposals += suggested
                let placed = Set(suggested.map(\.id))
                unfiled.removeAll { placed.contains($0.id) }
            }
            // Keep choices for meetings that are still listed, and only the new folders they use.
            let listed = Set(unfiled.map(\.id))
            choices = choices.filter { listed.contains($0.key) }
            newFolders = newFolders.filter { folder in choices.values.contains { $0.folder.id == folder.id } }
            previewIssue = nil; applyIssue = nil
        } catch {
            clearPreview()
            previewIssue = "Could not load meeting history. Try again."
        }
    }
    private func resetEditor() {
        focusedField = nil; editing = nil; name = ""; detail = ""; rule = ""; localOnly = appState.privateModeEnabled
    }
    private func save() {
        let folder = MeetingFolder(id: editing?.id ?? UUID(), name: name, description: detail, titleRule: rule,
                                   localOnly: editing?.localOnly ?? (localOnly || appState.privateModeEnabled))
        if appState.meetingFolders.edit(folder) {
            resetEditor(); appState.cloudSync.noteLocalChange()
            // End on the list so the saved name is visible, without leaving an empty form open.
            path = [.manage]
        }
    }
}

/// "Use AI to file new meetings" (3.10.0 FO2.4), shared by the organise screen and
/// Settings. Off by default. It covers only newly completed meetings; Preview has its own
/// button. While private mode is on it shows as off with the reason, nothing is sent, and
/// the person's own choice comes back when private mode ends.
struct FolderSuggestionToggle: View {
    @EnvironmentObject private var appState: AppState
    var onChange: (Bool) -> Void = { _ in }

    var body: some View {
        let blockedByPrivateMode = appState.privateModeEnabled
        Toggle("Use AI to file new meetings", isOn: Binding(
            get: { appState.folderAISuggestions && !blockedByPrivateMode },
            set: { appState.folderAISuggestions = $0; onChange($0) }
        ))
        .disabled(blockedByPrivateMode)
        .accessibilityIdentifier("folders.aiSuggestions")
        Text(FolderSuggestionToggle.caption(privateMode: blockedByPrivateMode))
            .font(.footnote).foregroundStyle(ColorPalette.Text.secondary)
            .accessibilityIdentifier("folders.aiSuggestions.caption")
    }

    static func caption(privateMode: Bool) -> String {
        privateMode
            ? "Off while private mode is on. Nothing is sent."
            : "When the rules cannot place a new meeting, its title and summary are sent to suggest one of your folders. Never the transcript, and never a meeting kept off the cloud."
    }

    /// Under the Preview button: what pressing it sends.
    static func requestCaption(count: Int) -> String {
        "Sends the title and summary of \(count) unfiled \(count == 1 ? "meeting" : "meetings"). Never transcripts. Nothing moves until you apply."
    }
}
