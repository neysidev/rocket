import RocketCore
import RocketDesign
import SwiftUI

/// Paste links → see name, size, type, resumability and destination → start (FR-ADD-01/02/03).
public struct AddDownloadsSheet: View {
    @Bindable var model: AddDownloadsModel
    let onFinish: ([UUID]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choosingFolder = false
    @State private var starting = false

    public init(model: AddDownloadsModel, onFinish: @escaping ([UUID]) -> Void) {
        self.model = model
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s5) {
            Text(model.phase == .input ? "Add downloads" : "Review downloads")
                .font(.rocketTitle)
                .foregroundStyle(RocketColor.textPrimary)

            switch model.phase {
            case .input: input
            case .review: review
            }

            HStack {
                folderPicker
                if model.queues.count > 1 {
                    Picker("Queue", selection: $model.queueID) {
                        ForEach(model.queues) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .help("Queue")
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                primaryButton
            }
        }
        .padding(RocketSpace.s6)
        .frame(width: 600)
        .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.folder = url }
        }
    }

    // MARK: Input

    private var input: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s3) {
            TextEditor(text: $model.text)
                .font(.rocketMono)
                .scrollContentBackground(.hidden)
                .padding(RocketSpace.s3)
                .frame(height: 160)
                .background(RocketColor.control, in: RoundedRectangle(cornerRadius: RocketRadius.control))
                .overlay(alignment: .topLeading) {
                    if model.text.isEmpty {
                        Text("Paste one or more links, one per line")
                            .font(.rocketBody)
                            .foregroundStyle(RocketColor.textTertiary)
                            .padding(RocketSpace.s4)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityLabel("Links")
            Text(linkCountText)
                .font(.rocketLabel)
                .foregroundStyle(RocketColor.textSecondary)
            DisclosureGroup("Request options") { RequestOptions(model: model) }
                .font(.rocketLabel)
        }
    }

    private var linkCountText: String {
        switch model.links.count {
        case 0: String(localized: "No http or https links found yet.")
        case 1: String(localized: "1 link")
        default: String(localized: "\(model.links.count) links")
        }
    }

    // MARK: Review

    @ViewBuilder
    private var review: some View {
        let rows = VStack(spacing: RocketSpace.s3) {
            ForEach($model.candidates) { $candidate in
                CandidateRow(candidate: $candidate, conflict: model.conflict(for: candidate), model: model)
            }
        }
        // A few links fit as they are; longer lists scroll.
        if model.candidates.count <= 3 {
            rows
        } else {
            ScrollView { rows }.frame(height: 400)
        }
    }

    // MARK: Footer

    private var folderPicker: some View {
        Button {
            choosingFolder = true
        } label: {
            Label(model.folder.lastPathComponent, systemImage: "folder")
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .help(model.folder.path)
        .accessibilityLabel("Destination folder, \(model.folder.lastPathComponent)")
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch model.phase {
        case .input:
            Button("Next") { Task { await model.review() } }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(model.links.isEmpty)
        case .review:
            Button(model.startCount > 1 ? "Start \(model.startCount) Downloads" : "Start Download") {
                starting = true
                Task {
                    let ids = await model.start()
                    starting = false
                    if !model.candidates.contains(where: { $0.error != nil && $0.resolution != .skip }) || !ids.isEmpty {
                        onFinish(ids)
                        dismiss()
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(starting || model.candidates.contains(where: \.isProbing)
                || (model.startCount == 0 && !model.candidates.contains { $0.resolution == .showExisting && $0.info != nil }))
        }
    }
}

private struct CandidateRow: View {
    @Binding var candidate: AddDownloadsModel.Candidate
    let conflict: AddDownloadsModel.Conflict?
    let model: AddDownloadsModel

    var body: some View {
        HStack(alignment: .top, spacing: RocketSpace.s4) {
            FileTile(symbol: FileCategory(fileName: candidate.fileName, mimeType: candidate.info?.contentType).symbol)
            VStack(alignment: .leading, spacing: RocketSpace.s2) {
                TextField("File name", text: $candidate.fileName)
                    .textFieldStyle(.plain)
                    .font(.rocketHeadline)
                    .disabled(candidate.info == nil)
                Text(candidate.url.absoluteString)
                    .font(.rocketMono)
                    .foregroundStyle(RocketColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                details
                if let conflict, candidate.info != nil {
                    Picker(conflictText(conflict), selection: $candidate.resolution) {
                        ForEach(model.resolutions(for: conflict)) { Text($0.title).tag($0) }
                    }
                    .font(.rocketLabel)
                    .fixedSize()
                }
            }
        }
        .padding(RocketSpace.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RocketColor.card, in: RoundedRectangle(cornerRadius: RocketRadius.card))
    }

    @ViewBuilder
    private var details: some View {
        if let error = candidate.error {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(RocketColor.danger)
                .font(.rocketLabel)
        } else if let info = candidate.info {
            HStack(spacing: RocketSpace.s2) {
                Text(info.totalBytes.map(Format.bytes) ?? String(localized: "Size unknown"))
                Text("·")
                Text(info.contentType ?? FileCategory(fileName: candidate.fileName).title)
                Text("·")
                if info.acceptsRanges {
                    Text("Resumable")
                } else {
                    Text("Not resumable, single connection")
                        .foregroundStyle(RocketColor.warning)
                }
            }
            .font(.rocketLabel)
            .foregroundStyle(RocketColor.textSecondary)
            .monospacedDigit()
        } else {
            HStack(spacing: RocketSpace.s2) {
                ProgressView().controlSize(.small)
                Text("Checking link…")
            }
            .font(.rocketLabel)
            .foregroundStyle(RocketColor.textSecondary)
        }
    }

    private func conflictText(_ conflict: AddDownloadsModel.Conflict) -> String {
        switch conflict {
        case .inList: String(localized: "Already in your downloads:")
        case .fileExists: String(localized: "A file with this name exists:")
        }
    }
}

/// Headers, referrer, user agent, cookies and Basic auth for sites that need them (FR-ADD-04).
private struct RequestOptions: View {
    @Bindable var model: AddDownloadsModel

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: RocketSpace.s3, verticalSpacing: RocketSpace.s2) {
            field("Referrer", text: optional(\.referrer), prompt: "https://example.com/page")
            field("User agent", text: optional(\.userAgent), prompt: "Default")
            field("Cookies", text: optional(\.cookies), prompt: "name=value; other=value")
            GridRow {
                Text("Sign in").gridColumnAlignment(.trailing)
                HStack {
                    TextField("User name", text: optional(\.username))
                    SecureField("Password", text: optional(\.password))
                }
            }
            GridRow(alignment: .top) {
                Text("Headers").gridColumnAlignment(.trailing)
                TextField("Name: value, one per line", text: $model.headerText, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.rocketMono)
            }
        }
        .textFieldStyle(.roundedBorder)
        .font(.rocketBody)
        .padding(.top, RocketSpace.s2)
        Text("Cookies and passwords are kept in your Keychain and only sent to the link's own site.")
            .font(.rocketCaption)
            .foregroundStyle(RocketColor.textSecondary)
    }

    private func field(_ label: LocalizedStringKey, text: Binding<String>, prompt: LocalizedStringKey) -> some View {
        GridRow {
            Text(label).gridColumnAlignment(.trailing)
            TextField(label, text: text, prompt: Text(prompt))
        }
    }

    private func optional(_ keyPath: WritableKeyPath<RequestContext, String?>) -> Binding<String> {
        Binding { model.context[keyPath: keyPath] ?? "" } set: { model.context[keyPath: keyPath] = $0 }
    }
}

/// Paste a fresh link for a download whose link expired (FR-ENG-09).
public struct RefreshLinkSheet: View {
    let download: Download
    let onRefresh: (URL) async -> String?
    @State private var text: String
    @State private var error: String?
    @State private var working = false
    @Environment(\.dismiss) private var dismiss

    public init(download: Download, onRefresh: @escaping (URL) async -> String?) {
        self.download = download
        self.onRefresh = onRefresh
        let clipboard = LinkExtractor.urls(in: NSPasteboard.general.string(forType: .string) ?? "").first
        _text = State(initialValue: clipboard?.absoluteString ?? "")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: RocketSpace.s4) {
            Text("Refresh link").font(.rocketTitle)
            Text("Paste a new link to \(download.fileName). Rocket keeps the \(Format.bytes(download.receivedBytes)) already downloaded if it is the same file.")
                .font(.rocketBody)
                .foregroundStyle(RocketColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("https://", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.rocketMono)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle").font(.rocketLabel).foregroundStyle(RocketColor.danger)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Refresh and Resume") {
                    guard let url = LinkExtractor.urls(in: text).first else { return error = String(localized: "That is not an http or https link.") }
                    working = true
                    Task {
                        error = await onRefresh(url)
                        working = false
                        if error == nil { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(working || text.isEmpty)
            }
        }
        .padding(RocketSpace.s6)
        .frame(width: 480)
    }
}
