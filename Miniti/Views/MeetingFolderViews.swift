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
    @State private var choices: [UUID: MeetingFolder] = [:]
    /// Folders named in Preview. They are created with Apply, like proposed broad folders.
    @State private var newFolders: [MeetingFolder] = []
    @State private var namingFolderFor: Meeting?
    @State private var newFolderName = ""
    private static let unfiledRowLimit = 200

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
            path = []; proposals = []; unfiled = []; choices = [:]; newFolders = []; previewIssue = nil; deleting = nil; resetEditor()
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

    private var preview: some View {
        Form {
            Section {
                Text(previewSummary).font(.headline).accessibilityIdentifier("folders.preview.summary")
                Text("Up to 1,000 recent finished meetings. Nothing moves until you apply.")
                    .font(.footnote).foregroundStyle(ColorPalette.Text.secondary)
                DisclosureGroup("Preview options") {
                    Toggle("Include manually filed meetings", isOn: $regroupManual)
                        .onChange(of: regroupManual) { _, _ in refreshPreview() }
                }
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
                        ForEach(group.meetings) { proposal in Text(proposal.title).font(.callout) }
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
                    ForEach(unfiled.prefix(Self.unfiledRowLimit)) { meeting in unfiledRow(meeting) }
                    if unfiled.count > Self.unfiledRowLimit {
                        Text("Showing the \(Self.unfiledRowLimit) most recent of \(unfiled.count). Apply, then open Preview again for the rest.")
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
                Button("Apply organisation") {
                    let picked = unfiled.compactMap { meeting in
                        choices[meeting.id].map { appState.manualFolderProposal(for: meeting, folder: $0) }
                    }
                    appState.folderUndo = appState.applyFolderProposals(proposals + picked)
                    proposals = []; unfiled = []; choices = [:]; newFolders = []; path.removeLast()
                }
                .disabled(filedCount == 0 || previewIssue != nil)
                .accessibilityIdentifier("folders.apply")
            }
        }
        .alert("New folder", isPresented: Binding(get: { namingFolderFor != nil }, set: { if !$0 { namingFolderFor = nil } })) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) { namingFolderFor = nil }
            Button("Add") { addNewFolderChoice() }
        } message: {
            Text("The folder is created when you apply.")
        }
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
            .accessibilityElement(children: .combine)
            if !dynamic { Spacer(minLength: MinitiDesignSystem.Spacing.compact) }
            Menu {
                ForEach(choosableFolders) { folder in
                    Button(folder.name) { choices[meeting.id] = folder }
                }
                Divider()
                Button("New folder…") { newFolderName = ""; namingFolderFor = meeting }
                if choices[meeting.id] != nil {
                    Button("Leave unfiled") { choices[meeting.id] = nil }
                }
            } label: {
                Text(choices[meeting.id]?.name ?? "Choose folder")
            }
            .fixedSize()
            .accessibilityLabel("Folder for \(meeting.title)")
            .accessibilityValue(choices[meeting.id]?.name ?? "Unfiled")
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
            choices[meeting.id] = existing; return
        }
        let folder = MeetingFolder(id: UUID(), name: name, localOnly: appState.privateModeEnabled || meeting.syncExcluded)
        newFolders.append(folder)
        choices[meeting.id] = folder
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
                    proposals = []; unfiled = []; choices = [:]; newFolders = []; return
                }
                var fetch = FetchDescriptor<Meeting>(predicate: #Predicate { $0.endTime != nil }, sortBy: [SortDescriptor(\Meeting.startTime, order: .reverse)])
                fetch.fetchLimit = 1000
                source = try context.fetch(fetch)
            }
            proposals = appState.folderProposals(meetings: source, regroupManual: regroupManual, preview: true)
            unfiled = appState.meetingsLeftUnfiled(in: source, after: proposals)
            // Keep choices for meetings that are still listed, and only the new folders they use.
            let listed = Set(unfiled.map(\.id))
            choices = choices.filter { listed.contains($0.key) }
            newFolders = newFolders.filter { folder in choices.values.contains { $0.id == folder.id } }
            previewIssue = nil
        } catch {
            proposals = []; unfiled = []; choices = [:]; newFolders = []
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
