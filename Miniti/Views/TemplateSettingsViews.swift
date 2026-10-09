import SwiftData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings → Templates (roadmap P2.1, 2.9.0)
//
// One shared implementation for both platforms. macOS wraps the sections in its own Form
// (`InsightTemplatesSettingsView`); iOS drops the sections into its settings Form
// (`InsightTemplatesSettingsSections`). The editor is a sheet on both.

struct InsightTemplatesSettingsView: View {
    var body: some View {
        Form {
            InsightTemplatesSettingsSections()
        }
        .formStyle(.grouped)
        #if os(macOS)
        .settingsSearchScrolling(for: .templates)
        #endif
    }
}

struct InsightTemplatesSettingsSections: View {
    @EnvironmentObject private var appState: AppState

    @State private var editing: EditorTarget?
    @State private var pendingDelete: InsightTemplate?
    @State private var exporting: InsightTemplate?
    @State private var isImporting = false
    @State private var message: String?
    @State private var messageIsError = false

    private struct EditorTarget: Identifiable {
        let id: String
        let template: InsightTemplate?
    }

    var body: some View {
        Section("Built-in") {
            Text("Pick one from the More menu during a meeting and miniti fills it in as you go. Duplicate any of these to make it your own.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(InsightTemplate.builtIn) { template in
                templateRow(template)
            }
        }
        .id("templates.list")

        Section("Your templates") {
            if appState.customInsightTemplates.isEmpty {
                Text("None yet. A template is a name and up to \(InsightTemplate.maxSections) sections, each with a title and a line telling the AI what belongs there. Sections only, no free-form prompts, so the notes always come back in the same shape.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(appState.customInsightTemplates) { template in
                templateRow(template)
            }
            HStack {
                Button {
                    editing = EditorTarget(id: "new", template: nil)
                } label: {
                    Label("New template", systemImage: "plus")
                }
                .disabled(!appState.canAddCustomInsightTemplate)

                Button {
                    isImporting = true
                } label: {
                    Label("Import…", systemImage: "square.and.arrow.down")
                }
                .disabled(!appState.canAddCustomInsightTemplate)

                Spacer()
                Text("\(appState.customInsightTemplates.count) of \(InsightTemplate.maxCustomTemplates)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(messageIsError ? ColorPalette.Status.error : ColorPalette.Accent.green)
            }
        }
        .id("templates.custom")
        .sheet(item: $editing) { target in
            InsightTemplateEditorSheet(template: target.template) { saved in
                appState.saveCustomInsightTemplate(saved)
                show("saved \(saved.name)")
            }
            .environmentObject(appState)
        }
        .alert("delete this template?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let template = pendingDelete {
                    appState.deleteCustomInsightTemplate(id: template.id)
                    show("deleted \(template.name)")
                }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("meetings that already used it keep their sections.")
        }
        .fileExporter(
            isPresented: Binding(get: { exporting != nil }, set: { if !$0 { exporting = nil } }),
            document: exporting.map { InsightTemplateDocument(template: $0) },
            contentType: .json,
            defaultFilename: exporting.map { "miniti-template-\(InsightTemplateDocument.filenameSlug($0.name))" } ?? "miniti-template"
        ) { result in
            if case .failure(let error) = result { show("export failed: \(error.localizedDescription)", error: true) }
            exporting = nil
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            importTemplate(result)
        }
    }

    @ViewBuilder
    private func templateRow(_ template: InsightTemplate) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: template.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                if !template.summary.isEmpty {
                    Text(template.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(template.sections.map(\.title).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            Spacer()
            if template.isCustom {
                iconButton("pencil", "Edit \(template.name)") {
                    editing = EditorTarget(id: template.id, template: template)
                }
                iconButton("square.and.arrow.up", "Export \(template.name)") {
                    exporting = template
                }
            }
            iconButton("plus.square.on.square", "Duplicate \(template.name)") {
                let copy = appState.duplicateInsightTemplate(template)
                show("added \(copy.name)")
            }
            .disabled(!appState.canAddCustomInsightTemplate)
            if template.isCustom {
                iconButton("trash", "Delete \(template.name)", destructive: true) {
                    pendingDelete = template
                }
            }
        }
    }

    private func iconButton(_ systemImage: String, _ label: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(role: destructive ? .destructive : nil, action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        #if os(macOS)
        .help(label)
        #endif
    }

    private func importTemplate(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            show("import failed: \(error.localizedDescription)", error: true)
        case .success(let url):
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let template = try CustomInsightTemplates.importTemplate(from: Data(contentsOf: url))
                appState.saveCustomInsightTemplate(template)
                show("imported \(template.name)")
            } catch {
                show(error.localizedDescription, error: true)
            }
        }
    }

    private func show(_ text: String, error: Bool = false) {
        message = text
        messageIsError = error
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if message == text { message = nil }
        }
    }
}

// MARK: - Editor

struct InsightTemplateEditorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let template: InsightTemplate?
    let onSave: (InsightTemplate) -> Void

    @State private var draft: InsightTemplateDraft
    @State private var prompt = ""
    @State private var isDrafting = false
    @State private var draftError: String?
    @State private var previewMeetingID: UUID?
    @State private var previewMeetings: [Meeting] = []
    @State private var previewSections: [(title: String, value: String)] = []
    @State private var previewMessage: String?
    @State private var isPreviewing = false

    init(template: InsightTemplate?, onSave: @escaping (InsightTemplate) -> Void) {
        self.template = template
        self.onSave = onSave
        _draft = State(initialValue: template.map(InsightTemplateDraft.init(template:)) ?? InsightTemplateDraft())
    }

    private var isNew: Bool { template == nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Describe it") {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField(
                            "",
                            text: $prompt,
                            prompt: Text("example: weekly 1:1 with a direct report. wins, blockers, feedback, growth, actions"),
                            axis: .vertical
                        )
                        .labelsHidden()
                        .lineLimit(2...5)
                        .onSubmit { Task { await runDraft() } }
                        HStack(spacing: 10) {
                            Button {
                                Task { await runDraft() }
                            } label: {
                                if isDrafting {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text("drafting…")
                                    }
                                } else {
                                    Label(hasContent ? "Draft again" : "Draft it", systemImage: "sparkles")
                                }
                            }
                            .disabled(isDrafting || prompt.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                            Text("miniti writes the name, summary and sections. Edit anything after.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let draftError {
                            Text(draftError)
                                .font(.caption)
                                .foregroundStyle(ColorPalette.Status.error)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section("Template") {
                    labeledField("Name", text: $draft.name, prompt: "example: Customer QBR", max: InsightTemplate.maxNameLength)
                    labeledField("Summary", text: $draft.summary, prompt: "one line on what it is for", max: InsightTemplate.maxSummaryLength)
                }

                Section("Sections") {
                    Text("Each section has a title and one line telling the AI what belongs in it. Sections are filled only from what was actually said.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(Array($draft.sections.enumerated()), id: \.element.id) { index, $section in
                        sectionEditor($section, index: index)
                    }
                    Button {
                        draft.sections.append(.init())
                    } label: {
                        Label("Add section", systemImage: "plus")
                    }
                    .disabled(draft.sections.count >= InsightTemplate.maxSections)
                }

                if !draft.problems.isEmpty {
                    Section {
                        ForEach(draft.problems, id: \.self) { problem in
                            Label(problem, systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundStyle(ColorPalette.Accent.amber)
                        }
                    }
                }

                Section("Preview") {
                    Text("Run this template against one of your meetings to see what it produces. Nothing is saved to the meeting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Meeting", selection: $previewMeetingID) {
                        Text("Choose a meeting").tag(UUID?.none)
                        ForEach(previewMeetings) { meeting in
                            Text("\(meeting.title) · \(meeting.startTime.formatted(date: .abbreviated, time: .shortened))").tag(UUID?.some(meeting.id))
                        }
                    }
                    Button {
                        Task { await runPreview() }
                    } label: {
                        if isPreviewing {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("previewing…")
                            }
                        } else {
                            Label("Preview", systemImage: "play")
                        }
                    }
                    .disabled(isPreviewing || previewMeetingID == nil || !draft.isValid)
                    if let previewMessage {
                        Text(previewMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(previewSections, id: \.title) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(.caption.weight(.semibold))
                            Text(entry.value)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "New template" : "Edit template")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let built = draft.build(id: template?.id ?? InsightTemplate.newCustomID()) {
                            onSave(built)
                            dismiss()
                        }
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 620, idealWidth: 680, minHeight: 600, idealHeight: 720)
        #endif
        .onAppear(perform: loadPreviewMeetings)
    }

    /// Anything typed or drafted so far, so the draft button can say "again".
    private var hasContent: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
            || draft.sections.contains { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Label above, field below, left-aligned, with the counter only once the text is long.
    private func labeledField(_ label: String, text: Binding<String>, prompt: String, max: Int, vertical: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                counter(text.wrappedValue.count, max)
            }
            if vertical {
                TextField("", text: text, prompt: Text(prompt), axis: .vertical)
                    .labelsHidden()
                    .lineLimit(2...4)
            } else {
                TextField("", text: text, prompt: Text(prompt))
                    .labelsHidden()
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func sectionEditor(_ section: Binding<InsightTemplateDraft.Section>, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Section \(index + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    draft.sections.removeAll { $0.id == section.wrappedValue.id }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Remove section \(index + 1)")
                .disabled(draft.sections.count == 1)
            }
            labeledField("Title", text: section.title, prompt: "example: next steps", max: InsightTemplate.maxTitleLength)
            labeledField("What belongs here", text: section.guidance, prompt: "example: what was agreed to happen next, by whom, and by when", max: InsightTemplate.maxGuidanceLength, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private func runDraft() async {
        let description = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard description.count >= 3, !isDrafting else { return }
        isDrafting = true
        draftError = nil
        defer { isDrafting = false }
        do {
            let drafted = try await appState.draftInsightTemplate(from: description)
            draft = drafted
            previewSections = []
            previewMessage = nil
        } catch {
            draftError = "couldn't draft the template: \(error.localizedDescription.lowercased())"
        }
    }

    /// Shown only once the text is close to or over its limit, so a short entry is not
    /// decorated with numbers.
    @ViewBuilder
    private func counter(_ count: Int, _ max: Int) -> some View {
        if count > max * 3 / 4 {
            Text("\(count)/\(max)")
                .font(.caption2)
                .foregroundStyle(count > max ? AnyShapeStyle(ColorPalette.Status.error) : AnyShapeStyle(.tertiary))
        }
    }

    private func loadPreviewMeetings() {
        guard let meetings = appState.fetchMeetings(.exportAll) else { return }
        previewMeetings = meetings
            .filter { $0.endTime != nil && !$0.segments.isEmpty }
            .sorted { $0.startTime > $1.startTime }
            .prefix(20)
            .map { $0 }
    }

    private func runPreview() async {
        guard let id = previewMeetingID, let meeting = previewMeetings.first(where: { $0.id == id }),
              let built = draft.build(id: template?.id ?? "custom_preview") else { return }
        isPreviewing = true
        previewMessage = nil
        previewSections = []
        defer { isPreviewing = false }
        do {
            let sections = try await appState.previewInsightTemplate(built, using: meeting)
            previewSections = built.orderedSections(from: sections).map { (title: $0.section.title, value: $0.value) }
            if previewSections.isEmpty {
                previewMessage = "nothing in that meeting matched these sections. try a different meeting or looser guidance"
            }
        } catch {
            previewMessage = "preview failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Export document

struct InsightTemplateDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    /// "Customer QBR review" → "customer-qbr-review", for the export file name on both platforms.
    static func filenameSlug(_ name: String) -> String {
        let slug = name.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return slug.isEmpty ? "template" : slug
    }

    let data: Data

    init(template: InsightTemplate) {
        data = template.exportData ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
