import AppKit
import RocketCore
import RocketDesign
import SwiftUI

/// Rule list: first enabled match wins, drag to change order (FR-ORG-02).
struct RulesSettings: View {
    @Bindable var model: DownloadsModel
    @Binding var editing: DownloadRule?
    @State private var dropTarget: String?

    var body: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s4) {
            HStack(alignment: .top, spacing: RocketSpace.s5) {
                Text("Rules decide where new downloads go and how they run. The first matching rule wins; options you pick when adding a download always win.")
                    .font(.rocketBody)
                    .foregroundStyle(RocketColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    editing = DownloadRule(name: "")
                } label: {
                    HStack(spacing: RocketSpace.s2 + 1) {
                        Image(systemName: "plus").font(.system(size: 10.5, weight: .semibold))
                        Text("New Rule")
                    }
                }
                .buttonStyle(RocketButtonStyle(.secondary, size: .small))
            }
            if model.rules.isEmpty {
                VStack(spacing: RocketSpace.s3) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 15))
                        .foregroundStyle(RocketColor.textSecondary)
                        .frame(width: 36, height: 36)
                        .rocketCard(fill: RocketColor.control, radius: 10)
                    Text("No rules yet").font(.rocketHeadline).foregroundStyle(RocketColor.textPrimary)
                    Text("For example: put .iso files from releases.ubuntu.com in a Linux folder.")
                        .font(.rocketLabel)
                        .foregroundStyle(RocketColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, RocketSpace.s7)
                .rocketCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.rules.enumerated()), id: \.element.id) { index, rule in
                        RuleRow(rule: rule, model: model, edit: { editing = rule })
                            .overlay(alignment: .top) {
                                if dropTarget == rule.id { Rectangle().fill(RocketColor.accent).frame(height: 2) }
                            }
                            .draggable(rule.id)
                            .dropDestination(for: String.self) { ids, _ in
                                dropTarget = nil
                                guard let id = ids.first, let from = model.rules.firstIndex(where: { $0.id == id }), from != index else { return false }
                                Task { await model.moveRules(from: IndexSet(integer: from), to: index) }
                                return true
                            } isTargeted: { targeted in
                                if targeted { dropTarget = rule.id } else if dropTarget == rule.id { dropTarget = nil }
                            }
                    }
                }
                .padding(.bottom, -1)
                .clipShape(RoundedRectangle(cornerRadius: RocketRadius.card, style: .continuous))
                .rocketCard()
                Text("Drag rules to change their order.")
                    .font(.rocketCaption)
                    .foregroundStyle(RocketColor.textTertiary)
            }
        }
    }
}

private struct RuleRow: View {
    let rule: DownloadRule
    let model: DownloadsModel
    let edit: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: RocketSpace.s4) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(RocketColor.textTertiary)
                .opacity(hovering ? 1 : 0.4)
            Toggle(isOn: Binding(get: { rule.enabled }, set: { enabled in
                var updated = rule
                updated.enabled = enabled
                Task { await model.saveRule(updated) }
            })) { EmptyView() }
                .toggleStyle(.rocketCheckbox)
                .accessibilityLabel("Enabled")
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name.isEmpty ? String(localized: "Untitled rule") : rule.name)
                    .font(.rocketHeadline)
                    .foregroundStyle(rule.enabled ? RocketColor.textPrimary : RocketColor.textSecondary)
                Text(RuleText.summary(rule, queues: model.queues))
                    .font(.rocketLabel)
                    .foregroundStyle(RocketColor.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: RocketSpace.s1) {
                Button("Edit", systemImage: "pencil", action: edit)
                    .buttonStyle(.rocketIcon)
                    .rocketTooltip(String(localized: "Edit"))
                Button("Delete", systemImage: "trash") { Task { await model.deleteRule(rule.id) } }
                    .buttonStyle(IconButtonStyle(role: .destructive))
                    .rocketTooltip(String(localized: "Delete"))
            }
            .opacity(hovering ? 1 : 0)
        }
        .rocketFormRowChrome()
        .background(hovering ? RocketColor.hover : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(RocketMotion.fast, value: hovering)
        .onTapGesture { if (NSApp.currentEvent?.clickCount ?? 1) >= 2 { edit() } }
        .rocketContextMenu {
            [RocketMenuSection(items: [
                RocketMenuItem(String(localized: "Edit…"), symbol: "pencil", action: edit),
                RocketMenuItem(String(localized: "Delete"), symbol: "trash", role: .destructive) { Task { await model.deleteRule(rule.id) } },
            ])]
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Edit", edit)
        .accessibilityAction(named: "Delete") { Task { await model.deleteRule(rule.id) } }
    }
}

struct RuleEditor: View {
    @State private var rule: DownloadRule
    let queues: [DownloadQueue]
    let onSave: (DownloadRule) -> Void
    @Environment(\.rocketDismiss) private var dismiss
    @State private var choosingFolder = false

    init(rule: DownloadRule, queues: [DownloadQueue], onSave: @escaping (DownloadRule) -> Void) {
        _rule = State(initialValue: rule)
        self.queues = queues
        self.onSave = onSave
    }

    var body: some View {
        RocketModalLayout(rule.name.isEmpty ? String(localized: "New rule") : String(localized: "Edit rule")) {
            ScrollView {
                VStack(alignment: .leading, spacing: RocketSpace.s5) {
                    RocketFormSection {
                        RocketFormRow(String(localized: "Name")) {
                            TextField("Name", text: $rule.name, prompt: Text("Linux ISOs")).rocketField().frame(width: 220)
                        }
                    }
                    RocketFormSection(String(localized: "When")) {
                        RocketFormRow(String(localized: "Sites")) {
                            TextField("Sites", text: list(\.match.domains), prompt: Text(verbatim: "releases.ubuntu.com, github.com"))
                                .rocketField().frame(width: 220)
                        }
                        RocketFormRow(String(localized: "File types")) {
                            TextField("File types", text: list(\.match.extensions), prompt: Text(verbatim: "iso, dmg, zip"))
                                .rocketField(mono: true).frame(width: 220)
                        }
                        RocketFormRow(String(localized: "At least (MB)")) {
                            TextField("At least (MB)", text: megabytes(\.match.minBytes), prompt: Text("any size"))
                                .rocketField(mono: true).frame(width: 120)
                        }
                        RocketFormRow(String(localized: "At most (MB)")) {
                            TextField("At most (MB)", text: megabytes(\.match.maxBytes), prompt: Text("any size"))
                                .rocketField(mono: true).frame(width: 120)
                        }
                    }
                    RocketFormSection(String(localized: "Then")) {
                        RocketFormRow(String(localized: "Save to")) {
                            HStack(spacing: RocketSpace.s1) {
                                Button {
                                    choosingFolder = true
                                } label: {
                                    HStack(spacing: RocketSpace.s2 + 2) {
                                        Image(systemName: "folder").foregroundStyle(RocketColor.textSecondary)
                                        Text(rule.action.folderPath.map { URL(filePath: $0).lastPathComponent } ?? String(localized: "Default folder"))
                                    }
                                }
                                .buttonStyle(RocketButtonStyle(.secondary, size: .small))
                                if rule.action.folderPath != nil {
                                    Button("Clear", systemImage: "xmark") { rule.action.folderPath = nil }
                                        .buttonStyle(IconButtonStyle(size: 22))
                                        .rocketTooltip(String(localized: "Use the default folder"))
                                }
                            }
                        }
                        RocketFormRow(String(localized: "Queue")) {
                            RocketSelect(String(localized: "Queue"), selection: $rule.action.queueID,
                                         options: [RocketOption(String?.none, String(localized: "Default"))]
                                             + queues.filter { !$0.isDefault }.map { RocketOption(String?.some($0.id), $0.name) })
                                .fixedSize()
                        }
                        RocketFormRow(String(localized: "Connections")) {
                            RocketSelect(String(localized: "Connections"), selection: $rule.action.connections,
                                         options: [RocketOption(Int?.none, String(localized: "Default"))]
                                             + [1, 2, 4, 8, 12, 16].map { RocketOption(Int?.some($0), "\($0)") })
                                .fixedSize()
                        }
                        RocketFormRow(String(localized: "Speed limit")) {
                            RocketSelect(String(localized: "Speed limit"), selection: $rule.action.speedLimit,
                                         groups: SpeedLimitOptions.selectGroups(current: rule.action.speedLimit, unlimited: String(localized: "None")))
                                .fixedSize()
                        }
                    }
                }
                .padding(.horizontal, RocketSpace.s6)
                .padding(.bottom, RocketSpace.s5)
            }
            .frame(height: 400)
        } actions: {
            Button("Cancel") { dismiss() }
                .buttonStyle(.rocketGhost)
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                onSave(rule)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.rocketPrimary)
        }
        .frame(width: 500)
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
