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
            path = []; proposals = []; previewIssue = nil; deleting = nil; resetEditor()
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

    private var preview: some View {
        Form {
            Section {
                Text("\(proposals.count) meetings across \(previewGroups.count) folders").font(.headline)
                Text("Up to 1,000 recent finished meetings. Nothing moves until you apply.")
                    .font(.footnote).foregroundStyle(ColorPalette.Text.secondary)
                DisclosureGroup("Preview options") {
                    Toggle("Include manually filed meetings", isOn: $regroupManual)
                        .onChange(of: regroupManual) { _, _ in refreshPreview() }
                }
            }
            if let previewIssue {
                Section { Text(previewIssue).foregroundStyle(ColorPalette.Status.warning); Button("Retry preview") { refreshPreview() } }
            } else if proposals.isEmpty {
                Section {
                    Text("No changes suggested")
                    Text("Add a folder and describe what belongs there, or enable broad folders in More options.")
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
        }
        .formStyle(.grouped)
        #if os(macOS)
        .scrollContentBackground(.hidden)
        .background(ColorPalette.Background.primary)
        #endif
        .safeAreaInset(edge: .bottom) {
            actionBar {
                Button("Apply organisation") {
                    appState.folderUndo = appState.applyFolderProposals(proposals)
                    proposals = []; path.removeLast()
                }
                .disabled(proposals.isEmpty || previewIssue != nil)
                .accessibilityIdentifier("folders.apply")
            }
        }
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
                    previewIssue = "Meeting history is not ready. Try again in a moment."; proposals = []; return
                }
                var fetch = FetchDescriptor<Meeting>(predicate: #Predicate { $0.endTime != nil }, sortBy: [SortDescriptor(\Meeting.startTime, order: .reverse)])
                fetch.fetchLimit = 1000
                source = try context.fetch(fetch)
            }
            proposals = appState.folderProposals(meetings: source, regroupManual: regroupManual)
            previewIssue = nil
        } catch {
            proposals = []; previewIssue = "Could not load meeting history. Try again."
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
