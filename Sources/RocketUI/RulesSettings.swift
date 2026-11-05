import RocketCore
import RocketDesign
import SwiftUI

/// Rule list: first enabled match wins, drag to change order (FR-ORG-02).
struct RulesSettings: View {
    @Bindable var model: DownloadsModel
    @State private var editing: DownloadRule?
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s3) {
            Text("Rules decide where new downloads go and how they run. The first matching rule wins; options you pick when adding a download always win.")
                .font(.rocketCaption)
                .foregroundStyle(RocketColor.textSecondary)
            List(selection: $selection) {
                ForEach(model.rules) { rule in
                    HStack {
                        Toggle("", isOn: Binding(get: { rule.enabled }, set: { enabled in
                            var updated = rule
                            updated.enabled = enabled
                            Task { await model.saveRule(updated) }
                        }))
                        .labelsHidden()
                        VStack(alignment: .leading, spacing: RocketSpace.s1) {
                            Text(rule.name.isEmpty ? String(localized: "Untitled rule") : rule.name).font(.rocketHeadline)
                            Text(RuleText.summary(rule, queues: model.queues))
                                .font(.rocketLabel)
                                .foregroundStyle(RocketColor.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .tag(rule.id)
                    .contextMenu {
                        Button("Edit…") { editing = rule }
                        Button("Delete") { Task { await model.deleteRule(rule.id) } }
                    }
                }
                .onMove { source, destination in Task { await model.moveRules(from: source, to: destination) } }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .frame(minHeight: 200)
            .overlay {
                if model.rules.isEmpty {
                    Text("No rules yet").font(.rocketBody).foregroundStyle(RocketColor.textSecondary)
                }
            }
            HStack(spacing: RocketSpace.s2) {
                Button("Add Rule", systemImage: "plus") { editing = DownloadRule(name: "") }
                Button("Remove", systemImage: "minus") {
                    if let selection { Task { await model.deleteRule(selection) } }
                }
                .disabled(selection == nil)
                Spacer()
                Button("Edit…") { editing = model.rules.first { $0.id == selection } }
                    .disabled(selection == nil)
            }
            .labelStyle(.iconOnly)
        }
        .padding(RocketSpace.s6)
        .frame(width: 520)
        .sheet(item: $editing) { rule in
            RuleEditor(rule: rule, queues: model.queues) { saved in Task { await model.saveRule(saved) } }
        }
    }
}

struct RuleEditor: View {
    @State private var rule: DownloadRule
    let queues: [DownloadQueue]
    let onSave: (DownloadRule) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choosingFolder = false

    init(rule: DownloadRule, queues: [DownloadQueue], onSave: @escaping (DownloadRule) -> Void) {
        _rule = State(initialValue: rule)
        self.queues = queues
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField("Name", text: $rule.name, prompt: Text("Linux ISOs"))
                Section("When") {
                    TextField("Sites", text: list(\.match.domains), prompt: Text("releases.ubuntu.com, github.com"))
                    TextField("File types", text: list(\.match.extensions), prompt: Text("iso, dmg, zip"))
                    TextField("At least (MB)", text: megabytes(\.match.minBytes), prompt: Text("any size"))
                    TextField("At most (MB)", text: megabytes(\.match.maxBytes), prompt: Text("any size"))
                }
                Section("Then") {
                    LabeledContent("Save to") {
                        HStack {
                            Button(rule.action.folderPath.map { URL(filePath: $0).lastPathComponent } ?? String(localized: "Default folder")) {
                                choosingFolder = true
                            }
                            if rule.action.folderPath != nil {
                                Button("Clear", systemImage: "xmark.circle.fill") { rule.action.folderPath = nil }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                    Picker("Queue", selection: $rule.action.queueID) {
                        Text("Default").tag(String?.none)
                        ForEach(queues.filter { !$0.isDefault }) { Text($0.name).tag(String?.some($0.id)) }
                    }
                    Picker("Connections", selection: $rule.action.connections) {
                        Text("Default").tag(Int?.none)
                        ForEach([1, 2, 4, 8, 12, 16], id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                    }
                    Picker("Speed limit", selection: $rule.action.speedLimit) {
                        Text("None").tag(Int64?.none)
                        ForEach(ByteRate.presets, id: \.self) { Text(Format.speed(Double($0))).tag(Int64?.some($0)) }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(RocketSpace.s6)
        }
        .frame(width: 460)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { rule.action.folderPath = url.path }
        }
    }

    /// Comma-separated text ↔ list.
    private func list(_ keyPath: WritableKeyPath<DownloadRule, [String]>) -> Binding<String> {
        Binding {
            rule[keyPath: keyPath].joined(separator: ", ")
        } set: {
            rule[keyPath: keyPath] = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
    }

    /// Megabytes text ↔ optional byte count.
    private func megabytes(_ keyPath: WritableKeyPath<DownloadRule, Int64?>) -> Binding<String> {
        Binding {
            rule[keyPath: keyPath].map { ($0 / 1_000_000).formatted(.number.grouping(.never)) } ?? ""
        } set: {
            rule[keyPath: keyPath] = Double($0.trimmingCharacters(in: .whitespaces)).map { Int64($0 * 1_000_000) }
        }
    }
}

enum RuleText {
    /// "github.com · iso, dmg · over 100 MB → Linux folder, Night queue, 2 MB/s"
    static func summary(_ rule: DownloadRule, queues: [DownloadQueue]) -> String {
        var when: [String] = []
        if !rule.match.domains.isEmpty { when.append(rule.match.domains.joined(separator: ", ")) }
        if !rule.match.extensions.isEmpty { when.append(rule.match.extensions.joined(separator: ", ")) }
        if let min = rule.match.minBytes { when.append(String(localized: "over \(Format.bytes(min))")) }
        if let max = rule.match.maxBytes { when.append(String(localized: "under \(Format.bytes(max))")) }
        var then: [String] = []
        if let folder = rule.action.folderPath { then.append(URL(filePath: folder).lastPathComponent) }
        if let queue = rule.action.queueID { then.append(queues.first { $0.id == queue }?.name ?? queue) }
        if let connections = rule.action.connections { then.append(String(localized: "\(connections) connections")) }
        if let limit = rule.action.speedLimit { then.append(Format.speed(Double(limit))) }
        let condition = when.isEmpty ? String(localized: "Every download") : when.joined(separator: " · ")
        return then.isEmpty ? condition : condition + " → " + then.joined(separator: ", ")
    }
}
